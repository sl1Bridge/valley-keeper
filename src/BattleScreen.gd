class_name BattleScreen
extends Control

## Экран боя в изометрии: земля ромбами, холмы и небо на фоне (фон позже будет
## меняться от уровня). Герой стоит слева, враги — строем справа; строй зависит
## от числа врагов. Все атакуют на дистанции. Герой выбирает случайную цель и
## бьёт её до смерти, затем выбирает следующую.
## С врагов с шансом падают сундуки (1 случайный предмет), после победы над всеми
## врагами в центре появляется финальный сундук (выбор 1 из 3, награды реже).
## Сундуки открываются кликом; волна завершается, только когда собраны все сундуки.
## Исключение — босс: его гибель сразу завершает забег победой, без фазы сундуков.
## Бой можно ускорять: x1 / x2.

signal wave_cleared
signal hero_died
signal boss_defeated

const HERO_POS := Vector2(320, 460)
const FORMATION_ANCHOR := Vector2(880, 420)  # центр строя врагов
const BOSS_POS := Vector2(920, 450)
const FINAL_CHEST_POS := Vector2(640, 430)  # центр поля боя

## Строи по числу врагов: смещения от FORMATION_ANCHOR.
## Один враг — напротив героя; больше — разные построения, не колонной.
const FORMATIONS := {
	1: [Vector2(0, 40)],
	2: [Vector2(-40, -20), Vector2(40, 60)],
	3: [Vector2(0, -60), Vector2(-60, 30), Vector2(60, 70)],
	4: [Vector2(0, -80), Vector2(-70, -10), Vector2(70, 20), Vector2(0, 90)],
	5: [Vector2(0, -100), Vector2(-80, -30), Vector2(80, -10), Vector2(-40, 70), Vector2(50, 90)],
	6: [Vector2(-20, -110), Vector2(70, -80), Vector2(-80, -30), Vector2(10, 0), Vector2(90, 30), Vector2(-30, 90)],
}

## Входные данные (заполняет Main до добавления на сцену)
var hero: Hero
var wave := 1

## Выбранная скорость боя запоминается между боями (сессия игры).
static var persisted_speed := 1.0

var _rng := RandomNumberGenerator.new()
var _state := "fight"  # "fight" | "loot" | "done"
var _kills := 0
var _enemy_total := 0
var _boss_dead := false
var _speed := 1.0

var _world: Node2D
var _hero_actor: Actor
var _enemies := []

# Сундуки на поле боя (узлы Chest)
var _chests := []
var _current_choices := []
var _chest_ui: Control = null

var _wave_label: Label
var _kills_label: Label
var _chests_label: Label
var _hint_label: Label
var _speed_btn: Button
var _center_label: Label


func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Backdrop.new())
	_build_hud()
	_world = Node2D.new()
	_world.y_sort_enabled = true  # глубина: ниже на экране — ближе к зрителю
	add_child(_world)
	_spawn_hero()
	_spawn_enemies()
	set_speed(persisted_speed)  # скорость из прошлого боя
	_update_hud()


func _build_hud() -> void:
	var hud := HBoxContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = 16
	hud.offset_top = 10
	hud.offset_right = -112  # справа — кнопки сдачи (флаг) и настроек (шестерёнка)
	hud.add_theme_constant_override("separation", 32)
	add_child(hud)

	_wave_label = Label.new()
	_wave_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_wave_label)

	_kills_label = Label.new()
	_kills_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_kills_label)

	_chests_label = Label.new()
	_chests_label.add_theme_font_size_override("font_size", 22)
	_chests_label.modulate = Color(0.95, 0.8, 0.3)
	hud.add_child(_chests_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)

	_speed_btn = Button.new()
	_speed_btn.text = "Скорость: x1"
	_speed_btn.pressed.connect(_on_speed_pressed)
	hud.add_child(_speed_btn)

	_hint_label = Label.new()
	_hint_label.text = "Бой идёт автоматически"
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.modulate = Color(1, 1, 1, 0.8)
	hud.add_child(_hint_label)

	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.add_theme_font_size_override("font_size", 42)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.visible = false
	add_child(_center_label)


