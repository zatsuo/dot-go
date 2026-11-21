## 確かめ用: ぐるっと一周 (8 方向より細かい向き)。お手本の 2 人を 24 コマ (15° ずつ) で回して GIF に書き出す (画面なしで動く)。
##   Godot --headless --path . -s tools/turn_gif.gd -- <出力のフォルダ>
## 出るもの: turn.gif (立ち・2 人)、turn_walk.gif (歩きながら回る)、turn.png (15° ずつの表: 上 = 青髪 (横・後ろの絵つき)、下 = 茶色 (正面だけ))
extends SceneTree

const W := 32
const H := 40
const N := 24


func cell(sheet: Image, r: Rect2i) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 4 - r.size.y))
	return im


func _init() -> void:
	var dir := "user://"
	for a in OS.get_cmdline_user_args():
		dir = a
	var Solid = load("res://scripts/solid.gd")
	var Anim = load("res://scripts/anim_export.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var sos := []
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
		sos.append(so)
	var big := Image.create_empty(W * N, H * 2, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	var stand := []
	var walk := []
	var cycle: Array = sos[0].walk_cycle()
	for k in N:
		var yaw := k * 360.0 / N
		var a := Image.create_empty(W * 2, H, false, Image.FORMAT_RGBA8)
		var b := Image.create_empty(W * 2, H, false, Image.FORMAT_RGBA8)
		for ci in 2:
			var so = sos[ci]
			so.pose = {}
			so.root = Vector3.ZERO
			var im: Image = so.render(yaw)
			a.blit_rect(im, Rect2i(0, 0, W, H), Vector2i(ci * W, 0))
			big.blend_rect(im, Rect2i(0, 0, W, H), Vector2i(k * W, ci * H))
			var c: Dictionary = so.walk_cycle()[k % 4]
			so.pose = c.pose
			so.root = c.root
			b.blit_rect(so.render(yaw), Rect2i(0, 0, W, H), Vector2i(ci * W, 0))
		stand.append(a)
		walk.append(b)
	# となりのコマと ちがう画素の数 (向きの切りかわりで とぶ所を見る)
	for ci in 2:
		var s := ""
		for k in N:
			var p: Image = stand[k].get_region(Rect2i(ci * W, 0, W, H))
			var q: Image = stand[(k + 1) % N].get_region(Rect2i(ci * W, 0, W, H))
			var n := 0
			for y in H:
				for x in W:
					if not p.get_pixel(x, y).is_equal_approx(q.get_pixel(x, y)):
						n += 1
			s += " %d→%d:%d" % [k * 360 / N, ((k + 1) % N) * 360 / N, n]
		print("キャラ %d となりのコマとの ちがい (画素):%s" % [ci, s])
	print("gif (立ち): ", Anim.save_gif(stand, dir.path_join("turn.gif"), 8, 6))
	print("gif (歩き): ", Anim.save_gif(walk, dir.path_join("turn_walk.gif"), 12, 6))
	big.resize(big.get_width() * 3, big.get_height() * 3, Image.INTERPOLATE_NEAREST)
	big.save_png(dir.path_join("turn.png"))
	quit()
