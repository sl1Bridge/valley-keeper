class_name Actor
extends Node2D

## Боец на экране боя: рисуется кодом (круг/квадрат/треугольник + полоса HP),
## сам держит таймер атаки по своей скорости атаки.

signal died(actor)
signal damaged(actor, amount)
signal attacked(attacker, target)
signal evaded(actor)
signal poisoned  # состав стаков отравления изменился (добавлен или истёк)
signal cast_ready(actor)  # умение заряжено (таймер дошёл до конца)

var display_name := ""
var team := "enemy"  # "hero" или "enemy"
var stats := {}      # hp, atk, spd (атак/с)
var max_hp := 1.0
var hp := 1.0
var regen := 0.0     # HP в секунду, работает прямо в бою
var def_pct := 0.0   # доля снижения входящего урона (0..1)
var evasion := 0.0   # шанс полностью избежать атаки (уворот/блок, 0..1)
var evasion_label := "Уворот!"  # текст всплывающей надписи при избегании
# Статусные эффекты: оставшееся время каждого стака (самый старый — первый)
var poison_times: Array = []
var bleed_times: Array = []
var stun_left := 0.0   # оставшееся время оглушения (0 — нет); не стакается
var taunt := false     # провокация: герой атакует этого врага в первую очередь
var cast_interval := 0.0  # период умения в секундах (0 — умения нет)
var cast_timer := 0.0     # накопленное время до готовности умения
var dmg_mult_next := 1.0  # множитель урона следующей атаки (способность Вора «Смертельный удар»)
var body_color := Color.WHITE
var shape := "rect"  # "rect" | "circle" | "triangle"
var radius := 30.0
var move_speed := 80.0
var alive := true
var engaged := false
var target: Actor = null

var _atk_timer := 0.0
var _atk_interval := 1.0  # интервал до следующего удара (у врагов — с разбросом)
var _flash := 0.0
var _bleed_accum := 0.0  # дробный урон кровотечения, копится до целого
var _stun_max := 1.0     # длительность текущего оглушения (для прогресс-бара)
var _badges := {}        # "poison" | "bleed" | "stun" → StatusBadge


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
	# Первый удар — в базовом темпе; следующие враги пересчитывают с разбросом
	_atk_interval = 1.0 / maxf(0.1, float(stats.get("spd", 1.0)))
	# Значки статусных эффектов над головой (видны, только когда эффект активен)
	var kinds := ["poison", "bleed", "stun"]
	for i in kinds.size():
		var b := StatusBadge.new(kinds[i])
		b.position = Vector2(-64.0 + i * 44.0, -radius * 2.0 - 76.0)
		b.visible = false
		add_child(b)
		_badges[kinds[i]] = b


## Наложить стак отравления: у каждого стака свой таймер.
func add_poison() -> void:
	poison_times.append(Hero.POISON_DURATION)
	_update_badges()
	poisoned.emit()


## Наложить стак кровотечения: у каждого стака свой таймер.
func add_bleed() -> void:
	bleed_times.append(Hero.BLEED_DURATION)
	_update_badges()


## Оглушение: не стакается — повторное наложение обновляет таймер.
## Таймер атаки сбрасывается: после стана атака начнёт накапливаться заново.
func add_stun(duration: float) -> void:
	stun_left = duration
	_stun_max = duration
	_atk_timer = 0.0
	_update_badges()


## Снять все статусные эффекты (вызывается при завершении фазы боя).
func clear_effects() -> void:
	var had_poison := not poison_times.is_empty()
	poison_times.clear()
	bleed_times.clear()
	_bleed_accum = 0.0
	stun_left = 0.0
	_update_badges()
	if had_poison:
		poisoned.emit()  # характеристики надо пересчитать без штрафа


## Тикают таймеры стаков, истёкшие снимаются. Возвращает true, если что-то истекло.
func _tick_stacks(times: Array, delta: float) -> bool:
	var expired := false
	for i in range(times.size() - 1, -1, -1):
		times[i] -= delta
		if times[i] <= 0.0:
			times.remove_at(i)
			expired = true
	return expired


