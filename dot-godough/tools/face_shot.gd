## 確かめ用: 顔の層 (肌・目・口を だ円の面から切りはなす)。正面 1 枚だけから作った立体を 15° ずつ回して、
##  上の段 = 顔の層なし、下の段 = 顔の層あり で並べる。お手本に 本物の横向きがあるキャラは、横向きの絵が どれだけ合うかも数える (画面なしで動く)。
##   Godot --headless --path . -s tools/face_shot.gd -- <出力.png> [キャラ.dotg.json]
extends SceneTree

const W := 26
const H := 40
const N := 13                    # 0°〜180° を 15° ずつ


func cell(sheet: Image, r: Rect2i) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 4 - r.size.y))
	return im


func same(a: Image, b: Image) -> Array:
	var best := 0
	var tot := 0
	for dx in [-2, -1, 0, 1, 2]:
		var n := 0
		var t := 0
		for y in a.get_height():
			for x in a.get_width():
				var xs: int = x + dx
				var pa := a.get_pixel(x, y)
				var pb := b.get_pixel(xs, y) if xs >= 0 and xs < b.get_width() else Color(0, 0, 0, 0)
				if pa.a > 0.5 or pb.a > 0.5:
					t += 1
					if pa.a > 0.5 and pb.a > 0.5 and pa.is_equal_approx(pb):
						n += 1
		if n > best:
			best = n
			tot = t
	return [best, tot]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var Solid = load("res://scripts/solid.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var chars := []                  # [名前, 立体, 本物の横向き (無ければ null)]
	var a = Solid.new()
	a.set_front(cell(sheet, Rect2i(4, 128, 18, 32)))
	chars.append(["青髪", a, cell(sheet, Rect2i(34, 128, 15, 32))])
	var b = Solid.new()
	b.set_front(cell(sheet, Rect2i(161, 64, 16, 32)))
	chars.append(["茶色", b, null])
	var c = Solid.new()
	c.set_front(cell(sheet, Rect2i(203, 59, 21, 37)))
	chars.append(["白衣", c, null])
	# 肌の色を塗りかえたキャラ (濃い肌・3 色の濃淡): 色を決め打ちしていないことの確かめ
	var fr: Image = cell(sheet, Rect2i(161, 64, 16, 32))
	for y in H:
		for x in W:
			var px := fr.get_pixel(x, y)
			if px.is_equal_approx(Color("#fce1c7")):
				fr.set_pixel(x, y, Color("#8d5a3c") if (x + y) % 5 != 0 else Color("#9a6646"))
			elif px.is_equal_approx(Color("#eec39a")):
				fr.set_pixel(x, y, Color("#6e4028"))
	var e = Solid.new()
	e.set_front(fr)
	chars.append(["肌の色を変えた", e, null])
	if args.size() > 1:
		var d = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		var u = Solid.from_doc(d.solid)
		if u != null:
			u.forget(90)
			u.forget(270)
			chars.append(["保存したキャラ", u, null])
	var cw := 0
	var chh := 0
	for ch in chars:
		cw = maxi(cw, ch[1].w)
		chh = maxi(chh, ch[1].h)
	var big := Image.create_empty(cw * N, chh * chars.size() * 2, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	var row := 0
	for ch in chars:
		var so = ch[1]
		so.ensure()
		var skins := []
		for k in so._skins:
			skins.append(Color.hex(k).to_html(false))
		var blobs := []
		for bl in so._fblobs:
			blobs.append("%d 画素 (x %d〜%d)" % [bl.pix.size(), bl.x0, bl.x1])
		print("%s: 顔 %s・肌の色 %s・目や口 %s・顔の幅の半分 %.1f・頭の奥行き %.1f" % [ch[0], so._face_ok, str(skins), str(blobs), so._fhw, so._hrz])
		for on in [false, true]:
			so.face_layer = on
			for k in N:
				var im: Image = so.render(k * 15.0)
				big.blend_rect(im, Rect2i(0, 0, so.w, so.h), Vector2i(k * cw, row * chh))
				if k == 6 and ch[2] != null:
					var sm := same(im, ch[2])
					print("  顔の層 %s: 横向き (90°) が 本物と同じ画素 %d / %d (%d%%)" % ["あり" if on else "なし", sm[0], sm[1], sm[0] * 100 / maxi(sm[1], 1)])
			row += 1
	big.resize(big.get_width() * 4, big.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png(args[0])
	quit()
