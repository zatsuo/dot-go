## 確かめ用: 頭身 × 向きの表を PNG に書き出す (画面なしで動く)。
##   Godot --headless --path . -s tools/shot.gd -- <出力.png> [px=48] [heads=2,3,4,6] [yaws=0,45,90,180] [zoom=4]
##   ほかの数値: pitch=20 line=1 res=72 cover=0.5 ss=3 pose=walk key=値 (体型の数値)
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "user://shot.png"
	var opt := {"px": "48", "heads": "2,2.5,3,4,5,6,7.5", "yaws": "0,45,90,180", "zoom": "4", "pitch": "0",
			"line": "1", "res": "72", "cover": "0.5", "ss": "3", "pose": "", "auto": "1", "rim": "0", "wear": "", "bg": "#8a8f9a", "probe": "0", "hair": ""}
	var body := {}
	for a in args:
		if "=" in a:
			var kv := a.split("=")
			if opt.has(kv[0]):
				opt[kv[0]] = kv[1]
			else:
				body[kv[0]] = float(kv[1])
		else:
			out = a
	var core = load("res://core/DotCore.cs").new()
	var heads: Array = Array(opt.heads.split(","))
	var yaws: Array = Array(opt.yaws.split(","))
	var px := int(opt.px)
	var cw := int(px * 1.5) + 4
	var ch := px + 6
	var zoom := int(opt.zoom)
	var sheet := Image.create_empty(cw * yaws.size(), ch * heads.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(opt.bg))
	var poses = load("res://scripts/poses.gd")
	var M = load("res://scripts/main.gd")
	var gs := []
	for w in opt.wear.split(",", false):
		M.wear(gs, M.clothes_named(w))
	var st: Dictionary = M.default_style()
	var hair: Dictionary = M.hair_named(opt.hair)
	for k in body.keys():
		if k.begins_with("h_"):          # h_bangs=0.5 のように、髪の数値を上書き
			hair[k.substr(2)] = body[k]
			body.erase(k)
	core.SetHair(hair)
	var mats: Array = M.mats_of(gs, hair)
	for r in heads.size():
		var s: Dictionary = {}
		if opt.auto == "1":
			s = core.ForHeads(float(heads[r]))
		s["heads"] = float(heads[r])
		for k in body:
			s[k] = body[k]
		var t0 := Time.get_ticks_msec()
		var info: Dictionary = core.Build(s, float(opt.res), M.garment_specs(gs))
		var chk: Dictionary = core.Check()
		print("heads %s: %d verts %d tris  mesh %.0f ms (all %d ms)  open=%d asym=%.5f parts=%s" % [
				heads[r], info.verts, info.tris, info.seconds * 1000.0, Time.get_ticks_msec() - t0, chk.open_edges, chk.x_asym, str(chk.parts)])
		if opt.probe == "1":
			for clothed in [false, true]:
				var pr: PackedFloat32Array = core.ShoulderProfile(16, 0.48, clothed)
				var t := ""
				for v in pr:
					t += "%6.3f" % v
				print("  肩の上の線 (%s) x=0→0.48B: %s" % ["服" if clothed else "体", t])
		if opt.pose != "":
			var p: Dictionary = poses.named(opt.pose, float(s.get("arm_angle", 45.0)), poses.hang_for(float(heads[r])))
			var rots: Dictionary = poses.to_quats(p)
			core.SetPose(rots, Vector3.ZERO)
			# 腕が胴や服に入っていたら開く (画面の fix_arms と同じ)
			var fixed: Dictionary = core.FixArms(0.25)
			for k in fixed:
				rots[k] = fixed[k]
			core.SetPose(rots, Vector3.ZERO)
			core.SetPose(rots, Vector3(0, -core.LowestY(), 0))
			print("  clear L %.2f R %.2f" % [core.ArmClearance("L"), core.ArmClearance("R")])
		else:
			core.SetPose({}, Vector3.ZERO)
		for c in yaws.size():
			core.SetView({"w": cw, "h": ch, "px": px, "yaw": float(yaws[c]), "pitch": float(opt.pitch),
					"floor": ch - 2, "cover": float(opt.cover), "ss": int(opt.ss)})
			st.line_mode = int(opt.line)
			st.rim = int(opt.rim)
			core.SetStyle(M.make_style(st, mats))
			var t1 := Time.get_ticks_usec()
			var img: Image = core.Render()
			if r == 0 and c == 0:
				print("render %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
			sheet.blend_rect(img, Rect2i(0, 0, cw, ch), Vector2i(c * cw, r * ch))
	sheet.resize(sheet.get_width() * zoom, sheet.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("-> ", out)
	quit()
