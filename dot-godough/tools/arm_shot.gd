## 確かめ用: 腕を体から はなしたときの絵 (細くなる・ちぎれる を見る)。画面なしで動く
##  行 = 腕のポーズ、列 = 向き (0・45・90・180・270・315)。上半分 = 青髪 (横・後ろの絵つき)、下半分 = 茶色 (正面だけ)
##   Godot --headless --path . -s tools/arm_shot.gd -- <出力.png>
extends SceneTree

const W := 34
const H := 44
const YAWS := [0.0, 45.0, 90.0, 180.0, 270.0, 315.0]


func cell(sheet: Image, r: Rect2i) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 4 - r.size.y))
	return im


## 腕の画素を数える: [画素の数, 島の数 (つながっていない かたまり), 線でない画素の数]
func arm_stat(so, img: Image, parts: Array) -> Array:
	var n := 0
	var fill := 0
	var seen := {}
	var isl := 0
	var mine := {}
	for y in H:
		for x in W:
			if so.hit_part(x, y) in parts:
				mine[Vector2i(x, y)] = true
				n += 1
				if not so.is_line_color(img.get_pixel(x, y)):
					fill += 1
	for p in mine:
		if seen.has(p):
			continue
		isl += 1
		var st := [p]
		seen[p] = true
		while not st.is_empty():
			var q: Vector2i = st.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var r: Vector2i = q + d
				if mine.has(r) and not seen.has(r):
					seen[r] = true
					st.append(r)
	return [n, isl, fill]


func _init() -> void:
	var out := "user://arm.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var Solid = load("res://scripts/solid.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var fwd := func(deg: float) -> Quaternion: return Quaternion(Vector3.RIGHT, -deg_to_rad(deg))
	var side := func(deg: float) -> Quaternion: return Quaternion(Vector3.BACK, deg_to_rad(deg))
	var A: int = Solid.ARM_A
	var B: int = Solid.ARM_B
	var FA: int = Solid.FORE_A
	var FB: int = Solid.FORE_B
	var poses := [
		["立ち", {}],
		["横へ 20", {B: side.call(20.0), A: side.call(-20.0)}],
		["横へ 45", {B: side.call(45.0), A: side.call(-45.0)}],
		["横へ 90", {B: side.call(90.0), A: side.call(-90.0)}],
		["上へ 150", {B: side.call(150.0), A: side.call(-150.0)}],
		["前へ 45", {B: fwd.call(45.0), A: fwd.call(45.0)}],
		["前へ 90", {B: fwd.call(90.0), A: fwd.call(90.0)}],
		["横 45 + ひじ 90", {B: side.call(45.0), A: side.call(-45.0), FB: fwd.call(90.0), FA: fwd.call(90.0)}],
		["横 60 + ひじ横 60", {B: side.call(60.0), A: side.call(-60.0), FB: side.call(60.0), FA: side.call(-60.0)}],
	]
	var big := Image.create_empty(W * YAWS.size(), H * poses.size() * 2, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	for ci in 2:
		var so = Solid.new()
		if ci == 0:
			so.set_front(cell(sheet, Rect2i(4, 128, 18, 32)))
			so.set_pic(90, cell(sheet, Rect2i(34, 128, 15, 32)))
			so.set_pic(270, cell(sheet, Rect2i(60, 128, 15, 32)))
			so.set_pic(180, cell(sheet, Rect2i(86, 128, 15, 32)))
		else:
			so.set_front(cell(sheet, Rect2i(161, 64, 16, 32)))
		so.ensure()
		for p in [A, B, FA, FB]:
			if so._prows.has(p):
				var ks: Array = so._prows[p].keys()
				ks.sort()
				var s := ""
				for y in ks:
					s += " %d:%s" % [y, str(so._prows[p][y])]
				print("キャラ %d %s:%s" % [ci, Solid.PART_NAMES[p], s])
		for sr in so._src:
			print("キャラ %d 絵 %d° と立体の横のずれ: %d 画素" % [ci, int(sr.yaw), int(sr.get("dx", 0))])
		for yv in [90.0, 180.0, 270.0]:
			so.pose = {}
			var rest: Image = so.render(yv)
			so.pose = {B: side.call(90.0), A: side.call(-90.0)}
			var posed: Image = so.render(yv)
			var same := 0
			var tot := 0
			var skin_left := 0
			for y in H:
				for x in W:
					var pp: int = so.hit_part(x, y)
					if pp in [Solid.HEAD, Solid.BODY, Solid.LEG_A, Solid.LEG_B, Solid.SHIN_A, Solid.SHIN_B]:
						tot += 1
						if rest.get_pixel(x, y).is_equal_approx(posed.get_pixel(x, y)):
							same += 1
						elif y > so.neck + 1 and posed.get_pixel(x, y).to_rgba32() == so._skin:
							skin_left += 1
			print("キャラ %d %d°: 腕を横へ 90° 上げても、頭・体・脚の画素は 立ちの絵と同じ %d / %d。体に残った肌の色 %d" % [ci, int(yv), same, tot, skin_left])
		for pi in poses.size():
			so.pose = poses[pi][1]
			so.root = Vector3.ZERO
			var line := ""
			for di in YAWS.size():
				var im: Image = so.render(YAWS[di])
				big.blend_rect(im, Rect2i(0, 0, W, H), Vector2i(di * W, (ci * poses.size() + pi) * H))
				if so.has_method("hit_part"):
					var sa := arm_stat(so, im, [A, FA])
					var sb := arm_stat(so, im, [B, FB])
					line += "  %d°: 左 %d 画素・島 %d・塗り %d / 右 %d・島 %d・塗り %d" % [int(YAWS[di]), sa[0], sa[1], sa[2], sb[0], sb[1], sb[2]]
			print("キャラ %d「%s」%s" % [ci, poses[pi][0], line])
	big.resize(big.get_width() * 6, big.get_height() * 6, Image.INTERPOLATE_NEAREST)
	big.save_png(out)
	print("-> ", out)
	quit()
