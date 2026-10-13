class_name Settings
extends RefCounted

## Настройки игры. Пока — только громкость музыки и звуков (по умолчанию 50%),
## значения хранятся на сессию, без сохранения на диск.
## Звуковые шины «Music» и «SFX» создаются при запуске игры; когда в игре
## появятся музыка и звуки, их нужно будет направить в эти шины —
## громкостью уже будут управлять слайдеры из окна настроек.

static var music_volume := 0.5
static var sfx_volume := 0.5


## Создать звуковые шины (если их ещё нет) и применить текущую громкость.
static func ensure_buses() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	apply()


## Громкость музыки, 0.0–1.0.
static func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	apply()


## Громкость звуков игры, 0.0–1.0.
static func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	apply()


static func apply() -> void:
	_apply_bus("Music", music_volume)
	_apply_bus("SFX", sfx_volume)


## Одноразовый звуковой эффект (шина "SFX"): плеер становится ребёнком parent
## и самоуничтожается по окончании. Несколько звуков могут играть сразу —
## каждый своим плеером. Вне дерева (headless-тесты) — тишина.
static func play_sfx(parent: Node, stream: AudioStream, db := 0.0) -> void:
	if parent == null or stream == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	if AudioServer.get_bus_index("SFX") != -1:
		p.bus = "SFX"
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


static func _apply_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


## Всплывающее окно настроек: затемнение фона и два слайдера громкости.
class SettingsWindow:
	extends Control

	signal closed


	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		# Родитель — CanvasLayer, а не Control: якоря сами не сработают,
		# поэтому размер окна задаём явно по размеру вьюпорта (и следим за ним)
		_sync_size()
		get_viewport().size_changed.connect(_sync_size)

		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.6)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)

		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)

		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.18, 0.23)
		style.set_corner_radius_all(12)
		style.set_border_width_all(2)
		style.border_color = Color(0.4, 0.44, 0.52)
		style.content_margin_left = 28
		style.content_margin_right = 28
		style.content_margin_top = 22
		style.content_margin_bottom = 22
		panel.add_theme_stylebox_override("panel", style)
		center.add_child(panel)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 16)
		panel.add_child(box)

		var title := Label.new()
		title.text = "Настройки"
		title.add_theme_font_size_override("font_size", 28)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)

		_add_slider_row(box, "Музыка", Settings.music_volume, Settings.set_music_volume)
		_add_slider_row(box, "Звуки игры", Settings.sfx_volume, Settings.set_sfx_volume)

		var close := Button.new()
		close.text = "Закрыть"
		close.custom_minimum_size = Vector2(180, 44)
		close.add_theme_font_size_override("font_size", 20)
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close.pressed.connect(_on_close)
		box.add_child(close)


	## Строка «название — слайдер — проценты». setter принимает громкость 0.0–1.0.
	func _add_slider_row(box: VBoxContainer, caption: String, initial: float, setter: Callable) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = caption
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.custom_minimum_size.x = 130
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_lbl)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = int(round(initial * 100.0))
		slider.custom_minimum_size = Vector2(220, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)

		var value_lbl := Label.new()
		value_lbl.add_theme_font_size_override("font_size", 20)
		value_lbl.custom_minimum_size.x = 56
		value_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value_lbl.text = "%d%%" % int(slider.value)
		row.add_child(value_lbl)

		slider.value_changed.connect(func(v: float) -> void:
			setter.call(v / 100.0)
			value_lbl.text = "%d%%" % int(v)
		)


	func _on_close() -> void:
		closed.emit()
		queue_free()


	func _sync_size() -> void:
		size = get_viewport_rect().size


## Кнопка-шестерёнка в верхнем левом углу игры, рисуется кодом.
class GearButton:
	extends Control

	signal pressed

	const BTN_SIZE := 40.0

	var _hover := false


	func _init() -> void:
		custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hover = false; queue_redraw())


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()


	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.95, 0.97, 1.0) if _hover else Color(0.75, 0.78, 0.85)
		var r_out := size.x * 0.44
		var r_ring := size.x * 0.27
		# Тёмная подложка, чтобы шестерёнка читалась на любом фоне
		draw_circle(c, r_out, Color(0, 0, 0, 0.35))
		# Зубцы
		var tw := size.x * 0.16
		for i in 8:
			var a := TAU * float(i) / 8.0
			draw_set_transform(c, a, Vector2.ONE)
			draw_rect(Rect2(-tw * 0.5, -r_out, tw, size.x * 0.18), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Обод шестерёнки
		draw_arc(c, r_ring, 0, TAU, 24, col, size.x * 0.11)
