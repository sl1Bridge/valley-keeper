extends SceneTree

## Автотесты проекта. Запуск (из папки проекта):
##   godot --headless --path . -s res://tests/TestRunner.gd
## Код выхода 0 — всё хорошо, 1 — есть провалы.

var _failures := 0
var _phase := 0
var _frames := 0


func _initialize() -> void:
	print("=== Логические тесты ===")
	_test_items()
	_test_hero()
	_test_rings_and_regen()
	_test_inventory()
	_test_enemies()
	_test_chests_heal_speed()
	_test_battle_sim()
	_test_boss_sims()
	print("=== Запуск Main.tscn ===")
	_phase = 1


func _process(_delta: float) -> bool:
	if _phase == 1:
		var packed: PackedScene = load("res://Main.tscn")
		_check(packed != null, "Main.tscn загружается")
		if packed == null:
			return _finish()
		var main := packed.instantiate()
		root.add_child(main)
		_phase = 2
		return false
	if _phase == 2:
		_frames += 1
		if _frames >= 30:
			var main := root.get_node("Main")
			_check(main._screen is GearScreen, "стартовый экран — лагерь")
			main._on_embark()
			_phase = 3
			_frames = 0
		return false
	if _phase == 3:
		_frames += 1
		if _frames >= 30:
			var main := root.get_node("Main")
			_check(main._screen is BattleScreen, "Main переключился на экран боя")
			return _finish()
		return false
	return false


func _finish() -> bool:
	if _failures == 0:
		print("=== ВСЕ ТЕСТЫ ПРОЙДЕНЫ ===")
		quit(0)
	else:
		printerr("=== ПРОВАЛЕНО ТЕСТОВ: %d ===" % _failures)
		quit(1)
	return true


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK: " + label)
	else:
		_failures += 1
		printerr("  FAIL: " + label)


func _test_items() -> void:
	print("-- Генерация предметов --")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ok := true
	for i in 40:
		var it := Item.generate(rng)
		if not Item.SLOT_NAMES.has(it.slot) or it.rarity < 0 or it.rarity >= Item.RARITY_NAMES.size() or it.bonuses.is_empty():
			ok = false
		if it.bonuses_text().is_empty():
			ok = false
	_check(ok, "40 предметов: слот, редкость и бонусы валидны")

	var chest_ok := true
	for i in 20:
		var it := Item.generate(rng, -1, 5)
		if it.rarity < 0 or it.rarity >= Item.RARITY_NAMES.size():
			chest_ok = false
	_check(chest_ok, "генерация с броском редкости по волне работает")

	var artifact := Item.generate(rng, 5)
	_check(artifact.rarity == 5 and artifact.rarity_name() == "Артефакт", "принудительная редкость «Артефакт»")
	_check(Item.RARITY_NAMES.size() == 6 and Item.RARITY_MULT.size() == 6, "6 редкостей с множителями")

	# Чем выше волна, тем выше средняя редкость дропа
	var avg := func(wave: int) -> float:
		var r := RandomNumberGenerator.new()
		r.seed = 100 + wave
		var sum := 0.0
		for i in 300:
			sum += Item.roll_rarity(r, wave)
		return sum / 300.0
	_check(avg.call(15) > avg.call(1), "редкость дропа растёт с номером волны")
	var rich_avg := func(wave: int) -> float:
		var r := RandomNumberGenerator.new()
		r.seed = 200 + wave
		var sum := 0.0
		for i in 300:
			sum += Item.roll_rarity(r, wave, true)
		return sum / 300.0
	_check(rich_avg.call(1) > avg.call(1), "финальный сундук ценнее обычного на той же волне")


func _test_hero() -> void:
	print("-- Герой: характеристики, опыт, экипировка --")
	var h := Hero.new()
	var s := h.get_stats()
	_check(int(s["hp"]) == 30 and int(s["atk"]) == 5, "базовые характеристики")
	_check(not h.allocate("atk"), "нельзя вложить очко без очков")

	var levels := h.add_xp(10)
	_check(levels == 1 and h.level == 2 and h.stat_points == Hero.POINTS_PER_LEVEL, "переход на 2 уровень")
	_check(h.allocate("atk"), "вложение очка в атаку")
	_check(int(h.get_stats()["atk"]) == 7, "атака выросла до 7")

	var it := Item.new()
	it.name = "Тестовый меч"
	it.slot = "weapon"
	it.rarity = 0
	it.bonuses = {"atk": 3}
	h.inventory.append(it)
	h.equip(it)
	_check(h.equipment["weapon"] == it and h.inventory.is_empty(), "предмет надет из рюкзака")
	_check(int(h.get_stats()["atk"]) == 10, "бонус меча учитывается (7+3)")
	h.unequip("weapon")
	_check(h.equipment["weapon"] == null and h.inventory.size() == 1, "предмет снят обратно в рюкзак")


