## The look of Windows XP (Luna, blue), built in code: colours, a theme and
## the little pictures (button faces, check marks, arrows) drawn pixel by pixel.
extends RefCounted

const FACE := Color("#ECE9D8")          # dialog face
const FACE_DARK := Color("#ACA899")     # control shadow
const EDGE := Color("#7F9DB9")          # edit box border
const BTN_EDGE := Color("#003C74")      # button border
const SELECT := Color("#316AC5")        # selection blue
const TEXT := Color("#000000")
const TEXT_OFF := Color("#ACA899")
const GROUP_TITLE := Color("#0046D5")
const TASK_TOP := Color("#7BA2E7")      # task pane background
const TASK_BOTTOM := Color("#6375D6")
const TASK_HEAD := Color("#215DC6")
const TASK_BODY := Color("#D6DFF7")
const TITLE_STOPS := [[0.0, "#3D95FF"], [0.12, "#0A6AF0"], [0.5, "#0058E6"], [0.85, "#0054E0"], [1.0, "#0040C0"]]
const TITLE_OFF := [[0.0, "#9DB9EB"], [0.5, "#7A96DF"], [1.0, "#7990D8"]]


static func font(bold := false) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["MS UI Gothic", "Tahoma", "Meiryo UI"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	if bold:
		f.font_weight = 700
	return f


# --------------------------------------------------------------------- pictures

static func grad(stops: Array, t: float) -> Color:
	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if t <= b[0]:
			return Color(a[1]).lerp(Color(b[1]), (t - a[0]) / max(b[0] - a[0], 0.0001))
	return Color(stops[-1][1])


## A rounded box with a vertical gradient, the shape of every XP button.
static func rounded(w: int, h: int, edge: Color, stops: Array, glow: Color = Color(0, 0, 0, 0),
		r := 2) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var c := grad(stops, float(y) / max(h - 1, 1))
		for x in w:
			var cx: int = min(x, w - 1 - x)
			var cy: int = min(y, h - 1 - y)
			if cx + cy < r - 1:
				continue                                   # cut corner
			if cx == 0 or cy == 0 or cx + cy == r - 1:
				img.set_pixel(x, y, edge)
			elif glow.a > 0.0 and (cx == 1 or cy == 1 or cx + cy == r):
				img.set_pixel(x, y, glow)
			elif glow.a > 0.0 and (cx == 2 or cy == 2):
				img.set_pixel(x, y, glow.lerp(c, 0.5))
			else:
				img.set_pixel(x, y, c)
	return img


static func tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func box_tex(img: Image, m := 4) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex(img)
	s.texture_margin_left = m
	s.texture_margin_right = m
	s.texture_margin_top = m
	s.texture_margin_bottom = m
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), bw := 1, radius := 0,
		pad := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = max(pad - 2, 1)
	s.content_margin_bottom = max(pad - 2, 1)
	s.anti_aliasing = false
	return s


static func check_img(checked: bool, radio := false, off := false) -> Image:
	var n := 13
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color("#1C5180") if not off else Color("#CAC8BB")
	var c := Vector2(6, 6)
	for y in n:
		for x in n:
			var inside := true
			var border := x == 0 or y == 0 or x == n - 1 or y == n - 1
			if radio:
				var d := Vector2(x, y).distance_to(c)
				inside = d <= 6.4
				border = d > 5.2 and inside
			if not inside:
				continue
			if border:
				img.set_pixel(x, y, edge)
			else:
				var t := float(x + y) / (2.0 * n)
				img.set_pixel(x, y, Color("#DCDCD7").lerp(Color("#FFFFFF"), t) if not off else Color("#F4F4F0"))
	if checked:
		var ink := Color("#21A121") if not off else Color("#CAC8BB")
		if radio:
			for y in range(4, 9):
				for x in range(4, 9):
					if Vector2(x, y).distance_to(c) <= 2.4:
						img.set_pixel(x, y, ink)
		else:
			var pts := [[3, 5], [4, 6], [5, 7], [6, 6], [7, 5], [8, 4], [9, 3]]
			for p in pts:
				for k in 3:
					img.set_pixel(p[0], p[1] + k, ink)
	return img


static func arrow_img(dir: String, w := 9, h := 9, col := Color("#4D6185")) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for k in 4:
		for j in range(k, 7 - k):
			var x := 1 + j
			var y := 2 + k
			match dir:
				"down": img.set_pixel(x, y, col)
				"up": img.set_pixel(x, h - 1 - y, col)
				"right": img.set_pixel(y, x, col)
				"left": img.set_pixel(w - 1 - y, x, col)
	return img


