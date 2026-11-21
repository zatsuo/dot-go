## 確かめ用: 手の画素・はなれ小島を、ポーズ × 向き で数える
##   Godot --headless --path . -s tools/hand_check.gd -- check <きざみ(度)> <モデル>...
##   Godot --headless --path . -s tools/hand_check.gd -- shot <出力.png> <モデル> <ポーズ名> <向き,向き,...>
## モデル: .dotg.json / .dotmodel.json、または 絵 "png:<パス>[:x,y,w,h[:横 x,y,w,h[:後ろ x,y,w,h]]]"
## 数えるもの:
##   残り = 首より下の 肌の色の画素で、腕の部品でないもの (腕を動かしたのに 体に残った手)
##   小島 = いちばん大きい かたまりに つながっていない画素
##   手 = 腕 1 本の 肌の かたまりが 2 つ以上 (手が増えた)
extends SceneTree

const POSES := ["立ち", "歩き 1", "歩き 2", "走り", "ばんざい", "T の字", "すわる", "ゆかにすわる", "おじぎ", "手をあげる"]
var Solid
var extra := {}                  # 手の色として数える色を足す (古い solid.gd と比べるとき): 環境変数 HAND_EXTRA=eacbae,...


func is_hand(so, k: int) -> bool:
	return so._is_skin(k) or extra.has(k) or (("_hand_cols" in so) and so._hand_cols.has(k))


func rect_of(s: String) -> Rect2i:
	var a := s.split(",")
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


func cut(sheet: Image, r: Rect2i, w: int, h: int) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	var rr := Rect2i(r.position + used.position, used.size)
	if w <= 0:
		w = rr.size.x + 8
		if w % 2 == 1:
			w += 1
		h = rr.size.y + 5
	var im := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, rr, Vector2i((w - rr.size.x) / 2, h - 2 - rr.size.y))
	return im


func load_model(spec: String):
	if spec.begins_with("png:"):
		var parts := spec.substr(4).split("|")
		var img := Image.load_from_file(parts[0])
		img.convert(Image.FORMAT_RGBA8)
		var bg := img.get_pixel(0, 0)
		if bg.a > 0.5:
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y) == bg:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
		var so = Solid.new()
		var r0 := rect_of(parts[1]) if parts.size() > 1 else Rect2i(Vector2i.ZERO, img.get_size())
		so.set_front(cut(img, r0, 0, 0))
		so.ensure()
		if parts.size() > 2:
			so.set_pic(90, cut(img, rect_of(parts[2]), so.w, so.h))
		if parts.size() > 3:
			so.set_pic(180, cut(img, rect_of(parts[3]), so.w, so.h))
		so.ensure()
		return so
	var d = JSON.parse_string(FileAccess.get_file_as_string(spec))
	var so2 = Solid.from_doc(d.solid)
	so2.ensure()
	return so2


func pose_list(so) -> Array:
	var out := []
	for nm in POSES:
		var p: Dictionary = {"pose": {}, "root": Vector3.ZERO} if nm == "立ち" else so.preset(nm)
		out.append([nm, p.pose, p.root])
	var cyc: Array = so.walk_cycle()
	for k in cyc.size():
		out.append(["歩きのコマ %d" % k, cyc[k].pose, cyc[k].root])
	# あいだのポーズ (モーションのアプリは コマのあいだを こうやって つなぐ)
	var base := out.duplicate()
	for pr in [[0, 1], [0, 3], [0, 4], [0, 5], [0, 9], [1, 2], [10, 11], [11, 12], [12, 13], [13, 10]]:
		for t in [0.33, 0.66]:
			var a: Dictionary = base[pr[0]][1]
			var b: Dictionary = base[pr[1]][1]
			var mix := {}
			for k in a.keys() + b.keys():
				mix[k] = Quaternion(a.get(k, Quaternion())).slerp(Quaternion(b.get(k, Quaternion())), t)
			out.append(["%s→%s %.2f" % [base[pr[0]][0], base[pr[1]][0], t], mix, Vector3(base[pr[0]][2]).lerp(Vector3(base[pr[1]][2]), t)])
	return out


func comps(w: int, h: int, ok: Callable) -> Array:
	var seen := {}
	var out := []
	for y in h:
		for x in w:
			var q := Vector2i(x, y)
			if seen.has(q) or not ok.call(x, y):
				continue
			var st := [q]
			seen[q] = true
			var cells := []
			while not st.is_empty():
				var c: Vector2i = st.pop_back()
				cells.append(c)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var nn := c + Vector2i(dx, dy)
						if nn.x >= 0 and nn.x < w and nn.y >= 0 and nn.y < h and not seen.has(nn) and ok.call(nn.x, nn.y):
							seen[nn] = true
							st.append(nn)
			out.append(cells)
	return out


