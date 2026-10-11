class_name GameMain
extends Node

## Корневой узел игры: хранит состояние забега и переключает экраны.
## Экраны: лагерь (GearScreen) → бой (BattleScreen) → победа/поражение → снова лагерь.

var hero: Hero
var wave := 1
var wins := 0

var _screen: Control = null


func _ready() -> void:
	hero = Hero.new()
	show_gear("Добро пожаловать в долину! Собери героя и жми «В путь».")


func _clear_screen() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
		_screen = null


func show_gear(msg: String) -> void:
	_clear_screen()
	var gear := GearScreen.new()
	gear.hero = hero
	gear.wave = wave
	gear.wins = wins
	gear.message = msg
	gear.embark_pressed.connect(_on_embark)
	add_child(gear)
	_screen = gear


func _on_embark() -> void:
	_clear_screen()
	var battle := BattleScreen.new()
	battle.hero = hero
	battle.wave = wave
	battle.wins = wins
	battle.wave_cleared.connect(_on_wave_cleared)
	battle.hero_died.connect(_on_hero_died)
	battle.boss_defeated.connect(_on_boss_defeated)
	add_child(battle)
	_screen = battle


func _on_wave_cleared() -> void:
	wave += 1
	show_gear("Волна пройдена! Герой отдохнул, раны затянулись. Проверь рюкзак.")


func _on_hero_died() -> void:
	_show_end_screen(
		"Поражение",
		"Герой пал в бою, но весь собранный лут и опыт сохранены.\nВложи очки характеристик, обнови снарягу — и вперёд, снова!",
		"Вернуться в лагерь",
		func(): show_gear("Не беда! Попробуй другую сборку — волна та же.")
	)


func _on_boss_defeated() -> void:
	wins += 1
	wave = 1
	_show_end_screen(
		"Победа!",
		"Каменный страж повержен, долина спасена!\nПобед над боссом: %d.\nНовый заход: враги станут сильнее, а герой сохранит всё, что накопил." % wins,
		"Новый заход",
		func(): show_gear("Новый заход! Враги усилились — проверь снарягу.")
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
