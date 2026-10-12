class_name GearScreen
extends Control

## Экран снаряжения (лагерь): характеристики героя, ячейки экипировки,
## рюкзак на 30 ячеек, продажа за опыт и кнопка «В путь».
## Интерфейс строится кодом. Предметы — иконки по типу слота, цвет — по редкости.
## Надеть/снять/продать — перетаскиванием (drag & drop); характеристики
## предмета — во всплывающей подсказке при наведении.

signal embark_pressed

## Входные данные (заполняет Main)
var hero: Hero
var wave := 1
var wins := 0
var message := ""

const SLOT_DISPLAY := {"weapon": "Оружие", "weapon1": "Оружие I", "weapon2": "Оружие II", "shield": "Щит", "armor": "Броня", "amulet": "Амулет", "ring1": "Кольцо I", "ring2": "Кольцо II"}
const CELL := 64.0
const INVENTORY_COLS := 6


func _ready() -> void:
	rebuild()


## Полностью перестроить интерфейс (после любого изменения данных).
## ВАЖНО: удаляем через queue_free, а не free — иначе игра падает,
## когда rebuild вызван обработчиком узла, который мы удаляем.
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

	# Отступ под кнопку настроек (шестерёнка в правом верхнем углу)
	var gear_gap := Control.new()
	gear_gap.custom_minimum_size.x = 40
	bar.add_child(gear_gap)


func _build_hero_panel(columns: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size.x = 320
	columns.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := Label.new()
	header.text = "%s — уровень %d" % [hero.hero_name(), hero.level]
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


## Панель экипировки: 5 ячеек-слотов с иконками.
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

	for slot in hero.equip_slots():
		var it: Item = hero.equipment[slot]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)

		var cell := InvCell.new()
		cell.gear = self
		cell.slot = slot
		cell.item = it
		row.add_child(cell)

		var info := VBoxContainer.new()
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(info)
		var slot_lbl := Label.new()
		slot_lbl.text = SLOT_DISPLAY[slot]
		slot_lbl.modulate = Color(1, 1, 1, 0.55)
		slot_lbl.add_theme_font_size_override("font_size", 14)
		info.add_child(slot_lbl)
		var item_lbl := Label.new()
		if it != null:
			item_lbl.text = it.name
			item_lbl.modulate = it.rarity_color()
		else:
			item_lbl.text = "— пусто —"
			item_lbl.modulate = Color(1, 1, 1, 0.35)
		info.add_child(item_lbl)

	var hint := Label.new()
	hint.text = "Перетащи предмет из рюкзака на ячейку,\nчтобы надеть. Перетащи надетый предмет\nв рюкзак, чтобы снять."
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.add_theme_font_size_override("font_size", 14)
	box.add_child(hint)


## Панель рюкзака: сетка 6×5 ячеек (30) + зона продажи.
func _build_inventory_panel(columns: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := Label.new()
	header.text = "Рюкзак (%d / %d)" % [hero.inventory.size(), Hero.INVENTORY_SIZE]
	header.add_theme_font_size_override("font_size", 22)
	box.add_child(header)

	var grid := GridContainer.new()
	grid.columns = INVENTORY_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	for i in Hero.INVENTORY_SIZE:
		var cell := InvCell.new()
		cell.gear = self
		if i < hero.inventory.size():
			cell.item = hero.inventory[i]
		grid.add_child(cell)

	# Зона продажи: перетащить предмет из рюкзака — получить опыт
	var sell_row := HBoxContainer.new()
	sell_row.add_theme_constant_override("separation", 10)
	box.add_child(sell_row)

	var sell := InvCell.new()
	sell.gear = self
	sell.is_sell = true
	sell.tooltip_text = "Перетащи сюда предмет из рюкзака, чтобы продать его за опыт"
	sell_row.add_child(sell)

	var sell_info := VBoxContainer.new()
	sell_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sell_row.add_child(sell_info)
	var sell_lbl := Label.new()
	sell_lbl.text = "Продажа за опыт"
	sell_lbl.add_theme_font_size_override("font_size", 18)
	sell_lbl.modulate = Color(0.95, 0.8, 0.3)
	sell_info.add_child(sell_lbl)
	var sell_hint := Label.new()
	sell_hint.text = "Обычный +%d · Необычный +%d · Редкий +%d\nМистический +%d · Легендарный +%d · Артефакт +%d" % Hero.SELL_XP
	sell_hint.modulate = Color(1, 1, 1, 0.5)
	sell_hint.add_theme_font_size_override("font_size", 13)
	sell_info.add_child(sell_hint)


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


## Подходит ли предмет ячейке экипировки (кольца — обеим ячейкам,
## оружие — обоим оружейным слотам Вора).
func _slot_matches(item: Item, slot: String) -> bool:
	return Hero.slot_accepts(slot, item.slot)


## Можно ли снять предмет в рюкзак (есть ли свободная ячейка).
func _can_unequip() -> bool:
	return hero.inventory.size() < Hero.INVENTORY_SIZE


## Бросок предмета на ячейку: надеть / снять / продать.
## При надевании передаём целевую ячейку — предмет встаёт именно в неё.
func _on_cell_drop(cell: InvCell, data: Dictionary) -> void:
	var item: Item = data["item"]
	if cell.is_sell:
		var xp := hero.sell_item(item)
		message = "Продан: %s (+%d опыта)" % [item.name, xp]
	elif cell.slot != "":
		hero.equip(item, cell.slot)
		message = "Надето: %s" % item.name
	else:
		hero.unequip(data["from"])
		message = "Снято в рюкзак: %s" % item.name
	rebuild()


## Иконка предмета по типу слота: одна на все предметы слота,
## цвет — по редкости (серая и полупрозрачная — пустая ячейка).
static func draw_slot_icon(cv: Control, slot: String, c: Vector2, s: float, color: Color) -> void:
	match slot:
		"shield":
			# Баклер: круг с ободком и умбоном
			cv.draw_circle(c, 0.42 * s, color)
			cv.draw_circle(c, 0.28 * s, color.darkened(0.3))
			cv.draw_circle(c, 0.1 * s, color)
		"weapon":
			# Клинок: лезвие, гарда, рукоять
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.5 * s),
				c + Vector2(0.1 * s, 0.08 * s),
				c + Vector2(-0.1 * s, 0.08 * s),
			]), color)
			cv.draw_rect(Rect2(c + Vector2(-0.26 * s, 0.1 * s), Vector2(0.52 * s, 0.08 * s)), color)
			cv.draw_rect(Rect2(c + Vector2(-0.06 * s, 0.18 * s), Vector2(0.12 * s, 0.24 * s)), color)
			cv.draw_circle(c + Vector2(0, 0.47 * s), 0.07 * s, color)
		"armor":
			# Щит
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.34 * s, -0.38 * s),
				c + Vector2(0.34 * s, -0.38 * s),
				c + Vector2(0.34 * s, 0.05 * s),
				c + Vector2(0, 0.45 * s),
				c + Vector2(-0.34 * s, 0.05 * s),
			]), color)
		"amulet":
			# Самоцвет на цепочке
			cv.draw_arc(c + Vector2(0, -0.28 * s), 0.14 * s, 0, TAU, 16, color, 0.06 * s)
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.08 * s),
				c + Vector2(0.26 * s, 0.14 * s),
				c + Vector2(0.15 * s, 0.42 * s),
				c + Vector2(-0.15 * s, 0.42 * s),
				c + Vector2(-0.26 * s, 0.14 * s),
			]), color)
		"ring":
			# Кольцо
			cv.draw_arc(c, 0.3 * s, 0, TAU, 24, color, 0.12 * s)
			cv.draw_circle(c + Vector2(0, -0.3 * s), 0.1 * s, color)


