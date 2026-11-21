class_name DotSolid
extends RefCounted
## ドット絵から作る立体 (試作)。決まりは docs/SOLID.md。
##  - 正面の絵の 1 行ごとに「横幅 × 奥行き」の だ円を置いて積む。奥行きは、横の絵があればそこから、無ければ決まり (頭は丸く、体は平たく) で作る
##  - 色は、決めた絵 (正面・横・後ろ) を面に映す。どの絵からも見えない面は「後ろの色」(その行でいちばん多い色) にする
##  - 輪郭線は絵から抜いて覚え (塗りの色 → 線の色)、描くたびに ふちへ引き直す。決めた向きは、絵をそのまま返す
## 座標: x = 正面の絵の右、z = 手前、紙の真ん中が 0。向き yaw のときの画面の横 = x cos + z sin

const KEYS := [0, 45, 90, 135, 180, 225, 270, 315]   ## 絵を決められる向き。立体の形に使うのは 0 と 90 / 270 だけ
## 部品。A = 正面の絵で画面の左、B = 画面の右
const HEAD := 1
const BODY := 2
const ARM_A := 3
const ARM_B := 4
const LEG_A := 5
const LEG_B := 6
## ひじ・ひざから先 (塗り分けは腕・脚のまま。行の真ん中で自動で分ける)
const FORE_A := 7
const FORE_B := 8
const SHIN_A := 9
const SHIN_B := 10
const PART_NAMES := ["", "頭", "体", "腕 (左)", "腕 (右)", "脚 (左)", "脚 (右)", "ひじから先 (左)", "ひじから先 (右)", "ひざから下 (左)", "ひざから下 (右)", "胸", "肩 (左)", "肩 (右)"]
const PART_COLORS := ["#000000", "#ffd24a", "#5ad07a", "#4aa8ff", "#ff6a5a", "#b07aff", "#ff9a3a", "#a8dcff", "#ffb4aa", "#dcc4ff", "#ffd0a0", "#b8f0a0", "#2a6ad0", "#c8362a"]
const CHEST := 11                           ## 胸 (体の上半分)。腰の関節で 腰 (BODY) の上に乗る
const SHOULDER_A := 12                      ## 肩 (形は無い)。首のつけ根のあたりを中心に回って、腕のつけ根を動かす
const SHOULDER_B := 13
const IK_PARTS := [7, 8, 9, 10]             ## 先をつまむと 2 本いっしょに動く部品
## 親: 頭・肩 → 胸 → 腰。腕 → 肩。脚は腰を傾けても動かない
const PARENT := [0, 11, 0, 12, 13, 0, 0, 3, 4, 5, 6, 2, 11, 11]
const CHILD := {3: 7, 4: 8, 5: 9, 6: 10}
const ARMS := [3, 4, 7, 8]
const LEGS := [5, 6, 9, 10]
const STEP := 0.25                          ## 回した部品を調べる きざみ (画素)

var w := 0
var h := 0
var pics := {}                   ## 向き (0 / 90 / 180 / 270) → 決めた絵 (Image)。0 は必ずある
var k_head := 1.0                ## 奥行き ÷ 横幅: 頭
var k_body := 0.65               ## 体
var k_leg := 1.5                 ## 脚 (1 本ごと)
var depth_scale := 1.0           ## 推定した奥行き全体にかける

var pmap := PackedByteArray()    ## 正面の絵の画素ごとの部品 (0 = 無い)
var leg_hidden := 0.2            ## 服にかくれた脚の長さ (首から脚までの何割か)。大きいほど 腰が高い
var arm_min := 1.5               ## 体から はなした腕の太さ (半径、画素)。絵の腕は 体に半分かくれて細いので、動かしたときは これより細くしない。0 = 絵のまま
var face_min := 0.55              ## 横を向いたときの 顔の幅 (正面の何割まで縮めるか)
var face_out := 0.0               ## 横を向いたとき 顔を 頭のふちから どれだけ外へ出すか (画素)
var front_reach := 70.0          ## 頭が 正面の絵 (と顔の層) を使いつづける角度 (度)。これより横で 横の絵に切りかわる。45 = いちばん近い絵を使う
var waist := 0.5                 ## 腰の関節の高さ: 体の行の 上から何割の所で 胸と腰に分けるか (0 = 分けない)
var shoulder_up := 1.0           ## 肩 (腕のつけ根) を、腕の画素の いちばん上の行より 何行上に置くか
var face_layer := true           ## 顔 (肌・目・口) を だ円の面から切りはなして、別の層として描く
var skin_tol := 0.3              ## 顔の真ん中の色に どれだけ近い色までを 肌とみなすか (色の差。0 = その 1 色だけ)
var _hand_line := Color(0, 0, 0, 0)   ## 手の ふちどりの色 (a = 0 なら 肌の線の色を使う)
var _lrow := {}                 ## Vector2i(腕の部品, 行) → 線の色。手のすぐ下の ふちどりの行 (線の色で描く)
var _hand_cols := {}             ## 手のかげの色 (rgba32 → true)。顔には無いが 手にだけ使われている、肌に近い色
var _skins := {}                 ## 肌の色 (rgba32 → true)。顔の真ん中の色と、それに近い色ぜんぶ (濃淡・ほお)
var _face := PackedByteArray()   ## 正面の絵の画素ごと: 0 = 顔でない、1 = 肌、2 = 目・口など
var _face_ok := false
var _fblobs := []                ## 目・口: [{pix: [Vector2i], x0, x1, cx}]
var _fcx := 0.0                  ## 顔の真ん中 (紙の真ん中からの横の場所)
var _fhw := 1.0                  ## 顔の幅の半分
var _hcx := 0.0                  ## 頭の軸 (顔の行の だ円の真ん中)
var _hcz := 0.0
var _hrz := 1.0                  ## 顔の行の、頭の奥行きの半分
var _hair_row := {}              ## 行 → その行の 顔でない所でいちばん多い色 (髪)
var _hair_mode := Color.BLACK
var _fill0: Image                ## 線を抜いた正面の絵
var _skin := 0                   ## 肌の色 (rgba32)。頭の下半分の真ん中でいちばん多い色
var adds: Array = []             ## 描いた画素 (描いた順): [部品, 場所 (部品の中の座標 Vector3), 奥行きの向き (Vector3), 厚みの半分, Color]。部品と一緒に動く。
                                 ##  色が透明 (a = 0) のものは「けずる」: そこに見えているものを消す
var air_thick := 1.0             ## 空中に描くときの 厚みの半分 (画素)。描いた向きの 奥と手前へ これだけ のびる
var _no_adds := false
var paint_reach := 20.0          ## 描いた色・足した画素が出る範囲: 描いた向きから ± 何度まで (180 = どの向きにも出る)
var spaint := {}                 ## 立体の面に塗った色: Vector3i(部品, 行, まわりの ます) → [Color, 描いたときの向き (その部品から見た度。NAN = どの向きにも)]
var _hb := {}                    ## さいごに描いた絵の、画素ごとの当たり {hp, hy, hd, lyaw, dx} (面に塗るのに使う)
var _hb_key := ""
var _last_hp := PackedByteArray()   ## さいごに描いた絵の、画素ごとの部品 (確かめ用)
var floor_clip := true           ## 床 (立っているときの足の下) より下は描かない
var _top := 0                    ## いちばん上の行
var _bot := 0                    ## 立っているときの、いちばん下の行
var _edge_ok := {}               ## 元の絵で、線なしで ふちにいた色 (手の肌など)。線を足さない
var _line_default := Color(0, 0, 0, 0)
var joints := true               ## ひじ・ひざで分ける
var _pm2 := PackedByteArray()    ## 関節で分けたあとの部品 (立体と色に使う)
var pmap_user := false           ## 部品を自分で塗った (自動で分け直さない)
var pose := {}                   ## 部品 → Quaternion (親の中での回転。つけ根のまわり)
var root := Vector3.ZERO         ## 全体のずれ (画素。y = 上)

var _dirty := true
var _prows := {}                 ## 部品 → {行: [[cx, rx, cz, rz], ...]}
var _prange := {}                ## 部品 → [いちばん上の行, いちばん下の行] (自分の画素がある行)
var _pivot := {}                 ## 部品 → つけ根 (x, 上が + の y, z)
var _tip := {}                   ## 部品 → 先 (つまむ所)
var _rad := {}                   ## 部品 → つけ根から いちばん遠い所までの長さ
var _pcol := {}                  ## 部品 → {行: その行でいちばん多い色}
var _pmode := {}                 ## 部品 → いちばん多い色
var _src: Array = []             ## 色を映す元 [{yaw, img (線を抜いた絵)}]
var _line := {}                  ## 塗りの色 (rgba32) → 線の色 (Color)
var _line_cols := {}             ## 線の色 (rgba32) → true
var _rim := Color(0, 0, 0, 0)    ## 外のふちの色 (二重の輪郭のとき。a = 0 なら無い)
var wrap := 0.6                  ## 絵の回りこみ: 0 = 絵は回さない (輪郭だけ変わる)、1 = 立体どおりに回す。向きがずれた分の この割合だけ絵をずらす
var neck := 0                    ## 首の行 (頭と体の境)


func set_front(img: Image) -> void:
	w = img.get_width()
	h = img.get_height()
	pics = {0: img.duplicate()}
	_dirty = true


static func key_of(yaw: float) -> int:
	var y := fposmod(yaw, 360.0)
	for k in KEYS:
		if absf(y - k) < 0.5 or absf(y - k - 360.0) < 0.5:
			return k
	return -1


## その向きの絵を「決めた絵」にする (まだ無ければ、いまの推定を写して始める)。描きかえる前に呼ぶ
func own(key: int) -> Image:
	if not pics.has(key):
		pics[key] = render(float(key))
		_dirty = true
	return pics[key]


func set_px(key: int, x: int, y: int, c: Color) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var img := own(key)
	if img.get_pixel(x, y) == c:
		return false
	img.set_pixel(x, y, c)
	_dirty = true
	return true


## 決めた絵をやめて、推定に戻す (正面は消せない)
func forget(key: int) -> void:
	if key != 0 and pics.has(key):
		pics.erase(key)
		_dirty = true


## その向きの絵を、まるごと決める (表にある横向き・後ろ向きの絵を使うとき)
func set_pic(key: int, img: Image) -> void:
	var im := img.duplicate() as Image
	if im.get_size() != Vector2i(w, h):
		var fit := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		fit.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i((w - im.get_width()) / 2, h - im.get_height()))
		im = fit
	pics[key] = im
	_dirty = true


func touch() -> void:
	_dirty = true


static func _op(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5


## 1 行の、つながった画素の区間 [[x0, x1], ...]
static func _runs(img: Image, y: int) -> Array:
	var out := []
	var x0 := -1
	for x in img.get_width() + 1:
		var on := x < img.get_width() and img.get_pixel(x, y).a > 0.5
		if on and x0 < 0:
			x0 = x
		elif not on and x0 >= 0:
			out.append([x0, x - 1])
			x0 = -1
	return out


## ふちの画素 (skip に入っている画素は無いものとして数える)
func _edge_of(img: Image, skip: Dictionary) -> Dictionary:
	var edge := {}
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if not _op(img, x, y) or skip.has(p):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + d
				if not _op(img, q.x, q.y) or skip.has(q):
					edge[p] = true
					break
	return edge


## ふちに多い色 = 線の色 (その色の 35% 以上が ふちにあり、ふち全体の 6% 以上)
func _line_colors(img: Image, edge: Dictionary, skip: Dictionary) -> Dictionary:
	var nb := {}
	var nt := {}
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if not _op(img, x, y) or skip.has(p):
				continue
			var c := img.get_pixel(x, y).to_rgba32()
			nt[c] = nt.get(c, 0) + 1
			if edge.has(p):
				nb[c] = nb.get(c, 0) + 1
	var lines := {}
	for c in nb:
		if nb[c] >= 0.35 * nt[c] and nb[c] >= maxi(3, int(0.06 * edge.size())):
			lines[c] = nb[c]
	return lines


## mask の画素を、内側のとなり (skip でも mask でもない画素) でいちばん多い色で埋める。learn = 塗りの色 → 線の色 を覚える
func _fill_in(src: Image, out: Image, mask: Dictionary, skip: Dictionary, learn: bool) -> void:
	var pair := {}
	for p in mask:
		var votes := {}
		for ring in 2:
			for d in ([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)] if ring == 0
					else [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]):
				var q: Vector2i = p + d
				if not _op(src, q.x, q.y) or mask.has(q) or skip.has(q):
					continue
				var qc := out.get_pixel(q.x, q.y).to_rgba32()
				votes[qc] = votes.get(qc, 0) + 1
			if not votes.is_empty():
				break
		if votes.is_empty():
			continue
		var best := 0
		var bc := 0
		for k in votes:
			if votes[k] > best:
				best = votes[k]
				bc = k
		var c := src.get_pixel(p.x, p.y).to_rgba32()
		out.set_pixel(p.x, p.y, Color.hex(bc))
		if learn:
			if not pair.has(bc):
				pair[bc] = {}
			pair[bc][c] = pair[bc].get(c, 0) + 1
	for f in pair:
		var best := 0
		for l in pair[f]:
			if pair[f][l] > best:
				best = pair[f][l]
				_line[f] = Color.hex(l)


## 輪郭線を抜いた絵を返す (線の画素を 内側の色で埋める)。塗りの色 → 線の色 を _line に足す。
## ふちのほとんどが 1 色 (白いふちなど) なら、それを「外のふち」(_rim) として、その内側の線も抜く (二重の輪郭)
func _strip_lines(img: Image) -> Image:
	var out := img.duplicate() as Image
	var e1 := _edge_of(img, {})
	var l1 := _line_colors(img, e1, {})
	var mask1 := {}
	for p in e1:
		var ec := img.get_pixel(p.x, p.y).to_rgba32()
		if l1.has(ec):
			mask1[p] = true
		else:
			_edge_ok[ec] = true
	for c in l1:
		_line_cols[c] = true
	var rim := 0
	for c in l1:
		if l1[c] >= 0.85 * e1.size():
			rim = c
	if rim == 0:
		_fill_in(img, out, mask1, {}, true)
		return out
	_rim = Color.hex(rim)
	var e2 := _edge_of(img, mask1)
	var l2 := _line_colors(img, e2, mask1)
	var mask2 := {}
	for p in e2:
		if l2.has(img.get_pixel(p.x, p.y).to_rgba32()):
			mask2[p] = true
	for c in l2:
		_line_cols[c] = true
	_fill_in(img, out, mask2, mask1, true)
	_fill_in(img, out, mask1, {}, false)
	return out


