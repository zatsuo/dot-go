## 確かめ用: 髪のペンが「描いたとおり」になるか。塗った画素と、できた髪の画素を数えて比べる (画面なしで動く)。
##   Godot --headless --path . -s tools/hairpen_feel.gd -- <出力.png>
extends SceneTree


func _init() -> void:
	var out := "user://hairpen_feel.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var core = load("res://core/DotCore.cs").new()
	var poses = load("res://scripts/poses.gd")
	var M = load("res://scripts/main.gd")
	var gs := []
	for w in ["長そでシャツ", "ズボン", "靴"]:
		M.wear(gs, M.clothes_named(w))
	var st: Dictionary = M.default_style()
	var px := 56
	var cw := int(px * 1.5) + 4
	var ch := px + 6
	var hair: Dictionary = M.hair_named("ボブ")
	var hcol: Color = hair.color

	var build := func() -> void:
		core.SetHair(hair)
		core.Build(core.ForHeads(3.0), 72.0, M.garment_specs(gs))
		var rots: Dictionary = poses.to_quats(poses.named("立ち", 45.0, poses.hang_for(3.0)))
		core.SetPose(rots, Vector3.ZERO)
		core.SetPose(rots, Vector3(0, -core.LowestY(), 0))
	var draw := func(yaw: float) -> Image:
		core.SetView({"w": cw, "h": ch, "px": px, "yaw": yaw, "pitch": 0.0, "floor": ch - 2, "cover": 0.5, "ss": 3})
		core.SetStyle(M.make_style(st, M.mats_of(gs, hair), core.PaintColors()))
		return core.Render()
	## 線 pts を太さ size で塗ったときの画素 (下書きと同じ決まり)
	var cells_of := func(pts: PackedVector2Array, size: float) -> Dictionary:
		var seen := {}
		var half := maxf(size * 0.5, 0.6)
		for i in pts.size() - 1:
			var steps := int(ceil(pts[i].distance_to(pts[i + 1]) / 0.3)) + 1
			for k in steps + 1:
				var c := pts[i].lerp(pts[i + 1], float(k) / steps)
				for y in range(int(floor(c.y - half)), int(ceil(c.y + half)) + 1):
					for x in range(int(floor(c.x - half)), int(ceil(c.x + half)) + 1):
						if Vector2(x + 0.5, y + 0.5).distance_to(c) <= maxf(half, 0.71):
							seen[Vector2i(x, y)] = true
		return seen
	## 塗った画素のうち、できた絵で髪 (部品 15・16) になっている割合
	var hit_rate := func(cells: Dictionary) -> float:
		var n := 0
		for c in cells:
			var p: int = core.Pick(c.x, c.y).part
			if p == 15 or p == 16:
				n += 1
		return float(n) / maxi(cells.size(), 1)

	build.call()
	draw.call(0.0)
	var j: Dictionary = core.Joints()
	var chin: Vector3 = core.Project(j["head"])
	var top: Vector3 = core.Project(j["head/tail"])
	var hh := chin.y - top.y
	var sheet := Image.create_empty(cw * 6, ch * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#8a8f9a"))
	var col := 0
	# 1) 太さ 1〜4 の線を、頭の外 (空) へ引く: 細い線が途切れないか
	for size in [1.0, 2.0, 3.0, 4.0]:
		hair.locks = []
		build.call()
		draw.call(0.0)
		var pts := PackedVector2Array([Vector2(chin.x + hh * 0.3, top.y + hh * 0.3), Vector2(chin.x + hh * 0.95, top.y + hh * 0.1),
				Vector2(chin.x + hh * 1.1, top.y + hh * 0.9)])
		hair.locks += core.HairStroke(pts, size, 0.0, false, false)
		build.call()
		var im: Image = draw.call(0.0)
		var cells: Dictionary = cells_of.call(pts, size)
		print("太さ %d: 塗った %d 画素のうち 髪になった %.0f%%・房 %d 本" % [int(size), cells.size(), hit_rate.call(cells) * 100.0, hair.locks.size()])
		if col < 6:
			sheet.blend_rect(im, Rect2i(0, 0, cw, ch), Vector2i(col * cw, 0))
			col += 1
	# 2) 胸の前へ垂らす (体の上を通る線): 体の中に隠れないか
	hair.locks = []
	build.call()
	draw.call(0.0)
	var down := PackedVector2Array([Vector2(chin.x + hh * 0.3, top.y + hh * 0.7), Vector2(chin.x + hh * 0.25, top.y + hh * 1.7)])
	hair.locks += core.HairStroke(down, 3.0, 0.0, true, false)
	build.call()
	var im2: Image = draw.call(0.0)
	var c2: Dictionary = cells_of.call(down, 3.0)
	print("胸の前へ垂らす: 塗った %d 画素のうち 髪になった %.0f%%" % [c2.size(), hit_rate.call(c2) * 100.0])
	sheet.blend_rect(im2, Rect2i(0, 0, cw, ch), Vector2i(4 * cw, 0))
	sheet.blend_rect(draw.call(90.0), Rect2i(0, 0, cw, ch), Vector2i(5 * cw, 0))
	# 3) 消しゴム: 髪の無い所 (空・服) をなぞっても何も足されない。髪の上は、なぞった画素から髪が消える
	draw.call(0.0)
	var none: Array = core.HairStroke(PackedVector2Array([Vector2(4, 4), Vector2(12, 6)]), 3.0, 0.0, false, true)
	var body_only: Array = core.HairStroke(PackedVector2Array([Vector2(chin.x - 2, top.y + hh * 2.2), Vector2(chin.x + 2, top.y + hh * 2.2)]), 3.0, 0.0, false, true)
	print("消しゴム: 空をなぞる → 線 %d 本・ズボンをなぞる → %d 本 (どちらも 0 のはず)" % [none.size(), body_only.size()])
	var er := PackedVector2Array([Vector2(chin.x + hh * 0.2, top.y + hh * 1.2), Vector2(chin.x + hh * 0.4, top.y + hh * 1.2)])
	hair.locks += core.HairStroke(er, 2.0, 0.0, false, true)
	build.call()
	var im3: Image = draw.call(0.0)
	var c3: Dictionary = cells_of.call(er, 2.0)
	print("消しゴム: 垂らした髪を横に消す → なぞった %d 画素のうち まだ髪 %.0f%% (0 のはず)" % [c3.size(), hit_rate.call(c3) * 100.0])
	sheet.blend_rect(im3, Rect2i(0, 0, cw, ch), Vector2i(0, ch))
	# 4) 重ね描き: 同じ所を何度も塗る → 中に線が出ない (線の画素を数える)
	hair.locks = []
	build.call()
	draw.call(0.0)
	for k in 4:
		var sc := PackedVector2Array([Vector2(chin.x - hh * 0.5, top.y + hh * (0.75 + 0.12 * k)), Vector2(chin.x - hh * 0.75, top.y + hh * (1.1 + 0.12 * k))])
		hair.locks += core.HairStroke(sc, 3.0, 0.3, false, false)
	build.call()
	var im4: Image = draw.call(0.0)
	sheet.blend_rect(im4, Rect2i(0, 0, cw, ch), Vector2i(cw, ch))
	hair["lock_sep"] = true
	build.call()
	sheet.blend_rect(draw.call(0.0), Rect2i(0, 0, cw, ch), Vector2i(2 * cw, ch))
	print("重ね描き: 左 = ひとかたまり (ふだん)、右 = 線で分ける")
	sheet.resize(sheet.get_width() * 5, sheet.get_height() * 5, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("-> ", out)
	quit()
