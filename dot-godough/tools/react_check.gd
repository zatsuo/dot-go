## 確かめ用: 1 画素 描く / 消す と、その画素のほかに 何画素変わるか (0 のはず)。向き 3 つ × 高さ 3 つ × (ふちの外・ふちの上・中) × (描く・消す)
##   Godot --headless --path . -s tools/react_check.gd -- <キャラ.dotg.json>
extends SceneTree
func _init() -> void:
	var Solid = load("res://scripts/solid.gd")
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var so = Solid.from_doc(d.solid)
	so.ensure()
	for yaw in [60.0, 20.0, 150.0]:
		var b: Image = so.render(yaw)
		var res := []
		for y in [so.neck - 6, so.neck + 5, so.neck + 9]:
			var ex := -1
			for x in so.w:
				if b.get_pixel(x, y).a > 0.5:
					ex = x
					break
			for dx in [-1, 0, 2]:
				for erase in [false, true]:
					so.adds.clear()
					so.touch()
					so.paint_surface(yaw, ex + dx, y, Color(0, 0, 0, 0) if erase else Color(0, 1, 1, 1))
					var a: Image = so.render(yaw)
					var oth := 0
					for yy in so.h:
						for xx in so.w:
							if (xx != ex + dx or yy != y) and not a.get_pixel(xx, yy).is_equal_approx(b.get_pixel(xx, yy)):
								oth += 1
					res.append(oth)
		print("%d°: ほかに変わった画素 %s" % [int(yaw), str(res)])
	quit()