func _spawn_hero() -> void:
	_hero_actor = Actor.new()
	# Имя и внешность — из реестра героев (выбор в главном меню)
	_hero_actor.setup(hero.hero_name(), _hero_battle_stats(), hero.body_color(), hero.body_shape(), 30.0, "hero")
	# Герой входит в бой с тем здоровьем, что осталось после прошлой волны + передышка
	_hero_actor.hp = clampf(hero.start_hp(), 1.0, _hero_actor.max_hp)
	_hero_actor.position = HERO_POS
	_hero_actor.engaged = true
	_hero_actor.died.connect(_on_hero_died)
	_hero_actor.damaged.connect(_on_actor_damaged)
	_hero_actor.attacked.connect(_on_actor_attacked)
	_hero_actor.evaded.connect(_on_actor_evaded)
	_hero_actor.poisoned.connect(_on_hero_poisoned)
	_world.add_child(_hero_actor)


## Боевые характеристики героя: сырые очки превращаем в реальные значения
## (здоровье из Выносливости, атак/с из Ловкости, % защиты, шанс уворота/блока).
## Отравление временно снижает базовые характеристики на процент от стаков.
func _hero_battle_stats() -> Dictionary:
	var stats := hero.get_stats()
	var poison := 0.0
	if is_instance_valid(_hero_actor):
		poison = Hero.poison_pct(_hero_actor.poison_times.size())
	if poison > 0.0:
		for k in ["atk", "spd", "def", "surv"]:
			stats[k] = stats.get(k, 0.0) * (1.0 - poison)
	var eff := Hero.effective(stats)
	stats["atk"] = eff["atk"]  # сила тоже проходит капы очков
	stats["hp"] = eff["max_hp"]
	stats["spd"] = eff["aps"]
	_apply_hero_effects(_hero_actor, eff)
	return stats


## Стаки отравления изменились: пересчитать характеристики героя
## (макс. HP может упасть — текущее здоровье обрезается, но не лечится).
func _on_hero_poisoned() -> void:
	_hero_actor.stats = _hero_battle_stats()
	_hero_actor.max_hp = float(maxi(1, int(_hero_actor.stats["hp"])))
	_hero_actor.hp = minf(_hero_actor.hp, _hero_actor.max_hp)
	_hero_actor.queue_redraw()


## Применить к бойцу производные характеристики героя (защита %, реген, уворот/блок).
func _apply_hero_effects(a: Actor, eff: Dictionary) -> void:
	if a == null:
		return
	a.def_pct = eff["def_pct"]
	a.regen = eff["regen_hp"]
	a.evasion = eff["class_pct"]
	a.evasion_label = "Блок!" if hero.kind == "knight" else "Уворот!"


## Остаток здоровья героя (Main забирает после боя).
func hero_hp() -> float:
	if is_instance_valid(_hero_actor):
		return _hero_actor.hp
	return 0.0


func _spawn_enemies() -> void:
	var comp := Enemies.wave_composition(wave, _rng)
	_enemy_total = comp.size()
	var formation: Array = FORMATIONS[mini(comp.size(), Enemies.MAX_ENEMIES)]
	for i in comp.size():
		var type: String = comp[i]
		var pos: Vector2 = BOSS_POS if type == "boss" else FORMATION_ANCHOR + formation[i]
		_add_enemy(type, pos, false)
	_pick_hero_target()


