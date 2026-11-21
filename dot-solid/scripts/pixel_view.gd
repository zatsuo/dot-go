class_name DotView
extends Control
## ドット絵を拡大して見せる窓。マウスは画素の座標 (小数まで) で知らせる。
## 左 = つまむ / 何もない所で向きを回す、右 = もどす、中ボタン = 動かす、ホイール = 拡大 (関節の上ではひねる)

signal pressed(px: Vector2, button: int)
signal dragged(px: Vector2, rel: Vector2, button: int)
signal released(px: Vector2, button: int)
signal hovered(px: Vector2)

var tex: ImageTexture
var img_size := Vector2i(64, 64)
var zoom := 8
var pan := Vector2.ZERO
var bg := Color("#8a8f9a")
var checker := true
var grid := false
var overlay: Callable            ## 上にかぶせて描くもの (関節の点など)。(この窓) を渡す
var wheel_handler: Callable      ## (px, 向き) → 使ったら true (使わなければ拡大)
var _button := 0
var _panning := false


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func set_image(img: Image) -> void:
	img_size = img.get_size()
	if tex == null or tex.get_size() != Vector2(img_size):
		tex = ImageTexture.create_from_image(img)
	else:
		tex.update(img)
	queue_redraw()


func origin() -> Vector2:
	return (size * 0.5 + pan - Vector2(img_size) * zoom * 0.5).round()


func to_px(p: Vector2) -> Vector2:
	return (p - origin()) / float(zoom)


func to_screen(px: Vector2) -> Vector2:
	return origin() + px * zoom


func fit() -> void:
	var z := int(floor(minf((size.x - 40.0) / img_size.x, (size.y - 40.0) / img_size.y)))
	zoom = clampi(z, 1, 24)
	pan = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#3a3d46"))
	var o := origin()
	var r := Rect2(o, Vector2(img_size) * zoom)
	draw_rect(r, bg)
	if checker:
		var c2 := bg.darkened(0.08)
		var step := 8
		for y in range(0, img_size.y, step):
			for x in range(0, img_size.x, step):
				if ((x / step) + (y / step)) % 2 == 1:
					var w := mini(step, img_size.x - x)
					var h := mini(step, img_size.y - y)
					draw_rect(Rect2(o + Vector2(x, y) * zoom, Vector2(w, h) * zoom), c2)
	if tex:
		draw_texture_rect(tex, r, false)
	if grid and zoom >= 6:
		var gc := Color(0, 0, 0, 0.12)
		for x in range(1, img_size.x):
			draw_line(o + Vector2(x * zoom, 0), o + Vector2(x * zoom, r.size.y), gc)
		for y in range(1, img_size.y):
			draw_line(o + Vector2(0, y * zoom), o + Vector2(r.size.x, y * zoom), gc)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.5), false, 1.0)
	if overlay.is_valid():
		overlay.call(self)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var px := to_px(e.position)
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not e.pressed:
				return
			var dir := 1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if wheel_handler.is_valid() and wheel_handler.call(px, dir):
				accept_event()
				return
			var before := to_px(e.position)
			zoom = clampi(zoom + dir, 1, 32)
			pan += (to_screen(before) - e.position) * -1.0
			queue_redraw()
			accept_event()
		elif e.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = e.pressed
		elif e.pressed:
			_button = e.button_index
			grab_focus()
			pressed.emit(px, e.button_index)
		else:
			if _button == e.button_index:
				_button = 0
			released.emit(px, e.button_index)
	elif e is InputEventMouseMotion:
		if _panning:
			pan += e.relative
			queue_redraw()
		elif _button != 0:
			dragged.emit(to_px(e.position), e.relative / float(zoom), _button)
		else:
			hovered.emit(to_px(e.position))