## Один шаг логики боя (вызывается из _process).
func step(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	var any_effects := false
	# Отравление: тикают таймеры стаков
	if not poison_times.is_empty():
		any_effects = true
		if _tick_stacks(poison_times, delta):
			poisoned.emit()
	# Кровотечение: урон в секунду за каждый стак, мимо уворота и защиты
	if not bleed_times.is_empty():
		any_effects = true
		_tick_stacks(bleed_times, delta)
		if alive and engaged and not bleed_times.is_empty():
			_bleed_accum += Hero.bleed_dps(bleed_times.size()) * delta
			var dot := floori(_bleed_accum)
			if dot >= 1:
				_bleed_accum -= dot
				_take_dot(dot)
	# Оглушение: таймер тикает, атаки заблокированы ниже
	if stun_left > 0.0:
		any_effects = true
		stun_left = maxf(0.0, stun_left - delta)
	if any_effects:
		_update_badges()
	# Регенерация здоровья (только пока идёт бой: прекращается, когда боец вышел из боя)
	if alive and engaged and regen > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen * delta)
		queue_redraw()
	# Умение: копится заряд, по заполнении — сигнал (обрабатывает экран боя)
	if alive and engaged and cast_interval > 0.0:
		cast_timer += delta
		queue_redraw()  # прогресс-бар умения
		if cast_timer >= cast_interval:
			cast_timer = 0.0
			cast_ready.emit(self)
	if not alive or not engaged or stun_left > 0.0 or target == null or not target.alive:
		return
	_atk_timer += delta
	if _atk_timer >= _atk_interval:
		_atk_timer -= _atk_interval
		_attack()
		_roll_next_attack()


## Следующий удар выбирает свою скорость: у врагов интервал каждый раз
## случайный в пределах разброса (одинаковые враги не бьют одновременно),
## герой бьёт в стабильном темпе по своей скорости атаки.
func _roll_next_attack() -> void:
	var base := 1.0 / maxf(0.1, float(stats.get("spd", 1.0)))
	if team == "enemy":
		_atk_interval = base * (1.0 + randf_range(-Enemies.ATK_JITTER, Enemies.ATK_JITTER))
	else:
		_atk_interval = base


## Обновить значки эффектов: счётчик стаков, прогресс самого старого, подсказка.
func _update_badges() -> void:
	if _badges.is_empty():
		return
	var poison_n := poison_times.size()
	_set_badge("poison", poison_n,
		float(poison_times[0]) / Hero.POISON_DURATION if poison_n > 0 else 0.0,
		"Отравление: базовые характеристики снижены на %.1f%%\nДействует эффектов: %d (каждый — %d с)" % [Hero.poison_pct(poison_n) * 100.0, poison_n, int(Hero.POISON_DURATION)])
	var bleed_n := bleed_times.size()
	_set_badge("bleed", bleed_n,
		float(bleed_times[0]) / Hero.BLEED_DURATION if bleed_n > 0 else 0.0,
		"Кровотечение: −%d HP/с\nДействует эффектов: %d (каждый — %d с)" % [roundi(Hero.bleed_dps(bleed_n)), bleed_n, int(Hero.BLEED_DURATION)])
	_set_badge("stun", 1 if stun_left > 0.0 else 0,
		stun_left / _stun_max if stun_left > 0.0 else 0.0,
		"Оглушение: герой не атакует\nОсталось: %.1f с" % stun_left)


func _set_badge(kind: String, stacks: int, frac: float, tip: String) -> void:
	var b: StatusBadge = _badges.get(kind)
	if b == null:
		return
	b.visible = stacks > 0
	if stacks <= 0:
		return
	b.stacks = stacks
	b.oldest_frac = clampf(frac, 0.0, 1.0)
	b.tooltip_text = tip
	b.queue_redraw()


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
	# Множитель следующей атаки (способность Вора) тратится этим ударом.
	var dmg := maxi(1, floori(float(stats.get("atk", 1)) * (1.0 - t.def_pct) * dmg_mult_next))
	dmg_mult_next = 1.0
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