## The trackbar thumb: a little pointed tab.
static func thumb_img(hot := false) -> Image:
	var w := 11
	var h := 21
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color("#1C5180")
	for y in h:
		var half: float = 5.0 if y < h - 6 else 5.0 - (y - (h - 6)) * 1.0
		for x in w:
			var dx: float = abs(x - 5)
			if dx > half + 0.01:
				continue
			var border: bool = dx > half - 1.0 or y == 0
			var c := Color("#FFFFFF").lerp(Color("#E3E3DB"), float(y) / h)
			if border:
				c = edge
			elif hot and (dx > half - 2.0 or y == 1):
				c = Color("#F9B342")
			elif y < 2 or (y >= 2 and dx > half - 2.0 and x < 5):
				c = Color("#21A121").lerp(Color("#FFFFFF"), 0.35) if y < 2 else c
			img.set_pixel(x, y, c)
	return img


static func close_img(hot := false) -> Image:
	var img := rounded(21, 21, Color("#FFFFFF"),
		[[0.0, "#E88C6E" if not hot else "#F2A285"], [0.5, "#D8502C" if not hot else "#E86A44"], [1.0, "#C23B17"]], Color(0, 0, 0, 0), 3)
	for k in range(6, 15):
		for t in 2:
			img.set_pixel(k + t - 1 if k + t - 1 < 21 else k, k, Color.WHITE)
			img.set_pixel(20 - k - t + 1 if 20 - k - t + 1 >= 0 else k, k, Color.WHITE)
	return img


static func caption_btn_img(kind: String, hot := false) -> Image:
	var img := rounded(21, 21, Color("#FFFFFF"),
		[[0.0, "#5A9BFB" if not hot else "#7EB4FF"], [0.5, "#2D6FEC" if not hot else "#4789F7"], [1.0, "#1E57D6"]], Color(0, 0, 0, 0), 3)
	var W := Color.WHITE
	match kind:
		"min":
			for x in range(5, 12):
				for y in range(13, 16):
					img.set_pixel(x, y, W)
		"max":
			for x in range(5, 16):
				for y in range(5, 16):
					var edge: bool = x == 5 or x == 15 or y == 15 or y <= 7
					if edge:
						img.set_pixel(x, y, W)
		"restore":
			for x in range(5, 13):
				for y in range(8, 16):
					if x == 5 or x == 12 or y == 15 or y <= 9:
						img.set_pixel(x, y, W)
			for x in range(8, 16):
				for y in range(5, 12):
					if (x == 15 or y <= 6 or (y == 11 and x > 12)) and not (x < 13 and y > 7):
						img.set_pixel(x, y, W)
	return img


