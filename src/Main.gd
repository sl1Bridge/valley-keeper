class_name GameMain
extends Node

## Корневой узел игры: хранит состояние текущего забега и переключает экраны.
## Экраны: главное меню (MainMenu) → лагерь (GearScreen) → бой (BattleScreen) →
## победа/поражение → лагерь или главное меню.
## Прогресса между забегами нет: каждый забег начинается с новым героем 1 уровня.
## Поверх всех экранов — кнопка настроек (шестерёнка в правом верхнем углу).

var hero: Hero = null  # герой текущего забега
var selected_kind := ""

var _screen: Control = null
var _settings_layer: CanvasLayer


func _ready() -> void:
	Settings.ensure_buses()
	_build_settings_button()
	show_menu("")


func _clear_screen() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
		_screen = null


# ---------- Главное меню ----------

func show_menu(msg: String) -> void:
	_clear_screen()
	var menu := MainMenu.new()
	menu.selected_kind = selected_kind
	menu.message = msg
	menu.start_pressed.connect(_on_menu_start)
	add_child(menu)
	_screen = menu


## Начало забега: всегда новый герой 1 уровня, прогресс между забегами не сохраняется.
func _on_menu_start(kind: String) -> void:
	selected_kind = kind
	hero = Hero.new(kind)
	show_gear("Забег начинается! Собери героя и жми «В путь».")


# ---------- Лагерь и бой ----------

func show_gear(msg: String) -> void:
	_clear_screen()
	var gear := GearScreen.new()
	gear.hero = hero
	gear.wave = hero.wave
	gear.message = msg
	gear.embark_pressed.connect(_on_embark)
	add_child(gear)
	_screen = gear


func _on_embark() -> void:
	_clear_screen()
	var battle := BattleScreen.new()
	battle.hero = hero
	battle.wave = hero.wave
	battle.wave_cleared.connect(_on_wave_cleared)
	battle.hero_died.connect(_on_hero_died)
	battle.boss_defeated.connect(_on_boss_defeated)
	add_child(battle)
	_screen = battle


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
	btn.pressed.connect(on_pressed)
	box.add_child(btn)

	add_child(screen)
	_screen = screen


# ---------- Настройки ----------

## Кнопка-шестерёнка: живёт в отдельном слое поверх всех экранов игры.
func _build_settings_button() -> void:
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 10
	add_child(_settings_layer)
	var btn := Settings.GearButton.new()
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.position = Vector2(-52, 10)
	btn.pressed.connect(_on_settings_pressed)
	_settings_layer.add_child(btn)


func _on_settings_pressed() -> void:
	var popup := Settings.SettingsWindow.new()
	_settings_layer.add_child(popup)
