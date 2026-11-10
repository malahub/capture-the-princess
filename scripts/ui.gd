class_name UI
extends CanvasLayer
## All screen-space UI, built in code: main menu, tutorial overlay, HUD, cards.

signal play_pressed
signal tutorial_pressed
signal online_pressed(team: int)
signal resume_pressed
signal restart_pressed
signal menu_pressed
signal quit_pressed

const GOLD := Color("e8b53f")
const IVORY := Color("f3ead8")
const INK := Color("10151f")
const PANEL := Color("161d2b")
const DIM := Color("93a0b5")
const REDC := Color("e2544a")
const BLUEC := Color("5b8bf0")

var game: Node = null
var root: Control
var menu: Control
var hud: Control
var help: Control
var pause: Control
var endcard: Control
var tutorial: Control

var lvl: Label
var hp_bar: ColorRect
var hp_bg: ColorRect
var class_label: Label
var cake_label: Label
var obj_label: Label
var prompt_label: Label
var banner: Label
var hold_label: Label
var hold_bar: ColorRect
var hold_bg: ColorRect
var map_view: Control
var end_title: Label
var end_body: Label
var tut_title: Label
var tut_body: Label
var tut_step: Label
var toast_label: Label
var dbg_label: Label
var banner_t := 0.0
var ui_guard := 0.0
var map_t := 0.0

# --- decorative frame drawn behind menus -----------------------------
class Frame extends Control:
	var accent: Color = Color("e8b53f")
	var bg_alpha := 0.42
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.04, 0.06, 0.10, bg_alpha), true)
		var t := 3.0
		var s := 46.0
		var c := accent
		# corner brackets
		draw_rect(Rect2(0, 0, s, t), c, true)
		draw_rect(Rect2(0, 0, t, s), c, true)
		draw_rect(Rect2(w - s, 0, s, t), c, true)
		draw_rect(Rect2(w - t, 0, t, s), c, true)
		draw_rect(Rect2(0, h - t, s, t), c, true)
		draw_rect(Rect2(0, h - s, t, s), c, true)
		draw_rect(Rect2(w - s, h - t, s, t), c, true)
		draw_rect(Rect2(w - t, h - s, t, s), c, true)
		# mid-edge ticks
		draw_rect(Rect2(w * 0.5 - 1.5, 0, 3, 22), c, true)
		draw_rect(Rect2(w * 0.5 - 1.5, h - 22, 3, 22), c, true)
		draw_rect(Rect2(0, h * 0.5 - 1.5, 22, 3), c, true)
		draw_rect(Rect2(w - 22, h * 0.5 - 1.5, 22, 3), c, true)


class MapView extends Control:
	var game: Node = null
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.05, 0.07, 0.11, 0.82), true)
		draw_rect(r, Color(0.91, 0.71, 0.25, 0.55), false, 2.0)
		if game == null:
			return
		var wx := Terrain.HALF_X * 2.0
		var wz := Terrain.HALF_Z * 2.0
		var p := Vector2(size.x / wx, size.y / wz)
		var o := Vector2(size.x * 0.5, size.y * 0.5)
		# castles
		for b in [Vector2(-Terrain.CASTLE_X, 0), Vector2(Terrain.CASTLE_X, 0)]:
			var rc := Rect2(o + Vector2(b.x - 12, b.y - 13) * p, Vector2(24, 26) * p)
			draw_rect(rc, Color(1, 1, 1, 0.10), true)
			draw_rect(rc, Color(1, 1, 1, 0.22), false, 1.0)
		# road
		draw_rect(Rect2(o + Vector2(-60, -3) * p, Vector2(22, 6) * p), Color(0.55, 0.44, 0.31, 0.28), true)
		draw_rect(Rect2(o + Vector2(38, -3) * p, Vector2(22, 6) * p), Color(0.55, 0.44, 0.31, 0.28), true)
		# river and bridges on the minimap
		draw_rect(Rect2(o + Vector2(-Terrain.WATER_HALF, -Terrain.HALF_Z) * p, Vector2(Terrain.WATER_HALF * 2.0, Terrain.HALF_Z * 2.0) * p), Color(0.22, 0.45, 0.62, 0.55), true)
		for bz in Terrain.BRIDGE_Z:
			draw_rect(Rect2(o + Vector2(-9, bz - 3.5) * p, Vector2(18, 7) * p), Color(0.62, 0.46, 0.28, 0.9), true)
		for cake in game.cakes:
			if cake["active"]:
				draw_circle(o + Vector2(cake["pos"].x, cake["pos"].z) * p, 2.6, Color("f6b8cf"))
		if game.red_princess != null:
			draw_circle(o + Vector2(game.red_princess.position.x, game.red_princess.position.z) * p, 4.2, REDC)
		if game.blue_princess != null:
			draw_circle(o + Vector2(game.blue_princess.position.x, game.blue_princess.position.z) * p, 4.2, BLUEC)
		for u in game.units:
			if not u.alive:
				continue
			var up := o + Vector2(u.pos.x, u.pos.z) * p
			if u.is_player:
				draw_circle(up, 4.6, Color("ffffff"))
				draw_circle(up, 3.2, GOLD)
			else:
				draw_circle(up, 3.0, REDC if u.team == 0 else BLUEC)


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.resized.connect(_relayout)
	_build_menu()
	_build_hud()
	_build_help()
	_build_pause()
	_build_end()
	_build_tutorial()
	show_menu()


