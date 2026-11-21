## 確かめ用: 肩 (腕のつけ根) の高さ。保存したキャラの腕を 横へ 30°・60°・90°・120° 上げて、shoulder_up = 0 (前の版) と いまの値で並べる。赤い点 = つけ根
##   Godot --headless --path . -s tools/shoulder_shot.gd -- <キャラ.dotg.json> <出力.png>
extends SceneTree
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var Solid = load("res://scripts/solid.gd")
	var d = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var so = Solid.from_doc(d.solid).padded(8, 6, 0)      # 紙を広げる (はみ出して切れないように)
	var keep: float = so.shoulder_up
	var angs := [0.0, 25.0, 45.0, 70.0, 100.0]
	var big := Image.create_empty(so.w * angs.size(), so.h * 2, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	# 手の数: 腕のポーズ × 向きごとに、首より下の 肌の画素の かたまり (つながった島) を数える。見える手は 0〜2 のはず
	so.ensure()
	for a in [0.0, 30.0, 60.0]:
		so.pose = {4: Quaternion(Vector3.BACK, deg_to_rad(a)), 3: Quaternion(Vector3.BACK, deg_to_rad(-a))} if a > 0.0 else {}
		var line := ""
		for yv in [0.0, 45.0, 90.0, 135.0, 180.0, 270.0]:
			var im: Image = so.render(yv, true)
			var seen := {}
			var isl := 0
			for y in range(so.neck + 2, so.h):
				for x in so.w:
					var q := Vector2i(x, y)
					if seen.has(q) or im.get_pixel(x, y).a < 0.5 or not so._is_skin(im.get_pixel(x, y).to_rgba32()):
						continue
					isl += 1
					var st := [q]
					seen[q] = true
					while not st.is_empty():
						var c: Vector2i = st.pop_back()
						for dy in [-1, 0, 1]:
							for dx in [-1, 0, 1]:
								var n := c + Vector2i(dx, dy)
								if n.x >= 0 and n.x < so.w and n.y > so.neck + 1 and n.y < so.h and not seen.has(n) and im.get_pixel(n.x, n.y).a > 0.5 and so._is_skin(im.get_pixel(n.x, n.y).to_rgba32()):
									seen[n] = true
									st.append(n)
			line += "  %d°: %d" % [int(yv), isl]
		print("腕 %d°: 見える手の数 %s" % [int(a), line])
	# 上の段: 肩を上げる (左右とも 25°)・胸をひねる (横へ 15°)・胸を前へ 25°・腰 + 胸で おじぎ・肩を上げて腕を 70°。下の段: 同じものを横から
	var Z := func(deg: float) -> Quaternion: return Quaternion(Vector3.BACK, deg_to_rad(deg))
	var X := func(deg: float) -> Quaternion: return Quaternion(Vector3.RIGHT, -deg_to_rad(deg))
	var poses := [
		{Solid.SHOULDER_B: Z.call(25.0), Solid.SHOULDER_A: Z.call(-25.0)},
		{Solid.CHEST: Z.call(15.0)},
		{Solid.CHEST: X.call(-25.0)},
		so.preset("おじぎ").pose,
		{Solid.SHOULDER_B: Z.call(25.0), Solid.SHOULDER_A: Z.call(-25.0), Solid.ARM_B: Z.call(70.0), Solid.ARM_A: Z.call(-70.0)},
	]
	print("部品: ", so._pivot.keys().map(func(k): return Solid.PART_NAMES[k]))
	for p in [Solid.CHEST, Solid.SHOULDER_A, Solid.SHOULDER_B, Solid.ARM_B]:
		if so._pivot.has(p):
			print("  %s: つけ根 %s・先 %s・親 %s" % [Solid.PART_NAMES[p], so._pivot[p], so._tip[p], Solid.PART_NAMES[so.parent_of(p)]])
	for r in 2:
		for k in poses.size():
			so.pose = poses[k]
			big.blend_rect(so.render(0.0 if r == 0 else 90.0, true), Rect2i(0, 0, so.w, so.h), Vector2i(k * so.w, r * so.h))
	big.resize(big.get_width() * 8, big.get_height() * 8, Image.INTERPOLATE_NEAREST)
	big.save_png(args[1])
	quit()
