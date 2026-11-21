extends Control
## dot-Godough モーション: dot-godough で作って書き出した ドット絵モデル (.dotmodel.json。.dotg.json もそのまま開ける) に動きをつける。
##  アニメ (clip) = 名前・速さ・長さ・キー (コマ番号 → ポーズ) の集まり。キーの無いコマは、前のキーのまま (ドット絵ふう) か、前後を混ぜる (なめらか)。
##  絵は コマごとに立体から描く (scripts/solid.gd は dot-godough と同じもの。Sync.bat で写す)。
## 起動: Run.bat。確かめ: Run.bat -- --selftest <フォルダ> (tests/selftest.gd)

const XP := preload("res://scripts/xp.gd")
const DIR_NAMES := ["正面", "左ななめ前", "左", "左ななめ後ろ", "後ろ", "右ななめ後ろ", "右", "右ななめ前"]
const POSE_NAMES := ["立ち", "歩き 1", "歩き 2", "すわる", "ゆかにすわる", "おじぎ", "手をあげる"]
const SWAP := {3: 4, 4: 3, 5: 6, 6: 5, 7: 8, 8: 7, 9: 10, 10: 9, 12: 13, 13: 12}

var model: DotSolid              ## 余白を足したあとの立体 (描くのは これ)
var base: DotSolid               ## 開いたままの立体 (余白なし)
var pad := {"x": 0, "top": 0, "bottom": 0}      ## 紙に足す余白 (画素): 左右それぞれ・上・下
var model_name := ""
var clips: Array = []            ## [{name, fps, loop, len, smooth, keys: {コマ: {pose: {部品: Quaternion}, root: Vector3}}}]
var clip_i := 0
var frame := 0
var yaw := 0.0
var playing := false
var onion := false
var show_handles := true
var gif_scale := 4
var turn_n := 16                 ## ぐるっと一周のコマ数
var file_path := ""

var pix: DotView
var _w := {}
var _syncing := false
var _hint: Label
var _clip_list: ItemList
var _tl: Control
var _prev: TextureRect
var _timer: Timer
var _dialog: FileDialog
var _undo: Array = []
var _redo: Array = []
var _cache := {}                 ## "アニメ|コマ|向き" → Image
var _clip_board = null           ## 写したキー
var _sdrag := 0
var _sdrag_last := Vector2.ZERO
var _yaw_drag := false
var _dirty_prev := true
var _onion_tex := {}
var _selftest: RefCounted


func _ready() -> void:
	theme = XP.make_theme()
	clips = [new_clip("アニメ 1")]
	_build_ui()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--selftest":
		_selftest = load("res://tests/selftest.gd").new()
		_selftest.run(self, args[1])
	elif args.size() >= 1 and args[0].ends_with(".json"):
		open_any(args[0])
	await get_tree().process_frame
	pix.fit()
	refresh()


# --- データ ----------------------------------------------------------------------------- #

func new_clip(name: String) -> Dictionary:
	return {"name": name, "fps": 8, "loop": true, "len": 4, "smooth": false, "keys": {}}


func clip() -> Dictionary:
	return clips[clip_i]


static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var pose := {}
	for k in a.pose:
		pose[k] = true
	for k in b.pose:
		pose[k] = true
	for k in pose:
		pose[k] = Quaternion(a.pose.get(k, Quaternion.IDENTITY)).slerp(Quaternion(b.pose.get(k, Quaternion.IDENTITY)), t)
	return {"pose": pose, "root": Vector3(a.root).lerp(Vector3(b.root), t)}


## アニメ c の コマ f のポーズ {pose, root}。キーが無ければ 立ち
func pose_at(c: Dictionary, f: int) -> Dictionary:
	if c.keys.has(f):
		return c.keys[f]
	var ks: Array = c.keys.keys()
	if ks.is_empty():
		return {"pose": {}, "root": Vector3.ZERO}
	ks.sort()
	var prev = null
	var next = null
	for k in ks:
		if k <= f:
			prev = k
		elif next == null:
			next = k
	if prev == null:
		if not c.loop:
			return c.keys[ks[0]]
		prev = ks[-1] - int(c.len)
	if next == null:
		if not c.loop:
			return c.keys[posmod(prev, int(c.len))]
		next = ks[0] + int(c.len)
	var ka: Dictionary = c.keys[posmod(prev, int(c.len))]
	if not c.smooth or next == prev:
		return ka
	return _mix(ka, c.keys[posmod(next, int(c.len))], float(f - prev) / float(next - prev))


## アニメ ci の コマ f を、向き y で描いた絵 (覚えておく)
func frame_image(ci: int, f: int, y: float) -> Image:
	var key := "%d|%d|%.1f" % [ci, f, y]
	if _cache.has(key):
		return _cache[key]
	var img: Image
	if model == null:
		img = Image.create_empty(32, 40, false, Image.FORMAT_RGBA8)
	else:
		var p := pose_at(clips[ci], f)
		model.pose = p.pose
		var r: Vector3 = p.root
		model.root = Vector3(roundf(r.x), roundf(r.y), roundf(r.z))      # 画素にそろえる (あいだのコマで にじまないように)
		img = model.render(y)
	_cache[key] = img
	return img


func invalidate() -> void:
	_cache.clear()
	_dirty_prev = true