func _relayout() -> void:
	for c in [menu, hud, help, pause, endcard, tutorial]:
		if c != null:
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ------------------------------------------------------------ helpers
func mk_label(parent: Node, text: String, fsize: int, color: Color = IVORY,
		pos: Vector2 = Vector2.ZERO, width: float = 0.0, height: float = 40.0) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.position = pos
	if width > 0.0:
		# width first, text last: assigning text to a zero-width label makes it
		# grow to the unwrapped line and overflow the panel it sits in
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = Vector2(width, height)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _btn_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


func mk_button(parent: Node, text: String, cb: Callable, y: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(330, 58)
	b.size = Vector2(330, 58)
	b.position = Vector2(0, y)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.19, 0.95)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	b.add_theme_stylebox_override("normal", sb)
	var sh: StyleBoxFlat = sb.duplicate()
	sh.bg_color = Color(0.16, 0.22, 0.34, 0.98)
	sh.border_color = Color("ffd766")
	b.add_theme_stylebox_override("hover", sh)
	var sp: StyleBoxFlat = sb.duplicate()
	sp.bg_color = GOLD
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", IVORY)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", INK)
	# fire on press, not release: the first click in a browser tab can lose its
	# release while the canvas takes focus, and a menu that eats clicks reads as broken
	b.button_down.connect(cb)
	parent.add_child(b)
	return b


func panel(parent: Node, rect: Rect2, color: Color = PANEL) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


