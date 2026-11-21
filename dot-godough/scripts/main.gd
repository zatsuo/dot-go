extends Control
## dot-Godough: SDF で作った人体を、その場でドット絵にして見ながら、体型とポーズを決める道具。
##
## 中身 (体を作る・撮る・ドット絵にする) は core/*.cs。ここは画面と、ポーズをつける操作。
## 起動: Run.bat。確かめ: Run.bat -- --selftest <フォルダ> (tests/selftest.gd)

const XP := preload("res://scripts/xp.gd")
const Poses := preload("res://scripts/poses.gd")
const CFG := "user://settings.cfg"

## 体型のスライダー: [キー, 名前, 刻み, 説明]
const BODY_UI := [
	["全体", [
		["heads", "頭身", 0.05, "身長 ÷ 頭の高さ。2 = ドット絵のちび、6 = low-Godough の既定"],
		["thickness", "体の太さ", 0.01, "胴・腕・脚をまとめて太く"],
		["sex", "女性らしさ", 0.01, "0 = 男性的 (肩が広い)、1 = 女性的 (腰が広い)"],
	]],
	["胴", [
		["shoulder", "肩幅", 0.01, ""], ["hip", "腰幅", 0.01, ""], ["depth", "胴の厚み", 0.01, "前後の厚み"], ["belly", "おなか", 0.01, "おなかのふくらみ"],
		["neck", "首の長さ", 0.005, ""], ["bust", "胸", 0.01, "女性らしさが 0 だと出ません"],
	]],
	["腕", [
		["arm", "腕の長さ", 0.01, ""], ["arm_thick", "腕の太さ", 0.01, ""], ["hand", "手の大きさ", 0.01, ""],
	]],
	["脚", [
		["leg", "脚の長さ", 0.005, "股の高さ ÷ あごから下の長さ"], ["leg_thick", "脚の太さ", 0.01, ""],
		["foot", "足の大きさ", 0.01, ""], ["taper", "手足の先太り", 0.01, "+ で手首・足首のほうを太く"],
	]],
	["頭", [
		["head_w", "頭の幅", 0.01, ""], ["head_d", "頭の奥行き", 0.01, ""],
		["chibi", "頭の丸さ", 0.01, "左端 (-1) = 頭身に合わせて自動。0 = low-Godough の頭、1 = 丸い頭"],
	]],
	["作るときの姿勢", [
		["arm_angle", "腕の開き", 1.0, "網目を作るときの腕の角度。腕が胴にくっつくときは広げる"],
		["leg_angle", "脚の開き", 0.5, "太い脚どうしがくっつくときは広げる"],
		["height", "身長 (m)", 0.01, "penInk に持っていくときの大きさ。ドット絵の大きさは「キャラの高さ」で決まる"],
	]],
]

## つまむ点: at = 点の場所 (core.Joints のキー)、bone = 回す骨、ik = 2 本まとめて動かす、move = 体ごと動かす
const HANDLES := [
	{"at": "hips", "move": true, "label": "体ごと動かす"},
	{"at": "hips/tail", "bone": "hips", "label": "腰"},
	{"at": "spine/tail", "bone": "spine", "label": "おなか"},
	{"at": "chest/tail", "bone": "chest", "label": "胸"},
	{"at": "neck/tail", "bone": "neck", "label": "首"},
	{"at": "head/tail", "bone": "head", "label": "頭"},
	{"at": "upper_arm.L/tail", "bone": "upper_arm.L", "label": "左ひじ"},
	{"at": "forearm.L/tail", "ik": ["upper_arm.L", "forearm.L"], "bone": "forearm.L", "label": "左手首"},
	{"at": "hand.L/tail", "bone": "hand.L", "label": "左手"},
	{"at": "upper_arm.R/tail", "bone": "upper_arm.R", "label": "右ひじ"},
	{"at": "forearm.R/tail", "ik": ["upper_arm.R", "forearm.R"], "bone": "forearm.R", "label": "右手首"},
	{"at": "hand.R/tail", "bone": "hand.R", "label": "右手"},
	{"at": "thigh.L/tail", "bone": "thigh.L", "label": "左ひざ"},
	{"at": "shin.L/tail", "ik": ["thigh.L", "shin.L"], "bone": "shin.L", "label": "左足首"},
	{"at": "foot.L/tail", "bone": "foot.L", "label": "左つま先"},
	{"at": "thigh.R/tail", "bone": "thigh.R", "label": "右ひざ"},
	{"at": "shin.R/tail", "ik": ["thigh.R", "shin.R"], "bone": "shin.R", "label": "右足首"},
	{"at": "foot.R/tail", "bone": "foot.R", "label": "右つま先"},
]

## 服のひな形: [名前, [部品…]]。kind = body (胴と脚。sleeve でそでつき) / arm (腕だけ) / skirt (すそ)。
## 縦の目盛り: 0 あご・1 肩・2 くびれ・3 股・4 ひざ・5 足首・6 地面。腕の目盛り: 0 肩・1 ひじ・2 手首・3 指先。
## thick・flare は身長の 100 分の 1 が単位。rank = 重ねる順 (大きいほど上)
const CLOTHES := [
	["半そでシャツ", [{"kind": "body", "from": 0.8, "to": 2.9, "thick": 1.0, "flare": 0.3, "sleeve": 0.6, "sleeve_flare": 0.3, "rank": 2, "color": "#f4f1ea"}]],
	["長そでシャツ", [{"kind": "body", "from": 0.8, "to": 2.9, "thick": 1.0, "flare": 0.3, "sleeve": 2.0, "sleeve_flare": 0.3, "rank": 2, "color": "#f4f1ea"}]],
	["ズボン", [{"kind": "body", "from": 2.1, "to": 5.0, "thick": 1.0, "flare": 0.4, "rank": 1, "color": "#3b4a6b"}]],
	["半ズボン", [{"kind": "body", "from": 2.1, "to": 3.7, "thick": 1.0, "flare": 0.5, "rank": 1, "color": "#3b4a6b"}]],
	["スカート", [{"kind": "skirt", "from": 2.1, "to": 3.8, "thick": 0.8, "flare": 5.0, "follow": 0.8, "rank": 3, "color": "#8a3b4a"}]],
	["ワンピース", [
		{"name": "ワンピース (上)", "kind": "body", "from": 0.8, "to": 2.3, "thick": 1.0, "flare": 0.0, "sleeve": 0.5, "sleeve_flare": 0.4, "rank": 3, "color": "#3f6b8a"},
		{"name": "ワンピース (すそ)", "kind": "skirt", "from": 2.1, "to": 4.5, "thick": 1.0, "flare": 6.0, "follow": 0.8, "rank": 3, "color": "#3f6b8a"}]],
	["上着", [{"kind": "body", "from": 0.7, "to": 3.0, "thick": 2.2, "flare": 0.6, "sleeve": 2.0, "sleeve_flare": 0.4, "rank": 4, "color": "#2b2b33"}]],
	["コート", [
		{"name": "コート (上)", "kind": "body", "from": 0.7, "to": 2.4, "thick": 2.2, "flare": 0.0, "sleeve": 2.0, "sleeve_flare": 0.4, "rank": 4, "color": "#5a4a3a"},
		{"name": "コート (すそ)", "kind": "skirt", "from": 2.2, "to": 4.6, "thick": 2.4, "flare": 3.0, "follow": 0.7, "rank": 4, "color": "#5a4a3a"}]],
	["靴下", [{"kind": "body", "from": 4.4, "to": 6.0, "thick": 0.2, "flare": 0.0, "rank": 0, "color": "#f4f1ea"}]],
	["靴", [{"kind": "body", "from": 4.9, "to": 6.0, "thick": 0.9, "flare": 0.0, "rank": 2, "color": "#5a3a2a"}]],
	["ブーツ", [{"kind": "body", "from": 4.2, "to": 6.0, "thick": 1.0, "flare": 0.0, "rank": 2, "color": "#3a2a22"}]],
	["手袋", [{"kind": "arm", "from": 1.9, "to": 3.0, "thick": 0.5, "flare": 0.0, "rank": 2, "color": "#f4f1ea"}]],
]

## 輪郭をつまむ: 部品の番号 (Mesher.PartOf) → 回りの骨と、変える体型の数値 (w = 横幅の向き、d = 前後の向き、len = 骨に沿う向き)
const SHAPE_PARTS := {
	1: {"bone": "head", "w": "head_w", "d": "head_d", "len": "heads"},
	2: {"bone": "upper_arm.L", "w": "arm_thick", "d": "arm_thick", "len": "arm"},
	3: {"bone": "forearm.L", "w": "arm_thick", "d": "arm_thick", "len": "arm"},
	4: {"bone": "hand.L", "w": "hand", "d": "hand", "len": "hand"},
	5: {"bone": "upper_arm.R", "w": "arm_thick", "d": "arm_thick", "len": "arm"},
	6: {"bone": "forearm.R", "w": "arm_thick", "d": "arm_thick", "len": "arm"},
	7: {"bone": "hand.R", "w": "hand", "d": "hand", "len": "hand"},
	8: {"bone": "thigh.L", "w": "leg_thick", "d": "leg_thick", "len": "leg"},
	9: {"bone": "shin.L", "w": "leg_thick", "d": "leg_thick", "len": "leg"},
	10: {"bone": "foot.L", "w": "foot", "d": "foot", "len": "foot"},
	11: {"bone": "thigh.R", "w": "leg_thick", "d": "leg_thick", "len": "leg"},
	12: {"bone": "shin.R", "w": "leg_thick", "d": "leg_thick", "len": "leg"},
	13: {"bone": "foot.R", "w": "foot", "d": "foot", "len": "foot"},
}

## 髪のひな形。長さ: 0 = 頭のてっぺん、1 = あご、2 = くびれ、3 = ひざ、4 = 地面
const HAIRS := {
	"ショート": {"vol": 0.045, "puff": 0.01, "bangs": 0.38, "bangs_w": 52.0, "side": 0.62, "back": 0.74, "tips": 0.5, "curl": 0.6, "gloss": 0.7},
	"ボブ": {"vol": 0.05, "puff": 0.025, "bangs": 0.42, "bangs_w": 55.0, "side": 0.92, "back": 0.98, "tips": 0.3, "curl": 0.7, "gloss": 0.7},
	"ロング": {"vol": 0.05, "puff": 0.02, "bangs": 0.42, "bangs_w": 55.0, "side": 1.3, "back": 1.9, "tips": 0.4, "curl": 0.3, "gloss": 0.7},
}
const HAIR_UI := [
	["vol", "ボリューム", 0.02, 0.12, 0.005, "頭からどれだけ浮かせるか (頭の高さが単位)"],
	["puff", "横と後ろのふくらみ", 0.0, 0.1, 0.005, "横と後ろだけ、さらに厚く"],
	["bangs", "前髪の長さ", 0.1, 0.8, 0.01, "頭のてっぺんから。0.58 あたりで目にかかります"],
	["bangs_w", "前髪の幅 (度)", 15.0, 80.0, 1.0, "正面から左右へ何度までを前髪にするか。顔の見える幅が決まります"],
	["side", "横の髪の長さ", 0.3, 3.0, 0.01, "1 = あご、2 = くびれ、3 = ひざ"],
	["back", "後ろ髪の長さ", 0.3, 4.0, 0.01, "1 = あご、2 = くびれ、3 = ひざ、4 = 地面"],
	["tips", "毛先のギザギザ", 0.0, 1.0, 0.01, "0 = ぱっつん"],
	["curl", "毛先の内巻き", 0.0, 1.0, 0.01, "下の端を内へすぼめます。0 だと箱のように見えます"],
	["gloss", "つやの帯の高さ", 0.0, 1.0, 0.01, "頭のまわりに出る明るい帯。0 = なし"],
]

var hair := {"on": false, "color": Color("#5a3e2e"), "vol": 0.05, "puff": 0.025, "bangs": 0.42, "bangs_w": 42.0, "side": 0.92, "back": 0.98, "tips": 0.3, "curl": 0.7, "gloss": 0.7,
		"locks": [], "lock_sep": false}                 ## locks = ペンで描いた房 (1 本 = PackedFloat32Array [x, y, z, 半径] × 点の数。頭の枠で)
var hair_pen := {"on": true, "size": 3, "taper": 0.0, "mirror": false}   ## 髪を描くペン (太さは画素)
var _stroke_cut := false         ## 引いている線が消しゴム (右ボタン) か
var hair_mode := false           ## 「髪」タブを開いていて、ペンが入っているあいだ: 絵の上に引いた線が髪の房になる
var _hair_tab := -1
var _stroke := PackedVector2Array()   ## 引いている最中の線 (画素)
var _stroke_v: DotView
var _stroking := false
var _head_h := 0.3
var core
var shape_on := true             ## 「体型」タブを開いているあいだ、絵の上で輪郭をつまんで形を変える
var shape_mode := false
var _shape := {}                 ## つまんでいる最中の覚え書き
var _lim := {}                   ## 体型の数値の範囲
var _plabel := {}                ## 体型の数値の名前
var garments: Array = []         ## 着ているもの (下に着るものから)。{name, kind, color, from, to, thick, flare, sleeve, sleeve_flare, follow, rank}
var pin_feet := true             ## 腰を動かしても、足は地面に残す
var keep_feet := true            ## 脚を動かしても、足の裏の向きを保つ
var mirror_edit := false         ## 左右いっしょに動かす
var auto_arms := true            ## 腕が胴や服に入ったら、入らなくなるまで開く
var body := {}
var auto_heads := true
var res := 72.0
var view := {"w": 64, "h": 64, "px": 56.0, "yaw": 0.0, "pitch": 0.0, "cover": 0.5, "smooth": 1, "ss": 3, "margin": 2}
var style := {}
var poses: Array = []            ## [{name, rots: {骨: Quaternion}, root: Vector3}]
var pose_i := 0
var ground := true
var show_handles := true
var snap_yaw := true
var joints := {}
var bone_parent := {}
var file_path := ""

var pix: DotView
var pix2: DotView                ## 横から見た絵 (奥行きがそのまま左右に見える。ここでも点をつまめる)
var side_view := true
var _aimed: DotView              ## いま、点の位置やつまむ向きを計算している窓
var _tabs_l: TabContainer
const PALETTE0 := ["#2a2030", "#ffffff", "#c8323c", "#f0c040", "#3f8a4a", "#3b6fb0", "#e8a0a8", "#6b3f36"]
## お手本 (似せたいドット絵)。sheet = 読んだ絵まるごと、rect = そのうち使う範囲、cell = 切り出した 1 体、off = 置く場所のずれ (画素)
## mode: 0 かくす・1 すかして重ねる・2 ちがう画素を光らせる・3 お手本だけ
var ref := {"path": "", "sheet": null, "rect": Rect2i(), "cell": null, "off": Vector2i.ZERO, "mode": 1, "alpha": 0.5, "gw": 0, "gh": 0}
var ref_mode := false            ## 「お手本」タブを開いているあいだ: 絵の上をつまむと お手本が動く
var ref_stats := {}              ## {same, total, shape}: お手本と同じ色の画素・比べた画素・形がちがう画素
var _ref_tab := -1
var _ref_view: DotView
var _ref_sel := false
var _ref_from := Vector2.ZERO
var _ref_to := Vector2.ZERO
var _ref_moving := false
var _ref_move := Vector2.ZERO
var _ref_move0 := Vector2i.ZERO
var _ref_img: Image              ## お手本を紙の大きさに置いたもの
var _ref_tex: ImageTexture
var _diff_tex: ImageTexture
var _ref_back := 1               ## R キーで「お手本だけ」から戻る先
## ドット絵から作った立体 (試作。scripts/solid.gd)。solid_on のあいだ、絵は体のモデルではなく この立体から描く
var solid: DotSolid = null
var solid_on := false
var _paint_yaw := NAN            ## 塗っている絵の向き (横の絵に塗っているとき。NAN = 真ん中の絵)
var _paint_v: DotView = null     ## ペンの形を出す窓
var _solid_tab := -1
var part_edit := false           ## 「立体」タブで、正面の絵に部品を塗っているあいだ
var part_sel := 1                ## 塗る部品
var _part_painting := false
var _sdrag := 0                  ## つまんでいる部品 (立体)
var _sdrag_yaw := 0.0
var _sdrag_last := Vector2.ZERO
var _side_img: Image             ## 右の「横から」の絵 (立体のとき。色を拾うのに使う)
var palette: Array = []          ## 絵の下に並ぶ色
var recent: Array = []           ## 最近使った色
var _pal_box: HFlowContainer
var _mat_box: VBoxContainer
## target: 0 = 体の面に塗る (向きを変えてもついてくる)・1 = この絵の画素をじかに直す (この向き・このポーズだけ)。clear = 画素を透明にする
var paint := {"color": Color("#2a2030"), "color2": Color("#ffffff"), "size": 1, "flat": false, "mirror": false, "kind": 0, "target": 0, "clear": false}   ## kind: 0 色・1 / 2 明るく・-1 / -2 暗く   ## ペン
var paint_mode := false          ## 「塗る」タブを開いているあいだ: 真ん中の絵の上は、つまむのではなく塗る
var _paint_tab := -1
const DOT_TOOLS := ["えんぴつ", "消しゴム", "バケツ", "線", "四角 (枠)", "四角 (ぬり)", "スポイト"]
var dot_tool := 0                ## ドット絵の道具 (立体・「この絵の画素」に描くとき)
var dot_perfect := true          ## えんぴつ (太さ 1): かどの よぶんな 1 画素を置かない
var _pp_last := Vector2i(-999, -999)     ## えんぴつ: さいごに置いた画素
var _pp_pending = null                   ## えんぴつ: 置くのを 1 つ待っている画素
var _dshape := {}                        ## 線・四角を引いている最中 {a, b, erase}
var _painting := 0               ## 塗っている最中のボタン (左 = 塗る、右 = 消す)
var _paint_last := Vector2.ZERO
var _paint_hover := Vector2(-99, -99)
var _paint_cache = null          ## core.GetPaint() の写し (元に戻す・保存に使う。塗ったら捨てる)
var _last_img: Image
var _w := {}                     ## 名前 → 部品 (スライダーなど)
var _syncing := false
var _d_body := true
var _d_pose := true
var _d_view := true
var _idle := 0.0
var _info: Label
var _hint: Label
var _pose_list: ItemList
var _sel := -1                   ## 選んでいる点 (HANDLES の番号)
var _gsel := -1                  ## 選んでいる服
var _glist: ItemList
var _no_ground := false
var _hover := -1
var _drag := -1
var _turning := false
var _turn_moved := 0.0
var _ground_off := 0.0
var _undo: Array = []
var _redo: Array = []
var _strip: TextureRect
var _prev: Array = []
var _prev_bg := Color("#6a8f5a")
var _mesh3d: MeshInstance3D
var _cam3d: Camera3D
var _tabs_r: TabContainer
var _pk: Node
var _pk_tex: TextureRect
var _pk_status: Label
var _pk_key := ""
var _pk_auto := false
var _dialog: FileDialog
var _dialog_cb: Callable
var _cfg := ConfigFile.new()
var _selftest: RefCounted


func _ready() -> void:
	theme = XP.make_theme()
	_cfg.load(CFG)
	core = load("res://core/DotCore.cs").new()
	for p in core.ParamList():
		body[p.key] = p.def
	body.merge(core.ForHeads(3.0), true)
	body["sex"] = 0.5
	style = default_style()
	palette = PALETTE0.map(func(c): return Color(c))
	poses = [make_pose("立ち", Poses.named("立ち", body.arm_angle, Poses.hang_for(body.heads)))]
	_pk = load("res://scripts/penink.gd").new()
	add_child(_pk)
	_pk.drawn.connect(_on_penink)
	_pk.status.connect(func(t: String): _pk_status.text = t)
	_build_ui()
	_sync_all()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--selftest":
		_selftest = load("res://tests/selftest.gd").new()      # 持っておかないと、待っているあいだに消える
		_selftest.run(self, args[1])
	elif args.size() >= 1 and args[0].ends_with(".json"):
		load_doc(args[0])
	await get_tree().process_frame
	fit_all()


static func default_style() -> Dictionary:
	return {
		"ramp": [Color("#b9806f"), Color("#d9a088"), Color("#f3cfb2"), Color("#fcebda")],   # 濃い影・影・基本・明るい
		"line": Color("#6b3f36"), "shades": 3,
		"shadow": 0.05, "light": 0.15, "light_angle": -37.0, "light_front": 0.65,
		"line_mode": 1, "inner": true, "one_line": false, "line_color": Color("#1a1420"),
		"despeckle": true, "rim": 0, "rim_shadow": true,
	}


static func make_pose(name: String, p: Dictionary) -> Dictionary:
	return {"name": name, "rots": Poses.to_quats(p), "root": p.get("root", Vector3.ZERO)}


# --- 作り直し・描き直し ---------------------------------------------------------------- #

func mark(what := "view") -> void:
	if what == "body":
		_d_body = true
	elif what == "pose":
		_d_pose = true
	_d_view = true
	_idle = 0.0
	set_process(true)


func _process(dt: float) -> void:
	var rebuilt := false
	if _d_body:
		_d_body = false
		_d_pose = true
		rebuilt = true
		core.SetHair(hair)
		var info: Dictionary = core.Build(body, res, garment_specs(garments))
		bone_parent.clear()
		for b in core.Bones():
			bone_parent[b.name] = b.parent
		_head_h = info.head_h
		_info.text = "頂点 %d・三角形 %d・作るのに %d ミリ秒" % [info.verts, info.tris, int(info.seconds * 1000.0)]
	if _d_pose:
		_d_pose = false
		apply_pose()
		if rebuilt and auto_arms:
			fix_arms()
	if _d_view:
		_d_view = false
		if pix2.visible and solid_on and solid != null:
			var y2 := fposmod(view.yaw + 90.0, 360.0)
			var im2: Image = _solid_img(y2)
			_apply_fix(im2, y2)
			_side_img = im2
			pix2.set_image(im2)
		elif pix2.visible:
			core.SetView(_view_of(pix2))
			core.SetStyle(style_dict())
			pix2.set_image(core.Render())
		_last_img = render_now()
		pix.set_image(_last_img)
		_aimed = pix
		_ref_refresh()
		_fix_label()
		if _w.has("spaint_info"):
			_w["spaint_info"].text = "描いた画素: %d・けずった画素: %d%s" % [solid.adds.filter(func(a): return a != null and Color(a[4]).a > 0.5).size() if solid != null else 0, solid.adds.filter(func(a): return a != null and Color(a[4]).a < 0.5).size() if solid != null else 0, ("・前の版で面に塗った所: %d" % solid.spaint.size()) if (solid != null and not solid.spaint.is_empty()) else ""]
		if _w.has("paint_info"):
			_w["paint_info"].text = "塗った点: %d・じかに直した画素 (この向き): %d" % [core.PaintCount(), _fix_of(view.yaw).size()]
		_update_3d()
	# 手を止めてから: 見え方・8 方向・penInk
	_idle += dt
	if _idle > 0.18:
		_update_previews()
		if _pk_auto and _pk.ready_ok and _pk_key == _body_key():
			_pk.draw(penink_request())
		set_process(false)


