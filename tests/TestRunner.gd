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
	_test_heroes_roster()
	_test_class_slots()
	_test_diminishing()
	_test_settings()
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
			_check(main._screen is MainMenu, "стартовый экран — главное меню")
			_check(main._screen._start_btn.disabled, "без выбора героя забег начать нельзя")
			main._on_menu_start("knight")
			_phase = 3
			_frames = 0
		return false
	if _phase == 3:
		_frames += 1
		if _frames >= 30:
			var main := root.get_node("Main")
			_check(main._screen is GearScreen, "после выбора героя — лагерь")
			main._on_embark()
			_phase = 4
			_frames = 0
		return false
	if _phase == 4:
		_frames += 1
		if _frames >= 30:
			var main := root.get_node("Main")
			_check(main._screen is BattleScreen, "Main переключился на экран боя")
			var actor_col: Color = (main._screen as BattleScreen)._hero_actor.body_color
			_check(actor_col == Hero.ROSTER["knight"]["color"], "на поле боя — внешность выбранного героя")
			_test_victory_flow(main)
			return _finish()
		return false
	return false


## Победа над боссом → главное меню; новый забег всегда начинается с нуля.
func _test_victory_flow(main) -> void:
	print("-- Победа → главное меню, новый забег с нуля --")
	main._on_boss_defeated()
	var btn := _find_button(main._screen)
	_check(btn != null, "на экране победы есть кнопка")
	if btn != null:
		btn.pressed.emit()
	_check(main._screen is MainMenu, "после победы игрок попадает в главное меню")
	main._on_menu_start("rogue")
	_check(main.hero.kind == "rogue", "выбран второй герой")
	_check(main.hero.level == 1 and main.hero.wave == 1, "новый забег — с нуля (уровень 1, волна 1)")
	_check(main.hero.inventory.is_empty(), "прогресс между забегами не сохраняется (рюкзак пуст)")
	_check(main._screen is GearScreen, "после выбора героя — лагерь")


func _find_button(node: Node) -> Button:
	if node is Button:
		return node
	for c in node.get_children():
		var found := _find_button(c)
		if found != null:
			return found
	return null


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


func _test_heroes_roster() -> void:
	print("-- Герои: реестр, выбор, прогресс --")
	_check(Hero.KINDS.size() == 2, "в игре два героя")
	var distinct := true
	var seen := {}
	for kind in Hero.KINDS:
		var def: Dictionary = Hero.ROSTER[kind]
		var visual: String = str(def["color"]) + def["shape"]
		if def["name"] == "" or seen.has(visual):
			distinct = false
		seen[visual] = true
	_check(distinct, "герои различаются именем и внешностью")
	var h := Hero.new()
	_check(h.kind == Hero.KINDS[0], "герой по умолчанию — первый из реестра")
	h.kind = Hero.KINDS[1]
	_check(h.hero_name() == Hero.ROSTER[Hero.KINDS[1]]["name"], "имя героя соответствует выбранному классу")
	_check(h.wave == 1, "забег героя начинается с 1-й волны")
	# Базовые характеристики классов пока одинаковые (отличия — слоты и классовая характеристика)
	var h2 := Hero.new()
	var same := true
	for k in Hero.STAT_ORDER:
		if h.get_stats()[k] != h2.get_stats()[k]:
			same = false
	_check(same, "базовые характеристики классов одинаковые")


func _test_settings() -> void:
	print("-- Настройки: громкость музыки и звуков --")
	_check(absf(Settings.music_volume - 0.5) < 0.001 and absf(Settings.sfx_volume - 0.5) < 0.001, "громкость по умолчанию — 50%%")
	Settings.set_music_volume(0.8)
	_check(absf(Settings.music_volume - 0.8) < 0.001, "громкость музыки меняется")
	Settings.set_sfx_volume(1.5)
	_check(absf(Settings.sfx_volume - 1.0) < 0.001, "громкость ограничена 100%%")
	Settings.set_music_volume(0.5)
	Settings.set_sfx_volume(0.5)
	Settings.ensure_buses()
	_check(AudioServer.get_bus_index("Music") != -1, "звуковая шина Music создана")
	_check(AudioServer.get_bus_index("SFX") != -1, "звуковая шина SFX создана")