## いまのコマのキー。make = 無ければ、いま見えているポーズで打つ
func key_here(make := false):
	var c := clip()
	if c.keys.has(frame):
		return c.keys[frame]
	if not make:
		return null
	var p := pose_at(c, frame)
	c.keys[frame] = {"pose": p.pose.duplicate(), "root": Vector3(p.root)}
	return c.keys[frame]


func push_undo() -> void:
	_undo.append({"clips": clips.duplicate(true), "clip_i": clip_i, "frame": frame})
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()


func _restore(s: Dictionary) -> void:
	clips = s.clips
	clip_i = clampi(s.clip_i, 0, clips.size() - 1)
	frame = clampi(s.frame, 0, int(clip().len) - 1)
	invalidate()
	_sync_clip_ui()
	refresh()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append({"clips": clips.duplicate(true), "clip_i": clip_i, "frame": frame})
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append({"clips": clips.duplicate(true), "clip_i": clip_i, "frame": frame})
	_restore(_redo.pop_back())


# --- 操作 ------------------------------------------------------------------------------- #

func set_frame(f: int) -> void:
	frame = posmod(f, int(clip().len))
	refresh()


func set_yaw(y: float) -> void:
	yaw = fposmod(y, 360.0)
	_sync("yaw", yaw)
	refresh()


func add_key() -> void:
	if clip().keys.has(frame):
		return
	push_undo()
	key_here(true)
	invalidate()
	refresh()


func remove_key() -> void:
	if not clip().keys.has(frame):
		return
	push_undo()
	clip().keys.erase(frame)
	invalidate()
	refresh()


func copy_key() -> void:
	var p := pose_at(clip(), frame)
	_clip_board = {"pose": p.pose.duplicate(), "root": Vector3(p.root)}
	_hint.text = "コマ %d のポーズを写しました" % (frame + 1)


## 写したポーズを、いまのコマに貼る。mirror = 左右を入れかえて貼る (歩きの反対の足など)
func paste_key(mirror := false) -> void:
	if _clip_board == null:
		return
	push_undo()
	var pose := {}
	for k in _clip_board.pose:
		var q := Quaternion(_clip_board.pose[k])
		if mirror:
			pose[SWAP.get(int(k), int(k))] = Quaternion(q.x, -q.y, -q.z, q.w)
		else:
			pose[int(k)] = q
	var r := Vector3(_clip_board.root)
	clip().keys[frame] = {"pose": pose, "root": Vector3(-r.x, r.y, r.z) if mirror else r}
	invalidate()
	refresh()


## いまのコマを、決まったポーズにする
func apply_preset(name: String) -> void:
	if model == null:
		return
	push_undo()
	var pr: Dictionary = model.preset(name)
	clip().keys[frame] = {"pose": pr.pose.duplicate(), "root": Vector3(pr.root)}
	invalidate()
	refresh()


## 全体を動かす (画素)。dx = 画面の横、dy = 上
func nudge(dx: int, dy: int) -> void:
	if model == null:
		return
	push_undo()
	var k = key_here(true)
	var th := deg_to_rad(yaw)
	k.root = Vector3(k.root) + Vector3(cos(th), 0.0, sin(th)) * float(dx) + Vector3(0.0, float(dy), 0.0)
	invalidate()
	refresh()


func set_len(n: int) -> void:
	n = clampi(n, 1, 120)
	var c := clip()
	if n == int(c.len):
		return
	push_undo()
	c.len = n
	for k in c.keys.keys():
		if k >= n:
			c.keys.erase(k)
	frame = mini(frame, n - 1)
	invalidate()
	_sync_clip_ui()
	refresh()


## いまのコマの後ろに、空のコマを 1 つ入れる (後ろのキーは 1 つずつ後ろへ)
func insert_frame() -> void:
	var c := clip()
	if int(c.len) >= 120:
		return
	push_undo()
	var nk := {}
	for k in c.keys:
		nk[k + 1 if k > frame else k] = c.keys[k]
	c.keys = nk
	c.len = int(c.len) + 1
	frame += 1
	invalidate()
	_sync_clip_ui()
	refresh()


## いまのコマを取りのぞく (後ろのキーは 1 つずつ前へ)
func delete_frame() -> void:
	var c := clip()
	if int(c.len) <= 1:
		return
	push_undo()
	var nk := {}
	for k in c.keys:
		if k != frame:
			nk[k - 1 if k > frame else k] = c.keys[k]
	c.keys = nk
	c.len = int(c.len) - 1
	frame = mini(frame, int(c.len) - 1)
	invalidate()
	_sync_clip_ui()
	refresh()


func add_clip(name := "") -> void:
	push_undo()
	clips.append(new_clip(name if name != "" else "アニメ %d" % (clips.size() + 1)))
	clip_i = clips.size() - 1
	frame = 0
	_sync_clip_ui()
	refresh()


func duplicate_clip() -> void:
	push_undo()
	var c: Dictionary = clip().duplicate(true)
	c.name += " の写し"
	clips.insert(clip_i + 1, c)
	clip_i += 1
	invalidate()
	_sync_clip_ui()
	refresh()


func remove_clip() -> void:
	if clips.size() <= 1:
		return
	push_undo()
	clips.remove_at(clip_i)
	clip_i = mini(clip_i, clips.size() - 1)
	frame = 0
	invalidate()
	_sync_clip_ui()
	refresh()


