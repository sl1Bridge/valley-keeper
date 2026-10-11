class_name BattleScreen
extends Control

## Экран боя. Герой стоит слева, враги — группой справа, никто не двигается.
## Все атакуют на дистанции. Герой выбирает случайную цель и бьёт её до смерти,
## затем выбирает следующую. Когда все враги повержены, открываются сундуки:
## 1 гарантированный + шанс дополнительного с каждого врага.
## Каждый сундук предлагает 3 разных предмета на выбор.

signal wave_cleared
signal hero_died
signal boss_defeated

const HERO_POS := Vector2(220, 500)
const ENEMY_ORIGIN := Vector2(850, 400)  # левый верхний враг группы
const ENEMY_COL_GAP := 135.0
const ENEMY_ROW_GAP := 100.0
const ENEMIES_PER_COL := 4
const BOSS_POS := Vector2(1010, 470)

## Входные данные (заполняет Main до добавления на сцену)
var hero: Hero
var wave := 1
var wins := 0

var _rng := RandomNumberGenerator.new()
var _state := "fight"  # "fight" | "loot" | "done"
var _kills := 0
var _enemy_total := 0
var _boss_dead := false

var _world: Node2D
var _hero_actor: Actor
var _enemies := []

# Сундуки
var _pending_chests := 0
var _chest_total := 0
var _chest_index := 0
var _current_choices := []
var _chest_ui: Control = null

var _wave_label: Label
var _kills_label: Label
var _chests_label: Label
var _center_label: Label


func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_hud()
	_world = Node2D.new()
	add_child(_world)
	_spawn_hero()
	_spawn_enemies()
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

	_chests_label = Label.new()
	_chests_label.add_theme_font_size_override("font_size", 22)
	_chests_label.modulate = Color(0.95, 0.8, 0.3)
	hud.add_child(_chests_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)

	var hint := Label.new()
	hint.text = "Бой идёт автоматически"
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
	_hero_actor.setup("Герой", stats, Color(0.25, 0.45, 0.9), "rect", 30.0, "hero")
	# Герой входит в бой с тем здоровьем, что осталось после прошлой волны + передышка
	_hero_actor.hp = clampf(hero.start_hp(), 1.0, _hero_actor.max_hp)
	_hero_actor.regen = float(stats.get("regen", 0.0))
	_hero_actor.position = HERO_POS
	_hero_actor.engaged = true
	_hero_actor.died.connect(_on_hero_died)
	_hero_actor.damaged.connect(_on_actor_damaged)
	_hero_actor.attacked.connect(_on_actor_attacked)
	_world.add_child(_hero_actor)


## Остаток здоровья героя (Main забирает после боя).
func hero_hp() -> float:
	if is_instance_valid(_hero_actor):
		return _hero_actor.hp
	return 0.0


func _spawn_enemies() -> void:
	var comp := Enemies.wave_composition(wave)
	_enemy_total = comp.size()
	for i in comp.size():
		var type: String = comp[i]
		var stats := Enemies.scaled(type, wave, wins)
		var def: Dictionary = Enemies.TYPES[type]
		var e := Actor.new()
		e.setup(stats["name"], stats, def["color"], def["shape"], def["size"], "enemy")
		if type == "boss":
			e.position = BOSS_POS
		else:
			var col := i / ENEMIES_PER_COL
			var row := i % ENEMIES_PER_COL
			e.position = ENEMY_ORIGIN + Vector2(col * ENEMY_COL_GAP, row * ENEMY_ROW_GAP)
		e.engaged = true
		e.target = _hero_actor
		e.died.connect(_on_enemy_died)
		e.damaged.connect(_on_actor_damaged)
		e.attacked.connect(_on_actor_attacked)
		_world.add_child(e)
		_enemies.append(e)
	_pick_hero_target()


## Герой выбирает случайную живую цель.
func _pick_hero_target() -> void:
	var alive := []
	for e in _enemies:
		if e.alive:
			alive.append(e)
	if alive.is_empty():
		_hero_actor.target = null
		_hero_actor.engaged = false
	else:
		_hero_actor.target = alive[_rng.randi_range(0, alive.size() - 1)]
		_hero_actor.engaged = true


