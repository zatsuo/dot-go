extends Control
## dot-Godough 立体: ドット絵 (正面の絵) から立体を作って、向きを変えた絵を直す・部品を分ける・ポーズで確かめる。これだけのアプリ。
##  できたものは ドット絵モデル (.dotmodel.json) として保存し、dot-Godough モーション (..\dot-godough-motion) で動きをつける。
##  立体そのものは scripts/solid.gd (dot-godough・モーションと同じもの。Sync.bat で写す)。
## 起動: Run.bat。確かめ: Run.bat -- --selftest <フォルダ> (tests/selftest.gd)

const XP := preload("res://scripts/xp.gd")
const DIR_NAMES := ["正面", "左ななめ前", "左", "左ななめ後ろ", "後ろ", "右ななめ後ろ", "右", "右ななめ前"]
const TOOLS := ["えんぴつ", "消しゴム", "バケツ", "線", "四角 (枠)", "四角 (ぬり)", "スポイト"]
const POSE_NAMES := ["立ち", "歩き 1", "歩き 2", "走り", "ばんざい", "T の字", "すわる", "おじぎ", "手をあげる"]
const PAINT_PARTS := [1, 2, 3, 4, 5, 6]
const MARGIN := Vector3i(4, 3, 2)    ## 紙の余白: 左右・上・下 (画素)
const SETTINGS := [                  ## [名前, ラベル, 最小, 最大, きざみ, 説明]
	["front_reach", "正面の顔を使う角度", 45, 85, 2.5, "頭が 正面の絵 (ずらした顔) を使いつづける角度"],
	["face_min", "横顔の幅", 0.3, 0.9, 0.05, "真横を向いたときの 顔の幅 (正面の何割か)"],
	["skin_tol", "肌とみなす色の広さ", 0.0, 0.6, 0.05, "顔の真ん中の色に どれだけ近い色までを肌にするか"],
	["wrap", "絵の回りこみ", 0.0, 1.0, 0.05, "向きがずれた分の どれだけ 絵をずらすか"],
	["shoulder_up", "肩の高さ", 0.0, 3.0, 0.5, "腕のつけ根を 腕の画素の いちばん上の行より 何行上に置くか"],
	["waist", "腰の関節の高さ", 0.0, 0.8, 0.05, "体の 上から何割の所で 胸と腰に分けるか (0 = 分けない)"],
	["leg_hidden", "脚のつけ根の高さ", 0.0, 0.6, 0.05, "服にかくれた脚の長さ (首から脚までの何割か)"],
	["arm_min", "はなした腕の太さ", 0.0, 2.5, 0.25, "体から はなした腕の半径 (画素)"],
	["k_head", "奥行き: 頭", 0.4, 1.6, 0.05, "横の絵が無いとき: 奥行き ÷ 横幅"],
	["k_body", "奥行き: 体", 0.3, 1.4, 0.05, ""],
	["k_leg", "奥行き: 脚", 0.6, 2.4, 0.05, ""],
	["paint_reach", "描いた色が出る範囲 (±°)", 0, 180, 5, "描いた向きから 何度はなれた向きまで出すか (180 = どの向きにも)"],
	["air_thick", "描いた画素の厚み", 0.5, 4.0, 0.5, "描いた向きの奥と手前へ のびる長さ (画素)。これから描く分に効く"],
]

var solid: DotSolid
var model_name := ""
var file_path := ""
var yaw := 0.0
var mode := 0                    ## 0 = 描く、1 = 部品、2 = ポーズ、3 = 絵から作る
var tool := 0
var pen := Color("#2a2030")
var pen_size := 1
var pen_mirror := false
var pen_perfect := true
var decide := false              ## 描いたものを「その向きの絵」にする (45° ごと。立体を作り直す)
var part_sel := 1
var pose := {}                   ## 確かめ用のポーズ (保存しない)
var sheet: Image                 ## 読んだ絵 (背景は透明にしてある)
var sheet_rect := Rect2i()       ## 選んだ 1 体
var _sheet_a := Vector2.ZERO

var pix: DotView                 ## いまの向きの絵 (ここに描く)
var pix2: DotView                ## 90° 回した絵 (見るだけ)
var sheet_view: DotView
var _w := {}
var _syncing := false
var _hint: Label
var _tabs: TabContainer
var _prev: TextureRect
var _pal_box: HFlowContainer
var _dialog: FileDialog
var _undo: Array = []
var _redo: Array = []
var _img: Image
var _painting := 0
var _last := Vector2.ZERO
var _hover := Vector2(-99, -99)
var _pp_last := Vector2i(-999, -999)
var _pp_pending = null
var _shape := {}
var _sdrag := 0
var _sdrag_last := Vector2.ZERO
var _yaw_drag := false
var _dirty_prev := true
var _prev_cache := {}
var _selftest: RefCounted


func _ready() -> void:
	theme = XP.make_theme()
	_build_ui()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--selftest":
		_selftest = load("res://tests/selftest.gd").new()
		_selftest.run(self, args[1])
	elif args.size() >= 1:
		open_any(args[0])
	await get_tree().process_frame
	refresh(true)


# --- 立体を作る ---------------------------------------------------------------------------- #