func cur() -> Dictionary:
	return poses[pose_i]


func apply_pose() -> void:
	var p := cur()
	_ground_off = 0.0
	core.SetPose(p.rots, p.root)
	if ground and not _no_ground:
		_ground_off = -core.LowestY()
		core.SetPose(p.rots, p.root + Vector3(0, _ground_off, 0))
	joints = core.Joints()


func style_dict() -> Dictionary:
	return make_style(style, mats_of(garments, hair), core.PaintColors())


## 色の並び: 服、そのあとに髪 (中身の素材の番号と同じ順)
static func mats_of(gs: Array, h: Dictionary) -> Array:
	return gs + ([h] if h.get("on", false) or not h.get("locks", []).is_empty() else [])


static func hair_named(name: String) -> Dictionary:
	var h := {"on": HAIRS.has(name), "color": Color("#5a3e2e"), "locks": [], "lock_sep": false}
	h.merge(HAIRS.get(name, HAIRS["ボブ"]))
	return h


func set_hair(name: String) -> void:
	var col: Color = hair.color
	var locks: Array = hair.locks
	var ll: bool = hair.get("lock_sep", false)
	var rp = hair.get("ramp")
	hair = hair_named(name)
	hair.color = col
	if rp != null:
		hair["ramp"] = rp
	hair.lock_sep = ll
	hair.locks = locks           # ペンで描いた分は、ひな形を変えても残す
	_sync_hair_ui()
	mark("body")


func _sync_hair_ui() -> void:
	if not _w.has("hair_color"):
		return
	_sync("hair_color", hair.color)
	if _w.has("hp_lines"):
		_w["hp_lines"].set_pressed_no_signal(hair.get("lock_sep", false))
	for it in HAIR_UI:
		_sync("h_" + it[0], hair[it[0]])
		_w["h_" + it[0]].get_parent().visible = hair.on
	_sync_mat_ui()


## 色の段: [濃い影, 影, 基本, 明るい, 線]。影は暗く・鮮やかに・色みをずらす (白や灰色の影は青みへ)
static func ramp_of(base: Color) -> Array:
	var h := base.h
	var sat := base.s
	var v := base.v
	if sat < 0.08:
		return [Color.from_hsv(0.62, 0.22, v * 0.66), Color.from_hsv(0.62, 0.13, v * 0.82), base,
				Color.from_hsv(0.12, 0.02, minf(1.0, v * 1.08 + 0.08)), Color.from_hsv(0.64, 0.3, v * 0.36)]
	return [Color.from_hsv(fposmod(h - 0.035, 1.0), clampf(sat * 1.3 + 0.05, 0, 1), v * 0.62),
			Color.from_hsv(fposmod(h - 0.018, 1.0), clampf(sat * 1.15 + 0.03, 0, 1), v * 0.8), base,
			Color.from_hsv(fposmod(h + 0.012, 1.0), sat * 0.7, minf(1.0, v * 1.08 + 0.06)),
			Color.from_hsv(fposmod(h - 0.05, 1.0), clampf(sat * 1.2 + 0.1, 0, 1), v * 0.38)]


## paints = 塗りに使っている色 (core.PaintColors())。色ごとに、服と同じ決まりで段を作って渡す
static func make_style(st: Dictionary, gs: Array, paints: Array = []) -> Dictionary:
	var n: int = clampi(st.shades, 2, 4)
	var steps := PackedFloat32Array()
	var hi: float = 1.0 - st.light
	var pick := func(r: Array) -> Array:
		return [r[1], r[2]] if n == 2 else ([r[1], r[2], r[3]] if n == 3 else [r[0], r[1], r[2], r[3]])
	match n:
		2:
			steps = [st.shadow]
		3:
			steps = [st.shadow, hi]
		_:
			steps = [st.shadow - 0.45, st.shadow, hi]
	var mats := [{"ramp": pick.call(st.ramp), "line": st.line}]
	for g in gs:
		var r: Array = g.ramp if g.has("ramp") else ramp_of(g.color)     # ramp = 自分で決めた色の段 (無ければ色から作る)
		mats.append({"ramp": pick.call(r), "line": r[4]})
	var pr := []
	for c in paints:
		pr.append({"color": c, "ramp": pick.call(ramp_of(c))})
	var a := deg_to_rad(st.light_angle)
	var f: float = clampf(st.light_front, 0.0, 0.98)
	var k := sqrt(1.0 - f * f)
	return {
		"mats": mats, "steps": steps, "paints": pr,
		"light": Vector3(sin(a) * k, cos(a) * k, f),
		"line_mode": st.line_mode, "inner": st.inner, "one_line": st.one_line, "line_color": st.line_color,
		"despeckle": st.despeckle, "rim": st.rim, "rim_shadow": st.rim_shadow,
	}


## 服の並び → 中身 (core.Build) に渡す数値
static func garment_specs(gs: Array) -> Array:
	var out := []
	for g in gs:
		out.append({"kind": g.kind, "from": g.from, "to": g.to, "thick": g.thick, "flare": g.get("flare", 0.0),
				"sleeve": g.get("sleeve", 0.0), "sleeve_flare": g.get("sleeve_flare", 0.0), "follow": g.get("follow", 0.8)})
	return out


## ひな形の服 (CLOTHES の名前) → 服の並びに足す部品
static func clothes_named(name: String) -> Array:
	var out := []
	for c in CLOTHES:
		if c[0] != name:
			continue
		for piece in c[1]:
			var g: Dictionary = piece.duplicate()
			g["name"] = piece.get("name", name)
			g["color"] = Color(piece.color)
			for k in ["flare", "sleeve", "sleeve_flare"]:
				if not g.has(k):
					g[k] = 0.0
			if not g.has("follow"):
				g["follow"] = 0.8
			out.append(g)
	return out


## 重ねる順 (rank) を守って足す。足した場所の番号を返す
static func wear(gs: Array, pieces: Array) -> int:
	var at := -1
	for g in pieces:
		at = gs.size()
		for i in gs.size():
			if int(gs[i].get("rank", 2)) > int(g.get("rank", 2)):
				at = i
				break
		gs.insert(at, g)
	return at


func view_dict(yaw: float) -> Dictionary:
	return {"w": view.w, "h": view.h, "px": view.px, "yaw": yaw, "pitch": view.pitch, "floor": view.h - view.margin,
			"cover": view.cover, "smooth": view.smooth, "ss": view.ss}


## その窓の向き: 真ん中の絵 = いまの向き。横の絵 = そこから 90° 横 (見下ろさない)
func _view_of(v: DotView) -> Dictionary:
	if v != null and v == pix2:
		var d := view_dict(fposmod(view.yaw + 90.0, 360.0))
		d["pitch"] = 0.0
		return d
	return view_dict(view.yaw)


## これから使う窓を決める (点の位置・つまむ向きは、その窓の向きで計算する)。使い終わったら _aim(pix) で戻す
func _aim(v: DotView) -> void:
	_aimed = v
	core.SetView(_view_of(v))


func _redraw() -> void:
	pix.queue_redraw()
	pix2.queue_redraw()


func fit_all() -> void:
	pix.fit()
	# 横の絵は、真ん中の絵と同じ倍率で (幅が狭いので、絵の左右の余白は切れる。人は真ん中に写る)
	pix2.zoom = pix.zoom
	pix2.pan = Vector2.ZERO
	pix2.queue_redraw()


func render_now(yaw := NAN) -> Image:
	var y: float = view.yaw if is_nan(yaw) else yaw
	core.SetView(view_dict(y))
	core.SetStyle(style_dict())
	var img: Image = _solid_img(y) if (solid_on and solid != null) else core.Render()
	_apply_fix(img, y)
	return img


func _part_editing() -> bool:
	return solid_on and solid != null and part_edit and _tabs_l != null and _tabs_l.current_tab == _solid_tab


## 立体を、いまのポーズ (ポーズごとの sp = 部品の回転、sroot = 全体のずれ) で描く。部品を塗っているあいだは 立ちで
func _solid_img(yaw: float) -> Image:
	var p := cur()
	if _part_editing():
		solid.pose = {}
		solid.root = Vector3.ZERO
	else:
		solid.pose = p.get("sp", {})
		solid.root = p.get("sroot", Vector3.ZERO)
	return solid.render(yaw)


## 立体の、つまむ所 (部品の先) を探す。無ければ 0
func _solid_pick(px: Vector2, yaw: float) -> int:
	var best := 2.6
	var part := 0
	for hd in solid.handles(yaw):
		var d: float = hd.tip.distance_to(px)
		if d < best:
			best = d
			part = hd.part
	return part


func solid_preset(name: String) -> void:
	if solid == null:
		return
	push_undo()
	var pr: Dictionary = solid.preset(name)
	cur()["sp"] = pr.pose
	cur()["sroot"] = pr.root
	mark()


func _part_paint(px: Vector2) -> void:
	if solid.set_part(int(floor(px.x)), int(floor(px.y)), part_sel):
		mark()


func _draw_solid_handles(v: DotView) -> void:
	var yaw := fposmod(view.yaw + (90.0 if v == pix2 else 0.0), 360.0)
	if _part_editing():
		# 部品の色分け (正面の絵の上に)
		if v == pix and DotSolid.key_of(view.yaw) == 0:
			for y in solid.h:
				for x in solid.w:
					var p: int = solid.part_at(x, y)
					if p > 0 and solid.pics[0].get_pixel(x, y).a > 0.5:
						v.draw_rect(Rect2(v.to_screen(Vector2(x, y)), Vector2(v.zoom, v.zoom)), Color(Color(DotSolid.PART_COLORS[p]), 0.6))
		return
	if not show_handles:
		return
	for hd in solid.handles(yaw):
		var a: Vector2 = v.to_screen(hd.pivot)
		var b: Vector2 = v.to_screen(hd.tip)
		v.draw_line(a, b, Color(0, 0, 0, 0.3), 1.0)
		v.draw_circle(a, 2.5, Color(0, 0, 0, 0.6))
		if hd.part == _sdrag:
			v.draw_circle(b, 8.0, Color(1, 1, 1, 0.95))
		v.draw_circle(b, 5.5, Color(0, 0, 0, 0.75))
		v.draw_circle(b, 4.5, Color(DotSolid.PART_COLORS[hd.part]))


func _update_previews() -> void:
	var img := render_now()
	for i in _prev.size():
		var z: int = i + 1
		var big := Image.create_empty(img.get_width() * z, img.get_height() * z, false, Image.FORMAT_RGBA8)
		big.fill(_prev_bg)
		var s := img.duplicate() as Image
		s.resize(img.get_width() * z, img.get_height() * z, Image.INTERPOLATE_NEAREST)
		big.blend_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), Vector2i.ZERO)
		_prev[i].texture = ImageTexture.create_from_image(big)
		_prev[i].custom_minimum_size = big.get_size()
	if _strip and _strip.is_visible_in_tree():
		var sheet := Image.create_empty(view.w * 4, view.h * 2, false, Image.FORMAT_RGBA8)
		sheet.fill(_prev_bg)
		for d in 8:
			var im := render_now(d * 45.0)
			sheet.blend_rect(im, Rect2i(0, 0, view.w, view.h), Vector2i((d % 4) * view.w, (d / 4) * view.h))
		_strip.texture = ImageTexture.create_from_image(sheet)
		_strip.custom_minimum_size = Vector2(sheet.get_size()) * (2 if view.w <= 72 else 1)
		render_now()     # つまむ点の位置は、いまの向きで


func _update_3d() -> void:
	if _mesh3d == null or not _mesh3d.is_visible_in_tree():
		return
	var h: float = body.height
	if solid_on and solid != null:
		# ドット絵から作った立体: だ円の板を積んだ形そのもの (足の下が床)
		solid.ensure()
		var p0 := cur()
		solid.pose = {} if _part_editing() else p0.get("sp", {})
		solid.root = Vector3.ZERO if _part_editing() else p0.get("sroot", Vector3.ZERO)
		_mesh3d.mesh = solid.make_mesh(h / maxf(float(solid._bot - solid._top + 1), 1.0), view.yaw)
		_mesh3d.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		_mesh3d.mesh = core.MakeMesh()
		_mesh3d.material_override.cull_mode = BaseMaterial3D.CULL_BACK
	_mesh3d.rotation = Vector3(0, deg_to_rad(view.yaw), 0)
	var p := deg_to_rad(view.pitch)
	_cam3d.size = h * 1.25
	_cam3d.position = Vector3(0, h * 0.5, 0) + Vector3(0, sin(p), cos(p)) * 6.0
	_cam3d.look_at(Vector3(0, h * 0.5, 0))


# --- 輪郭をつまんで形を変える ---------------------------------------------------------- #

## その窓の画素 px に写っている部品 ({part, name, rest, mat}。無ければ part = -1)
func _pick_part(px: Vector2, v: DotView) -> Dictionary:
	if v == pix2:
		# 中身が覚えているのは最後に描いた絵 (真ん中) なので、横の絵を描き直して調べ、真ん中に戻す
		core.SetView(_view_of(pix2))
		core.Render()
		var d: Dictionary = core.Pick(int(floor(px.x)), int(floor(px.y)))
		render_now()
		return d
	return core.Pick(int(floor(px.x)), int(floor(px.y)))


## つまんだ場所から、どの骨のまわりの・どの数値を変えるかを決める。体に当たっていなければ {}
func shape_target(px: Vector2, v: DotView) -> Dictionary:
	var info := _pick_part(px, v)
	var part: int = info.part
	if part < 0:
		return {}
	var t := {"part": part, "px": px, "view": v, "lock": "", "gi": -1}
	if part == 14:
		# すそ: その服の「広がり」
		var gi: int = int(info.get("mat", 0)) - 1
		if gi < 0 or gi >= garments.size() or garments[gi].kind != "skirt":
			return {}
		t.merge({"bone": "hips", "w": "", "d": "", "len": "", "gi": gi, "start_flare": float(garments[gi].get("flare", 0.0))})
	elif part == 0:
		# 胴: 高さで 肩幅・おなか・腰幅。前後の向きは 胴の厚み
		var ry: float = info.rest.y
		var rest := {}
		for b in core.Bones():
			rest[b.name] = b
		var w := "belly"
		if ry >= rest["chest"].origin.y:
			w = "shoulder"
		elif ry < rest["spine"].origin.y:
			w = "hip"
		t.merge({"bone": "spine", "w": w, "d": "depth", "len": ""})
	else:
		t.merge(SHAPE_PARTS[part])
	_aim(v)
	var a3: Vector3 = core.Project(joints[t.bone])
	var b3: Vector3 = core.Project(joints[t.bone + "/tail"])
	var ax: Array = core.Axes()
	_aim(pix)
	var a := Vector2(a3.x, a3.y)
	var dir := Vector2(b3.x, b3.y) - a
	t["len_px"] = maxf(dir.length(), 2.0)
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.UP      # 骨がこちらを向いている (足など) → たてを軸に
	var n := Vector2(-dir.y, dir.x)
	var off := (px - a).dot(n)
	t["dir"] = dir
	t["n"] = n
	t["side"] = signf(off) if absf(off) >= 0.75 else 0.0
	t["off"] = maxf(absf(off), 2.0)
	t["tip"] = (px - a).dot(dir) >= t.len_px * 0.5
	# 画面の「骨に直角な向き」は、その部品の横幅の向きか、前後の向きか
	var n3: Vector3 = ax[0] * n.x - ax[1] * n.y
	var bb: Basis = joints[t.bone + "/basis"]
	t["wide"] = absf(n3.dot(bb.x)) >= absf(n3.dot(bb.z))
	t["start"] = body.duplicate()
	return t


## 骨に直角につまむ = 太さ (輪郭がマウスについてくる)、骨に沿ってつまむ = 長さ
func shape_drag(t: Dictionary, px: Vector2) -> void:
	var d: Vector2 = px - t.px
	if t.lock == "":
		if d.length() < 1.5:
			return
		t.lock = "perp" if (absf(d.dot(t.n)) >= absf(d.dot(t.dir)) or t.len == "") else "along"
		if t.side == 0.0:
			t.side = signf(d.dot(t.n))
	if t.lock == "perp":
		var p: float = d.dot(t.n) * t.side
		if t.gi >= 0:
			garments[t.gi].flare = clampf(snappedf(t.start_flare + p * 100.0 / view.px, 0.1), 0.0, 12.0)
			if t.gi == _gsel:
				_sync_wear_ui()
			mark("body")
			return
		var key: String = t.w if t.wide else t.d
		_set_body(key, t.start[key] * clampf((t.off + p) / t.off, 0.3, 3.0))
	else:
		var q: float = d.dot(t.dir) * (1.0 if t.tip else -1.0)
		var f := clampf((t.len_px + q) / t.len_px, 0.3, 3.0)
		_set_body(t.len, t.start[t.len] / f if t.len == "heads" else t.start[t.len] * f)


func _set_body(key: String, x: float) -> void:
	if key == "" or not body.has(key):
		return
	x = clampf(x, _lim[key].min, _lim[key].max)
	if is_equal_approx(body[key], x):
		return
	body[key] = x
	_sync("b_" + key, x)
	mark("body")


## つまむと何が変わるか (下の行に出す)
func shape_hint(t: Dictionary) -> String:
	if t.is_empty():
		return "体の輪郭をつまむと形が変わります (骨に直角 = 太さ、骨に沿って = 長さ)。何もない所を左右につまむと向きが回ります"
	if t.gi >= 0:
		return "%s — 横につまむ = すその広がり" % garments[t.gi].name
	var key: String = t.w if t.wide else t.d
	var out := "つまむ: 骨に直角 = %s" % _plabel.get(key, key)
	if t.len != "":
		out += "、骨に沿って = %s" % _plabel.get(t.len, t.len)
	return out + " (右の「横から」の絵でつまむと、前後の厚み)"


# --- 塗る ------------------------------------------------------------------------------ #

func _paint_data() -> Dictionary:
	if _paint_cache == null:
		_paint_cache = core.GetPaint()
	return _paint_cache


## 絵の上の a から b まで塗る (画素の座標)。erase = 消しゴム
func _pyaw() -> float:
	return view.yaw if is_nan(_paint_yaw) else _paint_yaw


## --- ドット絵の道具 (画素を 1 つずつ置く) ---

func _dot_mode() -> bool:
	return (solid_on and solid != null) or int(paint.get("target", 0)) == 1


func _dot_w() -> int:
	return solid.w if (solid_on and solid != null) else int(view.w)


## a から b までの画素 (ブレゼンハム: よぶんな画素の無い 1 画素の線)
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


