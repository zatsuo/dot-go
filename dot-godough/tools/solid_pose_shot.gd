## 確かめ用: ドット絵から作った立体を部品 (頭・体・腕・脚) に分けて、ポーズをつけて 8 方向で描く (画面なしで動く)。
##  1 段目 = 部品の色分け (正面) と、立ち。2 段目から = 歩き 1・歩き 2・すわる・おじぎ・手をあげる
##  上半分 = 青髪 (表の横・後ろの絵も使う)、下半分 = 茶色のキャラ (正面 1 枚だけ)
##   Godot --headless --path . -s tools/solid_pose_shot.gd -- <出力.png>
extends SceneTree

const W := 30
const H := 42


func cell(sheet: Image, r: Rect2i) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 4 - r.size.y))
	return im


func _init() -> void:
	var out := "user://solid_pose.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var Solid = load("res://scripts/solid.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var names := ["立ち", "歩き 1", "歩き 2", "すわる", "ゆかにすわる", "おじぎ", "手をあげる"]
	var big := Image.create_empty(W * 9, H * names.size() * 2, false, Image.FORMAT_RGBA8)
	big.fill(Color("#8a8f9a"))
	for ci in 2:
		var so = Solid.new()
		if ci == 0:
			so.set_front(cell(sheet, Rect2i(4, 128, 18, 32)))
			so.set_pic(90, cell(sheet, Rect2i(34, 128, 15, 32)))
			so.set_pic(270, cell(sheet, Rect2i(60, 128, 15, 32)))
			so.set_pic(180, cell(sheet, Rect2i(86, 128, 15, 32)))
		else:
			so.set_front(cell(sheet, Rect2i(161, 64, 16, 32)))
		so.ensure()
		# 部品の色分け
		var pm := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
		var count := [0, 0, 0, 0, 0, 0, 0]
		for y in H:
			for x in W:
				var p: int = so.part_at(x, y)
				if p > 0 and so.pics[0].get_pixel(x, y).a > 0.5:
					pm.set_pixel(x, y, Color(Solid.PART_COLORS[p]))
					count[p] += 1
		big.blend_rect(pm, Rect2i(0, 0, W, H), Vector2i(0, ci * names.size() * H))
		print("キャラ %d の部品 (画素): 頭 %d・体 %d・腕 %d / %d・脚 %d / %d" % [ci, count[1], count[2], count[3], count[4], count[5], count[6]])
		for ni in names.size():
			var pr: Dictionary = so.preset(names[ni])
			so.pose = pr.pose
			so.root = pr.root
			var t0 := Time.get_ticks_msec()
			for d in 8:
				big.blend_rect(so.render(d * 45.0), Rect2i(0, 0, W, H), Vector2i((d + 1) * W, (ci * names.size() + ni) * H))
			print("  %s: 8 方向で %d ミリ秒" % [names[ni], Time.get_ticks_msec() - t0])
		# IK: 手の先を 正面の絵で (5, -6) 動かす → 先がそこへ行く。足の先を 横の絵で (4, -2)
		so.pose = {}
		so.root = Vector3.ZERO
		for tst in [[Solid.FORE_B, 0.0, Vector2(5, -6)], [Solid.SHIN_A, 90.0, Vector2(4, -2)]]:
			for hd in so.handles(tst[1]):
				if hd.part == tst[0]:
					var to: Vector2 = hd.tip + tst[2]
					so.drag_ik(tst[0], tst[1], to)
					for h2 in so.handles(tst[1]):
						if h2.part == tst[0]:
							print("  IK %s を %s 動かす: 目標 %s → 着いた所 %s" % [Solid.PART_NAMES[tst[0]], tst[2], to, h2.tip])
	big.resize(big.get_width() * 4, big.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png(out)
	print("-> ", out)
	quit()