static func _opaque(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5


## 絵を読む。背景が塗ってあれば、左上の色を「何も無い」とする
func load_sheet(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_hint.text = "読めませんでした: " + path
		return false
	img.convert(Image.FORMAT_RGBA8)
	var bg := img.get_pixel(0, 0)
	if bg.a > 0.5:
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y) == bg:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	sheet = img
	sheet_rect = img.get_used_rect() if (img.get_width() <= 64 and img.get_height() <= 64) else Rect2i()
	sheet_view.set_image(img)
	sheet_view.fit.call_deferred()
	if model_name == "":
		model_name = path.get_file().get_basename()
	_tabs.current_tab = 3
	_hint.text = "絵の上の 1 体をクリックして選び、左の「正面にして 立体を作る」を押してください"
	return true


## 絵の p にある 1 体 (つながった画素の かたまり) を選ぶ
func pick_island(p: Vector2i) -> Rect2i:
	if sheet == null or not _opaque(sheet, p.x, p.y):
		return Rect2i()
	var seen := {p: true}
	var todo := [p]
	var r := Rect2i(p, Vector2i.ONE)
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		r = r.expand(c).expand(c + Vector2i.ONE)
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q := c + Vector2i(dx, dy)
				if not seen.has(q) and _opaque(sheet, q.x, q.y):
					seen[q] = true
					todo.append(q)
	sheet_rect = r
	sheet_view.queue_redraw()
	return r


## 四角で囲んで選ぶ (中身のある所まで ちぢめる)
func set_sheet_rect(r: Rect2i) -> Rect2i:
	if sheet == null:
		return Rect2i()
	r = r.intersection(Rect2i(Vector2i.ZERO, sheet.get_size()))
	var used := sheet.get_region(r).get_used_rect() if (r.size.x > 0 and r.size.y > 0) else Rect2i()
	sheet_rect = Rect2i(r.position + used.position, used.size) if used.size.x > 0 else Rect2i()
	sheet_view.queue_redraw()
	return sheet_rect


## 選んだ 1 体を、向き key (0 = 正面、90 = 右向き、270 = 左向き、180 = 後ろ、45… = ななめ) の絵にする。正面なら 立体を作り直す
func use_cell(key: int) -> bool:
	if sheet == null or sheet_rect.size.x <= 0:
		_hint.text = "先に、絵の上の 1 体をクリックして選んでください"
		return false
	var used := sheet.get_region(sheet_rect).get_used_rect()
	var r := Rect2i(sheet_rect.position + used.position, used.size)
	if r.size.x <= 0:
		return false
	if key != 0 and solid == null:
		_hint.text = "先に「正面にして 立体を作る」を押してください"
		return false
	push_undo()
	if key == 0:
		var w := r.size.x + MARGIN.x * 2
		if w % 2 == 1:
			w += 1
		var h := r.size.y + MARGIN.y + MARGIN.z
		var im := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		im.blit_rect(sheet, r, Vector2i((w - r.size.x) / 2, h - MARGIN.z - r.size.y))
		solid = DotSolid.new()
		solid.set_front(im)
		pose = {}
	else:
		var im2 := Image.create_empty(solid.w, solid.h, false, Image.FORMAT_RGBA8)
		im2.blit_rect(sheet, r, Vector2i((solid.w - r.size.x) / 2, solid.h - MARGIN.z - r.size.y))
		solid.set_pic(key, im2)
	solid.ensure()
	yaw = float(key)
	_sync("yaw", yaw)
	_after_model_change()
	_tabs.current_tab = 0
	_hint.text = "%s の絵にしました (%d × %d)" % [DIR_NAMES[key / 45], r.size.x, r.size.y]
	return true


func forget_pic(key: int) -> void:
	if solid == null or not solid.pics.has(key) or key == 0:
		return
	push_undo()
	solid.forget(key)
	_after_model_change()


func _after_model_change() -> void:
	_title()
	_sync_settings()
	_sync_palette()
	refresh(true)


# --- 開く・保存 ---------------------------------------------------------------------------- #

func to_doc() -> Dictionary:
	return {"app": "dot-godough", "kind": "model", "version": 1, "name": model_name, "solid": solid.to_doc() if solid != null else {}}


func save_doc(path: String) -> bool:
	if solid == null:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_doc(), " "))
	file_path = path
	_title()
	return true


## モデル (.dotmodel.json)・dot-godough のキャラ (.dotg.json)・絵 (.png) を開く
func open_any(path: String) -> bool:
	if path.to_lower().ends_with(".png"):
		return load_sheet(path)
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (d.get("solid", null) is Dictionary) or d.solid.is_empty():
		_hint.text = "立体の入っていないファイルです: " + path.get_file()
		return false
	var s := DotSolid.from_doc(d.solid)
	if s == null:
		return false
	solid = s
	solid.ensure()
	model_name = str(d.get("name", path.get_file().get_basename().get_basename()))
	file_path = path if path.ends_with(".dotmodel.json") else ""
	pose = {}
	_undo.clear()
	_redo.clear()
	_tabs.current_tab = 0
	_after_model_change()
	return true


func _title() -> void:
	get_window().title = "dot-Godough 立体" + ("" if model_name == "" else " — " + model_name) + ("" if file_path == "" else " (" + file_path.get_file() + ")")