static func _mode(cnt: Dictionary) -> Color:
	var b := 0
	var bc := Color(0, 0, 0, 0)
	for c in cnt:
		if cnt[c] > b:
			b = cnt[c]
			bc = Color.hex(c)
	return bc


func _is_skin(c: int) -> bool:
	return c == _skin or _skins.has(c)


## 手の色か: 肌の色、または 手のかげの色
func _is_hand(c: int) -> bool:
	return c == _skin or _skins.has(c) or _hand_cols.has(c)


## 手のかげの色を見つける: 顔には出てこないが 手にだけ使われている、肌に近い色 (手の下や内側の 少し濃い肌色)。
##  肌は 顔の色から決めているので、手にしか無い色は 肌にならない → 腕を動かしても その 1 画素が 体に残り、横・後ろの絵の手も 消しきれない。
##  とりちがえないための決まり: 肌に近い色 (skin_tol)・線の色でない・頭に使われていない・首より下の その色の画素が ぜんぶ、
##  体の行 (脚より上) で 肌から 2 画素以内を伝って つながっている・数が 首より下の肌の 3 倍まで
##  (肌色に近い服の そで は 手から はなれた所にも たくさんあり、脚の肌のかげは 脚の行にあるので、どちらも入らない)
func _find_hand_cols(top: int, leg_start: int) -> void:
	_hand_cols = {}
	if _skin == 0 or _fill0 == null:
		return
	var sc := Color.hex(_skin)
	var head := {}
	for y in range(top, mini(neck + 1, h)):
		for x in w:
			if _op(_fill0, x, y):
				head[_fill0.get_pixel(x, y).to_rgba32()] = true
	var tot := {}                        # 色 → 首より下の画素の数
	var hit := {}                        # 色 → そのうち 肌から (候補の色を伝って) つながっている数
	var skin_n := 0
	for sr in _src:
		var im: Image = sr.raw           # もとの絵で数える (線を抜いた絵では、手のまわりの線が かげの色で埋まっている)
		var seen := {}
		var todo := []
		for y in range(neck + 2, h):
			for x in w:
				if not _op(im, x, y):
					continue
				var k := im.get_pixel(x, y).to_rgba32()
				if _is_skin(k):
					skin_n += 1
					todo.append(Vector2i(x, y))
				elif not head.has(k) and not _line_cols.has(k):
					var c := Color.hex(k)
					if Vector3(c.r - sc.r, c.g - sc.g, c.b - sc.b).length() <= skin_tol:
						tot[k] = tot.get(k, 0) + 1
		var ybot := mini(leg_start + 1, h)
		todo = todo.filter(func(t): return t.y < ybot)
		while not todo.is_empty():
			var q: Vector2i = todo.pop_back()
			for dy in [-2, -1, 0, 1, 2]:
				for dx in [-2, -1, 0, 1, 2]:
					var r := q + Vector2i(dx, dy)
					if r.x < 0 or r.x >= w or r.y < neck + 2 or r.y >= ybot or seen.has(r) or not _op(im, r.x, r.y):
						continue
					var k2 := im.get_pixel(r.x, r.y).to_rgba32()
					if tot.has(k2):
						seen[r] = true
						hit[k2] = hit.get(k2, 0) + 1
						todo.append(r)
	for k in tot:
		if hit.get(k, 0) == tot[k] and tot[k] <= 3 * maxi(skin_n, 1):
			_hand_cols[k] = true


## 顔を見つける。色は決め打ちしない: 顔の真ん中でいちばん多い色 (seed) を種にして、それに近い色を ぜんぶ肌とみなす。
##  肌 = 種とつながった 肌の色の画素。目・口 = 肌に囲まれた穴と、肌にくっついた 髪でない色の小さなかたまり
func _find_face(fill0: Image, top: int, seed: int) -> void:
	_face = PackedByteArray()
	_face.resize(w * h)
	_face_ok = false
	_fblobs = []
	_skins = {}
	_hair_row = {}
	_fill0 = fill0
	if seed == 0 or neck - top < 6:
		return
	var sc := Color.hex(seed)
	var hair := {}                    # 頭の上 3 分の 1 にある色 = 髪
	var cut := top + int((neck - top) * 0.35)
	for y in range(top, neck):
		for x in w:
			if not _op(fill0, x, y):
				continue
			var c := fill0.get_pixel(x, y)
			var k := c.to_rgba32()
			if y < cut:
				hair[k] = true
			var dv := Vector3(c.r - sc.r, c.g - sc.g, c.b - sc.b).length()
			if dv <= skin_tol:
				_skins[k] = true
	for k in hair:
		if k != seed:
			_skins.erase(k)           # 髪にも使われている色は 肌にしない
	_skins[seed] = true
	# 近い色でも、顔の外に多い色 (白い髪の明るい所など) は 肌にしない: 種の色の画素がある四角 (1 画素広げる) の中に 7 割以上あるものだけ残す
	var sx0 := w
	var sx1 := -1
	var sy0 := h
	var sy1 := -1
	for y in range(cut, neck + 1):
		for x in w:
			if _op(fill0, x, y) and fill0.get_pixel(x, y).to_rgba32() == seed:
				sx0 = mini(sx0, x)
				sx1 = maxi(sx1, x)
				sy0 = mini(sy0, y)
				sy1 = maxi(sy1, y)
	var tin := {}
	var tall := {}
	for y in range(top, neck + 1):
		for x in w:
			if not _op(fill0, x, y):
				continue
			var k := fill0.get_pixel(x, y).to_rgba32()
			if _skins.has(k):
				tall[k] = tall.get(k, 0) + 1
				if x >= sx0 - 1 and x <= sx1 + 1 and y >= sy0 - 1 and y <= sy1 + 1:
					tin[k] = tin.get(k, 0) + 1
	for k in tall:
		if k != seed and tin.get(k, 0) < tall[k] * 0.7:
			_skins.erase(k)
	# 肌の画素のかたまり (上下左右でつながる) のうち、いちばん大きいもの
	var comp := PackedInt32Array()
	comp.resize(w * h)
	var best_id := 0
	var best_n := 0
	var cid := 0
	for y in range(top, neck + 1):
		for x in w:
			if comp[x + w * y] != 0 or not _op(fill0, x, y) or not _skins.has(fill0.get_pixel(x, y).to_rgba32()):
				continue
			cid += 1
			var st := [Vector2i(x, y)]
			comp[x + w * y] = cid
			var cnt := 0
			while not st.is_empty():
				var q: Vector2i = st.pop_back()
				cnt += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var r: Vector2i = q + d
					if r.x < 0 or r.x >= w or r.y < top or r.y > neck or comp[r.x + w * r.y] != 0:
						continue
					if _op(fill0, r.x, r.y) and _skins.has(fill0.get_pixel(r.x, r.y).to_rgba32()):
						comp[r.x + w * r.y] = cid
						st.append(r)
			if cnt > best_n:
				best_n = cnt
				best_id = cid
	if best_n < 4:
		return
	var bx0 := w
	var bx1 := -1
	var by0 := h
	var by1 := -1
	for y in range(top, neck + 1):
		for x in w:
			if comp[x + w * y] == best_id:
				_face[x + w * y] = 1
				bx0 = mini(bx0, x)
				bx1 = maxi(bx1, x)
				by0 = mini(by0, y)
				by1 = maxi(by1, y)
	# 目・口: 顔の四角の中で、(a) 外から たどり着けない穴、(b) 肌にくっついた 髪でない色
	var out := {}                     # 外から たどり着ける 肌でない画素
	var st2 := []
	for x in range(bx0 - 1, bx1 + 2):
		st2.append(Vector2i(x, by0 - 1))
		st2.append(Vector2i(x, by1 + 1))
	for y in range(by0 - 1, by1 + 2):
		st2.append(Vector2i(bx0 - 1, y))
		st2.append(Vector2i(bx1 + 1, y))
	while not st2.is_empty():
		var q: Vector2i = st2.pop_back()
		if out.has(q) or q.x < bx0 - 1 or q.x > bx1 + 1 or q.y < by0 - 1 or q.y > by1 + 1:
			continue
		if q.x >= 0 and q.x < w and q.y >= 0 and q.y < h and _face[q.x + w * q.y] == 1:
			continue
		out[q] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			st2.append(q + d)
	var cand := {}
	for y in range(by0, by1 + 1):
		for x in range(bx0, bx1 + 1):
			if _face[x + w * y] == 1 or not _op(fill0, x, y):
				continue
			var q := Vector2i(x, y)
			if not out.has(q):
				cand[q] = true
				continue
			if hair.has(fill0.get_pixel(x, y).to_rgba32()):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var r: Vector2i = q + d
				if r.x >= 0 and r.x < w and r.y >= 0 and r.y < h and _face[r.x + w * r.y] == 1:
					cand[q] = true
					break
	var seen := {}
	for q0 in cand:
		if seen.has(q0):
			continue
		var pix := []
		var st3 := [q0]
		seen[q0] = true
		while not st3.is_empty():
			var q: Vector2i = st3.pop_back()
			pix.append(q)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var r := q + Vector2i(dx, dy)
					if cand.has(r) and not seen.has(r):
						seen[r] = true
						st3.append(r)
		if pix.size() > 14:
			continue                  # 大きすぎる: 髪の ふさ など
		var x0 := w
		var x1 := -1
		for q in pix:
			_face[q.x + w * q.y] = 2
			x0 = mini(x0, q.x)
			x1 = maxi(x1, q.x)
		_fblobs.append({"pix": pix, "x0": x0, "x1": x1, "cx": (x0 + x1 + 1) * 0.5 - w * 0.5})
	for b in _fblobs:
		bx0 = mini(bx0, b.x0)
		bx1 = maxi(bx1, b.x1)
	_fcx = (bx0 + bx1 + 1) * 0.5 - w * 0.5
	_fhw = (bx1 - bx0 + 1) * 0.5
	# 髪の色 (行ごと): 顔をどけた下に塗る
	var all_n := {}
	for y in range(top, neck + 1):
		var rn := {}
		for x in w:
			if _op(fill0, x, y) and _face[x + w * y] == 0 and y < neck:
				var k := fill0.get_pixel(x, y).to_rgba32()
				rn[k] = rn.get(k, 0) + 1
				all_n[k] = all_n.get(k, 0) + 1
		if not rn.is_empty():
			_hair_row[y] = _mode(rn)
	if all_n.is_empty():
		return
	_hair_mode = _mode(all_n)
	_face_ok = true


## 正面の絵を部品に分ける (自動): 首より上 = 頭、脚の行から下 = 脚 (左右)、あいだ = 体。体の両はしの、手 (顔と同じ肌の色) までを腕
func _segment(front: Image, fill0: Image, top: int, bot: int, leg_start: int) -> void:
	pmap = PackedByteArray()
	pmap.resize(w * h)
	# 肌の色: 頭の下半分・真ん中あたりでいちばん多い色
	var x0 := w
	var x1 := -1
	for y in range(top, neck):
		for r in _runs(front, y):
			x0 = mini(x0, r[0])
			x1 = maxi(x1, r[1])
	var skin_n := {}
	var third := maxi(1, (x1 - x0 + 1) / 3)
	for y in range((top + neck) / 2, neck):
		for x in range(x0 + third, x1 - third + 1):
			if _op(fill0, x, y):
				var c := fill0.get_pixel(x, y).to_rgba32()
				skin_n[c] = skin_n.get(c, 0) + 1
	var skin := _mode(skin_n).to_rgba32() if not skin_n.is_empty() else 0
	_skin = skin
	_find_face(fill0, top, skin)
	_find_hand_cols(top, leg_start)
	# 脚を左右に分ける所: 脚の行ぜんぶの、左はしと右はしの真ん中
	var lx0 := w
	var lx1 := -1
	for y in range(leg_start, bot + 1):
		for r in _runs(front, y):
			lx0 = mini(lx0, r[0])
			lx1 = maxi(lx1, r[1])
	var split := (lx0 + lx1 + 1) * 0.5
	for y in h:
		for x in w:
			if not _op(front, x, y):
				continue
			var p := HEAD if y < neck else (BODY if y < leg_start else (LEG_A if x + 0.5 < split else LEG_B))
			pmap[x + w * y] = p
	# 腕: 体の行で、肌の色の画素 (手) を左右に探す
	var bx0 := w
	var bx1 := -1
	for y in range(neck, leg_start):
		for r in _runs(front, y):
			bx0 = mini(bx0, r[0])
			bx1 = maxi(bx1, r[1])
	if bx1 < 0:
		return
	var mid := (bx0 + bx1 + 1) * 0.5
	for side in 2:
		var hand_bot := -1
		var aw := 0
		for y in range(neck + 2, leg_start):
			var rs := _runs(front, y)
			if rs.is_empty():
				continue
			var edge: int = rs[0][0] if side == 0 else rs[-1][1]
			for x in (range(edge, int(mid)) if side == 0 else range(edge, int(mid), -1)):
				if _op(fill0, x, y) and _is_skin(fill0.get_pixel(x, y).to_rgba32()) and absi(x - edge) <= 4:
					hand_bot = y
					aw = maxi(aw, absi(x - edge) + 1)
		if hand_bot < 0:
			hand_bot = neck + int((leg_start - neck) * 0.6)
			aw = 2
		aw = clampi(aw, 2, 4)
		var arm_bot := mini(hand_bot + 1, leg_start - 1)
		for y in range(neck + 1, arm_bot + 1):
			var rs := _runs(front, y)
			if rs.is_empty():
				continue
			var wide: Array = rs[0]
			for r in rs:
				if r[1] - r[0] > wide[1] - wide[0]:
					wide = r
			if wide[1] - wide[0] + 1 < 2 * aw + 3:
				continue
			for k in aw:
				var x: int = wide[0] + k if side == 0 else wide[1] - k
				pmap[x + w * y] = ARM_A if side == 0 else ARM_B
		# 手の下の線: 腕の いちばん下の行の すぐ下にある 線の色の画素は、手の ふちどり。体のままだと、腕を動かしたとき 腰に 1 画素残る
		var arm_id := ARM_A if side == 0 else ARM_B
		var last := -1
		for y in range(neck + 1, mini(arm_bot + 1, h)):
			for x in w:
				if pmap[x + w * y] == arm_id:
					last = y
		if last >= 0 and last + 1 < h:
			for x in w:
				if pmap[x + w * last] == arm_id and pmap[x + w * (last + 1)] != 0 and pmap[x + w * (last + 1)] != arm_id and _line_cols.has(front.get_pixel(x, last + 1).to_rgba32()):
					pmap[x + w * (last + 1)] = arm_id


