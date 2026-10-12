class_name MainMenu
extends Control

## Главное меню игры: слева — список героев (выбор обязателен перед забегом),
## справа — выбранный герой (фигура, имя, прогресс). Сюда же игрок попадает
## после победы над боссом. Интерфейс строится кодом.

signal start_pressed(kind: String)

## Входные данные (заполняет Main)
var heroes := {}            # kind -> Hero (героя может ещё не быть — забег не начат)
var selected_kind := ""     # ранее выбранный герой ("" — ещё не выбирали)
var wins := 0
var message := ""

var _list_buttons := {}     # kind -> Button
var _figure: HeroFigure = null
var _name_label: Label = null
var _desc_label: Label = null
var _info_label: Label = null
var _start_btn: Button = null


func _ready() -> void:
	_build()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.18, 0.23)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 20
	root.offset_right = -24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var title := Label.new()
	title.text = "Хранитель Долины"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var wins_lbl := Label.new()
	wins_lbl.text = "Побед над боссом: %d" % wins
	wins_lbl.add_theme_font_size_override("font_size", 20)
	wins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wins_lbl.modulate = Color(0.95, 0.85, 0.4)
	root.add_child(wins_lbl)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	root.add_child(columns)

	_build_hero_list(columns)
	_build_preview(columns)

	_build_bottom(root)
	_refresh_preview()


## Левая панель: список героев для выбора.
func _build_hero_list(columns: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size.x = 380
	columns.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := Label.new()
	header.text = "Выбери героя"
	header.add_theme_font_size_override("font_size", 24)
	box.add_child(header)

	for kind in Hero.KINDS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)

		var mini := HeroFigure.new()
		mini.kind = kind
		mini.figure_size = 40.0
		mini.custom_minimum_size = Vector2(48, 56)
		mini.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mini)

		var btn := Button.new()
		btn.text = Hero.ROSTER[kind]["name"]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 56)
		btn.add_theme_font_size_override("font_size", 20)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggled.connect(_on_hero_toggled.bind(kind))
		row.add_child(btn)
		_list_buttons[kind] = btn

	# При возврате в меню ранее выбранный герой остаётся выбранным
	if _list_buttons.has(selected_kind):
		_list_buttons[selected_kind].button_pressed = true


## Правая панель: выбранный герой — фигура, имя, прогресс забега.
func _build_preview(columns: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_figure = HeroFigure.new()
	_figure.figure_size = 110.0
	_figure.custom_minimum_size = Vector2(160, 190)
	_figure.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_figure)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 30)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 17)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size.x = 400
	_desc_label.modulate = Color(0.75, 0.85, 1.0)
	box.add_child(_desc_label)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 18)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_info_label)


func _build_bottom(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	root.add_child(bar)

	var msg := Label.new()
	msg.text = message
	msg.add_theme_font_size_override("font_size", 18)
	msg.modulate = Color(0.55, 0.9, 0.95)
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(msg)

	_start_btn = Button.new()
	_start_btn.text = "Начать забег →"
	_start_btn.custom_minimum_size = Vector2(220, 56)
	_start_btn.add_theme_font_size_override("font_size", 24)
	_start_btn.disabled = true
	_start_btn.pressed.connect(func() -> void:
		if selected_kind != "":
			start_pressed.emit(selected_kind)
	)
	bar.add_child(_start_btn)


## Клик по герою в списке: выбор не снимается повторным кликом.
func _on_hero_toggled(on: bool, kind: String) -> void:
	if on:
		_select(kind)
	elif selected_kind == kind:
		_list_buttons[kind].button_pressed = true


func _select(kind: String) -> void:
	selected_kind = kind
	for k in _list_buttons:
		_list_buttons[k].button_pressed = (k == kind)
	_refresh_preview()


func _refresh_preview() -> void:
	if _figure == null or _start_btn == null:
		return
	_figure.kind = selected_kind
	_figure.queue_redraw()
	if selected_kind == "":
		_name_label.text = "Герой не выбран"
		_desc_label.text = ""
		_info_label.text = "Выбери героя из списка слева,\nпрежде чем начать забег."
		_start_btn.disabled = true
		return
	_name_label.text = Hero.ROSTER[selected_kind]["name"]
	_desc_label.text = Hero.ROSTER[selected_kind]["desc"]
	var h: Hero = heroes.get(selected_kind)
	if h == null:
		_info_label.text = "Новый герой — забег ещё не начат."
	elif h.wave >= Enemies.TOTAL_WAVES:
		_info_label.text = "Уровень: %d\nЗабег: финальный босс" % h.level
	else:
		_info_label.text = "Уровень: %d\nЗабег: волна %d / %d" % [h.level, h.wave, Enemies.TOTAL_WAVES]
	_start_btn.disabled = false


## Портрет героя: та же фигура (форма + цвет), что и на поле боя.
class HeroFigure:
	extends Control

	var kind := ""
	var figure_size := 48.0


	func _draw() -> void:
		if kind == "" or not Hero.ROSTER.has(kind):
			return
		var def: Dictionary = Hero.ROSTER[kind]
		var col: Color = def["color"]
		var r := figure_size * 0.5
		var center := Vector2(size.x * 0.5, size.y * 0.58)
		# Тень под фигурой
		draw_set_transform(center + Vector2(0, r * 0.95), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, r * 0.9, Color(0, 0, 0, 0.2))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		match def["shape"]:
			"circle":
				draw_circle(center, r, col)
			"triangle":
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(-r, r * 0.7),
					center + Vector2(r, r * 0.7),
					center + Vector2(0, -r),
				]), col)
			_:
				draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2, r * 2)), col)
