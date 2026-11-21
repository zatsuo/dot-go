## 確かめ用: 明るさのペン (色を置かずに、その場所の色の段を上げ下げする)。髪にハイライト、服に影、
## 色の塗りの上に重ねる、消しゴムで元どおり、を絵と数で見る (画面なしで動く)。
##   Godot --headless --path . -s tools/tone_shot.gd -- <出力.png>
extends SceneTree


func _init() -> void:
	var out := "user://tone.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var core = load("res://core/DotCore.cs").new()
	var poses = load("res://scripts/poses.gd")
	var M = load("res://scripts/main.gd")
	var gs := []
	for w in ["長そでシャツ", "ズボン", "靴"]:
		M.wear(gs, M.clothes_named(w))
	gs[0]["color"] = Color("#c8323c") if gs[0].has("color") else Color.RED
	var st: Dictionary = M.default_style()
	var px := 56
	var cw := int(px * 1.5) + 4
	var ch := px + 6
	var hair: Dictionary = M.hair_named("ロング")
	hair["gloss"] = 0.0
	core.SetHair(hair)
	core.Build(core.ForHeads(3.0), 72.0, M.garment_specs(gs))
	var rots: Dictionary = poses.to_quats(poses.named("立ち", 45.0, poses.hang_for(3.0)))
	core.SetPose(rots, Vector3.ZERO)
	core.SetPose(rots, Vector3(0, -core.LowestY(), 0))
	var draw := func(yaw: float) -> Image:
		core.SetView({"w": cw, "h": ch, "px": px, "yaw": yaw, "pitch": 0.0, "floor": ch - 2, "cover": 0.5, "ss": 3})
		core.SetStyle(M.make_style(st, M.mats_of(gs, hair), core.PaintColors()))
		return core.Render()
	var diff := func(a: Image, b: Image) -> int:
		var n := 0
		for y in a.get_height():
			for x in a.get_width():
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					n += 1
		return n
	var line := func(a: Vector2, b: Vector2, size: float, kind: int, erase := false) -> int:
		var added := 0
		var n := int(ceil(a.distance_to(b) / 0.5))
		for i in n + 1:
			var p := a.lerp(b, float(i) / maxi(n, 1))
			added += core.PaintKind(p.x, p.y, size, Color.BLACK, false, erase, false, kind)
		return added

	var base: Image = draw.call(0.0)
	var j: Dictionary = core.Joints()
	var chin: Vector3 = core.Project(j["head"])
	var top: Vector3 = core.Project(j["head/tail"])
	var hh := chin.y - top.y
	var sheet := Image.create_empty(cw * 5, ch, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#8a8f9a"))
	sheet.blend_rect(base, Rect2i(0, 0, cw, ch), Vector2i(0, 0))
	# 髪にハイライト: 頭の上のほうに弧 (明るく)、その真ん中だけ もっと明るく
	var n1: int = 0
	for k in 9:
		var t0 := (k - 4) / 4.0
		var t1 := (k - 3) / 4.0
		n1 += line.call(Vector2(chin.x + hh * 0.36 * t0, top.y + hh * (0.2 + 0.05 * t0 * t0)), Vector2(chin.x + hh * 0.36 * minf(t1, 1.0), top.y + hh * (0.2 + 0.05 * t1 * t1)), 1.0, 1)
	n1 += line.call(Vector2(chin.x - hh * 0.2, top.y + hh * 0.2), Vector2(chin.x - hh * 0.05, top.y + hh * 0.2), 1.0, 2)
	# 髪の下のほうに影 (暗く)
	n1 += line.call(Vector2(chin.x + hh * 0.38, top.y + hh * 1.0), Vector2(chin.x + hh * 0.38, top.y + hh * 1.6), 2.0, -1)
	var a1: Image = draw.call(0.0)
	print("髪にハイライトと影: 足した点 %d・変わった画素 %d" % [n1, diff.call(base, a1)])
	# 服に影 (胸の下に横の線) と、いちばん明るい所に ハイライト
	var sh: Vector3 = core.Project(j["chest/tail"])
	var n2: int = line.call(Vector2(sh.x - 5, sh.y + 9.5), Vector2(sh.x + 5, sh.y + 9.5), 1.0, -1)
	n2 += line.call(Vector2(sh.x - 4, sh.y + 4.5), Vector2(sh.x - 1, sh.y + 4.5), 1.0, 1)
	var a2: Image = draw.call(0.0)
	print("服に影とハイライト: 足した点 %d・変わった画素 %d" % [n2, diff.call(a1, a2)])
	sheet.blend_rect(a2, Rect2i(0, 0, cw, ch), Vector2i(cw, 0))
	sheet.blend_rect(draw.call(45.0), Rect2i(0, 0, cw, ch), Vector2i(cw * 2, 0))
	# 色の塗りの上に重ねる: 髪に色のメッシュを塗って、その上を明るく → 色は残り、段だけ変わる
	draw.call(0.0)
	var mesh_col := Color("#e8a0b0")
	var n3 := 0
	for i in 20:
		n3 += core.PaintKind(chin.x - hh * 0.38, top.y + hh * (0.5 + 0.05 * i), 2.0, mesh_col, false, false, false, 0)
	var a3: Image = draw.call(0.0)
	var n4: int = line.call(Vector2(chin.x - hh * 0.38, top.y + hh * 0.7), Vector2(chin.x - hh * 0.38, top.y + hh * 0.9), 2.0, 1)
	var a4: Image = draw.call(0.0)
	print("色のメッシュ %d 点の上を明るく %d 点: 変わった画素 %d・塗りの色の数 %d (1 のはず)" % [n3, n4, diff.call(a3, a4), core.PaintColors().size()])
	sheet.blend_rect(a4, Rect2i(0, 0, cw, ch), Vector2i(cw * 3, 0))
	# 保存して戻す → 同じ絵。消しゴムで全部なぞる → 最初の絵
	var data: Dictionary = core.GetPaint()
	core.ClearPaint()
	core.SetPaint(data)
	print("データを戻す: ちがう画素 %d (0 のはず)" % diff.call(draw.call(0.0), a4))
	for y in range(0, ch, 2):
		line.call(Vector2(0, y + 0.5), Vector2(cw, y + 0.5), 3.0, 0, true)
	var a5: Image = draw.call(0.0)
	print("消しゴムで全部なぞる: 最初の絵とちがう画素 %d (0 のはず)" % diff.call(base, a5))
	sheet.blend_rect(a5, Rect2i(0, 0, cw, ch), Vector2i(cw * 4, 0))
	sheet.resize(sheet.get_width() * 5, sheet.get_height() * 5, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("-> ", out)
	quit()