## Создать врага на поле боя: внешность, сигналы, подсказка при наведении.
## taunt — свойство «Провокация»: герой атакует такого врага в первую очередь.
## summoned — призван боссом: не даёт опыта и не оставляет сундуков.
func _add_enemy(type: String, pos: Vector2, taunt: bool, summoned := false) -> Actor:
	var stats := Enemies.scaled(type, wave)
	stats["summoned"] = summoned
	var def: Dictionary = Enemies.TYPES[type]
	var e := Actor.new()
	e.setup(stats["name"], stats, def["color"], def["shape"], def["size"], "enemy")
	# Защита врага — по той же формуле затухания, что и у героя
	e.def_pct = Hero.diminish(float(stats.get("def", 0)), 1.0, Hero.DEF_K)
	e.taunt = taunt
	e.position = pos
	e.engaged = true
	e.target = _hero_actor
	e.died.connect(_on_enemy_died)
	e.damaged.connect(_on_actor_damaged)
	e.attacked.connect(_on_actor_attacked)
	e.evaded.connect(_on_actor_evaded)
	if type == "boss":
		# Умение босса: призыв союзников с провокацией (прогресс-бар над боссом)
		e.cast_interval = Enemies.SUMMON_INTERVAL
		e.cast_ready.connect(_on_boss_cast)
	# Зона наведения: подсказка с характеристиками, эффектами, умениями и свойствами
	var hover := Control.new()
	hover.position = Vector2(-e.radius, -e.radius * 2.0)
	hover.size = Vector2(e.radius * 2.0, e.radius * 2.0)
	hover.mouse_filter = Control.MOUSE_FILTER_PASS
	hover.tooltip_text = _enemy_tooltip(type, stats, taunt)
	e.add_child(hover)
	_world.add_child(e)
	_enemies.append(e)
	return e


## Умение босса «Призыв»: случайная комбинация союзников на сумму бюджета
## призыва (цены — Enemies.VALUES, последний может округлить сумму вверх).
## У всех — свойство «Провокация»: герой переключается на них, пока они живы.
func _on_boss_cast(boss: Actor) -> void:
	if _state != "fight" or not boss.alive:
		return
	var active := 0
	for e in _enemies:
		if e.alive and e.taunt:
			active += 1
	var slots: int = Enemies.SUMMON_MAX_ACTIVE - active
	if slots <= 0:
		return
	var spent := 0
	var i := 0
	var offsets := [Vector2(-80, -70), Vector2(-100, 20), Vector2(-70, 100)]
	while spent < Enemies.SUMMON_VALUE and i < slots:
		var type: String = Enemies.SUMMON_POOL[_rng.randi() % Enemies.SUMMON_POOL.size()]
		spent += Enemies.VALUES[type]
		_add_enemy(type, boss.position + offsets[i % offsets.size()], true, true)
		_enemy_total += 1  # призванные тоже считаются врагами волны
		i += 1
	_spawn_popup("Призыв!", boss.position + Vector2(-40, -boss.radius * 2.0 - 70), Color(0.72, 0.5, 0.95), 20)
	_update_hud()
	# Провокация: герой бьёт призванных в приоритете, босс — только когда они мертвы
	if _hero_actor.target == null or not _hero_actor.target.taunt:
		_pick_hero_target()


## Подсказка при наведении на врага: характеристики, эффекты,
## умения и свойства (провокация).
func _enemy_tooltip(type: String, stats: Dictionary, taunt := false) -> String:
	var def_pct := Hero.diminish(float(stats.get("def", 0)), 1.0, Hero.DEF_K)
	var lines := PackedStringArray()
	lines.append(str(stats["name"]))
	lines.append("Здоровье: %d · Атака: %d · Скорость: %.1f уд/с" % [int(stats["hp"]), int(stats["atk"]), float(stats["spd"])])
	lines.append("Защита: %d (−%d%% урона) · Опыт: %d" % [int(stats.get("def", 0)), roundi(def_pct * 100.0), int(stats.get("xp", 0))])
	var eff := Enemies.effect_desc(type)
	if eff != "":
		lines.append("Может наложить: " + eff)
	var ability := Enemies.ability_desc(type)
	if ability != "":
		lines.append("Умение: " + ability)
	if taunt:
		lines.append("Провокация: герой атакует этого врага в первую очередь")
	if stats.get("summoned", false):
		lines.append("Призван боссом: не даёт опыта и сундуков")
	return "\n".join(lines)