func _test_class_slots() -> void:
	print("-- Классы: слоты, два оружия Вора, классовые предметы --")
	var k := Hero.new("knight")
	_check(k.equip_slots().has("shield"), "у Рыцаря есть слот под щит")
	var r := Hero.new("rogue")
	_check(r.equip_slots().has("weapon1") and r.equip_slots().has("weapon2"), "у Вора два слота под оружие")
	_check(not r.equip_slots().has("shield") and not r.equip_slots().has("weapon"), "у Вора нет щита и единого слота оружия")

	# Вор носит два оружия; бросок на конкретный слот заменяет именно его
	var mk := func(p_name: String) -> Item:
		var it := Item.new()
		it.name = p_name
		it.slot = "weapon"
		it.rarity = 0
		it.bonuses = {"atk": 1}
		return it
	var w1: Item = mk.call("Клинок 1")
	var w2: Item = mk.call("Клинок 2")
	var w3: Item = mk.call("Клинок 3")
	r.inventory.append(w1)
	r.equip(w1)
	r.inventory.append(w2)
	r.equip(w2)
	_check(r.equipment["weapon1"] == w1 and r.equipment["weapon2"] == w2, "Вор надел два оружия")
	r.inventory.append(w3)
	var old := r.equip(w3, "weapon2")
	_check(r.equipment["weapon2"] == w3 and r.equipment["weapon1"] == w1, "бросок на Оружие II заменил именно его")
	_check(old == w2 and r.inventory.has(w2), "снятый клинок вернулся в рюкзак")
	_check(int(r.get_stats()["atk"]) == int(Hero.BASE["atk"]) + 2, "бонусы двух оружий складываются")

	# Совместимость слотов
	_check(Hero.slot_accepts("shield", "shield"), "щит встаёт в слот щита")
	_check(not Hero.slot_accepts("weapon1", "shield"), "щит не встаёт в слот оружия")
	_check(Hero.slot_accepts("weapon2", "weapon"), "оружие встаёт в Оружие II")
	_check(not Hero.slot_accepts("armor", "weapon"), "оружие не встаёт в броню")

	# Классовые предметы: щиты выпадают только Рыцарю
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var rogue_saw_shield := false
	for i in 300:
		if Item.generate(rng, -1, 5, [], false, "rogue").slot == "shield":
			rogue_saw_shield = true
	_check(not rogue_saw_shield, "Вору щит не выпадает никогда (300 генераций)")
	rng.seed = 77
	var knight_saw_shield := false
	for i in 300:
		if Item.generate(rng, -1, 5, [], false, "knight").slot == "shield":
			knight_saw_shield = true
	_check(knight_saw_shield, "Рыцарю щиты выпадают")

	# Предметы на уворот — только Вору, на блок — только Рыцарю
	rng.seed = 99
	var rogue_saw_block := false
	var rogue_saw_dodge := false
	for i in 400:
		var it := Item.generate(rng, -1, 8, [], false, "rogue")
		if it.bonuses.has("block"):
			rogue_saw_block = true
		if it.bonuses.has("dodge"):
			rogue_saw_dodge = true
	_check(rogue_saw_dodge, "Вору выпадают предметы на уворот")
	_check(not rogue_saw_block, "Вору не выпадают предметы на блок")
	rng.seed = 99
	var knight_saw_dodge := false
	var knight_saw_block := false
	for i in 400:
		var it2 := Item.generate(rng, -1, 8, [], false, "knight")
		if it2.bonuses.has("dodge"):
			knight_saw_dodge = true
		if it2.bonuses.has("block"):
			knight_saw_block = true
	_check(knight_saw_block, "Рыцарю выпадают предметы на блок")
	_check(not knight_saw_dodge, "Рыцарю не выпадают предметы на уворот")


