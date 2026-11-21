extends RefCounted
## 自己テスト: Run.bat -- --selftest <出力のフォルダ>。画面を実際に動かして、数字と絵を出す

var main
var out := ""


func note(t: String) -> void:
	print("[selftest] ", t)


func wait(sec: float) -> void:
	await main.get_tree().create_timer(sec).timeout


func shot(name: String) -> void:
	await wait(0.6)
	main.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func count(im: Image, c: Color) -> int:
	var n := 0
	for y in im.get_height():
		for x in im.get_width():
			if im.get_pixel(x, y).is_equal_approx(c):
				n += 1
	return n


func run(m, dir: String) -> void:
	main = m
	out = dir
	DirAccess.make_dir_recursive_absolute(dir)
	await wait(0.5)
	# 絵を開く → 1 体を選ぶ → 正面にして立体を作る → 横・後ろの絵も足す
	var ok: bool = main.load_sheet(ProjectSettings.globalize_path("res://samples/sample_sheet.png"))
	await shot("01_sheet")
	var isl: Rect2i = main.pick_island(Vector2i(170, 80))
	var r: Rect2i = main.set_sheet_rect(Rect2i(4, 128, 18, 32))
	note("クリックで選ぶ (はなれた 1 体): %s・囲んで選ぶ: %s" % [isl, r])
	var made: bool = main.use_cell(0)
	note("絵を開く %s・1 体を選ぶ %s・立体を作る %s (紙 %d × %d)" % [ok, r, made, main.solid.w, main.solid.h])
	var est90: Image = main.render(90.0)
	main.set_sheet_rect(Rect2i(34, 128, 15, 32))
	var side_ok: bool = main.use_cell(90)
	main.set_sheet_rect(Rect2i(86, 128, 15, 32))
	var back_ok: bool = main.use_cell(180)
	var real90: Image = main.render(90.0)
	var same := 0
	for y in est90.get_height():
		for x in est90.get_width():
			if est90.get_pixel(x, y).is_equal_approx(real90.get_pixel(x, y)):
				same += 1
	note("横・後ろの絵: %s・%s。決めた絵 %s。横の絵が 推定と同じ画素 %d / %d (ちがうはず)" % [side_ok, back_ok, str(main.solid.pics.keys()), same, est90.get_width() * est90.get_height()])
	main.set_yaw(0.0)
	await shot("02_front")
	# 描く: えんぴつ → 消しゴム (けずる) → バケツ。もとの絵は変わらない
	var pic0: PackedByteArray = main.solid.pics[0].get_data()
	main.set_pen(Color(1, 0, 1))
	main.set_tool(0)
	var cx: float = main.solid.w * 0.5
	var ny: float = main.solid.neck + 5.5
	main._press(Vector2(cx - 1.5, ny), MOUSE_BUTTON_LEFT)
	main._drag(Vector2(cx + 1.5, ny), Vector2(3, 0), MOUSE_BUTTON_LEFT)
	main._release(Vector2(cx + 1.5, ny), MOUSE_BUTTON_LEFT)
	var drawn: int = count(main.render(0.0), Color(1, 0, 1, 1))
	main.set_tool(1)
	main._press(Vector2(cx - 1.5, ny), MOUSE_BUTTON_LEFT)
	main._release(Vector2(cx - 1.5, ny), MOUSE_BUTTON_LEFT)
	var erased: bool = main.render(0.0).get_pixel(int(cx - 1.5), int(ny)).a < 0.5
	note("描く: えんぴつで 4 画素 → %d (4 のはず)・消しゴムで 1 画素けずる → 透明 %s・もとの正面の絵は そのまま %s・ほかの向き (90°) には出ない %d (0 のはず)" % [drawn, erased, pic0 == main.solid.pics[0].get_data(), count(main.render(90.0), Color(1, 0, 1, 1))])
	main.undo()
	main.undo()
	note("元に戻す × 2: 置いた・けずった画素 %d (0 のはず)" % main.solid.adds.size())
	# 部品を塗る
	main._tabs.current_tab = 1
	var p_before: int = main.solid.part_at(int(cx), main.solid.neck + 3)
	main.part_sel = 3
	main._press(Vector2(cx, main.solid.neck + 3.5), MOUSE_BUTTON_LEFT)
	main._release(Vector2(cx, main.solid.neck + 3.5), MOUSE_BUTTON_LEFT)
	note("部品を塗る: %s → %s (腕 (左) のはず)" % [DotSolid.PART_NAMES[p_before], DotSolid.PART_NAMES[main.solid.part_at(int(cx), main.solid.neck + 3)]])
	await shot("03_parts")
	main.undo()
	# ポーズ (確かめ用)
	main._tabs.current_tab = 2
	var stand: Image = main.render(0.0)
	main.apply_preset("ばんざい")
	var dif := 0
	var pim: Image = main.render(0.0)
	for y in pim.get_height():
		for x in pim.get_width():
			if not pim.get_pixel(x, y).is_equal_approx(stand.get_pixel(x, y)):
				dif += 1
	note("ポーズ「ばんざい」: 立ちと ちがう画素 %d (1 以上のはず)" % dif)
	await shot("04_pose")
	# 腕を動かしたとき、手の色 (肌・手のかげ) が 体に残らない
	var so: DotSolid = main.solid
	var left := 0
	for nm in ["T の字", "ばんざい", "走り", "歩き 1", "手をあげる"]:
		so.pose = so.preset(nm).pose
		for yw in [0.0, 30.0, 45.0, 90.0, 180.0, 270.0]:
			var him: Image = so.render(yw)
			for y in range(so.neck + 2, so.h):
				for x in so.w:
					var hc := him.get_pixel(x, y)
					if hc.a > 0.5 and so._is_hand(hc.to_rgba32()) and not (so._last_hp[x + so.w * y] in [1, 3, 4, 7, 8]):
						left += 1
	so.pose = {}
	note("腕を動かしたとき 体に残る 手の色の画素: %d (0 のはず)・手のかげの色 %d 色 (1 のはず)" % [left, so._hand_cols.size()])
	# 設定のタブで 絵をクリックしても 画素は置かれない
	main._tabs.current_tab = 4
	var n0: int = main.solid.adds.size()
	main._press(Vector2(cx, ny), MOUSE_BUTTON_LEFT)
	main._release(Vector2(cx, ny), MOUSE_BUTTON_LEFT)
	note("設定のタブで 絵をクリック: 置いた画素 %d (0 のはず)" % (main.solid.adds.size() - n0))
	main._tabs.current_tab = 0
	# 保存して開く・書き出し
	var doc1: String = JSON.stringify(main.to_doc())
	var saved: bool = main.save_doc(out.path_join("test.dotmodel.json"))
	var opened: bool = main.open_any(out.path_join("test.dotmodel.json"))
	note("保存 %s・開く %s・中身 %s" % [saved, opened, "同じ" if JSON.stringify(main.to_doc()) == doc1 else "ちがう"])
	note("書き出し: PNG %s・8 方向 %s" % [main.export_png(out.path_join("one.png")), main.export_sheet(out.path_join("eight.png"))])
	# 8 方向の歩き: シート (8 行 × 4 列)・Aseprite (タグ 8 つ)・GIF。コマが紙のはしで切れていないか (はしの画素) も数える
	var ok_png: bool = main.export_walk(out.path_join("walk8.png"))
	var ok_ase: bool = main.export_walk(out.path_join("walk8.aseprite"))
	var ok_gif: bool = main.export_walk(out.path_join("walk8.gif"))
	var wsheet := Image.load_from_file(out.path_join("walk8.png"))
	var fw: int = main.solid.w
	var fh: int = main.solid.h
	var edge := 0
	var moving := 0
	for d in 8:
		var f0 := wsheet.get_region(Rect2i(0, d * fh, fw, fh))
		for f in 4:
			var fr := wsheet.get_region(Rect2i(f * fw, d * fh, fw, fh))
			for y in fh:
				for x in fw:
					if fr.get_pixel(x, y).a > 0.5 and (x == 0 or x == fw - 1 or y == 0):
						edge += 1
			if f > 0 and fr.get_data() != f0.get_data():
				moving += 1
	var wj = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("walk8.json")))
	note("歩き 8 方向: シート %s (%d × %d = %d 列 × %d 行)・Aseprite %s・GIF %s・json の行 %d・1 コマ目とちがうコマ %d / 24 (24 のはず)・紙のはしの画素 %d (0 のはず)" % [
			ok_png, wsheet.get_width(), wsheet.get_height(), wsheet.get_width() / fw, wsheet.get_height() / fh, ok_ase, ok_gif, wj.rows.size(), moving, edge])
	main.set_yaw(45.0)
	await wait(1.5)
	await shot("05_draw")
	note("おわり")
	main.get_tree().quit()
