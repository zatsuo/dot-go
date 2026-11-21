## 確かめ用: 体を作って penInk 用のフォルダに書き出す (画面なしで動く)。
##   Godot --headless --path . -s tools/export_penink.gd -- <フォルダ> <名前> [heads=3] [体型の数値...]
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var plain := []
	var body := {}
	var heads := 3.0
	for a in args:
		if "=" in a:
			var kv := a.split("=")
			if kv[0] == "heads":
				heads = float(kv[1])
			else:
				body[kv[0]] = float(kv[1])
		else:
			plain.append(a)
	var core = load("res://core/DotCore.cs").new()
	var s: Dictionary = core.ForHeads(heads)
	for k in body:
		s[k] = body[k]
	var info: Dictionary = core.Build(s, 72.0, [])
	var dir: String = plain[0]
	var name: String = plain[1]
	var err: String = core.ExportPenink(dir.path_join(name), name)
	print("verts %d  -> %s  %s" % [info.verts, dir.path_join(name), "OK" if err == "" else err])
	quit()
