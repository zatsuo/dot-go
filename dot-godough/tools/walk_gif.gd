## 確かめ用: お手本の青髪のキャラを立体にして、歩きの 4 コマを 8 方向で描き、GIF と Aseprite のファイルに書き出す (画面なしで動く)。
##   Godot --headless --path . -s tools/walk_gif.gd -- <出力のフォルダ>
## 出るもの: walk.gif (8 方向を 4 × 2 に並べた歩き)、walk_side.gif (横向きだけ)、walk.aseprite (8 方向・向きごとのタグ)、back.png (後ろ 3 方向)
extends SceneTree

const W := 32
const H := 40


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
	var so = Solid.new()
	so.set_front(cell(sheet, Rect2i(4, 128, 18, 32)))
	so.set_pic(90, cell(sheet, Rect2i(34, 128, 15, 32)))
	so.set_pic(270, cell(sheet, Rect2i(60, 128, 15, 32)))
	so.set_pic(180, cell(sheet, Rect2i(86, 128, 15, 32)))
	var cycle: Array = so.walk_cycle()
	var names := ["正面", "左ななめ前", "左", "左ななめ後ろ", "後ろ", "右ななめ後ろ", "右", "右ななめ前"]
	var all := []                    # 向きごとに 4 コマ
	var tags := []
	var flat := []
	for d in 8:
		var fr := []
		for c in cycle:
			so.pose = c.pose
			so.root = c.root
			fr.append(so.render(d * 45.0))
		all.append(fr)
		tags.append({"name": names[d], "from": flat.size(), "to": flat.size() + fr.size() - 1})
		flat.append_array(fr)
	var grid := []
	for k in cycle.size():
		var im := Image.create_empty(W * 4, H * 2, false, Image.FORMAT_RGBA8)
		for d in 8:
			im.blit_rect(all[d][k], Rect2i(0, 0, W, H), Vector2i((d % 4) * W, (d / 4) * H))
		grid.append(im)
	print("gif (8 方向): ", Anim.save_gif(grid, dir.path_join("walk.gif"), 16, 4))
	print("gif (横): ", Anim.save_gif(all[2], dir.path_join("walk_side.gif"), 16, 6))
	print("aseprite: ", Anim.save_ase(flat, dir.path_join("walk.aseprite"), 160, tags))
	# すわる・後ろ向きの線の確かめ
	var sheet2 := Image.create_empty(W * 8, H * 2, false, Image.FORMAT_RGBA8)
	sheet2.fill(Color("#8a8f9a"))
	var row := 0
	for nm in ["すわる", "ゆかにすわる"]:
		var pr: Dictionary = so.preset(nm)
		so.pose = pr.pose
		so.root = pr.root
		for d in 8:
			sheet2.blend_rect(so.render(d * 45.0), Rect2i(0, 0, W, H), Vector2i(d * W, row * H))
		row += 1
	sheet2.resize(sheet2.get_width() * 5, sheet2.get_height() * 5, Image.INTERPOLATE_NEAREST)
	sheet2.save_png(dir.path_join("sit.png"))
	# 正面 1 枚だけのキャラの後ろ向き: ふちの画素のうち、線の色でない画素を数える
	var s2 = Solid.new()
	s2.set_front(cell(sheet, Rect2i(161, 64, 16, 32)))
	for yaw in [135.0, 180.0, 225.0]:
		var im: Image = s2.render(yaw)
		var edge := 0
		var bare := 0
		for y in H:
			for x in W:
				if im.get_pixel(x, y).a < 0.5:
					continue
				var on_edge := false
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + dd
					if q.x < 0 or q.y < 0 or q.x >= W or q.y >= H or im.get_pixel(q.x, q.y).a < 0.5:
						on_edge = true
				if on_edge:
					edge += 1
					if not s2._line_cols.has(im.get_pixel(x, y).to_rgba32()):
						bare += 1
		print("後ろ %d°: ふちの画素 %d のうち、線の色でない %d" % [int(yaw), edge, bare])
	var mesh: ArrayMesh = so.make_mesh(0.05)
	print("3D の網目: 面 %d・頂点 %d" % [mesh.get_surface_count(), mesh.surface_get_array_len(0) if mesh.get_surface_count() > 0 else 0])
	quit()