func _solve() -> void:
	_dirty = false
	_hb_key = ""
	_line = {}
	_line_cols = {}
	_edge_ok = {}
	_rim = Color(0, 0, 0, 0)
	_src = []
	var front: Image = pics[0]
	for k in pics:
		_src.append({"yaw": k, "img": _strip_lines(pics[k]), "raw": pics[k]})
	# 左右対称: 片方の横の絵しか無ければ、鏡にして反対側にも使う
	for pair in [[90, 270], [270, 90], [45, 315], [315, 45], [135, 225], [225, 135]]:
		if pics.has(pair[0]) and not pics.has(pair[1]):
			var m: Image = _src.filter(func(s): return s.yaw == pair[0])[0].img.duplicate()
			m.flip_x()
			var mr: Image = pics[pair[0]].duplicate()
			mr.flip_x()
			_src.append({"yaw": pair[1], "img": m, "raw": mr})
	var fill0: Image = _src[0].img
	for s in _src:
		if s.yaw == 0:
			fill0 = s.img
	# 首: 高さの 30〜70% のあいだで、いちばん細い行
	var top := h
	var bot := -1
	var width := []
	for y in h:
		var n := 0
		for r in _runs(front, y):
			n += r[1] - r[0] + 1
		width.append(n)
		if n > 0:
			top = mini(top, y)
			bot = y
	_bot = bot
	_top = top
	neck = top
	var best := 1 << 30
	for y in range(top + int((bot - top) * 0.3), top + int((bot - top) * 0.7) + 1):
		if y >= 0 and y < h and width[y] > 0 and width[y] < best:
			best = width[y]
			neck = y
	var body_w := 0
	for y in range(neck, bot + 1):
		body_w = maxi(body_w, width[y])
	# 脚の行 (脚が始まったら、その下の靴も脚)
	var leg_start := bot + 1
	for y in range(neck + 1, bot + 1):
		var big := 0                     # 幅 2 画素以上の区間の数 (手の 1 画素は数えない)
		for r in _runs(front, y):
			if r[1] - r[0] >= 1:
				big += 1
		if (big >= 2 or width[y] <= body_w * 0.55) and y > top + (bot - top) * 0.6:
			leg_start = y
			break
	if not pmap_user or pmap.size() != w * h:
		pmap_user = false
		_segment(front, fill0, top, bot, leg_start)
	else:
		var keep := pmap.duplicate()         # 肌の色だけ調べ直す
		_segment(front, fill0, top, bot, leg_start)
		pmap = keep
	# 正面でない絵に描きこまれた手 (首より下の 肌の色と、そのまわりの線): 腕を動かしたら、体の絵から消す
	for sr in _src:
		var hm := PackedByteArray()
		hm.resize(w * h)
		if sr.yaw != 0 and _skin != 0:
			var im0: Image = sr.img
			var raw0: Image = sr.raw
			for y in range(neck + 2, h):
				for x in w:
					if _op(im0, x, y) and _is_hand(im0.get_pixel(x, y).to_rgba32()):
						hm[x + w * y] = 1
			for y in range(neck + 2, h):
				for x in w:
					if hm[x + w * y] != 1:
						continue
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var xx: int = x + d.x
						var yy: int = y + d.y
						if xx >= 0 and xx < w and yy < h and hm[xx + w * yy] == 0 and _op(raw0, xx, yy) and _line_cols.has(raw0.get_pixel(xx, yy).to_rgba32()):
							hm[xx + w * yy] = 2
		elif sr.yaw == 0 and _skin != 0:
			# 正面の絵: 腕の手から 2 画素以内にある、腕に入らなかった 手のかげ (手から 1 画素はなして描いた かげ など) と、
			#  手のまわりの線 (線を抜いた絵では 手の色で埋まっている) も、体の絵から消す。手は いつも腕の立体が出すので、
			#  残すと 腕を動かしたとき 体に 1 画素残る。もとから肌の色の画素 (そでの無い服の おなか など) は消さない
			var imf: Image = sr.img
			var rawf: Image = sr.raw
			for y in range(neck + 2, h):
				for x in w:
					var hp0 := pmap[x + w * y]
					if hp0 == 0 or hp0 == ARM_A or hp0 == ARM_B or not _op(rawf, x, y) or not _op(imf, x, y):
						continue
					var rk0 := rawf.get_pixel(x, y).to_rgba32()
					if not (_hand_cols.has(rk0) or (_line_cols.has(rk0) and _is_hand(imf.get_pixel(x, y).to_rgba32()))):
						continue
					for dy in [-2, -1, 0, 1, 2]:
						for dx in [-2, -1, 0, 1, 2]:
							var xx2: int = x + dx
							var yy2: int = y + dy
							if xx2 >= 0 and xx2 < w and yy2 >= 0 and yy2 < h and (pmap[xx2 + w * yy2] == ARM_A or pmap[xx2 + w * yy2] == ARM_B) and _op(rawf, xx2, yy2) and _is_hand(rawf.get_pixel(xx2, yy2).to_rgba32()):
								hm[x + w * y] = 1
		sr["hand"] = hm
	# 横の絵 (あれば): 行ごとの奥行きの区間
	var side: Image = null
	var side_sign := 1.0
	if pics.has(90):
		side = pics[90]
	elif pics.has(270):
		side = pics[270]
		side_sign = -1.0
	# 手の前後の場所: 横の絵に描いてある手 (首より下の肌の色) の 横の真ん中。腕は 肩 (奥行き 0) から ここへ ななめに下りる。
	#  腕を体の真横 (奥行き 0) に置いたままだと、横から見たとき 絵の手と 立体の手が 別の所に出て、手が増えたり消えたりする
	var arm_hz := 0.0
	if side != null and _skin != 0:
		var sxs := 0.0
		var sn := 0
		for y in range(neck + 2, h):
			for x in w:
				if _op(side, x, y) and _is_skin(side.get_pixel(x, y).to_rgba32()):
					sxs += x + 0.5 - w * 0.5
					sn += 1
		if sn > 0:
			arm_hz = sxs / sn * side_sign * 0.5      # 半分だけ寄せる: 全部寄せると、ななめ前 (30〜45°) で 奥の手が体に かくれて 1 つに見える
	var arm_top := {}                # 腕 (左右) → [いちばん上の行, いちばん下の行]
	for y in h:
		for x in w:
			var ap := pmap[x + w * y]
			if (ap == ARM_A or ap == ARM_B) and _op(front, x, y):
				if not arm_top.has(ap):
					arm_top[ap] = [y, y]
				arm_top[ap][1] = y
	# 関節: 腕・脚を、行の真ん中で「つけ根側」と「先」に分ける
	_pm2 = pmap.duplicate()
	# 腰の関節: 体を 胸 (上) と 腰 (下) に分ける
	if joints and waist > 0.0:
		var b0 := h
		var b1 := -1
		for y in h:
			for x in w:
				if pmap[x + w * y] == BODY and _op(front, x, y):
					b0 = mini(b0, y)
					b1 = maxi(b1, y)
		if b1 - b0 + 1 >= 6:
			var wy := b0 + clampi(int(round((b1 - b0 + 1) * waist)), 2, b1 - b0 - 1)
			for y in range(b0, wy):
				for x in w:
					if pmap[x + w * y] == BODY:
						_pm2[x + w * y] = CHEST
	if joints:
		var rng := {}
		for y in h:
			for x in w:
				var p := pmap[x + w * y]
				if (p == ARM_A or p == ARM_B) and _op(front, x, y):
					if not rng.has(p):
						rng[p] = [y, y]
					rng[p][1] = y
		for p in rng:
			var cnt: int = rng[p][1] - rng[p][0] + 1
			if cnt < 4:
				continue
			for y in range(rng[p][0] + cnt / 2, rng[p][1] + 1):
				for x in w:
					if pmap[x + w * y] == p:
						_pm2[x + w * y] = CHILD[p]
	# 部品ごとに、行の区間 → だ円
	_prows = {}
	_prange = {}
	var praw := {}                   # 部品 → {行: [[x0, x1], ...]}
	for y in h:
		var x := 0
		while x < w:
			var p := _pm2[x + w * y] if _op(front, x, y) else 0
			if p == 0:
				x += 1
				continue
			var x1 := x
			while x1 + 1 < w and _op(front, x1 + 1, y) and _pm2[x1 + 1 + w * y] == p:
				x1 += 1
			if not praw.has(p):
				praw[p] = {}
				_prange[p] = [y, y]
			if not praw[p].has(y):
				praw[p][y] = []
			praw[p][y].append([x, x1])
			_prange[p][1] = y
			x = x1 + 1
	# 脚: 服 (体) にかくれている分を上へ足す (首から脚までの leg_hidden の割合、1〜6 行)。つけ根 = その上のはし (腰)。
	# 関節があれば、かくれた分もふくめた長さの真ん中 (ひざ) で分ける
	var ptop := {}                   # 部品 → つけ根の行 (自分の画素の いちばん上と ちがうとき)
	var hid := {}                    # 部品 → {かくれた行: 形をまねる行}
	for p in [LEG_A, LEG_B]:
		if not praw.has(p):
			continue
		var c: int = CHILD[p]
		var t0: int = _prange[p][0]
		var bt: int = _prange[p][1]
		var hip := maxi(t0 - clampi(int(round((t0 - neck) * leg_hidden)), 1, 6), neck + 1)
		var total := bt - hip + 1
		var knee := hip + total / 2 if (joints and total >= 4) else bt + 1
		ptop[p] = hip
		ptop[c] = knee
		hid[p] = {}
		hid[c] = {}
		var mine := {}
		var kids := {}
		for y in range(hip, bt + 1):
			var runs: Array = praw[p][y] if y >= t0 else praw[p][t0].duplicate(true)
			if y < knee:
				mine[y] = runs
				if y < t0:
					hid[p][y] = t0
			else:
				kids[y] = runs
				if y < t0:
					hid[c][y] = t0
				else:
					for r in runs:
						for x in range(r[0], r[1] + 1):
							_pm2[x + w * y] = c
		praw[p] = mine
		_prange[p] = [t0, mini(bt, knee - 1)] if knee > t0 else [0, -1]
		if not kids.is_empty():
			praw[c] = kids
			_prange[c] = [maxi(knee, t0), bt]
	# 脚 1 本の太さ = 平均 (靴の行は左右がつながって太く見えるので、奥行きは この太さで決める)
	var leg_sum := 0.0
	var leg_n := 0
	for p in LEGS:
		for y in praw.get(p, {}):
			for r in praw[p][y]:
				leg_sum += (r[1] - r[0] + 1) * 0.5
				leg_n += 1
	var leg_rx := maxf(leg_sum / maxi(leg_n, 1), 1.0)
	for p in praw:
		_prows[p] = {}
		for y in praw[p]:
			var zr := []
			if side != null and not (p in ARMS):
				for r in _runs(side, hid.get(p, {}).get(y, y)):
					var a: float = (r[0] - w * 0.5) * side_sign
					var b: float = (r[1] + 1 - w * 0.5) * side_sign
					zr.append([(a + b) * 0.5, absf(b - a) * 0.5])
			var row := []
			for r in praw[p][y]:
				var cx: float = (r[0] + r[1] + 1) * 0.5 - w * 0.5
				var rx: float = (r[1] - r[0] + 1) * 0.5
				if not zr.is_empty():
					for z in zr:
						row.append([cx, rx, z[0], z[1]])
				elif p in ARMS:
					var ar: Array = arm_top.get(p if p <= 4 else p - 4, [y, y])
					var az: float = arm_hz * clampf(float(y - ar[0]) / maxf(float(ar[1] - ar[0]), 1.0), 0.0, 1.0)
					row.append([cx, rx, az, maxf(1.0, roundf(rx * depth_scale))])
				elif p in LEGS:
					var rz := maxf(1.0, roundf(minf(rx, leg_rx) * k_leg * depth_scale))
					if y >= bot - 1:
						row.append([cx, rx, 0.5, rz + 0.5])      # 靴: つま先を前へ 1 画素
					else:
						row.append([cx, rx, 0.0, rz])
				else:
					row.append([cx, rx, 0.0, maxf(1.0, roundf(rx * (k_head if p == HEAD else k_body) * depth_scale))])
			_prows[p][y] = row
	# かくれている所を足す: 脚は体の中へ 2 行、体は頭の中へ 2 行 (回したとき、つけ根が はなれないように)
	for p in [BODY, CHEST, FORE_A, FORE_B]:
		if not _prows.has(p):
			continue
		var t: int = _prange[p][0]
		for k in ([1, 2] if (p == BODY or p == CHEST) else [1]):
			if t - k >= 0:
				var cp := []
				for e in _prows[p][t]:
					cp.append([e[0], minf(e[1], 3.0) if (p == BODY or p == CHEST) else e[1], e[2], minf(e[3], 3.0) if (p == BODY or p == CHEST) else e[3]])
				_prows[p][t - k] = cp
	# つけ根と先 (つまむ所)、大きさ
	var cx_of := func(p: int, y: int) -> float:
		var lo := 1e9
		var hi := -1e9
		for e in _prows[p].get(y, []):
			lo = minf(lo, e[0] - e[1])
			hi = maxf(hi, e[0] + e[1])
		return (lo + hi) * 0.5 if hi > lo else 0.0
	var cz_of := func(p: int, y: int) -> float:
		var rws: Array = _prows[p].get(y, [])
		return float(rws[0][2]) if (p in ARMS and not rws.is_empty()) else 0.0
	_pivot = {}
	_tip = {}
	_rad = {}
	for p in _prows:
		var t: int = ptop.get(p, _prange[p][0])
		var bt: int = _prange[p][1]
		if ptop.has(p):
			# 脚: 形のある行の いちばん下 (かくれた行だけの部品もある)
			bt = t
			for y in _prows[p]:
				bt = maxi(bt, y)
		match p:
			HEAD:
				_pivot[p] = Vector3(cx_of.call(p, bt), -(bt + 1.0), 0.0)
				_tip[p] = Vector3(cx_of.call(p, t), -float(t), 0.0)
			BODY, CHEST:
				_pivot[p] = Vector3(cx_of.call(p, bt), -(bt + 1.0), 0.0)
				_tip[p] = Vector3(cx_of.call(p, t), -float(t), 0.0)
			ARM_A, ARM_B:
				# 肩: 腕の画素の いちばん上の行より shoulder_up 行だけ上 (えりの中)。絵の腕は 肩口が えりや髪に かくれていて、
				#  見えている いちばん上の行を つけ根にすると、腕を上げたとき 胸〜おなかから生えたように見える
				_pivot[p] = Vector3(cx_of.call(p, t), -(t + 0.5 - shoulder_up), 0.0)
				_tip[p] = Vector3(cx_of.call(p, bt), -(bt + 1.0), cz_of.call(p, bt))
			_:
				_pivot[p] = Vector3(cx_of.call(p, t), -float(t), cz_of.call(p, t))
				_tip[p] = Vector3(cx_of.call(p, bt), -(bt + 1.0), cz_of.call(p, bt))
		var r := 1.0
		for y in _prows[p]:
			for e in _prows[p][y]:
				var dx: float = absf(e[0] - _pivot[p].x) + e[1]
				var dz: float = absf(e[2]) + e[3]
				var dy: float = maxf(absf(-float(y) - _pivot[p].y), absf(-float(y + 1) - _pivot[p].y))
				r = maxf(r, sqrt(dx * dx + dy * dy + dz * dz))
		_rad[p] = r + 0.5 + (arm_min + 1.0 if p in ARMS else 0.0)
	# 顔の層: 頭の軸 (顔の行の だ円の真ん中) と、その奥行き
	if _face_ok and _prows.has(HEAD):
		var sx := 0.0
		var sz := 0.0
		var cnt2 := 0
		_hrz = 1.0
		for y in _prows[HEAD]:
			var has_face := false
			for x in w:
				if _face[x + w * y] != 0:
					has_face = true
					break
			if has_face and not _prows[HEAD][y].is_empty():
				var e: Array = _prows[HEAD][y][0]
				sx += e[0]
				sz += e[2]
				cnt2 += 1
				_hrz = maxf(_hrz, e[3])
		if cnt2 > 0:
			_hcx = sx / cnt2
			_hcz = sz / cnt2
		else:
			_face_ok = false
	# 肩 (形の無い部品): 首のつけ根 (体の真ん中寄り) を中心に、腕のつけ根を動かす。先 = 腕のつけ根
	for sp2 in [[SHOULDER_A, ARM_A], [SHOULDER_B, ARM_B]]:
		if _pivot.has(sp2[1]):
			var ap2: Vector3 = _pivot[sp2[1]]
			var top_p: int = CHEST if _pivot.has(CHEST) else BODY
			var mx: float = _tip[top_p].x if _tip.has(top_p) else 0.0
			_pivot[sp2[0]] = Vector3(lerpf(mx, ap2.x, 0.25), ap2.y, 0.0)
			_tip[sp2[0]] = ap2
			_rad[sp2[0]] = 1.0
	# 線の色が分からないときに使う色: いちばん多くの塗りの色についている線の色
	var lc := {}
	for f in _line:
		var k: int = _line[f].to_rgba32()
		lc[k] = lc.get(k, 0) + 1
	_line_default = _mode(lc) if not lc.is_empty() else Color(0, 0, 0, 0)
	# 部品の色 (行ごと・全体): かくれていて絵に無い所を塗るのに使う
	_pcol = {}
	_pmode = {}
	var all_n := {}
	for y in h:
		for x in w:
			if not _op(fill0, x, y):
				continue
			var p := _pm2[x + w * y]
			var c := fill0.get_pixel(x, y).to_rgba32()
			if not all_n.has(p):
				all_n[p] = {}
				_pcol[p] = {}
			all_n[p][c] = all_n[p].get(c, 0) + 1
			if not _pcol[p].has(y):
				_pcol[p][y] = {}
			_pcol[p][y][c] = _pcol[p][y].get(c, 0) + 1
	for p in all_n:
		_pmode[p] = _mode(all_n[p])
		for y in _pcol[p]:
			_pcol[p][y] = _mode(_pcol[p][y])
	# 手の下の線の行: 腕の行のうち、手より下にあって、もとの絵では 線の色の画素しか無い行 (手のすぐ下の ふちどり)。
	#  線を抜いた絵では 手の色で埋まることがあり、そのまま写すと 動かした腕の手が 1 行 長くなる → その行は 線の色で描く (手の先が 線で閉じる)
	_lrow = {}
	for lside in 2:
		var lparts := [ARM_A, FORE_A] if lside == 0 else [ARM_B, FORE_B]
		var seen_hand := false
		for y in h:
			var n_all := 0
			var n_line := 0
			var lcol := Color.BLACK
			var lpart := 0
			var has_hand := false
			for x in w:
				var lp := _pm2[x + w * y]
				if not (lp in lparts) or not _op(front, x, y):
					continue
				n_all += 1
				lpart = lp
				var lrk := front.get_pixel(x, y).to_rgba32()
				if _line_cols.has(lrk):
					n_line += 1
					lcol = front.get_pixel(x, y)
				elif _is_hand(lrk):
					has_hand = true
			if n_all > 0 and n_line == n_all and seen_hand:
				_lrow[Vector2i(lpart, y)] = lcol
			if has_hand:
				seen_hand = true
	# 手の ふちどりの色: 正面の絵で、腕の 手の色の画素の となりにある 線の色のうち いちばん多いもの。
	#  肌の線の色 (_line) は 顔のまわりから決まるので、髪の線の色になっていることがある → 動かした腕の手だけ ふちの色が変わって見える
	_hand_line = Color(0, 0, 0, 0)
	var hl_n := {}
	for y in range(mini(neck + 2, h), h):
		for x in w:
			if not (_pm2[x + w * y] in ARMS) or not _op(front, x, y) or not _is_hand(front.get_pixel(x, y).to_rgba32()):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var hx: int = x + d.x
				var hy2: int = y + d.y
				if hx >= 0 and hx < w and hy2 >= 0 and hy2 < h and _op(front, hx, hy2):
					var hk := front.get_pixel(hx, hy2).to_rgba32()
					if _line_cols.has(hk) and hk != _rim.to_rgba32():
						hl_n[hk] = hl_n.get(hk, 0) + 1
	if not hl_n.is_empty():
		_hand_line = _mode(hl_n)
	# 画素の無い部品 (服にかくれた もも): 先 (ひざから下) の色で塗る
	for p in _prows:
		if not _pmode.has(p):
			_pmode[p] = _pmode.get(CHILD.get(p, 0), _pmode.get(PARENT[p], Color.BLACK))
			_pcol[p] = {}
	# 絵と立体の 横のずれ (dx): 手描きの後ろ・ななめの絵は、立体 (正面の絵から作った) を その向きから見た輪郭と 1 画素ずれていることがある
	#  (幅が奇数と偶数で 真ん中がちがう、など)。ずれたまま映すと、片側は線が立体の外へ落ちて消え、反対側は 線が 2 重になる。
	#  絵の輪郭と 立体の輪郭が いちばん重なる ずれを はかり、色を取るときは その分ずらし、できた絵も 絵の場所に合わせて ずらす
	for sr in _src:
		sr["dx"] = 0
	var kp := pose
	var kr := root
	pose = {}
	root = Vector3.ZERO
	_no_adds = true                  # 絵と立体を合わせるあいだは、足した画素を入れない
	var found := []                  # [絵, ずれ]
	for sr in _src:
		if int(sr.yaw) == 0:
			continue
		render(float(sr.yaw), true)
		var raw1: Image = sr.raw
		var dbest := 0
		var dbs := -1
		for dx in [0, -1, 1, -2, 2]:
			var sc := 0
			for y in h:
				for x in w:
					if (_last_hp[x + w * y] != 0) == _op(raw1, x + dx, y):
						sc += 1
			if sc > dbs:
				dbs = sc
				dbest = dx
		found.append([sr, dbest])
		sr["rest"] = _last_hp.duplicate()        # 立ちのとき、その向きで 画素ごとに どの部品が見えるか
	for f in found:
		f[0]["dx"] = f[1]
	_no_adds = false
	pose = kp
	root = kr


