## 確かめ用: 塗りが体についてくるか。正面で 目 (そのままの色) と 胸の線 (影つき) を塗って、
## 向き・ポーズ・頭身を変えた絵を並べる (画面なしで動く)。
##   Godot --headless --path . -s tools/paint_shot.gd -- <出力.png> [px=56] [zoom=4]
extends SceneTree


func _init() -> void:
	var out := "user://paint.png"
	var px := 56
	var zoom := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("px="):
			px = int(a.substr(3))
		elif a.begins_with("zoom="):
			zoom = int(a.substr(5))
		else:
			out = a
	var core = load("res://core/DotCore.cs").new()
	var poses = load("res://scripts/poses.gd")
	var M = load("res://scripts/main.gd")
	var gs := []
	for w in ["長そでシャツ", "ズボン", "靴"]:
		M.wear(gs, M.clothes_named(w))
	var st: Dictionary = M.default_style()
	var cw := int(px * 1.5) + 4
	var ch := px + 6
	var eye := Color("#2a2030")
	var red := Color("#c8323c")

	var pose_of := func(name: String, heads: float) -> void:
		var rots: Dictionary = poses.to_quats(poses.named(name, 45.0, poses.hang_for(heads)))
		core.SetPose(rots, Vector3.ZERO)
		var fixed: Dictionary = core.FixArms(0.25)
		for k in fixed:
			rots[k] = fixed[k]
		core.SetPose(rots, Vector3.ZERO)
		core.SetPose(rots, Vector3(0, -core.LowestY(), 0))

	var draw := func(yaw: float) -> Image:
		core.SetView({"w": cw, "h": ch, "px": px, "yaw": yaw, "pitch": 0.0, "floor": ch - 2, "cover": 0.5, "ss": 3})
		core.SetStyle(M.make_style(st, gs, core.PaintColors()))
		return core.Render()

	var count := func(img: Image, c: Color) -> int:
		var n := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).is_equal_approx(c):
					n += 1
		return n

	# 3 頭身・立ち・正面で塗る
	var s: Dictionary = core.ForHeads(3.0)
	core.Build(s, 72.0, M.garment_specs(gs))
	pose_of.call("立ち", 3.0)
	draw.call(0.0)
	var j: Dictionary = core.Joints()
	var chin: Vector3 = core.Project(j["head"])
	var top: Vector3 = core.Project(j["head/tail"])
	var ey := chin.y + (top.y - chin.y) * 0.42
	var added := 0
	for sx in [-3.5, 3.5]:
		for dy in [0.0, 1.0]:
			added += core.PaintAt(chin.x + sx, ey + dy, 1.0, eye, true, false, false)
	var sh: Vector3 = core.Project(j["chest/tail"])
	for dx in range(-7, 8):
		added += core.PaintAt(sh.x + dx + 0.5, sh.y + 5.5, 1.0, red, false, false, false)
	# 左右対称: 左のそでに 1 か所塗ると、右にも
	var el: Vector3 = core.Project(j["forearm.L"])
	added += core.PaintAt(el.x, el.y, 2.0, red, false, false, true)
	print("塗った点: %d (PaintCount %d)" % [added, core.PaintCount()])
	var img0: Image = draw.call(0.0)
	print("正面: 目の画素 %d (4 のはず)" % count.call(img0, eye))
	# 同じ所をもう一度塗っても点は増えない
	var again: int = core.PaintAt(chin.x - 3.5, ey, 1.0, eye, true, false, false)
	print("同じ所をもう一度: 足した点 %d (0 のはず)" % again)

	var rows := [["立ち", 3.0], ["走り", 3.0], ["すわる", 3.0], ["立ち", 2.0], ["立ち", 6.0]]
	var yaws := [0.0, 45.0, 90.0, 180.0, 315.0]
	var sheet := Image.create_empty(cw * yaws.size(), ch * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#8a8f9a"))
	var heads_now := 3.0
	for r in rows.size():
		if rows[r][1] != heads_now:
			heads_now = rows[r][1]
			var t0 := Time.get_ticks_msec()
			core.Build(core.ForHeads(heads_now), 72.0, M.garment_specs(gs))
			print("%s 頭身に作り直し: %d ミリ秒 (塗りの点 %d)" % [str(heads_now), Time.get_ticks_msec() - t0, core.PaintCount()])
		pose_of.call(rows[r][0], heads_now)
		var line := "%s %s 頭身: " % [rows[r][0], str(heads_now)]
		for c in yaws.size():
			var im: Image = draw.call(yaws[c])
			line += "%d°: 目 %d  " % [int(yaws[c]), count.call(im, eye)]
			sheet.blend_rect(im, Rect2i(0, 0, cw, ch), Vector2i(c * cw, r * ch))
		print(line)

	# 消しゴム・保存して戻す
	core.Build(core.ForHeads(3.0), 72.0, M.garment_specs(gs))
	pose_of.call("立ち", 3.0)
	var before: Image = draw.call(0.0)
	var data: Dictionary = core.GetPaint()
	core.PaintAt(chin.x - 3.5, ey, 3.0, eye, true, true, false)
	print("消しゴムのあと: 目の画素 %d (2 のはず)" % count.call(draw.call(0.0), eye))
	core.SetPaint(data)
	var back: Image = draw.call(0.0)
	print("データを戻す: %s" % ("同じ絵" if back.get_data() == before.get_data() else "ちがう"))
	core.ClearPaint()
	print("全部消す: 目の画素 %d" % count.call(draw.call(0.0), eye))

	sheet.resize(sheet.get_width() * zoom, sheet.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("-> ", out)
	quit()