# ------------------------------------------------------------ menu
# ------------------------------------------------------------ unit pictograms
class UnitIcon extends Control:
	var kind := "warrior"
	var tint: Color = Color("e8b53f")

	func _draw() -> void:
		var s: float = size.x / 72.0
		var c: Vector2 = size * 0.5
		draw_circle(c + Vector2(0, 27) * s, 24 * s, Color(0, 0, 0, 0.28))
		match kind:
			"warrior":
				_sword(c, s)
			"ranger":
				_bow(c, s)
			"mage":
				_staff(c, s)
			"worker":
				_hammer(c, s)
			_:
				_hand(c, s)

	func _sword(c: Vector2, s: float) -> void:
		draw_circle(c + Vector2(-13, 4) * s, 19 * s, Color("6d737b"))
		draw_circle(c + Vector2(-13, 4) * s, 15 * s, tint)
		draw_circle(c + Vector2(-13, 4) * s, 6 * s, Color("e8b53f"))
		draw_rect(Rect2(c + Vector2(4, -26) * s, Vector2(8, 38) * s), Color("eef3fa"))
		draw_rect(Rect2(c + Vector2(5, -26) * s, Vector2(3, 38) * s), Color("ffffff"))
		draw_rect(Rect2(c + Vector2(-6, 10) * s, Vector2(26, 7) * s), Color("e8b53f"))
		draw_rect(Rect2(c + Vector2(5, 17) * s, Vector2(5, 13) * s), Color("8a5a33"))

	func _bow(c: Vector2, s: float) -> void:
		var r := 25.0 * s
		var mid := c + Vector2(-2, 0) * s
		draw_arc(mid, r, deg_to_rad(118), deg_to_rad(242), 22, Color("8a5a33"), 5 * s)
		var a1 := mid + Vector2(cos(deg_to_rad(118)), sin(deg_to_rad(118))) * r
		var a2 := mid + Vector2(cos(deg_to_rad(242)), sin(deg_to_rad(242))) * r
		draw_line(a1, a2, Color(0.92, 0.94, 0.97, 0.85), 1.5 * s)
		draw_line(c + Vector2(-16, 0) * s, c + Vector2(16, 0) * s, Color("8a5a33"), 3 * s)
		var head := PackedVector2Array([
			c + Vector2(23, 0) * s, c + Vector2(13, -5.5) * s, c + Vector2(13, 5.5) * s])
		draw_colored_polygon(head, Color("eef3fa"))
		draw_line(c + Vector2(-16, 0) * s, c + Vector2(-22, -6) * s, Color("cf3f36"), 3 * s)
		draw_line(c + Vector2(-16, 0) * s, c + Vector2(-22, 6) * s, Color("cf3f36"), 3 * s)

	func _staff(c: Vector2, s: float) -> void:
		draw_line(c + Vector2(9, 28) * s, c + Vector2(-5, -14) * s, Color("8a5a33"), 6 * s)
		draw_circle(c + Vector2(-8, -22) * s, 13 * s, tint)
		draw_circle(c + Vector2(-8, -22) * s, 8 * s, Color("58d6d6"))
		draw_circle(c + Vector2(-8, -22) * s, 3.6 * s, Color("ffffff"))
		for a in [0.2, 1.9, 3.6, 5.2]:
			draw_circle(c + Vector2(-8, -22) * s + Vector2(cos(a), sin(a)) * 18 * s, 2.2 * s,
				Color("ffd166"))

	func _hammer(c: Vector2, s: float) -> void:
		# handle
		draw_line(c + Vector2(-14, 24) * s, c + Vector2(10, -12) * s, Color("8a5a33"), 7 * s)
		# head
		draw_rect(Rect2(c + Vector2(-4, -24) * s, Vector2(26, 13) * s), tint)
		draw_rect(Rect2(c + Vector2(-4, -24) * s, Vector2(8, 13) * s), tint.darkened(0.25))
		# claw
		draw_rect(Rect2(c + Vector2(18, -22) * s, Vector2(10, 8) * s), tint.darkened(0.35))

	func _hand(c: Vector2, s: float) -> void:
		var skin := Color("f0c39a")
		draw_rect(Rect2(c + Vector2(-13, -2) * s, Vector2(26, 24) * s), skin)
		for i in 4:
			draw_rect(Rect2(c + Vector2(-11.0 + float(i) * 6.0, -22) * s, Vector2(4.5, 22) * s), skin)
		draw_rect(Rect2(c + Vector2(-19, 3) * s, Vector2(7, 12) * s), skin)
		draw_line(c + Vector2(-6, 10) * s, c + Vector2(4, 10) * s, Color("c99a72"), 1.6 * s)


func _card(r: Rect2) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.05, 0.08, 0.88)
	bg.position = r.position
	bg.size = r.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bg)
	var edges := [
		Rect2(r.position.x, r.position.y, r.size.x, 3),
		Rect2(r.position.x, r.position.y + r.size.y - 3, r.size.x, 3),
		Rect2(r.position.x, r.position.y, 3, r.size.y),
		Rect2(r.position.x + r.size.x - 3, r.position.y, 3, r.size.y),
		Rect2(r.position.x, r.position.y, 34, 6),
		Rect2(r.position.x, r.position.y, 6, 34),
		Rect2(r.position.x + r.size.x - 34, r.position.y, 34, 6),
		Rect2(r.position.x + r.size.x - 6, r.position.y, 6, 34),
		Rect2(r.position.x, r.position.y + r.size.y - 6, 34, 6),
		Rect2(r.position.x, r.position.y + r.size.y - 34, 6, 34),
		Rect2(r.position.x + r.size.x - 34, r.position.y + r.size.y - 6, 34, 6),
		Rect2(r.position.x + r.size.x - 6, r.position.y + r.size.y - 34, 6, 34),
	]
	for e in edges:
		var er := ColorRect.new()
		er.color = Color(0.91, 0.71, 0.25, 0.8)
		er.position = e.position
		er.size = e.size
		er.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu.add_child(er)