func push_undo() -> void:
	_undo.append({"solid": solid.to_doc() if solid != null else {}, "pose": pose.duplicate()})
	if _undo.size() > 60:
		_undo.pop_front()
	_redo.clear()


func _restore(s: Dictionary) -> void:
	solid = DotSolid.from_doc(s.solid) if not s.solid.is_empty() else null
	pose = s.pose
	if solid != null:
		solid.ensure()
	_after_model_change()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append({"solid": solid.to_doc() if solid != null else {}, "pose": pose.duplicate()})
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append({"solid": solid.to_doc() if solid != null else {}, "pose": pose.duplicate()})
	_restore(_redo.pop_back())


# --- 描く --------------------------------------------------------------------------------- #

func render(y: float) -> Image:
	if solid == null:
		return Image.create_empty(24, 36, false, Image.FORMAT_RGBA8)
	solid.pose = pose if mode == 2 else {}
	solid.root = Vector3.ZERO
	return solid.render(y)


func refresh(fit := false) -> void:
	if pix == null:
		return
	_img = render(yaw)
	pix.set_image(_img)
	pix2.set_image(render(fposmod(yaw + 90.0, 360.0)))
	if fit:
		pix.fit.call_deferred()
		pix2.fit.call_deferred()
	pix.queue_redraw()
	_dirty_prev = true
	_prev_cache.clear()
	if _w.has("info") and solid != null:
		var key := DotSolid.key_of(yaw)
		var kind := "あいだの向き (立体から描いた絵)" if key < 0 else ("決めた絵" if solid.is_drawn(key) else "推定の絵")
		if mode == 2 and not pose.is_empty():
			kind = "ポーズ中 (立体から描いた絵。保存されません)"
		var na: int = solid.adds.filter(func(a): return a != null and Color(a[4]).a > 0.5).size()
		var nc: int = solid.adds.filter(func(a): return a != null and Color(a[4]).a < 0.5).size()
		_w["info"].text = "向き %d° — %s　　紙 %d × %d　　置いた画素 %d・けずった画素 %d　　決めた絵: %s" % [int(yaw), kind, solid.w, solid.h, na, nc,
				", ".join(solid.pics.keys().map(func(k): return DIR_NAMES[int(k) / 45]))]


func set_yaw(y: float) -> void:
	yaw = fposmod(y, 360.0)
	_sync("yaw", yaw)
	refresh()


func set_mode(m: int) -> void:
	mode = m
	refresh()


static func _bres(a: Vector2i, b: Vector2i) -> Array:
	var out := []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


