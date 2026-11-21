## 確かめ用: 部品の自動推定を絵にする。お手本の 2 人について、正面の絵 → 部品の色分け (関節で分けたあと) を並べる (画面なしで動く)。
##   Godot --headless --path . -s tools/parts_shot.gd -- <出力.png>
extends SceneTree

const W := 26
const H := 38


func cell(sheet: Image, r: Rect2i) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 3 - r.size.y))
	return im


func _init() -> void:
	var out := "user://parts.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var Solid = load("res://scripts/solid.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var big := Image.create_empty(W * 4, H, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	var ci := 0
	for r in [Rect2i(4, 128, 18, 32), Rect2i(161, 64, 16, 32)]:
		var so = Solid.new()
		so.set_front(cell(sheet, r))
		so.ensure()
		big.blend_rect(so.pics[0], Rect2i(0, 0, W, H), Vector2i(ci * 2 * W, 0))
		for y in H:
			for x in W:
				var p: int = so._pm2[x + W * y]
				if p > 0 and so.pics[0].get_pixel(x, y).a > 0.5:
					big.set_pixel(ci * 2 * W + W + x, y, Color(Solid.PART_COLORS[p]))
		# 首の行と 脚の始まりの行に しるし
		print("キャラ %d: 首の行 %d・肌の色 %s・脚の範囲 %s" % [ci, so.neck, Color.hex(so._skin).to_html(), str(so._prange.get(Solid.SHIN_A, []))])
		ci += 1
	big.resize(big.get_width() * 6, big.get_height() * 6, Image.INTERPOLATE_NEAREST)
	big.save_png(out)
	quit()