## Герой выбирает случайную живую цель.
## Враги с провокацией — в приоритете: пока они живы, других герой не бьёт.
func _pick_hero_target() -> void:
	var alive := []
	for e in _enemies:
		if e.alive:
			alive.append(e)
	if alive.is_empty():
		_hero_actor.target = null
		_hero_actor.engaged = false
	else:
		var taunters := []
		for e in alive:
			if e.taunt:
				taunters.append(e)
		var pool := taunters if not taunters.is_empty() else alive
		_hero_actor.target = pool[_rng.randi_range(0, pool.size() - 1)]
		_hero_actor.engaged = true


func _update_hud() -> void:
	if wave >= Enemies.TOTAL_WAVES:
		_wave_label.text = "ФИНАЛЬНАЯ ВОЛНА — БОСС"
	else:
		_wave_label.text = "Волна %d / %d" % [wave, Enemies.TOTAL_WAVES]
	_kills_label.text = "Побеждено: %d / %d" % [_kills, _enemy_total]
	_chests_label.text = "Сундуки: %d" % _chests.size()


func _process(delta: float) -> void:
	step(delta)


## Один шаг логики боя. Вынесен отдельно, чтобы прогонять в тестах.
func step(_delta: float) -> void:
	if _state != "fight":
		return
	if _kills >= _enemy_total:
		_start_loot_phase()


func _on_enemy_died(e: Actor) -> void:
	_kills += 1
	# Мёртвый враг не должен перехватывать мышь: на его место падает сундук,
	# а Control перекрывает клики по Area2D даже с mouse_filter PASS
	# (известное поведение движка, godotengine/godot#54529).
	for c in e.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var is_boss: bool = e.stats.get("type", "") == "boss"
	# Призванные боссом не дают ни опыта, ни сундуков
	var is_summoned: bool = e.stats.get("summoned", false)

	# Опыт и уровни
	if not is_summoned:
		var xp: int = int(e.stats.get("xp", 1))
		var levels := hero.add_xp(xp)
		_spawn_popup("+%d опыта" % xp, e.position + Vector2(-30, -e.radius * 2.0 - 40), Color(0.95, 0.9, 0.4), 18)
		if levels > 0:
			# Новый уровень: характеристики пересчитываются, герой лечится на часть от максимума
			_hero_actor.stats = _hero_battle_stats()
			_hero_actor.max_hp = int(_hero_actor.stats["hp"])
			var healed: float = _hero_actor.max_hp * Hero.LEVEL_UP_HEAL
			_hero_actor.hp = minf(_hero_actor.max_hp, _hero_actor.hp + healed)
			_hero_actor.queue_redraw()
			_spawn_popup("Уровень %d! +%d HP, +%d очко характеристик" % [hero.level, int(healed), Hero.POINTS_PER_LEVEL], _hero_actor.position + Vector2(-160, -_hero_actor.radius * 2.0 - 70), Color(0.5, 1.0, 0.6), 24)

	# Шанс сундука с врага (с босса и призванных сундуки не падают)
	if not is_boss and not is_summoned and _rng.randf() < Enemies.CHEST_DROP_CHANCE:
		_spawn_chest(e.position, false)
		_spawn_popup("Выпал сундук!", e.position + Vector2(-30, -e.radius * 2.0 - 75), Color(0.95, 0.8, 0.3), 20)

	# Герой переключается на следующую случайную цель
	if _hero_actor.target == e:
		_pick_hero_target()

	if is_boss:
		_boss_dead = true
		# Победа над боссом — сразу, открывать оставшиеся сундуки не нужно
		_state = "done"
		_hero_actor.engaged = false
		_hero_actor.clear_effects()  # эффекты живут только в фазе боя
		_show_center("Босс повержен!")
		_emit_deferred(boss_defeated)

	_update_hud()