func _update_hud() -> void:
	if wave >= Enemies.TOTAL_WAVES:
		_wave_label.text = "ФИНАЛЬНАЯ ВОЛНА — БОСС"
	else:
		_wave_label.text = "Волна %d / %d" % [wave, Enemies.TOTAL_WAVES]
	_kills_label.text = "Побеждено: %d / %d" % [_kills, _enemy_total]
	_chests_label.text = "Сундуки: %d" % _pending_chests


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

	# Опыт и уровни
	var xp: int = int(e.stats.get("xp", 1))
	var levels := hero.add_xp(xp)
	_spawn_popup("+%d опыта" % xp, e.position + Vector2(-30, -60), Color(0.95, 0.9, 0.4), 18)
	if levels > 0:
		# Новый уровень: характеристики пересчитываются, герой полностью исцеляется
		_hero_actor.stats = hero.get_stats()
		_hero_actor.max_hp = int(_hero_actor.stats["hp"])
		_hero_actor.hp = _hero_actor.max_hp
		_hero_actor.queue_redraw()
		_spawn_popup("Уровень %d! +%d очка характеристик" % [hero.level, Hero.POINTS_PER_LEVEL], _hero_actor.position + Vector2(-140, -110), Color(0.5, 1.0, 0.6), 24)

	# Шанс дополнительного сундука
	if _rng.randf() < Enemies.CHEST_DROP_CHANCE:
		_pending_chests += 1
		_spawn_popup("Выпал сундук!", e.position + Vector2(-30, -95), Color(0.95, 0.8, 0.3), 20)

	# Герой переключается на следующую случайную цель
	if _hero_actor.target == e:
		_pick_hero_target()

	if e.stats.get("type", "") == "boss":
		_boss_dead = true

	_update_hud()


func _on_hero_died(_a: Actor) -> void:
	if _state == "done":
		return
	_state = "done"
	for e in _enemies:
		e.engaged = false
	_show_center("Герой пал…")
	_emit_deferred(hero_died)


func _on_actor_damaged(a: Actor, amount: int) -> void:
	var col := Color(1, 0.45, 0.4) if a.team == "hero" else Color(1, 1, 1)
	_spawn_popup("-%d" % amount, a.position + Vector2(randf_range(-14, 14), -a.radius - 26), col, 16)


## «Снаряд»: точка летит от атакующего к цели.
func _on_actor_attacked(src: Actor, dst: Actor) -> void:
	if not is_inside_tree():
		return
	var dot := ColorRect.new()
	dot.size = Vector2(10, 10)
	dot.color = Color(1.0, 0.85, 0.3) if src.team == "hero" else Color(0.9, 0.35, 0.3)
	dot.position = src.position - Vector2(5, 5)
	_world.add_child(dot)
	var tween := create_tween()
	tween.tween_property(dot, "position", dst.position - Vector2(5, 5), 0.18)
	tween.tween_callback(dot.queue_free)


# ---------- Сундуки ----------

func _start_loot_phase() -> void:
	if _state != "fight":
		return
	_state = "loot"
	_hero_actor.engaged = false
	_pending_chests += Enemies.BASE_CHESTS
	_chest_total = _pending_chests
	_chest_index = 0
	_update_hud()
	_open_next_chest()


func _open_next_chest() -> void:
	if _pending_chests <= 0:
		_finish_wave_or_boss()
		return
	_chest_index += 1
	# 3 предмета на выбор, без повторов внутри сундука
	_current_choices = []
	var taken := []
	for i in Enemies.CHEST_CHOICES:
		var item := Item.generate(_rng, -1, true, taken)
		taken.append(item.name)
		_current_choices.append(item)
	_show_chest_ui()


func _show_chest_ui() -> void:
	if _chest_ui != null:
		_chest_ui.queue_free()
	_chest_ui = PanelContainer.new()
	_chest_ui.set_anchors_preset(Control.PRESET_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.18, 0.97)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.65, 0.2)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	_chest_ui.add_theme_stylebox_override("panel", style)
	add_child(_chest_ui)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_chest_ui.add_child(box)

	var title := Label.new()
	title.text = "Сундук %d из %d — выбери предмет" % [_chest_index, _chest_total]
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	for item in _current_choices:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(360, 56)
		btn.text = "%s (%s)\n%s · %s" % [item.name, item.rarity_name(), item.slot_name(), item.bonuses_text()]
		btn.add_theme_color_override("font_color", item.rarity_color())
		btn.pressed.connect(_on_chest_choice.bind(item))
		box.add_child(btn)


func _on_chest_choice(item: Item) -> void:
	hero.inventory.append(item)
	_current_choices = []
	if _chest_ui != null:
		_chest_ui.queue_free()
		_chest_ui = null
	_pending_chests -= 1
	_update_hud()
	_open_next_chest()


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