## ペンの太さぶんの画素 (c のまわり)
func _brush(c: Vector2i) -> Array:
	var sz := int(paint.size)
	if sz <= 1:
		return [c]
	var out := []
	var half := sz * 0.5
	var ctr := Vector2(c) + (Vector2(0.5, 0.5) if sz % 2 == 1 else Vector2.ZERO)
	for y in range(int(floor(ctr.y - half)), int(ceil(ctr.y + half)) + 1):
		for x in range(int(floor(ctr.x - half)), int(ceil(ctr.x + half)) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(ctr) <= half:
				out.append(Vector2i(x, y))
	return out


## 画素をまとめて置く (col.a = 0 なら消す)。どこへ入るか:
##  「この絵の画素」= ドット直し / 立体の正面 (立ち)・「その向きの絵を決める」= その向きの絵 / ほか = 立体に画素を置く (けずる)
func dot_plot(cells: Array, col: Color) -> int:
	var changed := 0
	var seen := {}
	var all := []
	for cell in cells:
		for mi in (2 if paint.mirror else 1):
			var q: Vector2i = cell if mi == 0 else Vector2i(_dot_w() - 1 - cell.x, cell.y)
			if not seen.has(q):
				seen[q] = true
				all.append(q)
	if int(paint.get("target", 0)) == 1 or not (solid_on and solid != null):
		var f := _fix_of(_pyaw(), true)
		var o := _fix_origin()
		for q in all:
			if q.x < 0 or q.y < 0 or q.x >= int(view.w) or q.y >= int(view.h):
				continue
			var k: Vector2i = q - o
			if not f.has(k) or f[k] != col:
				f[k] = col
				changed += 1
	else:
		var key := DotSolid.key_of(_pyaw())
		# ふつうは どの向きでも 画素を置く。絵そのものを直すのは「その向きの絵を決める」のときだけ:
		#  正面の絵を直すと 立体を作り直すので (線の色・部品・顔の見分けが変わる)、1 画素描いただけで 別の所の画素まで変わることがある
		var decide: bool = key >= 0 and not solid.is_posed() and int(paint.get("solid_mode", 0)) == 1
		for q in all:
			if (solid.set_px(key, q.x, q.y, col) if decide else solid.paint_surface(_pyaw(), q.x, q.y, col)):
				changed += 1
	if changed > 0:
		mark()
	return changed


## 絵の a から b まで、いまの色・太さで線を引く (erase = 消す)
func solid_line(a: Vector2, b: Vector2, erase := false) -> int:
	var col := Color(0, 0, 0, 0) if (erase or paint.get("clear", false)) else Color(paint.color, 1.0)
	var cells := []
	for c in _bres(Vector2i(a.floor()), Vector2i(b.floor())):
		cells.append_array(_brush(c))
	return dot_plot(cells, col)


## バケツ: つながった同じ色の所を塗りつぶす。透明な所は、絵のはしまで つながっていたら塗らない
func dot_fill(cell: Vector2i, col: Color) -> int:
	var img: Image = render_now(_pyaw())
	var w2 := img.get_width()
	var h2 := img.get_height()
	if cell.x < 0 or cell.y < 0 or cell.x >= w2 or cell.y >= h2:
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
			if r.x < 0 or r.y < 0 or r.x >= w2 or r.y >= h2:
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
	return dot_plot(cells, col)


## 線・四角の画素
func _shape_cells(a: Vector2i, b: Vector2i, tool: int) -> Array:
	if tool == 3:
		var out := []
		for c in _bres(a, b):
			out.append_array(_brush(c))
		return out
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	var cells := []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if tool == 5 or x == x0 or x == x1 or y == y0 or y == y1:
				cells.append(Vector2i(x, y))
	return cells


## えんぴつ (太さ 1・かどを消す): 画素を 1 つ おくれて置く。かど (L 字) になる画素は置かない
func _pp_feed(cell: Vector2i, col: Color) -> void:
	if cell == _pp_last or (_pp_pending != null and cell == _pp_pending):
		return
	if _pp_pending != null:
		var pd: Vector2i = _pp_pending
		var corner: bool = (pd.x == _pp_last.x or pd.y == _pp_last.y) and (pd.x == cell.x or pd.y == cell.y) and _pp_last.x != cell.x and _pp_last.y != cell.y
		if not corner:
			dot_plot([pd], col)
			_pp_last = pd
	_pp_pending = cell


func _dot_col(erase: bool) -> Color:
	return Color(0, 0, 0, 0) if (erase or dot_tool == 1 or paint.get("clear", false)) else Color(paint.color, 1.0)


func _dot_press(px: Vector2, button: int) -> void:
	var cell := Vector2i(px.floor())
	var erase := button == MOUSE_BUTTON_RIGHT
	if dot_tool == 6:
		pick_color(px, false)
		return
	if not erase and dot_tool != 1 and not paint.clear:
		use_color(paint.color)
	push_undo()
	if dot_tool == 2:
		var n := dot_fill(cell, _dot_col(erase))
		if n > 0:
			_hint.text = "バケツ: %d 画素" % n
		return
	_painting = button
	_paint_last = px
	if dot_tool >= 3:
		_dshape = {"a": cell, "b": cell, "erase": erase}
		return
	if int(paint.size) <= 1 and dot_perfect:
		dot_plot([cell], _dot_col(erase))
		_pp_last = cell
		_pp_pending = null
	else:
		dot_plot(_brush(cell), _dot_col(erase))


func _dot_drag(px: Vector2) -> void:
	var cell := Vector2i(px.floor())
	var erase := _painting == MOUSE_BUTTON_RIGHT
	if not _dshape.is_empty():
		_dshape.b = cell
		_redraw()
		return
	if int(paint.size) <= 1 and dot_perfect:
		for c in _bres(_pp_last if _pp_pending == null else _pp_pending, cell):
			_pp_feed(c, _dot_col(erase))
		_redraw()
	else:
		var cells := []
		for c in _bres(Vector2i(_paint_last.floor()), cell):
			cells.append_array(_brush(c))
		dot_plot(cells, _dot_col(erase))
	_paint_last = px


func _dot_release() -> void:
	if not _dshape.is_empty():
		dot_plot(_shape_cells(_dshape.a, _dshape.b, dot_tool), _dot_col(_dshape.erase))
		_dshape = {}
	if _pp_pending != null:
		dot_plot([_pp_pending], _dot_col(_painting == MOUSE_BUTTON_RIGHT))
		_pp_pending = null
	_pp_last = Vector2i(-999, -999)


func set_dot_tool(i: int) -> void:
	dot_tool = clampi(i, 0, DOT_TOOLS.size() - 1)
	for k in DOT_TOOLS.size():
		if _w.has("dot_tool_%d" % k):
			_w["dot_tool_%d" % k].set_pressed_no_signal(k == dot_tool)
	_hint.text = "道具: " + DOT_TOOLS[dot_tool]


## いまのお手本 (紙に置いた 1 体) を正面の絵として、立体を作る
func make_solid() -> bool:
	if _ref_img == null:
		_hint.text = "先に、お手本の絵を開いて 1 体を選んでください"
		return false
	push_undo()
	solid = DotSolid.new()
	solid.set_front(_ref_img)
	solid_on = true
	_sync("solid_on", true)
	_sync_solid_ui()
	ref.mode = 0
	_sync("ref_mode", 0)
	mark()
	return true


func _sync_solid_ui() -> void:
	if solid == null:
		return
	_sync("so_head", solid.k_head)
	_sync("so_body", solid.k_body)
	_sync("so_leg", solid.k_leg)
	_sync("so_wrap", solid.wrap)
	_sync("so_joints", solid.joints)
	_sync("so_hip", solid.leg_hidden)
	_sync("so_arm", solid.arm_min)
	_sync("so_shoulder", solid.shoulder_up)
	_sync("so_waist", solid.waist)
	_sync("so_face", solid.face_layer)
	_sync("so_face_min", solid.face_min)
	_sync("so_air", solid.air_thick)
	_sync("so_reach", solid.paint_reach)
	_sync("so_front_reach", solid.front_reach)
	_sync("so_skin_tol", solid.skin_tol)


## いま選んでいる お手本の 1 体を、立体の その向きの絵にする (90 = 右向きの横、270 = 左向きの横、180 = 後ろ)
func solid_use_ref(key: int) -> bool:
	if solid == null or _ref_img == null:
		_hint.text = "先に立体を作り、表の中の 横向き (後ろ向き) の 1 体を選んでください"
		return false
	push_undo()
	solid.set_pic(key, _ref_img)
	ref.mode = 0
	_sync("ref_mode", 0)
	mark()
	return true


func solid_forget(keys: Array) -> void:
	if solid == null:
		return
	push_undo()
	for k in keys:
		solid.forget(k)
	mark()


func paint_line(a: Vector2, b: Vector2, erase := false) -> int:
	if solid_on and solid != null:
		return solid_line(a, b, erase)
	if int(paint.get("target", 0)) == 1:
		return fix_line(a, b, erase)
	var n := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
	var added := 0
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		added += core.PaintKind(p.x, p.y, float(paint.size), paint.color, paint.flat, erase, paint.mirror, int(paint.kind))
	if added > 0:
		_paint_cache = null
		mark()
	return added


func _paint_press(px: Vector2, button: int) -> void:
	if Input.is_key_pressed(KEY_ALT):
		pick_color(px, button == MOUSE_BUTTON_RIGHT)
		return
	if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
		return
	if _dot_mode():
		_dot_press(px, button)
		return
	if button == MOUSE_BUTTON_LEFT and (int(paint.kind) == 0 or int(paint.target) == 1) and not paint.clear:
		use_color(paint.color)
	push_undo()
	_painting = button
	_paint_last = px
	paint_line(px, px, button == MOUSE_BUTTON_RIGHT)


func clear_paint() -> void:
	push_undo()
	core.ClearPaint()
	_paint_cache = null
	mark()


# --- モデルの書き出し (アニメーションは 別アプリ dot-godough-motion で) ------------------- #

## 立体 (ドット絵モデル) を書き出す: アニメーション用のアプリ (dot-godough-motion) で開くファイル
func export_model(path: String) -> bool:
	if solid == null:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"app": "dot-godough", "kind": "model", "version": 1,
			"name": path.get_file().trim_suffix(".dotmodel.json"), "solid": solid.to_doc()}, " "))
	return true


func _ask_model() -> void:
	if solid == null:
		_hint.text = "先に「立体」タブで 立体を作ってください"
		return
	_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.dotmodel.json ; ドット絵モデル"], "キャラ.dotmodel.json", func(p: String):
		if not p.ends_with(".dotmodel.json"):
			p += ".dotmodel.json"
		_hint.text = ("モデルを書き出しました: " + p) if export_model(p) else ("書き出せませんでした: " + p))


# --- ドット直し: 絵の画素をじかに直す (この向き・このポーズだけ) ------------------------ #
# ポーズごとに {向き (度): {紙の真ん中下からの場所: 色}} を持つ。色の a = 0 は「その画素を消す」

func _fix_key(yaw: float) -> String:
	return str(int(roundf(fposmod(yaw, 360.0))) % 360)


func _fix_of(yaw: float, make := false) -> Dictionary:
	var p := cur()
	var k := _fix_key(yaw)
	if not p.has("fix"):
		if not make:
			return {}
		p["fix"] = {}
	if not p.fix.has(k):
		if not make:
			return {}
		p.fix[k] = {}
	return p.fix[k]


func _fix_origin() -> Vector2i:
	return Vector2i(view.w / 2, view.h - view.margin)


func _apply_fix(img: Image, yaw: float) -> void:
	var f := _fix_of(yaw)
	if f.is_empty():
		return
	var o := _fix_origin()
	for k in f:
		var q: Vector2i = k + o
		if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
			img.set_pixel(q.x, q.y, f[k])


## 絵の a から b まで、画素をじかに直す。erase = 直しを取りのぞく (計算した絵に戻る)。変えた画素の数を返す
func fix_line(a: Vector2, b: Vector2, erase := false) -> int:
	var f := _fix_of(_pyaw(), true)
	var o := _fix_origin()
	var col := Color(0, 0, 0, 0) if paint.get("clear", false) else Color(paint.color, 1.0)
	var half := float(paint.size) * 0.5
	var n := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
	var changed := 0
	for i in n + 1:
		var c := a.lerp(b, float(i) / n)
		var cells := []
		if int(paint.size) <= 1:
			cells.append(Vector2i(c.floor()))
		else:
			for y in range(int(floor(c.y - half)), int(ceil(c.y + half)) + 1):
				for x in range(int(floor(c.x - half)), int(ceil(c.x + half)) + 1):
					if Vector2(x + 0.5, y + 0.5).distance_to(c) <= half:
						cells.append(Vector2i(x, y))
		for cell in cells:
			for m in (2 if paint.mirror else 1):
				var q: Vector2i = cell if m == 0 else Vector2i(view.w - 1 - cell.x, cell.y)
				if q.x < 0 or q.y < 0 or q.x >= view.w or q.y >= view.h:
					continue
				var k := q - o
				if erase:
					if f.has(k):
						f.erase(k)
						changed += 1
				elif not f.has(k) or f[k] != col:
					f[k] = col
					changed += 1
	if changed > 0:
		mark()
	return changed


## ドット直しのある向き: [[向き (度), 画素の数], ...] (いまのコマ)
func fix_dirs() -> Array:
	var out := []
	var f: Dictionary = cur().get("fix", {})
	for k in f:
		if not f[k].is_empty():
			out.append([int(k), f[k].size()])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## ドット直しを消す。keep_front = 正面 (0°) の直しは残す。消した向きの数を返す
func clear_fix_all(keep_front := true) -> int:
	var f: Dictionary = cur().get("fix", {})
	var ks := []
	for k in f:
		if not (keep_front and int(k) == 0) and not f[k].is_empty():
			ks.append(k)
	if ks.is_empty():
		return 0
	push_undo()
	for k in ks:
		f.erase(k)
	mark()
	return ks.size()


func _fix_label() -> void:
	if not _w.has("fix_info"):
		return
	var d := fix_dirs()
	if d.is_empty():
		_w["fix_info"].text = "ドット直し: ありません"
	else:
		_w["fix_info"].text = "ドット直しのある向き: " + ", ".join(d.map(func(e): return "%d° (%d 画素)" % [e[0], e[1]]))


func clear_fix() -> void:
	if _fix_of(view.yaw).is_empty():
		return
	push_undo()
	cur().fix.erase(_fix_key(view.yaw))
	mark()


# --- ペンの色・パレット ----------------------------------------------------------------- #

func set_pen_color(c: Color, keep_kind := false) -> void:
	paint.color = Color(c.r, c.g, c.b)
	_sync("paint_color", paint.color)
	_sync("pen_color", paint.color)
	if not keep_kind:
		if int(paint.kind) != 0:
			paint.kind = 0
			_sync("paint_kind", 0)
		if paint.clear:
			paint.clear = false
			_sync("paint_clear", false)
	_refresh_palette()


func swap_colors() -> void:
	var c: Color = paint.color
	set_pen_color(paint.color2)
	_set_color2(c)


func _set_color2(c: Color) -> void:
	paint.color2 = c
	if _w.has("pen_color2"):
		for st in ["normal", "hover", "pressed"]:
			_w["pen_color2"].add_theme_stylebox_override(st, XP.flat(c, Color.BLACK, 1))


## 使った色を「最近使った色」の先頭へ
func use_color(c: Color) -> void:
	var h := c.to_html(false)
	if not recent.is_empty() and recent[0].to_html(false) == h:
		return
	recent = recent.filter(func(x: Color): return x.to_html(false) != h)
	recent.push_front(Color(c.r, c.g, c.b))
	if recent.size() > 10:
		recent.resize(10)
	_refresh_palette()


## 絵の画素 px の色を拾ってペンの色にする。from_ref = お手本から (絵に何も無い所は、いつもお手本から)
func pick_color(px: Vector2, from_ref := false) -> bool:
	var x := int(floor(px.x))
	var y := int(floor(px.y))
	var own: Image = _side_img if (solid_on and not is_nan(_paint_yaw)) else _last_img
	for src in ([_ref_img] if from_ref else [own, _ref_img]):
		if src == null or x < 0 or y < 0 or x >= src.get_width() or y >= src.get_height():
			continue
		var c: Color = src.get_pixel(x, y)
		if c.a > 0.5:
			set_pen_color(c)
			_hint.text = "色を拾いました: #%s (%s)" % [c.to_html(false), "お手本" if src == _ref_img else "絵"]
			return true
	return false


func palette_has(c: Color) -> bool:
	var h := c.to_html(false)
	return palette.any(func(x: Color): return x.to_html(false) == h)


func palette_add(c: Color) -> void:
	if not palette_has(c):
		palette.append(Color(c.r, c.g, c.b))
	_refresh_palette()


## 絵に使われている色 (色みごとに、暗い → 明るい の順)
static func colors_of(img: Image, limit := 96) -> Array:
	var count := {}
	var d := img.get_data()
	for i in range(0, d.size(), 4):
		if d[i + 3] < 128:
			continue
		var k := (d[i] << 16) | (d[i + 1] << 8) | d[i + 2]
		count[k] = count.get(k, 0) + 1
	var keys := count.keys()
	keys.sort_custom(func(a, b): return count[a] > count[b])
	if keys.size() > limit:
		keys.resize(limit)
	var cols := keys.map(func(k: int): return Color8((k >> 16) & 255, (k >> 8) & 255, k & 255))
	cols.sort_custom(func(a: Color, b: Color):
		var ga := -1 if a.s < 0.1 else int(fposmod(a.h + 0.04, 1.0) * 8.0)
		var gb := -1 if b.s < 0.1 else int(fposmod(b.h + 0.04, 1.0) * 8.0)
		return a.v < b.v if ga == gb else ga < gb)
	return cols


func palette_from_ref() -> int:
	var src: Image = ref.cell if ref.cell != null else ref.sheet
	if src == null:
		_hint.text = "先に「お手本」タブで絵を開いてください"
		return 0
	palette = colors_of(src)
	_refresh_palette()
	return palette.size()


func palette_from_art() -> void:
	if _last_img == null:
		return
	for c in colors_of(_last_img):
		if not palette_has(c):
			palette.append(c)
	_refresh_palette()


## パレットを読む: 絵 (.png — 使われている色)、.hex (1 行に rrggbb)、.gpl (GIMP: 1 行に r g b)
func palette_load(path: String) -> int:
	var cols := []
	if path.get_extension().to_lower() in ["png", "bmp", "jpg", "webp"]:
		var img := Image.load_from_file(path)
		if img == null:
			return 0
		img.convert(Image.FORMAT_RGBA8)
		cols = colors_of(img, 256)
	else:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var t := line.strip_edges()
			var parts := t.split(" ", false)
			if t.begins_with("#") and t.length() < 6:
				continue
			var hx := t.trim_prefix("#")
			if hx.length() >= 6 and hx.substr(0, 6).is_valid_hex_number():
				cols.append(Color(hx.substr(0, 6)))
			elif parts.size() >= 3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int():
				cols.append(Color8(int(parts[0]), int(parts[1]), int(parts[2])))
	if cols.is_empty():
		return 0
	palette = cols
	_refresh_palette()
	return cols.size()


func _swatch(parent: Control, col: Color, px: int, tip: String, on_left: Callable, on_right := Callable(), sel := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var edge := Color.WHITE if sel else Color(0, 0, 0, 0.75)
	b.add_theme_stylebox_override("normal", XP.flat(col, edge, 2 if sel else 1))
	b.add_theme_stylebox_override("hover", XP.flat(col, Color.WHITE, 2))
	b.add_theme_stylebox_override("pressed", XP.flat(col, Color.WHITE, 2))
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				on_left.call()
			elif e.button_index == MOUSE_BUTTON_RIGHT and on_right.is_valid():
				on_right.call())
	parent.add_child(b)
	return b


func _refresh_palette() -> void:
	if _pal_box == null:
		return
	for c in _pal_box.get_children():
		_pal_box.remove_child(c)
		c.queue_free()
	var cur_h: String = paint.color.to_html(false)
	for i in palette.size():
		var col: Color = palette[i]
		var key := ("・キー %d" % ((i + 1) % 10)) if i < 10 else ""
		_swatch(_pal_box, col, 20, "#%s%s\n左クリック = ペンの色・右クリック = パレットから外す" % [col.to_html(false), key],
				func(): set_pen_color(col), func():
					palette.remove_at(i)
					_refresh_palette.call_deferred(), col.to_html(false) == cur_h)
	if not recent.is_empty():
		var sep := Label.new()
		sep.text = " 最近:"
		sep.add_theme_color_override("font_color", Color("#555555"))
		_pal_box.add_child(sep)
		for col in recent:
			_swatch(_pal_box, col, 16, "#%s (最近使った色)\n左クリック = ペンの色・右クリック = パレットに足す" % col.to_html(false),
					func(): set_pen_color(col), func(): palette_add.call_deferred(col))


func _build_palette_bar(parent: Control) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", XP.flat(XP.FACE, Color("#D5D2C2"), 1, 0, 4))
	parent.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var c := _color(h, "pen_color", func(col: Color): set_pen_color(col, true), "ペンの色 (押すと色を作れます)")
	c.custom_minimum_size = Vector2(44, 44)
	c.color = paint.color
	var c2 := Button.new()
	c2.custom_minimum_size = Vector2(24, 24)
	c2.size_flags_vertical = Control.SIZE_SHRINK_END
	c2.focus_mode = Control.FOCUS_NONE
	c2.tooltip_text = "もう 1 つの色。押すと ペンの色と入れかわります (X キー)"
	c2.pressed.connect(swap_colors)
	h.add_child(c2)
	_w["pen_color2"] = c2
	_set_color2(paint.color2)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	_pal_box = _flow(v)
	_pal_box.add_theme_constant_override("h_separation", 2)
	_pal_box.add_theme_constant_override("v_separation", 2)
	var f := _flow(v)
	_button(f, "＋ 今の色", func(): palette_add(paint.color), "ペンの色をパレットに足す")
	_button(f, "お手本の色", palette_from_ref, "パレットを、お手本 (選んだ 1 体。選んでいなければ絵まるごと) に使われている色に入れかえる")
	_button(f, "今の絵の色", palette_from_art, "いまの絵に出ている色をパレットに足す")
	_button(f, "読む…", func():
		_ask(FileDialog.FILE_MODE_OPEN_FILE, ["*.png, *.hex, *.gpl, *.txt ; パレット"], "", func(pth: String):
			_hint.text = "パレットを読みました: %d 色" % palette_load(pth)), "絵 (使われている色)・.hex・.gpl からパレットを読む")
	_button(f, "空に", func():
		palette = []
		_refresh_palette())
	var tip := Label.new()
	tip.text = " 1〜0 = 色を選ぶ・X = 入れかえ・Alt+クリック = 色を拾う・[ ] = 太さ"
	tip.add_theme_color_override("font_color", Color("#555555"))
	f.add_child(tip)
	_refresh_palette()


# --- 素材ごとの色の段 ------------------------------------------------------------------- #
# 素材 0 = 肌、1〜 = 服 (着ている順)、最後 = 髪。段 0〜3 = 濃い影・影・基本・明るい、4 = 線

func mat_count() -> int:
	return 1 + mats_of(garments, hair).size()


func _mat_dict(m: int) -> Dictionary:
	return garments[m - 1] if m <= garments.size() else hair


func mat_name(m: int) -> String:
	return "肌" if m == 0 else (str(garments[m - 1].get("name", "服")) if m <= garments.size() else "髪")


func mat_get(m: int, slot: int) -> Color:
	if m == 0:
		return style.line if slot == 4 else style.ramp[slot]
	var d := _mat_dict(m)
	return (d.ramp if d.has("ramp") else ramp_of(d.color))[slot]


func mat_set(m: int, slot: int, c: Color) -> void:
	c = Color(c.r, c.g, c.b)
	if m == 0:
		if slot == 4:
			style.line = c
			_sync("line", c)
		else:
			style.ramp[slot] = c
			_sync("ramp%d" % slot, c)
	else:
		var d := _mat_dict(m)
		if not d.has("ramp"):
			d["ramp"] = ramp_of(d.color)
		d.ramp[slot] = c
		if slot == 2:
			d.color = c
	mark()


## 自分で決めた色の段をやめて、「基本」の色から作る段に戻す
func mat_auto(m: int) -> void:
	if m == 0:
		ramp_from(style.ramp[2])
	else:
		_mat_dict(m).erase("ramp")
	mark()


