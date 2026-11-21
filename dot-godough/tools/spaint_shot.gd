## 確かめ用: 立体の面に塗る。正面 1 枚だけのキャラの 60° の絵に 髪かざり (黄) と そでの線 (白) を描き、0°〜180° を 15° ずつ並べる
##  上 = 塗る前、下 = 塗ったあと (60° で 1 回描いただけ)。画面なしで動く
##   Godot --headless --path . -s tools/spaint_shot.gd -- <出力.png>
extends SceneTree

const W := 26
const H := 40


func _init() -> void:
	var Solid = load("res://scripts/solid.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var r := Rect2i(161, 64, 16, 32)
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 4 - r.size.y))
	var so = Solid.new()
	so.set_front(im)
	so.ensure()
	var big := Image.create_empty(W * 13, H * 2, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	for row in 2:
		if row == 1:
			var n := 0
			for p in [[14, so.neck - 9], [15, so.neck - 9], [14, so.neck - 8], [15, so.neck - 8], [16, so.neck - 8], [15, so.neck - 7]]:
				if so.paint_surface(60.0, p[0], p[1], Color("#ffd24a")):
					n += 1
			for x in range(8, 18):
				if so.paint_surface(60.0, x, so.neck + 8, Color("#f4f4f4")):
					n += 1
			print("60° で塗れた画素: %d・面の ます: %d" % [n, so.spaint.size()])
		for k in 13:
			big.blend_rect(so.render(k * 15.0), Rect2i(0, 0, W, H), Vector2i(k * W, row * H))
	big.resize(big.get_width() * 4, big.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png(OS.get_cmdline_user_args()[0])
	quit()