## Урон от эффектов (кровотечение): идёт мимо уворота и защиты.
func _take_dot(dmg: int) -> void:
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
		_draw_cast_bar()
		_draw_taunt_flag()


func _draw_hp_bar() -> void:
	var w := radius * 2.0
	var h := 7.0
	var y := -radius * 2.0 - 16.0
	draw_rect(Rect2(-radius, y, w, h), Color(0.12, 0.12, 0.14))
	var fill := Color(0.35, 0.85, 0.4) if team == "hero" else Color(0.9, 0.32, 0.32)
	draw_rect(Rect2(-radius, y, w * hp_fraction(), h), fill)


## Прогресс-бар умения над полосой HP: заполняется к готовности, потом сгорает.
func _draw_cast_bar() -> void:
	if cast_interval <= 0.0:
		return
	var w := radius * 2.0
	var y := -radius * 2.0 - 29.0
	draw_rect(Rect2(-radius, y, w, 5.0), Color(0.12, 0.12, 0.14))
	var frac := clampf(cast_timer / cast_interval, 0.0, 1.0)
	draw_rect(Rect2(-radius, y, w * frac, 5.0), Color(0.72, 0.5, 0.95))


## Иконка провокации: красный флажок справа над головой —
## герой атакует этого врага в первую очередь.
func _draw_taunt_flag() -> void:
	if not taunt:
		return
	var fx := radius * 0.8
	var fy := -radius * 2.0 - 8.0
	var red := Color(0.9, 0.22, 0.22)
	draw_line(Vector2(fx, fy), Vector2(fx, fy - 22.0), red, 2.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(fx, fy - 22.0),
		Vector2(fx + 14.0, fy - 17.0),
		Vector2(fx, fy - 12.0),
	]), red)


## Значок статусного эффекта над головой бойца: иконка по виду эффекта,
## счётчик стаков в правом нижнем углу и прогресс-бар самого старого стака
## (у оглушения — оставшееся время). Подсказка — штатный тултип Control.
class StatusBadge:
	extends Control

	var kind := "poison"  # "poison" | "bleed" | "stun"
	var stacks := 0
	var oldest_frac := 1.0  # доля оставшегося времени самого раннего стака


	func _init(p_kind: String = "poison") -> void:
		kind = p_kind
		custom_minimum_size = Vector2(40, 46)
		size = custom_minimum_size
		mouse_default_cursor_shape = Control.CURSOR_HELP


	func _effect_color() -> Color:
		match kind:
			"bleed":
				return Color(0.85, 0.25, 0.25)
			"stun":
				return Color(1.0, 0.85, 0.25)
			_:
				return Color(0.45, 0.85, 0.35)


	func _draw() -> void:
		if stacks <= 0:
			return
		var col := _effect_color()
		var c := Vector2(size.x * 0.42, size.y * 0.38)
		var r := size.x * 0.26
		if kind == "stun":
			# Иконка оглушения: звезда
			var pts := PackedVector2Array()
			for i in 10:
				var ang := -PI / 2.0 + i * PI / 5.0
				var rr: float = r * 1.3 if i % 2 == 0 else r * 0.55
				pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(pts, col)
		else:
			# Иконки отравления и кровотечения: капля (круг + заострённый верх)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 1.7),
				c + Vector2(r * 0.75, -r * 0.35),
				c + Vector2(-r * 0.75, -r * 0.35),
			]), col)
			draw_circle(c, r, col)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.25), r * 0.25, col.lightened(0.35))
		# Счётчик стаков в правом нижнем углу иконки
		if stacks > 1:
			var font := ThemeDB.fallback_font
			var p := Vector2(size.x - 16.0, size.y - 14.0)
			draw_string(font, p + Vector2(1, 1), str(stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0))
			draw_string(font, p, str(stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		# Прогресс-бар под иконкой: оставшееся время самого раннего стака
		var bar := Rect2(Vector2(2, size.y - 8.0), Vector2(size.x - 4, 5))
		draw_rect(bar, Color(0.12, 0.12, 0.14))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * oldest_frac, bar.size.y)), col)
