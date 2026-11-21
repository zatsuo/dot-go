## 確かめ用: 手の出方。保存したキャラを 15° ずつ一周 (上 = 立ち、下 = 歩きのコマ) で描き、向きごとに 首より下の 肌の かたまり (手) の数と場所を出す
##   Godot --headless --path . -s tools/hand_shot.gd -- <キャラ.dotg.json> <出力.png>
extends SceneTree

func hands(so, im: Image) -> Array:
	var seen := {}
	var out := []
	for y in range(so.neck + 2, so.h):
		for x in so.w:
			var q := Vector2i(x, y)
			if seen.has(q) or im.get_pixel(x, y).a < 0.5 or not so._is_skin(im.get_pixel(x, y).to_rgba32()):
				continue
			var st := [q]
			seen[q] = true
			var n := 0
			while not st.is_empty():
				var c: Vector2i = st.pop_back()
				n += 1
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var nn := c + Vector2i(dx, dy)
						if nn.x >= 0 and nn.x < so.w and nn.y > so.neck + 1 and nn.y < so.h and not seen.has(nn) and im.get_pixel(nn.x, nn.y).a > 0.5 and so._is_skin(im.get_pixel(nn.x, nn.y).to_rgba32()):
							seen[nn] = true
							st.append(nn)
			out.append("(%d,%d)×%d" % [x, y, n])
	return out

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var Solid = load("res://scripts/solid.gd")
	var d = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var so = Solid.from_doc(d.solid)
	so.ensure()
	var N := 24
	var cyc: Array = so.walk_cycle()
	var big := Image.create_empty(so.w * N, so.h * 2, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	for r in 2:
		for k in N:
			so.pose = {} if r == 0 else cyc[k % 4].pose
			so.root = Vector3.ZERO if r == 0 else cyc[k % 4].root
			var im: Image = so.render(k * 360.0 / N)
			big.blend_rect(im, Rect2i(0, 0, so.w, so.h), Vector2i(k * so.w, r * so.h))
			if k <= 12:
				print("%s %3d°: 手 %s" % ["立ち" if r == 0 else "歩き", k * 15, str(hands(so, im))])
	big.resize(big.get_width() * 4, big.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png(args[1])
	quit()