func _brush(c: Vector2i) -> Array:
	if pen_size <= 1:
		return [c]
	var out := []
	var half := pen_size * 0.5
	var ctr := Vector2(c) + (Vector2(0.5, 0.5) if pen_size % 2 == 1 else Vector2.ZERO)
	for y in range(int(floor(ctr.y - half)), int(ceil(ctr.y + half)) + 1):
		for x in range(int(floor(ctr.x - half)), int(ceil(ctr.x + half)) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(ctr) <= half:
				out.append(Vector2i(x, y))
	return out


## 画素をまとめて置く (col.a = 0 なら消す = けずる)。「その向きの絵を決める」のときは、その向きの絵そのものを直す
func plot(cells: Array, col: Color) -> int:
	if solid == null:
		return 0
	var key := DotSolid.key_of(yaw)
	var dec: bool = decide and key >= 0
	var changed := 0
	var seen := {}
	for cell in cells:
		for mi in (2 if pen_mirror else 1):
			var q: Vector2i = cell if mi == 0 else Vector2i(solid.w - 1 - cell.x, cell.y)
			if seen.has(q):
				continue
			seen[q] = true
			if (solid.set_px(key, q.x, q.y, col) if dec else solid.paint_surface(yaw, q.x, q.y, col)):
				changed += 1
	if changed > 0:
		refresh()
	return changed


func fill(cell: Vector2i, col: Color) -> int:
	var img := _img
	if img == null or cell.x < 0 or cell.y < 0 or cell.x >= img.get_width() or cell.y >= img.get_height():
		return 0
	var c0 := img.get_pixel(cell.x, cell.y)
	var open0 := c0.a < 0.5
	if (not open0 and col.a > 0.5 and c0.is_equal_approx(col)) or (open0 and col.a < 0.5):
		return 0
	var cells := []
	var seen := {cell: true}
	var st := [cell]
	while not st.is_empty():
		var q: Vector2i = st.pop_back()
		cells.append(q)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var r: Vector2i = q + d
			if r.x < 0 or r.y < 0 or r.x >= img.get_width() or r.y >= img.get_height():
				if open0:
					_hint.text = "バケツ: 透明な所が 絵のはしまで つながっています (線で囲んでから塗ってください)"
					return 0
				continue
			if seen.has(r):
				continue
			var cr := img.get_pixel(r.x, r.y)
			if (open0 and cr.a < 0.5) or (not open0 and cr.a > 0.5 and cr.is_equal_approx(c0)):
				seen[r] = true
				st.append(r)
	return plot(cells, col)


func _shape_cells(a: Vector2i, b: Vector2i) -> Array:
	if tool == 3:
		var out := []
		for c in _bres(a, b):
			out.append_array(_brush(c))
		return out
	var cells := []
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			if tool == 5 or x == a.x or x == b.x or y == a.y or y == b.y:
				cells.append(Vector2i(x, y))
	return cells


func _col(erase: bool) -> Color:
	return Color(0, 0, 0, 0) if (erase or tool == 1) else Color(pen, 1.0)


func _pp_feed(cell: Vector2i, col: Color) -> void:
	if cell == _pp_last or (_pp_pending != null and cell == _pp_pending):
		return
	if _pp_pending != null:
		var pd: Vector2i = _pp_pending
		var corner: bool = (pd.x == _pp_last.x or pd.y == _pp_last.y) and (pd.x == cell.x or pd.y == cell.y) and _pp_last.x != cell.x and _pp_last.y != cell.y
		if not corner:
			plot([pd], col)
			_pp_last = pd
	_pp_pending = cell


func pick_color(px: Vector2) -> bool:
	var x := int(floor(px.x))
	var y := int(floor(px.y))
	if _img == null or x < 0 or y < 0 or x >= _img.get_width() or y >= _img.get_height() or _img.get_pixel(x, y).a < 0.5:
		return false
	set_pen(_img.get_pixel(x, y))
	return true


func set_pen(c: Color) -> void:
	pen = Color(c.r, c.g, c.b)
	_sync("pen", pen)
	_hint.text = "色: #" + pen.to_html(false)


func set_tool(i: int) -> void:
	tool = clampi(i, 0, TOOLS.size() - 1)
	for k in TOOLS.size():
		if _w.has("tool_%d" % k):
			_w["tool_%d" % k].set_pressed_no_signal(k == tool)


func _press(px: Vector2, button: int) -> void:
	if solid == null or (button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT):
		return
	var cell := Vector2i(px.floor())
	var erase := button == MOUSE_BUTTON_RIGHT
	if mode == 2:
		_pose_press(px, button)
		return
	if mode == 1:
		# 部品を塗る (正面の絵の上だけ)
		if DotSolid.key_of(yaw) != 0:
			_hint.text = "部品は 正面の絵の上で塗ります (向きを正面に)"
			return
		push_undo()
		_painting = button
		if solid.set_part(cell.x, cell.y, part_sel):
			refresh()
		return
	if mode != 0:
		_hint.text = "描くのは「描く」タブで (いまのタブでは 絵は変わりません)"
		return
	if Input.is_key_pressed(KEY_ALT) or tool == 6:
		pick_color(px)
		return
	push_undo()
	if tool == 2:
		var n := fill(cell, _col(erase))
		_hint.text = "バケツ: %d 画素" % n
		return
	_painting = button
	_last = px
	if tool >= 3:
		_shape = {"a": cell, "b": cell, "erase": erase}
		return
	if pen_size <= 1 and pen_perfect:
		plot([cell], _col(erase))
		_pp_last = cell
		_pp_pending = null
	else:
		plot(_brush(cell), _col(erase))


func _drag(px: Vector2, rel: Vector2, button: int) -> void:
	_hover = px
	if mode == 2:
		_pose_drag(px, rel, button)
		return
	if _painting == 0 or solid == null:
		return
	var cell := Vector2i(px.floor())
	var erase := _painting == MOUSE_BUTTON_RIGHT
	if mode == 1:
		var ch := false
		for c in _bres(Vector2i(_last.floor()) if _last != Vector2.ZERO else cell, cell):
			if solid.set_part(c.x, c.y, part_sel):
				ch = true
		_last = px
		if ch:
			refresh()
		return
	if not _shape.is_empty():
		_shape.b = cell
		pix.queue_redraw()
		return
	if pen_size <= 1 and pen_perfect:
		for c in _bres(_pp_last if _pp_pending == null else _pp_pending, cell):
			_pp_feed(c, _col(erase))
		pix.queue_redraw()
	else:
		var cells := []
		for c in _bres(Vector2i(_last.floor()), cell):
			cells.append_array(_brush(c))
		plot(cells, _col(erase))
	_last = px


func _release(_px: Vector2, _button: int) -> void:
	if mode == 2:
		if _yaw_drag:
			_yaw_drag = false
			set_yaw(roundf(yaw / 45.0) * 45.0)
		_sdrag = 0
		pix.queue_redraw()
		return
	if _painting != 0 and mode == 0:
		if not _shape.is_empty():
			plot(_shape_cells(_shape.a, _shape.b), _col(_shape.erase))
			_shape = {}
		if _pp_pending != null:
			plot([_pp_pending], _col(_painting == MOUSE_BUTTON_RIGHT))
			_pp_pending = null
		_pp_last = Vector2i(-999, -999)
	_painting = 0
	_last = Vector2.ZERO
	pix.queue_redraw()


# --- ポーズ (確かめ用) --------------------------------------------------------------------- #

func _pick_handle(px: Vector2) -> int:
	var best := 2.6
	var part := 0
	solid.pose = pose
	solid.root = Vector3.ZERO
	for hd in solid.handles(yaw):
		var d: float = hd.tip.distance_to(px)
		if d < best:
			best = d
			part = hd.part
	return part


func _pose_press(px: Vector2, button: int) -> void:
	var part := _pick_handle(px)
	if button == MOUSE_BUTTON_RIGHT:
		if part != 0:
			push_undo()
			pose.erase(part)
			if part in DotSolid.IK_PARTS:
				pose.erase(DotSolid.PARENT[part])
			refresh()
		return
	if part == 0:
		_yaw_drag = true
		return
	push_undo()
	_sdrag = part
	_sdrag_last = px


func _pose_drag(px: Vector2, rel: Vector2, _button: int) -> void:
	if _yaw_drag:
		set_yaw(yaw + rel.x * pix.zoom * 0.6)
		return
	if _sdrag == 0:
		return
	solid.pose = pose
	solid.root = Vector3.ZERO
	if _sdrag in DotSolid.IK_PARTS and not Input.is_key_pressed(KEY_SHIFT):
		solid.drag_ik(_sdrag, yaw, px)
	else:
		solid.drag_part(_sdrag, yaw, _sdrag_last, px)
	_sdrag_last = px
	refresh()


func apply_preset(name: String) -> void:
	if solid == null:
		return
	push_undo()
	pose = solid.preset(name).pose.duplicate()
	refresh()


# --- 書き出し ------------------------------------------------------------------------------ #

func export_png(path: String) -> bool:
	return solid != null and render(yaw).save_png(path) == OK


## 8 方向を横に並べた絵 (いまのポーズ)
func export_sheet(path: String) -> bool:
	if solid == null:
		return false
	var im := Image.create_empty(solid.w * 8, solid.h, false, Image.FORMAT_RGBA8)
	for d in 8:
		im.blit_rect(render(d * 45.0), Rect2i(0, 0, solid.w, solid.h), Vector2i(d * solid.w, 0))
	return im.save_png(path) == OK


## 保存してから、モーションのアプリで開く
func open_in_motion() -> void:
	if solid == null:
		return
	if file_path == "":
		_hint.text = "先に保存してください (モーションは 保存したファイルを開きます)"
		return
	save_doc(file_path)
	var proj := ProjectSettings.globalize_path("res://").path_join("../dot-godough-motion").simplify_path()
	if not DirAccess.dir_exists_absolute(proj):
		_hint.text = "モーションのフォルダが見つかりません: " + proj
		return
	OS.create_process(OS.get_executable_path(), ["--path", proj, "--", file_path])
	_hint.text = "モーションで開きました: " + file_path.get_file()


func _ask(mode2: int, filters: PackedStringArray, name: String, cb: Callable) -> void:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = mode2
	_dialog.filters = filters
	_dialog.current_file = name
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(cb)
	add_child(_dialog)
	_dialog.popup_centered(Vector2i(820, 560))


func _save(as_new := false) -> void:
	if solid == null:
		_hint.text = "まだ立体がありません"
		return
	if file_path != "" and not as_new:
		_hint.text = ("保存しました: " + file_path) if save_doc(file_path) else "保存できませんでした"
		return
	_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.dotmodel.json ; ドット絵モデル"], (model_name if model_name != "" else "キャラ") + ".dotmodel.json", func(p: String):
		if not p.ends_with(".dotmodel.json"):
			p += ".dotmodel.json"
		model_name = p.get_file().trim_suffix(".dotmodel.json")
		_hint.text = ("保存しました: " + p) if save_doc(p) else "保存できませんでした")


