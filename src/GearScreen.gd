class_name GearScreen
extends Control

## Экран снаряжения (лагерь): характеристики героя, слоты экипировки,
## рюкзак и кнопка «В путь». Весь интерфейс строится кодом.

signal embark_pressed

## Входные данные (заполняет Main)
var hero: Hero
var wave := 1
var wins := 0
var message := ""

const SLOT_ORDER := ["weapon", "armor", "amulet", "ring1", "ring2"]
const SLOT_DISPLAY := {"weapon": "Оружие", "armor": "Броня", "amulet": "Амулет", "ring1": "Кольцо I", "ring2": "Кольцо II"}


func _ready() -> void:
	rebuild()


## Полностью перестроить интерфейс (после любого изменения данных).
## ВАЖНО: удаляем через queue_free, а не free — иначе игра падает,
## когда rebuild вызван кликом по кнопке, которую мы удаляем.
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
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

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	_build_top_bar(root)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)

	_build_hero_panel(columns)
	_build_equipment_panel(columns)
	_build_inventory_panel(columns)
	_build_bottom_bar(root)


func _build_top_bar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	root.add_child(bar)

	var title := Label.new()
	title.text = "Хранитель Долины — Лагерь"
	title.add_theme_font_size_override("font_size", 26)
	bar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var wave_lbl := Label.new()
	if wave >= Enemies.TOTAL_WAVES:
		wave_lbl.text = "Далее: ФИНАЛЬНЫЙ БОСС"
	else:
		wave_lbl.text = "Далее: волна %d / %d" % [wave, Enemies.TOTAL_WAVES]
	wave_lbl.add_theme_font_size_override("font_size", 18)
	bar.add_child(wave_lbl)

	var wins_lbl := Label.new()
	wins_lbl.text = "Побед над боссом: %d" % wins
	wins_lbl.add_theme_font_size_override("font_size", 18)
	wins_lbl.modulate = Color(0.95, 0.85, 0.4)
	bar.add_child(wins_lbl)


func _build_hero_panel(columns: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size.x = 320
	columns.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := Label.new()
	header.text = "Герой — уровень %d" % hero.level
	header.add_theme_font_size_override("font_size", 22)
	box.add_child(header)

	var xp_bar := ProgressBar.new()
	xp_bar.max_value = hero.xp_to_next()
	xp_bar.value = hero.xp
	xp_bar.custom_minimum_size.y = 18
	xp_bar.show_percentage = false
	box.add_child(xp_bar)

	var xp_lbl := Label.new()
	xp_lbl.text = "Опыт: %d / %d" % [hero.xp, hero.xp_to_next()]
	xp_lbl.modulate = Color(1, 1, 1, 0.7)
	box.add_child(xp_lbl)

	var hp_lbl := Label.new()
	hp_lbl.text = "Здоровье: %d / %d" % [int(hero.start_hp()), int(hero.max_hp())]
	hp_lbl.add_theme_font_size_override("font_size", 18)
	hp_lbl.modulate = Color(0.95, 0.55, 0.5)
	box.add_child(hp_lbl)

	var points := Label.new()
	points.text = "Свободные очки: %d" % hero.stat_points
	points.add_theme_font_size_override("font_size", 18)
	points.modulate = Color(0.5, 1.0, 0.6) if hero.stat_points > 0 else Color(1, 1, 1, 0.6)
	box.add_child(points)

	var stats := hero.get_stats()
	for key in Item.STAT_ORDER:
		var row := HBoxContainer.new()
		box.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = Item.STAT_NAMES[key]
		name_lbl.custom_minimum_size.x = 150
		row.add_child(name_lbl)

		var val := Label.new()
		val.text = "%.2f" % stats[key] if key == "spd" or key == "regen" else str(int(stats[key]))
		val.add_theme_font_size_override("font_size", 18)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 30)
		plus.visible = hero.stat_points > 0
		plus.tooltip_text = "+%s за очко" % str(Hero.PER_POINT[key])
		plus.pressed.connect(_on_stat_plus.bind(key))
		row.add_child(plus)


func _build_equipment_panel(columns: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := Label.new()
	header.text = "Экипировка"
	header.add_theme_font_size_override("font_size", 22)
	box.add_child(header)

	for slot in SLOT_ORDER:
		var it: Item = hero.equipment[slot]
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 64)
		if it != null:
			btn.text = "%s\n%s — %s" % [SLOT_DISPLAY[slot], it.name, it.bonuses_text()]
			btn.add_theme_color_override("font_color", it.rarity_color())
			btn.tooltip_text = "Нажми, чтобы снять в рюкзак"
		else:
			btn.text = "%s\n— пусто —" % SLOT_DISPLAY[slot]
			btn.modulate = Color(1, 1, 1, 0.5)
		btn.pressed.connect(_on_slot_pressed.bind(slot))
		box.add_child(btn)

	var hint := Label.new()
	hint.text = "Клик по надетому предмету — снять.\nКлик по предмету в рюкзаке — надеть."
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.add_theme_font_size_override("font_size", 14)
	box.add_child(hint)


func _build_inventory_panel(columns: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := Label.new()
	header.text = "Рюкзак (%d)" % hero.inventory.size()
	header.add_theme_font_size_override("font_size", 22)
	box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if hero.inventory.is_empty():
		var empty := Label.new()
		empty.text = "Пока пусто. Снаряга появится\nпосле первых волн."
		empty.modulate = Color(1, 1, 1, 0.5)
		list.add_child(empty)
		return

	var sorted := hero.inventory.duplicate()
	sorted.sort_custom(func(a, b):
		if a.slot != b.slot:
			return a.slot < b.slot
		return a.rarity > b.rarity)
	for it in sorted:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s\n%s · %s" % [it.name, it.slot_name(), it.bonuses_text()]
		btn.add_theme_color_override("font_color", it.rarity_color())
		btn.pressed.connect(_on_item_pressed.bind(it))
		list.add_child(btn)


func _build_bottom_bar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	root.add_child(bar)

	var msg := Label.new()
	msg.text = message
	msg.add_theme_font_size_override("font_size", 18)
	msg.modulate = Color(0.55, 0.9, 0.95)
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(msg)

	var go := Button.new()
	go.text = "В путь →"
	go.custom_minimum_size = Vector2(180, 52)
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(func(): embark_pressed.emit())
	bar.add_child(go)


func _on_stat_plus(stat: String) -> void:
	if hero.allocate(stat):
		rebuild()


func _on_slot_pressed(slot: String) -> void:
	if hero.equipment[slot] != null:
		hero.unequip(slot)
		rebuild()


func _on_item_pressed(item: Item) -> void:
	hero.equip(item)
	rebuild()
