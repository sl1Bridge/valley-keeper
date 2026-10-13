class_name GameMain
extends Node

## Корневой узел игры: хранит состояние текущего забега и переключает экраны.
## Экраны: главное меню (MainMenu) → лагерь (GearScreen) → бой (BattleScreen) →
## победа/поражение → лагерь или главное меню.
## Прогресса между забегами нет: каждый забег начинается с новым героем 1 уровня.
## Поверх всех экранов — кнопка настроек (шестерёнка) и, во время забега,
## кнопка сдачи (белый флаг на красном). Открытие настроек или окна сдачи
## во время боя ставит бой на паузу.

var hero: Hero = null  # герой текущего забега
var selected_kind := ""

## Фоновая музыка (шина "Music"): зацикленные треки по экранам.
const MUSIC := {
	"menu": preload("res://assets/music/valley_keeper_menu.wav"),
	"camp": preload("res://assets/music/valley_keeper_camp.wav"),
	"battle": preload("res://assets/music/valley_keeper_battle.wav"),
}

## Общий клик кнопки интерфейса (шина "SFX"). Играет от имени Main —
## узел постоянный, звук не обрывается при смене экрана.
const SFX_UI_CLICK := preload("res://assets/sfx/ui_click.mp3")

var _screen: Control = null
var _settings_layer: CanvasLayer
var _surrender_btn: FlagButton
var _modal_count := 0  # открытые модальные окна (настройки, сдача)
var _music_player: AudioStreamPlayer
var _music_current := ""


func _ready() -> void:
	Settings.ensure_buses()
	# Музыка не подчиняется паузе: продолжает играть, когда бой на паузе
	# (открыты настройки — так слайдер громкости слышен сразу)
	_music_player = AudioStreamPlayer.new()
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") != -1:
		_music_player.bus = "Music"
	add_child(_music_player)
	_build_settings_button()
	_build_surrender_button()
	show_menu("")


## Переключить фоновую музыку (без перезапуска, если трек тот же). Зациклена.
func _play_music(key: String) -> void:
	if _music_current == key:
		return
	_music_current = key
	# Зацикливание задано при импорте (.import, edit/loop_mode=Forward):
	# установка stream.loop_mode в рантайме ломает старт воспроизведения.
	_music_player.stream = MUSIC[key]
	# Особенность движка: play() в тот же кадр, в котором плеер вошёл в дерево
	# (первая музыка — из _ready), молча не стартует. Ждём кадр.
	await get_tree().process_frame
	_music_player.play()


func _clear_screen() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
		_screen = null


# ---------- Главное меню ----------

func show_menu(msg: String) -> void:
	_clear_screen()
	_play_music("menu")
	var menu := MainMenu.new()
	menu.selected_kind = selected_kind
	menu.message = msg
	menu.start_pressed.connect(_on_menu_start)
	add_child(menu)
	_screen = menu
	_update_overlay()


## Начало забега: всегда новый герой 1 уровня, прогресс между забегами не сохраняется.
func _on_menu_start(kind: String) -> void:
	Settings.play_sfx(self, SFX_UI_CLICK)
	selected_kind = kind
	hero = Hero.new(kind)
	show_gear("Забег начинается! Собери героя и жми «В путь».")


# ---------- Лагерь и бой ----------

func show_gear(msg: String) -> void:
	_clear_screen()
	_play_music("camp")
	var gear := GearScreen.new()
	gear.hero = hero
	gear.wave = hero.wave
	gear.message = msg
	gear.embark_pressed.connect(_on_embark)
	add_child(gear)
	_screen = gear
	_update_overlay()


func _on_embark() -> void:
	_clear_screen()
	_play_music("battle")
	var battle := BattleScreen.new()
	battle.hero = hero
	battle.wave = hero.wave
	battle.wave_cleared.connect(_on_wave_cleared)
	battle.hero_died.connect(_on_hero_died)
	battle.boss_defeated.connect(_on_boss_defeated)
	add_child(battle)
	_screen = battle
	_update_overlay()


func _on_wave_cleared() -> void:
	# Сохраняем остаток здоровья и добавляем фиксированную передышку
	if _screen is BattleScreen:
		hero.current_hp = (_screen as BattleScreen).hero_hp()
	hero.apply_rest()
	hero.wave += 1
	show_gear("Волна пройдена! Передышка: +%d HP. Проверь рюкзак и очки характеристик." % int(Hero.REST_HEAL))


func _on_hero_died() -> void:
	hero.full_restore()
	_show_end_screen(
		"Поражение",
		"Герой пал в бою, но весь собранный лут и опыт сохранены.\nВ лагере он полностью пришёл в себя.\nВложи очки характеристик, обнови снарягу — и вперёд, снова!",
		"Вернуться в лагерь",
		func(): show_gear("Не беда! Попробуй другую сборку — волна та же.")
	)


func _on_boss_defeated() -> void:
	_show_end_screen(
		"Победа!",
		"Каменный страж повержен, долина спасена!\nЗабег пройден. Следующий забег начнётся с нуля —\nпрогресс между забегами не сохраняется.",
		"В главное меню",
		func(): show_menu("Долина спасена! Выбери героя — новый забег ждёт.")
	)