## 歩きのアニメを足す (4 コマ。足をついたコマと、入れかえる途中のコマ)
func make_walk() -> void:
	if model == null:
		_hint.text = "先にモデルを開いてください"
		return
	push_undo()
	var c := new_clip("歩き")
	var i := 0
	for k in model.walk_cycle():
		c.keys[i] = {"pose": k.pose.duplicate(), "root": Vector3(k.root)}
		i += 1
	c.len = i
	c.fps = 6
	clips.append(c)
	clip_i = clips.size() - 1
	frame = 0
	invalidate()
	_sync_clip_ui()
	refresh()


func play(on: bool) -> void:
	playing = on and int(clip().len) > 1
	if playing:
		_timer.wait_time = 1.0 / maxf(float(clip().fps), 1.0)
		_timer.start()
	else:
		_timer.stop()
	if _w.has("play"):
		_w["play"].text = "■ 止める" if playing else "▶ 再生"


func _tick() -> void:
	var c := clip()
	if frame + 1 >= int(c.len) and not c.loop:
		play(false)
		return
	set_frame(frame + 1)


# --- 開く・保存 -------------------------------------------------------------------------- #

## モデルを開く (.dotmodel.json か、dot-godough のキャラ .dotg.json)。アニメは そのまま残る (モデルだけ入れかえる)
func load_model(path: String) -> bool:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not d.has("solid") or not (d.solid is Dictionary) or d.solid.is_empty():
		_hint.text = "立体の入っていないファイルです: " + path.get_file()
		return false
	var m := DotSolid.from_doc(d.solid)
	if m == null:
		return false
	base = m
	model_name = str(d.get("name", path.get_file().get_basename().get_basename()))
	_apply_pad()
	_title()
	return true


func _apply_pad() -> void:
	if base == null:
		return
	model = base.padded(int(pad.x), int(pad.top), int(pad.bottom))
	model.ensure()
	invalidate()
	for k in ["x", "top", "bottom"]:
		_sync("pad_" + k, pad[k])
	if _w.has("pad_info"):
		_w["pad_info"].text = "紙: %d × %d 画素 (もとは %d × %d)" % [model.w, model.h, base.w, base.h]
	refresh()
	if pix != null:
		pix.fit()


## 紙の余白を変える (画素)。キーは そのまま (ポーズは 紙の大きさに よらない)
func set_pad(x: int, top: int, bottom: int) -> void:
	pad = {"x": clampi(x, 0, 64), "top": clampi(top, 0, 64), "bottom": clampi(bottom, 0, 64)}
	_apply_pad()


## 全部のアニメ・全部のコマ・8 方向を描いて、はみ出さない いちばん小さい余白にする (上と左右。足もとは そのまま)
func fit_pad() -> void:
	if base == null:
		return
	var big := 32
	var probe: DotSolid = base.padded(big, big, int(pad.bottom))
	probe.ensure()
	var x0 := probe.w
	var x1 := -1
	var y0 := probe.h
	for c in clips:
		for f in int(c.len):
			var p := pose_at(c, f)
			probe.pose = p.pose
			probe.root = Vector3(roundf(p.root.x), roundf(p.root.y), roundf(p.root.z))
			for d in 8:
				var r: Rect2i = probe.render(d * 45.0).get_used_rect()
				if r.size.x > 0:
					x0 = mini(x0, r.position.x)
					x1 = maxi(x1, r.end.x - 1)
					y0 = mini(y0, r.position.y)
	if x1 < 0:
		return
	# 紙のはしに 1 画素あける
	var need_x := maxi(maxi(big - x0, x1 - (big + base.w - 1)) + 1, 0)
	var need_top := maxi(big - y0 + 1, 0)
	set_pad(need_x, need_top, int(pad.bottom))
	_hint.text = "余白を 左右 %d・上 %d 画素にしました (紙 %d × %d)" % [need_x, need_top, model.w, model.h]


func to_doc() -> Dictionary:
	var cs := []
	for c in clips:
		var ks := []
		var fs: Array = c.keys.keys()
		fs.sort()
		for f in fs:
			var pose := {}
			for p in c.keys[f].pose:
				var q := Quaternion(c.keys[f].pose[p])
				pose[str(p)] = [q.x, q.y, q.z, q.w]
			var r := Vector3(c.keys[f].root)
			ks.append({"f": f, "pose": pose, "root": [r.x, r.y, r.z]})
		cs.append({"name": c.name, "fps": c.fps, "loop": c.loop, "len": c.len, "smooth": c.smooth, "keys": ks})
	return {"app": "dot-godough-motion", "version": 1, "model_name": model_name, "model": base.to_doc() if base != null else {}, "pad": pad, "clips": cs}


func from_doc(d: Dictionary) -> void:
	if d.get("model", {}) is Dictionary and not d.get("model", {}).is_empty():
		base = DotSolid.from_doc(d.model)
	var pd: Dictionary = d.get("pad", {})
	pad = {"x": int(pd.get("x", 0)), "top": int(pd.get("top", 0)), "bottom": int(pd.get("bottom", 0))}
	model_name = str(d.get("model_name", ""))
	clips = []
	for c in d.get("clips", []):
		var nc := new_clip(str(c.get("name", "アニメ")))
		nc.fps = int(c.get("fps", 8))
		nc.loop = bool(c.get("loop", true))
		nc.len = maxi(int(c.get("len", 4)), 1)
		nc.smooth = bool(c.get("smooth", false))
		for k in c.get("keys", []):
			var pose := {}
			for p in k.get("pose", {}):
				var a: Array = k.pose[p]
				pose[int(p)] = Quaternion(a[0], a[1], a[2], a[3])
			var r: Array = k.get("root", [0, 0, 0])
			nc.keys[int(k.f)] = {"pose": pose, "root": Vector3(r[0], r[1], r[2])}
		clips.append(nc)
	if clips.is_empty():
		clips = [new_clip("アニメ 1")]
	clip_i = 0
	frame = 0
	_undo.clear()
	_redo.clear()
	_sync_clip_ui()
	_apply_pad()