# --- 画面 --------------------------------------------------------------------------------- #

func _process(_dt: float) -> void:
	if solid == null or not _dirty_prev or _painting != 0 or _sdrag != 0:
		return
	for d in 8:
		if not _prev_cache.has(d):
			_prev_cache[d] = render(d * 45.0)
			return
	var im := Image.create_empty(solid.w * 4, solid.h * 2, false, Image.FORMAT_RGBA8)
	im.fill(Color("#8a8f9a"))
	for d in 8:
		im.blend_rect(_prev_cache[d], Rect2i(0, 0, solid.w, solid.h), Vector2i((d % 4) * solid.w, (d / 4) * solid.h))
	_prev.texture = ImageTexture.create_from_image(im)
	_prev.custom_minimum_size = Vector2(284, 284.0 * (solid.h * 2.0) / (solid.w * 4.0))
	_dirty_prev = false


func _overlay(v: DotView) -> void:
	if solid == null:
		v.draw_string(get_theme_default_font(), Vector2(12, 24), "「絵を開く」で ドット絵 (PNG) を開くか、「開く」で モデルを開いてください", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
		return
	if mode == 1 and DotSolid.key_of(yaw) == 0:
		for y in solid.h:
			for x in solid.w:
				var p: int = solid.part_at(x, y)
				if p > 0 and solid.pics[0].get_pixel(x, y).a > 0.5:
					v.draw_rect(Rect2(v.to_screen(Vector2(x, y)), Vector2(v.zoom, v.zoom)), Color(Color(DotSolid.PART_COLORS[p]), 0.6))
	elif mode == 2:
		solid.pose = pose
		solid.root = Vector3.ZERO
		for hd in solid.handles(yaw):
			var a: Vector2 = v.to_screen(hd.pivot)
			var b: Vector2 = v.to_screen(hd.tip)
			v.draw_line(a, b, Color(0, 0, 0, 0.3), 1.0)
			v.draw_circle(a, 2.5, Color(0, 0, 0, 0.6))
			if hd.part == _sdrag:
				v.draw_circle(b, 8.0, Color(1, 1, 1, 0.95))
			v.draw_circle(b, 5.5, Color(0, 0, 0, 0.75))
			v.draw_circle(b, 4.5, Color(DotSolid.PART_COLORS[hd.part]))
	elif mode == 0:
		var pc := Color(pen, 0.85) if not (_shape.get("erase", false) or tool == 1) else Color(1, 0.3, 0.3, 0.6)
		if not _shape.is_empty():
			for c in _shape_cells(_shape.a, _shape.b):
				v.draw_rect(Rect2(v.to_screen(Vector2(c)), Vector2(v.zoom, v.zoom)), pc)
		if _pp_pending != null:
			v.draw_rect(Rect2(v.to_screen(Vector2(_pp_pending)), Vector2(v.zoom, v.zoom)), pc)
		if _hover.x > -50:
			v.draw_rect(Rect2(v.to_screen(_hover.floor()), Vector2(v.zoom, v.zoom)), Color(1, 1, 1, 0.9), false, 1.0)


func _sheet_overlay(v: DotView) -> void:
	if sheet_rect.size.x > 0:
		v.draw_rect(Rect2(v.to_screen(Vector2(sheet_rect.position)), Vector2(sheet_rect.size) * v.zoom), Color(1, 0.85, 0.2), false, 2.0)


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var ctrl: bool = e.ctrl_pressed
	if ctrl:
		match e.keycode:
			KEY_Z:
				undo()
			KEY_Y:
				redo()
			KEY_S:
				_save()
			_:
				return
	else:
		match e.keycode:
			KEY_B:
				set_tool(0)
			KEY_E:
				set_tool(1)
			KEY_G:
				set_tool(2)
			KEY_L:
				set_tool(3)
			KEY_U:
				set_tool(5 if e.shift_pressed else 4)
			KEY_I:
				set_tool(6)
			KEY_LEFT:
				set_yaw(roundf(yaw / 45.0) * 45.0 - 45.0)
			KEY_RIGHT:
				set_yaw(roundf(yaw / 45.0) * 45.0 + 45.0)
			_:
				return
	accept_event()


func _sync(key: String, value) -> void:
	if not _w.has(key):
		return
	_syncing = true
	var c = _w[key]
	if c is Range:
		c.value = value
	elif c is ColorPickerButton:
		c.color = value
	elif c is BaseButton:
		c.button_pressed = value
	_syncing = false


func _sync_settings() -> void:
	if solid == null:
		return
	for it in SETTINGS:
		_sync("s_" + it[0], solid.get(it[0]))
	_sync("s_face_layer", solid.face_layer)
	_sync("s_joints", solid.joints)


## 絵に使われている色を パレットに並べる
func _sync_palette() -> void:
	if _pal_box == null:
		return
	for c in _pal_box.get_children():
		_pal_box.remove_child(c)
		c.queue_free()
	if solid == null:
		return
	var cnt := {}
	for k in solid.pics:
		var im: Image = solid.pics[k]
		for y in im.get_height():
			for x in im.get_width():
				var px := im.get_pixel(x, y)
				if px.a > 0.5:
					cnt[px.to_rgba32()] = cnt.get(px.to_rgba32(), 0) + 1
	var ks: Array = cnt.keys()
	ks.sort_custom(func(a, b): return cnt[a] > cnt[b])
	for k in ks.slice(0, 32):
		var col := Color.hex(k)
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "#" + col.to_html(false)
		b.add_theme_stylebox_override("normal", XP.flat(col, Color.BLACK, 1))
		b.add_theme_stylebox_override("hover", XP.flat(col, Color.WHITE, 1))
		b.add_theme_stylebox_override("pressed", XP.flat(col, Color.WHITE, 1))
		b.pressed.connect(func(): set_pen(col))
		_pal_box.add_child(b)


func _head(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", XP.GROUP_TITLE)
	l.add_theme_font_override("font", XP.font(true))
	parent.add_child(l)


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("#555555"))
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _flow(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 3)
	parent.add_child(f)
	return f


func _check(parent: Control, key: String, text: String, cb: Callable, tip := "") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool):
		if not _syncing:
			cb.call(on))
	parent.add_child(c)
	_w[key] = c
	return c


