class_name BattleScreen
extends Control

## Экран боя: герой сам идёт слева направо, враги бросаются навстречу,
## бой идёт автоматически, сундуки открываются по пути, лут падает в рюкзак.

signal wave_cleared
signal hero_died
signal boss_defeated

const GROUND_Y := 560.0
const HERO_START_X := 120.0
const FIRST_ENEMY_X := 720.0
const ENEMY_GAP := 300.0
const AGGRO_RANGE := 320.0
const HERO_WALK_SPEED := 140.0
const DROP_CHANCE := 0.25

## Входные данные (заполняет Main до добавления на сцену)
var hero: Hero
var wave := 1
var wins := 0

var _rng := RandomNumberGenerator.new()
var _state := "walk"  # "walk" | "done"
var _kills := 0
var _enemy_total := 0

var _world: Node2D
var _hero_actor: Actor
var _enemies := []
var _chests := []
var _opening_chest = null
var _open_timer := 0.0

var _wave_label: Label
var _kills_label: Label
var _center_label: Label


## Сундук: рисованный золотой ящик.
class Chest:
	extends Node2D
	var opened := false

	func _draw() -> void:
		var c := Color(0.85, 0.65, 0.2) if not opened else Color(0.45, 0.38, 0.25)
		draw_rect(Rect2(-20, -30, 40, 30), c)
		draw_rect(Rect2(-20, -30, 40, 10), c.lightened(0.2))
		draw_rect(Rect2(-4, -22, 8, 10), Color(0.3, 0.25, 0.15))


func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_hud()
	_world = Node2D.new()
	add_child(_world)
	_spawn_hero()
	_spawn_enemies()
	_spawn_chests()
	_update_hud()


func _build_background() -> void:
	var sky := ColorRect.new()
	sky.color = Color(0.72, 0.84, 0.94)
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	var ground := ColorRect.new()
	ground.color = Color(0.62, 0.78, 0.55)
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.anchor_top = 0.72
	add_child(ground)


func _build_hud() -> void:
	var hud := HBoxContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = 16
	hud.offset_top = 10
	hud.offset_right = -16
	hud.add_theme_constant_override("separation", 32)
	add_child(hud)

	_wave_label = Label.new()
	_wave_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_wave_label)

	_kills_label = Label.new()
	_kills_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_kills_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)

	var hint := Label.new()
	hint.text = "Бой идёт автоматически — наблюдай и готовь следующую сборку"
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.8)
	hud.add_child(hint)

	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.add_theme_font_size_override("font_size", 42)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.visible = false
	add_child(_center_label)


func _spawn_hero() -> void:
	_hero_actor = Actor.new()
	var stats := hero.get_stats()
	stats["move"] = HERO_WALK_SPEED
	_hero_actor.setup("Герой", stats, Color(0.25, 0.45, 0.9), "rect", 30.0, "hero")
	_hero_actor.position = Vector2(HERO_START_X, GROUND_Y)
	_hero_actor.died.connect(_on_hero_died)
	_hero_actor.damaged.connect(_on_actor_damaged)
	_world.add_child(_hero_actor)


func _spawn_enemies() -> void:
	var comp := Enemies.wave_composition(wave)
	_enemy_total = comp.size()
	for i in comp.size():
		var type: String = comp[i]
		var stats := Enemies.scaled(type, wave, wins)
		var def: Dictionary = Enemies.TYPES[type]
		var e := Actor.new()
		e.setup(stats["name"], stats, def["color"], def["shape"], def["size"], "enemy")
		e.position = Vector2(FIRST_ENEMY_X + i * ENEMY_GAP, GROUND_Y)
		e.died.connect(_on_enemy_died)
		e.damaged.connect(_on_actor_damaged)
		_world.add_child(e)
		_enemies.append(e)


func _spawn_chests() -> void:
	var count := Enemies.chest_count(wave)
	var last_x: float = FIRST_ENEMY_X + maxi(0, _enemy_total - 1) * ENEMY_GAP
	for i in count:
		var chest := Chest.new()
		var frac := float(i + 1) / float(count + 1)
		chest.position = Vector2(lerpf(560.0, last_x + 150.0, frac), GROUND_Y + 15)
		_world.add_child(chest)
		_chests.append(chest)


func _update_hud() -> void:
	if wave >= Enemies.TOTAL_WAVES:
		_wave_label.text = "ФИНАЛЬНАЯ ВОЛНА — БОСС"
	else:
		_wave_label.text = "Волна %d / %d" % [wave, Enemies.TOTAL_WAVES]
	_kills_label.text = "Побеждено: %d / %d" % [_kills, _enemy_total]


func _process(delta: float) -> void:
	step(delta)