func _sync_mat_ui() -> void:
	if _mat_box == null:
		return
	for c in _mat_box.get_children():
		_mat_box.remove_child(c)
		c.queue_free()
	var names := ["濃い影", "影", "基本", "明るい", "線"]
	for m in mat_count():
		var h := HBoxContainer.new()
		_mat_box.add_child(h)
		var l := Label.new()
		l.text = mat_name(m)
		l.custom_minimum_size.x = 96
		l.clip_text = true
		h.add_child(l)
		for slot in [3, 2, 1, 0, 4]:
			if slot == 4:
				var sp := Control.new()
				sp.custom_minimum_size.x = 8
				h.add_child(sp)
			var col := mat_get(m, slot)
			_swatch(h, col, 24, "%s の「%s」 #%s\n左クリック = ペンの色を入れる・右クリック = この色をペンの色にする" % [mat_name(m), names[slot], col.to_html(false)],
					func():
						push_undo(true)
						mat_set(m, slot, paint.color)
						_sync_wear_ui()
						_sync_mat_ui.call_deferred(),
					func(): set_pen_color(mat_get(m, slot)))
		if m == 0 or _mat_dict(m).has("ramp"):
			_button(h, "自動", func():
				push_undo(true)
				mat_auto(m)
				_sync_mat_ui.call_deferred(), "「基本」の色から、ほかの色を作り直す")


# --- お手本 (似せたいドット絵) を重ねる -------------------------------------------------- #

func load_ref(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return false
	img.convert(Image.FORMAT_RGBA8)
	# 背景が塗ってある絵: 左上の色を「何も無い」として扱う
	var bgc := img.get_pixel(0, 0)
	if bgc.a > 0.5:
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y) == bgc:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	ref.path = path
	ref.sheet = img
	ref.rect = Rect2i()
	ref.cell = null
	ref.off = Vector2i.ZERO
	if _ref_view:
		_ref_view.set_image(img)
		_ref_view.fit.call_deferred()
	_ref_refresh()
	_redraw()
	return true


func clear_ref() -> void:
	ref.path = ""
	ref.sheet = null
	ref.rect = Rect2i()
	ref.cell = null
	ref.off = Vector2i.ZERO
	if _ref_view:
		_ref_view.tex = null
		_ref_view.queue_redraw()
	_ref_refresh()
	_redraw()


static func _opaque(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5


## お手本の絵の画素 p につながっている 1 体 (ななめも つながりに数える) の枠
func ref_island(p: Vector2i) -> Rect2i:
	var img: Image = ref.sheet
	if img == null or not _opaque(img, p.x, p.y):
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
				if not seen.has(q) and _opaque(img, q.x, q.y):
					seen[q] = true
					todo.append(q)
	return r


## 使う範囲を決める (中身のある所まで ちぢめる)。1 体を切り出して、位置を合わせる
func set_ref_rect(r: Rect2i, align := true) -> bool:
	var img: Image = ref.sheet
	if img == null:
		return false
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var used := img.get_region(r).get_used_rect() if r.size.x > 0 and r.size.y > 0 else Rect2i()
	if used.size.x <= 0 or used.size.y <= 0:
		return false
	ref.rect = Rect2i(r.position + used.position, used.size)
	ref.cell = img.get_region(ref.rect)
	ref.off = Vector2i.ZERO
	if int(ref.mode) == 0:
		ref.mode = 1
		_sync("ref_mode", 1)
	if align:
		ref_align()
	_ref_refresh()
	_redraw()
	if _ref_view:
		_ref_view.queue_redraw()
	return true


## お手本を紙に置く場所 (左上)。ふだんは 紙の真ん中・足もとの線に、お手本の下の真ん中を合わせる
func _ref_origin() -> Vector2i:
	var s: Vector2i = ref.cell.get_size()
	return Vector2i(view.w / 2 - s.x / 2, view.h - view.margin - s.y) + ref.off


## 紙とキャラの大きさを、お手本に合わせる
func fit_paper_to_ref() -> void:
	if ref.cell == null:
		return
	var s: Vector2i = ref.cell.get_size()
	var line := 1 if int(style.line_mode) == 1 else 0
	view.margin = 2
	view.w = s.x + 4 + (s.x % 2)
	view.h = s.y + 4
	view.px = float(maxi(s.y - 2 * line, 8))
	for k in ["w", "h", "px", "margin"]:
		_sync(k, view[k])
	ref.off = Vector2i.ZERO
	ref_align()
	mark()
	fit_all.call_deferred()


## お手本の位置を、いまの絵と形がいちばん重なる所へ
func ref_align() -> void:
	if ref.cell == null or _d_body:
		return
	var keep: Vector2i = ref.off
	ref.off = Vector2i.ZERO
	var img := render_now()
	var o := _ref_origin()
	var cell: Image = ref.cell
	var pts := []
	for y in cell.get_height():
		for x in cell.get_width():
			if cell.get_pixel(x, y).a > 0.5:
				pts.append(Vector2i(x, y))
	var mask := PackedByteArray()
	mask.resize(view.w * view.h)
	var d := img.get_data()
	for i in view.w * view.h:
		mask[i] = 1 if d[i * 4 + 3] > 127 else 0
	var best := -1
	var best_off := keep
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var n := 0
			for p in pts:
				var q: Vector2i = o + p + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < view.w and q.y < view.h and mask[q.x + view.w * q.y] == 1:
					n += 1
			var score := n * 100 - absi(dx) - absi(dy)
			if score > best:
				best = score
				best_off = Vector2i(dx, dy)
	ref.off = best_off
	_ref_refresh()
	_redraw()


## お手本を紙の大きさに置いた絵・ちがう画素の絵・点数を作り直す
func _ref_refresh() -> void:
	ref_stats = {}
	_ref_img = null
	if ref.cell == null or _last_img == null:
		_ref_info()
		return
	var w := _last_img.get_width()
	var h := _last_img.get_height()
	_ref_img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var cell: Image = ref.cell
	var o := _ref_origin()
	for y in cell.get_height():
		for x in cell.get_width():
			var q := o + Vector2i(x, y)
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				_ref_img.set_pixel(q.x, q.y, cell.get_pixel(x, y))
	var a := _last_img.get_data()
	var b := _ref_img.get_data()
	var diff := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var same := 0
	var total := 0
	var shape := 0
	for i in w * h:
		var ao := a[i * 4 + 3] > 127
		var bo := b[i * 4 + 3] > 127
		if not ao and not bo:
			continue
		total += 1
		if ao != bo:
			shape += 1
			diff.set_pixel(i % w, i / w, Color(1.0, 0.85, 0.1, 0.9) if bo else Color(0.1, 0.9, 1.0, 0.9))
		elif a[i * 4] == b[i * 4] and a[i * 4 + 1] == b[i * 4 + 1] and a[i * 4 + 2] == b[i * 4 + 2]:
			same += 1
		else:
			diff.set_pixel(i % w, i / w, Color(1.0, 0.1, 0.9, 0.85))
	ref_stats = {"same": same, "total": total, "shape": shape}
	if _ref_tex == null or _ref_tex.get_size() != Vector2(w, h):
		_ref_tex = ImageTexture.create_from_image(_ref_img)
		_diff_tex = ImageTexture.create_from_image(diff)
	else:
		_ref_tex.update(_ref_img)
		_diff_tex.update(diff)
	_ref_info()


func ref_score() -> float:
	return float(ref_stats.same) / maxi(ref_stats.total, 1) if ref_stats.has("same") else 0.0


func _ref_text() -> String:
	if not ref_stats.has("same"):
		return ""
	return "お手本と同じ %d%% (%d / %d 画素)・形のちがい %d" % [int(floor(ref_score() * 100.0)), ref_stats.same, ref_stats.total, ref_stats.shape]


func _ref_info() -> void:
	if _w.has("ref_info"):
		_w["ref_info"].text = _ref_text() if ref.cell != null else ("絵の中のキャラをクリックして選んでください" if ref.sheet != null else "お手本の絵を開いてください")


## 絵の上に、お手本を重ねて描く
func _draw_ref(v: DotView) -> void:
	if ref.cell == null or _ref_tex == null:
		return
	var r := Rect2(v.origin(), Vector2(v.img_size) * v.zoom)
	match int(ref.mode):
		1:
			v.draw_texture_rect(_ref_tex, r, false, Color(1, 1, 1, ref.alpha))
		2:
			v.draw_texture_rect(_diff_tex, r, false)
		3:
			v.draw_rect(r, v.bg)
			v.draw_texture_rect(_ref_tex, r, false)
	if int(ref.mode) != 0:
		var t := _ref_text() + ("  [お手本だけ]" if int(ref.mode) == 3 else "")
		v.draw_string(get_theme_default_font(), Vector2(7, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.7))
		v.draw_string(get_theme_default_font(), Vector2(6, 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))


## 素材ごとの色 (段・線) を、お手本の同じ場所でいちばん多い色にする。変えた色の数を返す
func colors_from_ref() -> int:
	if ref.cell == null or _ref_img == null:
		return 0
	push_undo(true)
	render_now()
	var cls: PackedInt32Array = core.Classes()
	var w: int = view.w
	var votes := {}
	for i in cls.size():
		var c := cls[i]
		if c < 0:
			continue
		var rc := _ref_img.get_pixel(i % w, i / w)
		if rc.a < 0.5:
			continue
		if not votes.has(c):
			votes[c] = {}
		var k := rc.to_rgba32()
		votes[c][k] = votes[c].get(k, 0) + 1
	var first := 0 if clampi(style.shades, 2, 4) == 4 else 1
	var n := 0
	for c in votes:
		var best := 0
		var bk := 0
		for k in votes[c]:
			if votes[c][k] > best:
				best = votes[c][k]
				bk = k
		var m: int = c / 8
		var b: int = c % 8
		if m >= mat_count():
			continue
		var slot := 4 if b == 7 else clampi(b + first, 0, 3)
		var col := Color.hex(bk)
		if mat_get(m, slot).to_html(false) != col.to_html(false):
			mat_set(m, slot, col)
			n += 1
	_sync_wear_ui()
	_sync_hair_ui()
	mark()
	return n


## いまの向きの絵で、お手本とちがう画素を全部 お手本の色に直す (ドット直しとして残る)。直した数を返す
func ref_trace() -> int:
	if ref.cell == null or _ref_img == null or _last_img == null:
		return 0
	push_undo()
	_last_img = render_now()
	_ref_refresh()
	var f := _fix_of(view.yaw, true)
	var o := _fix_origin()
	var n := 0
	for y in _last_img.get_height():
		for x in _last_img.get_width():
			var a := _last_img.get_pixel(x, y)
			var b := _ref_img.get_pixel(x, y)
			if (a.a > 0.5) != (b.a > 0.5) or (a.a > 0.5 and a.to_rgba32() != b.to_rgba32()):
				f[Vector2i(x, y) - o] = b if b.a > 0.5 else Color(0, 0, 0, 0)
				n += 1
	mark()
	return n


func _ref_to_doc() -> Dictionary:
	var r: Rect2i = ref.rect
	return {"path": ref.path, "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "off": [ref.off.x, ref.off.y],
			"mode": int(ref.mode), "alpha": ref.alpha, "gw": int(ref.gw), "gh": int(ref.gh)}


func _ref_from_doc(d: Dictionary) -> void:
	clear_ref()
	ref.mode = int(d.get("mode", 1))
	ref.alpha = float(d.get("alpha", 0.5))
	ref.gw = int(d.get("gw", 0))
	ref.gh = int(d.get("gh", 0))
	for k in ["ref_mode", "ref_alpha", "ref_gw", "ref_gh"]:
		_sync(k, ref[k.trim_prefix("ref_")])
	var path: String = d.get("path", "")
	if path == "" or not FileAccess.file_exists(path) or not load_ref(path):
		ref.path = path
		return
	var r: Array = d.get("rect", [0, 0, 0, 0])
	if set_ref_rect(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])), false):
		var o: Array = d.get("off", [0, 0])
		ref.off = Vector2i(int(o[0]), int(o[1]))


func _ref_view_overlay(v: DotView) -> void:
	var r: Rect2i = ref.rect
	if r.size.x > 0:
		v.draw_rect(Rect2(v.to_screen(Vector2(r.position)), Vector2(r.size) * v.zoom).grow(1), Color("#ffd24a"), false, 2.0)
	if _ref_sel:
		var a := _ref_from.min(_ref_to).floor()
		var b := _ref_from.max(_ref_to).ceil()
		v.draw_rect(Rect2(v.to_screen(a), (b - a) * v.zoom), Color(1, 1, 1, 0.9), false, 1.0)


func _build_ref_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "お手本"
	tabs.add_child(v.get_meta("scroll"))
	_ref_tab = tabs.get_tab_count() - 1
	_note(v, "似せたいドット絵を開いて、絵の上に重ねます。ちがう画素の数が出るので、形・色・画素を順に寄せていけます。")
	var f0 := _flow(v)
	_button(f0, "お手本の絵を開く…", func():
		_ask(FileDialog.FILE_MODE_OPEN_FILE, ["*.png, *.bmp, *.webp ; 絵"], "", func(p: String):
			_hint.text = "お手本を開きました。絵の中のキャラをクリックして選んでください" if load_ref(p) else "開けませんでした: " + p))
	_button(f0, "外す", clear_ref)
	_ref_view = DotView.new()
	_ref_view.custom_minimum_size.y = 240
	_ref_view.overlay = _ref_view_overlay
	_ref_view.pressed.connect(func(px: Vector2, button: int):
		if button == MOUSE_BUTTON_LEFT and ref.sheet != null:
			_ref_sel = true
			_ref_from = px
			_ref_to = px)
	_ref_view.dragged.connect(func(px: Vector2, _rel: Vector2, _b: int):
		if _ref_sel:
			_ref_to = px
			_ref_view.queue_redraw())
	_ref_view.released.connect(func(_px: Vector2, _b: int):
		if not _ref_sel:
			return
		_ref_sel = false
		var a := Vector2i(_ref_from.min(_ref_to).floor())
		var b := Vector2i(_ref_from.max(_ref_to).ceil())
		var r := Rect2i(a, b - a)
		if _ref_from.distance_to(_ref_to) < 2.0:
			var p := Vector2i(_ref_from.floor())
			if int(ref.gw) > 0 and int(ref.gh) > 0:
				r = Rect2i(p.x / int(ref.gw) * int(ref.gw), p.y / int(ref.gh) * int(ref.gh), int(ref.gw), int(ref.gh))
			else:
				r = ref_island(p)
		if not set_ref_rect(r):
			_hint.text = "そこには何も描かれていません"
		_ref_view.queue_redraw())
	v.add_child(_ref_view)
	_note(v, "クリック = つながっている 1 体を選ぶ / つまんで囲む = その範囲 / ホイール = 拡大・中ボタン = 動かす")
	_slider(v, "ref_gw", "ますの幅", 0, 96, 1, func(x: float): ref.gw = int(x), "キャラどうしが くっついている表のとき: 1 ますの幅と高さを入れると、クリックで そのますを選びます (0 = 使わない)")
	_slider(v, "ref_gh", "ますの高さ", 0, 96, 1, func(x: float): ref.gh = int(x))
	_head(v, "重ね方")
	_option(v, "ref_mode", "見せ方", ["かくす", "すかして重ねる", "ちがう画素を光らせる", "お手本だけ見る"], func(i: int):
		ref.mode = i
		_redraw())
	_w["ref_mode"].select(1)
	_slider(v, "ref_alpha", "すかす濃さ", 0.1, 1.0, 0.05, func(x: float):
		ref.alpha = x
		_redraw())
	_sync("ref_alpha", 0.5)
	_note(v, "R キー = お手本だけ ⇔ 元の見せ方 (ぱっと見くらべる)。ちがう画素の色: 赤紫 = 色がちがう・黄 = お手本にだけある・水色 = こちらにだけある")
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_override("font", XP.font(true))
	v.add_child(info)
	_w["ref_info"] = info
	_head(v, "1. 大きさと位置")
	_button(v, "紙とキャラの大きさを お手本に合わせる", fit_paper_to_ref, "紙の幅・高さとキャラの高さ (画素) を、選んだ 1 体に合わせます。頭身は「体型」タブで")
	var f1 := _flow(v)
	_button(f1, "位置を合わせ直す", ref_align, "いまの絵と形がいちばん重なる所へ、お手本を動かします")
	for d in [["←", Vector2i(-1, 0)], ["→", Vector2i(1, 0)], ["↑", Vector2i(0, -1)], ["↓", Vector2i(0, 1)]]:
		_button(f1, d[0], func():
			ref.off += d[1]
			_ref_refresh()
			_redraw(), "お手本を 1 画素動かす")
	_note(v, "このタブを開いているあいだ、真ん中の絵の上をつまんでも お手本が動きます。")
	_head(v, "2. 色")
	_button(v, "色を お手本から取る", func():
		_hint.text = "お手本から %d 色を取りました (肌・服・髪の色の段と線)" % colors_from_ref(),
			"肌・服・髪それぞれの 影・基本・明るい・線の色を、お手本の同じ場所でいちばん多い色にします。形がだいたい合ってから押すと うまく取れます")
	_note(v, "1 色ずつ直すときは「ドット絵」タブの「素材ごとの色」へ。Alt + クリックで お手本の色を拾えます。")
	_head(v, "3. 画素")
	_note(v, "残りは「塗る」タブで、塗る先を「この絵の画素」にして 1 画素ずつ直します。")
	_button(v, "ちがう画素を全部 お手本の色に直す (この向き)", func():
		_hint.text = "%d 画素を直しました (この向き・このポーズのドット直しとして残ります)" % ref_trace(),
			"いまの向き・いまのポーズの絵を、お手本と同じにします。体やポーズを変えても、直した画素はその場所に残ります")
	_button(v, "この向きのドット直しを消す", clear_fix)
	_note(v, "4. 立体にして 向きを変えたり ポーズをつけるのは、となりの「立体」タブで。")
	v = _panel(320)
	v.get_meta("scroll").name = "立体"
	tabs.add_child(v.get_meta("scroll"))
	_solid_tab = tabs.get_tab_count() - 1
	_head(v, "立体を作る (試作)")
	_note(v, "「お手本」タブで選んだ 1 体を正面の絵として、行ごとに 横幅 × 奥行きの だ円を積んだ立体にします。横・後ろ・ななめは そこから描いた推定です。")
	var mk := func():
		if make_solid():
			_hint.text = "立体を作りました。← → キーで向きを変えて、「塗る」タブで 横や後ろの絵に描き足せます"
	_button(v, "この絵を正面として 立体を作る", mk)
	_check(v, "solid_on", "ドット絵から作った立体を見る", func(on: bool):
		solid_on = on and solid != null
		if on and solid == null:
			_sync("solid_on", false)
			_hint.text = "まだ立体がありません。上のボタンで作ってください"
		mark(), "切ると、体型タブなどで作った体の絵に戻ります")
	_slider(v, "so_head", "頭の奥行き", 0.4, 1.5, 0.05, func(x: float):
		if solid != null:
			solid.k_head = x
			solid.touch()
			mark(), "横幅に対する奥行き。横の絵を自分で描くと、そちらが使われます")
	_slider(v, "so_body", "体の奥行き", 0.3, 1.5, 0.05, func(x: float):
		if solid != null:
			solid.k_body = x
			solid.touch()
			mark())
	_slider(v, "so_leg", "脚の奥行き", 0.5, 3.0, 0.05, func(x: float):
		if solid != null:
			solid.k_leg = x
			solid.touch()
			mark())
	_slider(v, "so_wrap", "絵の回りこみ", 0.0, 1.0, 0.05, func(x: float):
		if solid != null:
			solid.wrap = x
			solid.touch()
			mark(), "ななめなど 絵の無い向きで、いちばん近い絵をどれだけずらすか。0 = 絵は動かさない (輪郭だけ変わる)、1 = 立体どおりに回す (顔が はしへ流れる)。手描きのななめ顔に近いのは 0.5〜0.7")
	for kv in [["so_head", 1.0], ["so_body", 0.65], ["so_leg", 1.5], ["so_wrap", 0.6]]:
		_sync(kv[0], kv[1])
	_note(v, "表に 横向き・後ろ向きの絵があれば: 上の絵でその 1 体を選んでから、下のボタンで その向きの絵にします。")
	var f5 := _flow(v)
	for kv in [["右向きの横の絵にする", 90], ["左向きの横の絵にする", 270], ["後ろの絵にする", 180]]:
		_button(f5, kv[0], func():
			if solid_use_ref(kv[1]):
				_hint.text = "選んだ 1 体を「%s」にしました" % kv[0].trim_suffix("にする"), "位置は、いま重ねてある場所のまま使います (←→↑↓ で合わせてから押す)")
	var f4 := _flow(v)
	_button(f4, "横の絵を推定に戻す", func(): solid_forget([90, 270]))
	_button(f4, "後ろの絵を推定に戻す", func(): solid_forget([180]))
	_button(f4, "ななめの絵を推定に戻す", func(): solid_forget([45, 135, 225, 315]))
	_note(v, "直し方: 「塗る」タブを開き、正面・横・後ろの絵 (右の「横から」の絵でもよい) に描くと、その絵が「決めた絵」になって立体が作り直されます。右ボタン = 画素を消す。ななめ (45° ごと) の絵に描いても「決めた絵」になり、その絵は面に貼りつくので、ポーズをつけてもついてきます (形は変わりません)。左右対称として、反対側のななめにも鏡で使います。")
	_head(v, "ポーズ")
	_note(v, "手・足の先 (うすい丸) をつまむと、ひじ・ひざが曲がって 腕・脚ぜんたいが ついてきます。頭・体・ひじ・ひざ (濃い丸) は、つけ根のまわりに回ります。右の「横から」の絵でつまむと前後に動きます。右クリック = 戻す。")
	var f6 := _flow(v)
	for nm in ["立ち", "歩き 1", "歩き 2", "すわる", "ゆかにすわる", "おじぎ", "手をあげる"]:
		_button(f6, nm, func(): solid_preset(nm))
	_check(v, "so_joints", "ひじ・ひざで曲げる", func(on: bool):
		if solid != null:
			push_undo()
			solid.joints = on
			solid.touch()
			mark(), "腕・脚を真ん中で 2 つに分けます。うすい丸 (手・足の先) をつまむと、ひじ・ひざが曲がって 腕・脚ぜんたいが ついてきます。Shift を押しながらだと、ひじ・ひざから先だけ曲がります。濃い丸 (ひじ・ひざ) は つけ根から回します")
	_w["so_joints"].set_pressed_no_signal(true)
	_slider(v, "so_hip", "脚のつけ根の高さ", 0.0, 0.6, 0.05, func(x: float):
		if solid != null:
			solid.leg_hidden = x
			solid.touch()
			mark(), "服にかくれた脚の長さ (首から脚までの何割か)。大きいほど 腰が高くなり、すわったとき 脚が上のほうから出ます")
	_sync("so_hip", 0.2)
	_slider(v, "so_arm", "はなした腕の太さ", 0.0, 2.5, 0.25, func(x: float):
		if solid != null:
			solid.arm_min = x
			solid.touch()
			mark(), "体から はなした腕の半径 (画素)。絵の腕は 体に半分かくれて細いので、動かしたときは これより細くしません。0 = 絵のまま (細い)")
	_sync("so_arm", 1.5)
	_slider(v, "so_shoulder", "肩の高さ", 0.0, 3.0, 0.5, func(x: float):
		if solid != null:
			solid.shoulder_up = x
			solid.touch()
			mark(), "腕のつけ根を、腕の画素の いちばん上の行より 何行上に置くか。大きいほど 肩が高い")
	_sync("so_shoulder", 1.0)
	_slider(v, "so_waist", "腰の関節の高さ", 0.0, 0.8, 0.05, func(x: float):
		if solid != null:
			solid.waist = x
			solid.touch()
			mark(), "体の 上から何割の所で 胸と腰に分けるか。0 = 分けない (体は 1 つ)")
	_sync("so_waist", 0.5)
	_head(v, "ほかの向きで描くとき")
	_note(v, "描いた色は、その場所に画素として置かれ (立体の上でも 空中でも同じ)、近くの部品にくっついて動き、描いた向きの近く (下の「描いた色が出る範囲」) で出ます。消しゴム (右ボタン) は そこを空にします — 立体もけずれます。")
	_slider(v, "so_air", "描いた画素の厚み", 0.5, 4.0, 0.5, func(x: float):
		if solid != null:
			solid.air_thick = x, "描いた画素が、描いた向きの奥と手前へ のびる長さ (画素)。小さい = うすい板、大きい = 厚い。これから描く分に効きます")
	_sync("so_air", 1.0)
	_slider(v, "so_reach", "描いた色が出る範囲 (±°)", 0, 180, 5, func(x: float):
		if solid != null:
			solid.paint_reach = x
			mark(), "描いた向きから 何度はなれた向きまで、塗った色・足した画素を出すか。小さい = その向きの近くだけ、180 = どの向きにも出る。あとから変えても 描いた分に効きます")
	_sync("so_reach", 20.0)
	_option(v, "so_mode", "描いた色は", ["画素を置く (もとの絵は変えない)", "その向きの絵を決める (45° ごと・立体を作り直す)"], func(i: int):
		paint["solid_mode"] = i)
	var spi := Label.new()
	v.add_child(spi)
	_w["spaint_info"] = spi
	_button(v, "面に塗った色を全部消す", func():
		if solid != null and not solid.spaint.is_empty():
			push_undo()
			solid.spaint.clear()
			mark(), "「元に戻す」で戻せます")
	_button(v, "描いた・けずった画素を全部消す", func():
		if solid != null and not solid.adds.is_empty():
			push_undo()
			solid.adds.clear()
			solid.touch()
			mark(), "「元に戻す」で戻せます")
	_head(v, "顔の層 (試作)")
	_note(v, "正面の絵の 顔 (肌・目・口) を、頭の だ円から切りはなして描きます。横を向くと 顔は向いたほうへ すべり、目は つぶれずに形のまま動きます。肌の色は決め打ちせず、顔の真ん中の色と それに近い色を 肌とみなします。横の絵を描いてあれば、そちらが先です。")
	_check(v, "so_face", "顔を別の層にする", func(on: bool):
		if solid != null:
			solid.face_layer = on
			solid.touch()
			mark())
	_sync("so_face", true)
	_slider(v, "so_face_min", "横顔の幅", 0.3, 0.9, 0.05, func(x: float):
		if solid != null:
			solid.face_min = x
			solid.touch()
			mark(), "真横を向いたときの 顔の幅 (正面の何割か)")
	_sync("so_face_min", 0.55)
	_slider(v, "so_front_reach", "正面の顔を使う角度", 45, 85, 2.5, func(x: float):
		if solid != null:
			solid.front_reach = x
			solid.touch()
			mark(), "頭が 正面の絵 (ずらした顔) を使いつづける角度。これより横を向くと 横の絵に切りかわります。45 = いちばん近い絵を使う (60° あたりで 横顔に寄りすぎる)")
	_sync("so_front_reach", 70.0)
	_slider(v, "so_skin_tol", "肌とみなす色の広さ", 0.0, 0.6, 0.05, func(x: float):
		if solid != null:
			solid.skin_tol = x
			solid.touch()
			mark(), "顔の真ん中の色に どれだけ近い色までを肌にするか。0 = その 1 色だけ。髪が肌に まざるなら小さく、ほおや影が抜けるなら大きく")
	_sync("so_skin_tol", 0.3)
	_head(v, "ドット直し (絵の上に重ねた画素)")
	_note(v, "ドット直しは、その向き・そのコマの絵の上に そのまま重なります (立体やポーズには ついてきません)。前に なぞった直しが残っていると、その向きだけ 絵がくずれて見えます。")
	var fi := Label.new()
	fi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(fi)
	_w["fix_info"] = fi
	var ff := _flow(v)
	_button(ff, "この向きの直しを消す", clear_fix, "いま見ている向き (左の絵) のドット直しを消す。「元に戻す」で戻せます")
	_button(ff, "正面以外の直しを全部消す", func(): _hint.text = "ドット直しを %d 方向ぶん消しました (「元に戻す」で戻せます)" % clear_fix_all(true),
			"正面 (0°) の直しは残して、ほかの向きのドット直しを全部消す")
	_head(v, "アニメーション")
	_note(v, "アニメーションは 別のアプリ (dot-Godough モーション) で作ります。上の列の「モデルを書き出す」で作ったファイルを、向こうの「モデルを開く」で開いてください。")
	_head(v, "部品 (頭・体・腕・脚)")
	_check(v, "part_edit", "部品を見る・塗り直す", func(on: bool):
		part_edit = on
		if on:
			view.yaw = 0.0
			_sync("yaw", 0.0)
		mark(), "正面の絵を部品ごとに色分けして見せます。まちがっている所は、下で部品を選んで 絵の上をなぞると直せます")
	_option(v, "part_sel", "塗る部品", ["頭", "体", "腕 (画面の左)", "腕 (画面の右)", "脚 (画面の左)", "脚 (画面の右)"], func(i: int): part_sel = i + 1)
	_button(v, "部品を自動で分け直す", func():
		if solid != null:
			push_undo()
			solid.reset_parts()
			mark(), "首より上 = 頭、脚の行から下 = 脚、あいだ = 体。体の両はしの、手 (顔と同じ肌の色) までを腕にします")


