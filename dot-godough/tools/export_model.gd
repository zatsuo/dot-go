## 確かめ用: お手本の青髪のキャラ (正面・横・後ろの絵つき) を ドット絵モデルに書き出す (画面なしで動く)
##   Godot --headless --path . -s tools/export_model.gd -- <出力.dotmodel.json>
extends SceneTree

const W := 32
const H := 40


func cell(sheet: Image, r: Rect2i) -> Image:
	var used := sheet.get_region(r).get_used_rect()
	r = Rect2i(r.position + used.position, used.size)
	var im := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, r, Vector2i(W / 2 - r.size.x / 2, H - 4 - r.size.y))
	return im


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var Solid = load("res://scripts/solid.gd")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://refs/sample_sheet.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var so = Solid.new()
	so.set_front(cell(sheet, Rect2i(4, 128, 18, 32)))
	so.set_pic(90, cell(sheet, Rect2i(34, 128, 15, 32)))
	so.set_pic(270, cell(sheet, Rect2i(60, 128, 15, 32)))
	so.set_pic(180, cell(sheet, Rect2i(86, 128, 15, 32)))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"app": "dot-godough", "kind": "model", "version": 1, "name": "青髪", "solid": so.to_doc()}, " "))
	f.close()
	print("-> ", out)
	quit()