## 部品 p の、行 y の「絵に無い所の色」: 頭は 頭でいちばん多い色、ほかは その行でいちばん多い色
func _back_of(p: int, y: int) -> Color:
	if p == HEAD or not _pcol.has(p) or _prange[p][1] < _prange[p][0]:
		return _pmode.get(p, Color.BLACK)
	var yy := clampi(y, _prange[p][0], _prange[p][1])
	return _pcol[p].get(yy, _pmode[p])


## 部品 p の親 (その親が このキャラに無ければ、さらに上の親)
func parent_of(p: int) -> int:
	var par := int(PARENT[p])
	while par != 0 and not _pivot.has(par):
		par = PARENT[par]
	return par


## 部品 p の、いまのポーズでの [回転 (Basis), つけ根の場所]
func _world(p: int) -> Array:
	var q: Quaternion = pose.get(p, Quaternion.IDENTITY)
	var par: int = parent_of(p)
	if par == 0 or not _pivot.has(par):
		return [Basis(q), _pivot[p] + root]
	var pw := _world(par)
	return [pw[0] * Basis(q), pw[1] + pw[0] * (_pivot[p] - _pivot[par])]


func is_posed() -> bool:
	if root.length() > 0.001:
		return true
	for p in pose:
		if not Quaternion(pose[p]).is_equal_approx(Quaternion.IDENTITY):
			return true
	return false


func ensure() -> void:
	if _dirty:
		_solve()


## 画面の場所 (画素) ← 立体の中の点
func project(v: Vector3, yaw: float) -> Vector2:
	var th := deg_to_rad(yaw)
	return Vector2(v.x * cos(th) + v.z * sin(th) + w * 0.5 + _view_dx(yaw), -v.y)


## 向き yaw の絵を 横へずらす画素の数: その向きに いちばん近い絵の、立体との ずれ
func _view_dx(yaw: float) -> int:
	var best := 0
	var bd := 1e9
	for src in _src:
		var k := absf(angle_difference(deg_to_rad(src.yaw), deg_to_rad(yaw))) + (0.0 if int(src.yaw) % 180 == 0 else 0.0002)
		if k < bd:
			bd = k
			best = int(src.get("dx", 0))
	return best


## つまむ所: [{part, pivot (画素), tip (画素)}]
func handles(yaw: float) -> Array:
	ensure()
	var out := []
	for p in _pivot:
		var wd := _world(p)
		out.append({"part": p, "pivot": project(wd[1], yaw), "tip": project(wd[1] + wd[0] * (_tip[p] - _pivot[p]), yaw)})
	return out


## 部品 p の先を、画面の from から to へつまんで動かす: つけ根のまわりに、見ている向きを軸にして回す
func drag_part(p: int, yaw: float, from: Vector2, to: Vector2) -> void:
	ensure()
	if not _pivot.has(p):
		return
	var th := deg_to_rad(yaw)
	var axis := Vector3(-sin(th), 0.0, cos(th))
	var wd := _world(p)
	var pv := project(wd[1], yaw)
	if from.distance_to(pv) < 0.5 or to.distance_to(pv) < 0.5:
		return
	var ang := (from - pv).angle_to(to - pv)
	var par: int = parent_of(p)
	var rp: Basis = _world(par)[0] if (par != 0 and _pivot.has(par)) else Basis()
	var q0: Quaternion = pose.get(p, Quaternion.IDENTITY)
	var best := INF
	var keep := q0
	for sgn in [1.0, -1.0]:
		var q := (rp.inverse() * Basis(axis, ang * sgn) * rp).get_rotation_quaternion() * q0
		pose[p] = q.normalized()
		var w2 := _world(p)
		var d := project(w2[1] + w2[0] * (_tip[p] - _pivot[p]), yaw).distance_to(to)
		if d < best:
			best = d
			keep = pose[p]
	pose[p] = keep


## IK: 手・足の先 (ひじ・ひざから先の部品 child の先) を、画面の to へ持っていく。つけ根側と先の 2 本をいっしょに回す。
## ひじは後ろへ、ひざは前へ曲がる (いま曲がっていれば、その向きのまま)
func drag_ik(child: int, yaw: float, to: Vector2) -> bool:
	ensure()
	var par: int = parent_of(child)
	if par == 0 or not _pivot.has(child) or not _pivot.has(par):
		return false
	var th := deg_to_rad(yaw)
	var a3 := Vector3(cos(th), 0.0, sin(th))
	var wp := _world(par)
	var wc := _world(child)
	var p0: Vector3 = wp[1]
	var elbow: Vector3 = wc[1]
	var tipw: Vector3 = wc[1] + wc[0] * (_tip[child] - _pivot[child])
	var cur := project(tipw, yaw)
	# 目標: いまの先を、画面の上で to まで動かした所 (奥行きはそのまま)
	var target := tipw + a3 * (to.x - cur.x) + Vector3(0.0, -(to.y - cur.y), 0.0)
	var v1: Vector3 = _pivot[child] - _pivot[par]
	var v2: Vector3 = _tip[child] - _pivot[child]
	var l1 := v1.length()
	var l2 := v2.length()
	if l1 < 0.01 or l2 < 0.01:
		return false
	var d := target - p0
	var dist := clampf(d.length(), absf(l1 - l2) + 0.05, l1 + l2 - 0.02)
	var dn := d.normalized() if d.length() > 0.001 else Vector3.DOWN
	# 曲がる向き: いまの ひじの場所 (まっすぐなら、腕は後ろ・脚は前)
	var hint := (elbow - p0) - dn * (elbow - p0).dot(dn)
	if hint.length() < 0.15:
		hint = Vector3(0.0, 0.0, -1.0 if child in [FORE_A, FORE_B] else 1.0)
		hint = hint - dn * hint.dot(dn)
		if hint.length() < 0.01:
			hint = Vector3.UP - dn * Vector3.UP.dot(dn)
	hint = hint.normalized()
	var along := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var up := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var e2 := p0 + dn * along + hint * up
	var t2 := p0 + dn * dist
	var gp: int = parent_of(par)
	var rg: Basis = _world(gp)[0] if (gp != 0 and _pivot.has(gp)) else Basis()
	var r1 := Basis(Quaternion(v1.normalized(), (e2 - p0).normalized()))
	var r2 := Basis(Quaternion(v2.normalized(), (t2 - e2).normalized()))
	pose[par] = (rg.inverse() * r1).get_rotation_quaternion()
	pose[child] = (r1.inverse() * r2).get_rotation_quaternion()
	return true


## 歩きの 4 コマ: [{name, pose, root}]。足をついたコマ (体が 1 画素下がる) と、足を入れかえる途中のコマを交互に
func walk_cycle() -> Array:
	ensure()
	var fwd := func(deg: float) -> Quaternion: return Quaternion(Vector3.RIGHT, -deg_to_rad(deg))
	var c1: Dictionary = preset("歩き 1")
	var c2: Dictionary = preset("歩き 2")
	var down := Vector3(0.0, -1.0, 0.0)
	return [
		{"name": "歩き 1", "pose": c1.pose, "root": down},
		{"name": "歩き 2", "pose": {LEG_B: fwd.call(12.0), SHIN_B: fwd.call(-45.0), ARM_A: fwd.call(-6.0), ARM_B: fwd.call(6.0),
				FORE_A: fwd.call(15.0), FORE_B: fwd.call(15.0)}, "root": Vector3.ZERO},
		{"name": "歩き 3", "pose": c2.pose, "root": down},
		{"name": "歩き 4", "pose": {LEG_A: fwd.call(12.0), SHIN_A: fwd.call(-45.0), ARM_B: fwd.call(-6.0), ARM_A: fwd.call(6.0),
				FORE_A: fwd.call(15.0), FORE_B: fwd.call(15.0)}, "root": Vector3.ZERO},
	]


