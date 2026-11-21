## 確かめ用: ペンで引いた線が髪の房になるか。3 頭身・正面で ツインテール (左右対称)・アホ毛、
## 横から ポニーテール を引いて、向き・ポーズ・頭身を変えた絵を並べる (画面なしで動く)。
##   Godot --headless --path . -s tools/hairpen_shot.gd -- <出力.png> [px=56] [zoom=4]
extends SceneTree


func _init() -> void:
	var out := "user://hairpen.png"
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

	var pose_of := func(name: String, heads: float) -> void:
		var rots: Dictionary = poses.to_quats(poses.named(name, 45.0, poses.hang_for(heads)))
		core.SetPose(rots, Vector3.ZERO)
		var fixed: Dictionary = core.FixArms(0.25)
		for k in fixed:
			rots[k] = fixed[k]
		core.SetPose(rots, Vector3.ZERO)
		core.SetPose(rots, Vector3(0, -core.LowestY(), 0))

	var hair: Dictionary = M.hair_named("ボブ")
	var draw := func(yaw: float) -> Image:
		core.SetView({"w": cw, "h": ch, "px": px, "yaw": yaw, "pitch": 0.0, "floor": ch - 2, "cover": 0.5, "ss": 3})
		core.SetStyle(M.make_style(st, M.mats_of(gs, hair), core.PaintColors()))
		return core.Render()
	var build := func(heads: float, h: Dictionary) -> void:
		core.SetHair(h)
		var info: Dictionary = core.Build(core.ForHeads(heads), 72.0, M.garment_specs(gs))
		print("%s 頭身: 頂点 %d・%d ミリ秒・房 %d 本" % [str(heads), info.verts, int(info.seconds * 1000.0), h.locks.size()])

	var rows := []       # [名前, 髪, ポーズ, 頭身]
	# ボブ + ツインテール + アホ毛
	build.call(3.0, hair)
	pose_of.call("立ち", 3.0)
	draw.call(0.0)
	var j: Dictionary = core.Joints()
	var chin: Vector3 = core.Project(j["head"])
	var top: Vector3 = core.Project(j["head/tail"])
	var hh := chin.y - top.y
	var c := Vector2(chin.x, top.y)
	# 頭の横 (高め) から外へ出て、下へ垂れる
	var tw := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		tw.append(c + Vector2(hh * (0.36 + 0.34 * sin(t * PI * 0.55)), hh * (0.28 + 1.05 * t * t)))
	hair.locks += core.HairStroke(tw, 0.13 * hh * 2.0, 0.75, true, false)
	# アホ毛: てっぺんから上へ、くるっと
	var ah := PackedVector2Array()
	for i in 7:
		var t := i / 6.0
		ah.append(c + Vector2(hh * 0.22 * sin(t * PI), hh * (0.06 - 0.26 * sin(t * PI * 0.6))))
	hair.locks += core.HairStroke(ah, 0.035 * hh * 2.0, 0.6, false, false)
	print("ツインテール 2 本 + アホ毛: 房 %d 本・点 %s" % [hair.locks.size(), str(hair.locks.map(func(l): return l.size() / 4))])
	rows.append(["ボブ + ツインテール", hair.duplicate(true), "立ち", 3.0])
	rows.append(["同じ・走り", hair.duplicate(true), "走り", 3.0])
	rows.append(["同じ・2 頭身", hair.duplicate(true), "立ち", 2.0])
	rows.append(["同じ・6 頭身", hair.duplicate(true), "立ち", 6.0])

	# ショート + ポニーテール (横の絵に描く) + おだんご (1 点)
	var h2: Dictionary = M.hair_named("ショート")
	build.call(3.0, h2)
	pose_of.call("立ち", 3.0)
	draw.call(90.0)
	j = core.Joints()
	chin = core.Project(j["head"])
	top = core.Project(j["head/tail"])
	hh = chin.y - top.y
	# 向き 90° の絵で、後ろがどちら側かを 3D から調べる
	var back: Vector3 = core.Project(j["head"] + Vector3(0, 0, -1.0))
	var sgn := signf(back.x - chin.x)
	var pc := Vector2(chin.x, top.y)
	var pt := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pt.append(pc + Vector2(sgn * hh * (0.3 + 0.5 * sin(t * PI * 0.6)), hh * (0.3 + 1.0 * t * t)))
	h2.locks += core.HairStroke(pt, 0.12 * hh * 2.0, 0.8, false, false)
	rows.append(["ショート + ポニーテール (横から描いた)", h2.duplicate(true), "立ち", 3.0])
	rows.append(["同じ・走り", h2.duplicate(true), "走り", 3.0])

	# 殻なし (ひな形「なし」): ペンだけ。おだんご 2 つ (1 点の線)
	var h3: Dictionary = M.hair_named("")
	build.call(3.0, h3)
	pose_of.call("立ち", 3.0)
	draw.call(0.0)
	j = core.Joints()
	chin = core.Project(j["head"])
	top = core.Project(j["head/tail"])
	hh = chin.y - top.y
	h3.locks += core.HairStroke(PackedVector2Array([Vector2(chin.x + hh * 0.3, top.y + hh * 0.08)]), 0.16 * hh * 2.0, 0.0, true, false)
	rows.append(["ひな形なし + おだんご", h3.duplicate(true), "立ち", 3.0])

	# 切るペン: ボブの前髪に、下から上へ切れ込み = 真ん中の分け目
	var h4: Dictionary = M.hair_named("ボブ")
	build.call(3.0, h4)
	pose_of.call("立ち", 3.0)
	draw.call(0.0)
	h4.locks += core.HairStroke(PackedVector2Array([Vector2(chin.x, top.y + hh * 0.56), Vector2(chin.x, top.y + hh * 0.2)]), 0.13 * hh * 2.0, 0.7, false, true)
	rows.append(["ボブ + 真ん中の分け目 (切るペン)", h4.duplicate(true), "立ち", 3.0])
	rows.append(["同じ・2 頭身", h4.duplicate(true), "立ち", 2.0])
	# 横分け + ななめの前髪: 片側へ寄せた切れ込みと、前髪の下の端をななめに切る
	var h5: Dictionary = M.hair_named("ロング")
	h5["bangs"] = 0.55
	build.call(3.0, h5)
	pose_of.call("立ち", 3.0)
	draw.call(0.0)
	h5.locks += core.HairStroke(PackedVector2Array([Vector2(chin.x + hh * 0.2, top.y + hh * 0.6), Vector2(chin.x + hh * 0.14, top.y + hh * 0.12)]), 0.07 * hh * 2.0, 0.85, false, true)
	h5.locks += core.HairStroke(PackedVector2Array([Vector2(chin.x + hh * 0.16, top.y + hh * 0.62), Vector2(chin.x - hh * 0.34, top.y + hh * 0.44)]), 0.08 * hh * 2.0, 0.0, false, true)
	rows.append(["ロング + 横分け・ななめの前髪", h5.duplicate(true), "立ち", 3.0])
	# 房を足してから切る (描いた順に効く): ツインテールの先を切り落とす
	var h6: Dictionary = rows[0][1].duplicate(true)
	build.call(3.0, h6)
	pose_of.call("立ち", 3.0)
	draw.call(0.0)
	h6.locks += core.HairStroke(PackedVector2Array([tw[9] + Vector2(-4, 0), tw[9] + Vector2(4, 0)]), 0.12 * hh * 2.0, 0.0, true, true)
	rows.append(["ツインテールの先を切る", h6.duplicate(true), "立ち", 3.0])

	var yaws := [0.0, 45.0, 90.0, 180.0, 315.0]
	var sheet := Image.create_empty(cw * yaws.size(), ch * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#8a8f9a"))
	for r in rows.size():
		hair = rows[r][1]
		build.call(rows[r][3], hair)
		pose_of.call(rows[r][2], rows[r][3])
		for ci in yaws.size():
			var im: Image = draw.call(yaws[ci])
			sheet.blend_rect(im, Rect2i(0, 0, cw, ch), Vector2i(ci * cw, r * ch))
		var chk: Dictionary = core.Check()
		print("%s: %s" % [rows[r][0], str(chk)])

	sheet.resize(sheet.get_width() * zoom, sheet.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("-> ", out)
	quit()
