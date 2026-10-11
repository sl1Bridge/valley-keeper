class_name Actor
extends Node2D

## Боец на экране боя: рисуется кодом (круг/квадрат/треугольник + полоса HP),
## сам держит таймер атаки по своей скорости атаки.

signal died(actor)
signal damaged(actor, amount)

var display_name := ""
var team := "enemy"  # "hero" или "enemy"
var stats := {}      # hp, atk, def, spd
var max_hp := 1
var hp := 1
var body_color := Color.WHITE
var shape := "rect"  # "rect" | "circle" | "triangle"
var radius := 30.0
var move_speed := 80.0
var alive := true
var engaged := false
var target: Actor = null

var _atk_timer := 0.0
var _flash := 0.0


func setup(p_name: String, p_stats: Dictionary, p_color: Color, p_shape: String, p_radius: float, p_team: String) -> void:
	display_name = p_name
	stats = p_stats
	body_color = p_color
	shape = p_shape
	radius = p_radius
	team = p_team
	max_hp = maxi(1, int(stats.get("hp", 1)))
	hp = max_hp
	move_speed = float(stats.get("move", 80.0))


## Шаг логики боя (вызывается из _process).
func step(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	if not alive or not engaged or target == null or not target.alive:
		return
	_atk_timer += delta
	var interval := 1.0 / maxf(0.1, float(stats.get("spd", 1.0)))
	if _atk_timer >= interval:
		_atk_timer -= interval
		_attack()


func _process(delta: float) -> void:
	step(delta)


func _attack() -> void:
	if target == null or not target.alive:
		return
	var dmg := maxi(1, int(stats.get("atk", 1)) - int(target.stats.get("def", 0)))
	target.take_damage(dmg)


func take_damage(dmg: int) -> void:
	if not alive:
		return
	hp -= dmg
	_flash = 0.12
	damaged.emit(self, dmg)
	queue_redraw()
	if hp <= 0:
		hp = 0
		alive = false
		died.emit(self)
		queue_redraw()


func hp_fraction() -> float:
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


func _draw() -> void:
	var c := Color.WHITE if _flash > 0.0 else body_color
	if not alive:
		c = c.darkened(0.6)
	match shape:
		"circle":
			draw_circle(Vector2.ZERO, radius, c)
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				Vector2(-radius, radius * 0.7),
				Vector2(radius, radius * 0.7),
				Vector2(0.0, -radius),
			]), c)
		_:
			draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), c)
	if alive:
		_draw_hp_bar()


func _draw_hp_bar() -> void:
	var w := radius * 2.0
	var h := 7.0
	var y := -radius - 16.0
	draw_rect(Rect2(-radius, y, w, h), Color(0.12, 0.12, 0.14))
	var fill := Color(0.35, 0.85, 0.4) if team == "hero" else Color(0.9, 0.32, 0.32)
	draw_rect(Rect2(-radius, y, w * hp_fraction(), h), fill)