func _make_ring(p_name: String) -> Item:
	var r := Item.new()
	r.name = p_name
	r.slot = "ring"
	r.rarity = 0
	r.bonuses = {"hp": 5}
	return r


func _test_rings_and_regen() -> void:
	print("-- Кольца, регенерация, передышка --")
	var h := Hero.new()

	# Два кольца надеваются одновременно, третье вытесняет первое
	var r1 := _make_ring("Кольцо 1")
	var r2 := _make_ring("Кольцо 2")
	var r3 := _make_ring("Кольцо 3")
	h.inventory.append(r1)
	h.equip(r1)
	_check(h.equipment["ring1"] == r1, "первое кольцо — в слот I")
	h.inventory.append(r2)
	h.equip(r2)
	_check(h.equipment["ring2"] == r2, "второе кольцо — в слот II")
	h.inventory.append(r3)
	var replaced := h.equip(r3)
	_check(h.equipment["ring1"] == r3 and h.equipment["ring2"] == r2, "третье кольцо вытеснило первое")
	_check(replaced == r1 and h.inventory.has(r1), "вытесненное кольцо вернулось в рюкзак")

	# Регенерация: вложение очков и бонус предмета
	h.add_xp(10)
	h.allocate("regen")
	var regen_ring := Item.new()
	regen_ring.name = "Кольцо регенерации"
	regen_ring.slot = "ring"
	regen_ring.rarity = 0
	regen_ring.bonuses = {"regen": 0.5}
	h.inventory.append(regen_ring)
	h.equip(regen_ring)
	var expected := Hero.PER_POINT["regen"] + 0.5
	_check(absf(h.get_stats()["regen"] - expected) < 0.001, "регенерация = очко + кольцо (%.2f)" % expected)

	# Регенерация работает в бою
	var a := Actor.new()
	a.setup("тест", {"hp": 20, "atk": 1, "def": 0, "spd": 1.0}, Color.WHITE, "rect", 10.0, "hero")
	a.hp = 10.0
	a.regen = 2.0
	a.engaged = true
	a.step(1.0)
	_check(absf(a.hp - 12.0) < 0.01, "регенерация в бою: 10 + 2/с × 1с = 12")
	a.step(10.0)
	_check(a.hp == 20.0, "регенерация не превышает максимум")
	# Регенерация прекращается с завершением боя (боец вышел из боя)
	a.engaged = false
	a.hp = 10.0
	a.step(1.0)
	_check(a.hp == 10.0, "регенерация останавливается после завершения боя")
	a.free()

	# Передышка: фиксированное восстановление, не полное
	h.current_hp = 10.0
	h.apply_rest()
	_check(absf(h.current_hp - (10.0 + Hero.REST_HEAL)) < 0.01, "передышка: +%d HP" % int(Hero.REST_HEAL))
	h.current_hp = h.max_hp() - 5.0
	h.apply_rest()
	_check(h.current_hp == h.max_hp(), "передышка не превышает максимум")
	h.full_restore()
	_check(h.start_hp() == h.max_hp(), "после смерти герой полностью восстановлен")


func _test_inventory() -> void:
	print("-- Инвентарь: лимит 30, вытеснение, продажа --")
	var h := Hero.new()
	_check(Hero.INVENTORY_SIZE == 30, "вместимость рюкзака — 30 ячеек")

	var mk := func(rarity: int) -> Item:
		var it := Item.new()
		it.name = "Предмет р%d" % rarity
		it.slot = "weapon"
		it.rarity = rarity
		it.bonuses = {"atk": 1}
		return it

	for i in 28:
		h.add_item(mk.call(0))
	var rare: Item = mk.call(3)
	h.add_item(rare)
	h.add_item(mk.call(0))
	_check(h.inventory.size() == Hero.INVENTORY_SIZE, "рюкзак заполнен до 30")

	var extra: Item = mk.call(1)
	var lost := h.add_item(extra)
	_check(h.inventory.size() == Hero.INVENTORY_SIZE, "при переполнении рюкзак остаётся 30")
	_check(lost != null and lost.rarity == 0, "потерян случайный предмет самой низкой редкости")
	_check(h.inventory.has(extra) and h.inventory.has(rare), "новый и редкий предметы на месте")

	# Продажа за опыт: +12 опыта (мистический) — сразу новый уровень
	var xp_gained := h.sell_item(rare)
	_check(xp_gained == Hero.SELL_XP[3], "цена продажи по редкости (+%d опыта)" % Hero.SELL_XP[3])
	_check(not h.inventory.has(rare), "проданный предмет ушёл из рюкзака")
	_check(h.level == 2 and h.xp == 2, "опыт за продажу дал уровень (10 порог, остаток 2)")
	_check(h.stat_points == Hero.POINTS_PER_LEVEL, "очки характеристик за уровень начислены")
	_check(h.sell_item(rare) == 0, "нельзя продать предмет, которого нет в рюкзаке")