# --- 髪をペンで描く -------------------------------------------------------------------- #

## 窓 v の絵の上に引いた線 pts (画素) を、髪の房にする。足した房の数を返す
func hair_stroke(pts: PackedVector2Array, v: DotView, cut := false) -> int:
	if pts.is_empty():
		return 0
	if v == pix2:
		# 中身が覚えているのは真ん中の絵なので、横の絵を描き直してから線を置き、真ん中に戻す
		core.SetView(_view_of(pix2))
		core.Render()
	var locks: Array = core.HairStroke(pts, float(hair_pen.size), hair_pen.taper, hair_pen.mirror, cut)
	if v == pix2:
		render_now()
	if locks.is_empty():
		return 0                         # 髪の無い所を消しゴムでなぞった: 何も変えない (元に戻す の 1 回ぶんも使わない)
	push_undo()
	hair.locks = hair.locks + locks      # 並びを作り直す (元に戻す用に覚えた並びを書きかえない)
	mark("body")
	return locks.size()


func clear_locks() -> void:
	if hair.locks.is_empty():
		return
	push_undo()
	hair.locks = []
	mark("body")


# --- ポーズをつける -------------------------------------------------------------------- #

## with_body = 体型と服も覚える (輪郭をつまんだとき。ふだんはポーズと塗りだけ:
## 体型まで覚えると、ポーズを戻したときに、そのあとスライダーで変えた体型まで戻ってしまう)
func push_undo(with_body := false) -> void:
	_undo.append(_snapshot(with_body))
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()


func _snapshot(with_body := false) -> Dictionary:
	var s := {"i": pose_i, "rots": cur().rots.duplicate(), "root": cur().root, "paint": _paint_data(), "locks": hair.locks,
			"fix": cur().get("fix", {}).duplicate(true), "solid": solid.to_doc() if solid != null else {}, "solid_on": solid_on,
			"sp": cur().get("sp", {}).duplicate(), "sroot": cur().get("sroot", Vector3.ZERO)}
	if with_body:
		s["body"] = body.duplicate()
		s["wear"] = garments.duplicate(true)
		s["style"] = style.duplicate(true)
		s["hair_col"] = [hair.color, hair.get("ramp", []).duplicate()]
	return s


func _restore(s: Dictionary) -> void:
	pose_i = clampi(s.i, 0, poses.size() - 1)
	cur().rots = s.rots.duplicate()
	cur().root = s.root
	if s.has("sp"):
		cur()["sp"] = s.sp.duplicate()
		cur()["sroot"] = s.sroot
	if s.has("solid"):
		solid = DotSolid.from_doc(s.solid) if not s.solid.is_empty() else null
		solid_on = s.solid_on and solid != null
		_sync("solid_on", solid_on)
		_sync_solid_ui()
	if s.has("fix"):
		if s.fix.is_empty():
			cur().erase("fix")
		else:
			cur()["fix"] = s.fix.duplicate(true)
	if s.has("paint") and s.paint != _paint_data():
		core.SetPaint(s.paint)
		_paint_cache = s.paint
	if s.has("locks") and s.locks != hair.locks:
		hair.locks = s.locks
		mark("body")
	if s.has("body"):
		body = s.body.duplicate()
		garments = s.wear.duplicate(true)
		if s.has("style"):
			style = s.style.duplicate(true)
			hair.color = s.hair_col[0]
			if s.hair_col[1].is_empty():
				hair.erase("ramp")
			else:
				hair["ramp"] = s.hair_col[1].duplicate()
			for i in 4:
				_sync("ramp%d" % i, style.ramp[i])
			_sync("line", style.line)
			_sync_hair_ui()
		for k in body:
			_sync("b_" + k, body[k])
		_sync_wear_ui()
		mark("body")
	apply_pose()         # 関節の位置をすぐ今のポーズに (次のコマを待つと、戻した直後につまんだとき古い位置で計算してしまう)
	_sync_pose_ui()
	mark("pose")


func undo() -> void:
	if _undo.is_empty():
		return
	var s: Dictionary = _undo.pop_back()
	_redo.append(_snapshot(s.has("body")))
	_restore(s)


func redo() -> void:
	if _redo.is_empty():
		return
	var s: Dictionary = _redo.pop_back()
	_undo.append(_snapshot(s.has("body")))
	_restore(s)


func _refresh_pose() -> void:
	apply_pose()
	_d_view = true
	_idle = 0.0
	set_process(true)


## 骨 b を、世界の回転 q だけ回す (親の枠の中の回転に直して入れる)
func turn(b: String, q: Quaternion) -> void:
	var par: String = bone_parent.get(b, "")
	var rp: Basis = Basis() if par == "" else joints[par + "/basis"]
	var c: Quaternion = cur().rots.get(b, Quaternion.IDENTITY)
	cur().rots[b] = (rp.inverse() * Basis(q) * rp * Basis(c)).orthonormalized().get_rotation_quaternion()
	apply_pose()


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized()
	b = b.normalized()
	if a.dot(b) < -0.9999:
		var ax := a.cross(Vector3.UP)
		if ax.length() < 0.01:
			ax = a.cross(Vector3.RIGHT)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a, b)


## マウスの画素 px に写る、o から長さ len の点 (奥行きの向きは今の先 tip と同じ側。flip で反対側)
func _target(o: Vector3, tip: Vector3, px: Vector2, length: float, flip := false) -> Vector3:
	var ax: Array = core.Axes()
	var ppm: float = core.Ppm()
	var po: Vector3 = core.Project(o)
	var d := (px - Vector2(po.x, po.y)) / ppm
	var plane: Vector3 = ax[0] * d.x - ax[1] * d.y
	var r := plane.length()
	if r >= length:
		return o + plane / maxf(r, 1e-6) * length
	var sgn := 1.0 if (tip - o).dot(ax[2]) >= 0.0 else -1.0
	if flip:
		sgn = -sgn
	return o + plane + ax[2] * sgn * sqrt(length * length - r * r)


## deep = 奥行きだけ動かす (Shift)。rel = マウスが動いた量 (画素)。下へ = 手前、上へ = 奥
func drag_handle(i: int, px: Vector2, rel := Vector2.ZERO, deep := false) -> void:
	var h: Dictionary = HANDLES[i]
	var flip := Input.is_key_pressed(KEY_ALT)
	var zmove: Vector3 = core.Axes()[2] * (rel.y / core.Ppm())
	if h.has("move"):
		if deep:
			_move_body(zmove)
		else:
			var po: Vector3 = core.Project(joints["hips"])
			var d: Vector2 = (px - Vector2(po.x, po.y)) / core.Ppm()
			var ax: Array = core.Axes()
			_move_body(ax[0] * d.x - ax[1] * d.y)
	elif h.has("ik"):
		var leg: bool = h.ik[0].begins_with("thigh")
		var side: String = h.ik[0].right(1)
		var fb: Basis = joints["foot.%s/basis" % side]
		if deep:
			_ik_to(h.ik[0], h.ik[1], joints[h.ik[1] + "/tail"] + zmove)
		else:
			_ik(h.ik[0], h.ik[1], px, flip)
		if leg and keep_feet:
			_keep_world("foot." + side, fb)
		_mirror_from(h.ik + (["foot." + side] if leg else []))
	else:
		var b: String = h.bone
		var o: Vector3 = joints[b]
		var t: Vector3 = joints[b + "/tail"]
		if deep:
			turn(b, _arc(t - o, t + zmove - o))
		else:
			turn(b, _arc(t - o, _target(o, t, px, (t - o).length(), flip) - o))
		_mirror_from([b])
	_refresh_pose()
	_sync_bone_sliders()


## 体ごと delta だけ動かす。足を地面に残す (pin_feet) なら、体だけ動かして、足首が元の場所に来るように脚を曲げる
## (下げればしゃがむ、横へ動かせば片足に乗る)
func _move_body(delta: Vector3) -> void:
	if not pin_feet:
		cur().root += delta
		if ground:
			cur().root.y = 0.0
		return
	var g0 := _ground_off
	var off := Vector3(0, g0, 0)
	var ankle := {}
	var fb := {}
	for sd in ["L", "R"]:
		ankle[sd] = joints["shin.%s/tail" % sd] - off
		fb[sd] = joints["foot.%s/basis" % sd]
	cur().root += delta
	_no_ground = true
	for pass_i in 2:
		apply_pose()
		for sd in ["L", "R"]:
			_ik_to("thigh." + sd, "shin." + sd, ankle[sd])
			_keep_world("foot." + sd, fb[sd])
		# 脚が伸びきっても届かない高さまでは上げない (上げた分がたまると、下げるときに戻ってこない)
		var rise: float = core.LowestY() + g0
		if not ground or rise < 1e-4:
			break
		cur().root.y -= rise
	_no_ground = false


## 骨 b の世界での向きを wb にする (脚を動かしても、足の裏の向きを保つのに使う)
func _keep_world(b: String, wb: Basis) -> void:
	var par: String = bone_parent.get(b, "")
	var rp: Basis = Basis() if par == "" else joints[par + "/basis"]
	cur().rots[b] = (rp.inverse() * wb).orthonormalized().get_rotation_quaternion()
	apply_pose()


## 左右いっしょに動かす: いま動かした骨の回転を、反対側の骨に鏡写しで入れる
func _mirror_from(bones: Array) -> void:
	if not mirror_edit:
		return
	var any := false
	for b in bones:
		var o: String = b
		if b.ends_with(".L"):
			o = b.left(-2) + ".R"
		elif b.ends_with(".R"):
			o = b.left(-2) + ".L"
		else:
			continue
		var q: Quaternion = cur().rots.get(b, Quaternion.IDENTITY)
		cur().rots[o] = Quaternion(q.x, -q.y, -q.z, q.w)
		any = true
	if any:
		apply_pose()


## 腕が胴・頭・脚・服に入っていたら、入らなくなるまで開く (離れていく向きは中身が選ぶ)。変えたら true
func fix_arms() -> bool:
	var ch: Dictionary = core.FixArms(0.25)
	for b in ch:
		cur().rots[b] = ch[b]
	if not ch.is_empty():
		apply_pose()
	return not ch.is_empty()


## 2 本の骨 (上腕 + 前腕、太もも + すね) の先を、マウスの所へ
func _ik(b1: String, b2: String, px: Vector2, flip: bool) -> void:
	var o: Vector3 = joints[b1]
	var e: Vector3 = joints[b2]
	var w: Vector3 = joints[b2 + "/tail"]
	var lmax: float = ((e - o).length() + (w - e).length()) * 0.999
	var ax: Array = core.Axes()
	var po: Vector3 = core.Project(o)
	var d: Vector2 = (px - Vector2(po.x, po.y)) / core.Ppm()
	var plane: Vector3 = ax[0] * d.x - ax[1] * d.y
	var zrel: float = (w - o).dot(ax[2]) * (-1.0 if flip else 1.0)
	var m: Vector3 = o + plane + ax[2] * zrel
	var r := plane.length()
	if (m - o).length() > lmax:
		# 届かない: 画面の上ではマウスの向きのまま、奥行きを縮めて届かせる
		if r >= lmax:
			m = o + plane / maxf(r, 1e-6) * lmax
		else:
			m = o + plane + ax[2] * signf(zrel if zrel != 0.0 else 1.0) * sqrt(lmax * lmax - r * r)
	_ik_to(b1, b2, m)


## 2 本の骨の先を、3D の点 m へ
func _ik_to(b1: String, b2: String, m: Vector3) -> void:
	var o: Vector3 = joints[b1]
	var e: Vector3 = joints[b2]
	var w: Vector3 = joints[b2 + "/tail"]
	var l1: float = (e - o).length()
	var l2: float = (w - e).length()
	var v: Vector3 = m - o
	if v.length() < 1e-5:
		v = Vector3(0, -1, 0)
	var dir: Vector3 = v.normalized()
	var dist: float = clampf(v.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.999)
	m = o + dir * dist
	var ca: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sa: float = sqrt(1.0 - ca * ca)
	# 曲がる向き: いまのひじ・ひざの側。まっすぐなら、ひざは前・ひじは後ろ
	var perp: Vector3 = (e - o) - dir * (e - o).dot(dir)
	if perp.length() < l1 * 0.02:
		var bb: Basis = joints[b1 + "/basis"]
		var pref: Vector3 = bb * (Vector3(0, 0, 1) if b1.begins_with("thigh") else Vector3(0, 0, -1))
		perp = pref - dir * pref.dot(dir)
		if perp.length() < 1e-4:
			var ax: Array = core.Axes()
			perp = dir.cross(ax[2])
	perp = perp.normalized()
	var e2: Vector3 = o + (dir * ca + perp * sa) * l1
	turn(b1, _arc(e - o, e2 - o))
	var e3: Vector3 = joints[b2]
	var w3: Vector3 = joints[b2 + "/tail"]
	turn(b2, _arc(w3 - e3, m - e3))


func twist(i: int, deg: float) -> void:
	var h: Dictionary = HANDLES[i]
	if not h.has("bone"):
		return
	var b: String = h.bone
	turn(b, Quaternion((joints[b + "/tail"] - joints[b]).normalized(), deg_to_rad(deg)))
	_refresh_pose()
	_sync_bone_sliders()


func reset_bones(names: Array) -> void:
	push_undo()
	for b in names:
		cur().rots.erase(b)
	_sync_bone_sliders()
	mark("pose")


func handle_px(i: int) -> Vector3:
	return core.Project(joints[HANDLES[i].at])


func pick(px: Vector2) -> int:
	if not show_handles or joints.is_empty() or paint_mode or shape_mode:
		return -1
	var best := -1
	var zm: float = (_aimed if _aimed != null else pix).zoom
	var bd := 9.0 / zm + 0.6
	var bz := -1e9
	var best_d := 1e9
	for i in HANDLES.size():
		var p := handle_px(i)
		var d := Vector2(p.x, p.y).distance_to(px)
		if d < bd and (best < 0 or p.z > bz - 0.02 or d < bd * 0.5):
			if best >= 0 and p.z < bz - 0.02 and d > bd * 0.5:
				continue
			best = i
			bz = p.z
			best_d = d
	# 選んである点が同じ所に重なっていれば、そちらを取る (横から見ると左右の点が重なる。
	# 先に正面で選んでおけば、横の絵でもその点をつまめる)
	if _sel >= 0 and _sel != best and best >= 0:
		var ps := handle_px(_sel)
		if Vector2(ps.x, ps.y).distance_to(px) <= best_d + 1.5 / zm:
			return _sel
	return best