## Ячейка интерфейса: экипировка, рюкзак или зона продажи.
## Рисует фон, рамку и иконку; поддерживает drag & drop.
class InvCell:
	extends Control

	var gear: GearScreen = null
	var item: Item = null
	var slot := ""      # слот экипировки; "" — ячейка рюкзака
	var is_sell := false


	func _init() -> void:
		custom_minimum_size = Vector2(GearScreen.CELL, GearScreen.CELL)


	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.14, 0.16, 0.21))
		var border := Color(0.3, 0.33, 0.4)
		if item != null:
			border = item.rarity_color()
		elif is_sell:
			border = Color(0.95, 0.8, 0.3)
		draw_rect(r, border, false, 2.0)
		if item != null:
			GearScreen.draw_slot_icon(self, item.slot, size / 2, size.x * 0.72, item.rarity_color())
			tooltip_text = "%s (%s)\n%s · %s" % [item.name, item.rarity_name(), item.slot_name(), item.bonuses_text()]
		elif slot != "":
			var base := slot
			if slot == "ring1" or slot == "ring2":
				base = "ring"
			elif slot == "weapon1" or slot == "weapon2":
				base = "weapon"
			GearScreen.draw_slot_icon(self, base, size / 2, size.x * 0.72, Color(1, 1, 1, 0.18))
			tooltip_text = "Пустая ячейка: %s" % GearScreen.SLOT_DISPLAY[slot]
		elif is_sell:
			# Монета
			draw_circle(size / 2, size.x * 0.2, Color(0.95, 0.8, 0.3))
			draw_circle(size / 2, size.x * 0.13, Color(0.75, 0.6, 0.2))
		else:
			tooltip_text = "Пустая ячейка рюкзака"


	func _get_drag_data(_pos: Vector2) -> Variant:
		if item == null or is_sell:
			return null
		var data := {"item": item, "from": slot if slot != "" else "inventory"}
		var preview := Control.new()
		preview.custom_minimum_size = Vector2(48, 48)
		var icon := _DragIcon.new()
		icon.icon_slot = item.slot
		icon.icon_color = item.rarity_color()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		preview.add_child(icon)
		set_drag_preview(preview)
		return data


	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if gear == null or typeof(data) != TYPE_DICTIONARY or not data.has("item"):
			return false
		if is_sell:
			return data["from"] == "inventory"
		if slot != "":
			return data["from"] == "inventory" and gear._slot_matches(data["item"], slot)
		# Ячейка рюкзака: принимает только надетые предметы, и если есть место
		return data["from"] != "inventory" and gear._can_unequip()


	func _drop_data(_pos: Vector2, data: Variant) -> void:
		gear._on_cell_drop(self, data)


## Иконка для превью перетаскивания.
class _DragIcon:
	extends Control

	var icon_slot := "weapon"
	var icon_color := Color.WHITE


	func _draw() -> void:
		GearScreen.draw_slot_icon(self, icon_slot, size / 2, size.x * 0.8, icon_color)