## 決まったポーズ: {pose: {部品: Quaternion}, root: Vector3}
func preset(name: String) -> Dictionary:
	ensure()
	var fwd := func(deg: float) -> Quaternion: return Quaternion(Vector3.RIGHT, -deg_to_rad(deg))
	var out := func(deg: float) -> Quaternion: return Quaternion(Vector3.BACK, deg_to_rad(deg))
	match name:
		"走り":
			return {"pose": {LEG_A: fwd.call(50.0), SHIN_A: fwd.call(-25.0), LEG_B: fwd.call(-35.0), SHIN_B: fwd.call(-70.0),
					ARM_A: fwd.call(-45.0), FORE_A: fwd.call(70.0), ARM_B: fwd.call(40.0), FORE_B: fwd.call(70.0), CHEST: fwd.call(-10.0)}, "root": Vector3.ZERO}
		"ばんざい":
			return {"pose": {ARM_B: out.call(140.0), ARM_A: out.call(-140.0), SHOULDER_B: out.call(15.0), SHOULDER_A: out.call(-15.0)}, "root": Vector3.ZERO}
		"T の字", "Tの字":
			return {"pose": {ARM_B: out.call(68.0), ARM_A: out.call(-68.0), FORE_B: out.call(8.0), FORE_A: out.call(-8.0)}, "root": Vector3.ZERO}
		"歩き 1":
			return {"pose": {LEG_A: fwd.call(30.0), LEG_B: fwd.call(-22.0), SHIN_B: fwd.call(-30.0),
					ARM_A: fwd.call(-22.0), ARM_B: fwd.call(18.0), FORE_A: fwd.call(15.0), FORE_B: fwd.call(30.0)}, "root": Vector3.ZERO}
		"歩き 2":
			return {"pose": {LEG_B: fwd.call(30.0), LEG_A: fwd.call(-22.0), SHIN_A: fwd.call(-30.0),
					ARM_B: fwd.call(-22.0), ARM_A: fwd.call(18.0), FORE_B: fwd.call(15.0), FORE_A: fwd.call(30.0)}, "root": Vector3.ZERO}
		"すわる":
			# いすにすわる: ももを前へ、ひざから下は下へ。腰は ももの長さだけ下がる
			var n := 0
			if _prange.has(LEG_A):
				n = _prange[LEG_A][1] - _prange[LEG_A][0] + 1
			if not _prows.has(SHIN_A):
				return {"pose": {LEG_A: fwd.call(88.0), LEG_B: fwd.call(88.0)}, "root": Vector3(0.0, -float(maxi(n - 2, 0)), 0.0)}
			return {"pose": {LEG_A: fwd.call(88.0), LEG_B: fwd.call(88.0), SHIN_A: fwd.call(-88.0), SHIN_B: fwd.call(-88.0),
					FORE_A: fwd.call(40.0), FORE_B: fwd.call(40.0)}, "root": Vector3(0.0, -float(maxi(n - 1, 0)), 0.0)}
		"ゆかにすわる":
			var n := 0
			for p in [LEG_A, SHIN_A]:
				if _prange.has(p):
					n += _prange[p][1] - _prange[p][0] + 1
			return {"pose": {LEG_A: fwd.call(88.0), LEG_B: fwd.call(88.0)}, "root": Vector3(0.0, -float(maxi(n - 2, 0)), 0.0)}
		"おじぎ":
			# 上へ のびる部品 (腰・胸) は、脚と 回す向きが逆: 前へ たおすには 負の角度
			return {"pose": {BODY: fwd.call(-18.0), CHEST: fwd.call(-16.0)} if _pivot.has(CHEST) else {BODY: fwd.call(-28.0)}, "root": Vector3.ZERO}
		"手をあげる":
			return {"pose": {ARM_B: out.call(105.0), FORE_B: out.call(40.0)}, "root": Vector3.ZERO}
	return {"pose": {}, "root": Vector3.ZERO}


func part_at(x: int, y: int) -> int:
	ensure()
	return pmap[x + w * y] if (x >= 0 and y >= 0 and x < w and y < h) else 0


## 正面の絵の画素 (x, y) を部品 p にする (自分で分け直す)
func set_part(x: int, y: int, p: int) -> bool:
	ensure()
	if x < 0 or y < 0 or x >= w or y >= h or not _op(pics[0], x, y) or pmap[x + w * y] == p:
		return false
	pmap[x + w * y] = p
	pmap_user = true
	_dirty = true
	return true


func reset_parts() -> void:
	pmap_user = false
	_dirty = true