func _on_pressed(px: Vector2, button: int, v: DotView = null) -> void:
	if hair_mode:
		if button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT:
			_stroking = true
			_stroke_cut = button == MOUSE_BUTTON_RIGHT
			_stroke_v = v if v != null else pix
			_stroke = PackedVector2Array([px])
			_stroke_v.queue_redraw()
		return
	if paint_mode and (v == null or v == pix or (solid_on and v == pix2)):
		_paint_yaw = fposmod(view.yaw + 90.0, 360.0) if v == pix2 else NAN
		_paint_press(px, button)
		return
	if _part_editing() and (v == null or v == pix):
		if button == MOUSE_BUTTON_LEFT and DotSolid.key_of(view.yaw) == 0:
			push_undo()
			_part_painting = true
			_part_paint(px)
		return
	if solid_on and not ref_mode:
		# 立体: 部品の先をつまむと、つけ根のまわりに回る。何もない所をつまむと向きが回る
		var yv := fposmod(view.yaw + (90.0 if v == pix2 else 0.0), 360.0)
		var part := _solid_pick(px, yv)
		if part > 0 and button == MOUSE_BUTTON_LEFT:
			push_undo()
			_sdrag = part
			_sdrag_yaw = yv
			_sdrag_last = px
			if not cur().has("sp"):
				cur()["sp"] = {}
			_redraw()
		elif part > 0 and button == MOUSE_BUTTON_RIGHT:
			push_undo()
			if cur().has("sp"):
				cur().sp.erase(part)
				if part in DotSolid.IK_PARTS:
					cur().sp.erase(DotSolid.PARENT[part])      # 手・足の先を戻す = 腕・脚ぜんたいを戻す
			mark()
		elif button == MOUSE_BUTTON_LEFT:
			_turning = true
			_turn_moved = 0.0
			_aimed = v if v != null else pix
		return
	if ref_mode and (v == null or v == pix) and ref.cell != null:
		if Input.is_key_pressed(KEY_ALT):
			pick_color(px, button == MOUSE_BUTTON_RIGHT)
		elif button == MOUSE_BUTTON_LEFT:
			_ref_moving = true
			_ref_move = Vector2.ZERO
			_ref_move0 = ref.off
		return
	if shape_mode and button == MOUSE_BUTTON_LEFT:
		var t := shape_target(px, v if v != null else pix)
		if not t.is_empty():
			push_undo(true)
			_shape = t
			return
	_aim(v if v != null else pix)
	var h := pick(px)
	if button == MOUSE_BUTTON_LEFT:
		if h >= 0:
			push_undo()
			_drag = h
			_sel = h
			_sync_bone_sliders()
		else:
			_turning = true
			_turn_moved = 0.0
		_redraw()
	elif button == MOUSE_BUTTON_RIGHT and h >= 0:
		var hd: Dictionary = HANDLES[h]
		if hd.has("move"):
			push_undo()
			cur().root = Vector3.ZERO
			mark("pose")
		else:
			reset_bones(hd.ik if hd.has("ik") else [hd.bone])
	_aim(pix)


func _on_dragged(px: Vector2, rel: Vector2, _button: int, v: DotView = null) -> void:
	if _stroking:
		if _stroke.is_empty() or _stroke[-1].distance_to(px) > 0.3:
			_stroke.append(px)
		_paint_hover = px
		_stroke_v.queue_redraw()
		return
	if _part_painting:
		_part_paint(px)
		return
	if _sdrag > 0:
		solid.pose = cur().sp
		# 手・足の先: 腕・脚ぜんたいが動く (IK)。Shift を押していれば、ひじ・ひざから先だけ曲げる
		if _sdrag in DotSolid.IK_PARTS and not Input.is_key_pressed(KEY_SHIFT):
			solid.drag_ik(_sdrag, _sdrag_yaw, px)
		else:
			solid.drag_part(_sdrag, _sdrag_yaw, _sdrag_last, px)
		_sdrag_last = px
		mark()
		return
	if _ref_moving:
		_ref_move += rel
		var off := _ref_move0 + Vector2i(_ref_move.round())
		if off != ref.off:
			ref.off = off
			_ref_refresh()
			_redraw()
		return
	if _painting != 0:
		if _dot_mode():
			_dot_drag(px)
		else:
			paint_line(_paint_last, px, _painting == MOUSE_BUTTON_RIGHT)
			_paint_last = px
		_paint_hover = px
		return
	if not _shape.is_empty():
		shape_drag(_shape, px)
		_hint.text = shape_hint(_shape)
		return
	_aim(v if v != null else pix)
	if _drag >= 0:
		drag_handle(_drag, px, rel, Input.is_key_pressed(KEY_SHIFT))
	elif _turning:
		_turn_moved += absf(rel.x * _aimed.zoom)
		view.yaw = fposmod(view.yaw + rel.x * _aimed.zoom * 0.6, 360.0)
		_sync("yaw", view.yaw)
		mark()
	_aim(pix)


func _on_released(_px: Vector2, _button: int, _v: DotView = null) -> void:
	if _painting != 0 and _dot_mode():
		_dot_release()
	_painting = 0
	_paint_yaw = NAN
	_shape = {}
	_part_painting = false
	if _sdrag > 0:
		_sdrag = 0
		_redraw()
		return
	if _ref_moving:
		_ref_moving = false
		return
	if _stroking:
		_stroking = false
		hair_stroke(_stroke, _stroke_v, _stroke_cut)
		_stroke = PackedVector2Array()
		_redraw()
		return
	if _turning:
		_turning = false
		if _turn_moved < 3.0:
			_sel = -1
			_sync_bone_sliders()
		elif snap_yaw:
			view.yaw = fposmod(roundf(view.yaw / 45.0) * 45.0, 360.0)
			_sync("yaw", view.yaw)
		mark()
	_drag = -1
	_redraw()


func _on_hover(px: Vector2, v: DotView = null) -> void:
	if hair_mode:
		_paint_hover = px
		if not _stroking:
			_stroke_v = v if v != null else pix
		_redraw()
		_hint.text = "左ボタン = 髪を描く (塗った所がそのまま髪になります)・右ボタン = 消しゴム・Ctrl+Z = 1 筆もどす。向きは ← → キーで。右の「横から」の絵にも描けます"
		return
	if paint_mode:
		var on_side: bool = solid_on and v == pix2
		_paint_hover = px if (v == null or v == pix or on_side) else Vector2(-99, -99)
		_paint_v = pix2 if on_side else pix
		_redraw()
		_hint.text = "左ボタン = 塗る・右ボタン = 消す・Alt + 左 = 絵の色を拾う・Alt + 右 = お手本の色を拾う・1〜0 = パレットの色・X = 色を入れかえ・[ ] = 太さ。向きは ← → キー"
		return
	if _part_editing():
		_hint.text = "正面の絵の上をなぞる = その画素を「%s」にする。向きは正面のままで" % DotSolid.PART_NAMES[part_sel]
		return
	if solid_on and not ref_mode:
		_hint.text = "うすい丸 (手・足の先) をつまむ = 腕・脚ぜんたいが ついてくる (Shift = ひじ・ひざから先だけ)・濃い丸 = つけ根のまわりに回す・右クリック = 戻す・何もない所 = 向きを回す。右の「横から」の絵でもつまめます"
		return
	if ref_mode and ref.cell != null:
		_hint.text = "絵の上をつまむ = お手本を動かす・Alt + 左 = 絵の色を拾う・Alt + 右 = お手本の色を拾う・R = お手本だけ見る"
		return
	if shape_mode:
		# 横の絵は、調べるたびに描き直しになるので、動かしているだけのときは調べない
		_hint.text = shape_hint(shape_target(px, pix) if (v == null or v == pix) else {})
		return
	_aim(v if v != null else pix)
	var h := pick(px)
	_aim(pix)
	if h != _hover:
		_hover = h
		_redraw()
	_hint.text = ("%s — つまんで動かす・Shift で奥行きだけ (下 = 手前)・ホイールでひねる・右クリックでもどす・Alt で奥行きを反対に" % HANDLES[h].label) if h >= 0 \
			else "何もない所を左右につまむと向きが回ります。中ボタンで絵を動かす・ホイールで拡大。右の絵は横から見た所 (奥行き)"


func _on_wheel(px: Vector2, dir: int, v: DotView = null) -> bool:
	_aim(v if v != null else pix)
	var h := pick(px)
	_aim(pix)
	if h < 0 or not HANDLES[h].has("bone"):
		return false
	push_undo()
	_sel = h
	twist(h, dir * (15.0 if Input.is_key_pressed(KEY_SHIFT) else 5.0))
	return true


func _draw_handles(v: DotView) -> void:
	if v == pix:
		_draw_ref(v)
		if ref_mode and ref.cell != null:
			return               # お手本を見くらべているあいだは、関節の点を出さない
	if v == pix2:
		v.draw_string(get_theme_default_font(), Vector2(6, 16), "横から (奥行き)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	if solid_on and solid != null:
		var yv := fposmod(view.yaw + (90.0 if v == pix2 else 0.0), 360.0)
		var key := DotSolid.key_of(yv)
		var t := "ポーズをつけた絵 (立体から描く)" if solid.is_posed() else "あいだの向き: 立体から描いた絵" if key < 0 else ("決めた絵" if solid.is_drawn(key) else "推定の絵 (描くと 決めた絵になり、立体が変わる)")
		var nfix := _fix_of(yv).size()
		if nfix > 0:
			t += " ＋ ドット直し %d 画素が上に重なっています" % nfix
		v.draw_string(get_theme_default_font(), Vector2(6, v.size.y - 8), "立体 (試作) — " + t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1.0, 0.85, 0.4, 0.95) if nfix > 0 else Color(1, 1, 1, 0.85))
	if hair_mode:
		# 引いている線と、ペンの太さ
		# 引いている線: 塗られる画素をそのまま見せる (離したら立体になる)
		if v == _stroke_v:
			var half := maxf(float(hair_pen.size) * 0.5, 0.6)
			if _stroking and _stroke.size() > 0:
				var n := _stroke.size()
				var seen := {}
				var col := Color(0.62, 0.64, 0.7, 0.9) if _stroke_cut else Color(hair.color, 0.95)
				for i in n:
					var r: float = maxf(half * (1.0 - hair_pen.taper * pow(float(i) / maxf(n - 1, 1), 2.0)), 0.5)
					var c := _stroke[i]
					for y in range(int(floor(c.y - r)), int(ceil(c.y + r)) + 1):
						for x in range(int(floor(c.x - r)), int(ceil(c.x + r)) + 1):
							var cell := Vector2i(x, y)
							if seen.has(cell) or Vector2(x + 0.5, y + 0.5).distance_to(c) > maxf(r, 0.71):
								continue
							seen[cell] = true
							v.draw_rect(Rect2(v.to_screen(Vector2(x, y)), Vector2(v.zoom, v.zoom)), col)
			if _paint_hover.x > -50:
				if int(hair_pen.size) <= 1:
					v.draw_rect(Rect2(v.to_screen(_paint_hover.floor()), Vector2(v.zoom, v.zoom)), Color(1, 1, 1, 0.9), false, 1.0)
				else:
					v.draw_arc(v.to_screen(_paint_hover), half * v.zoom, 0, TAU, 32, Color(1, 1, 1, 0.9), 1.0)
		return
	if paint_mode:
		if _dot_mode() and v == (_paint_v if _paint_v != null else pix):
			# 線・四角の下がき、えんぴつが置くのを待っている画素
			var pc := Color(paint.color, 0.85) if not (_dshape.get("erase", false) or dot_tool == 1) else Color(1, 0.3, 0.3, 0.6)
			if not _dshape.is_empty():
				for c in _shape_cells(_dshape.a, _dshape.b, dot_tool):
					v.draw_rect(Rect2(v.to_screen(Vector2(c)), Vector2(v.zoom, v.zoom)), pc)
			if _pp_pending != null:
				v.draw_rect(Rect2(v.to_screen(Vector2(_pp_pending)), Vector2(v.zoom, v.zoom)), pc)
		# ペンの形
		if v == (_paint_v if _paint_v != null else pix) and _paint_hover.x > -50:
			var col := Color(1, 1, 1, 0.9)
			if int(paint.size) <= 1:
				v.draw_rect(Rect2(v.to_screen(_paint_hover.floor()), Vector2(v.zoom, v.zoom)), col, false, 1.0)
			else:
				v.draw_arc(v.to_screen(_paint_hover), paint.size * 0.5 * v.zoom, 0, TAU, 32, col, 1.0)
		return
	if shape_mode:
		return
	if solid_on and solid != null:
		_draw_solid_handles(v)
		return
	if not show_handles or joints.is_empty():
		return
	_aim(v)
	# 骨の線
	for b in ["hips", "spine", "chest", "neck", "head", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R",
			"thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]:
		var a: Vector3 = core.Project(joints[b])
		var c: Vector3 = core.Project(joints[b + "/tail"])
		v.draw_line(v.to_screen(Vector2(a.x, a.y)), v.to_screen(Vector2(c.x, c.y)), Color(0, 0, 0, 0.28), 1.0)
	for i in HANDLES.size():
		var p := handle_px(i)
		var s := v.to_screen(Vector2(p.x, p.y))
		var at: String = HANDLES[i].at
		var col := Color("#ffd24a")
		if ".L" in at:
			col = Color("#4aa8ff")
		elif ".R" in at:
			col = Color("#ff6a5a")
		var r := 4.0
		if HANDLES[i].has("ik") or HANDLES[i].has("move"):
			r = 5.5
		if i == _sel:
			v.draw_circle(s, r + 3.5, Color(1, 1, 1, 0.95))
		elif i == _hover:
			v.draw_circle(s, r + 2.5, Color(1, 1, 1, 0.7))
		v.draw_circle(s, r + 1.0, Color(0, 0, 0, 0.75))
		v.draw_circle(s, r, col)
	_aim(pix)


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed:
		return
	if e.ctrl_pressed and e.keycode == KEY_Z:
		if e.shift_pressed:
			redo()
		else:
			undo()
	elif e.ctrl_pressed and e.keycode == KEY_Y:
		redo()
	elif e.ctrl_pressed and e.keycode == KEY_S:
		_ask_save()
	elif e.ctrl_pressed or e.alt_pressed:
		return
	elif e.keycode >= KEY_0 and e.keycode <= KEY_9:
		var i: int = (e.keycode - KEY_0 + 9) % 10
		if i >= palette.size():
			return
		set_pen_color(palette[i])
	elif paint_mode and not e.ctrl_pressed and e.keycode in [KEY_B, KEY_E, KEY_G, KEY_L, KEY_U, KEY_I]:
		set_dot_tool({KEY_B: 0, KEY_E: 1, KEY_G: 2, KEY_L: 3, KEY_U: (5 if e.shift_pressed else 4), KEY_I: 6}[e.keycode])
	elif e.keycode == KEY_X:
		swap_colors()
	elif e.keycode == KEY_BRACKETLEFT or e.keycode == KEY_BRACKETRIGHT:
		paint.size = clampi(int(paint.size) + (1 if e.keycode == KEY_BRACKETRIGHT else -1), 1, 8)
		_sync("paint_size", paint.size)
		_redraw()
	elif e.keycode == KEY_R and ref.cell != null:
		if int(ref.mode) == 3:
			ref.mode = _ref_back
		else:
			_ref_back = int(ref.mode)
			ref.mode = 3
		_sync("ref_mode", int(ref.mode))
		_redraw()
	elif e.keycode == KEY_LEFT or e.keycode == KEY_RIGHT:
		view.yaw = fposmod(roundf(view.yaw / 45.0) * 45.0 + (45.0 if e.keycode == KEY_RIGHT else -45.0), 360.0)
		_sync("yaw", view.yaw)
		mark()
	else:
		return
	accept_event()


# --- ファイル -------------------------------------------------------------------------- #

func to_doc() -> Dictionary:
	var ps := []
	for p in poses:
		var bones := {}
		for b in p.rots:
			var e: Vector3 = Basis(p.rots[b]).get_euler(EULER_ORDER_YXZ)
			bones[b] = [snappedf(rad_to_deg(e.x), 0.01), snappedf(rad_to_deg(e.y), 0.01), snappedf(rad_to_deg(e.z), 0.01)]
		var o := {"name": p.name, "bones": bones, "root": [p.root.x, p.root.y, p.root.z]}
		var fx := {}
		for k in p.get("fix", {}):
			if not p.fix[k].is_empty():
				fx[k] = p.fix[k].keys().map(func(c: Vector2i): return [c.x, c.y, "#" + p.fix[k][c].to_html(true)])
		if not fx.is_empty():
			o["fix"] = fx
		if not p.get("sp", {}).is_empty() or p.get("sroot", Vector3.ZERO) != Vector3.ZERO:
			var sp := {}
			for k in p.get("sp", {}):
				var q: Quaternion = p.sp[k]
				sp[str(k)] = [snappedf(q.x, 0.00001), snappedf(q.y, 0.00001), snappedf(q.z, 0.00001), snappedf(q.w, 0.00001)]
			var sr: Vector3 = p.get("sroot", Vector3.ZERO)
			o["sp"] = sp
			o["sroot"] = [sr.x, sr.y, sr.z]
		ps.append(o)
	var html := func(cols: Array) -> Array: return cols.map(func(c: Color): return "#" + c.to_html(false))
	var st := style.duplicate(true)
	st.ramp = st.ramp.map(func(c: Color): return "#" + c.to_html(false))
	st.line = "#" + style.line.to_html(false)
	st.line_color = "#" + style.line_color.to_html(false)
	return {"app": "dot-Godough", "version": 1, "body": body, "auto_heads": auto_heads, "res": res, "view": view, "style": st,
			"poses": ps, "pose": pose_i, "ground": ground,
			"palette": html.call(palette), "ref": _ref_to_doc(),
			"solid": solid.to_doc() if solid != null else {}, "solid_on": solid_on,
			"hair": hair.merged({"color": "#" + hair.color.to_html(false), "ramp": html.call(hair.get("ramp", [])),
				"locks": hair.locks.map(func(l): return Array(l).map(func(x): return snappedf(x, 0.0001)))}, true),
			"paint": {"f": Array(_paint_data().f).map(func(x): return snappedf(x, 0.000001)), "i": Array(_paint_data().i)},
			"wear": garments.map(func(g: Dictionary):
				var o := g.duplicate()
				o["color"] = "#" + g.color.to_html(false)
				if g.has("ramp"):
					o["ramp"] = html.call(g.ramp)
				return o)}


func from_doc(d: Dictionary) -> void:
	for k in d.get("body", {}):
		if body.has(k):
			body[k] = float(d.body[k])
	auto_heads = d.get("auto_heads", true)
	res = d.get("res", 72.0)
	for k in d.get("view", {}):
		if view.has(k):
			view[k] = d.view[k]
	for k in ["w", "h", "smooth", "ss", "margin"]:
		view[k] = int(view[k])
	var st: Dictionary = d.get("style", {})
	for k in st:
		if not style.has(k):
			continue
		if k == "ramp":
			style.ramp = st.ramp.map(func(c): return Color(c))
		elif k in ["line", "line_color"]:
			style[k] = Color(st[k])
		elif k in ["shades", "line_mode", "rim"]:
			style[k] = int(st[k])
		else:
			style[k] = st[k]
	garments = []
	for g in d.get("wear", []):
		var o: Dictionary = g.duplicate()
		o["color"] = Color(g.get("color", "#808080"))
		if o.has("ramp"):
			o["ramp"] = o.ramp.map(func(c): return Color(c))
		garments.append(o)
	_gsel = mini(_gsel, garments.size() - 1)
	hair = hair_named("")
	for k in d.get("hair", {}):
		if k == "locks":
			hair.locks = d.hair.locks.map(func(l): return PackedFloat32Array(l))
		elif k == "ramp":
			if d.hair.ramp.size() == 5:
				hair["ramp"] = d.hair.ramp.map(func(c): return Color(c))
		else:
			hair[k] = Color(d.hair[k]) if k == "color" else d.hair[k]
	var pd: Dictionary = d.get("paint", {})
	core.SetPaint({"f": PackedFloat32Array(pd.get("f", [])), "i": PackedInt32Array(pd.get("i", []).map(func(x): return int(x)))})
	_paint_cache = null
	poses.clear()
	for p in d.get("poses", []):
		var bones := {}
		for b in p.get("bones", {}):
			var e: Array = p.bones[b]
			bones[b] = Vector3(e[0], e[1], e[2])
		var r: Array = p.get("root", [0, 0, 0])
		poses.append(make_pose(p.get("name", "ポーズ"), {"bones": bones, "root": Vector3(r[0], r[1], r[2])}))
		if p.has("fix"):
			var fx := {}
			for k in p.fix:
				fx[k] = {}
				for e in p.fix[k]:
					fx[k][Vector2i(int(e[0]), int(e[1]))] = Color(e[2])
			poses[-1]["fix"] = fx
		if p.has("sp"):
			var sp := {}
			for k in p.sp:
				var q: Array = p.sp[k]
				sp[int(k)] = Quaternion(q[0], q[1], q[2], q[3]).normalized()
			var sr: Array = p.get("sroot", [0, 0, 0])
			poses[-1]["sp"] = sp
			poses[-1]["sroot"] = Vector3(sr[0], sr[1], sr[2])
	palette = d.get("palette", PALETTE0).map(func(c): return Color(c))
	_refresh_palette()
	_ref_from_doc(d.get("ref", {}))
	solid = DotSolid.from_doc(d.solid) if not d.get("solid", {}).is_empty() else null
	solid_on = d.get("solid_on", false) and solid != null
	_sync("solid_on", solid_on)
	_sync_solid_ui()
	if poses.is_empty():
		poses = [make_pose("立ち", Poses.named("立ち", body.arm_angle, Poses.hang_for(body.heads)))]
	pose_i = clampi(int(d.get("pose", 0)), 0, poses.size() - 1)
	ground = d.get("ground", true)
	_undo.clear()
	_redo.clear()
	_sync_all()


func save_doc(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_doc(), " "))
	file_path = path
	_title()
	return true


func load_doc(path: String) -> bool:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return false
	from_doc(d)
	file_path = path
	_title()
	return true


func _title() -> void:
	get_window().title = "dot-Godough" + ("" if file_path == "" else " — " + file_path.get_file())