func save_doc(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_doc(), " "))
	file_path = path
	_title()
	return true


## ファイルを開く: アニメのファイル (.dotanim.json) なら全部、モデルなら モデルだけ入れかえる
func open_any(path: String) -> bool:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return false
	if d.get("app", "") == "dot-godough-motion":
		from_doc(d)
		file_path = path
		_title()
		if pix != null:
			pix.fit()
		return true
	return load_model(path)


func _title() -> void:
	get_window().title = "dot-Godough モーション" + ("" if model_name == "" else " — " + model_name) + ("" if file_path == "" else " (" + file_path.get_file() + ")")


# --- 書き出し ---------------------------------------------------------------------------- #

func clip_frames(ci: int, y: float) -> Array:
	var out := []
	for f in int(clips[ci].len):
		out.append(frame_image(ci, f, y))
	return out


## GIF: いまのアニメ。all_dirs = 8 方向を 4 × 2 に並べる
func export_gif(path: String, all_dirs: bool) -> bool:
	if model == null:
		return false
	var frames := []
	if all_dirs:
		for f in int(clip().len):
			var im := Image.create_empty(model.w * 4, model.h * 2, false, Image.FORMAT_RGBA8)
			for d in 8:
				im.blit_rect(frame_image(clip_i, f, d * 45.0), Rect2i(0, 0, model.w, model.h), Vector2i((d % 4) * model.w, (d / 4) * model.h))
			frames.append(im)
	else:
		frames = clip_frames(clip_i, yaw)
	return AnimExport.save_gif(frames, path, int(round(100.0 / maxf(float(clip().fps), 1.0))), gif_scale)


## Aseprite: all_clips = 全部のアニメ、all_dirs = 8 方向。アニメ × 向きごとにタグ。コマの長さは アニメごとの速さ
func export_ase(path: String, all_clips: bool, all_dirs: bool) -> bool:
	if model == null:
		return false
	var frames := []
	var ms := []
	var tags := []
	for ci in (range(clips.size()) if all_clips else [clip_i]):
		var c: Dictionary = clips[ci]
		for d in (range(8) if all_dirs else [-1]):
			var fr := clip_frames(ci, yaw if d < 0 else d * 45.0)
			var nm: String = c.name
			if d >= 0:
				nm += " " + DIR_NAMES[d]
			tags.append({"name": nm, "from": frames.size(), "to": frames.size() + fr.size() - 1})
			frames.append_array(fr)
			for i in fr.size():
				ms.append(int(round(1000.0 / maxf(float(c.fps), 1.0))))
	return AnimExport.save_ase(frames, path, ms, tags)


## ぐるっと一周: いまのコマのポーズを n 方向 (360 / n 度ずつ) で描いて、GIF か Aseprite に。
## walk = 回りながら アニメも進める (コマ k は アニメの k 番目)
func export_turn(path: String, n: int, walk := false) -> bool:
	if model == null:
		return false
	var frames := []
	var c := clip()
	for k in n:
		frames.append(frame_image(clip_i, posmod(frame + k, int(c.len)) if walk else frame, snappedf(k * 360.0 / n, 0.1)))
	if path.ends_with(".gif"):
		return AnimExport.save_gif(frames, path, int(round(100.0 / maxf(float(c.fps), 1.0))), gif_scale)
	return AnimExport.save_ase(frames, path, int(round(1000.0 / maxf(float(c.fps), 1.0))), [{"name": "一周", "from": 0, "to": n - 1}])


## 8 方向の歩きのスプライト: 「歩き」という名前のアニメ (無ければ 立体の歩き 4 コマを作って足す) を、拡張子で シート PNG / Aseprite / GIF に
func export_walk8(path: String) -> bool:
	if model == null:
		return false
	var wi := -1
	for i in clips.size():
		if str(clips[i].name) == "歩き":
			wi = i
	if wi < 0:
		make_walk()
		wi = clips.size() - 1
	var keep := clip_i
	clip_i = wi
	var ext := path.get_extension().to_lower()
	var ok: bool = export_ase(path, false, true) if ext == "aseprite" else (export_gif(path, true) if ext == "gif" else export_sheet(path))
	clip_i = keep
	refresh()
	return ok


## シート (PNG): いまのアニメ。行 = 8 方向、列 = コマ。となりに .json (コマの大きさ・速さ・向き)
func export_sheet(path: String) -> bool:
	if model == null:
		return false
	var c := clip()
	var sheet := Image.create_empty(model.w * int(c.len), model.h * 8, false, Image.FORMAT_RGBA8)
	for d in 8:
		for f in int(c.len):
			sheet.blit_rect(frame_image(clip_i, f, d * 45.0), Rect2i(0, 0, model.w, model.h), Vector2i(f * model.w, d * model.h))
	if sheet.save_png(path) != OK:
		return false
	var jf := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify({"name": c.name, "frame_w": model.w, "frame_h": model.h, "frames": c.len, "fps": c.fps, "loop": c.loop, "rows": DIR_NAMES}, " "))
	return true


