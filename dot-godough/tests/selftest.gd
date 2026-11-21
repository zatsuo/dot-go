## 画面を開いて一通り操作し、画面の絵と書き出しを <フォルダ> に残す。
##   Run.bat -- --selftest <フォルダ>
extends RefCounted

var main
var out := ""
var log_lines: Array = []


func note(t: String) -> void:
	log_lines.append(t)
	print("[selftest] ", t)


func shot(name: String) -> void:
	for i in 3:
		await main.get_tree().process_frame
	# 省電力モードでは、変化がないとコマを描かない (描き終わりの合図が来ない) → 描き直しを頼んでから待つ
	main.pix.queue_redraw()
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func wait(sec: float) -> void:
	await main.get_tree().create_timer(sec).timeout


func run(m, dir: String) -> void:
	main = m
	out = dir
	DirAccess.make_dir_recursive_absolute(out)
	await wait(0.6)
	main.fit_all()
	await shot("01_start")

	# 体型: ひな形を順に
	for h in [2.0, 6.0, 3.0]:
		main.set_heads(h, true)
		await wait(0.4)
		main.fit_all()
		await shot("02_heads_%s" % str(h))
	note("体: " + main._info.text)

	var left: TabContainer = main._tabs_l

	# 服: ひな形を足す・厚みを変える・重ねる順
	left.current_tab = 1
	for n in ["靴", "長そでシャツ", "ズボン", "靴下"]:
		main.add_clothes(n)
	await wait(0.5)
	note("服の並び: " + ", ".join(main.garments.map(func(g): return g.name)))
	note("服を着たあとの腕のすき間 (ます): L %.2f R %.2f" % [main.core.ArmClearance("L"), main.core.ArmClearance("R")])
	await shot("02b_wear")
	main.add_clothes("スカート")
	main._gset("flare", 9.0)
	main._sync_wear_ui()
	await wait(0.5)
	note("スカートのあとの腕のすき間: L %.2f R %.2f" % [main.core.ArmClearance("L"), main.core.ArmClearance("R")])
	await shot("02c_skirt")
	left.current_tab = 0

	# しゃがむ: 腰の点を下へ。足首は元の場所に残る
	main.push_undo()
	var a0: Vector3 = main.joints["shin.L/tail"]
	var h0: Vector3 = main.joints["hips"]
	var hp: Vector3 = main.handle_px(0)
	main.drag_handle(0, Vector2(hp.x + 2, hp.y + 5))
	var a1: Vector3 = main.joints["shin.L/tail"]
	var h1: Vector3 = main.joints["hips"]
	note("しゃがむ: 腰 %.3f m 下がる・足首のずれ %.4f m" % [h0.y - h1.y, (a1 - a0).length()])
	await wait(0.4)
	await shot("02d_crouch")
	# 上げすぎても、たまらない: 大きく上へ 5 回 → 体は脚が伸びきった高さで止まる
	for i in 5:
		hp = main.handle_px(0)
		main.drag_handle(0, Vector2(hp.x, hp.y - 30))
	note("腰を上げ続けたあとの root.y: %.3f (脚が届く高さで止まるはず)" % main.cur().root.y)
	main.undo()

	# 左右いっしょ
	main.push_undo()
	main.mirror_edit = true
	var wp: Vector3 = main.handle_px(7)
	main.drag_handle(7, Vector2(wp.x + 5, wp.y - 8))
	var ql: Quaternion = main.cur().rots["upper_arm.L"]
	var qr: Quaternion = main.cur().rots["upper_arm.R"]
	note("左右いっしょ: " + ("OK" if qr.is_equal_approx(Quaternion(ql.x, -ql.y, -ql.z, ql.w)) else "ちがう"))
	main.mirror_edit = false
	main.undo()

	# 輪郭をつまむ: 正面で左の上腕の外側を 2 画素 外へ → 腕の太さ。胸の横を 2 画素 外へ → 肩幅。
	# 横の絵でおなかを 2 画素 → 胴の厚み。頭のてっぺんを上へ → 頭身が減る。元に戻すと体型も戻る
	left.current_tab = 0
	await wait(0.4)
	var b0: Dictionary = main.body.duplicate()
	var grab := func(at: Vector2, by: Vector2, v) -> String:
		var t: Dictionary = main.shape_target(at, v)
		if t.is_empty():
			return "体に当たらず"
		main.push_undo(true)
		main.shape_drag(t, at + by * 0.5)
		main.shape_drag(t, at + by)
		return main.shape_hint(t)
	var el: Vector3 = main.core.Project(main.joints["upper_arm.L"].lerp(main.joints["upper_arm.L/tail"], 0.5))
	var probe := Vector2(el.x, el.y)
	while not main.shape_target(probe + Vector2(1, 0), main.pix).is_empty() and main.shape_target(probe + Vector2(1, 0), main.pix).part in [2, 3]:
		probe.x += 1.0
	note("腕の外側をつまむ: " + grab.call(probe, Vector2(2, 0), main.pix))
	await wait(0.6)
	note("  腕の太さ %.2f → %.2f" % [b0.arm_thick, main.body.arm_thick])
	var ch: Vector3 = main.core.Project(main.joints["chest"].lerp(main.joints["chest/tail"], 0.6))
	note("胸をつまむ: " + grab.call(Vector2(ch.x + 3.0, ch.y), Vector2(2, 0), main.pix))
	await wait(0.6)
	note("  肩幅 %.2f → %.2f" % [b0.shoulder, main.body.shoulder])
	main._aim(main.pix2)
	var sp2: Vector3 = main.core.Project(main.joints["spine"].lerp(main.joints["spine/tail"], 0.5))
	main._aim(main.pix)
	var belly := Vector2(sp2.x, sp2.y)      # 横からは腕が胴に重なるので、胴が見えている所をさがす
	for dx in [5.0, 4.0, 3.0, -3.0, -4.0, -5.0]:
		var tt: Dictionary = main.shape_target(Vector2(sp2.x + dx, sp2.y), main.pix2)
		if not tt.is_empty() and tt.part == 0:
			belly.x = sp2.x + dx
			break
	note("横の絵でおなかをつまむ: " + grab.call(belly, Vector2(signf(belly.x - sp2.x) * 2.0, 0), main.pix2))
	await wait(0.6)
	note("  胴の厚み %.2f → %.2f" % [b0.depth, main.body.depth])
	var hd: Vector3 = main.core.Project(main.joints["head"].lerp(main.joints["head/tail"], 0.85))
	note("頭の上のほうを上へつまむ: " + grab.call(Vector2(hd.x, hd.y), Vector2(0, -3), main.pix))
	await wait(0.6)
	note("  頭身 %.2f → %.2f" % [b0.heads, main.body.heads])
	await shot("02i_shape")
	for i in 4:
		main.undo()
	await wait(0.6)
	note("輪郭をつまんだのを元に戻す: " + ("体型も戻った" if main.body == b0 else "ちがう"))

	# 塗る: 顔に目 (そのままの色)、胸に線 (影つき・左右対称)。向きを変えてもついてくる。元に戻すと消える
	left.current_tab = main._paint_tab
	await wait(0.3)
	var chin: Vector3 = main.handle_px(4)
	var crown: Vector3 = main.handle_px(5)
	var ey: float = chin.y + (crown.y - chin.y) * 0.4
	main.paint.flat = true
	main.paint.color = Color("#2a2030")
	for sx in [-3.5, 3.5]:
		main._paint_press(Vector2(chin.x + sx, ey), MOUSE_BUTTON_LEFT)
		main._on_dragged(Vector2(chin.x + sx, ey + 1.0), Vector2(0, 1), MOUSE_BUTTON_LEFT)
		main._on_released(Vector2.ZERO, MOUSE_BUTTON_LEFT)
	var n_eye: int = main.core.PaintCount()
	main.paint.flat = false
	main.paint.mirror = true
	main.paint.color = Color("#c8323c")
	var sh: Vector3 = main.handle_px(3)
	main._paint_press(Vector2(sh.x, sh.y + 5.5), MOUSE_BUTTON_LEFT)
	main._on_dragged(Vector2(sh.x + 6.0, sh.y + 5.5), Vector2(6, 0), MOUSE_BUTTON_LEFT)
	main._on_released(Vector2.ZERO, MOUSE_BUTTON_LEFT)
	main.paint.mirror = false
	note("塗る: 目 %d 点・胸の線を足して %d 点 (4 と 18 のはず)" % [n_eye, main.core.PaintCount()])
	await wait(0.4)
	await shot("02g_paint")
	main.view.yaw = 45.0
	main._sync("yaw", 45.0)
	main.mark()
	await wait(0.4)
	await shot("02h_paint_45")
	main.view.yaw = 0.0
	main._sync("yaw", 0.0)
	main.mark()
	main.undo()
	var n_undo: int = main.core.PaintCount()
	main.redo()
	note("塗りを元に戻す → やり直す: %d 点 → %d 点" % [n_undo, main.core.PaintCount()])
	left.current_tab = 0
	await wait(0.3)

	# 奥行き: 横の絵で手首を右へ → 真ん中の絵では、ほぼ同じ場所のまま、奥行きだけ変わる
	main.push_undo()
	var ax0: Array = main.core.Axes()
	var m0: Vector3 = main.handle_px(7)
	var w0: Vector3 = main.joints["forearm.L/tail"]
	main._aim(main.pix2)
	var sp: Vector3 = main.handle_px(7)
	main.drag_handle(7, Vector2(sp.x + 5, sp.y))
	main._aim(main.pix)
	var m1: Vector3 = main.handle_px(7)
	var w1: Vector3 = main.joints["forearm.L/tail"]
	note("横の絵で手首を 5 画素: 真ん中の絵でのずれ (%.1f, %.1f) 画素・奥行き %.3f m 動く" % [m1.x - m0.x, m1.y - m0.y, (w1 - w0).dot(ax0[2])])
	await wait(0.4)
	await shot("02e_depth_side")
	main.undo()
	# Shift: 奥行きだけ (下へ 6 画素 = 手前)
	main.push_undo()
	m0 = main.handle_px(7)
	w0 = main.joints["forearm.L/tail"]
	for i in 6:
		main.drag_handle(7, Vector2(m0.x, m0.y), Vector2(0, 1), true)
	m1 = main.handle_px(7)
	w1 = main.joints["forearm.L/tail"]
	note("Shift で手首を下へ 6 画素: 真ん中の絵でのずれ (%.1f, %.1f) 画素・手前へ %.3f m" % [m1.x - m0.x, m1.y - m0.y, (w1 - w0).dot(ax0[2])])
	m0 = main.handle_px(12)
	w0 = main.joints["thigh.L/tail"]
	for i in 4:
		main.drag_handle(12, Vector2(m0.x, m0.y), Vector2(0, 1), true)
	w1 = main.joints["thigh.L/tail"]
	note("Shift で左ひざを下へ 4 画素: 手前へ %.3f m" % (w1 - w0).dot(ax0[2]))
	await wait(0.4)
	await shot("02f_depth_shift")
	main.undo()

	# ポーズ: 手首をつまんで動かす (IK)・ひざ・頭、ひねる、元に戻す
	var before: Dictionary = main.cur().rots.duplicate()
	main.push_undo()
	var wrist := 7
	var p: Vector3 = main.handle_px(wrist)
	main.drag_handle(wrist, Vector2(p.x + 6, p.y - 12))
	var p2: Vector3 = main.handle_px(wrist)
	note("左手首 IK: 目標 (%.1f, %.1f) → 着いた所 (%.1f, %.1f)" % [p.x + 6, p.y - 12, p2.x, p2.y])
	var knee := 12
	p = main.handle_px(knee)
	main.drag_handle(knee, Vector2(p.x + 4, p.y - 3))
	main._sel = 5
	main.twist(5, 20.0)
	main._sync_bone_sliders()
	await wait(0.4)
	await shot("03_posed")
	main.undo()
	await wait(0.3)
	var same := true
	for b in before:
		if not main.cur().rots.has(b) or not main.cur().rots[b].is_equal_approx(before[b]):
			same = false
	note("元に戻す: " + ("OK" if same and main.cur().rots.size() == before.size() else "ちがう"))

	# 髪: ひな形をあてる (このあとの保存・シート・penInk にも髪が入る)
	left.current_tab = main._hair_tab
	main.set_hair("ボブ")
	await wait(0.8)
	note("髪 (ボブ): " + main._info.text)
	await shot("03b_hair")
	# 髪をペンで描く: 頭の横から下へ線を引く (左右対称 → 房 2 本)、横の絵にも 1 本、右ボタンで消す、元に戻す
	note("髪のペン: タブを開くと hair_mode = %s" % str(main.hair_mode))
	var hj: Vector3 = main.core.Project(main.joints["head"])
	var ht: Vector3 = main.core.Project(main.joints["head/tail"])
	var hh2 := hj.y - ht.y
	var line := PackedVector2Array()
	for i in 10:
		var t := i / 9.0
		line.append(Vector2(hj.x + hh2 * (0.38 + 0.3 * sin(t * PI * 0.5)), ht.y + hh2 * (0.3 + 0.9 * t * t)))
	main.hair_pen.mirror = true
	main.hair_pen.size = 4
	main.hair_pen.taper = 0.6
	main._on_pressed(line[0], MOUSE_BUTTON_LEFT, main.pix)
	for i in range(1, line.size()):
		main._on_dragged(line[i], line[i] - line[i - 1], MOUSE_BUTTON_LEFT, main.pix)
	main._on_released(line[-1], MOUSE_BUTTON_LEFT, main.pix)
	await wait(0.8)
	var n_l1: int = main.hair.locks.size()
	main.hair_pen.mirror = false
	main.hair_stroke(PackedVector2Array([Vector2(main.view.w * 0.5, ht.y + hh2 * 0.1), Vector2(main.view.w * 0.5, ht.y - hh2 * 0.15)]), main.pix2)
	await wait(0.8)
	var n_l2: int = main.hair.locks.size()
	# 右ボタン = 消しゴム: 描いた房の途中を横に消す → その画素から髪が消える
	var ex := line[7]
	var p_before: int = main.core.Pick(int(ex.x), int(ex.y)).part
	main._on_pressed(ex + Vector2(-4, 0), MOUSE_BUTTON_RIGHT, main.pix)
	main._on_dragged(ex + Vector2(4, 0), Vector2(8, 0), MOUSE_BUTTON_RIGHT, main.pix)
	main._on_released(ex + Vector2(4, 0), MOUSE_BUTTON_RIGHT, main.pix)
	await wait(0.8)
	var p_after: int = main.core.Pick(int(ex.x), int(ex.y)).part
	var n_l3: int = main.hair.locks.size()
	main.undo()
	await wait(0.8)
	note("髪のペン: 左右対称の線 → %d 本、横の絵にも 1 本 → %d 本、消しゴム: 部品 %d → %d (髪でなくなるはず)・%d 本、元に戻す → %d 本。%s" % [
			n_l1, n_l2, p_before, p_after, n_l3, main.hair.locks.size(), main._info.text])
	# 消しゴムで前髪に下から切れ込み (分け目)。額の画素が髪 → 肌に変わる
	var fx := int(hj.x)
	var fy := int(ht.y + hh2 * 0.36)
	var m_before: int = main.core.Pick(fx, fy).get("mat", -1)
	main.hair_pen.size = 3
	main.hair_pen.taper = 0.7
	main.hair_stroke(PackedVector2Array([Vector2(hj.x, ht.y + hh2 * 0.56), Vector2(hj.x, ht.y + hh2 * 0.2)]), main.pix, true)
	await wait(0.8)
	note("消しゴムで分け目: 額の素材 %d → %d (0 = 肌のはず)" % [m_before, main.core.Pick(fx, fy).get("mat", -1)])
	await shot("03c_hair_pen")
	left.current_tab = 0

	# ひな形のポーズと向き
	var p3: Dictionary = main.Poses.named("走り", main.body.arm_angle, main.Poses.hang_for(main.body.heads))
	main.cur().rots = main.Poses.to_quats(p3)
	main.view.yaw = 45.0
	main._sync("yaw", 45.0)
	main.mark("pose")
	await wait(0.5)
	await shot("04_run_45")

	# タブ: ドット絵・ポーズ、右は 3D
	left.current_tab = 2
	main.style.rim = 1
	main._sync("rim", 1)
	main.mark()
	await wait(0.4)
	await shot("05_look_tab")
	main.style.rim = 0
	main._sync("rim", 0)
	left.current_tab = 3
	main._tabs_r.current_tab = 2
	main.mark()
	await wait(0.5)
	await shot("06_pose_tab_3d")

	# お手本: 1 体を選ぶ → 紙を合わせる → 色を取る → 画素をじかに直す → 全部直す
	left.current_tab = main._ref_tab
	note("お手本を開く: " + str(main.load_ref(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))))
	main.set_heads(2.0, true)
	await wait(0.6)
	var isl: Rect2i = main.ref_island(Vector2i(136, 80))
	main.set_ref_rect(isl)
	main.fit_paper_to_ref()
	await wait(0.6)
	main.ref_align()
	note("お手本 1 体 %s・紙 %d×%d・キャラの高さ %d: %s" % [isl, main.view.w, main.view.h, int(main.view.px), main._ref_text()])
	var ncol: int = main.colors_from_ref()
	await wait(0.6)
	note("色を お手本から取る (%d 色): %s" % [ncol, main._ref_text()])
	await shot("06b_ref")
	main.ref.mode = 2
	await shot("06c_ref_diff")
	note("パレット: お手本から %d 色" % main.palette_from_ref())
	main.set_pen_color(main.palette[0])
	main.paint.target = 1
	main.push_undo()
	var nfix: int = main.fix_line(Vector2(3.5, 3.5), Vector2(6.5, 3.5))
	await wait(0.3)
	note("画素をじかに直す: 変えた %d 画素・絵がその色 %s" % [nfix, main._last_img.get_pixel(4, 3).to_html(false) == main.paint.color.to_html(false)])
	main.undo()
	await wait(0.3)
	note("元に戻す: 何も無い所に戻った %s" % (main._last_img.get_pixel(4, 3).a < 0.5))
	main.paint.target = 0
	var ntr: int = main.ref_trace()
	await wait(0.4)
	note("ちがう画素を全部直す (%d 画素): %s" % [ntr, main._ref_text()])
	main.ref.mode = 1
	left.current_tab = main._paint_tab
	await shot("06d_ref_traced")

	# 立体 (試作): お手本を正面として作る → 横の絵に描く → 立体が変わる → 元に戻す
	main.clear_fix()
	await wait(0.3)
	note("立体を作る: %s" % main.make_solid())
	main.paint["solid_mode"] = 1         # ここから下は「その向きの絵を決める」描き方の確かめ
	main.view.yaw = 0.0
	main._sync("yaw", 0.0)
	main.mark()
	await wait(0.4)
	var so_same := 0
	for y in main.view.h:
		for x in main.view.w:
			if main._last_img.get_pixel(x, y) == main._ref_img.get_pixel(x, y):
				so_same += 1
	note("立体の正面: お手本と同じ画素 %d / %d" % [so_same, main.view.w * main.view.h])
	var d45: Image = main.render_now(45.0)
	var side0: Image = main.render_now(90.0)
	main.render_now()
	# 横の絵 (右の窓) の頭の後ろに 3 画素描く → 決めた絵になり、ななめの絵も変わる
	var sy: int = main.solid.neck - 6
	var sx := 0
	while sx < main.view.w and side0.get_pixel(sx, sy).a < 0.5:
		sx += 1
	main.set_pen_color(side0.get_pixel(sx + 1, sy))
	main._on_pressed(Vector2(sx - 0.5, sy + 0.5), MOUSE_BUTTON_LEFT, main.pix2)
	main._on_dragged(Vector2(sx - 2.5, sy + 0.5), Vector2(-2, 0), MOUSE_BUTTON_LEFT, main.pix2)
	main._on_released(Vector2(sx - 2.5, sy + 0.5), MOUSE_BUTTON_LEFT, main.pix2)
	await wait(0.4)
	var side1: Image = main.render_now(90.0)
	var d45b: Image = main.render_now(45.0)
	main.render_now()
	var nd := 0
	var nd45 := 0
	for y in main.view.h:
		for x in main.view.w:
			if side0.get_pixel(x, y) != side1.get_pixel(x, y):
				nd += 1
			if d45.get_pixel(x, y) != d45b.get_pixel(x, y):
				nd45 += 1
	note("横の絵に描く: 横は決めた絵 %s・横の絵で変わった画素 %d・ななめの絵で変わった画素 %d (どちらも 1 以上のはず)" % [main.solid.is_drawn(90), nd, nd45])
	await shot("06e_solid")
	main.undo()
	await wait(0.3)
	note("元に戻す: 横は決めた絵 %s (false のはず)" % main.solid.is_drawn(90))
	# 表にある横向きの 1 体を選んで、横の絵にする → その向きは その絵のまま
	left.current_tab = main._ref_tab
	main.set_ref_rect(Rect2i(34, 128, 15, 32))
	await wait(0.3)
	note("横向きの 1 体を横の絵にする: %s" % main.solid_use_ref(90))
	await wait(0.4)
	var so_side: Image = main.render_now(90.0)
	main.render_now()
	var so_n := 0
	for y in main.view.h:
		for x in main.view.w:
			if so_side.get_pixel(x, y) == main._ref_img.get_pixel(x, y):
				so_n += 1
	note("  横の絵: 選んだ絵と同じ画素 %d / %d" % [so_n, main.view.w * main.view.h])
	main.view.yaw = 45.0
	main._sync("yaw", 45.0)
	main.mark()
	await wait(0.4)
	await shot("06f_solid_side")
	# ななめの絵に描く → 決めた絵になる。反対側のななめには鏡で出る。ポーズをつけても その画素は残る
	left.current_tab = main._paint_tab
	main.paint.target = 0
	main.view.yaw = 45.0
	main._sync("yaw", 45.0)
	main.mark()
	await wait(0.4)
	var dg := Vector2i(main.view.w / 2, main.solid.neck - 8)
	main.set_pen_color(Color("#ff00ff"))
	main._on_pressed(Vector2(dg) + Vector2(0.5, 0.5), MOUSE_BUTTON_LEFT, main.pix)
	main._on_released(Vector2(dg) + Vector2(0.5, 0.5), MOUSE_BUTTON_LEFT, main.pix)
	await wait(0.4)
	var dg45: Image = main.render_now(45.0)
	var dg315: Image = main.render_now(315.0)
	main.solid_preset("歩き 1")
	var dgw: Image = main.render_now(45.0)
	main.undo()
	main.render_now()
	note("ななめの絵に描く: 決めた絵 %s・その画素 %s・反対のななめ (鏡) %s・歩きのポーズでも残る %s" % [main.solid.is_drawn(45),
			dg45.get_pixel(dg.x, dg.y).to_html(false), dg315.get_pixel(main.view.w - 1 - dg.x, dg.y).to_html(false), dgw.get_pixel(dg.x, dg.y).to_html(false)])
	main.undo()
	await wait(0.3)
	note("  元に戻す: ななめは決めた絵 %s (false のはず)" % main.solid.is_drawn(45))
	# ポーズ: 決まったポーズ、部品の先をつまむ、部品を塗り直す、元に戻す
	left.current_tab = main._solid_tab
	main.view.yaw = 90.0
	main._sync("yaw", 90.0)
	var st_img: Image = main.render_now(90.0)
	main.solid_preset("歩き 1")
	await wait(0.4)
	var wk_img: Image = main.render_now(90.0)
	var wk_n := 0
	for y in main.view.h:
		for x in main.view.w:
			if st_img.get_pixel(x, y) != wk_img.get_pixel(x, y):
				wk_n += 1
	note("立体のポーズ「歩き 1」: 横の絵で変わった画素 %d (1 以上のはず)・ポーズあり %s" % [wk_n, main.solid.is_posed()])
	await shot("06g_solid_walk")
	main.solid_preset("立ち")
	main.view.yaw = 0.0
	main._sync("yaw", 0.0)
	main.mark()
	await wait(0.4)
	var tip := Vector2.ZERO
	for sh1 in main.solid.handles(0.0):
		if sh1.part == main.solid.ARM_B:
			tip = sh1.tip
	main._on_pressed(tip, MOUSE_BUTTON_LEFT, main.pix)
	main._on_dragged(tip + Vector2(3, -2), Vector2(3, -2), MOUSE_BUTTON_LEFT, main.pix)
	main._on_dragged(tip + Vector2(5, -5), Vector2(2, -3), MOUSE_BUTTON_LEFT, main.pix)
	main._on_released(tip + Vector2(5, -5), MOUSE_BUTTON_LEFT, main.pix)
	await wait(0.4)
	var tip2 := Vector2.ZERO
	for sh2 in main.solid.handles(0.0):
		if sh2.part == main.solid.ARM_B:
			tip2 = sh2.tip
	note("腕の先をつまんで (5, -5) 動かす: %s → %s (目標 %s)" % [tip, tip2, tip + Vector2(5, -5)])
	await shot("06h_solid_arm")
	main.undo()
	await wait(0.3)
	note("元に戻す: ポーズあり %s (false のはず)" % main.solid.is_posed())
	# IK: 手の先 (うすい丸) をつまむと、腕ぜんたいが動いて 先がそこへ行く
	var hand0 := Vector2.ZERO
	for sh4 in main.solid.handles(0.0):
		if sh4.part == main.solid.FORE_B:
			hand0 = sh4.tip
	main._on_pressed(hand0, MOUSE_BUTTON_LEFT, main.pix)
	main._on_dragged(hand0 + Vector2(2, -2), Vector2(2, -2), MOUSE_BUTTON_LEFT, main.pix)
	main._on_dragged(hand0 + Vector2(4, -5), Vector2(2, -3), MOUSE_BUTTON_LEFT, main.pix)
	main._on_released(hand0 + Vector2(4, -5), MOUSE_BUTTON_LEFT, main.pix)
	await wait(0.3)
	var hand1 := Vector2.ZERO
	for sh5 in main.solid.handles(0.0):
		if sh5.part == main.solid.FORE_B:
			hand1 = sh5.tip
	note("IK: 手の先をつまんで (4, -5) 動かす: %s → %s (目標 %s)・ひじも回った %s" % [hand0, hand1, hand0 + Vector2(4, -5), main.cur().sp.has(main.solid.ARM_B)])
	main.undo()
	await wait(0.3)
	main.part_edit = true
	main.part_sel = main.solid.BODY
	main.mark()
	await wait(0.3)
	var arm_px := Vector2(tip.x - 0.5, tip.y - 3.5)
	for sh3 in main.solid.handles(0.0):
		if sh3.part == main.solid.FORE_B:
			arm_px = Vector2(sh3.tip.x - 0.5, sh3.tip.y - 2.5)      # 手のすぐ上 (ひじから先)
	var before_p: int = main.solid.part_at(int(arm_px.x), int(arm_px.y))
	main._on_pressed(arm_px, MOUSE_BUTTON_LEFT, main.pix)
	main._on_released(arm_px, MOUSE_BUTTON_LEFT, main.pix)
	await wait(0.3)
	note("部品を塗り直す: %d → %d (2 = 体のはず)・自分で分けた %s" % [before_p, main.solid.part_at(int(arm_px.x), int(arm_px.y)), main.solid.pmap_user])
	await shot("06i_solid_parts")
	main.undo()
	main.part_edit = false
	main.solid_preset("すわる")
	await wait(0.3)
	# モデルの書き出し (アニメーションは 別アプリ)
	main.solid_preset("立ち")
	var model_ok: bool = main.export_model(out.path_join("test.dotmodel.json"))
	note("モデルを書き出す: %s (%d バイト)" % [model_ok, FileAccess.get_file_as_bytes(out.path_join("test.dotmodel.json")).size()])
	# 顔の層: 顔が見つかる・横向きで 目の色の画素が残る (層なしだと つぶれる)
	var sof = main.solid
	sof.pose = {}
	sof.ensure()
	var eye_n := [0, 0]
	for fi2 in 2:
		sof.face_layer = fi2 == 1
		var fim: Image = sof.render(75.0)
		for bl in sof._fblobs:
			var ec: Color = sof.pics[0].get_pixel(bl.pix[0].x, bl.pix[0].y)
			for yy2 in fim.get_height():
				for xx2 in fim.get_width():
					if fim.get_pixel(xx2, yy2).is_equal_approx(ec):
						eye_n[fi2] += 1
	sof.face_layer = true
	note("顔の層: 顔 %s・肌の色 %d 色・目や口 %d つ。75° で 目や口の色の画素: 層なし %d → 層あり %d" % [sof._face_ok, sof._skins.size(), sof._fblobs.size(), eye_n[0], eye_n[1]])
	sof.pose = main.cur().get("sp", {})
	# 面に塗る: ななめ (30°) で塗った色が、ほかの向き (45°・60°・0°) にも出る。保存して読み直しても残る
	var spt = main.solid
	spt.pose = {}
	spt.spaint.clear()
	spt.paint_reach = 180.0              # まず「どの向きにも出る」で確かめる
	var mark_c := Color(1, 0, 1, 1)
	var hit_n := 0
	for yy3 in range(spt.neck + 3, spt.neck + 7):
		for xx3 in range(spt.w / 2 - 1, spt.w / 2 + 3):
			if spt.paint_surface(30.0, xx3, yy3, mark_c):
				hit_n += 1
	var seen_s := []
	for yv in [30.0, 45.0, 60.0, 0.0, 210.0]:
		var sim: Image = spt.render(yv)
		var cnt3 := 0
		for yy3 in sim.get_height():
			for xx3 in sim.get_width():
				if sim.get_pixel(xx3, yy3).is_equal_approx(mark_c):
					cnt3 += 1
		seen_s.append("%d°:%d" % [int(yv), cnt3])
	var spt2 = DotSolid.from_doc(spt.to_doc())
	note("面に塗る: 30° で %d 画素塗った → 見える画素 %s (30〜60° と 0° は 1 以上、反対側の 210° は 0 のはず)・保存して読むと %d (%d のはず)" % [hit_n, str(seen_s), spt2.adds.size(), spt.adds.size()])
	spt.spaint.clear()
	spt.adds.clear()
	spt.touch()
	# 空中に描く: 横向き (90°) で 頭の後ろの 立体の無い所に 3 画素描く → 立体に足されて、ななめ・後ろ・ポーズ中にも出る
	var air_c := Color(0, 1, 1, 1)
	var air_n := 0
	var air_x := -1
	var base_im: Image = spt.render(90.0)
	for xx4 in spt.w:
		if base_im.get_pixel(xx4, spt.neck - 6).a > 0.5:
			air_x = xx4
			break
	for k4 in 3:
		if spt.paint_surface(90.0, air_x - 1 - k4, spt.neck - 6, air_c):
			air_n += 1
	var air_seen := []
	for yv4 in [90.0, 135.0, 180.0, 45.0]:
		var aim: Image = spt.render(yv4)
		var c4 := 0
		for yy4 in aim.get_height():
			for xx4 in aim.get_width():
				if aim.get_pixel(xx4, yy4).is_equal_approx(air_c):
					c4 += 1
		air_seen.append("%d°:%d" % [int(yv4), c4])
	spt.pose = {DotSolid.HEAD: Quaternion(Vector3.BACK, 0.4)}
	var tilt: Image = spt.render(90.0)
	var c5 := 0
	for yy4 in tilt.get_height():
		for xx4 in tilt.get_width():
			if tilt.get_pixel(xx4, yy4).is_equal_approx(air_c):
				c5 += 1
	spt.pose = {}
	var spt3 = DotSolid.from_doc(spt.to_doc())
	var er: bool = spt.paint_surface(90.0, air_x - 1, spt.neck - 6, Color(0, 0, 0, 0))
	note("空中に描く: 横向きで %d 画素足した (頭の後ろ x %d の外) → 見える画素 %s (90° は 3、135° は 1 以上のはず)・頭を傾けても %d (1 以上のはず)・保存して読むと %d (3 のはず)・消しゴム %s → 残り %d" % [air_n, air_x, str(air_seen), c5, spt3.adds.size(), er, spt.adds.filter(func(a): return a != null and Color(a[4]).a > 0.5).size()])
	# 出る範囲: ± 20° にすると、90° で描いたものは 75°・105° には出て、45°・135° には出ない
	spt.paint_surface(90.0, air_x - 1, spt.neck - 6, air_c)
	spt.paint_surface(90.0, air_x + 2, spt.neck - 6, air_c)
	spt.paint_reach = 20.0
	var reach_s := []
	for yv5 in [90.0, 75.0, 105.0, 45.0, 135.0, 0.0]:
		var rim: Image = spt.render(yv5)
		var c6 := 0
		for yy5 in rim.get_height():
			for xx5 in rim.get_width():
				if rim.get_pixel(xx5, yy5).is_equal_approx(air_c):
					c6 += 1
		reach_s.append("%d°:%d" % [int(yv5), c6])
	note("出る範囲 ± 20°: 90° で描いた色が見える画素 %s (90・75・105 は 1 以上、45・135・0 は 0 のはず)" % str(reach_s))
	spt.adds.clear()
	spt.spaint.clear()
	spt.touch()
	# 画面のペン: ふつうの設定 (面に塗る) で 横向きに描くと、面に色が貼られる (決めた絵は増えない)
	main.paint["solid_mode"] = 0
	var keys_before: int = spt.pics.size()
	main.view.yaw = 90.0
	var pen_n: int = main.solid_line(Vector2(spt.w * 0.5, spt.neck + 5.5), Vector2(spt.w * 0.5 + 2.0, spt.neck + 5.5))
	main.view.yaw = 0.0
	note("ペンで横向きに描く: 変わった画素 %d・置いた画素 %d (1 以上のはず)・決めた絵 %d → %d (同じはず)" % [pen_n, spt.adds.size(), keys_before, spt.pics.size()])
	# けずる: 横向きで 頭の後ろのはしを 2 画素消す → 90°・75° では透明、0° では そのまま
	spt.adds.clear()
	spt.touch()
	var before90: Image = spt.render(90.0)
	var before0: Image = spt.render(0.0)
	var cx0 := -1
	for xx6 in spt.w:
		if before90.get_pixel(xx6, spt.neck - 6).a > 0.5:
			cx0 = xx6
			break
	main.view.yaw = 90.0
	main.set_dot_tool(1)
	main._dot_press(Vector2(cx0 + 0.5, spt.neck - 5.5), MOUSE_BUTTON_LEFT)
	main._dot_drag(Vector2(cx0 + 1.5, spt.neck - 5.5))
	main._dot_release()
	main._painting = 0
	var after90: Image = spt.render(90.0)
	var after0: Image = spt.render(0.0)
	var same0 := true
	for yy6 in after0.get_height():
		for xx6 in after0.get_width():
			if not after0.get_pixel(xx6, yy6).is_equal_approx(before0.get_pixel(xx6, yy6)):
				same0 = false
	note("けずる (消しゴム): 90° の x %d・%d が 透明 %s・%s (true のはず)・正面の絵は そのまま %s" % [cx0, cx0 + 1, after90.get_pixel(cx0, spt.neck - 6).a < 0.5, after90.get_pixel(cx0 + 1, spt.neck - 6).a < 0.5, same0])
	# 描きかえた向きは、ほかの向きで描いたものを受けつけない: 90° で描く → 80° にも出る → 80° で描く → そのあと 90° で描いたものは 80° に出ない
	spt.adds.clear()
	spt.touch()
	var lk90: Image = spt.render(90.0)
	var lx := -1
	for xx8 in spt.w:
		if lk90.get_pixel(xx8, spt.neck - 6).a > 0.5:
			lx = xx8
			break
	var cnt := func(im8: Image, c8: Color) -> int:
		var n8 := 0
		for yy8 in im8.get_height():
			for xx8 in im8.get_width():
				if im8.get_pixel(xx8, yy8).is_equal_approx(c8):
					n8 += 1
		return n8
	var ca := Color(0, 1, 1, 1)
	var cb8 := Color(1, 0, 1, 1)
	var cc := Color(1, 1, 0, 1)
	spt.paint_surface(90.0, lx + 2, spt.neck - 6, ca)
	var s1: int = cnt.call(spt.render(80.0), ca)
	var before80: Image = spt.render(80.0)
	spt.paint_surface(80.0, lx + 3, spt.neck - 3, cb8)
	var after80: Image = spt.render(80.0)
	var s2: int = cnt.call(after80, ca)
	var diff8 := 0
	for yy8 in after80.get_height():
		for xx8 in after80.get_width():
			if not after80.get_pixel(xx8, yy8).is_equal_approx(before80.get_pixel(xx8, yy8)):
				diff8 += 1
	spt.paint_surface(90.0, lx + 2, spt.neck - 4, cc)
	note("描きかえた向き: 90° で描いた色が 80° に出る %d (1 以上)・80° で 1 画素描く → 80° で変わった画素 %d (1 のはず)・前からの色は残る %d (1 以上)・そのあと 90° で描いた色は 80° に出ない %d (0 のはず)・90° には出る %d・70° には出る %d" % [s1, diff8, s2, cnt.call(spt.render(80.0), cc), cnt.call(spt.render(90.0), cc), cnt.call(spt.render(75.0), cc)])
	# 1 画素描いても、ほかの画素は変わらない (ふちのすぐ外・ふちの上・中 で確かめる)
	spt.adds.clear()
	spt.touch()
	var b90: Image = spt.render(90.0)
	var edge_x7 := -1
	for xx7 in spt.w:
		if b90.get_pixel(xx7, spt.neck - 6).a > 0.5:
			edge_x7 = xx7
			break
	var react := []
	for dx7 in [-1, 0, 3]:
		spt.adds.clear()
		spt.touch()
		spt.paint_surface(90.0, edge_x7 + dx7, spt.neck - 6, Color(0, 1, 1, 1))
		var a90: Image = spt.render(90.0)
		var oth := 0
		for yy7 in a90.get_height():
			for xx7 in a90.get_width():
				if (xx7 != edge_x7 + dx7 or yy7 != spt.neck - 6) and not a90.get_pixel(xx7, yy7).is_equal_approx(b90.get_pixel(xx7, yy7)):
					oth += 1
		react.append(oth)
	spt.adds.clear()
	spt.touch()
	main.view.yaw = 0.0
	main.paint["solid_mode"] = 0
	var pic0: Image = spt.pics[0].duplicate()
	main.set_dot_tool(0)
	main._dot_press(Vector2(spt.w * 0.5, spt.neck + 4.5), MOUSE_BUTTON_LEFT)
	main._dot_release()
	main._painting = 0
	note("1 画素描く (横向き。ふちの外・ふちの上・中): ほかに変わった画素 %s ([0, 0, 0] のはず)。正面に描く: 正面の絵は そのまま %s・置いた画素 %d" % [str(react), pic0.get_data() == spt.pics[0].get_data(), spt.adds.size()])
	spt.adds.clear()
	spt.touch()
	main.view.yaw = 90.0
	# ポーズのタブ: 立体を見ているあいだは 立体のポーズになる
	var tpose: Dictionary = spt.preset("T の字")
	var run: Dictionary = spt.preset("走り")
	note("立体のポーズ: T の字 %d 部品・走り %d 部品・ばんざい %d 部品 (どれも 1 以上のはず)" % [tpose.pose.size(), run.pose.size(), spt.preset("ばんざい").pose.size()])
	# 道具: 線 → 四角 (ぬり) → バケツ。えんぴつは ななめに引いても かどの画素を置かない
	spt.adds.clear()
	spt.touch()
	main.set_dot_tool(0)
	main._dot_press(Vector2(2.5, 2.5), MOUSE_BUTTON_LEFT)
	for st6 in [Vector2(3.5, 2.5), Vector2(3.5, 3.5), Vector2(4.5, 3.5), Vector2(4.5, 4.5), Vector2(5.5, 4.5), Vector2(5.5, 5.5)]:
		main._dot_drag(st6)
	main._dot_release()
	main._painting = 0
	var pencil_n: int = spt.adds.size()
	main.set_dot_tool(5)
	main._dot_press(Vector2(1.5, 8.5), MOUSE_BUTTON_LEFT)
	main._dot_drag(Vector2(3.5, 9.5))
	main._dot_release()
	main._painting = 0
	var rect_n: int = spt.adds.size() - pencil_n
	main.set_pen_color(Color(0, 1, 0))
	main.set_dot_tool(2)
	main._dot_press(Vector2(2.5, 9.5), MOUSE_BUTTON_LEFT)
	var green := 0
	var fim6: Image = spt.render(90.0)
	for yy6 in fim6.get_height():
		for xx6 in fim6.get_width():
			if fim6.get_pixel(xx6, yy6).is_equal_approx(Color(0, 1, 0, 1)):
				green += 1
	note("道具: えんぴつで かいだん状に 7 か所 → 置いた画素 %d (かどを置かないので 4 のはず)・四角 (ぬり) 3 × 2 → %d (6 のはず)・バケツ → 緑の画素 %d (6 のはず)" % [pencil_n, rect_n, green])
	main.set_dot_tool(0)
	main.view.yaw = 0.0
	spt.spaint.clear()
	main.mark()
	# ドット直しのある向きが分かる・正面以外をまとめて消せる
	main.cur()["fix"] = {"0": {Vector2i(0, -5): Color.RED}, "270": {Vector2i(1, -5): Color.RED, Vector2i(2, -5): Color(0, 0, 0, 0)}}
	var fd: Array = main.fix_dirs()
	var cleared: int = main.clear_fix_all(true)
	note("ドット直しのある向き %s → 正面以外を消す: %d 方向消えた・残り %s ([[0, 1]] のはず)" % [str(fd), cleared, str(main.fix_dirs())])
	main.cur()["fix"] = {}
	# 腕を はなしても 1 画素の棒にならない
	var so2 = main.solid
	so2.pose = {DotSolid.ARM_B: Quaternion(Vector3.BACK, deg_to_rad(60.0))}
	var arm_im: Image = so2.render(0.0)
	var arm_n := 0
	var arm_seen := {}
	for yy in arm_im.get_height():
		for xx in arm_im.get_width():
			if so2.hit_part(xx, yy) in [DotSolid.ARM_B, DotSolid.FORE_B]:
				arm_n += 1
				arm_seen[yy] = arm_seen.get(yy, 0) + 1
	so2.pose = main.cur().get("sp", {})
	note("腕を横へ 60°: 腕の画素 %d・出ている行 %d (1 行あたり %.1f 画素。1.5 より多いはず)" % [arm_n, arm_seen.size(), float(arm_n) / maxf(arm_seen.size(), 1.0)])
	main._tabs_r.current_tab = 2
	main.mark()
	await wait(0.5)
	var m3: ArrayMesh = main.solid.make_mesh(0.05, 60.0)
	var skin_faces := 0
	var cols3: PackedColorArray = m3.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c3 in cols3:
		if main.solid._is_skin(c3.to_rgba32()):
			skin_faces += 1
	note("3D の網目 (60° から見る・顔の層): 肌の色の頂点 %d (1 以上のはず)" % skin_faces)
	note("3D タブ: 立体の網目の頂点 %d (1 以上のはず)" % (main._mesh3d.mesh.surface_get_array_len(0) if main._mesh3d.mesh != null and main._mesh3d.mesh.get_surface_count() > 0 else 0))
	left.current_tab = main._solid_tab
	await shot("06j_solid_3d")
	left.current_tab = main._paint_tab
	main.export_sheet(out.path_join("solid8.png"), 8)

	# 保存 → 開く
	var path := out.path_join("test.dotg.json")
	main.save_doc(path)
	main.load_doc(path)      # 1 回読みなおしてから比べる (JSON を通ると 2 が 2.0 になるなど、書き方だけ変わるので)
	var a := JSON.stringify(main.to_doc())
	main.set_heads(7.5, true)
	main.load_doc(path)
	await wait(0.4)
	note("保存して開く: " + ("同じ" if JSON.stringify(main.to_doc()) == a else "ちがう"))

	# シート
	main.poses.append(main.make_pose("歩き 1", main.Poses.named("歩き 1", main.body.arm_angle, main.Poses.hang_for(main.body.heads))))
	main.poses.append(main.make_pose("すわる", main.Poses.named("すわる", main.body.arm_angle, main.Poses.hang_for(main.body.heads))))
	main._sync_pose_ui()
	main.export_sheet(out.path_join("sheet8.png"), 8)
	note("シート: " + str(FileAccess.file_exists(out.path_join("sheet8.png"))))

	# penInk
	main._tabs_r.current_tab = 1
	main.view.yaw = 45.0
	main._sync("yaw", 45.0)
	main.mark("pose")
	await wait(0.3)
	main.penink_draw()
	var t := 0.0
	while main._pk_tex.texture == null and t < 45.0:
		await wait(0.5)
		t += 0.5
	note("penInk: %s (%.1f 秒待った) %s" % ["描けた" if main._pk_tex.texture != null else "描けなかった", t, main._pk_status.text])
	await wait(0.3)
	await shot("07_penink")
	main._pk.stop()

	var f := FileAccess.open(out.path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	main.get_tree().quit()
