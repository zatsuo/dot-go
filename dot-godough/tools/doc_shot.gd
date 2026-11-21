## 確かめ用: 保存したキャラ (.dotg.json) の立体を読んで、8 方向と 15° ずつの一周を描く (画面なしで動く)
##   Godot --headless --path . -s tools/doc_shot.gd -- <キャラ.dotg.json> <出力.png>
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var Solid = load("res://scripts/solid.gd")
	var d = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var so = Solid.from_doc(d.solid)
	so.ensure()
	var W: int = so.w
	var H: int = so.h
	print("紙 %d × %d・絵 %s・ふち %s・首 %d・ずれ %s" % [W, H, str(so.pics.keys()), so._rim, so.neck, str(so._src.map(func(s): return [s.yaw, s.get("dx", 0)]))])
	for p in so._prows:
		var ks: Array = so._prows[p].keys()
		ks.sort()
		print("  %s: 行 %d〜%d・つけ根 %s・最初の行 %s" % [Solid.PART_NAMES[p], ks[0], ks[-1], so._pivot[p], str(so._prows[p][ks[0]])])
	# 頭のまわり: 45°〜90° を 7.5° ずつ。上 = 正面の顔を 45° まで (前の版)、下 = front_reach まで
	var strip := Image.create_empty(W * 7, H * 2, false, Image.FORMAT_RGBA8)
	strip.fill(Color("#8a8f9a"))
	var keep_reach: float = so.front_reach
	for rr in 2:
		so.front_reach = 45.0 if rr == 0 else keep_reach
		for k in 7:
			strip.blend_rect(so.render(45.0 + k * 7.5), Rect2i(0, 0, W, H), Vector2i(k * W, rr * H))
	so.front_reach = keep_reach
	strip.resize(strip.get_width() * 6, strip.get_height() * 6, Image.INTERPOLATE_NEAREST)
	strip.save_png(args[1].get_basename() + "_45_90.png")
	var N := 24
	var big := Image.create_empty(W * N, H, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	for k in N:
		var r: Image = so.render(k * 360.0 / N)
		big.blend_rect(r, Rect2i(0, 0, W, H), Vector2i(k * W, 0))
		var n := 0
		var x0 := W
		var x1 := -1
		for y in H:
			for x in W:
				if r.get_pixel(x, y).a > 0.5:
					n += 1
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
		print("%d°: %d 画素 (x %d〜%d)" % [k * 15, n, x0, x1])
	big.resize(big.get_width() * 4, big.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png(args[1])
	quit()