func _ask(mode: int, filters: PackedStringArray, name: String, cb: Callable) -> void:
	play(false)
	if _dialog != null:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = mode
	_dialog.filters = filters
	_dialog.current_file = name
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(cb)
	add_child(_dialog)
	_dialog.popup_centered(Vector2i(820, 560))


func _ask_export(ext: String, label: String, fn: Callable) -> void:
	if model == null:
		_hint.text = "先にモデルを開いてください"
		return
	_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*." + ext], clip().name + "." + ext, func(p: String):
		if not p.ends_with("." + ext):
			p += "." + ext
		_hint.text = (label + "を書き出しました: " + p) if fn.call(p) else ("書き出せませんでした: " + p))


# --- 画面 ------------------------------------------------------------------------------- #

func refresh() -> void:
	if pix == null:
		return
	pix.set_image(frame_image(clip_i, frame, yaw))
	pix.queue_redraw()
	_tl.queue_redraw()
	_dirty_prev = true
	if _w.has("info"):
		var c := clip()
		var k: String = "キー" if c.keys.has(frame) else ("あいだ (混ぜる)" if c.smooth else "前のキーのまま")
		_w["info"].text = "コマ %d / %d — %s　　向き %d°" % [frame + 1, int(c.len), k if not c.keys.is_empty() else "キーなし (立ち)", int(yaw)]


func _process(_dt: float) -> void:
	# 8 方向の見本: 手があいたら 1 枚ずつ描いて、そろったら並べる
	if model == null or not _dirty_prev or _sdrag != 0:
		return
	for d in 8:
		var key := "%d|%d|%.1f" % [clip_i, frame, d * 45.0]
		if not _cache.has(key):
			frame_image(clip_i, frame, d * 45.0)
			return
	var im := Image.create_empty(model.w * 4, model.h * 2, false, Image.FORMAT_RGBA8)
	im.fill(Color("#8a8f9a"))
	for d in 8:
		im.blend_rect(frame_image(clip_i, frame, d * 45.0), Rect2i(0, 0, model.w, model.h), Vector2i((d % 4) * model.w, (d / 4) * model.h))
	_prev.texture = ImageTexture.create_from_image(im)
	_prev.custom_minimum_size = Vector2(284, 284.0 * (model.h * 2.0) / (model.w * 4.0))
	_dirty_prev = false