func _roster_row(y: float, kind: String, tint: Color, title: String, stats: String, desc: String) -> void:
	var row := ColorRect.new()
	row.color = Color(0.07, 0.09, 0.135, 0.92)
	row.position = Vector2(846, y)
	row.size = Vector2(660, 112)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(row)
	var bar := ColorRect.new()
	bar.color = tint
	bar.position = Vector2(846, y)
	bar.size = Vector2(5, 112)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bar)

	var icon := UnitIcon.new()
	icon.kind = kind
	icon.tint = tint
	icon.position = Vector2(862, y + 19)
	icon.size = Vector2(70, 70)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(icon)

	var nm := mk_label(menu, title, 24, Color.WHITE, Vector2(952, y + 8))
	nm.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	var st := mk_label(menu, stats, 15, tint.lightened(0.25), Vector2(952, y + 34))
	var ds := mk_label(menu, desc, 15, Color(0.82, 0.86, 0.92), Vector2(952, y + 56), 540, 40)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)

	var f := Frame.new()
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(f)

	_card(Rect2(88, 92, 704, 620))
	_card(Rect2(824, 92, 704, 620))

	# ---- left: title and the three doors in
	var t := mk_label(menu, "CAPTURE THE PRINCESS", 44, GOLD, Vector2(88, 118), 704)
	t.add_theme_constant_override("outline_size", 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := mk_label(menu, "an isometric siege of cake, crowns\nand very fat princesses", 21, IVORY,
		Vector2(88, 212), 704, 74)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := ColorRect.new()
	rule.color = Color(0.91, 0.71, 0.25, 0.5)
	rule.position = Vector2(352, 306)
	rule.size = Vector2(176, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(rule)

	var col := VBoxContainer.new()
	col.position = Vector2(275, 340)
	col.custom_minimum_size = Vector2(330, 0)
	col.add_theme_constant_override("separation", 14)
	menu.add_child(col)
	var b1 := mk_button(col, "RESCUE THE PRINCESS", func(): _fire(play_pressed), 0)
	b1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var b2 := mk_button(col, "TUTORIAL", func(): _fire(tutorial_pressed), 0)
	b2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var b3 := mk_button(col, "HOW TO PLAY", func(): help.visible = true, 0)
	b3.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var loop := mk_label(menu, "THE LOOP", 17, GOLD, Vector2(108, 566), 664, 24)
	loop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var steps := mk_label(menu,
		"1   FEED the captive princess — every slice makes her heavy\n"
		+ "2   RESCUE your own princess from the blue dungeon\n"
		+ "3   HOLD her on your throne for 25 seconds",
		16, Color(0.84, 0.87, 0.92), Vector2(108, 592), 664, 70)
	steps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := mk_label(menu,
		"Blue has more soldiers — you have the better ideas.",
		15, Color(0.62, 0.68, 0.78), Vector2(108, 668), 664, 24)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ---- right: the roster, so the menu teaches the units
	var hdr := mk_label(menu, "THE ROSTER", 30, GOLD, Vector2(846, 104))
	var hsub := mk_label(menu, "hats stand in your castle — stand on one and press E to become that unit",
		15, Color(0.66, 0.72, 0.8), Vector2(846, 142), 660, 24)
	_roster_row(158, "worker", Color("c39a5e"), "WORKER  ·  YOU SPAWN HERE", "160 HP   ·   5.3   ·   11 dmg chisel",
		"No hat, no class. Chop wood and ore, repair your gate, and feed the stands that upgrade the whole team — then take a hat.")
	_roster_row(280, "warrior", Color("a8b0ba"), "WARRIOR", "240 HP   ·   slow   ·   2.2 m arc",
		"The front line. Widest swing in the game and the health to hold a doorway.")
	_roster_row(402, "ranger", Color("6fb35f"), "RANGER", "150 HP   ·   quick   ·   15 m range",
		"Shoots a carrier off the princess from across the field. Fragile in a brawl.")
	_roster_row(524, "mage", Color("a479e0"), "MAGE", "170 HP   ·   slow   ·   splash damage",
		"Fireball that splashes. The answer to a crowd camping the throne.")

	# ---- online: pick a side and drop into a shared room (solo is untouched)
	var bar := HBoxContainer.new()
	bar.position = Vector2(846, 648)
	bar.add_theme_constant_override("separation", 10)
	menu.add_child(bar)
	var olabel := mk_label(bar, "JOIN ONLINE", 15, GOLD, Vector2.ZERO, 150, 24)
	olabel.custom_minimum_size = Vector2(150, 34)
	for side in [0, 1]:
		var b := mk_button(bar, "RED" if side == 0 else "BLUE", func(): online_pressed.emit(side), 0)
		b.custom_minimum_size = Vector2(104, 34)
		b.size = Vector2(104, 34)
		b.add_theme_font_size_override("font_size", 15)
		if side == 1:
			b.add_theme_stylebox_override("normal", _btn_style(Color("3364cc"), Color("5b8bf0")))
	var osub := mk_label(menu, "100 per room · pick a side", 12,
		Color(0.62, 0.68, 0.78), Vector2(846, 690), 400, 18)

	var hintplate := ColorRect.new()
	hintplate.color = Color(0.03, 0.05, 0.09, 0.68)
	hintplate.position = Vector2(0, 776)
	hintplate.size = Vector2(1600, 96)
	hintplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(hintplate)
	var ruleline := ColorRect.new()
	ruleline.color = Color(0.91, 0.71, 0.25, 0.35)
	ruleline.position = Vector2(0, 776)
	ruleline.size = Vector2(1600, 2)
	ruleline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(ruleline)

	var hint := mk_label(menu,
		"WASD move   ·   SPACE / LMB attack   ·   V jump   ·   E carry or take a hat   ·   F feed cake   ·   SHIFT dash   ·   H help",
		20, DIM, Vector2(0, 800), 1600)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var foot := mk_label(menu, "original art, code and title — no assets from any commercial game", 16,
		Color(0.6, 0.66, 0.75), Vector2(0, 840), 1600)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _fire(sig: Signal) -> void:
	if ui_guard > 0.0:
		return
	sig.emit()


# ------------------------------------------------------------ hud
func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)

	# top-left: hero card
	panel(hud, Rect2(24, 22, 340, 126), Color(0.05, 0.07, 0.11, 0.78))
	mk_label(hud, "YOU", 16, GOLD, Vector2(40, 30))
	class_label = mk_label(hud, "WORKER", 26, IVORY, Vector2(40, 50))
	hp_bg = panel(hud, Rect2(40, 90, 280, 18), Color(0.15, 0.10, 0.10, 1.0))
	hp_bar = panel(hud, Rect2(42, 92, 276, 14), Color("57c46a"))
	cake_label = mk_label(hud, "CAKE 0", 21, Color("f6b8cf"), Vector2(40, 110))

	# top-right: minimap
	map_view = MapView.new()
	map_view.game = game
	map_view.position = Vector2(1600 - 24 - 240, 22)
	map_view.size = Vector2(240, 156)
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(map_view)

	# top-centre: hold state
	hold_label = mk_label(hud, "", 30, IVORY, Vector2(0, 26), 1600)
	hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hold_bg = panel(hud, Rect2(540, 66, 520, 14), Color(0.07, 0.09, 0.13, 0.9))
	hold_bar = panel(hud, Rect2(542, 68, 0, 10), GOLD)

	# left: objectives
	panel(hud, Rect2(24, 156, 340, 178), Color(0.05, 0.07, 0.11, 0.62))
	obj_label = mk_label(hud, "", 18, IVORY, Vector2(38, 168), 312, 160)

	# bottom centre: prompt
	prompt_label = mk_label(hud, "", 30, GOLD, Vector2(0, 792), 1600)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	banner = mk_label(hud, "", 52, GOLD, Vector2(0, 300), 1600)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0

	dbg_label = mk_label(hud, "", 20, Color("9ff2a0"), Vector2(24, 500), 760)
	dbg_label.visible = false

	toast_label = mk_label(hud, "", 24, IVORY, Vector2(0, 120), 1600)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate.a = 0.0


func update_hud(d: Dictionary) -> void:
	if not hud.visible:
		return
	var hpf: float = clampf(d.get("hp", 1.0), 0.0, 1.0)
	hp_bar.size.x = 276.0 * hpf
	hp_bar.color = Color("57c46a") if hpf > 0.5 else (Color("e8c04a") if hpf > 0.25 else Color("e2544a"))
	class_label.text = String(d.get("cls", "VILLAGER")).to_upper()
	cake_label.text = "CAKE  %d / 3" % int(d.get("cake", 0))
	obj_label.text = String(d.get("objectives", ""))
	hold_label.text = String(d.get("hold_text", ""))
	var frac: float = clampf(d.get("hold_frac", 0.0), 0.0, 1.0)
	hold_bar.size.x = 516.0 * frac
	hold_bar.color = REDC if bool(d.get("hold_red", true)) else BLUEC
	hold_bg.visible = frac > 0.001
	prompt_label.text = String(d.get("prompt", ""))
	prompt_label.position.y = 566.0 if tutorial.visible else 792.0
	if map_view != null and is_instance_valid(map_view):
		map_view.queue_redraw()


func flash_banner(text: String, color: Color = GOLD, dur: float = 2.2) -> void:
	banner.text = text
	banner.modulate = Color(color.r, color.g, color.b, 1.0)
	banner_t = dur


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0


func _process(dt: float) -> void:
	ui_guard = maxf(0.0, ui_guard - dt)
	if banner_t > 0.0:
		banner_t -= dt
		banner.modulate.a = clampf(banner_t, 0.0, 1.0)
	if toast_label.modulate.a > 0.0:
		toast_label.modulate.a = maxf(0.0, toast_label.modulate.a - dt * 0.5)


# ------------------------------------------------------------ help
func _build_help() -> void:
	help = Control.new()
	help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help.visible = false
	root.add_child(help)
	var f := Frame.new()
	f.bg_alpha = 0.985
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help.add_child(f)
	var t := mk_label(help, "HOW TO PLAY", 52, GOLD, Vector2(0, 42), 1600)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var left := mk_label(help, "", 18, IVORY, Vector2(90, 104), 730, 660)
	left.text = """TWO PRINCESSES, TWO DUNGEONS

Each castle holds the other team's princess. The RED Princess is locked in the BLUE dungeon; the BLUE Princess is locked in YOURS.

YOUR JOB

1. Feed the BLUE Princess in your dungeon. Every cake slice makes her heavier, and a heavy princess is slow to steal back.
2. Break their gate down (hit it) and keep it down — or their worker builds it back.
3. Take the KEY from the hook beside their cage, then walk it to the cage. The door swings open.
4. Press E beside the RED Princess to lift her, then carry her to your throne and hold it for 25 seconds.

CARRYING

Weight is speed: at 6 you crawl, at 9 you are a statue. Allies walking with you add speed. E again drops her.

CAKE

Walk over a pink platter to take a slice (max 3). F feeds the captive princess one slice. Her weight bleeds off slowly."""
	left.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_theme_constant_override("line_spacing", 4)

	var right := mk_label(help, "", 17, IVORY, Vector2(860, 104), 660, 670)
	right.text = """HATS ARE CLASSES

Three hat stands in every castle. You start — and respawn — as a hatless WORKER; walk onto a stand and press E to take that class. Die and you lose it: your hat drops where you fell, and any hatless worker can pick it up.

WORKER (no hat, where you spawn) - gathers wood and ore, repairs your gate, hits like a chisel.
WARRIOR - sword, most health, wide arc. Holds a doorway.
RANGER - bow, kills at range, fragile.
MAGE - fireball, splash damage, slow.

WHY TEAMS WIN  (all of it optional)

WORKER - 3 wood + 3 ore at a stand upgrades that class for EVERYONE: +22% damage, for the whole match.
RANGER / MAGE on a wall walk - +35% damage, shooting down from the parapet.
WARRIOR standing among allies - those allies take 18% less damage.
WORKER (where you start) - gather wood and ore, repair the gate.

None of it is required. A lone player can break a gate and win a fight without any of it - you are just playing with a handicap against a team that does.

CONTROLS

WASD move   ·   SPACE / LMB attack   ·   V jump
SHIFT dash   ·   E carry or take a hat
F feed cake   ·   Q drop princess
R turn the camera 90°   ·   SCROLL zoom   ·   V jump
ESC pause   ·   H help   ·   M mute

PLAYING ONLINE

Pick RED or BLUE on the menu and you drop into a shared room —
up to 100 players. Solo play is untouched: the tutorial, the siege
and the AI all run exactly as before when you are not online.
Your side is balanced by the server, so a lopsided room fills evenly.

SEEING THROUGH WALLS

Anyone the castle hides from you is drawn as an outline:
YELLOW is your side, RED is theirs. Turn the camera with R to
look at the fight from another corner before you commit."""
	right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_theme_constant_override("line_spacing", 2)

	var b := mk_button(help, "BACK", func(): help.visible = false, 0)
	b.position = Vector2(635, 836)
	b.custom_minimum_size = Vector2(330, 50)


# ------------------------------------------------------------ pause
func _build_pause() -> void:
	pause = Control.new()
	pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause.visible = false
	root.add_child(pause)
	var f := Frame.new()
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.bg_alpha = 0.88
	pause.add_child(f)
	var t := mk_label(pause, "PAUSED", 72, GOLD, Vector2(0, 220), 1600)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b1 := mk_button(pause, "RESUME", func(): _fire(resume_pressed), 0)
	b1.position = Vector2(635, 380)
	var b2 := mk_button(pause, "RESTART", func(): _fire(restart_pressed), 0)
	b2.position = Vector2(635, 452)
	var b3 := mk_button(pause, "MAIN MENU", func(): _fire(menu_pressed), 0)
	b3.position = Vector2(635, 524)


# ------------------------------------------------------------ end
func _build_end() -> void:
	endcard = Control.new()
	endcard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	endcard.visible = false
	root.add_child(endcard)
	var f := Frame.new()
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.bg_alpha = 0.9
	endcard.add_child(f)
	end_title = mk_label(endcard, "", 86, GOLD, Vector2(0, 230), 1600)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_body = mk_label(endcard, "", 24, IVORY, Vector2(340, 350), 920, 200)
	end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var b1 := mk_button(endcard, "PLAY AGAIN", func(): _fire(restart_pressed), 0)
	b1.position = Vector2(635, 560)
	var b2 := mk_button(endcard, "MAIN MENU", func(): _fire(menu_pressed), 0)
	b2.position = Vector2(635, 632)


func show_end(win: bool, time_text: String, detail: String) -> void:
	end_title.text = "VICTORY" if win else "DEFEAT"
	end_title.add_theme_color_override("font_color", GOLD if win else Color("e2544a"))
	end_body.text = detail + "\n\nmatch time  " + time_text
	endcard.visible = true
	endcard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.visible = false
	ui_guard = 0.6


# ------------------------------------------------------------ tutorial
func _build_tutorial() -> void:
	tutorial = Control.new()
	tutorial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial.visible = false
	tutorial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tutorial)
	panel(tutorial, Rect2(24, 612, 620, 200), Color(0.05, 0.07, 0.11, 0.88))
	tut_step = mk_label(tutorial, "STEP 1 / 7", 18, GOLD, Vector2(44, 626))
	tut_title = mk_label(tutorial, "", 30, IVORY, Vector2(44, 650), 570)
	tut_body = mk_label(tutorial, "", 21, DIM, Vector2(44, 696), 570, 105)
	tut_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func set_tutorial(step: int, total: int, title: String, body: String) -> void:
	tutorial.visible = true
	tut_step.text = "STEP %d / %d" % [step, total]
	tut_title.text = title
	tut_body.text = body


# ------------------------------------------------------------ screens
func show_menu() -> void:
	menu.visible = true
	hud.visible = false
	help.visible = false
	pause.visible = false
	endcard.visible = false
	tutorial.visible = false
	ui_guard = 0.5


func show_hud() -> void:
	menu.visible = false
	help.visible = false
	pause.visible = false
	endcard.visible = false
	hud.visible = true
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_guard = 0.4


func show_pause(v: bool) -> void:
	pause.visible = v
	if v:
		pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_guard = 0.4


func hide_tutorial() -> void:
	tutorial.visible = false