## 向き yaw (度) の絵
func render(yaw: float, force := false) -> Image:
	if _dirty:
		_solve()
	var posed := is_posed()
	var key := key_of(yaw)
	var base_pic: Image = null
	if key >= 0 and not posed and not force:
		# 決めた絵をそのまま返す。面に塗った色があれば、下で立体を描いて その画素だけ上に重ねる
		if pics.has(key):
			if spaint.is_empty() and adds.is_empty():
				return pics[key].duplicate()
			base_pic = pics[key].duplicate()
		else:
			var other := (360 - key) % 360               # 左右対称: 反対側の絵を鏡にして使う
			if other != key and pics.has(other):
				var m: Image = pics[other].duplicate()
				m.flip_x()
				if spaint.is_empty() and adds.is_empty():
					return m
				base_pic = m
	var th := deg_to_rad(yaw)
	var c := cos(th)
	var s := sin(th)
	var a3 := Vector3(c, 0.0, s)
	var b3 := Vector3(-s, 0.0, c)
	var n := w * h
	var zb := PackedFloat32Array()
	zb.resize(n)
	zb.fill(-INF)
	var hp := PackedByteArray()
	hp.resize(n)
	var hy := PackedInt32Array()
	hy.resize(n)
	var hd := PackedFloat32Array()   # 画素ごとに 6 つ: だ円の真ん中からの場所 x・z、だ円の真ん中 x・半径 x・真ん中 z・半径 z
	hd.resize(n * 6)
	var lyaw := {}                   # 部品 → その部品から見た「見ている向き」(度)
	var moved := {}                  # 部品 → 動かした (回した・ずらした)
	var rot := {}                    # 部品 → 回した
	for p in _prows:
		var wd := _world(p)
		var R: Basis = wd[0]
		var Pw: Vector3 = wd[1]
		var pr: Vector3 = _pivot[p]
		var still: bool = R.is_equal_approx(Basis()) and Pw.is_equal_approx(pr)
		moved[p] = not still
		rot[p] = not R.is_equal_approx(Basis())
		var prow: Dictionary = _prows[p]
		if still:
			lyaw[p] = yaw
			# 回していない部品: 行ごとに だ円と光線の交わりを式で解く (決めた絵とぴったり合う)
			for y in prow:
				for px in w:
					var t0 := px + 0.5 - w * 0.5
					var i: int = px + w * y
					for e in prow[y]:
						var cx: float = e[0]
						var rx: float = e[1]
						var cz: float = e[2]
						var rz: float = e[3]
						var t := t0 - (cx * c + cz * s)
						var qa := s * s / (rx * rx) + c * c / (rz * rz)
						var qb := 2.0 * t * c * s * (1.0 / (rz * rz) - 1.0 / (rx * rx))
						var qc := t * t * (c * c / (rx * rx) + s * s / (rz * rz)) - 1.0
						var disc := qb * qb - 4.0 * qa * qc
						if disc <= 0.0:
							continue
						var d := (-qb + sqrt(disc)) / (2.0 * qa)
						var dd := d + (-cx * s + cz * c)
						if dd > zb[i]:
							zb[i] = dd
							hp[i] = p
							hy[i] = y
							var lx := t * c - d * s
							var lz := t * s + d * c
							hd[i * 6] = lx
							hd[i * 6 + 1] = lz
							hd[i * 6 + 2] = cx
							hd[i * 6 + 3] = rx
							hd[i * 6 + 4] = cz
							hd[i * 6 + 5] = rz
			continue
		# 回した部品: 光線を部品の中の座標に直して、手前から少しずつ進めて当たりを探す
		var Rt := R.inverse()
		var bl: Vector3 = Rt * b3
		lyaw[p] = rad_to_deg(atan2(-bl.x, bl.z))
		var pu := Pw.dot(a3)
		var pd := Pw.dot(b3)
		var r: float = _rad[p]
		var stepv: Vector3 = Rt * b3 * -STEP
		# 腕は「丸い管」として解く: 行ごとの円板だと、回したとき 段のところで切れ、幅 2 画素の腕は 1 画素の棒になる。
		#  管 = 行の真ん中を なめらかにつないだ線のまわりの丸。太さは arm_min より細くしない (太らせる分は体の側へ: 外の輪郭は変えない)。
		#  つけ根・ひじの はしは丸 (曲げても すきまが空かない)、手の先は ほぼ平ら
		var tube: bool = (p in ARMS) and arm_min > 0.0 and not prow.is_empty()
		var tt := 0
		var tb := -1
		var tcx := PackedFloat32Array()
		var tcz := PackedFloat32Array()
		var trr := PackedFloat32Array()
		var trow := PackedInt32Array()
		var free_end := true
		var thh := bl.x * bl.x + bl.z * bl.z      # 光線の向きのうち、腕の軸に直角な分 (0 に近い = 腕が こちらを向いている)
		var tflat := clampf((thh - 0.15) / 0.35, 0.0, 1.0)      # 行を 軸で決める度合い。腕が こちらを向くほど 面のまま (先の丸い面が見えているので、軸で決めると でたらめな行になる)
		if tube:
			tt = 1 << 30
			for y in prow:
				tt = mini(tt, y)
				tb = maxi(tb, y)
			var bx: float = _pivot[BODY].x if _pivot.has(BODY) else 0.0
			var last: int = tt
			for y in range(tt, tb + 1):
				if prow.has(y):
					last = y
				var e: Array = prow[last][0]
				var rr0 := maxf(maxf(e[1], e[3]), arm_min)
				if tcx.size() > 0 and _lrow.has(Vector2i(p, last)):
					# 手のすぐ下の ふちどりの行 (幅 1 画素): 管の真ん中は 上の行のまま、太さは 絵のまま (太らせない)。
					#  ほかの行と同じに 体の側へ太らせると、手の先だけ 体の側へ 1 画素 曲がる
					tcx.append(tcx[tcx.size() - 1])
					tcz.append(tcz[tcz.size() - 1])
					trr.append(maxf(e[1], 0.5))
				else:
					tcx.append(e[0] + signf(bx - e[0]) * (rr0 - e[1]))
					tcz.append(e[2])
					trr.append(rr0)
				trow.append(last)
			free_end = not (CHILD.has(p) and _prows.has(CHILD[p]))
		for row in range(maxi(0, int(floor(-Pw.y - r))), mini((_bot + 1) if floor_clip else h, int(ceil(-Pw.y + r)) + 1)):
			var Y := -(row + 0.5)
			for px in range(maxi(0, int(floor(pu - r + w * 0.5))), mini(w, int(ceil(pu + r + w * 0.5)) + 1)):
				var u := px + 0.5 - w * 0.5
				var rr := r * r - (u - pu) * (u - pu) - (Y - Pw.y) * (Y - Pw.y)
				if rr <= 0.0:
					continue
				var half := sqrt(rr)
				var i: int = px + w * row
				var d0 := pd + half
				if d0 - 2.0 * half <= zb[i] and zb[i] > d0:
					continue
				var q: Vector3 = Rt * (a3 * u + Vector3(0.0, Y, 0.0) + b3 * d0 - Pw) + pr
				var steps := int(2.0 * half / STEP) + 1
				for k in steps:
					var dd := d0 - k * STEP
					if dd <= zb[i]:
						break
					var lrow := int(floor(-q.y))
					if tube:
						var fy := -q.y - 0.5 - tt
						var yc := clampf(fy, 0.0, float(tb - tt))
						var i0 := int(floor(yc))
						var i1 := mini(i0 + 1, tb - tt)
						var f := yc - i0
						var R2 := lerpf(trr[i0], trr[i1], f)
						var dx := q.x - lerpf(tcx[i0], tcx[i1], f)
						var dz := q.z - lerpf(tcz[i0], tcz[i1], f)
						var dy := fy - yc
						if dy > 0.0 and free_end:
							dy *= R2 / 0.75
						if dx * dx + dz * dz + dy * dy < R2 * R2:
							# 絵のどの行を写すかは、当たった面ではなく 腕の軸で決める (光線が 軸に いちばん近づく所の高さ)。
							#  面で決めると、腕を前後に かたむけたとき、管の真ん中の画素は 両はしの画素より 1 行ほど先 (または手前) の行を写す:
							#  手の行と そでの行が 画面の同じ行にまざって、手の肌が そでをはさんで 2 つに分かれる (肌が 1 画素 はなれて残る)
							var ya := yc
							if tflat > 0.0:
								var y1 := clampf(fy + tflat * clampf((dx * bl.x + dz * bl.z) / thh * bl.y, -2.0 * R2, 2.0 * R2), 0.0, float(tb - tt))
								# 軸は まっすぐではない (行ごとに 少しずつ ずれる) ので、その高さの軸で もう 1 回 はかり直す (画面の同じ行の画素が 同じ行を写すように)
								var j0 := int(floor(y1))
								var j1 := mini(j0 + 1, tb - tt)
								var dx1 := q.x - lerpf(tcx[j0], tcx[j1], y1 - j0)
								var dz1 := q.z - lerpf(tcz[j0], tcz[j1], y1 - j0)
								ya = clampf(fy + tflat * clampf((dx1 * bl.x + dz1 * bl.z) / thh * bl.y, -2.0 * R2, 2.0 * R2), 0.0, float(tb - tt))
							var ik := int(floor(ya + 0.5))
							if thh < 0.4:
								# 腕の先が こちらを向いている: 見えているのは 先の丸い面。手の下の線の行ではなく その上の 手の行を写す (手が 線の色で ふさがらない)
								while ik > 0 and _lrow.has(Vector2i(p, trow[ik])):
									ik -= 1
							var ir := trow[ik]
							var e2: Array = prow[ir][0]
							zb[i] = dd
							hp[i] = p
							hy[i] = ir
							hd[i * 6] = dx * e2[1] / R2
							hd[i * 6 + 1] = dz * e2[3] / R2
							hd[i * 6 + 2] = e2[0]
							hd[i * 6 + 3] = e2[1]
							hd[i * 6 + 4] = e2[2]
							hd[i * 6 + 5] = e2[3]
							break
					elif prow.has(lrow):
						var found := false
						for e in prow[lrow]:
							var tx: float = (q.x - e[0]) / e[1]
							var tz: float = (q.z - e[2]) / e[3]
							var m := tx * tx + tz * tz
							if m < 1.0:
								zb[i] = dd
								hp[i] = p
								hy[i] = lrow
								hd[i * 6] = q.x - e[0]
								hd[i * 6 + 1] = q.z - e[2]
								hd[i * 6 + 2] = e[0]
								hd[i * 6 + 3] = e[1]
								hd[i * 6 + 4] = e[2]
								hd[i * 6 + 5] = e[3]
								found = true
								break
						if found:
							break
					q += stepv
	# 空中に描いて足した画素: 描いた向きの奥行きに 厚みを持った 小さな点の集まり。部品と一緒に動く。手前にあるものが残る
	var addpix := PackedInt32Array()     # 画素 → 足した画素の番号 + 1
	addpix.resize(n)
	var cutpix := PackedByteArray()      # けずった画素
	cutpix.resize(n)
	var basehp := hp.duplicate()         # 描いた・けずった画素を入れる前の、画素ごとの部品
	if not _no_adds:
		var wcache := {}
		var locked := _view_locked(b3)
		for ai in adds.size():
			var ad = adds[ai]
			if ad == null:
				continue
			var ap: int = ad[0]
			if not _pivot.has(ap):
				continue
			if not wcache.has(ap):
				wcache[ap] = _world(ap)
			var aR: Basis = wcache[ap][0]
			var aP: Vector3 = wcache[ap][1]
			# 描いた向きから paint_reach より はなれた向きでは出さない。この向きで描いたものがある (locked) なら、ほかの向きで描いたものは出さない
			var aang := _add_ang(ad, aR, b3)
			if (locked and aang > LOCK_EPS) or (paint_reach < 180.0 and aang > deg_to_rad(paint_reach) + 0.001):
				continue
			var is_cut: bool = Color(ad[4]).a < 0.5
			var th2: float = 0.0 if is_cut else float(ad[3])
			var steps2 := maxi(int(ceil(th2 * 2.0 / 0.5)), 1)
			for k in steps2 + 1:
				var q: Vector3 = Vector3(ad[1]) + Vector3(ad[2]) * (-th2 + 2.0 * th2 * k / steps2)
				var wp: Vector3 = aP + aR * (q - _pivot[ap])
				var ax := int(floor(wp.dot(a3) + w * 0.5))
				var ay := int(floor(-wp.y))
				if ax < 0 or ax >= w or ay < 0 or ay >= h or (floor_clip and ay > _bot):
					continue
				var ad2 := wp.dot(b3)
				var j := ax + w * ay
				if is_cut:
					# けずる: そこに見えているもの (立体も、前に描いた画素も) を消す。あとから描いた画素は また出る
					zb[j] = -INF
					hp[j] = 0
					addpix[j] = 0
					cutpix[j] = 1
				elif ad2 > zb[j]:
					zb[j] = ad2
					hp[j] = ap
					hy[j] = ay
					addpix[j] = ai + 1
					cutpix[j] = 0
					if not lyaw.has(ap):
						lyaw[ap] = yaw
	# 色: 部品ごとに、使う絵を 1 枚だけ決める (その部品から見た向きにいちばん近い絵。同じ近さなら 正面・後ろを先に)。
	# 1 つの部品の中で 2 枚の絵を混ぜない: 手描きの正面と横は立体として食いちがうので、混ぜると 顔の肌が髪に入りこむ
	_last_hp = hp
	var painted := PackedByteArray()     # 面に塗った色が出た画素
	painted.resize(n)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var fixed := PackedByteArray()   # 絵をそのまま (線ごと) 写した画素。輪郭線を引き直さない
	fixed.resize(n)
	var pick := {}
	for p in lyaw:
		var ly := deg_to_rad(lyaw[p])
		var best = null
		var bd := 1e9
		var bdel := 0.0
		for src in _src:
			var del := angle_difference(deg_to_rad(src.yaw), ly)
			var k := absf(del) + (0.0 if int(src.yaw) % 180 == 0 else 0.0002)
			if k < bd:
				bd = k
				best = src
				bdel = del
		# 頭は、正面の絵を front_reach まで使う: 横の絵を大きく ずらした顔 (60° あたり) は 横顔に寄りすぎて くずれる。
		#  ゆずるのは 真横の絵だけ (自分で決めた ななめの絵は そのまま使う)
		if p == HEAD and best != null and posmod(int(best.yaw), 180) == 90 and absf(wrapf(ly, -PI, PI)) <= deg_to_rad(front_reach):
			for src in _src:
				if int(src.yaw) == 0:
					best = src
					bdel = angle_difference(0.0, ly)
		pick[p] = [best, bdel, ly]
	# 顔の層 (頭が 正面の絵を使っているとき): 髪は だ円の面に映し、顔は 面から切りはなして 横へすべらせる。
	#  肌 = 向いたほうへ すべり、幅が縮む (ある幅より細くしない)。目・口 = つぶさず 形のまま動かす。奥の目は 50° あたりで消える。
	#  立体どおりに面へ映すと、横を向いたとき 目 (幅 1 画素) が つぶれて消え、肌は 手描きの横顔より ずっと細くなる
	var f_on := false
	var f_d := 0.0
	var f_k := 1.0
	var f_slide := 0.0
	var f_map := {}
	if face_layer and _face_ok and pick.has(HEAD) and pick[HEAD][0] != null and int(pick[HEAD][0].yaw) == 0:
		f_d = wrapf(pick[HEAD][2], -PI, PI)
		var ad := absf(f_d)
		var lim := deg_to_rad(115.0)
		if not (ad < 0.02 and not rot.get(HEAD, false)) and ad < lim:
			f_on = true
			f_k = maxf(cos(f_d), face_min) if ad <= PI * 0.5 else face_min * (lim - ad) / (lim - PI * 0.5)
			f_k = maxf(f_k, 0.05)
			# 頭のふちの 1 画素は線 (外ふちがあれば 2 画素) になるので、その分 内側に置く
			f_slide = sin(f_d) * maxf(_hrz - face_min * _fhw - (2.0 if _rim.a > 0.5 else 1.0) + face_out, 0.0)
			var foff0 := _fcx - _hcx
			if ad < deg_to_rad(105.0):
				for b in _fblobs:
					var ob: float = b.cx - _fcx
					if ob * sin(f_d) < -0.2 * _fhw and ad > deg_to_rad(50.0):
						continue                 # 奥の目
					var sh := int(round(foff0 * cos(f_d) + f_slide + ob * f_k - (b.cx - _hcx)))
					var bw: int = b.x1 - b.x0 + 1
					for q in b.pix:
						if bw >= 3 and absf(q.x + 0.5 - w * 0.5 - b.cx) > maxf(0.5, bw * f_k * 0.5):
							continue             # 口など 横に長いもの: 縮める
						f_map[Vector2i(q.x + sh, q.y)] = _fill0.get_pixel(q.x, q.y)
	for i in n:
		var p := hp[i]
		if p == 0:
			continue
		if addpix[i] != 0:
			img.set_pixel(i % w, i / w, adds[addpix[i] - 1][4])
			fixed[i] = 1                     # 描いた色のまま (ふちどりで上書きしない)
			painted[i] = 1
			continue
		var y := hy[i]
		var col := _back_of(p, y)
		if f_on and p == HEAD:
			col = _hair_mode
		var src = pick[p][0]
		var del: float = pick[p][1]
		# 腕は 正面の絵からだけ色を取る: 横・後ろの絵の腕は 体に重ねて描いてあり、立体の腕の場所と合わない (行ごとの色 = そで・手 は _back_of が出す)
		if src != null and absf(del) <= deg_to_rad(100.0) and y >= _prange[p][0] and y <= _prange[p][1] and not (p in ARMS and int(src.yaw) != 0):
			var ly: float = pick[p][2]
			var lx := hd[i * 6]
			var lz := hd[i * 6 + 1]
			var cx := hd[i * 6 + 2]
			var rx := hd[i * 6 + 3]
			var cz := hd[i * 6 + 4]
			var rz := hd[i * 6 + 5]
			var a := deg_to_rad(src.yaw)
			var exact := absf(del) < 0.02
			# その部品を「いま見ている向き」から見たときの、だ円の真ん中からの横のずれ t (-幅 〜 +幅)
			var t := lx * cos(ly) + lz * sin(ly)
			var off := t
			var ok := true
			if not exact:
				# 向きがずれた分のうち wrap の割合だけ、絵を回りこませる (立体どおりには回さない: 顔が はしへ流れすぎない)
				var wv := sqrt(rx * rx * cos(ly) * cos(ly) + rz * rz * sin(ly) * sin(ly))
				# 頭が 横の絵を使っていて、いまの向きが その絵より 正面寄り (70°〜90° など) のとき: 絵を回りこませない。
				#  回りこませると、手前に出てくる側 (鼻・口のある はし) の 1 列が引きのばされて、口や目が 横向きの絵より長くなる
				var wr := wrap
				if p == HEAD and int(src.yaw) != 0 and absf(wrapf(ly, -PI, PI)) < absf(wrapf(a, -PI, PI)) - 0.001:
					wr = 0.0
				var ang := asin(clampf(t / maxf(wv, 0.001), -1.0, 1.0)) - wr * del
				ok = absf(ang) < PI * 0.5
				# 回って新しく見えてきた側は、絵の はしの 1 列が何画素にも引きのばされる → 2 倍をこえたら、絵を使わず 部品の色 (頭なら髪) で塗る
				var sn := clampf(t / maxf(wv, 0.001), -1.0, 1.0)
				if ok and ang * del < 0.0 and cos(ang) / maxf(sqrt(1.0 - sn * sn), 0.05) < 0.5:
					ok = false
				off = sqrt(rx * rx * cos(a) * cos(a) + rz * rz * sin(a) * sin(a)) * sin(ang)
			if ok:
				var u0 := int(floor(cx * cos(a) + cz * sin(a) + off + w * 0.5))      # 立体の上での場所
				var u := u0 + int(src.dx)                                           # 絵の上での場所
				# 絵をそのまま (線ごと) 写すのは、回していない部品だけ。回した部品に 元の場所の線を写すと、線が でたらめな所に出て、ふちどりも引き直されない
				var as_is: bool = exact and not rot.get(p, false)
				var im: Image = src.raw if as_is else src.img
				# 体や脚の絵に描きこまれた手: その腕を動かしていたら使わない (腕を上げたのに 手が下に残らないように)
				var hand_gone := false
				if not (p in ARMS) and u >= 0 and u < w and src.hand[u + w * y] != 0:
					var ca := cos(a)
					var arm: int
					if absf(ca) > 0.5:
						arm = ARM_A if (u + 0.5 - w * 0.5) * ca < 0.0 else ARM_B
					else:
						arm = ARM_A if sin(a) > 0.0 else ARM_B      # 横の絵: 手前の腕
					hand_gone = true         # 手は いつも腕の立体が出す (絵の手と 両方出ると 手が増える)
				if hand_gone:
					pass
				elif _op(im, u, y):
					# 正面・後ろの絵で、そこが別の部品の画素なら使わない (腕をどけた下の体に、腕の絵が映らないように)
					var other: bool = (src.yaw == 0 and _pm2[u + w * y] != p) or (src.yaw == 180 and _pm2[clampi(w - 1 - u0, 0, w - 1) + w * y] != p)
					if not other:
						col = im.get_pixel(u, y)
						if as_is:
							fixed[i] = 1
						elif f_on and p == HEAD and _face[u + w * y] != 0:
							col = _hair_row.get(y, _hair_mode)      # 面に映った顔は使わない (顔は下の層で描く)
		if not _lrow.is_empty() and _lrow.has(Vector2i(p, y)):
			col = _lrow[Vector2i(p, y)]      # 手のすぐ下の ふちどりの行
		if f_on and p == HEAD and y >= _prange[p][0] and y <= _prange[p][1]:
			var fly: float = pick[p][2]
			var ft := hd[i * 6] * cos(fly) + hd[i * 6 + 1] * sin(fly) + (hd[i * 6 + 2] - _hcx) * cos(fly) + (hd[i * 6 + 4] - _hcz) * sin(fly)
			var fxf := _fcx + (ft - (_fcx - _hcx) * cos(f_d) - f_slide) / f_k
			var fpx := int(floor(fxf + w * 0.5))
			if fpx >= 0 and fpx < w and _face[fpx + w * y] != 0:
				col = _fill0.get_pixel(fpx, y) if _face[fpx + w * y] == 1 else Color.hex(_skin)
				var fq := Vector2i(int(floor(ft + _hcx + w * 0.5)), y)
				if f_map.has(fq):
					col = f_map[fq]
		if not spaint.is_empty():
			var sk := _skey(p, y, hd[i * 6], hd[i * 6 + 1], hd[i * 6 + 3], hd[i * 6 + 5])
			if spaint.has(sk) and _in_reach(spaint[sk][1], float(lyaw.get(p, yaw))):
				col = spaint[sk][0]
				fixed[i] = 1                 # 塗った色は そのまま (ふちどりで上書きしない)
				painted[i] = 1
		img.set_pixel(i % w, i / w, col)
	# 絵がある向きを ぴったり見ているとき: 回していない部品の輪郭は、立体ではなく 絵に合わせる。
	#  手描きの後ろ・横の絵の輪郭は、立体 (正面の絵の幅で作った) の輪郭と 所どころ 1 画素食いちがう。
	#  そのままだと、絵が立体より外に出ている側は 線が消え、立体が絵より外に出ている側は 部品の色 + 引き直した線で 線が 2 重になる
	var vsrc = null
	for src in _src:
		if absf(angle_difference(deg_to_rad(src.yaw), th)) < 0.02 and src.has("rest"):
			vsrc = src
	if vsrc != null:
		var rsx := int(round(root.dot(a3)))
		var rsy := int(round(-root.y))
		var vdx := int(vsrc.dx)
		var vraw: Image = vsrc.raw
		var rest: PackedByteArray = vsrc.rest
		var va := deg_to_rad(vsrc.yaw)
		for y in mini(h, (_bot + 1) if floor_clip else h):
			for x in w:
				var i := x + w * y
				var qx := x - rsx                # 立ちの絵での場所 (立体の上)
				var qy := y - rsy
				var ux := qx + vdx               # 絵の上での場所
				var on := _op(vraw, ux, qy)
				if cutpix[i] != 0:
					continue                     # けずった所は 絵から足さない
				var p := hp[i]
				if p != 0:
					# 立体が絵より外に出ている: 絵に無い所は描かない
					if not on and addpix[i] == 0 and not rot.get(p, false) and pick[p][0] == vsrc:
						hp[i] = 0
						fixed[i] = 0
						img.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				if not on:
					continue
				# 絵が立体より外に出ている: 絵の画素を足す。だれの画素か = 立ちのとき いちばん近くに見えていた部品
				var owner := 0
				for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
					var ex: int = qx + d.x
					var ey: int = qy + d.y
					if ex >= 0 and ex < w and ey >= 0 and ey < h and rest[ex + w * ey] != 0:
						owner = rest[ex + w * ey]
						break
				if owner == 0 or rot.get(owner, false):
					continue                     # 回した部品 (上げた腕) の 元の場所には足さない
				if vsrc.hand[ux + w * qy] != 0:
					var ca := cos(va)
					var arm: int
					if absf(ca) > 0.5:
						arm = ARM_A if (ux + 0.5 - w * 0.5) * ca < 0.0 else ARM_B
					else:
						arm = ARM_A if sin(va) > 0.0 else ARM_B
					continue
				img.set_pixel(x, y, vraw.get_pixel(ux, qy))
				fixed[i] = 1
				hp[i] = owner
				zb[i] = -1e6
	# 輪郭線を引き直す: ふちの画素を、その色の線の色に。外のふち (_rim) があれば、いちばん外をその色に、その内側を線の色に。
	# 絵をそのまま写した画素 (fixed) は、絵の線がもう入っているので触らない
	var out := img.duplicate() as Image
	# ふちは「描いた・けずった画素を入れる前の形」で決める。入れたあとの形で決めると、1 画素描くたびに となりの画素が 線になったり 線でなくなったりする
	var eimg := img
	if not adds.is_empty():
		eimg = img.duplicate()
		for i in n:
			if cutpix[i] != 0:
				fixed[i] = 1
				if basehp[i] != 0:
					eimg.set_pixel(i % w, i / w, Color.BLACK)
			elif addpix[i] != 0 and basehp[i] == 0:
				eimg.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
	var ring := _edge_of(eimg, {})
	var skip := {}
	if _rim.a > 0.5:
		for p in ring:
			if fixed[p.x + w * p.y] == 0:
				out.set_pixel(p.x, p.y, _rim)
		skip = ring
		ring = _edge_of(eimg, skip)
	for p in ring:
		if fixed[p.x + w * p.y] == 1:
			continue
		var k := img.get_pixel(p.x, p.y).to_rgba32()
		if _is_skin(k) and hp[p.x + w * p.y] in ARMS:
			continue                 # 手: 小さいので ふちどりで つぶさない (手のかげは ふちに来たら 線にする: 手の先が 線で閉じる)
		if _line.has(k):
			out.set_pixel(p.x, p.y, _line[k])
		elif not _edge_ok.has(k) and not _line_cols.has(k):
			# 元の絵の ふちに無かった色 (部品の色で塗った所など): その部品の線の色、無ければ いちばんふつうの線の色
			var pc: Color = _pmode.get(hp[p.x + w * p.y], Color.BLACK)
			var lcol: Color = _line.get(pc.to_rgba32(), _line_default)
			if lcol.a > 0.5:
				out.set_pixel(p.x, p.y, lcol)
	# 動かした腕・脚が、ほかの部品と となりあう所にも ふちどりを引く (黒い服の横・上の黒い腕が 服と一体に見えないように。
	#  奥行きの差は見ない: 肩のあたりは 腕と体が同じ奥行きで並ぶので、差を見ると線が出ず、腕が腰から生えたように見えた)。
	#  同じ腕の中 (ひじの上下) には引かない。手 (元の絵で線なしで ふちにいた色) にも引かない
	for i in n:
		var p := hp[i]
		if not (p in ARMS or p in LEGS) or not moved.get(p, false) or fixed[i] == 1:
			continue
		var limb := p if p <= 6 else p - 4
		var x := i % w
		var y := i / w
		var over := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = x + d.x
			var yy: int = y + d.y
			if xx < 0 or xx >= w or yy < 0 or yy >= h:
				continue
			var j := xx + w * yy
			var q := hp[j]
			if q != 0 and (q if q <= 6 else q - 4) != limb:
				over = true
				break
		if not over:
			continue
		var k := img.get_pixel(x, y).to_rgba32()
		if _is_hand(k) and p in ARMS:
			continue                 # 手 (肌・かげ) には引かない
		var lcol: Color = _line.get(k, _line.get(_pmode.get(p, Color.BLACK).to_rgba32(), _line_default))
		if lcol.a > 0.5:
			out.set_pixel(x, y, lcol)
	# 手を太らせない: 絵の手は 線にはさまれた 幅 1 画素。腕を管 (幅 3) にすると 手が 4〜7 画素の かたまりになり、向きを変えるたびに 手が増えたように見える。
	#  腕の 肌の画素が 横に 2 つ以上並んだら、はしを線の色にする (2 つなら 外側の 1 つだけ)
	var hline: Color = _hand_line if _hand_line.a > 0.5 else _line.get(_skin, _line_default)
	if hline.a > 0.5:
		for y in h:
			var x := 0
			while x < w:
				var i0 := x + w * y
				if not (hp[i0] in ARMS and fixed[i0] == 0 and _is_hand(out.get_pixel(x, y).to_rgba32())):
					x += 1
					continue
				var x1 := x
				while x1 + 1 < w and hp[x1 + 1 + w * y] in ARMS and fixed[x1 + 1 + w * y] == 0 and _is_hand(out.get_pixel(x1 + 1, y).to_rgba32()):
					x1 += 1
				var n2 := x1 - x + 1
				if n2 >= 3:
					out.set_pixel(x, y, hline)
					out.set_pixel(x1, y, hline)
				elif n2 == 2:
					var left_open: bool = x == 0 or eimg.get_pixel(x - 1, y).a < 0.5      # 描いた画素は見ない (となりに描いても 手の形が変わらないように)
					out.set_pixel(x if left_open else x1, y, hline)
				x = x1 + 1
		# 手は 腕 1 本に 1 つ: 腕の 肌の かたまりが 2 つ以上あれば、いちばん大きいもの (同じ大きさなら 手の先に近いほう) を残し、
		#  2 画素までの小さいものは 線の色にする (ひじを曲げて 手の一部が かくれたときなどに、肌が 1 画素だけ はなれて残らないように)。
		#  3 画素より大きい かたまりは そのまま (そでの無い腕に 腕輪があるような絵)
		for hl_limb in [[ARM_A, FORE_A], [ARM_B, FORE_B]]:
			var hl_seen := {}
			var hl_blobs := []
			for i in n:
				if hl_seen.has(i) or fixed[i] == 1 or not (hp[i] in hl_limb) or not _is_hand(out.get_pixel(i % w, i / w).to_rgba32()):
					continue
				var hl_cells := PackedInt32Array()
				var hl_todo := [i]
				var hl_tip := 0
				hl_seen[i] = true
				while not hl_todo.is_empty():
					var ci: int = hl_todo.pop_back()
					hl_cells.append(ci)
					hl_tip = maxi(hl_tip, hy[ci])
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
						var cx2: int = ci % w + d.x
						var cy2: int = ci / w + d.y
						if cx2 < 0 or cx2 >= w or cy2 < 0 or cy2 >= h:
							continue
						var cj := cx2 + w * cy2
						if not hl_seen.has(cj) and fixed[cj] == 0 and hp[cj] in hl_limb and _is_hand(out.get_pixel(cx2, cy2).to_rgba32()):
							hl_seen[cj] = true
							hl_todo.append(cj)
				hl_blobs.append([hl_cells, hl_tip])
			if hl_blobs.size() < 2:
				continue
			var hl_best := 0
			for bi in range(1, hl_blobs.size()):
				var sz: int = hl_blobs[bi][0].size()
				var bz: int = hl_blobs[hl_best][0].size()
				if sz > bz or (sz == bz and hl_blobs[bi][1] > hl_blobs[hl_best][1]):
					hl_best = bi
			for bi in hl_blobs.size():
				if bi != hl_best and hl_blobs[bi][0].size() <= 2:
					for ci in hl_blobs[bi][0]:
						out.set_pixel(ci % w, ci / w, hline)
	# 絵の場所に合わせて 横へずらす (立ちの絵と ポーズの絵で、体が 1 画素とばないように)
	var sdx := _view_dx(yaw)
	if sdx != 0:
		var sh := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		sh.blit_rect(out, Rect2i(0, 0, w, h), Vector2i(sdx, 0))
		var hp2 := PackedByteArray()
		hp2.resize(n)
		for i in n:
			var x2 := i % w - sdx
			if x2 >= 0 and x2 < w:
				hp2[i] = hp[i - sdx]
		_last_hp = hp2
		out = sh
	_hb = {"hp": hp, "hy": hy, "hd": hd, "lyaw": lyaw, "dx": sdx, "zb": zb, "add": addpix, "yaw": yaw}
	_hb_key = "%.2f|%s|%s" % [yaw, str(pose), str(root)]
	if base_pic != null:
		for i in n:
			var xs := i % w - sdx
			if xs >= 0 and xs < w and painted[i - sdx] == 1 and hp[i - sdx] != 0:
				base_pic.set_pixel(i % w, i / w, out.get_pixel(i % w, i / w))
			elif xs >= 0 and xs < w and cutpix[i - sdx] == 1:
				base_pic.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
		return base_pic
	return out