func _test_enemies() -> void:
	print("-- Враги и волны --")
	var comp1 := Enemies.wave_composition(1)
	_check(comp1.size() == 3 and comp1.all(func(t): return t == "slime"), "волна 1 — три слизня")
	_check(Enemies.wave_composition(Enemies.TOTAL_WAVES) == ["boss"], "волна %d — босс" % Enemies.TOTAL_WAVES)
	_check(Enemies.TOTAL_WAVES == 20, "в локации 20 волн")

	# Ни в одной волне не больше MAX_ENEMIES врагов
	var capped := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for w in range(1, Enemies.TOTAL_WAVES):
		if Enemies.wave_composition(w, rng).size() > Enemies.MAX_ENEMIES:
			capped = false
	_check(capped, "в волне не больше %d врагов" % Enemies.MAX_ENEMIES)
	var comp9 := Enemies.wave_composition(9, rng)
	_check(comp9.size() == Enemies.MAX_ENEMIES, "волна 9 — ровно %d врагов" % Enemies.MAX_ENEMIES)

	# Сильные враги встречаются чаще на поздних волнах
	var w1: Dictionary = Enemies.type_weights(1)
	var w9: Dictionary = Enemies.type_weights(9)
	_check(w1["wolf"] == 0.0 and w1["golem"] == 0.0, "на 1 волне только слизни")
	_check(w9["golem"] > w9["slime"] and w9["wolf"] > w1["wolf"], "сильные враги чаще к 9 волне")

	var base: Dictionary = Enemies.TYPES["slime"]
	var scaled := Enemies.scaled("slime", 5, 0)
	_check(int(scaled["hp"]) > int(base["hp"]), "враги усиливаются к 5 волне")
	var ng := Enemies.scaled("slime", 1, 2)
	_check(int(ng["hp"]) > int(base["hp"]), "новый заход сложнее")

	_check(Enemies.BASE_CHESTS == 1, "1 гарантированный сундук за волну")
	_check(Enemies.CHEST_DROP_CHANCE > 0.0 and Enemies.CHEST_DROP_CHANCE < 0.5, "шанс доп. сундука разумный")


func _test_chests_heal_speed() -> void:
	print("-- Сундуки, лечение при уровне, скорость боя --")
	var h := Hero.new()
	var b := BattleScreen.new()
	b.hero = h
	b.wave = 1
	b.wins = 0
	b._ready()

	# Сундук с врага: 1 случайный предмет сразу, без выбора
	var before: int = h.inventory.size()
	var c := b._spawn_chest(Vector2(500, 400), false)
	b._on_chest_clicked(c)
	_check(h.inventory.size() == before + 1, "сундук с врага даёт 1 предмет сразу")
	_check(b._chests.is_empty(), "открытый сундук исчезает с поля")

	# Финальный сундук: выбор 1 из 3 без повторов
	var fc := b._spawn_chest(Vector2(620, 330), true)
	b._on_chest_clicked(fc)
	_check(b._current_choices.size() == Enemies.CHEST_CHOICES, "финальный сундук предлагает выбор 1 из 3")
	var names := []
	var unique := true
	for it in b._current_choices:
		if names.has(it.name):
			unique = false
		names.append(it.name)
	_check(unique, "в финальном сундуке нет одинаковых предметов")
	b._on_chest_choice(b._current_choices[0])
	_check(h.inventory.size() == before + 2, "предмет из финального сундука попал в рюкзак")
	_check(b._chests.is_empty(), "финальный сундук собран")

	# Лечение при повышении уровня — частичное
	b._hero_actor.hp = 10.0
	var e := Actor.new()
	e.setup("тест", {"hp": 1, "atk": 1, "def": 0, "spd": 1.0, "xp": 10, "type": "slime"}, Color.WHITE, "rect", 10.0, "enemy")
	b._on_enemy_died(e)
	var expected := 10.0 + b._hero_actor.max_hp * Hero.LEVEL_UP_HEAL
	_check(absf(b._hero_actor.hp - expected) < 0.01, "уровень лечит часть HP (10 + %.0f%% макс.)" % (Hero.LEVEL_UP_HEAL * 100))
	_check(b._hero_actor.hp < b._hero_actor.max_hp, "лечение при уровне — не полное")
	e.free()

	# Скорость боя x1/x2
	b.set_speed(2.0)
	_check(Engine.time_scale == 2.0, "ускорение боя x2")
	b.set_speed(1.0)
	_check(Engine.time_scale == 1.0, "возврат к скорости x1")

	# Выбранная скорость сохраняется в следующем бою
	b.set_speed(2.0)
	var b2 := BattleScreen.new()
	b2.hero = Hero.new()
	b2.wave = 1
	b2.wins = 0
	b2._ready()
	_check(Engine.time_scale == 2.0, "скорость боя сохраняется в новом бою")
	b2.set_speed(1.0)
	b2.free()

	b.free()


