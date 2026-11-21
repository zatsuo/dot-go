extends RefCounted
## 自己テスト: Run.bat -- --selftest <出力のフォルダ>。画面を実際に動かして、数字と絵を出す

var main
var out := ""


func note(t: String) -> void:
	print("[selftest] ", t)


func wait(sec: float) -> void:
	await main.get_tree().create_timer(sec).timeout


func shot(name: String) -> void:
	await wait(0.4)
	main.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func diff(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				n += 1
	return n


func run(m, dir: String) -> void:
	main = m
	out = dir
	DirAccess.make_dir_recursive_absolute(dir)
	await wait(0.5)
	var ok: bool = main.load_model(ProjectSettings.globalize_path("res://samples/aogami.dotmodel.json"))
	note("モデルを開く: %s (%d × %d・絵 %s)" % [ok, main.model.w, main.model.h, str(main.model.pics.keys())])
	await shot("01_model")
	# 歩きを足す → コマごとに絵がちがう
	main.make_walk()
	var c: Dictionary = main.clip()
	var d01: int = diff(main.frame_image(main.clip_i, 0, 90.0), main.frame_image(main.clip_i, 1, 90.0))
	note("歩き: %d コマ・キー %d。横向きで コマ 1 と 2 のちがい %d 画素 (1 以上のはず)" % [int(c.len), c.keys.size(), d01])
	# 手の先をつまむ (IK) → キーが打たれて 絵が変わる
	main.add_clip("手をふる")
	main.set_len(6)
	main.set_frame(0)
	main.add_key()
	main.set_frame(3)
	var before: Image = main.frame_image(main.clip_i, 3, 0.0).duplicate()
	var tip := Vector2.ZERO
	for hd in main.model.handles(0.0):
		if hd.part == DotSolid.FORE_B:
			tip = hd.tip
	main._on_press(tip, MOUSE_BUTTON_LEFT)
	main._on_drag(tip + Vector2(5, -8), Vector2(5, -8), MOUSE_BUTTON_LEFT)
	main._on_release(tip + Vector2(5, -8), MOUSE_BUTTON_LEFT)
	var got := Vector2.ZERO
	var kp: Dictionary = main.pose_at(main.clip(), 3)
	main.model.pose = kp.pose
	main.model.root = kp.root
	for hd in main.model.handles(0.0):
		if hd.part == DotSolid.FORE_B:
			got = hd.tip
	note("手の先をつまむ: %s → %s (目標 %s)・コマ 4 にキー %s・絵のちがい %d 画素" % [tip, got, tip + Vector2(5, -8), main.clip().keys.has(3), diff(before, main.frame_image(main.clip_i, 3, 0.0))])
	# あいだのコマ: 切 = 前のキーのまま、入 = 混ぜる
	var hold: int = diff(main.frame_image(main.clip_i, 1, 0.0), main.frame_image(main.clip_i, 0, 0.0))
	main.clip().smooth = true
	main.invalidate()
	var mixed: int = diff(main.frame_image(main.clip_i, 1, 0.0), main.frame_image(main.clip_i, 0, 0.0))
	note("あいだのコマ 2: 混ぜない → コマ 1 とのちがい %d (0 のはず)・混ぜる → %d (1 以上のはず)" % [hold, mixed])
	# 写す・左右を入れかえて貼る・元に戻す
	main.copy_key()
	main.set_frame(5)
	main.paste_key(true)
	var mk: Dictionary = main.clip().keys[5]
	note("左右を入れかえて貼る: 左腕にキー %s・右腕にキー %s (true / false のはず)" % [mk.pose.has(DotSolid.ARM_A), mk.pose.has(DotSolid.ARM_B)])
	main.undo()
	note("元に戻す: コマ 6 のキー %s (false のはず)" % main.clip().keys.has(5))
	main.set_frame(3)
	main.onion = true
	await shot("02_wave")
	main.onion = false
	# コマを入れる・取る
	main.insert_frame()
	var n1 := int(main.clip().len)
	main.delete_frame()
	note("コマを入れる → %d コマ、取る → %d コマ。キーのあるコマ %s" % [n1, int(main.clip().len), str(main.clip().keys.keys())])
	# 紙の大きさ: 手を上げると切れる → 余白を足すと切れない
	main.set_frame(3)
	main.apply_preset("手をあげる")
	main.nudge(0, 6)
	var cut_n := 0
	var im0: Image = main.frame_image(main.clip_i, 3, 0.0)
	for x in im0.get_width():
		if im0.get_pixel(x, 0).a > 0.5:
			cut_n += 1
	var w0: int = main.model.w
	var h0: int = main.model.h
	main.fit_pad()
	var im1: Image = main.frame_image(main.clip_i, 3, 0.0)
	var edge_n := 0
	for x in im1.get_width():
		if im1.get_pixel(x, 0).a > 0.5:
			edge_n += 1
	for y in im1.get_height():
		if im1.get_pixel(0, y).a > 0.5 or im1.get_pixel(im1.get_width() - 1, y).a > 0.5:
			edge_n += 1
	note("紙の大きさ: 余白なし %d × %d で 上のはしの画素 %d (切れている) → はみ出さない大きさ %d × %d (余白 %s) で はしの画素 %d (0 のはず)" % [w0, h0, cut_n, main.model.w, main.model.h, str(main.pad), edge_n])
	await shot("02b_pad")
	# 保存して開く
	var doc1: String = JSON.stringify(main.to_doc())
	main.save_doc(out.path_join("test.dotanim.json"))
	main.open_any(out.path_join("test.dotanim.json"))
	note("保存して開く: %s・アニメ %d つ" % ["同じ" if JSON.stringify(main.to_doc()) == doc1 else "ちがう", main.clips.size()])
	# 書き出し
	main.clip_i = 1
	main._sync_clip_ui()
	var g1: bool = main.export_gif(out.path_join("walk.gif"), false)
	var g8: bool = main.export_gif(out.path_join("walk8.gif"), true)
	var a1: bool = main.export_ase(out.path_join("walk.aseprite"), false, false)
	var a8: bool = main.export_ase(out.path_join("all.aseprite"), true, true)
	var sh: bool = main.export_sheet(out.path_join("walk_sheet.png"))
	note("書き出し: GIF %s・GIF 8 方向 %s・Aseprite %s (%d バイト)・Aseprite 全部 %s (%d バイト)・シート %s" % [g1, g8, a1,
			FileAccess.get_file_as_bytes(out.path_join("walk.aseprite")).size(), a8, FileAccess.get_file_as_bytes(out.path_join("all.aseprite")).size(), sh])
	var t1: bool = main.export_turn(out.path_join("turn.gif"), 16, false)
	var t2: bool = main.export_turn(out.path_join("turn_walk.aseprite"), 16, true)
	note("ぐるっと一周: GIF %s (%d バイト)・歩きながら Aseprite %s (%d バイト)" % [t1, FileAccess.get_file_as_bytes(out.path_join("turn.gif")).size(), t2, FileAccess.get_file_as_bytes(out.path_join("turn_walk.aseprite")).size()])
	main.set_yaw(90.0)
	main.set_frame(0)
	await wait(1.5)
	await shot("03_walk")
	main.play(true)
	await wait(1.0)
	note("再生: 動いている %s・いまのコマ %d" % [main.playing, main.frame + 1])
	main.play(false)
	note("おわり")
	main.get_tree().quit()