## 空中 (立体の無い画素) に描く: いちばん近い立体の画素と 同じ部品・同じ奥行きに、画素を 1 つ足す。
## 近くに立体が無ければ、頭 (首より上) か 体の 真ん中の奥行きに置く。足した画素は その部品と一緒に動き、ほかの向きからも見える
func _add_air(xs: int, y: int, c: Color) -> bool:
	var hp: PackedByteArray = _hb.hp
	var zb: PackedFloat32Array = _hb.zb
	var yaw: float = _hb.yaw
	var th := deg_to_rad(yaw)
	var a3 := Vector3(cos(th), 0.0, sin(th))
	var b3 := Vector3(-sin(th), 0.0, cos(th))
	var part := 0
	var depth := 0.0
	var best := 1e9
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var xx := xs + dx
			var yy := y + dy
			if xx < 0 or xx >= w or yy < 0 or yy >= h or hp[xx + w * yy] == 0:
				continue
			var d2 := float(dx * dx + dy * dy)
			if d2 < best:
				best = d2
				part = hp[xx + w * yy]
				depth = zb[xx + w * yy]
	if part == 0:
		part = HEAD if (y < neck and _pivot.has(HEAD)) else BODY
		if not _pivot.has(part):
			return false
		depth = Vector3(_world(part)[1]).dot(b3)
	var wd := _world(part)
	var R: Basis = wd[0]
	var world := a3 * (xs + 0.5 - w * 0.5) + Vector3(0.0, -(y + 0.5), 0.0) + b3 * depth
	var Rt := R.inverse()
	adds.append([part, Rt * (world - Vector3(wd[1])) + _pivot[part], Rt * b3, air_thick, c])
	# 当たりの表を その場で直す (つづけて描く画素が、いま足した画素に くっつくように)
	var i := xs + w * y
	var cut := c.a < 0.5
	hp[i] = 0 if cut else part
	zb[i] = -INF if cut else depth
	_hb.hp = hp
	_hb.zb = zb
	var ap: PackedInt32Array = _hb.add
	ap[i] = 0 if cut else adds.size()
	_hb.add = ap
	return true


const LOCK_EPS := 0.011          ## 「同じ向きで描いた」とみなす角度の差 (ラジアン。およそ 0.6°)


## 描いた画素 ad の「描いた向き」と、いまの向き b3 (部品の回転 R) との差 (ラジアン)
func _add_ang(ad: Array, R: Basis, b3: Vector3) -> float:
	var cb: Vector3 = R.inverse() * b3
	var av := Vector2(Vector3(ad[2]).x, Vector3(ad[2]).z)
	if av.length() < 0.01:
		return 0.0
	return absf(av.angle_to(Vector2(cb.x, cb.z)))


## この向きで描いた (けずった) ものが 1 つでもあるか。あれば、この向きは「描きかえた向き」: ほかの向きで描いたものを受けつけない
func _view_locked(b3: Vector3) -> bool:
	var wc := {}
	for ad in adds:
		if ad == null or not _pivot.has(ad[0]):
			continue
		if not wc.has(ad[0]):
			wc[ad[0]] = _world(ad[0])[0]
		if _add_ang(ad, wc[ad[0]], b3) <= LOCK_EPS:
			return true
	return false


## はじめて この向きで描く前に: いま この向きに出ている「ほかの向きで描いたもの」を、この向きのものとして写す。
## (写さないと、1 画素描いたとたんに ほかの向きから来ていた画素が ぜんぶ消える)
func _bake_view(yaw: float) -> void:
	var th := deg_to_rad(yaw)
	var b3 := Vector3(-sin(th), 0.0, cos(th))
	if _view_locked(b3):
		return
	var wc := {}
	var copies := []
	for ad in adds:
		if ad == null or not _pivot.has(ad[0]):
			continue
		if not wc.has(ad[0]):
			wc[ad[0]] = _world(ad[0])[0]
		var R: Basis = wc[ad[0]]
		if paint_reach >= 180.0 or _add_ang(ad, R, b3) <= deg_to_rad(paint_reach) + 0.001:
			copies.append([ad[0], Vector3(ad[1]), R.inverse() * b3, ad[3], ad[4]])
	adds.append_array(copies)


## 描いたときの向き py (度) が、いまの向き cur (度) から paint_reach 以内か
func _in_reach(py: float, cur: float) -> bool:
	return is_nan(py) or paint_reach >= 180.0 or absf(angle_difference(deg_to_rad(py), deg_to_rad(cur))) <= deg_to_rad(paint_reach) + 0.001


## 面の ます: 部品 p の 行 y の だ円のまわりを、およそ 1 画素ごとに区切った番号
func _skey(p: int, y: int, lx: float, lz: float, rx: float, rz: float) -> Vector3i:
	var nb := maxi(8, int(ceil(TAU * maxf(rx, rz))))
	var b := int(floor(fposmod(atan2(lx / maxf(rx, 0.01), lz / maxf(rz, 0.01)), TAU) / TAU * nb)) % nb
	return Vector3i(p, y, b)


