class_name Actor
extends Node2D

## Боец на экране боя: рисуется кодом (круг/квадрат/треугольник + полоса HP),
## сам держит таймер атаки по своей скорости атаки.

signal died(actor)
signal damaged(actor, amount)
signal attacked(attacker, target)
signal evaded(actor)
signal poisoned  # состав стаков отравления изменился (добавлен или истёк)

var display_name := ""
var team := "enemy"  # "hero" или "enemy"
var stats := {}      # hp, atk, spd (атак/с)
var max_hp := 1.0
var hp := 1.0
var regen := 0.0     # HP в секунду, работает прямо в бою
var def_pct := 0.0   # доля снижения входящего урона (0..1)
var evasion := 0.0   # шанс полностью избежать атаки (уворот/блок, 0..1)
var evasion_label := "Уворот!"  # текст всплывающей надписи при избегании
# Отравление: оставшееся время каждого стака (самый старый — первый)
var poison_times: Array = []
var body_color := Color.WHITE
var shape := "rect"  # "rect" | "circle" | "triangle"
var radius := 30.0
var move_speed := 80.0
var alive := true
var engaged := false
var target: Actor = null

var _atk_timer := 0.0
var _flash := 0.0
var _badge: PoisonBadge = null


func setup(p_name: String, p_stats: Dictionary, p_color: Color, p_shape: String, p_radius: float, p_team: String) -> void:
	display_name = p_name
	stats = p_stats
	body_color = p_color
	shape = p_shape
	radius = p_radius
	team = p_team
	max_hp = float(maxi(1, int(stats.get("hp", 1))))
	hp = max_hp
	move_speed = float(stats.get("move", 80.0))
	# Значок отравления над головой (виден, только когда есть стаки)
	_badge = PoisonBadge.new()
	_badge.position = Vector2(-20, -radius * 2.0 - 76.0)
	_badge.visible = false
	add_child(_badge)


## Наложить стак отравления: у каждого стака свой таймер.
func add_poison() -> void:
	poison_times.append(Hero.POISON_DURATION)
	_update_poison_badge()
	poisoned.emit()


## Один шаг логики боя (вызывается из _process).
func step(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	# Отравление: тикают таймеры стаков, истёкшие снимаются
	if not poison_times.is_empty():
		var expired := false
		for i in range(poison_times.size() - 1, -1, -1):
			poison_times[i] -= delta
			if poison_times[i] <= 0.0:
				poison_times.remove_at(i)
				expired = true
		_update_poison_badge()
		if expired:
			poisoned.emit()
	# Регенерация здоровья (только пока идёт бой: прекращается, когда боец вышел из боя)
	if alive and engaged and regen > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen * delta)
		queue_redraw()
	if not alive or not engaged or target == null or not target.alive:
		return
	_atk_timer += delta
	var interval := 1.0 / maxf(0.1, float(stats.get("spd", 1.0)))
	if _atk_timer >= interval:
		_atk_timer -= interval
		_attack()


## Обновить значок отравления: счётчик стаков, прогресс самого старого, подсказка.
func _update_poison_badge() -> void:
	if _badge == null:
		return
	var n := poison_times.size()
	_badge.visible = n > 0
	if n == 0:
		return
	_badge.stacks = n
	_badge.oldest_frac = clampf(float(poison_times[0]) / Hero.POISON_DURATION, 0.0, 1.0)
	_badge.tooltip_text = "Отравление: базовые характеристики снижены на %.1f%%\nДействует эффектов: %d (каждый — %d с)" % [Hero.poison_pct(n) * 100.0, n, int(Hero.POISON_DURATION)]
	_badge.queue_redraw()


func _process(delta: float) -> void:
	step(delta)


func _attack() -> void:
	if target == null or not target.alive:
		return
	# Захватываем цель локально: take_damage может её убить, тогда
	# _on_enemy_died обнуляет self.target ещё до отправки сигнала attacked.
	var t: Actor = target
	# Защита цели снижает урон на процент (def_pct), минимум 1.
	# Округление вниз: иначе мелкие атаки первых волн бьют больнее, чем раньше.
	var dmg := maxi(1, floori(float(stats.get("atk", 1)) * (1.0 - t.def_pct)))
	t.take_damage(dmg)
	attacked.emit(self, t)


func take_damage(dmg: int) -> void:
	if not alive:
		return
	# Уворот/блок: атака полностью избегнута
	if evasion > 0.0 and randf() < evasion:
		evaded.emit(self)
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
	# Тень на земле (position — точка, где боец стоит)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius * 0.9, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c := Color.WHITE if _flash > 0.0 else body_color
	if not alive:
		c = c.darkened(0.6)
	var off := Vector2(0, -radius)  # тело над точкой опоры
	match shape:
		"circle":
			draw_circle(off, radius, c)
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				off + Vector2(-radius, radius * 0.7),
				off + Vector2(radius, radius * 0.7),
				off + Vector2(0.0, -radius),
			]), c)
		_:
			draw_rect(Rect2(off - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), c)
	if alive:
		_draw_hp_bar()


func _draw_hp_bar() -> void:
	var w := radius * 2.0
	var h := 7.0
	var y := -radius * 2.0 - 16.0
	draw_rect(Rect2(-radius, y, w, h), Color(0.12, 0.12, 0.14))
	var fill := Color(0.35, 0.85, 0.4) if team == "hero" else Color(0.9, 0.32, 0.32)
	draw_rect(Rect2(-radius, y, w * hp_fraction(), h), fill)


## Значок статусного эффекта над головой бойца: иконка, счётчик стаков
## в правом нижнем углу и прогресс-бар самого старого стака.
## Подсказка — штатный тултип Control (текст задаёт Actor).
class PoisonBadge:
	extends Control

	var stacks := 0
	var oldest_frac := 1.0  # доля оставшегося времени самого раннего стака


	func _init() -> void:
		custom_minimum_size = Vector2(40, 46)
		size = custom_minimum_size
		mouse_default_cursor_shape = Control.CURSOR_HELP


	func _draw() -> void:
		if stacks <= 0:
			return
		var poison := Color(0.45, 0.85, 0.35)
		# Иконка: капля яда (круг + заострённый верх)
		var c := Vector2(size.x * 0.42, size.y * 0.38)
		var r := size.x * 0.26
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r * 1.7),
			c + Vector2(r * 0.75, -r * 0.35),
			c + Vector2(-r * 0.75, -r * 0.35),
		]), poison)
		draw_circle(c, r, poison)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.25), r * 0.25, poison.lightened(0.35))
		# Счётчик стаков в правом нижнем углу иконки
		if stacks > 1:
			var font := ThemeDB.fallback_font
			var p := Vector2(size.x - 16.0, size.y - 14.0)
			draw_string(font, p + Vector2(1, 1), str(stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0))
			draw_string(font, p, str(stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		# Прогресс-бар под иконкой: оставшееся время самого раннего стака
		var bar := Rect2(Vector2(2, size.y - 8.0), Vector2(size.x - 4, 5))
		draw_rect(bar, Color(0.12, 0.12, 0.14))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * oldest_frac, bar.size.y)), poison)
