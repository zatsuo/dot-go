## 確かめ用: お手本の表のキャラを、正面の絵 1 枚から立体にして 8 方向で描く (画面なしで動く)。
##  1 段目 = 青髪 (立ち): 正面だけから推定 / 2 段目 = 表にある横向き・後ろ向きの絵も使う / 3・4 段目 = ほかの 2 体 (推定だけ)
##  表に本物の横・後ろの絵がある青髪で、推定がどれだけ当たっているかを数える
##   Godot --headless --path . -s tools/solid_shot.gd -- <出力.png>
extends SceneTree

const W := 28
const H := 42


func cell(sheet: Image, r: Rect2i) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 2 - r.size.y))
	return im


## a と b の同じ画素の割合 (どちらかに何かある画素のうち)。b を左右に ±3 ずらして、いちばん合う所で数える
func match_of(a: Image, b: Image) -> float:
	var best := 0.0
	for dx in range(-3, 4):
		var same := 0
		var total := 0
		for y in H:
			for x in W:
				var pa := a.get_pixel(x, y)
				var xb := x - dx
				var pb := b.get_pixel(xb, y) if xb >= 0 and xb < W else Color(0, 0, 0, 0)
				if pa.a < 0.5 and pb.a < 0.5:
					continue
				total += 1
				if pa.a > 0.5 and pb.a > 0.5 and pa.to_rgba32() == pb.to_rgba32():
					same += 1
		best = maxf(best, float(same) / maxi(total, 1))
	return best


func _init() -> void:
	var out := "user://solid.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var Solid = load("res://scripts/solid.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var front := cell(sheet, Rect2i(4, 128, 18, 32))
	var right := cell(sheet, Rect2i(34, 128, 15, 32))
	var left := cell(sheet, Rect2i(60, 128, 15, 32))
	var back := cell(sheet, Rect2i(86, 128, 15, 32))
	var big := Image.create_empty(W * 8, H * 5, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))

	var so = Solid.new()
	so.set_front(front)
	print("推定だけ (正面 1 枚): 横の絵が本物と同じ %.0f%%・後ろ %.0f%%・正面 %.0f%%" % [
			match_of(so.render(90.0), right) * 100.0, match_of(so.render(180.0), back) * 100.0, match_of(so.render(0.0), front) * 100.0])
	for wv in [0.0, 0.5, 1.0]:
		so.wrap = wv
		so.touch()
		print("  顔を横へ回す %.1f: 横 %.0f%%" % [wv, match_of(so.render(90.0), right) * 100.0])
	so.wrap = 0.0
	for kh in [0.9, 1.0, 1.1]:
		for kb in [0.55, 0.65, 0.75]:
			so.k_head = kh
			so.k_body = kb
			so.touch()
			print("  頭 %.2f 体 %.2f: 横 %.0f%%" % [kh, kb, match_of(so.render(90.0), right) * 100.0])
	so = Solid.new()
	so.set_front(front)
	for d in 8:
		big.blend_rect(so.render(d * 45.0), Rect2i(0, 0, W, H), Vector2i(d * W, 0))
	so.wrap = 1.0
	so.touch()
	for d in 8:
		big.blend_rect(so.render(d * 45.0), Rect2i(0, 0, W, H), Vector2i(d * W, 4 * H))
	so.wrap = 0.0
	so.touch()
	# 表にある横向き・後ろ向きの絵を使う
	so.set_pic(90, right)
	so.set_pic(270, left)
	so.set_pic(180, back)
	for d in 8:
		big.blend_rect(so.render(d * 45.0), Rect2i(0, 0, W, H), Vector2i(d * W, H))
	print("横・後ろの絵も使う: 横 %.0f%%・後ろ %.0f%% (100 のはず)" % [match_of(so.render(90.0), right) * 100.0, match_of(so.render(180.0), back) * 100.0])
	var row := 2
	for r in [Rect2i(161, 64, 16, 32), Rect2i(203, 59, 21, 37)]:
		var s2 = Solid.new()
		s2.set_front(cell(sheet, r))
		for d in 8:
			big.blend_rect(s2.render(d * 45.0), Rect2i(0, 0, W, H), Vector2i(d * W, row * H))
		print("キャラ %d: 首の行 %d・線の色 %d 組・外のふち %s" % [row - 1, s2.neck, s2._line.size(), s2._rim.a > 0.5])
		row += 1
	big.resize(big.get_width() * 5, big.get_height() * 5, Image.INTERPOLATE_NEAREST)
	big.save_png(out)
	print("-> ", out)
	quit()