func _slider(parent: Control, key: String, label: String, lo: float, hi: float, step: float, cb: Callable, tip := "") -> HSlider:
	var h := HBoxContainer.new()
	h.tooltip_text = tip
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 132
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	var val := Label.new()
	val.custom_minimum_size.x = 34
	s.value_changed.connect(func(x: float):
		val.text = str(snappedf(x, 0.01))
		if not _syncing:
			cb.call(x))
	h.add_child(s)
	h.add_child(val)
	parent.add_child(h)
	_w[key] = s
	return s


func _tab(name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	m.add_child(v)
	_tabs.add_child(sc)
	return v


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = XP.FACE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	add_child(root)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_button(bar, "絵を開く", func(): _ask(FileDialog.FILE_MODE_OPEN_FILE, ["*.png ; ドット絵"], "", func(p: String): load_sheet(p)), "ドット絵 (1 体だけの絵でも、何体も並んだ表でも) を開いて、立体のもとにする")
	_button(bar, "開く", func(): _ask(FileDialog.FILE_MODE_OPEN_FILE, ["*.dotmodel.json, *.dotg.json ; ドット絵モデル / dot-Godough のキャラ"], "", func(p: String): open_any(p)))
	_button(bar, "保存", func(): _save(), "Ctrl+S")
	_button(bar, "名前をつけて保存", func(): _save(true))
	bar.add_child(VSeparator.new())
	_button(bar, "元に戻す", undo, "Ctrl+Z")
	_button(bar, "やり直す", redo, "Ctrl+Y")
	bar.add_child(VSeparator.new())
	_button(bar, "全体を表示", func():
		pix.fit()
		pix2.fit())
	bar.add_child(VSeparator.new())
	_button(bar, "モーションで開く", open_in_motion, "保存して、dot-Godough モーション (動きをつけるアプリ) で開く")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.x = 330
	cols.add_child(_tabs)
	_tabs.tab_changed.connect(func(i: int):
		set_mode(i)
		if sheet_view != null:
			sheet_view.visible = i == 3
			pix.get_parent().visible = i != 3)

	# 描く
	var dv := _tab("描く")
	_head(dv, "道具")
	var tf := _flow(dv)
	var tkeys := ["B", "E", "G", "L", "U", "Shift+U", "I"]
	for ti in TOOLS.size():
		var tb := _button(tf, TOOLS[ti], func(): set_tool(ti), tkeys[ti])
		tb.toggle_mode = true
		tb.button_pressed = ti == 0
		_w["tool_%d" % ti] = tb
	_note(dv, "右ボタンは どの道具でも「消す」(立体もけずれる)。Alt + クリックで色を拾う。")
	_slider(dv, "pen_size", "太さ (画素)", 1, 8, 1, func(x: float): pen_size = int(x))
	_sync("pen_size", 1)
	_check(dv, "perfect", "かどの よぶんな画素を置かない (太さ 1)", func(on: bool): pen_perfect = on)
	_sync("perfect", true)
	_check(dv, "mirror", "左右対称に描く", func(on: bool): pen_mirror = on)
	_head(dv, "色")
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color = pen
	cp.edit_alpha = false
	cp.color_changed.connect(func(c: Color):
		if not _syncing:
			pen = Color(c.r, c.g, c.b))
	dv.add_child(cp)
	_w["pen"] = cp
	_pal_box = _flow(dv)
	_head(dv, "描いたものの入り方")
	_check(dv, "decide", "その向きの絵を決める (45° ごと・立体を作り直す)", func(on: bool): decide = on,
			"切ってあるとき (ふつう): 描いた画素は 立体に置かれ、もとの絵は変わりません。描いた向きと その近くで出ます。入れると: その向きの絵そのものを直します (正面・横は 立体の形も変わる)")
	_note(dv, "描きかえた向きには、ほかの向きで描いたものは出ません (その向きの絵が 勝手に変わらない)。")
	var fb := _flow(dv)
	_button(fb, "描いた・けずった画素を全部消す", func():
		if solid != null and not solid.adds.is_empty():
			push_undo()
			solid.adds.clear()
			solid.touch()
			refresh())
	_button(fb, "この向きの決めた絵を捨てる", func(): forget_pic(DotSolid.key_of(yaw)), "推定の絵に戻す (正面は捨てられません)")

	# 部品
	var pv := _tab("部品")
	_note(pv, "正面の絵の どの画素が どの部品かを 塗って直します (向きを正面にして、絵の上をなぞる)。胸と腰・ひじ・ひざは 自動で分かれます。")
	var pf := _flow(pv)
	for p in PAINT_PARTS:
		var b := _button(pf, DotSolid.PART_NAMES[p], func():
			part_sel = p
			for q in PAINT_PARTS:
				_w["part_%d" % q].set_pressed_no_signal(q == p))
		b.toggle_mode = true
		b.button_pressed = p == 1
		b.add_theme_color_override("font_color", Color(DotSolid.PART_COLORS[p]).darkened(0.45))
		_w["part_%d" % p] = b
	_button(pv, "自動の分け方に戻す", func():
		if solid != null:
			push_undo()
			solid.reset_parts()
			refresh())

	# ポーズ
	var ov := _tab("ポーズ")
	_note(ov, "立体が ちゃんと動くかを確かめる所です (ここのポーズは保存されません。動きは モーションのアプリで)。色のついた丸をつまむ: 手・足の先は 腕・脚ごと (Shift で先だけ)。右クリックで戻す。何もない所を引くと 向きが回る。")
	var of := _flow(ov)
	for nm in POSE_NAMES:
		_button(of, nm, func(): apply_preset(nm))
	_button(ov, "全部もどす", func():
		push_undo()
		pose = {}
		refresh())

	# 絵から作る
	var sv := _tab("絵から作る")
	_note(sv, "「絵を開く」で開いた絵の上で、1 体をクリックして選びます (黄色の枠)。となりの絵と くっついて 一緒に選ばれてしまうときは、引いて 四角で囲んでください。")
	_button(sv, "正面にして 立体を作る", func(): use_cell(0), "選んだ 1 体を 正面の絵にして、立体を作り直す")
	_head(sv, "ほかの向きの絵 (あれば)")
	_note(sv, "横・後ろの絵があると、奥行きや 後ろ姿が その絵から決まります。無ければ 推定です。")
	var sf := _flow(sv)
	_button(sf, "横: 顔が画面の右を向いた絵", func(): use_cell(90), "向きの名前では「左」(90°)。片方だけあれば、反対側は鏡にして使います")
	_button(sf, "横: 顔が画面の左を向いた絵", func(): use_cell(270), "向きの名前では「右」(270°)")
	_button(sf, "後ろ姿", func(): use_cell(180))
	var sf2 := _flow(sv)
	for k in [45, 135, 225, 315]:
		_button(sf2, DIR_NAMES[k / 45] + " にする", func(): use_cell(k))

	# 設定
	var gv := _tab("設定")
	_check(gv, "s_face_layer", "顔を別の層にする", func(on: bool):
		if solid != null:
			push_undo()
			solid.face_layer = on
			solid.touch()
			refresh())
	_check(gv, "s_joints", "関節で分ける (ひじ・ひざ・腰)", func(on: bool):
		if solid != null:
			push_undo()
			solid.joints = on
			solid.touch()
			refresh())
	for it in SETTINGS:
		_slider(gv, "s_" + it[0], it[1], it[2], it[3], it[4], func(x: float):
			if solid != null:
				solid.set(it[0], x)
				solid.touch()
				refresh(), it[5])

	# 真ん中
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 3)
	cols.add_child(cv)
	var dirs := HBoxContainer.new()
	cv.add_child(dirs)
	for d in 8:
		_button(dirs, DIR_NAMES[d], func(): set_yaw(d * 45.0))
	var ys := HSlider.new()
	ys.min_value = 0
	ys.max_value = 359
	ys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ys.focus_mode = Control.FOCUS_NONE
	ys.value_changed.connect(func(v: float):
		if not _syncing:
			yaw = v
			refresh())
	dirs.add_child(ys)
	_w["yaw"] = ys
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(split)
	pix = DotView.new()
	pix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pix.size_flags_stretch_ratio = 1.6
	pix.grid = true
	pix.overlay = _overlay
	pix.pressed.connect(_press)
	pix.dragged.connect(_drag)
	pix.released.connect(_release)
	pix.hovered.connect(func(px: Vector2):
		_hover = px
		pix.queue_redraw())
	split.add_child(pix)
	pix2 = DotView.new()
	pix2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pix2.overlay = func(v: DotView): v.draw_string(get_theme_default_font(), Vector2(6, 16), "90° 回した向き (見るだけ)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	split.add_child(pix2)
	sheet_view = DotView.new()
	sheet_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_view.visible = false
	sheet_view.overlay = _sheet_overlay
	# クリック = つながった 1 体を選ぶ。引いて囲む = その四角の中を選ぶ (となりと くっついている表のとき)
	sheet_view.pressed.connect(func(px: Vector2, button: int):
		if button == MOUSE_BUTTON_LEFT:
			_sheet_a = px)
	sheet_view.dragged.connect(func(px: Vector2, _rel: Vector2, button: int):
		if button == MOUSE_BUTTON_LEFT and _sheet_a.distance_to(px) > 1.5:
			set_sheet_rect(Rect2i(Vector2i(_sheet_a.floor()), Vector2i.ZERO).expand(Vector2i(px.floor())).grow_individual(0, 0, 1, 1)))
	sheet_view.released.connect(func(px: Vector2, button: int):
		if button != MOUSE_BUTTON_LEFT:
			return
		if _sheet_a.distance_to(px) <= 1.5:
			pick_island(Vector2i(px.floor()))
		_hint.text = ("1 体を選びました (%d × %d)" % [sheet_rect.size.x, sheet_rect.size.y]) if sheet_rect.size.x > 0 else "そこには何もありません")
	cv.add_child(sheet_view)
	var info := Label.new()
	cv.add_child(info)
	_w["info"] = info

	# 右
	var rsc := ScrollContainer.new()
	rsc.custom_minimum_size.x = 300
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(rsc)
	var rm := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		rm.add_theme_constant_override("margin_" + s, 8)
	rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rsc.add_child(rm)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 5)
	rm.add_child(rv)
	_head(rv, "8 方向 (クリックで その向きへ)")
	_prev = TextureRect.new()
	_prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_prev.stretch_mode = TextureRect.STRETCH_SCALE
	_prev.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prev.custom_minimum_size = Vector2(284, 178)
	_prev.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _prev.size.x > 0:
			set_yaw((clampi(int(e.position.y / (_prev.size.y / 2.0)), 0, 1) * 4 + clampi(int(e.position.x / (_prev.size.x / 4.0)), 0, 3)) * 45.0))
	rv.add_child(_prev)
	_head(rv, "書き出す")
	_button(rv, "PNG (この向き)", func(): _ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.png"], model_name + ".png", func(p: String):
		_hint.text = ("書き出しました: " + p) if export_png(p if p.ends_with(".png") else p + ".png") else "書き出せませんでした"))
	_button(rv, "PNG (8 方向を横に並べる)", func(): _ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.png"], model_name + "_8.png", func(p: String):
		_hint.text = ("書き出しました: " + p) if export_sheet(p if p.ends_with(".png") else p + ".png") else "書き出せませんでした"))
	_note(rv, "動き (アニメ)・Aseprite・GIF は、保存したモデルを「モーションで開く」で。")

	_hint = Label.new()
	_hint.text = "B えんぴつ　E 消しゴム　G バケツ　L 線　U 四角　I スポイト　← → 向き　Ctrl+Z 元に戻す"
	root.add_child(_hint)