func _test_diminishing() -> void:
	print("-- Формулы затухания: защита %, скорость, регенерация, уворот/блок --")
	var e0 := Hero.effective({"def": 0, "spd": 0, "regen": 0})
	_check(absf(e0["def_pct"]) < 0.001, "без защиты снижение урона 0%")
	var e15 := Hero.effective({"def": 15, "spd": 0, "regen": 0})
	_check(absf(e15["def_pct"] - 0.5) < 0.001, "защита 15 → снижение 50%")
	var e30 := Hero.effective({"def": 30, "spd": 0, "regen": 0})
	_check(e30["def_pct"] > e15["def_pct"] and e30["def_pct"] < 0.7, "защита 30 → меньше 70%")
	var inc1: float = e15["def_pct"] - e0["def_pct"]
	var inc2: float = e30["def_pct"] - e15["def_pct"]
	_check(inc2 < inc1, "прирост защиты затухает: вторые +15 дают меньше первых")

	_check(absf(e0["aps"] - 1.0) < 0.001, "без очков скорости — базовый темп 1.00 уд/с")
	var s10 := Hero.effective({"spd": 10, "def": 0, "regen": 0})
	_check(absf(s10["aps"] - 2.0) < 0.001, "скорость 10 → 2.00 уд/с")
	_check(s10["aps"] < 1.0 + Hero.SPD_CAP, "темп ниже максимума формулы")
	var r12 := Hero.effective({"regen": 12, "def": 0, "spd": 0})
	_check(absf(r12["regen_hp"] - 4.0) < 0.001, "регенерация 12 → 4 HP/с")
	var d15 := Hero.effective({"dodge": 15})
	_check(absf(d15["class_pct"] - 0.3) < 0.001, "уворот 15 → шанс 30%")

	# Урон снижается на процент защиты цели
	var attacker := Actor.new()
	attacker.setup("атакующий", {"hp": 10, "atk": 10, "spd": 1.0}, Color.WHITE, "rect", 10.0, "hero")
	var victim := Actor.new()
	victim.setup("цель", {"hp": 100, "atk": 1, "spd": 1.0}, Color.WHITE, "rect", 10.0, "enemy")
	victim.def_pct = 0.5
	attacker.target = victim
	attacker._attack()
	_check(victim.hp == 95.0, "урон 10 по защите 50% → 5")
	# Уворот/блок: при 100% атака полностью избегается
	victim.evasion = 1.0
	victim.hp = 95.0
	attacker._attack()
	_check(victim.hp == 95.0, "уворот 100% → урон полностью избегнут")
	attacker.free()
	victim.free()

	# Классовую характеристику нельзя качать очками за уровень
	var rr := Hero.new("rogue")
	rr.stat_points = 3
	_check(not rr.allocate("dodge"), "уворот нельзя качать очками — только предметы")
	var kk := Hero.new("knight")
	kk.stat_points = 3
	_check(not kk.allocate("block"), "блок нельзя качать очками — только предметы")
	_check(rr.stat_order().has("dodge") and not rr.stat_order().has("block"), "у Вора отображается уворот, а не блок")


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

	# Бросок кольца на конкретный слот заменяет именно его, а не первый
	var r4 := _make_ring("Кольцо 4")
	h.inventory.append(r4)
	var old2 := h.equip(r4, "ring2")
	_check(h.equipment["ring2"] == r4 and h.equipment["ring1"] == r3, "бросок на Кольцо II заменил именно его")
	_check(old2 == r2 and h.inventory.has(r2), "снятое с Кольца II вернулось в рюкзак")

	# Регенерация: вложение очков и бонус предмета
	h.add_xp(10)
	h.allocate("regen")
	var regen_ring := Item.new()
	regen_ring.name = "Кольцо регенерации"
	regen_ring.slot = "ring"
	regen_ring.rarity = 0
	regen_ring.bonuses = {"regen": 3}
	h.inventory.append(regen_ring)
	h.equip(regen_ring)
	var expected := Hero.PER_POINT["regen"] + 3.0
	_check(absf(h.get_stats()["regen"] - expected) < 0.001, "регенерация = очко + кольцо (%.0f очков)" % expected)

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
	var scaled := Enemies.scaled("slime", 5)
	_check(int(scaled["hp"]) > int(base["hp"]), "враги усиливаются к 5 волне")

	_check(Enemies.BASE_CHESTS == 1, "1 гарантированный сундук за волну")
	_check(Enemies.CHEST_DROP_CHANCE > 0.0 and Enemies.CHEST_DROP_CHANCE < 0.5, "шанс доп. сундука разумный")


func _test_chests_heal_speed() -> void:
	print("-- Сундуки, лечение при уровне, скорость боя --")
	var h := Hero.new()
	var b := BattleScreen.new()
	b.hero = h
	b.wave = 1
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


func _run_battle(h: Hero, wave: int) -> BattleScreen:
	var b := BattleScreen.new()
	b.hero = h
	b.wave = wave
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
	var b1 := _run_battle(strong, Enemies.TOTAL_WAVES)
	_check(b1._state == "done", "бой с боссом завершился")
	_check(b1._hero_actor.alive, "прокачанный герой победил босса")
	_check(b1._boss_dead and b1._chests.is_empty(), "победа над боссом — сразу, без фазы сундуков")
	b1.free()

	# Голый герой 1 уровня должен проиграть (и игра это корректно обрабатывает)
	var weak := Hero.new()
	var b2 := _run_battle(weak, Enemies.TOTAL_WAVES)
	_check(b2._state == "done", "бой слабого героя завершился")
	_check(not b2._hero_actor.alive, "слабый герой пал — путь поражения работает")
	b2.free()