func _on_hero_died(_a: Actor) -> void:
	if _state == "done":
		return
	_state = "done"
	for e in _enemies:
		e.engaged = false
	_hero_actor.clear_effects()  # эффекты живут только в фазе боя
	_show_center("Герой пал…")
	_emit_deferred(hero_died)


func _on_actor_damaged(a: Actor, amount: int) -> void:
	var col := Color(1, 0.45, 0.4) if a.team == "hero" else Color(1, 1, 1)
	_spawn_popup("-%d" % amount, a.position + Vector2(randf_range(-14, 14), -a.radius * 2.0 - 26), col, 16)


## Уворот/блок: всплывающая надпись («Уворот!» у Вора, «Блок!» у Рыцаря).
func _on_actor_evaded(a: Actor) -> void:
	_spawn_popup(a.evasion_label, a.position + Vector2(-24, -a.radius * 2.0 - 58), Color(0.6, 0.9, 1.0), 20)


## «Снаряд»: точка летит от атакующего к цели.
## Атаки врагов могут наложить на героя статусный эффект:
## слизень — отравление, волк — кровотечение, голем и босс — оглушение.
func _on_actor_attacked(src: Actor, dst: Actor) -> void:
	if dst.team == "hero":
		var etype: String = src.stats.get("type", "")
		if etype == "slime" and _rng.randf() < Enemies.POISON_CHANCE:
			dst.add_poison()
			_spawn_popup("Отравление!", dst.position + Vector2(-44, -dst.radius * 2.0 - 96), Color(0.5, 0.9, 0.4), 18)
		elif etype == "wolf" and _rng.randf() < Enemies.BLEED_CHANCE:
			dst.add_bleed()
			_spawn_popup("Кровотечение!", dst.position + Vector2(-52, -dst.radius * 2.0 - 96), Color(0.9, 0.35, 0.3), 18)
		elif Enemies.STUN_CHANCE.has(etype) and _rng.randf() < Enemies.STUN_CHANCE[etype]:
			dst.add_stun(Enemies.STUN_DURATION[etype])
			_spawn_popup("Оглушение!", dst.position + Vector2(-44, -dst.radius * 2.0 - 96), Color(1.0, 0.85, 0.3), 18)
	if not is_inside_tree():
		return
	var dot := ColorRect.new()
	dot.size = Vector2(10, 10)
	dot.color = Color(1.0, 0.85, 0.3) if src.team == "hero" else Color(0.9, 0.35, 0.3)
	dot.position = src.position + Vector2(-5, -src.radius - 5)
	_world.add_child(dot)
	var tween := create_tween()
	tween.tween_property(dot, "position", dst.position + Vector2(-5, -dst.radius - 5), 0.18)
	tween.tween_callback(dot.queue_free)


# ---------- Ускорение боя ----------

func _on_speed_pressed() -> void:
	set_speed(2.0 if _speed < 2.0 else 1.0)


## Скорость боя: x1 или x2 (масштабирует время движка, включая твины и таймеры).
## Выбор сохраняется в persisted_speed и действует в следующих боях.
func set_speed(mult: float) -> void:
	_speed = mult
	persisted_speed = mult
	Engine.time_scale = mult
	if is_instance_valid(_speed_btn):
		_speed_btn.text = "Скорость: x%d" % int(mult)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ---------- Сундуки ----------

## Ставит сундук на поле боя. is_final — финальный сундук волны (ценные награды).
func _spawn_chest(pos: Vector2, is_final: bool) -> Chest:
	var chest := Chest.new()
	chest.is_final = is_final
	chest.position = pos
	chest.clicked.connect(_on_chest_clicked)
	_chests.append(chest)
	_world.add_child(chest)
	_update_hud()
	return chest


func _start_loot_phase() -> void:
	if _state != "fight":
		return
	_state = "loot"
	_hero_actor.engaged = false
	_hero_actor.clear_effects()  # эффекты живут только в фазе боя
	# Финальный сундук — в центре экрана, награды в нём ценнее
	_spawn_chest(FINAL_CHEST_POS, true)
	_hint_label.text = "Победа! Кликай по сундукам, чтобы забрать награды"
	_update_hud()