func _ask(mode: int, filters: PackedStringArray, name: String, cb: Callable) -> void:
	_dialog.file_mode = mode
	_dialog.filters = filters
	_dialog.current_file = name
	var last: String = _cfg.get_value("ui", "dir", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	_dialog.current_dir = last
	_dialog_cb = cb
	_dialog.popup_centered_ratio(0.7)


func _on_file(path: String) -> void:
	_cfg.set_value("ui", "dir", path.get_base_dir())
	_cfg.save(CFG)
	if _dialog_cb.is_valid():
		_dialog_cb.call(path)


func _ask_save() -> void:
	if file_path != "":
		save_doc(file_path)
		_hint.text = "保存しました: " + file_path
		return
	_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.dotg.json ; dot-Godough のキャラ"], "キャラ.dotg.json", func(p: String):
		if not p.ends_with(".json"):
			p += ".dotg.json"
		save_doc(p))


func _ask_open() -> void:
	_ask(FileDialog.FILE_MODE_OPEN_FILE, ["*.dotg.json ; dot-Godough のキャラ", "*.json"], "", func(p: String): load_doc(p))


func _ask_png() -> void:
	_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.png"], cur().name + ".png", func(p: String):
		if not p.ends_with(".png"):
			p += ".png"
		render_now().save_png(p)
		_hint.text = "書き出しました: " + p)


## ポーズ × 向きの表 (スプライトシート) と、その並びを書いた JSON
func export_sheet(path: String, dirs: int) -> void:
	var keep := pose_i
	var sheet := Image.create_empty(view.w * dirs, view.h * poses.size(), false, Image.FORMAT_RGBA8)
	for r in poses.size():
		pose_i = r
		apply_pose()
		for c in dirs:
			sheet.blend_rect(render_now(c * 360.0 / dirs), Rect2i(0, 0, view.w, view.h), Vector2i(c * view.w, r * view.h))
	pose_i = keep
	apply_pose()
	render_now()
	sheet.save_png(path)
	var f := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cell": [view.w, view.h], "rows": poses.map(func(p): return p.name),
				"cols": range(dirs).map(func(c): return c * 360.0 / dirs), "floor": view.h - view.margin}, " "))
	_hint.text = "書き出しました: " + path


func _ask_sheet(dirs: int) -> void:
	_ask(FileDialog.FILE_MODE_SAVE_FILE, ["*.png"], "シート.png", func(p: String):
		if not p.ends_with(".png"):
			p += ".png"
		export_sheet(p, dirs))


# --- penInk ---------------------------------------------------------------------------- #

func _body_key() -> String:
	return JSON.stringify([body, res, style.ramp.map(func(c: Color): return c.to_html(false)), garment_specs(garments),
			garments.map(func(g: Dictionary): return g.color.to_html(false))])


func penink_folder() -> String:
	return OS.get_user_data_dir().path_join("penink/dot")


func penink_request() -> Dictionary:
	var bones := {}
	for b in cur().rots:
		var e: Vector3 = Basis(cur().rots[b]).get_euler(EULER_ORDER_YXZ)
		bones[b] = [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]
	var root: Vector3 = cur().root + Vector3(0, _ground_off, 0)
	return {"yaw": fposmod(180.0 + view.yaw, 360.0), "pitch": view.pitch, "px": float(view.px) * _pk.PLAYER_H / float(body.height) * float(_w["pk_scale"].value),
			"bones": bones, "root": [root.x, root.y, root.z], "ground": false}


## いまの体を penInk 用に書き出して、同じポーズを描いてもらう
func penink_draw() -> void:
	if not _pk.available():
		_pk_status.text = "penInk が見つかりません (%s)。環境変数 PENINK で場所を教えてください" % _pk.penink_dir
		return
	var key := _body_key()
	if key != _pk_key or not (_pk.ready_ok or _pk.pid > 0):
		style_dict()
		core.SetStyle(style_dict())
		var err: String = core.ExportPenink(penink_folder(), "dot")
		if err != "":
			_pk_status.text = "書き出せませんでした: " + err
			return
		_pk_key = key
		_pk.start(penink_folder())
	_pk.draw(penink_request())


func _on_penink(img: Image, _sec: float) -> void:
	var used := img.get_used_rect()
	if used.size.x > 0:
		img = img.get_region(used.grow(4).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	var bgd := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	bgd.fill(Color("#f6f6f8"))
	bgd.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	_pk_tex.texture = ImageTexture.create_from_image(bgd)
	_pk_tex.custom_minimum_size = Vector2(bgd.get_size()) * (2 if bgd.get_width() <= 150 else 1)


func open_in_animator() -> void:
	core.SetStyle(style_dict())
	var folder := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("dot-Godough/penink/dot")
	var err: String = core.ExportPenink(folder, "dot")
	if err != "":
		_hint.text = "書き出せませんでした: " + err
		return
	var bat: String = _pk.penink_dir.path_join("Animator.bat")
	if FileAccess.file_exists(bat):
		OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\"), "--chara", folder.replace("/", "\\")], false)
		_hint.text = "penInk Animator を開いています: " + folder
	else:
		_hint.text = "penInk 用に書き出しました: " + folder


# --- 画面 ------------------------------------------------------------------------------ #

func _panel(min_w: int) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.x = min_w
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 6)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	v.set_meta("scroll", sc)
	return v


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


func _slider(parent: Control, key: String, label: String, lo: float, hi: float, step: float, cb: Callable, tip := "") -> HSlider:
	var h := HBoxContainer.new()
	h.tooltip_text = tip
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.scrollable = false
	s.tooltip_text = tip
	h.add_child(s)
	var n := Label.new()
	n.custom_minimum_size.x = 40
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(n)
	var fmt := "%d" if step >= 1.0 else ("%.1f" if step >= 0.1 else ("%.2f" if step >= 0.01 else "%.3f"))
	s.value_changed.connect(func(v: float):
		n.text = fmt % v
		if not _syncing:
			cb.call(v))
	n.text = fmt % lo
	parent.add_child(h)
	_w[key] = s
	return s


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


func _color(parent: Control, key: String, cb: Callable, tip := "") -> ColorPickerButton:
	var c := ColorPickerButton.new()
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(38, 24)
	c.tooltip_text = tip
	c.color_changed.connect(func(col: Color):
		if not _syncing:
			cb.call(col))
	parent.add_child(c)
	_w[key] = c
	return c


func _button(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _option(parent: Control, key: String, label: String, items: Array, cb: Callable) -> OptionButton:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	h.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for it in items:
		o.add_item(it)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i: int):
		if not _syncing:
			cb.call(i))
	h.add_child(o)
	parent.add_child(h)
	_w[key] = o
	return o


func _flow(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 3)
	parent.add_child(f)
	return f


func _sync(key: String, value) -> void:
	if not _w.has(key):
		return
	_syncing = true
	var c = _w[key]
	if c is HSlider:
		c.value = value
	elif c is CheckBox:
		c.button_pressed = value
	elif c is ColorPickerButton:
		c.color = value
	elif c is OptionButton:
		c.select(value)
	_syncing = false


func _sync_all() -> void:
	for k in body:
		_sync("b_" + k, body[k])
	_sync("auto_heads", auto_heads)
	_sync("res", res)
	for k in ["w", "h", "px", "yaw", "pitch", "cover", "smooth", "margin"]:
		_sync(k, view[k])
	for k in ["shadow", "light", "light_angle", "light_front", "inner", "one_line", "line_color", "despeckle", "rim_shadow", "line"]:
		_sync(k, style[k])
	_sync("shades", style.shades - 2)
	_sync("line_mode", style.line_mode)
	_sync("rim", style.rim)
	for i in 4:
		_sync("ramp%d" % i, style.ramp[i])
	_sync("ground", ground)
	_sync_pose_ui()
	_sync_wear_ui()
	_sync_hair_ui()
	mark("body")


func _sync_pose_ui() -> void:
	if _pose_list == null:
		return
	_pose_list.clear()
	for p in poses:
		_pose_list.add_item(p.name)
	_pose_list.select(pose_i)
	_sync_bone_sliders()


func _sync_bone_sliders() -> void:
	var b := ""
	if _sel >= 0 and HANDLES[_sel].has("bone"):
		b = HANDLES[_sel].bone
	_w["bone_name"].text = "選んでいる関節: " + (HANDLES[_sel].label if _sel >= 0 else "なし (絵の上の点をクリック)")
	var e := Vector3.ZERO
	if b != "":
		e = Basis(cur().rots.get(b, Quaternion.IDENTITY)).get_euler(EULER_ORDER_YXZ)
	for i in 3:
		var s: HSlider = _w["bone%d" % i]
		s.editable = b != ""
		_sync("bone%d" % i, rad_to_deg(e[i]))


func _set_bone_euler(axis: int, deg: float) -> void:
	if _sel < 0 or not HANDLES[_sel].has("bone"):
		return
	var b: String = HANDLES[_sel].bone
	var e: Vector3 = Basis(cur().rots.get(b, Quaternion.IDENTITY)).get_euler(EULER_ORDER_YXZ)
	e[axis] = deg_to_rad(deg)
	cur().rots[b] = Basis.from_euler(e, EULER_ORDER_YXZ).get_rotation_quaternion()
	mark("pose")


func set_heads(h: float, preset := false) -> void:
	body["heads"] = h
	if auto_heads or preset:
		body.merge(core.ForHeads(h), true)
		if preset:
			for p in core.ParamList():
				if p.key in ["taper", "head_d", "chibi", "leg_angle", "bust", "arm_angle"]:
					body[p.key] = p.def
			body["sex"] = 1.0 if is_equal_approx(h, 6.0) else (0.0 if h > 7.0 else 0.5)
		for k in body:
			_sync("b_" + k, body[k])
	mark("body")


func ramp_from(base: Color) -> void:
	# ドット絵の色の段: 影は暗く・鮮やかに・色みを赤紫のほうへ、明るい所は薄く・黄みへ (色相をずらす)
	var h := base.h
	var s := base.s
	var v := base.v
	style.ramp = [
		Color.from_hsv(fposmod(h - 0.035, 1.0), clampf(s * 1.75 + 0.06, 0, 1), v * 0.72),
		Color.from_hsv(fposmod(h - 0.018, 1.0), clampf(s * 1.4 + 0.03, 0, 1), v * 0.87),
		base,
		Color.from_hsv(fposmod(h + 0.012, 1.0), s * 0.55, minf(1.0, v * 1.04 + 0.02)),
	]
	style.line = Color.from_hsv(fposmod(h - 0.05, 1.0), clampf(s * 1.6 + 0.15, 0, 1), v * 0.42)
	for i in 4:
		_sync("ramp%d" % i, style.ramp[i])
	_sync("line", style.line)
	mark()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = XP.FACE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(_on_file)
	add_child(_dialog)

	# 道具の行
	var barp := PanelContainer.new()
	barp.add_theme_stylebox_override("panel", XP.flat(XP.FACE, Color("#D5D2C2"), 0, 0, 4))
	root.add_child(barp)
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 4)
	barp.add_child(bar)
	_button(bar, "新しく", func():
		file_path = ""
		from_doc({})
		set_heads(3.0, true)
		_title())
	_button(bar, "開く", _ask_open)
	_button(bar, "保存", _ask_save, "Ctrl+S")
	bar.add_child(VSeparator.new())
	_button(bar, "PNG に書き出す", _ask_png, "いまの絵を 1 枚 (等倍)")
	_button(bar, "シート (4 方向)", func(): _ask_sheet(4), "ポーズ × 4 方向の表")
	_button(bar, "シート (8 方向)", func(): _ask_sheet(8), "ポーズ × 8 方向の表")
	_button(bar, "モデルを書き出す", _ask_model, "立体 (ドット絵モデル) を、アニメーション用のアプリ dot-Godough モーション で開けるファイルに書き出す")
	bar.add_child(VSeparator.new())
	_button(bar, "元に戻す", undo, "Ctrl+Z (ポーズ)")
	_button(bar, "やり直す", redo, "Ctrl+Y")
	bar.add_child(VSeparator.new())
	_button(bar, "全体を表示", fit_all)
	_check(bar, "grid", "ます目", func(on: bool):
		pix.grid = on
		pix2.grid = on
		_redraw())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	# 左: 体型・画風・ポーズ
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 330
	split.add_child(tabs)
	_tabs_l = tabs
	_build_body_tab(tabs)
	_build_wear_tab(tabs)
	_build_look_tab(tabs)
	_build_pose_tab(tabs)
	_build_paint_tab(tabs)
	_build_hair_tab(tabs)
	_build_ref_tab(tabs)
	tabs.tab_changed.connect(func(i: int):
		ref_mode = i == _ref_tab
		_ref_moving = false
		paint_mode = i == _paint_tab
		hair_mode = hair_pen.on and i == _hair_tab
		_stroking = false
		_painting = 0
		_shape = {}
		shape_mode = shape_on and i == 0
		_redraw())

	var split2 := HSplitContainer.new()
	split2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(split2)

	# 真ん中: ドット絵
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	split2.add_child(mid)
	var vb := _flow(mid)
	for d in 8:
		var names := ["正面", "左ななめ前", "左", "左ななめ後ろ", "後ろ", "右ななめ後ろ", "右", "右ななめ前"]
		var yaw := d * 45.0
		_button(vb, names[d], func():
			view.yaw = yaw
			_sync("yaw", yaw)
			mark())
	pix = DotView.new()
	pix.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pix.overlay = _draw_handles
	pix.wheel_handler = _on_wheel
	pix.pressed.connect(_on_pressed)
	pix.dragged.connect(_on_dragged)
	pix.released.connect(_on_released)
	pix.hovered.connect(_on_hover)
	var views := HBoxContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.add_theme_constant_override("separation", 2)
	mid.add_child(views)
	pix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pix.size_flags_stretch_ratio = 1.5
	views.add_child(pix)
	pix2 = DotView.new()
	pix2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pix2.overlay = _draw_handles
	pix2.wheel_handler = func(px: Vector2, dir: int) -> bool: return _on_wheel(px, dir, pix2)
	pix2.pressed.connect(_on_pressed.bind(pix2))
	pix2.dragged.connect(_on_dragged.bind(pix2))
	pix2.released.connect(_on_released.bind(pix2))
	pix2.hovered.connect(_on_hover.bind(pix2))
	views.add_child(pix2)
	var vrow := HBoxContainer.new()
	mid.add_child(vrow)
	var c1 := VBoxContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(c1)
	_slider(c1, "yaw", "向き", 0, 360, 1, func(v: float):
		view.yaw = v
		mark())
	var c2 := VBoxContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(c2)
	_slider(c2, "pitch", "見下ろす角度", 0, 60, 1, func(v: float):
		view.pitch = v
		mark())
	_check(vrow, "snap_yaw", "45° にそろえる", func(on: bool): snap_yaw = on)
	_w["snap_yaw"].set_pressed_no_signal(true)
	_check(vrow, "side_view", "横からも見る", func(on: bool):
		side_view = on
		pix2.visible = on
		fit_all.call_deferred()
		mark(), "横から見た絵を並べます。奥行き (手前・奥) がそのまま左右に見えて、そこでも点をつまめます")
	_w["side_view"].set_pressed_no_signal(true)
	_build_palette_bar(mid)

	# 右: 見え方・penInk・3D
	_tabs_r = TabContainer.new()
	_tabs_r.custom_minimum_size.x = 330
	split2.add_child(_tabs_r)
	_tabs_r.tab_changed.connect(func(_i: int): mark())
	_build_preview_tab(_tabs_r)
	_build_penink_tab(_tabs_r)
	_build_3d_tab(_tabs_r)
	split2.split_offset = 4000

	# 下の行
	var st := PanelContainer.new()
	st.add_theme_stylebox_override("panel", XP.flat(XP.FACE, Color("#D5D2C2"), 0, 0, 4))
	root.add_child(st)
	var sh := HBoxContainer.new()
	st.add_child(sh)
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.clip_text = true
	sh.add_child(_hint)
	_info = Label.new()
	sh.add_child(_info)


func _build_body_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "体型"
	tabs.add_child(v.get_meta("scroll"))
	_head(v, "ひな形 (頭身)")
	var f := _flow(v)
	for h in [2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 7.5]:
		_button(f, ("%.1f" % h).trim_suffix(".0"), func(): set_heads(h, true),
				"low-Godough の既定 (アニメ 少女)" if h == 6.0 else "")
	_check(v, "auto_heads", "頭身を動かすと、体型もいっしょに変える", func(on: bool): auto_heads = on,
			"切ると、頭の大きさだけが変わります")
	_check(v, "shape_on", "絵の上で輪郭をつまんで形を変える", func(on: bool):
		shape_on = on
		shape_mode = on and _tabs_l.current_tab == 0
		_redraw(), "このタブを開いているあいだ、体をつまむと その部品の太さ・長さが変わります (ポーズの点は出ません。ポーズは「ポーズ」タブで)")
	_w["shape_on"].set_pressed_no_signal(true)
	shape_mode = shape_on
	var lim := {}
	for p in core.ParamList():
		lim[p.key] = p
	_lim = lim
	for sec in BODY_UI:
		_head(v, sec[0])
		for it in sec[1]:
			var key: String = it[0]
			_plabel[key] = it[1]
			if key == "heads":
				_slider(v, "b_heads", it[1], lim[key].min, lim[key].max, it[2], func(x: float): set_heads(x), it[3])
			else:
				_slider(v, "b_" + key, it[1], lim[key].min, lim[key].max, it[2], func(x: float):
					body[key] = x
					mark("body"), it[3])
	_head(v, "網目")
	_slider(v, "res", "細かさ", 40, 140, 1, func(x: float):
		res = x
		mark("body"), "身長を何ますに割るか。細い手足が切れるときは上げる")


func add_clothes(name: String) -> void:
	_gsel = wear(garments, clothes_named(name))
	_sync_wear_ui()
	mark("body")


func _gset(key: String, x: float) -> void:
	if _gsel < 0 or _gsel >= garments.size():
		return
	garments[_gsel][key] = x
	mark("body")


func _sync_wear_ui() -> void:
	_sync_mat_ui.call_deferred()
	if _glist == null:
		return
	_glist.clear()
	for g in garments:
		_glist.add_item(g.name)
	_gsel = clampi(_gsel, -1, garments.size() - 1)
	if _gsel >= 0:
		_glist.select(_gsel)
	var g: Dictionary = garments[_gsel] if _gsel >= 0 else {}
	var kind: String = g.get("kind", "")
	var keys := {"body": ["from", "to", "thick", "flare", "sleeve", "sleeve_flare"], "arm": ["from", "to", "thick", "flare"],
			"skirt": ["from", "to", "thick", "flare", "follow"]}
	_syncing = true
	for k in ["from", "to", "thick", "flare", "sleeve", "sleeve_flare", "follow"]:
		var sl: HSlider = _w["g_" + k]
		var on: bool = kind != "" and k in keys[kind]
		sl.get_parent().visible = on
		if k in ["from", "to"]:
			sl.max_value = 3.0 if kind == "arm" else 6.0
		if k == "flare":
			sl.max_value = 12.0 if kind == "skirt" else 4.0
		if on:
			sl.value = g.get(k, 0.0)
	_w["g_color"].get_parent().visible = kind != ""
	if kind != "":
		_w["g_color"].color = g.color
	_w["g_scale"].text = "" if kind == "" else ("目盛り: 0 肩・1 ひじ・2 手首・3 指先" if kind == "arm" \
			else "目盛り: 0 あご・1 肩・2 くびれ・3 股・4 ひざ・5 足首・6 地面")
	_syncing = false


func _build_wear_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "服"
	tabs.add_child(v.get_meta("scroll"))
	_head(v, "ひな形から足す")
	var f := _flow(v)
	for c in CLOTHES:
		var n: String = c[0]
		_button(f, n, func(): add_clothes(n))
	_head(v, "着ているもの (下の行ほど上に重なる)")
	_glist = ItemList.new()
	_glist.custom_minimum_size.y = 130
	_glist.focus_mode = Control.FOCUS_NONE
	_glist.item_selected.connect(func(i: int):
		_gsel = i
		_sync_wear_ui())
	v.add_child(_glist)
	var f2 := _flow(v)
	var move := func(d: int):
		var j := _gsel + d
		if _gsel < 0 or j < 0 or j >= garments.size():
			return
		var t = garments[_gsel]
		garments[_gsel] = garments[j]
		garments[j] = t
		_gsel = j
		_sync_wear_ui()
		mark("body")
	_button(f2, "下に重ねる", func(): move.call(-1), "一覧で上へ = 体に近い側へ")
	_button(f2, "上に重ねる", func(): move.call(1))
	_button(f2, "ぬぐ", func():
		if _gsel < 0:
			return
		garments.remove_at(_gsel)
		_sync_wear_ui()
		mark("body"))
	_button(f2, "全部ぬぐ", func():
		garments.clear()
		_gsel = -1
		_sync_wear_ui()
		mark("body"))
	_head(v, "選んだ服")
	var cr := HBoxContainer.new()
	v.add_child(cr)
	var cl := Label.new()
	cl.text = "色"
	cl.custom_minimum_size.x = 96
	cr.add_child(cl)
	_color(cr, "g_color", func(c: Color):
		if _gsel >= 0:
			garments[_gsel].color = c
			garments[_gsel].erase("ramp")
			_sync_mat_ui.call_deferred()
			mark())
	_slider(v, "g_from", "上の端", 0, 6, 0.05, func(x: float): _gset("from", x))
	_slider(v, "g_to", "下の端", 0, 6, 0.05, func(x: float): _gset("to", x))
	_slider(v, "g_thick", "厚み", 0, 6, 0.1, func(x: float): _gset("thick", x), "身長の 100 分の 1 が単位。0 なら体の形のまま色だけ変わります")
	_slider(v, "g_flare", "下の端の広がり", 0, 4, 0.1, func(x: float): _gset("flare", x),
			"すそ (スカート) は、立ち姿の脚より内側にはなりません (足りない分は自動で広がります)")
	_slider(v, "g_sleeve", "そでの長さ", 0, 3, 0.05, func(x: float): _gset("sleeve", x), "0 = そでなし、1 = ひじ、2 = 手首")
	_slider(v, "g_sleeve_flare", "そで口の広がり", 0, 4, 0.1, func(x: float): _gset("sleeve_flare", x))
	_slider(v, "g_follow", "脚についていく", 0, 1, 0.05, func(x: float): _gset("follow", x),
			"歩く・すわるとき、すそがどれだけ太ももについていくか")
	_w["g_scale"] = _note(v, "")
	_note(v, "肌は服を突き抜けません (服の下の肌は作っていません)。重なった所の色は、一覧で下にある服になります。")