# ------------------------------------------------------------------- the theme

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 12
	var bold := font(true)

	# buttons
	var normal := rounded(18, 23, BTN_EDGE, [[0.0, "#FFFFFF"], [0.85, "#ECEBE6"], [1.0, "#D6D0C5"]], Color(0, 0, 0, 0), 3)
	var hover := rounded(18, 23, BTN_EDGE, [[0.0, "#FFFFFF"], [0.85, "#ECEBE6"], [1.0, "#D6D0C5"]], Color("#F9B342"), 3)
	var pressed := rounded(18, 23, BTN_EDGE, [[0.0, "#CDCAC3"], [0.2, "#E3E2DA"], [1.0, "#F1F0EA"]], Color(0, 0, 0, 0), 3)
	var focus_in := rounded(18, 23, BTN_EDGE, [[0.0, "#FFFFFF"], [0.85, "#ECEBE6"], [1.0, "#D6D0C5"]], Color("#9DB9EB"), 3)
	var disabled := rounded(18, 23, Color("#C9C7BA"), [[0.0, "#F5F4EA"], [1.0, "#F5F4EA"]], Color(0, 0, 0, 0), 3)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, box_tex(normal))
		t.set_stylebox("hover", cls, box_tex(hover))
		t.set_stylebox("pressed", cls, box_tex(pressed))
		t.set_stylebox("hover_pressed", cls, box_tex(pressed))
		t.set_stylebox("disabled", cls, box_tex(disabled))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, TEXT)
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_color("font_hover_pressed_color", cls, TEXT)
		t.set_color("font_focus_color", cls, TEXT)
		t.set_color("font_disabled_color", cls, TEXT_OFF)
	t.set_icon("arrow", "OptionButton", tex(arrow_img("down")))
	t.set_constant("arrow_margin", "OptionButton", 6)

	# toggle buttons on the toolbar: flat until hovered, sunken when on
	t.set_type_variation("ToolButton", "Button")
	var tb_normal := StyleBoxEmpty.new()
	tb_normal.content_margin_left = 6
	tb_normal.content_margin_right = 6
	tb_normal.content_margin_top = 3
	tb_normal.content_margin_bottom = 3
	t.set_stylebox("normal", "ToolButton", tb_normal)
	var tb_hover := flat(Color("#FFFFFF", 0.6), Color("#CECEC3"), 1, 2, 6)
	var tb_on := flat(Color("#E3E3DB"), Color("#9D9D92"), 1, 2, 6)
	for s in [tb_hover, tb_on]:
		s.content_margin_top = 3
		s.content_margin_bottom = 3
	t.set_stylebox("hover", "ToolButton", tb_hover)
	t.set_stylebox("pressed", "ToolButton", tb_on)
	t.set_stylebox("hover_pressed", "ToolButton", tb_on)
	t.set_stylebox("disabled", "ToolButton", tb_normal)
	t.set_stylebox("focus", "ToolButton", StyleBoxEmpty.new())

	# check boxes and radios
	t.set_icon("unchecked", "CheckBox", tex(check_img(false)))
	t.set_icon("checked", "CheckBox", tex(check_img(true)))
	t.set_icon("unchecked_disabled", "CheckBox", tex(check_img(false, false, true)))
	t.set_icon("checked_disabled", "CheckBox", tex(check_img(true, false, true)))
	t.set_icon("radio_unchecked", "CheckBox", tex(check_img(false, true)))
	t.set_icon("radio_checked", "CheckBox", tex(check_img(true, true)))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckBox", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckBox", TEXT)
	t.set_icon("checked", "PopupMenu", tex(check_img(true)))
	t.set_icon("unchecked", "PopupMenu", tex(check_img(false)))
	t.set_icon("radio_checked", "PopupMenu", tex(check_img(true, true)))
	t.set_icon("radio_unchecked", "PopupMenu", tex(check_img(false, true)))

	# edit boxes
	var edit := flat(Color.WHITE, EDGE, 1, 0, 3)
	for cls in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", cls, edit)
		t.set_stylebox("focus", cls, flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		t.set_stylebox("read_only", cls, flat(FACE, EDGE, 1, 0, 3))
		t.set_color("font_color", cls, TEXT)
		t.set_color("selection_color", cls, SELECT)
		t.set_color("font_selected_color", cls, Color.WHITE)
		t.set_color("caret_color", cls, TEXT)
	t.set_icon("updown", "SpinBox", tex(_updown()))

	# panels and frames
	t.set_stylebox("panel", "Panel", flat(FACE))
	t.set_stylebox("panel", "PanelContainer", flat(FACE, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_type_variation("GroupBox", "PanelContainer")
	var gb := flat(Color(0, 0, 0, 0), Color("#D0D0BF"), 1, 3, 6)
	gb.content_margin_top = 6
	t.set_stylebox("panel", "GroupBox", gb)
	t.set_type_variation("Sunken", "PanelContainer")
	var sunk := flat(Color.WHITE, EDGE, 1, 0, 1)
	t.set_stylebox("panel", "Sunken", sunk)
	t.set_type_variation("StatusCell", "PanelContainer")
	var cell := StyleBoxFlat.new()
	cell.bg_color = FACE
	cell.border_color = Color("#D5D2C2")
	cell.border_width_left = 1
	cell.border_width_top = 1
	cell.content_margin_left = 6
	cell.content_margin_right = 6
	cell.content_margin_top = 2
	cell.content_margin_bottom = 2
	t.set_stylebox("panel", "StatusCell", cell)
	t.set_type_variation("GroupTitle", "Label")
	t.set_color("font_color", "GroupTitle", GROUP_TITLE)
	t.set_font("font", "GroupTitle", bold)
	t.set_type_variation("TaskTitle", "Label")
	t.set_color("font_color", "TaskTitle", TASK_HEAD)
	t.set_font("font", "TaskTitle", bold)
	t.set_type_variation("Bold", "Label")
	t.set_font("font", "Bold", bold)
	t.set_color("font_color", "Label", TEXT)

	# sliders: a sunken channel and a pointed thumb
	var channel := flat(Color("#F3F2EB"), Color("#9D9C99"), 1, 1, 0)
	channel.content_margin_top = 2
	channel.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", channel)
	t.set_stylebox("grabber_area", "HSlider", flat(Color("#9DB9EB"), Color(0, 0, 0, 0), 0, 1, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(Color("#9DB9EB"), Color(0, 0, 0, 0), 0, 1, 0))
	t.set_icon("grabber", "HSlider", tex(thumb_img()))
	t.set_icon("grabber_highlight", "HSlider", tex(thumb_img(true)))
	t.set_constant("center_grabber", "HSlider", 0)

	# scroll bars, the light blue of Luna
	for cls in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", cls, flat(Color("#F4F3EE"), Color("#EEEDE5"), 1, 0, 0))
		t.set_stylebox("scroll_focus", cls, flat(Color("#F4F3EE"), Color("#EEEDE5"), 1, 0, 0))
		var g := flat(Color("#C8D6FB"), Color("#9AB4F0"), 1, 3, 4)
		t.set_stylebox("grabber", cls, g)
		t.set_stylebox("grabber_highlight", cls, flat(Color("#DCE6FD"), Color("#9AB4F0"), 1, 3, 4))
		t.set_stylebox("grabber_pressed", cls, flat(Color("#AFC4F6"), Color("#7E9EE8"), 1, 3, 4))
	t.set_icon("increment", "VScrollBar", tex(_scroll_btn("down")))
	t.set_icon("decrement", "VScrollBar", tex(_scroll_btn("up")))
	t.set_icon("increment", "HScrollBar", tex(_scroll_btn("right")))
	t.set_icon("decrement", "HScrollBar", tex(_scroll_btn("left")))
	t.set_icon("increment_highlight", "VScrollBar", tex(_scroll_btn("down", true)))
	t.set_icon("decrement_highlight", "VScrollBar", tex(_scroll_btn("up", true)))
	t.set_icon("increment_highlight", "HScrollBar", tex(_scroll_btn("right", true)))
	t.set_icon("decrement_highlight", "HScrollBar", tex(_scroll_btn("left", true)))

	# menus: white with a grey edge, blue highlight
	var pm := flat(Color.WHITE, FACE_DARK, 1, 0, 3)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", flat(SELECT, Color(0, 0, 0, 0), 0, 0, 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_OFF)
	t.set_color("font_separator_color", "PopupMenu", FACE_DARK)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_constant("item_start_padding", "PopupMenu", 6)
	var sep := StyleBoxLine.new()
	sep.color = FACE_DARK
	sep.thickness = 1
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_icon("submenu", "PopupMenu", tex(arrow_img("right", 9, 9, TEXT)))
	var mb_normal := StyleBoxEmpty.new()
	mb_normal.content_margin_left = 7
	mb_normal.content_margin_right = 7
	mb_normal.content_margin_top = 2
	mb_normal.content_margin_bottom = 2
	t.set_stylebox("normal", "MenuBar", mb_normal)
	var mb_hot := flat(SELECT, Color(0, 0, 0, 0), 0, 0, 7)
	mb_hot.content_margin_top = 2
	mb_hot.content_margin_bottom = 2
	t.set_stylebox("hover", "MenuBar", mb_hot)
	t.set_stylebox("pressed", "MenuBar", mb_hot)
	t.set_stylebox("hover_pressed", "MenuBar", mb_hot)
	t.set_stylebox("focus", "MenuBar", StyleBoxEmpty.new())
	t.set_color("font_color", "MenuBar", TEXT)
	t.set_color("font_hover_color", "MenuBar", Color.WHITE)
	t.set_color("font_pressed_color", "MenuBar", Color.WHITE)
	t.set_color("font_hover_pressed_color", "MenuBar", Color.WHITE)
	t.set_constant("h_separation", "MenuBar", 0)

	# lists
	for cls in ["ItemList", "Tree"]:
		t.set_stylebox("panel", cls, flat(Color.WHITE, EDGE, 1, 0, 2))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_stylebox("selected", cls, flat(SELECT))
		t.set_stylebox("selected_focus", cls, flat(SELECT))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_selected_color", cls, Color.WHITE)

	# tabs: the orange line on the chosen one
	var tab_on := flat(Color("#FCFCFE"), Color("#919B9C"), 1, 2, 6)
	tab_on.border_color = Color("#919B9C")
	tab_on.border_width_top = 3
	tab_on.border_color = Color("#E68B2C")
	var tab_off := flat(Color("#F3F3EF"), Color("#919B9C"), 1, 2, 6)
	t.set_stylebox("tab_selected", "TabContainer", tab_on)
	t.set_stylebox("tab_unselected", "TabContainer", tab_off)
	t.set_stylebox("tab_hovered", "TabContainer", tab_off)
	t.set_stylebox("panel", "TabContainer", flat(Color("#FCFCFE"), Color("#919B9C"), 1, 0, 6))
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	# tooltips
	t.set_stylebox("panel", "TooltipPanel", flat(Color("#FFFFE1"), TEXT, 1, 0, 4))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# dialogs (embedded windows): a blue frame with the title in it
	var win := StyleBoxFlat.new()
	win.bg_color = FACE
	win.border_color = Color("#0055E5")
	win.border_width_left = 3
	win.border_width_right = 3
	win.border_width_bottom = 3
	win.border_width_top = 27
	win.expand_margin_left = 3
	win.expand_margin_right = 3
	win.expand_margin_bottom = 3
	win.expand_margin_top = 27
	win.corner_radius_top_left = 7
	win.corner_radius_top_right = 7
	win.anti_aliasing = false
	t.set_stylebox("embedded_border", "Window", win)
	t.set_stylebox("embedded_unfocused_border", "Window", win)
	t.set_font("title_font", "Window", bold)
	t.set_font_size("title_font_size", "Window", 13)
	t.set_color("title_color", "Window", Color.WHITE)
	t.set_constant("title_height", "Window", 26)
	t.set_icon("close", "Window", tex(close_img()))
	t.set_icon("close_pressed", "Window", tex(close_img(true)))
	t.set_constant("close_h_offset", "Window", 25)
	t.set_constant("close_v_offset", "Window", 23)
	t.set_stylebox("panel", "AcceptDialog", flat(FACE, Color(0, 0, 0, 0), 0, 0, 8))
	return t


static func _updown() -> Image:
	var img := Image.create(15, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var up := rounded(15, 10, Color("#A7BDEF"), [[0.0, "#E6EEFC"], [1.0, "#BFD0F7"]], Color(0, 0, 0, 0), 2)
	img.blit_rect(up, Rect2i(0, 0, 15, 10), Vector2i(0, 0))
	img.blit_rect(up, Rect2i(0, 0, 15, 10), Vector2i(0, 10))
	var a := arrow_img("up", 9, 9)
	var d := arrow_img("down", 9, 9)
	img.blend_rect(a, Rect2i(0, 0, 9, 9), Vector2i(3, 0))
	img.blend_rect(d, Rect2i(0, 0, 9, 9), Vector2i(3, 10))
	return img


static func _scroll_btn(dir: String, hot := false) -> Image:
	var img := rounded(17, 17, Color("#B4C8F6"), [[0.0, "#E1EAFE" if not hot else "#F0F5FF"], [1.0, "#C1D3FB"]], Color(0, 0, 0, 0), 3)
	img.blend_rect(arrow_img(dir), Rect2i(0, 0, 9, 9), Vector2i(4, 4))
	return img


## A XP explorer-style title strip for a pane: white to light blue, blue text.
static func pane_header_box() -> StyleBoxTexture:
	var img := Image.create(64, 22, false, Image.FORMAT_RGBA8)
	for y in 22:
		for x in 64:
			var c := Color("#FFFFFF").lerp(Color("#C6D3F7"), float(x) / 63.0)
			if y == 21:
				c = Color("#A9BCEB")
			img.set_pixel(x, y, c)
	var s := StyleBoxTexture.new()
	s.texture = tex(img)
	s.texture_margin_left = 2
	s.texture_margin_right = 2
	s.texture_margin_top = 2
	s.texture_margin_bottom = 2
	s.content_margin_left = 8
	s.content_margin_right = 6
	s.content_margin_top = 3
	s.content_margin_bottom = 4
	return s


static func task_bg_box() -> StyleBoxTexture:
	var img := Image.create(4, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 4:
			img.set_pixel(x, y, TASK_TOP.lerp(TASK_BOTTOM, float(y) / 63.0))
	var s := StyleBoxTexture.new()
	s.texture = tex(img)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func title_bar_image(w: int, h: int, active := true) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stops: Array = TITLE_STOPS if active else TITLE_OFF
	for y in h:
		var c := grad(stops, float(y) / max(h - 1, 1))
		for x in w:
			img.set_pixel(x, y, c)
	return img