## Клик по сундуку: вражеский выдаёт 1 случайный предмет сразу,
## финальный открывает выбор 1 из 3.
func _on_chest_clicked(chest: Chest) -> void:
	if not _chests.has(chest):
		return
	if chest.is_final:
		if not _current_choices.is_empty():
			return  # уже открыт, ждёт выбора предмета
		_open_final_chest()
		return
	var pos: Vector2 = chest.position
	_chests.erase(chest)
	chest.queue_free()
	var item := Item.generate(_rng, -1, wave, [], false, hero.kind)
	_grant_item(item, pos)
	_update_hud()
	_check_loot_done()


## Предмет — в рюкзак с учётом вместимости; если места не хватило,
## показываем, какой предмет потерян.
func _grant_item(item: Item, pos: Vector2) -> void:
	var lost := hero.add_item(item)
	_spawn_popup("Найдено: %s (%s)" % [item.name, item.rarity_name()], pos + Vector2(-70, -70), item.rarity_color(), 18)
	if lost != null:
		_spawn_popup("Рюкзак полон: потерян %s" % lost.name, pos + Vector2(-70, -100), Color(0.75, 0.75, 0.75), 16)


## Финальный сундук: 3 предмета на выбор, без повторов, редкость выше обычной.
func _open_final_chest() -> void:
	_current_choices = []
	var taken := []
	for i in Enemies.CHEST_CHOICES:
		var item := Item.generate(_rng, -1, wave, taken, true, hero.kind)
		taken.append(item.name)
		_current_choices.append(item)
	_show_chest_ui()


func _show_chest_ui() -> void:
	if _chest_ui != null:
		_chest_ui.queue_free()
	# Обертка на весь экран: окно сундука центрируется по экрану
	_chest_ui = CenterContainer.new()
	_chest_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_chest_ui)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.18, 0.97)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.65, 0.2)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	_chest_ui.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Финальный сундук — выбери предмет"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	box.add_child(columns)

	# Слева — три предмета на выбор
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	choices.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(choices)
	for item in _current_choices:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(360, 56)
		btn.text = "%s (%s)\n%s · %s" % [item.name, item.rarity_name(), item.slot_name(), item.bonuses_text()]
		btn.add_theme_color_override("font_color", item.rarity_color())
		btn.pressed.connect(_on_chest_choice.bind(item))
		choices.add_child(btn)

	columns.add_child(VSeparator.new())

	# Справа — что сейчас на герое и что лежит в рюкзаке: проще сравнить
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	columns.add_child(side)

	var eq_title := Label.new()
	eq_title.text = "Сейчас на герое:"
	eq_title.add_theme_font_size_override("font_size", 16)
	side.add_child(eq_title)
	for slot in hero.equip_slots():
		var it: Item = hero.equipment[slot]
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		if it != null:
			l.text = "%s: %s — %s" % [GearScreen.SLOT_DISPLAY[slot], it.name, it.bonuses_text()]
			l.modulate = it.rarity_color()
		else:
			l.text = "%s: — пусто —" % GearScreen.SLOT_DISPLAY[slot]
			l.modulate = Color(1, 1, 1, 0.35)
		side.add_child(l)

	var inv_title := Label.new()
	inv_title.text = "В рюкзаке (%d):" % hero.inventory.size()
	inv_title.add_theme_font_size_override("font_size", 16)
	side.add_child(inv_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 150)
	side.add_child(scroll)
	var inv_list := VBoxContainer.new()
	inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_list.add_theme_constant_override("separation", 2)
	scroll.add_child(inv_list)
	if hero.inventory.is_empty():
		var empty := Label.new()
		empty.text = "— пусто —"
		empty.add_theme_font_size_override("font_size", 13)
		empty.modulate = Color(1, 1, 1, 0.35)
		inv_list.add_child(empty)
	else:
		for it in hero.inventory:
			var l := Label.new()
			l.add_theme_font_size_override("font_size", 13)
			l.text = "%s (%s) — %s" % [it.name, it.slot_name(), it.bonuses_text()]
			l.modulate = it.rarity_color()
			inv_list.add_child(l)