## Простой финальный экран с одной кнопкой.
func _show_end_screen(title: String, text: String, button_text: String, on_pressed: Callable) -> void:
	_clear_screen()

	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 56)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_lbl)

	var text_lbl := Label.new()
	text_lbl.text = text
	text_lbl.add_theme_font_size_override("font_size", 20)
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_lbl.modulate = Color(1, 1, 1, 0.8)
	box.add_child(text_lbl)

	var btn := Button.new()
	btn.text = button_text
	btn.custom_minimum_size = Vector2(260, 56)
	btn.add_theme_font_size_override("font_size", 24)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void:
		Settings.play_sfx(self, SFX_UI_CLICK)
		on_pressed.call()
	)
	box.add_child(btn)

	add_child(screen)
	_screen = screen
	_update_overlay()


# ---------- Оверлей: кнопки поверх экранов, модальные окна, пауза ----------

## Видимость кнопки сдачи и пауза боя зависят от текущего экрана.
func _update_overlay() -> void:
	_surrender_btn.visible = _screen is BattleScreen or _screen is GearScreen
	_refresh_pause()


## Бой на паузе, пока открыто модальное окно (настройки, подтверждение сдачи).
## Пауза — только на экране боя: в меню и лагере дерево не останавливаем,
## иначе замёрзнут их кнопки.
func _refresh_pause() -> void:
	get_tree().paused = _modal_count > 0 and _screen is BattleScreen


## Открыть модальное окно в слое поверх экранов (ставит бой на паузу).
func _open_modal(win: Control) -> void:
	_modal_count += 1
	win.closed.connect(_on_modal_closed)
	_settings_layer.add_child(win)
	_refresh_pause()


func _on_modal_closed() -> void:
	_modal_count = maxi(0, _modal_count - 1)
	_refresh_pause()


# ---------- Настройки и сдача забега ----------

## Кнопка-шестерёнка: живёт в отдельном слое поверх всех экранов игры.
## Слой работает и на паузе — иначе на паузе замерло бы само окно настроек.
func _build_settings_button() -> void:
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 10
	_settings_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_settings_layer)
	var btn := Settings.GearButton.new()
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.position = Vector2(-52, 10)
	btn.pressed.connect(_on_settings_pressed)
	_settings_layer.add_child(btn)


func _on_settings_pressed() -> void:
	_open_modal(Settings.SettingsWindow.new())


## Кнопка сдачи: белый флаг на красном, слева от шестерёнки.
## Видна только во время забега (лагерь и бой) — см. _update_overlay.
func _build_surrender_button() -> void:
	_surrender_btn = FlagButton.new()
	_surrender_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_surrender_btn.position = Vector2(-100, 10)
	_surrender_btn.visible = false
	_surrender_btn.pressed.connect(_on_surrender_pressed)
	_settings_layer.add_child(_surrender_btn)


func _on_surrender_pressed() -> void:
	var dlg := SurrenderDialog.new()
	dlg.confirmed.connect(_on_surrender_confirmed)
	_open_modal(dlg)


## Забег завершён досрочно: герой сбрасывается, возврат в главное меню.
func _on_surrender_confirmed() -> void:
	hero = null
	show_menu("Забег завершён. Выбери героя — долина ждёт нового защитника.")


## Кнопка сдачи забега: красный круг с белым флагом, рисуется кодом.
class FlagButton:
	extends Control

	signal pressed

	const BTN_SIZE := 40.0

	var _hover := false


	func _init() -> void:
		custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Завершить забег"
		mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hover = false; queue_redraw())


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()


	func _draw() -> void:
		var c := size * 0.5
		var s := size.x
		var bg := Color(0.78, 0.25, 0.22) if _hover else Color(0.62, 0.17, 0.16)
		# Красная круглая подложка
		draw_circle(c, s * 0.44, bg)
		var white := Color(0.95, 0.95, 0.97)
		# Древко флага
		draw_rect(Rect2(c + Vector2(-s * 0.15, -s * 0.24), Vector2(s * 0.05, s * 0.5)), white)
		# Полотнище флага
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-s * 0.1, -s * 0.24),
			c + Vector2(s * 0.24, -s * 0.15),
			c + Vector2(-s * 0.1, -s * 0.06),
		]), white)


## Окно подтверждения сдачи забега (модальное, ставит бой на паузу).
class SurrenderDialog:
	extends Control

	signal confirmed
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
		style.border_color = Color(0.75, 0.3, 0.28)
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
		title.text = "Завершить забег?"
		title.add_theme_font_size_override("font_size", 28)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)

		var text := Label.new()
		text.text = "Весь прогресс текущего забега будет потерян,\nгерой вернётся в главное меню."
		text.add_theme_font_size_override("font_size", 18)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.modulate = Color(1, 1, 1, 0.8)
		box.add_child(text)

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)

		var yes := Button.new()
		yes.text = "Завершить забег"
		yes.custom_minimum_size = Vector2(200, 48)
		yes.add_theme_font_size_override("font_size", 20)
		yes.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		yes.pressed.connect(_on_confirm)
		row.add_child(yes)

		var no := Button.new()
		no.text = "Отмена"
		no.custom_minimum_size = Vector2(160, 48)
		no.add_theme_font_size_override("font_size", 20)
		no.pressed.connect(_on_cancel)
		row.add_child(no)


	func _on_confirm() -> void:
		confirmed.emit()
		closed.emit()
		queue_free()


	func _on_cancel() -> void:
		closed.emit()
		queue_free()


	func _sync_size() -> void:
		size = get_viewport_rect().size