func _test_battle_sim() -> void:
	print("-- Симуляция боя волны 1 (пошагово, 0.05 с) --")
	var h := Hero.new()
	var b := BattleScreen.new()
	b.hero = h
	b.wave = 1
	b.wins = 0
	b._ready()

	var dt := 0.05
	var steps := 0
	var choices_seen := 0
	var choices_unique := true
	while b._state != "done" and steps < 6000:
		b.step(dt)
		b._hero_actor.step(dt)
		for e in b._enemies:
			e.step(dt)
		# Фаза сундуков: открываем все, у финального выбираем первый предмет
		if b._state == "loot":
			_open_field_chests(b)
			if not b._current_choices.is_empty():
				choices_seen += 1
				var names := []
				for it in b._current_choices:
					if names.has(it.name):
						choices_unique = false
					names.append(it.name)
				b._on_chest_choice(b._current_choices[0])
		steps += 1

	_check(b._state == "done", "бой завершился за %d шагов" % steps)
	_check(b._hero_actor.alive, "герой выжил на волне 1")
	_check(b._kills == b._enemy_total, "все враги повержены (%d/%d)" % [b._kills, b._enemy_total])
	_check(h.xp > 0 or h.level > 1, "герой получил опыт")
	_check(choices_seen >= 1, "открылся финальный сундук (открыто: %d)" % choices_seen)
	_check(choices_unique, "в сундуках нет одинаковых предметов")
	_check(h.inventory.size() >= 1, "награды попали в рюкзак (всего: %d)" % h.inventory.size())
	_check(b._chests.is_empty(), "бой завершился только после сбора всех сундуков")
	b.free()


## Открыть все сундуки на поле: вражеские — сразу, финальный — кликом (выбор появится).
func _open_field_chests(b: BattleScreen) -> void:
	for c in b._chests.duplicate():
		b._on_chest_clicked(c)


func _run_battle(h: Hero, wave: int, wins: int) -> BattleScreen:
	var b := BattleScreen.new()
	b.hero = h
	b.wave = wave
	b.wins = wins
	b._ready()
	var dt := 0.05
	var steps := 0
	while b._state != "done" and steps < 12000:
		b.step(dt)
		b._hero_actor.step(dt)
		for e in b._enemies:
			e.step(dt)
		if b._state == "loot":
			_open_field_chests(b)
			if not b._current_choices.is_empty():
				b._on_chest_choice(b._current_choices[0])
		steps += 1
	return b


func _test_boss_sims() -> void:
	print("-- Симуляция босса: сильный и слабый герой --")

	# Сильный герой должен победить босса
	var strong := Hero.new()
	strong.add_xp(600)
	while strong.stat_points > 0:
		strong.allocate("hp")
		if strong.stat_points > 0:
			strong.allocate("atk")
	for slot in ["weapon", "armor", "amulet"]:
		var it := Item.new()
		it.name = "Легенда"
		it.slot = slot
		it.rarity = 4
		it.bonuses = {"atk": 8, "hp": 20, "def": 4}
		strong.inventory.append(it)
		strong.equip(it)
	var b1 := _run_battle(strong, Enemies.TOTAL_WAVES, 0)
	_check(b1._state == "done", "бой с боссом завершился")
	_check(b1._hero_actor.alive, "прокачанный герой победил босса")
	b1.free()

	# Голый герой 1 уровня должен проиграть (и игра это корректно обрабатывает)
	var weak := Hero.new()
	var b2 := _run_battle(weak, Enemies.TOTAL_WAVES, 0)
	_check(b2._state == "done", "бой слабого героя завершился")
	_check(not b2._hero_actor.alive, "слабый герой пал — путь поражения работает")
	b2.free()