## 向き yaw の絵の 画素 (x, y) に描く。立体の上でも 空中でも同じ: そこに 色のついた画素を 1 つ置く。c.a = 0 なら そこを空にする (立体もけずる)。
## 置いた画素は 近くの部品にくっついて動き、描いた向きから ± paint_reach の向きで出る
func paint_surface(yaw: float, x: int, y: int, c: Color) -> bool:
	var key := "%.2f|%s|%s" % [yaw, str(pose), str(root)]
	if _dirty or _hb_key != key or _hb.is_empty():
		render(yaw, true)
	if not _hb.get("baked", false):
		var n_before := adds.size()
		_bake_view(yaw)
		if adds.size() != n_before:
			render(yaw, true)
		_hb["baked"] = true
	var xs := x - int(_hb.dx)
	if xs < 0 or xs >= w or y < 0 or y >= h:
		return false
	var i := xs + w * y
	var on_add: int = _hb.add[i]
	if c.a >= 0.5:
		# 描く: 前に描いた画素の上なら 色を変える。そうでなければ、そこに画素を 1 つ足す (立体の上でも 空中でも同じ)
		if on_add != 0:
			if adds[on_add - 1][4] == c:
				return false
			adds[on_add - 1][4] = c
			return true
		return _add_air(xs, y, c)
	# 消す: そこを空にする (描いた画素も、立体そのものも)
	if on_add == 0 and _hb.hp[i] == 0:
		return false
	if on_add != 0:
		adds[on_add - 1] = null
	return _add_air(xs, y, Color(0, 0, 0, 0))


## さいごに描いた絵で、画素 (x, y) に出ている部品 (0 = 無い / 決めた絵をそのまま返したとき)
func hit_part(x: int, y: int) -> int:
	var i := x + w * y
	return _last_hp[i] if i >= 0 and i < _last_hp.size() else 0


func is_line_color(c: Color) -> bool:
	return _line_cols.has(c.to_rgba32()) or (_rim.a > 0.5 and c.is_equal_approx(_rim))


## view_yaw = 見ている向き (度)。渡すと、顔の層 (向きで すべる顔) を その向きの見え方で網目に塗る。
## 3D で見る用の網目。unit = 1 画素の長さ。足の下が y = 0。色は、面の向きに近い絵から取る (見るだけの簡単な色)
func make_mesh(unit: float, view_yaw := NAN) -> ArrayMesh:
	ensure()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := float(_bot + 1)
	for p in _prows:
		var wd := _world(p)
		var R: Basis = wd[0]
		var Pw: Vector3 = wd[1]
		var pr: Vector3 = _pivot[p]
		var fat: bool = (p in ARMS) and arm_min > 0.0 and not (R.is_equal_approx(Basis()) and Pw.is_equal_approx(pr))
		var to_w := func(v: Vector3) -> Vector3:
			var q: Vector3 = Pw + R * (v - pr)
			return Vector3(q.x, q.y + base, q.z) * unit
		var part_ly := NAN                   # この部品から見た、いまの向き (度)
		if not is_nan(view_yaw):
			var pb: Vector3 = R.inverse() * Vector3(-sin(deg_to_rad(view_yaw)), 0.0, cos(deg_to_rad(view_yaw)))
			part_ly = rad_to_deg(atan2(-pb.x, pb.z))
		# 顔の層: 頭が 正面の絵を使う向きなら、render と同じ式で 顔を すべらせて塗る
		var f_on := false
		var f_d := 0.0
		var f_k := 1.0
		var f_slide := 0.0
		if p == HEAD and face_layer and _face_ok and not is_nan(view_yaw):
			var vth := deg_to_rad(view_yaw)
			var vbl: Vector3 = R.inverse() * Vector3(-sin(vth), 0.0, cos(vth))
			f_d = wrapf(atan2(-vbl.x, vbl.z), -PI, PI)
			var near_yaw := 0
			var near_d := absf(f_d)
			for src in _src:
				var sd := absf(angle_difference(deg_to_rad(src.yaw), f_d)) + (0.0 if int(src.yaw) % 180 == 0 else 0.0002)
				if sd < near_d:
					near_d = sd
					near_yaw = int(src.yaw)
			var near0: bool = near_yaw == 0 or (posmod(near_yaw, 180) == 90 and absf(f_d) <= deg_to_rad(front_reach))
			var lim := deg_to_rad(115.0)
			if near0 and absf(f_d) < lim:
				f_on = true
				f_k = maxf(cos(f_d), face_min) if absf(f_d) <= PI * 0.5 else face_min * (lim - absf(f_d)) / (lim - PI * 0.5)
				f_k = maxf(f_k, 0.05)
				f_slide = sin(f_d) * maxf(_hrz - face_min * _fhw - (2.0 if _rim.a > 0.5 else 1.0) + face_out, 0.0)
		for y in _prows[p]:
			var own: bool = y >= _prange[p][0] and y <= _prange[p][1]
			for e_raw in _prows[p][y]:
				var e: Array = e_raw
				if fat:
					var rr0 := maxf(maxf(e[1], e[3]), arm_min)
					var bx: float = _pivot[BODY].x if _pivot.has(BODY) else 0.0
					e = [e[0] + signf(bx - e[0]) * (rr0 - e[1]), rr0, e[2], rr0]
				var capc := _back_of(p, y)
				var seg := clampi(int(ceil(TAU * maxf(e[1], e[3]))), 8, 64)      # 1 面が およそ 1 画素
				for k in seg:
					var f0 := TAU * k / seg
					var f1 := TAU * (k + 1) / seg
					var fm := (f0 + f1) * 0.5
					var col := capc
					if own:
						# 面の向き (度) にいちばん近い絵
						var facing := -fm
						var best = null
						var bd := 1e9
						for src in _src:
							var dv := absf(angle_difference(deg_to_rad(src.yaw), facing))
							if dv < bd:
								bd = dv
								best = src
						if best != null and bd < PI * 0.5:
							var a := deg_to_rad(best.yaw)
							var mx: float = e[0] + e[1] * sin(fm)
							var mz: float = e[2] + e[3] * cos(fm)
							var u := int(floor(mx * cos(a) + mz * sin(a) + w * 0.5))
							if _op(best.img, u, y):
								var other: bool = (best.yaw == 0 and _pm2[u + w * y] != p) or (best.yaw == 180 and _pm2[(w - 1 - u) + w * y] != p)
								if not other:
									col = best.img.get_pixel(u, y)
									if f_on and int(best.yaw) == 0 and _face[u + w * y] != 0:
										col = _hair_mode
					if f_on and own:
						var qx: float = e[0] + e[1] * sin(fm) - _hcx
						var qz: float = e[2] + e[3] * cos(fm) - _hcz
						if -qx * sin(f_d) + qz * cos(f_d) > 0.0:
							var ft := qx * cos(f_d) + qz * sin(f_d)
							var fpx := int(floor(_fcx + (ft - (_fcx - _hcx) * cos(f_d) - f_slide) / f_k + w * 0.5))
							if fpx >= 0 and fpx < w and _face[fpx + w * y] != 0:
								col = _fill0.get_pixel(fpx, y)
					if not spaint.is_empty():
						var sk := _skey(p, y, e[1] * sin(fm), e[3] * cos(fm), e[1], e[3])
						if spaint.has(sk) and (is_nan(part_ly) or _in_reach(spaint[sk][1], part_ly)):
							col = spaint[sk][0]
					var a0 := Vector3(e[0] + e[1] * sin(f0), -float(y), e[2] + e[3] * cos(f0))
					var a1 := Vector3(e[0] + e[1] * sin(f1), -float(y), e[2] + e[3] * cos(f1))
					var b0 := a0 + Vector3(0, -1, 0)
					var b1 := a1 + Vector3(0, -1, 0)
					var nrm: Vector3 = (R * Vector3(sin(fm) / e[1], 0.0, cos(fm) / e[3])).normalized()
					for v in [a0, b0, a1, a1, b0, b1]:
						st.set_color(col)
						st.set_normal(nrm)
						st.add_vertex(to_w.call(v))
					# ふた (上と下)
					var ct := Vector3(e[0], -float(y), e[2])
					var cb := ct + Vector3(0, -1, 0)
					for tri in [[ct, a0, a1, Vector3.UP], [cb, b1, b0, Vector3.DOWN]]:
						for v in [tri[0], tri[1], tri[2]]:
							st.set_color(capc)
							st.set_normal((R * tri[3]).normalized())
							st.add_vertex(to_w.call(v))
	for ad in adds:
		if ad == null or not _pivot.has(ad[0]) or Color(ad[4]).a < 0.5:
			continue                     # けずった所は 網目には出ない
		var wd2 := _world(ad[0])
		var R2: Basis = wd2[0]
		if not is_nan(view_yaw):
			var vb3 := Vector3(-sin(deg_to_rad(view_yaw)), 0.0, cos(deg_to_rad(view_yaw)))
			var mang := _add_ang(ad, R2, vb3)
			if (_view_locked(vb3) and mang > LOCK_EPS) or (paint_reach < 180.0 and mang > deg_to_rad(paint_reach) + 0.001):
				continue
		var c0: Vector3 = Vector3(wd2[1]) + R2 * (Vector3(ad[1]) - _pivot[ad[0]])
		var az: Vector3 = (R2 * Vector3(ad[2])).normalized() * float(ad[3])
		var au := Vector3(0.0, 0.5, 0.0)
		var ar: Vector3 = au.cross(az).normalized() * 0.5
		var cs := []
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var v: Vector3 = c0 + ar * sx + au * sy + az * sz
					cs.append(Vector3(v.x, v.y + base, v.z) * unit)
		for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			var nr: Vector3 = (cs[f[1]] - cs[f[0]]).cross(cs[f[2]] - cs[f[0]]).normalized()
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(ad[4])
				st.set_normal(nr)
				st.add_vertex(cs[f[k]])
	return st.commit()


## 横の絵の、いまの見た目 (決めた絵か、推定)
func is_drawn(key: int) -> bool:
	return pics.has(key)


## 紙に余白を足した写し (左右 px ずつ・上 top・下 bottom 画素)。ポーズで紙から はみ出す分を入れるため。
## 左右は同じだけ足す (紙の真ん中 = 回る軸 なので)
func padded(px: int, top: int, bottom: int) -> DotSolid:
	var s := DotSolid.from_doc(to_doc())
	if px <= 0 and top <= 0 and bottom <= 0:
		return s
	px = maxi(px, 0)
	top = maxi(top, 0)
	bottom = maxi(bottom, 0)
	var nw := w + 2 * px
	var nh := h + top + bottom
	for k in s.pics.keys():
		var im := Image.create_empty(nw, nh, false, Image.FORMAT_RGBA8)
		im.blit_rect(s.pics[k], Rect2i(0, 0, w, h), Vector2i(px, top))
		s.pics[k] = im
	if s.pmap_user and s.pmap.size() == w * h:
		var pm := PackedByteArray()
		pm.resize(nw * nh)
		for y in h:
			for x in w:
				pm[(x + px) + nw * (y + top)] = s.pmap[x + w * y]
		s.pmap = pm
	if top != 0:
		for ad in s.adds:
			ad[1] = Vector3(ad[1]) - Vector3(0.0, top, 0.0)
		var sp := {}
		for k in s.spaint:
			sp[Vector3i(k.x, k.y + top, k.z)] = s.spaint[k]
		s.spaint = sp
	s.w = nw
	s.h = nh
	s._dirty = true
	return s


func _doc_more(d: Dictionary) -> Dictionary:
	if not spaint.is_empty():
		var sp := []
		for k in spaint:
			var e := [k.x, k.y, k.z, Color(spaint[k][0]).to_html(true)]
			if not is_nan(spaint[k][1]):
				e.append(spaint[k][1])
			sp.append(e)
		d["spaint"] = sp
	var al := []
	for ad in adds:
		if ad != null:
			var q := Vector3(ad[1])
			var ax := Vector3(ad[2])
			al.append([ad[0], q.x, q.y, q.z, ax.x, ax.y, ax.z, ad[3], Color(ad[4]).to_html(true)])
	if not al.is_empty():
		d["adds"] = al
	d["air_thick"] = air_thick
	d["paint_reach"] = paint_reach
	return d


func to_doc() -> Dictionary:
	var p := {}
	for k in pics:
		p[str(k)] = Marshalls.raw_to_base64(pics[k].get_data())
	if pmap_user:
		return _doc_more({"w": w, "h": h, "pics": p, "k_head": k_head, "k_body": k_body, "k_leg": k_leg, "depth": depth_scale, "wrap": wrap, "joints": joints, "leg_hidden": leg_hidden, "arm_min": arm_min, "face_layer": face_layer, "shoulder_up": shoulder_up, "waist": waist, "front_reach": front_reach, "skin_tol": skin_tol, "face_min": face_min,
				"pmap": Marshalls.raw_to_base64(pmap)})
	return _doc_more({"w": w, "h": h, "pics": p, "k_head": k_head, "k_body": k_body, "k_leg": k_leg, "depth": depth_scale, "wrap": wrap, "joints": joints, "leg_hidden": leg_hidden, "arm_min": arm_min, "face_layer": face_layer, "shoulder_up": shoulder_up, "waist": waist, "front_reach": front_reach, "skin_tol": skin_tol, "face_min": face_min})


static func from_doc(d: Dictionary) -> DotSolid:
	var s := DotSolid.new()
	s.w = int(d.get("w", 0))
	s.h = int(d.get("h", 0))
	for k in d.get("pics", {}):
		var data := Marshalls.base64_to_raw(d.pics[k])
		if data.size() == s.w * s.h * 4:
			s.pics[int(k)] = Image.create_from_data(s.w, s.h, false, Image.FORMAT_RGBA8, data)
	s.k_head = float(d.get("k_head", 1.0))
	s.k_body = float(d.get("k_body", 0.65))
	s.k_leg = float(d.get("k_leg", 1.5))
	s.wrap = float(d.get("wrap", 0.6))
	s.depth_scale = float(d.get("depth", 1.0))
	s.joints = d.get("joints", true)
	s.leg_hidden = float(d.get("leg_hidden", 0.2))
	s.arm_min = float(d.get("arm_min", 1.5))
	s.face_layer = d.get("face_layer", true)
	s.shoulder_up = float(d.get("shoulder_up", 1.0))
	s.waist = float(d.get("waist", 0.5))
	s.front_reach = float(d.get("front_reach", 70.0))
	s.skin_tol = float(d.get("skin_tol", 0.3))
	s.face_min = float(d.get("face_min", 0.55))
	if d.has("pmap"):
		var pm := Marshalls.base64_to_raw(d.pmap)
		if pm.size() == s.w * s.h:
			s.pmap = pm
			s.pmap_user = true
	s.air_thick = float(d.get("air_thick", 1.0))
	s.paint_reach = float(d.get("paint_reach", 20.0))
	for e in d.get("adds", []):
		s.adds.append([int(e[0]), Vector3(e[1], e[2], e[3]), Vector3(e[4], e[5], e[6]), float(e[7]), Color(str(e[8]))])
	for e in d.get("spaint", []):
		s.spaint[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = [Color(str(e[3])), float(e[4]) if e.size() > 4 else NAN]
	return s if s.pics.has(0) else null