## Один шаг логики боя. Вынесен отдельно, чтобы можно было прогонять в тестах.
func step(delta: float) -> void:
	if _state == "done":
		return

	# Таймер открытия сундука
	if _opening_chest != null:
		_open_timer -= delta
		if _open_timer <= 0.0:
			_finish_open_chest()

	# Враги: подходят и вступают в бой
	for e in _enemies:
		if not e.alive or e.engaged or not _hero_actor.alive:
			continue
		var dist: float = e.position.x - _hero_actor.position.x
		if dist < AGGRO_RANGE:
			e.position.x -= e.move_speed * delta
		if dist <= _hero_actor.radius + e.radius + 6.0:
			_engage(e)

	# Герой идёт вперёд, если ни с кем не дерётся и не открывает сундук
	if _hero_actor.alive and not _hero_actor.engaged and _opening_chest == null:
		_hero_actor.position.x += HERO_WALK_SPEED * delta
		_check_chests()

	# Все враги повержены — волна пройдена
	if _kills >= _enemy_total:
		_finish_wave()


func _engage(e: Actor) -> void:
	e.engaged = true
	e.target = _hero_actor
	if _hero_actor.target == null or not _hero_actor.target.alive:
		_hero_actor.target = e
		_hero_actor.engaged = true


func _check_chests() -> void:
	for chest in _chests:
		if not chest.opened and absf(_hero_actor.position.x - chest.position.x) < 36.0:
			_opening_chest = chest
			_open_timer = 0.7
			return


func _finish_open_chest() -> void:
	var chest = _opening_chest
	_opening_chest = null
	chest.opened = true
	chest.queue_redraw()
	var item := Item.generate(_rng, -1, true)
	hero.inventory.append(item)
	_spawn_popup("Сундук: %s (%s)!" % [item.name, item.rarity_name()], chest.position + Vector2(-80, -70), item.rarity_color(), 20)


func _on_enemy_died(e: Actor) -> void:
	_kills += 1
	_update_hud()

	# Опыт и уровни
	var levels := hero.add_xp(int(e.stats.get("xp", 1)))
	_spawn_popup("+%d опыта" % int(e.stats.get("xp", 1)), e.position + Vector2(-30, -60), Color(0.95, 0.9, 0.4), 18)
	if levels > 0:
		# Новый уровень: характеристики пересчитываются, герой полностью исцеляется
		var stats := hero.get_stats()
		stats["move"] = HERO_WALK_SPEED
		_hero_actor.stats = stats
		_hero_actor.max_hp = int(stats["hp"])
		_hero_actor.hp = _hero_actor.max_hp
		_hero_actor.queue_redraw()
		_spawn_popup("Уровень %d! +%d очка характеристик" % [hero.level, Hero.POINTS_PER_LEVEL], _hero_actor.position + Vector2(-140, -110), Color(0.5, 1.0, 0.6), 24)

	# Дроп предмета
	if _rng.randf() < DROP_CHANCE:
		var item := Item.generate(_rng)
		hero.inventory.append(item)
		_spawn_popup("Дроп: %s (%s)" % [item.name, item.rarity_name()], e.position + Vector2(-60, -90), item.rarity_color(), 18)

	# Перенацеливание героя на следующего врага в ближнем бою
	if _hero_actor.target == e:
		_hero_actor.target = null
		_hero_actor.engaged = false
		for other in _enemies:
			if other.alive and other.engaged:
				_hero_actor.target = other
				_hero_actor.engaged = true
				break

	# Босс повержен — отдельный финал
	if e.stats.get("type", "") == "boss":
		_finish_boss()


func _on_hero_died(_a: Actor) -> void:
	if _state == "done":
		return
	_state = "done"
	_show_center("Герой пал…")
	_emit_deferred(hero_died)


func _on_actor_damaged(a: Actor, amount: int) -> void:
	var col := Color(1, 0.45, 0.4) if a.team == "hero" else Color(1, 1, 1)
	_spawn_popup("-%d" % amount, a.position + Vector2(randf_range(-14, 14), -a.radius - 26), col, 16)


func _finish_wave() -> void:
	if _state == "done":
		return
	_state = "done"
	_show_center("Волна пройдена!")
	_emit_deferred(wave_cleared)


func _finish_boss() -> void:
	if _state == "done":
		return
	_state = "done"
	_show_center("Босс повержен!")
	_emit_deferred(boss_defeated)


func _show_center(text: String) -> void:
	_center_label.text = text
	_center_label.visible = true


## Сигнал с небольшой паузой, чтобы игрок увидел финальную надпись.
func _emit_deferred(sig: Signal) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(1.6).timeout
	sig.emit()


## Всплывающий текст (лут, урон, опыт).
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
