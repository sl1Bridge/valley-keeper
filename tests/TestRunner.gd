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
	_test_enemies()
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
		if not Item.SLOT_NAMES.has(it.slot) or it.rarity < 0 or it.rarity > 2 or it.bonuses.is_empty():
			ok = false
		if it.bonuses_text().is_empty():
			ok = false
	_check(ok, "40 предметов: слот, редкость и бонусы валидны")

	var chest_ok := true
	for i in 20:
		var it := Item.generate(rng, -1, true)
		if it.rarity < 0 or it.rarity > 2:
			chest_ok = false
	_check(chest_ok, "генерация из сундука работает")

	var epic := Item.generate(rng, 2)
	_check(epic.rarity == 2 and epic.rarity_name() == "Эпический", "принудительная эпическая редкость")


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


func _test_enemies() -> void:
	print("-- Враги и волны --")
	var comp1 := Enemies.wave_composition(1)
	_check(comp1.size() == 3 and comp1.all(func(t): return t == "slime"), "волна 1 — три слизня")
	_check(Enemies.wave_composition(10) == ["boss"], "волна 10 — босс")
	_check(Enemies.wave_composition(5).has("golem"), "с 5 волны появляются големы")

	var base: Dictionary = Enemies.TYPES["slime"]
	var scaled := Enemies.scaled("slime", 5, 0)
	_check(int(scaled["hp"]) > int(base["hp"]), "враги усиливаются к 5 волне")
	var ng := Enemies.scaled("slime", 1, 2)
	_check(int(ng["hp"]) > int(base["hp"]), "новый заход сложнее")

	_check(Enemies.BASE_CHESTS == 1, "1 гарантированный сундук за волну")
	_check(Enemies.CHEST_DROP_CHANCE > 0.0 and Enemies.CHEST_DROP_CHANCE < 0.5, "шанс доп. сундука разумный")


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
		# Фаза сундуков: выбираем первый предмет, заодно проверяем отсутствие повторов
		if b._state == "loot" and not b._current_choices.is_empty():
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
	_check(choices_seen >= 1, "открылся минимум 1 сундук (открыто: %d)" % choices_seen)
	_check(choices_unique, "в сундуках нет одинаковых предметов")
	_check(h.inventory.size() >= 1, "выбранный предмет попал в рюкзак (всего: %d)" % h.inventory.size())
	b.free()


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
		if b._state == "loot" and not b._current_choices.is_empty():
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
		it.name = "Эпик"
		it.slot = slot
		it.rarity = 2
		it.bonuses = {"atk": 8, "hp": 20, "def": 4}
		strong.inventory.append(it)
		strong.equip(it)
	var b1 := _run_battle(strong, 10, 0)
	_check(b1._state == "done", "бой с боссом завершился")
	_check(b1._hero_actor.alive, "прокачанный герой победил босса")
	b1.free()

	# Голый герой 1 уровня должен проиграть (и игра это корректно обрабатывает)
	var weak := Hero.new()
	var b2 := _run_battle(weak, 10, 0)
	_check(b2._state == "done", "бой слабого героя завершился")
	_check(not b2._hero_actor.alive, "слабый герой пал — путь поражения работает")
	b2.free()