## Выбор предмета в финальном сундуке.
func _on_chest_choice(item: Item) -> void:
	_grant_item(item, FINAL_CHEST_POS)
	_current_choices = []
	if _chest_ui != null:
		_chest_ui.queue_free()
		_chest_ui = null
	for c in _chests.duplicate():
		if c.is_final:
			_chests.erase(c)
			c.queue_free()
	_update_hud()
	_check_loot_done()


## Волна завершается, только когда открыты все сундуки и награды получены.
func _check_loot_done() -> void:
	if _state == "loot" and _chests.is_empty():
		_finish_wave_or_boss()


# ---------- Финалы ----------

func _finish_wave_or_boss() -> void:
	if _state == "done":
		return
	_state = "done"
	if _boss_dead:
		_show_center("Босс повержен!")
		_emit_deferred(boss_defeated)
	else:
		_show_center("Волна пройдена!")
		_emit_deferred(wave_cleared)


func _show_center(text: String) -> void:
	_center_label.text = text
	_center_label.visible = true


## Сигнал с небольшой паузой, чтобы игрок увидел финальную надпись.
func _emit_deferred(sig: Signal) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(1.6).timeout
	sig.emit()


## Всплывающий текст (урон, опыт, события).
func _spawn_popup(text: String, pos: Vector2, color: Color, size: int) -> void:
	if not is_inside_tree():
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", size)
	add_child(lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", pos.y - 60.0, 1.2)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.2)
	tween.chain().tween_callback(lbl.queue_free)


# ---------- Внутренние классы ----------

class Chest:
	extends Area2D
	## Сундук на поле боя: рисуется кодом, открывается кликом.
	## Финальный сундук волны крупнее и с золотой окантовкой.

	signal clicked(chest)

	var is_final := false
	var base_size := 44.0


	func _ready() -> void:
		var s := base_size * (1.4 if is_final else 1.0)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(s, s)
		shape.shape = rect
		shape.position = Vector2(0, -s * 0.5)
		add_child(shape)
		input_event.connect(_on_input_event)


	func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(self)


	func _draw() -> void:
		var s := base_size * (1.4 if is_final else 1.0)
		var wood := Color(0.55, 0.38, 0.2)
		var wood_dark := Color(0.42, 0.28, 0.14)
		var trim := Color(0.95, 0.8, 0.3) if is_final else Color(0.7, 0.7, 0.72)
		if is_final:
			draw_circle(Vector2(0, -s * 0.5), s * 0.9, Color(1.0, 0.9, 0.4, 0.18))
		# Тень на земле
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, s * 0.55, Color(0, 0, 0, 0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Корпус, крышка и замок
		var body := Rect2(-s / 2, -s * 0.6, s, s * 0.6)
		var lid := Rect2(-s / 2, -s, s, s * 0.45)
		draw_rect(body, wood)
		draw_rect(lid, wood_dark)
		draw_rect(body, trim, false, 2.0)
		draw_rect(lid, trim, false, 2.0)
		draw_rect(Rect2(-s * 0.08, -s * 0.68, s * 0.16, s * 0.22), trim)


class Backdrop:
	extends Node2D
	## Фон экрана боя слоями: небо и солнце, дальние холмы и деревья,
	## полоса изометрического поля боя посередине, трава переднего плана внизу.
	## Рисуется под реальный размер окна. Позже фон будет меняться от уровня.

	const TILE_W := 96.0
	const TILE_H := 48.0
	const HORIZON := 0.44      # линия горизонта (доля высоты окна)
	const FIELD_TOP := 0.56    # верх поля боя
	const FIELD_BOTTOM := 0.9  # низ поля боя (дальше — передний план)


	func _ready() -> void:
		# Перерисовка при изменении размера окна (stretch expand меняет ширину)
		get_viewport().size_changed.connect(queue_redraw)


	func _draw() -> void:
		var size := get_viewport_rect().size
		var horizon_y: float = size.y * HORIZON
		var field_top: float = size.y * FIELD_TOP
		var field_bottom: float = size.y * FIELD_BOTTOM

		# Небо (две полосы, светлее к горизонту)
		draw_rect(Rect2(0, 0, size.x, horizon_y), Color(0.66, 0.82, 0.95))
		draw_rect(Rect2(0, horizon_y * 0.55, size.x, horizon_y * 0.45 + 2), Color(0.75, 0.88, 0.96))
		# Солнце
		var sun := Vector2(size.x * 0.84, size.y * 0.16)
		draw_circle(sun, size.y * 0.085, Color(1.0, 0.95, 0.6, 0.25))
		draw_circle(sun, size.y * 0.06, Color(1.0, 0.95, 0.62))

		# Дальние холмы: два мягких гребня через весь экран
		_draw_ridge(size, horizon_y + size.y * 0.02, size.y * 0.1, Color(0.62, 0.78, 0.66), 3)
		_draw_ridge(size, horizon_y + size.y * 0.06, size.y * 0.06, Color(0.52, 0.7, 0.57), 4)

		# Деревья-кроны вдоль горизонта
		for fx in [0.1, 0.36, 0.64, 0.9]:
			_draw_canopy(Vector2(size.x * fx, horizon_y + size.y * 0.05), size.y * 0.045)

		# Трава между горизонтом и полем боя
		draw_rect(Rect2(0, horizon_y, size.x, field_top - horizon_y + TILE_H), Color(0.6, 0.78, 0.52))

		# Поле боя: изометрическая плитка сплошной полосой через весь экран
		var base := Color(0.57, 0.75, 0.5)
		draw_rect(Rect2(0, field_top, size.x, field_bottom - field_top), base)
		var alt := Color(0.62, 0.79, 0.54)
		var row := 0
		var y: float = field_top - TILE_H / 2
		while y < field_bottom + TILE_H:
			var x: float = -TILE_W + (TILE_W / 2 if row % 2 == 1 else 0.0)
			var col := 0
			while x < size.x + TILE_W:
				var c := alt if (row + col) % 2 == 0 else base
				draw_colored_polygon(PackedVector2Array([
					Vector2(x, y - TILE_H / 2),
					Vector2(x + TILE_W / 2, y),
					Vector2(x, y + TILE_H / 2),
					Vector2(x - TILE_W / 2, y),
				]), c)
				x += TILE_W
				col += 1
			y += TILE_H / 2
			row += 1

		# Передний план: более тёмная трава, закрывает нижний край плитки
		draw_rect(Rect2(0, field_bottom, size.x, size.y - field_bottom), Color(0.5, 0.69, 0.45))


	## Гребень холмов через весь экран: треугольная волна с заданным числом пиков.
	func _draw_ridge(size: Vector2, base_y: float, amp: float, color: Color, peaks: int) -> void:
		var pts := PackedVector2Array()
		pts.append(Vector2(0, base_y))
		for i in range(peaks * 2 + 1):
			var x: float = size.x * i / (peaks * 2)
			var y: float = base_y - (amp if i % 2 == 1 else 0.0)
			pts.append(Vector2(x, y))
		pts.append(Vector2(size.x, base_y + amp * 2))
		pts.append(Vector2(0, base_y + amp * 2))
		draw_colored_polygon(pts, color)


	## Крона дерева: три круга.
	func _draw_canopy(center: Vector2, r: float) -> void:
		var c := Color(0.42, 0.64, 0.42)
		draw_circle(center + Vector2(-r, 0), r, c)
		draw_circle(center + Vector2(r, 0), r, c)
		draw_circle(center + Vector2(0, -r * 0.8), r * 1.1, c.lightened(0.08))