func _overlay(v: DotView) -> void:
	if model == null:
		v.draw_string(get_theme_default_font(), Vector2(12, 24), "「モデルを開く」で、dot-godough から書き出した ドット絵モデルを開いてください", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
		return
	var c := clip()
	if onion and not playing and int(c.len) > 1:
		# 前と次のコマを うすく重ねる (前 = 青、次 = 赤)
		for it in [[-1, Color(0.4, 0.6, 1.0, 0.35)], [1, Color(1.0, 0.45, 0.4, 0.35)]]:
			var f: int = frame + it[0]
			if not c.loop and (f < 0 or f >= int(c.len)):
				continue
			var t := ImageTexture.create_from_image(frame_image(clip_i, posmod(f, int(c.len)), yaw))
			_onion_tex[it[0]] = t        # 持っておく (描き終わる前に消えると 白い四角になる)
			v.draw_texture_rect(t, Rect2(v.to_screen(Vector2.ZERO), Vector2(v.img_size) * v.zoom), false, it[1])
	if not show_handles or playing:
		return
	var p := pose_at(c, frame)
	model.pose = p.pose
	model.root = Vector3(roundf(p.root.x), roundf(p.root.y), roundf(p.root.z))
	for hd in model.handles(yaw):
		var a: Vector2 = v.to_screen(hd.pivot)
		var b: Vector2 = v.to_screen(hd.tip)
		v.draw_line(a, b, Color(0, 0, 0, 0.3), 1.0)
		v.draw_circle(a, 2.5, Color(0, 0, 0, 0.6))
		if hd.part == _sdrag:
			v.draw_circle(b, 8.0, Color(1, 1, 1, 0.95))
		v.draw_circle(b, 5.5, Color(0, 0, 0, 0.75))
		v.draw_circle(b, 4.5, Color(DotSolid.PART_COLORS[hd.part]))


func _pick(px: Vector2) -> int:
	var best := 2.6
	var part := 0
	var p := pose_at(clip(), frame)
	model.pose = p.pose
	model.root = Vector3(roundf(p.root.x), roundf(p.root.y), roundf(p.root.z))
	for hd in model.handles(yaw):
		var d: float = hd.tip.distance_to(px)
		if d < best:
			best = d
			part = hd.part
	return part


func _on_press(px: Vector2, button: int) -> void:
	if model == null:
		return
	play(false)
	var part := _pick(px) if show_handles else 0
	if button == MOUSE_BUTTON_RIGHT:
		if part != 0:
			# その部品を まっすぐに戻す (手・足の先なら つけ根側も)
			push_undo()
			var k = key_here(true)
			k.pose.erase(part)
			if part in DotSolid.IK_PARTS:
				k.pose.erase(DotSolid.PARENT[part])
			invalidate()
			refresh()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	if part == 0:
		_yaw_drag = true
		return
	push_undo()
	key_here(true)
	_sdrag = part
	_sdrag_last = px


func _on_drag(px: Vector2, rel: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or model == null:
		return
	if _yaw_drag:
		set_yaw(yaw + rel.x * pix.zoom * 0.6)
		return
	if _sdrag == 0:
		return
	var k = key_here(true)
	model.pose = k.pose              # 同じ辞書を渡す: 立体が書きかえた回転が そのままキーに入る
	model.root = Vector3(roundf(k.root.x), roundf(k.root.y), roundf(k.root.z))
	if _sdrag in DotSolid.IK_PARTS and not Input.is_key_pressed(KEY_SHIFT):
		model.drag_ik(_sdrag, yaw, px)
	else:
		model.drag_part(_sdrag, yaw, _sdrag_last, px)
	_sdrag_last = px
	invalidate()
	refresh()


func _on_release(_px: Vector2, _button: int) -> void:
	if _yaw_drag:
		_yaw_drag = false
		set_yaw(roundf(yaw / 45.0) * 45.0)
	_sdrag = 0
	pix.queue_redraw()


func _draw_timeline() -> void:
	var c := clip()
	var n := int(c.len)
	var cw := clampf((_tl.size.x - 8.0) / n, 8.0, 34.0)
	var f := get_theme_default_font()
	_tl.draw_rect(Rect2(Vector2.ZERO, _tl.size), Color("#ffffff"))
	_tl.draw_rect(Rect2(Vector2.ZERO, _tl.size), XP.EDGE, false, 1.0)
	for i in n:
		var r := Rect2(4.0 + i * cw, 4.0, cw - 1.0, _tl.size.y - 8.0)
		_tl.draw_rect(r, XP.SELECT if i == frame else (Color("#e8eefb") if i % 2 == 0 else Color("#f6f8fd")))
		if c.keys.has(i):
			var m := r.get_center() + Vector2(0, 6)
			var s := minf(cw * 0.3, 6.0)
			_tl.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s), m + Vector2(s, 0), m + Vector2(0, s), m + Vector2(-s, 0)]),
					Color.WHITE if i == frame else Color("#d0661a"))
		if cw >= 16.0 or i % 5 == 0:
			_tl.draw_string(f, r.position + Vector2(3, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE if i == frame else Color("#555555"))


func _tl_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var n := int(clip().len)
		var cw := clampf((_tl.size.x - 8.0) / n, 8.0, 34.0)
		play(false)
		set_frame(clampi(int((e.position.x - 4.0) / cw), 0, n - 1))


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var ctrl: bool = e.ctrl_pressed
	match e.keycode:
		KEY_SPACE:
			play(not playing)
		KEY_COMMA:
			play(false)
			set_frame(frame - 1)
		KEY_PERIOD:
			play(false)
			set_frame(frame + 1)
		KEY_K:
			add_key()
		KEY_DELETE:
			remove_key()
		KEY_Q:
			set_yaw(roundf(yaw / 45.0) * 45.0 - 45.0)
		KEY_E:
			set_yaw(roundf(yaw / 45.0) * 45.0 + 45.0)
		KEY_LEFT:
			nudge(-1, 0)
		KEY_RIGHT:
			nudge(1, 0)
		KEY_UP:
			nudge(0, 1)
		KEY_DOWN:
			nudge(0, -1)
		KEY_Z:
			if ctrl:
				undo()
		KEY_Y:
			if ctrl:
				redo()
		KEY_C:
			if ctrl:
				copy_key()
		KEY_V:
			if ctrl:
				paste_key(e.shift_pressed)
		KEY_S:
			if ctrl:
				_save()
		_:
			return
	accept_event()


func _save() -> void:
	if file_path != "":
		_hint.text = ("保存しました: " + file_path) if save_doc(file_path) else "保存できませんでした"
	else:
		_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.dotanim.json ; dot-Godough モーション"], (model_name if model_name != "" else "アニメ") + ".dotanim.json", func(p: String):
			if not p.ends_with(".dotanim.json"):
				p += ".dotanim.json"
			_hint.text = ("保存しました: " + p) if save_doc(p) else "保存できませんでした")


func _sync(key: String, value) -> void:
	if not _w.has(key):
		return
	_syncing = true
	var c = _w[key]
	if c is Range:
		c.value = value
	elif c is BaseButton:
		c.button_pressed = value
	elif c is LineEdit:
		if c.text != str(value):
			c.text = str(value)
	_syncing = false


func _sync_clip_ui() -> void:
	if _clip_list == null:
		return
	_clip_list.clear()
	for c in clips:
		_clip_list.add_item("%s  (%d コマ・%d コマ/秒)" % [c.name, int(c.len), int(c.fps)])
	_clip_list.select(clip_i)
	var c := clip()
	_sync("c_name", c.name)
	_sync("c_fps", c.fps)
	_sync("c_len", c.len)
	_sync("c_loop", c.loop)
	_sync("c_smooth", c.smooth)
	if playing:
		play(true)


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


func _spin(parent: Control, key: String, label: String, lo: int, hi: int, cb: Callable, tip := "") -> SpinBox:
	var h := HBoxContainer.new()
	h.tooltip_text = tip
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	h.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float):
		if not _syncing:
			cb.call(int(v)))
	h.add_child(s)
	parent.add_child(h)
	_w[key] = s
	return s


func _panel(width: int) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size.x = width
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	m.add_child(v)
	_cols.add_child(sc)
	return v