func _build_look_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "ドット絵"
	tabs.add_child(v.get_meta("scroll"))
	_head(v, "大きさ")
	_slider(v, "px", "キャラの高さ", 12, 200, 1, func(x: float):
		view.px = x
		mark(), "立っているキャラの高さ (画素)")
	_slider(v, "w", "紙の幅", 8, 256, 1, func(x: float):
		view.w = int(x)
		mark())
	_slider(v, "h", "紙の高さ", 8, 256, 1, func(x: float):
		view.h = int(x)
		mark())
	_slider(v, "margin", "足もとの余白", 0, 24, 1, func(x: float):
		view.margin = int(x)
		mark())
	var f := _flow(v)
	for s in [[32, 32, 28], [48, 48, 42], [64, 64, 56], [96, 96, 84], [128, 128, 112]]:
		_button(f, "%d×%d" % [s[0], s[1]], func():
			view.w = s[0]
			view.h = s[1]
			view.px = float(s[2])
			_sync("w", s[0])
			_sync("h", s[1])
			_sync("px", s[2])
			mark()
			fit_all.call_deferred())
	_head(v, "肌の色")
	var cr := HBoxContainer.new()
	v.add_child(cr)
	var names := ["濃い影", "影", "基本", "明るい"]
	for i in [3, 2, 1, 0]:
		_color(cr, "ramp%d" % i, func(c: Color):
			style.ramp[i] = c
			mark(), names[i])
	var sp := Control.new()
	sp.custom_minimum_size.x = 10
	cr.add_child(sp)
	_color(cr, "line", func(c: Color):
		style.line = c
		mark(), "線")
	_button(v, "「基本」の色から、ほかの色を作る", func(): ramp_from(style.ramp[2]),
			"影は暗く鮮やかに赤みへ、明るい所は薄く黄みへ")
	_option(v, "shades", "色の段の数", ["2 段", "3 段", "4 段"], func(i: int):
		style.shades = i + 2
		mark())
	_head(v, "素材ごとの色 (肌・服・髪)")
	_note(v, "左から 明るい・基本・影・濃い影、はなれて線。左クリック = ペンの色 (絵の下のパレットで選んだ色) を入れる / 右クリック = その色をペンの色にする")
	_mat_box = VBoxContainer.new()
	_mat_box.add_theme_constant_override("separation", 2)
	v.add_child(_mat_box)
	_head(v, "光")
	_slider(v, "light_angle", "光の来る向き", -180, 180, 1, func(x: float):
		style.light_angle = x
		mark(), "0 = 真上から、マイナス = 左上から")
	_slider(v, "light_front", "手前からの光", 0, 0.95, 0.01, func(x: float):
		style.light_front = x
		mark())
	_slider(v, "shadow", "影の広さ", -0.6, 0.8, 0.01, func(x: float):
		style.shadow = x
		mark())
	_slider(v, "light", "明るい所の広さ", 0, 0.8, 0.01, func(x: float):
		style.light = x
		mark())
	_head(v, "線")
	_option(v, "line_mode", "ふちの線", ["なし", "外 (1 画素足す)", "内 (ふちの画素を線に)"], func(i: int):
		style.line_mode = i
		mark())
	_check(v, "inner", "重なった部品の境目にも線", func(on: bool):
		style.inner = on
		mark())
	var lr := HBoxContainer.new()
	v.add_child(lr)
	_check(lr, "one_line", "線を 1 色にする", func(on: bool):
		style.one_line = on
		mark())
	_color(lr, "line_color", func(c: Color):
		style.line_color = c
		mark())
	_head(v, "画素の決め方")
	_slider(v, "cover", "細らせる ↔ 太らせる", 0.1, 0.9, 0.01, func(x: float):
		view.cover = 1.0 - x
		mark(), "画素にどれだけ体がかかっていたら塗るか")
	_slider(v, "smooth", "面をならす", 0, 4, 1, func(x: float):
		view.smooth = int(x)
		mark(), "小さい絵で、でこぼこが斑点になるのを防ぐ")
	_check(v, "despeckle", "孤立した 1 画素をまわりに合わせる", func(on: bool):
		style.despeckle = on
		mark())
	_head(v, "ふちの濃い色 (試作)")
	_note(v, "くわしい説明を聞いてから作り直す予定の、仮のものです。")
	_slider(v, "rim", "幅 (画素)", 0, 3, 1, func(x: float):
		style.rim = int(x)
		mark())
	_check(v, "rim_shadow", "光と反対の側だけ", func(on: bool):
		style.rim_shadow = on
		mark())


func _build_pose_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "ポーズ"
	tabs.add_child(v.get_meta("scroll"))
	_head(v, "ポーズの一覧")
	_pose_list = ItemList.new()
	_pose_list.custom_minimum_size.y = 130
	_pose_list.focus_mode = Control.FOCUS_NONE
	_pose_list.item_selected.connect(func(i: int):
		pose_i = i
		_sync_bone_sliders()
		mark("pose"))
	v.add_child(_pose_list)
	var f := _flow(v)
	_button(f, "ふやす", func():
		var p := cur()
		poses.insert(pose_i + 1, {"name": p.name + " 2", "rots": p.rots.duplicate(), "root": p.root,
				"sp": p.get("sp", {}).duplicate(), "sroot": p.get("sroot", Vector3.ZERO)})
		pose_i += 1
		_sync_pose_ui()
		mark("pose"), "いまのポーズの写しを足す")
	_button(f, "消す", func():
		if poses.size() <= 1:
			return
		poses.remove_at(pose_i)
		pose_i = clampi(pose_i, 0, poses.size() - 1)
		_sync_pose_ui()
		mark("pose"))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "名前を変える (Enter)"
	name_edit.custom_minimum_size.x = 140
	name_edit.text_submitted.connect(func(t: String):
		if t.strip_edges() != "":
			cur().name = t.strip_edges()
			_sync_pose_ui()
		name_edit.text = ""
		name_edit.release_focus())
	f.add_child(name_edit)
	_note(v, "「立体」を見ているあいだは、ひな形・左右を入れかえる・全部もどす が 立体のポーズに効きます (その下の 地面・足・関節の角度は 体型で作った体だけ)。")
	_head(v, "ひな形のポーズをあてはめる")
	var f2 := _flow(v)
	for n in Poses.names():
		_button(f2, n, func():
			if solid_on and solid != null:
				# 立体を見ているあいだは、立体のポーズにする (無い名前は 立ち)
				solid_preset(n)
				if cur().name.begins_with("ポーズ") or cur().name in Poses.names():
					cur().name = n
				_sync_pose_ui()
				_hint.text = "立体のポーズ: " + n
				return
			push_undo()
			var p: Dictionary = Poses.named(n, body.arm_angle, Poses.hang_for(body.heads))
			cur().rots = Poses.to_quats(p)
			cur().root = Vector3.ZERO
			apply_pose()
			if auto_arms:
				fix_arms()
			if cur().name.begins_with("ポーズ") or cur().name in Poses.names():
				cur().name = n
			_sync_pose_ui()
			mark("pose"))
	_head(v, "直す")
	var f3 := _flow(v)
	_button(f3, "左右を入れかえる", func():
		push_undo()
		if solid_on and solid != null:
			var sw := {3: 4, 4: 3, 5: 6, 6: 5, 7: 8, 8: 7, 9: 10, 10: 9, 12: 13, 13: 12}
			var sp2 := {}
			for k in cur().get("sp", {}):
				var q2 := Quaternion(cur().sp[k])
				sp2[sw.get(int(k), int(k))] = Quaternion(q2.x, -q2.y, -q2.z, q2.w)
			cur()["sp"] = sp2
			var r2 := Vector3(cur().get("sroot", Vector3.ZERO))
			cur()["sroot"] = Vector3(-r2.x, r2.y, r2.z)
			mark()
			return
		var out := {}
		for b in cur().rots:
			var o: String = b
			if b.ends_with(".L"):
				o = b.left(-2) + ".R"
			elif b.ends_with(".R"):
				o = b.left(-2) + ".L"
			var q: Quaternion = cur().rots[b]
			out[o] = Quaternion(q.x, -q.y, -q.z, q.w)
		cur().rots = out
		cur().root.x = -cur().root.x
		_sync_bone_sliders()
		mark("pose"))
	_button(f3, "全部もどす", func():
		push_undo()
		if solid_on and solid != null:
			cur()["sp"] = {}
			cur()["sroot"] = Vector3.ZERO
			mark()
			return
		cur().rots = {}
		cur().root = Vector3.ZERO
		_sync_bone_sliders()
		mark("pose"), "作るときの姿勢 (腕を開いた形) にもどす")
	_check(v, "ground", "地面に立たせる", func(on: bool):
		ground = on
		mark("pose"), "いちばん低い所が地面に来るように、体を上下させる")
	_check(v, "pin_feet", "腰を動かしても、足は地面に残す", func(on: bool): pin_feet = on,
			"腰の大きい点を下げるとしゃがみ、横へ動かすと片足に乗ります")
	_w["pin_feet"].set_pressed_no_signal(true)
	_check(v, "keep_feet", "脚を動かしても、足の裏の向きを保つ", func(on: bool): keep_feet = on)
	_w["keep_feet"].set_pressed_no_signal(true)
	_check(v, "mirror_edit", "左右いっしょに動かす", func(on: bool): mirror_edit = on,
			"片方の腕や脚を動かすと、反対側も鏡写しに動きます")
	_check(v, "auto_arms", "腕を胴や服にめり込ませない", func(on: bool): auto_arms = on,
			"体や服を変えたとき・ひな形のポーズをあてはめたときに、入らなくなるまで腕を開きます")
	_w["auto_arms"].set_pressed_no_signal(true)
	_button(v, "いま、腕のめり込みを直す", func():
		push_undo()
		fix_arms()
		_sync_bone_sliders()
		mark("pose"))
	_check(v, "handles", "つまむ点を出す", func(on: bool):
		show_handles = on
		_redraw())
	_w["handles"].set_pressed_no_signal(true)
	_head(v, "関節の角度")
	var bn := Label.new()
	v.add_child(bn)
	_w["bone_name"] = bn
	var labs := ["前へ倒す", "左へひねる", "左へ倒す"]
	for i in 3:
		var s := _slider(v, "bone%d" % i, labs[i], -180, 180, 1, func(x: float): _set_bone_euler(i, x))
		s.drag_started.connect(push_undo)
	_note(v, "絵の上の点をつまんで動かすのが早道です。手首・足首は、ひじ・ひざがついてきます。\n奥行き (手前・奥) は、右の「横から」の絵でつまむか、Shift を押しながら上下に動かします。")


func _build_hair_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "髪"
	tabs.add_child(v.get_meta("scroll"))
	_hair_tab = tabs.get_tab_count() - 1
	_head(v, "ペンで描く")
	_check(v, "hp_on", "絵の上に髪を描く", func(on: bool):
		hair_pen.on = on
		hair_mode = on and _tabs_l.current_tab == _hair_tab
		_redraw(), "このタブを開いているあいだ、絵の上に引いた線が髪の房 (立体) になります。切ると、いつものように向きを回せます")
	_w["hp_on"].set_pressed_no_signal(hair_pen.on)
	_note(v, "左ボタン = 髪を描く / 右ボタン = 消しゴム / Ctrl+Z = 1 筆もどす\n絵を描くのと同じで、塗った所がそのまま髪になり、消した所の髪が消えます。ボタンを離すと立体になるので、向きを変えても (← → キー) ついてきます。")
	_slider(v, "hp_size", "太さ (画素)", 1, 12, 1, func(x: float): hair_pen.size = int(x))
	_slider(v, "hp_taper", "抜き (線の終わりを細く)", 0.0, 0.95, 0.01, func(x: float): hair_pen.taper = x, "0 = 同じ太さのまま。大きいほど、線の終わりがとがります (毛先・アホ毛に)")
	_check(v, "hp_mirror", "左右対称に描く", func(on: bool): hair_pen.mirror = on, "頭の左右反対側にも同じように描きます (ツインテールなど)")
	_check(v, "hp_lines", "描いた髪を線で分ける", func(on: bool):
		hair.lock_sep = on
		mark("body"), "ふだんは切っておきます (描いた髪は ひな形の髪と ひとかたまり)。入れると、描いた髪と ひな形の髪の境に線が出ます")
	_w["hp_mirror"].set_pressed_no_signal(hair_pen.mirror)
	_sync("hp_size", hair_pen.size)
	_sync("hp_taper", hair_pen.taper)
	_button(v, "描いた髪を全部消す", clear_locks, "Ctrl+Z で戻せます")
	_head(v, "ひな形")
	var f := _flow(v)
	for n in ["なし", "ショート", "ボブ", "ロング"]:
		_button(f, n, func(): set_hair(n))
	_head(v, "色")
	var hr := HBoxContainer.new()
	v.add_child(hr)
	_color(hr, "hair_color", func(col: Color):
		hair.color = col
		hair.erase("ramp")
		_sync_mat_ui.call_deferred()
		mark())
	for col in ["#5a3e2e", "#2a2430", "#c9a24a", "#b0502e", "#e8a0b0", "#5a78b8", "#e8e4dc", "#4a8a6a"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", XP.flat(Color(col), Color.BLACK, 1))
		b.add_theme_stylebox_override("hover", XP.flat(Color(col), Color.WHITE, 1))
		b.add_theme_stylebox_override("pressed", XP.flat(Color(col), Color.WHITE, 1))
		b.pressed.connect(func():
			hair.color = Color(col)
			hair.erase("ramp")
			_sync("hair_color", hair.color)
			_sync_mat_ui.call_deferred()
			mark())
		hr.add_child(b)
	_head(v, "形")
	for it in HAIR_UI:
		var key: String = it[0]
		_slider(v, "h_" + key, it[1], it[2], it[3], it[4], func(x: float):
			hair[key] = x
			mark("body"), it[5])
	_note(v, "髪は頭を少しふくらませた形で、前髪・横・後ろの 3 つの長さで切っています。頭のいちばん広い所から下は、まっすぐ垂れます。\nツインテール・アホ毛・おだんごなど頭から離れる形は、上のペンで描きます (ひな形「なし」のまま、ペンだけで作ることもできます)。")


func _build_paint_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "塗る"
	tabs.add_child(v.get_meta("scroll"))
	_paint_tab = tabs.get_tab_count() - 1
	_note(v, "このタブを開いているあいだ、真ん中の絵の上を塗れます。塗った色は体に貼りつくので、向きやポーズを変えてもついてきます。")
	_note(v, "左ボタン = 塗る / 右ボタン = 消す / Alt + 左 = 絵の色を拾う / Alt + 右 = お手本の色を拾う。色は絵の下のパレットで選べます")
	_head(v, "塗る先")
	_option(v, "paint_target", "どこに塗る", ["体の面 (向きを変えてもついてくる)", "この絵の画素 (この向き・このポーズだけ)"], func(i: int):
		paint.target = i)
	_note(v, "「この絵の画素」は、できあがった絵の 1 画素をそのままの色にします (ドット直し)。線の上や、体の外にも置けます。右ボタン = 直しを取りのぞく。")
	_check(v, "paint_clear", "透明にする (画素を消す)", func(on: bool): paint.clear = on, "「この絵の画素」のとき: 色を置くかわりに、その画素を何も無い所にします")
	_head(v, "ペンの種類")
	_option(v, "paint_kind", "何を塗る", ["色", "明るく (ハイライト)", "もっと明るく", "暗く (影)", "もっと暗く"], func(i: int):
		paint.kind = [0, 1, 2, -1, -2][i])
	_note(v, "「明るく」「暗く」は色を置かずに、その場所の色を 1 段 (もっと = 2 段) 明るく・暗くします。髪でも肌でも服でも、下の色に合った色になります。色の塗りの上にも重ねられます。")
	_head(v, "色")
	var hr := HBoxContainer.new()
	v.add_child(hr)
	var c := _color(hr, "paint_color", func(col: Color): set_pen_color(col, true))
	c.color = paint.color
	for col in ["#2a2030", "#ffffff", "#c8323c", "#f0c040", "#3f8a4a", "#3b6fb0", "#e8a0a8", "#6b3f36"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", XP.flat(Color(col), Color.BLACK, 1))
		b.add_theme_stylebox_override("hover", XP.flat(Color(col), Color.WHITE, 1))
		b.add_theme_stylebox_override("pressed", XP.flat(Color(col), Color.WHITE, 1))
		b.pressed.connect(func(): set_pen_color(Color(col)))
		hr.add_child(b)
	_head(v, "ドット絵の道具")
	_note(v, "立体・「この絵の画素」に描くときの道具。右ボタンは どの道具でも「消す」。Alt + クリックで色を拾う。立体では、描いた画素は 立体の上でも空中でも同じように置かれ、消すと 立体もけずれます。")
	var tf := _flow(v)
	var tkeys := ["B", "E", "G", "L", "U", "Shift+U", "I"]
	for ti in DOT_TOOLS.size():
		var tb := _button(tf, DOT_TOOLS[ti], func(): set_dot_tool(ti), tkeys[ti])
		tb.toggle_mode = true
		tb.button_pressed = ti == 0
		_w["dot_tool_%d" % ti] = tb
	_check(v, "dot_perfect", "かどの よぶんな画素を置かない (太さ 1)", func(on: bool): dot_perfect = on,
			"ななめに引くとき、L 字のかどに入る 1 画素を置きません (1 画素のきれいな線になる)")
	_w["dot_perfect"].set_pressed_no_signal(true)
	_head(v, "ペン")
	_slider(v, "paint_size", "太さ (画素)", 1, 8, 1, func(x: float): paint.size = int(x))
	_check(v, "paint_shade", "光に合わせて影をつける", func(on: bool): paint.flat = not on,
			"入れると、服と同じように明るい所・暗い所で色が変わります。切ると塗った色そのままで、線よりも上に出ます (目や口は切るのがおすすめ)")
	_w["paint_shade"].set_pressed_no_signal(true)
	_check(v, "paint_mirror", "左右対称に塗る", func(on: bool): paint.mirror = on, "体の左右反対側の同じ所にも塗ります")
	_head(v, "直す")
	_button(v, "塗りを全部消す", clear_paint, "Ctrl+Z で戻せます")
	var info := Label.new()
	v.add_child(info)
	_w["paint_info"] = info
	_note(v, "体型や服の厚みを変えても、塗りは残ります (体の部分といっしょに伸び縮みします)。\n体から離れた形 (フリルなど) は塗りでは作れません。penInk には まだ渡りません。")


func _build_preview_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "見え方"
	tabs.add_child(v.get_meta("scroll"))
	var hr := HBoxContainer.new()
	v.add_child(hr)
	var l := Label.new()
	l.text = "背景の色"
	hr.add_child(l)
	var c := _color(hr, "prev_bg", func(col: Color):
		_prev_bg = col
		mark())
	c.color = _prev_bg
	for col in ["#6a8f5a", "#8a8f9a", "#2a2a35", "#f4f0e6"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", XP.flat(Color(col), Color.BLACK, 1))
		b.add_theme_stylebox_override("hover", XP.flat(Color(col), Color.WHITE, 1))
		b.add_theme_stylebox_override("pressed", XP.flat(Color(col), Color.WHITE, 1))
		b.pressed.connect(func():
			_prev_bg = Color(col)
			c.color = _prev_bg
			mark())
		hr.add_child(b)
	_head(v, "等倍・2 倍・3 倍")
	var pr := HBoxContainer.new()
	pr.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_child(pr)
	for i in 3:
		var t := TextureRect.new()
		t.stretch_mode = TextureRect.STRETCH_KEEP
		t.size_flags_vertical = Control.SIZE_SHRINK_END
		pr.add_child(t)
		_prev.append(t)
	_head(v, "8 方向 (クリックでその向きへ)")
	_strip = TextureRect.new()
	_strip.stretch_mode = TextureRect.STRETCH_SCALE
	_strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _strip.size.x > 0:
			var cx := clampi(int(e.position.x / _strip.size.x * 4.0), 0, 3)
			var cy := clampi(int(e.position.y / _strip.size.y * 2.0), 0, 1)
			view.yaw = (cy * 4 + cx) * 45.0
			_sync("yaw", view.yaw)
			mark())
	v.add_child(_strip)


func _build_penink_tab(tabs: TabContainer) -> void:
	var v := _panel(320)
	v.get_meta("scroll").name = "penInk"
	tabs.add_child(v.get_meta("scroll"))
	_note(v, "同じ体・同じポーズ・同じ向きを、penInk (手描き風) に描いてもらいます。")
	var f := _flow(v)
	_button(f, "penInk で描く", penink_draw)
	_button(f, "penInk Animator で開く", open_in_animator, "ドキュメント/dot-Godough/penink に書き出して開く")
	_check(v, "pk_auto", "ポーズや向きを変えたら描き直す", func(on: bool): _pk_auto = on)
	_slider(v, "pk_scale", "大きさ (倍)", 1, 6, 0.5, func(_x: float):
		if _pk.ready_ok:
			_pk.draw(penink_request()), "penInk の絵は、線を引くぶん大きく描くほうがきれい")
	_w["pk_scale"].value = 3.0
	_pk_status = _note(v, "")
	_pk_tex = TextureRect.new()
	_pk_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_pk_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pk_tex.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(_pk_tex)


func _build_3d_tab(tabs: TabContainer) -> void:
	var box := VBoxContainer.new()
	box.name = "3D"
	tabs.add_child(box)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	_cam3d = Camera3D.new()
	_cam3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam3d.near = 0.1
	_cam3d.far = 40.0
	sv.add_child(_cam3d)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	sv.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#8a8f9a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	sv.add_child(env)
	_mesh3d = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	_mesh3d.material_override = mat
	sv.add_child(_mesh3d)
	var l := _note(box, "形そのもの。向きはドット絵と同じ。体型で作った体は 色 = 部品ごと。「立体」タブで ドット絵から作った立体を見ているあいだは、その立体 (だ円の板を積んだ形) が出ます。")
	l.custom_minimum_size.y = 54