func check_one(so, im: Image) -> Dictionary:
	var hp: PackedByteArray = so._last_hp
	var w: int = so.w
	var h: int = so.h
	var left := []
	for y in range(so.neck + 2, h):
		for x in w:
			var c := im.get_pixel(x, y)
			if c.a > 0.5 and is_hand(so, c.to_rgba32()) and not (hp[x + w * y] in [1, 3, 4, 7, 8]):
				left.append("(%d,%d %s)" % [x, y, Solid.PART_NAMES[hp[x + w * y]]])
	var isl := comps(w, h, func(x, y): return im.get_pixel(x, y).a > 0.5)
	isl.sort_custom(func(a, b): return a.size() > b.size())
	var islands := []
	for k in range(1, isl.size()):
		islands.append("(%d,%d)×%d" % [isl[k][0].x, isl[k][0].y, isl[k].size()])
	var hands := []
	for arm in [[3, 7], [4, 8]]:
		var cs := comps(w, h, func(x, y): return im.get_pixel(x, y).a > 0.5 and hp[x + w * y] in arm and is_hand(so, im.get_pixel(x, y).to_rgba32()))
		if cs.size() >= 2:
			hands.append("%s: %d 個" % [Solid.PART_NAMES[arm[0]], cs.size()])
	return {"left": left, "islands": islands, "hands": hands}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	Solid = load(OS.get_environment("SOLID_GD") if OS.get_environment("SOLID_GD") != "" else "res://scripts/solid.gd")
	for e in OS.get_environment("HAND_EXTRA").split(",", false):
		extra[Color(e).to_rgba32()] = true
	if args[0] == "shot":
		var so = load_model(args[2])
		var yaws := args[4].split(",")
		var big := Image.create_empty(so.w * yaws.size(), so.h, false, Image.FORMAT_RGBA8)
		big.fill(Color("#8a8f9a"))
		for pl in pose_list(so):
			if pl[0] != args[3]:
				continue
			so.pose = pl[1]
			so.root = pl[2]
			for k in yaws.size():
				var im: Image = so.render(float(yaws[k]))
				big.blend_rect(im, Rect2i(0, 0, so.w, so.h), Vector2i(k * so.w, 0))
		var z := 12
		big.resize(big.get_width() * z, big.get_height() * z, Image.INTERPOLATE_NEAREST)
		big.save_png(args[1])
		quit()
		return
	if args[0] == "pic":
		# pic <モデル>: 正面の絵を 文字で出す (関節で分けたあとの部品の番号 + 肌 S / 線 l / ほか #)。右に 線を抜いた絵
		var so4 = load_model(args[1])
		var raw: Image = so4.pics[0]
		var fl: Image = so4._fill0
		for y in range(so4.neck - 1, so4.h):
			var l1 := ""
			var l2 := ""
			for x in so4.w:
				for which in 2:
					var im4: Image = raw if which == 0 else fl
					var c4 := im4.get_pixel(x, y)
					var t4 := " ."
					if c4.a > 0.5:
						var k4 := c4.to_rgba32()
						t4 = "%x%s" % [so4._pm2[x + so4.w * y], "S" if is_hand(so4, k4) else ("l" if so4._line_cols.has(k4) else "#")]
					if which == 0:
						l1 += t4
					else:
						l2 += t4
			print("%2d %s   |%s" % [y, l1, l2])
		for p in [3, 4, 7, 8]:
			if so4._prows.has(p):
				var rws: Array = so4._prows[p].keys()
				rws.sort()
				var txt := ""
				for r4 in rws:
					txt += " %d:%s" % [r4, str(so4._prows[p][r4][0])]
				print("%s つけ根 %s 先 %s 行%s" % [Solid.PART_NAMES[p], str(so4._pivot[p]), str(so4._tip.get(p, "")), txt])
		quit()
		return
	if args[0] == "dump":
		# dump <モデル> <ポーズ名> <向き,向き,...>: 首から下を 文字で出す (部品の番号 + 肌 S / 線 l / ほか #)
		var so3 = load_model(args[1])
		for pl in pose_list(so3):
			if pl[0] != args[2]:
				continue
			so3.pose = pl[1]
			so3.root = pl[2]
			for ys in args[3].split(","):
				var im3: Image = so3.render(float(ys), true)
				var hp3: PackedByteArray = so3._last_hp
				print("-- %s %s°" % [pl[0], ys])
				for y in range(so3.neck - 1, so3.h):
					var line := ""
					for x in so3.w:
						var c3 := im3.get_pixel(x, y)
						if c3.a < 0.5:
							line += " ."
						else:
							var k3 := c3.to_rgba32()
							line += "%x%s" % [hp3[x + so3.w * y], "S" if is_hand(so3, k3) else ("l" if so3._line_cols.has(k3) else "#")]
					print("%2d %s" % [y, line])
		quit()
		return
	var step := float(args[1])
	for mi in range(2, args.size()):
		var so = load_model(args[mi])
		print("== %s (紙 %d × %d、首 %d、決めた絵 %s)" % [args[mi].get_file(), so.w, so.h, so.neck, str(so.pics.keys())])
		var tot := {"left": 0, "islands": 0, "hands": 0}
		var n := 0
		for pl in pose_list(so):
			so.pose = pl[1]
			so.root = pl[2]
			var yaw := 0.0
			while yaw < 359.9:
				var key: int = Solid.key_of(yaw)
				if not (pl[1].is_empty() and key >= 0 and (so.pics.has(key) or so.pics.has((360 - key) % 360))):
					var im: Image = so.render(yaw)
					var r := check_one(so, im)
					n += 1
					for k in tot:
						if not r[k].is_empty():
							tot[k] += 1
					if not (r.left.is_empty() and r.islands.is_empty() and r.hands.is_empty()):
						print("  %s %5.1f°: %s%s%s" % [pl[0], yaw,
								("残り " + " ".join(r.left) + "  ") if not r.left.is_empty() else "",
								("小島 " + " ".join(r.islands) + "  ") if not r.islands.is_empty() else "",
								("手 " + " ".join(r.hands)) if not r.hands.is_empty() else ""])
				yaw += step
		print("  計 %d 枚: 残り %d・小島 %d・手が 2 つ以上 %d" % [n, tot.left, tot.islands, tot.hands])
	quit()