var _cols: HBoxContainer


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = XP.FACE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	add_child(root)
	# 上の列
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_button(bar, "モデルを開く", func(): _ask(FileDialog.FILE_MODE_OPEN_FILE, ["*.dotmodel.json, *.dotg.json ; ドット絵モデル / dot-Godough のキャラ", "*.json"], "", func(p: String):
		_hint.text = ("モデルを開きました: " + p.get_file()) if load_model(p) else _hint.text),
			"dot-godough の「モデルを書き出す」で作ったファイル。キャラのファイル (.dotg.json) も そのまま開けます。アニメは残して モデルだけ入れかえます")
	bar.add_child(VSeparator.new())
	_button(bar, "開く", func(): _ask(FileDialog.FILE_MODE_OPEN_FILE, ["*.dotanim.json ; dot-Godough モーション"], "", func(p: String): open_any(p)), "アニメのファイルを開く")
	_button(bar, "保存", _save, "Ctrl+S")
	_button(bar, "名前をつけて保存", func():
		file_path = ""
		_save())
	bar.add_child(VSeparator.new())
	_button(bar, "元に戻す", undo, "Ctrl+Z")
	_button(bar, "やり直す", redo, "Ctrl+Y")
	bar.add_child(VSeparator.new())
	_button(bar, "全体を表示", func(): pix.fit())
	_check(bar, "handles", "つまむ所", func(on: bool):
		show_handles = on
		pix.queue_redraw())
	_sync("handles", true)
	_check(bar, "onion", "前後のコマを うすく重ねる", func(on: bool):
		onion = on
		pix.queue_redraw(), "前のコマ = 青、次のコマ = 赤")
	_cols = HBoxContainer.new()
	_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_cols)

	# 左: アニメの一覧
	var lv := _panel(250)
	_head(lv, "アニメ")
	_clip_list = ItemList.new()
	_clip_list.custom_minimum_size.y = 130
	_clip_list.focus_mode = Control.FOCUS_NONE
	_clip_list.item_selected.connect(func(i: int):
		clip_i = i
		frame = 0
		_sync_clip_ui()
		refresh())
	lv.add_child(_clip_list)
	var f1 := _flow(lv)
	_button(f1, "足す", func(): add_clip())
	_button(f1, "写す", duplicate_clip)
	_button(f1, "消す", remove_clip)
	_button(f1, "歩きを足す", make_walk, "歩きの 4 コマのアニメを足す")
	var ne := LineEdit.new()
	ne.placeholder_text = "名前"
	ne.text_changed.connect(func(t: String):
		if not _syncing:
			clip().name = t
			_clip_list.set_item_text(clip_i, "%s  (%d コマ・%d コマ/秒)" % [t, int(clip().len), int(clip().fps)]))
	lv.add_child(ne)
	_w["c_name"] = ne
	_spin(lv, "c_len", "長さ (コマ)", 1, 120, set_len)
	_spin(lv, "c_fps", "速さ (コマ/秒)", 1, 30, func(v: int):
		clip().fps = v
		_sync_clip_ui())
	_check(lv, "c_loop", "くり返す", func(on: bool):
		push_undo()
		clip().loop = on
		invalidate()
		refresh())
	_check(lv, "c_smooth", "キーのあいだを混ぜる", func(on: bool):
		push_undo()
		clip().smooth = on
		invalidate()
		refresh(), "切ると、キーの無いコマは 前のキーのまま (ドット絵ふうの コマ送り)。入れると 前後のキーを なめらかに混ぜる")
	_head(lv, "紙の大きさ (余白を足す)")
	_note(lv, "ポーズが紙から はみ出して切れるときに。書き出す絵も この大きさになります。")
	var pi := Label.new()
	lv.add_child(pi)
	_w["pad_info"] = pi
	_spin(lv, "pad_x", "左右 (それぞれ)", 0, 64, func(v: int): set_pad(v, int(pad.top), int(pad.bottom)), "左と右に 同じだけ足します (紙の真ん中が 回る軸なので)")
	_spin(lv, "pad_top", "上", 0, 64, func(v: int): set_pad(int(pad.x), v, int(pad.bottom)))
	_spin(lv, "pad_bottom", "下", 0, 64, func(v: int): set_pad(int(pad.x), int(pad.top), v), "足もとより下。床より下は描かれないので、ふつうは 0 のまま")
	_button(lv, "はみ出さない大きさにする", fit_pad, "全部のアニメ・全部のコマ・8 方向を調べて、切れない いちばん小さい余白 (上と左右) にします")
	_head(lv, "このコマのポーズ")
	var f2 := _flow(lv)
	for nm in POSE_NAMES:
		_button(f2, nm, func(): apply_preset(nm))
	_note(lv, "色のついた丸をつまむ: 手・足の先は 腕・脚ごと ついてくる (Shift で先だけ)。右クリックで まっすぐに戻す。何もない所を引くと 向きが回る。←→↑↓ で全体を 1 画素動かす。")

	# 真ん中: 絵・コマ
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 3)
	_cols.add_child(cv)
	var dirs := HBoxContainer.new()
	cv.add_child(dirs)
	for d in 8:
		_button(dirs, DIR_NAMES[d], func(): set_yaw(d * 45.0))
	var ys := HSlider.new()
	ys.min_value = 0
	ys.max_value = 359
	ys.custom_minimum_size.x = 160
	ys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ys.focus_mode = Control.FOCUS_NONE
	ys.value_changed.connect(func(v: float):
		if not _syncing:
			yaw = v
			refresh())
	dirs.add_child(ys)
	_w["yaw"] = ys
	pix = DotView.new()
	pix.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pix.overlay = _overlay
	pix.pressed.connect(_on_press)
	pix.dragged.connect(_on_drag)
	pix.released.connect(_on_release)
	cv.add_child(pix)
	var tb := HBoxContainer.new()
	cv.add_child(tb)
	_w["play"] = _button(tb, "▶ 再生", func(): play(not playing), "Space")
	_button(tb, "◀", func():
		play(false)
		set_frame(frame - 1), "前のコマ ( , )")
	_button(tb, "▶", func():
		play(false)
		set_frame(frame + 1), "次のコマ ( . )")
	tb.add_child(VSeparator.new())
	_button(tb, "キーを打つ", add_key, "いま見えているポーズを このコマのキーにする (K)。つまんで動かすと 自動で打たれます")
	_button(tb, "キーを消す", remove_key, "Delete")
	_button(tb, "写す", copy_key, "Ctrl+C")
	_button(tb, "貼る", func(): paste_key(false), "Ctrl+V")
	_button(tb, "左右を入れかえて貼る", func(): paste_key(true), "Ctrl+Shift+V。歩きの 反対の足のコマなどに")
	tb.add_child(VSeparator.new())
	_button(tb, "コマを入れる", insert_frame, "いまのコマの後ろに 空のコマを 1 つ")
	_button(tb, "コマを取る", delete_frame)
	_tl = Control.new()
	_tl.custom_minimum_size.y = 46
	_tl.draw.connect(_draw_timeline)
	_tl.gui_input.connect(_tl_input)
	cv.add_child(_tl)
	var info := Label.new()
	cv.add_child(info)
	_w["info"] = info

	# 右: 8 方向・書き出し
	var rv := _panel(300)
	_head(rv, "8 方向 (クリックで その向きへ)")
	_prev = TextureRect.new()
	_prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_prev.stretch_mode = TextureRect.STRETCH_SCALE
	_prev.custom_minimum_size = Vector2(284, 178)
	_prev.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prev.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _prev.size.x > 0:
			var cx := clampi(int(e.position.x / (_prev.size.x / 4.0)), 0, 3)
			var cy := clampi(int(e.position.y / (_prev.size.y / 2.0)), 0, 1)
			set_yaw((cy * 4 + cx) * 45.0))
	rv.add_child(_prev)
	_head(rv, "Aseprite に書き出す")
	_note(rv, "等倍・レイヤー 1 枚。アニメ × 向きごとに タグがつきます。コマの長さは アニメごとの速さ。")
	_button(rv, "このアニメ・この向き", func(): _ask_export("aseprite", "Aseprite のファイル", func(p: String): return export_ase(p, false, false)))
	_button(rv, "このアニメ・8 方向", func(): _ask_export("aseprite", "Aseprite のファイル", func(p: String): return export_ase(p, false, true)))
	_button(rv, "全部のアニメ・8 方向", func(): _ask_export("aseprite", "Aseprite のファイル", func(p: String): return export_ase(p, true, true)))
	_head(rv, "GIF・シート")
	_spin(rv, "gif_scale", "GIF の拡大", 1, 8, func(v: int): gif_scale = v)
	_sync("gif_scale", gif_scale)
	_button(rv, "GIF (この向き)", func(): _ask_export("gif", "GIF ", func(p: String): return export_gif(p, false)))
	_button(rv, "GIF (8 方向を並べる)", func(): _ask_export("gif", "GIF ", func(p: String): return export_gif(p, true)))
	_button(rv, "シート PNG (行 = 8 方向、列 = コマ)", func(): _ask_export("png", "シート", export_sheet), "となりに .json (コマの大きさ・速さ) も出ます")

	_head(rv, "歩き (8 方向)")
	_note(rv, "「歩き」のアニメを 8 方向で書き出します (無ければ 立体の歩き 4 コマで作ります)。シートは 行 = 向き、列 = コマ。")
	for it in [["シート PNG", "png"], ["Aseprite (向きごとにタグ)", "aseprite"], ["GIF (8 方向を並べる)", "gif"]]:
		_button(rv, "歩き 8 方向: " + it[0], func():
			if model == null:
				_hint.text = "先にモデルを開いてください"
				return
			_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*." + it[1]], "walk8." + it[1], func(p: String):
				if not p.to_lower().ends_with("." + it[1]):
					p += "." + it[1]
				_hint.text = ("歩きを書き出しました: " + p) if export_walk8(p) else ("書き出せませんでした: " + p)))

	_head(rv, "ぐるっと一周")
	_note(rv, "8 方向より細かい向きで順に描きます。絵を決めた向きの あいだは推定です。")
	_spin(rv, "turn_n", "一周のコマ数", 8, 48, func(v: int): turn_n = v, "16 = 22.5° ずつ、24 = 15° ずつ")
	_sync("turn_n", turn_n)
	_check(rv, "turn_walk", "回りながら アニメも進める", func(_on: bool): pass, "切ると、いまのコマのポーズのまま回ります")
	var tw := func() -> bool: return _w["turn_walk"].button_pressed
	_button(rv, "一周の GIF", func(): _ask_export("gif", "一周の GIF ", func(p: String): return export_turn(p, turn_n, tw.call())))
	_button(rv, "一周の Aseprite", func(): _ask_export("aseprite", "一周の Aseprite ", func(p: String): return export_turn(p, turn_n, tw.call())))
	_hint = Label.new()
	_hint.text = "Space = 再生　, . = コマ送り　K = キー　Q E = 向き　Ctrl+Z = 元に戻す"
	root.add_child(_hint)
	_timer = Timer.new()
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_sync_clip_ui()
