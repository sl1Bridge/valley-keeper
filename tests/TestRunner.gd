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
	_test_item_pool()
	_test_hero()
	_test_heroes_roster()
	_test_class_slots()
	_test_diminishing()
	_test_settings()
	_test_rings_and_regen()
	_test_inventory()
	_test_enemies()
	_test_poison()
	_test_bleed_stun()
	_test_enemy_tooltip()
	_test_summon_taunt()
	_test_hero_abilities()
	_test_battle_layout()
	_test_attack_jitter()
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
			var bs := main._screen as BattleScreen
			var actor_col: Color = bs._hero_actor.body_color
			_check(actor_col == Hero.ROSTER["knight"]["color"], "на поле боя — внешность выбранного героя")
			_check(bs.size.y > 100.0, "экран боя имеет реальный размер (родитель — Node, якоря не работают сами)")
			_check(bs._ability_icon.position.y > 100.0, "иконка способности в нижней части экрана, а не за верхним краем")
			_test_surrender_flow(main)
			_test_victory_flow(main)
			return _finish()
		return false
	return false


## Сдача забега: кнопка-флаг, окно подтверждения, пауза боя при модальных окнах.
func _test_surrender_flow(main) -> void:
	print("-- Сдача забега и пауза боя --")
	_check(main._surrender_btn.visible, "кнопка сдачи видна на экране боя")

	# Настройки во время боя ставят бой на паузу
	main._on_settings_pressed()
	_check(paused, "бой на паузе, пока открыты настройки")
	var win := _find_modal(main, "settings")
	_check(win != null, "окно настроек открылось")
	if win != null:
		win._on_close()
	_check(not paused, "закрытие настроек снимает паузу")

	# Окно сдачи: пауза, отмена возвращает в бой
	main._on_surrender_pressed()
	_check(paused, "бой на паузе, пока открыто окно сдачи")
	var dlg := _find_modal(main, "surrender")
	_check(dlg != null, "окно подтверждения сдачи открылось")
	if dlg != null:
		dlg._on_cancel()
	_check(not paused, "отмена сдачи снимает паузу")
	_check(main._screen is BattleScreen, "после отмены мы всё ещё в бою")

	# Подтверждение: забег завершён, возврат в главное меню
	main._on_surrender_pressed()
	var dlg2 := _find_modal(main, "surrender")
	if dlg2 != null:
		dlg2._on_confirm()
	_check(main._screen is MainMenu, "после подтверждения сдачи — главное меню")
	_check(main.hero == null, "герой забега сброшен")
	_check(not paused, "пауза снята после сдачи")
	_check(not main._surrender_btn.visible, "в главном меню кнопка сдачи скрыта")
	_check(Engine.time_scale == 1.0, "скорость боя сброшена после ухода с экрана боя")


## Найти открытое модальное окно в оверлей-слое Main.
func _find_modal(main, what: String) -> Control:
	for c in main._settings_layer.get_children():
		if what == "settings" and c is Settings.SettingsWindow:
			return c
		if what == "surrender" and c is GameMain.SurrenderDialog:
			return c
	return null


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
	_check(main._surrender_btn.visible, "кнопка сдачи видна в лагере")


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


func _test_item_pool() -> void:
	print("-- Пул предметов: баланс шаблонов --")
	# Большинство предметов имеет негативную сторону
	var with_neg := 0
	var without_neg := 0
	for t in Item.TEMPLATES:
		var has_neg := false
		for k in t["bonuses"]:
			if t["bonuses"][k] < 0:
				has_neg = true
		if has_neg:
			with_neg += 1
		else:
			without_neg += 1
	_check(with_neg > without_neg, "большинство предметов со штрафом (%d из %d)" % [with_neg, Item.TEMPLATES.size()])

	# Сумма плюсов шаблона (уворот/блок считаем за очки)
	var pos_sum := func(t: Dictionary) -> float:
		var s := 0.0
		for k in t["bonuses"]:
			if t["bonuses"][k] > 0:
				s += t["bonuses"][k]
		return s
	# a строго лучше b: не хуже по всем характеристикам и лучше хотя бы по одной
	var dominates := func(a: Dictionary, b: Dictionary) -> bool:
		var better := false
		var keys := {}
		for k in a["bonuses"]:
			keys[k] = true
		for k in b["bonuses"]:
			keys[k] = true
		for k in keys:
			var av: float = a["bonuses"].get(k, 0)
			var bv: float = b["bonuses"].get(k, 0)
			if av < bv:
				return false
			if av > bv:
				better = true
		return better
	var band_ok := true
	var fair_ok := true
	for i in Item.TEMPLATES.size():
		for j in Item.TEMPLATES.size():
			if i == j:
				continue
			var a: Dictionary = Item.TEMPLATES[i]
			var b: Dictionary = Item.TEMPLATES[j]
			if a["slot"] != b["slot"] or a.get("class", "") != b.get("class", ""):
				continue
			if absf(pos_sum.call(a) - pos_sum.call(b)) > 2.0:
				band_ok = false
			if dominates.call(a, b):
				fair_ok = false
	_check(band_ok, "внутри слота суммы плюсов различаются не больше чем на 2 очка")
	_check(fair_ok, "ни один предмет не хуже другого того же слота по всем характеристикам")

	# Штрафы не растут с редкостью (плюсы множатся, минусы — нет)
	var rng5 := RandomNumberGenerator.new()
	rng5.seed = 77
	var neg_ok := true
	var seen_neg := 0
	for i in 200:
		var it := Item.generate(rng5, 5)
		for t in Item.TEMPLATES:
			if t["name"] != it.name:
				continue
			for k in t["bonuses"]:
				if t["bonuses"][k] < 0:
					seen_neg += 1
					if int(it.bonuses.get(k, 0)) != int(t["bonuses"][k]):
						neg_ok = false
	_check(seen_neg > 0, "в генерации артефактов встречались предметы со штрафом (%d)" % seen_neg)
	_check(neg_ok, "штрафы не множатся на редкость")


func _test_hero() -> void:
	print("-- Герой: характеристики, опыт, экипировка --")
	var h := Hero.new()
	var s := h.get_stats()
	_check(int(s["atk"]) == int(Hero.BASE[h.kind]["atk"]) and int(s["surv"]) == int(Hero.BASE[h.kind]["surv"]), "базовые характеристики берутся из базы класса")
	_check(not s.has("hp") and not s.has("regen"), "здоровье и регенерация — не характеристики, а производные Выносливости")
	_check(h.max_hp() > 35.0 and h.max_hp() < 40.0, "стартовое здоровье Рыцаря около 37 (%d)" % int(h.max_hp()))
	_check(not h.allocate("atk"), "нельзя вложить очко без очков")

	var levels := h.add_xp(10)
	_check(levels == 1 and h.level == 2 and h.stat_points == Hero.POINTS_PER_LEVEL, "переход на 2 уровень")
	_check(h.allocate("atk"), "вложение очка в атаку")
	_check(int(h.get_stats()["atk"]) == int(Hero.BASE["knight"]["atk"]) + Hero.PER_POINT["atk"], "атака выросла на прирост за очко")

	var it := Item.new()
	it.name = "Тестовый меч"
	it.slot = "weapon"
	it.rarity = 0
	it.bonuses = {"atk": 3}
	h.inventory.append(it)
	h.equip(it)
	_check(h.equipment["weapon"] == it and h.inventory.is_empty(), "предмет надет из рюкзака")
	_check(int(h.get_stats()["atk"]) == int(Hero.BASE["knight"]["atk"]) + Hero.PER_POINT["atk"] + 3, "бонус меча учитывается (+3)")
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
	# Базовые характеристики классов различаются: Рыцарь — защитный, Вор — атакующий
	var kk := Hero.new("knight")
	var rr := Hero.new("rogue")
	var ks := kk.get_stats()
	var rs := rr.get_stats()
	_check(ks["def"] > rs["def"] and ks["surv"] > rs["surv"], "у Рыцаря больше защита и выносливость")
	_check(rs["atk"] > ks["atk"] and rs["spd"] > ks["spd"], "у Вора больше сила и ловкость")
	_check(absf(Hero.effective(ks)["class_pct"] - Hero.BASE_CLASS_PCT["knight"] / 100.0) < 0.001, "у Рыцаря базовый шанс блока %d%%" % int(Hero.BASE_CLASS_PCT["knight"]))
	_check(absf(Hero.effective(rs)["class_pct"] - Hero.BASE_CLASS_PCT["rogue"] / 100.0) < 0.001, "у Вора базовый шанс уворота %d%%" % int(Hero.BASE_CLASS_PCT["rogue"]))


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
	_check(k.equip_slots().has("helmet") and k.equip_slots().has("boots"), "у Рыцаря есть слоты шлема и сапог")
	_check(r.equip_slots().has("helmet") and r.equip_slots().has("boots"), "у Вора есть слоты шлема и сапог")

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
	_check(int(r.get_stats()["atk"]) == int(Hero.BASE["rogue"]["atk"]) + 2, "бонусы двух оружий складываются")

	# Совместимость слотов
	_check(Hero.slot_accepts("shield", "shield"), "щит встаёт в слот щита")
	_check(not Hero.slot_accepts("weapon1", "shield"), "щит не встаёт в слот оружия")
	_check(Hero.slot_accepts("weapon2", "weapon"), "оружие встаёт в Оружие II")
	_check(not Hero.slot_accepts("armor", "weapon"), "оружие не встаёт в броню")
	_check(Hero.slot_accepts("helmet", "helmet") and Hero.slot_accepts("boots", "boots"), "шлем и сапоги встают в свои слоты")
	_check(not Hero.slot_accepts("helmet", "boots") and not Hero.slot_accepts("boots", "helmet"), "шлем и сапоги не взаимозаменяемы")

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

	# Классовые шлемы/сапоги: свои — выпадают, чужие — никогда
	rng.seed = 123
	var knight_saw_rogue_gear := false
	var saw_helmet := false
	var saw_boots := false
	for i in 400:
		var it3 := Item.generate(rng, -1, 8, [], false, "knight")
		if it3.name == "Капюшон тени" or it3.name == "Сапоги акробата":
			knight_saw_rogue_gear = true
		if it3.slot == "helmet":
			saw_helmet = true
		if it3.slot == "boots":
			saw_boots = true
	_check(not knight_saw_rogue_gear, "Рыцарю не выпадают шлем и сапоги Вора (400 генераций)")
	_check(saw_helmet and saw_boots, "шлемы и сапоги реально выпадают")


func _test_diminishing() -> void:
	print("-- Формулы затухания: защита %, ловкость, выносливость, уворот/блок --")
	# Отображаемые названия: Сила, Ловкость, Выносливость
	_check(Item.STAT_NAMES["atk"] == "Сила", "атака отображается как Сила")
	_check(Item.STAT_NAMES["spd"] == "Ловкость", "скорость атаки отображается как Ловкость")
	_check(Item.STAT_NAMES["surv"] == "Выносливость", "Выживаемость переименована в Выносливость")

	# S-образная кривая cap × raw² / (raw² + K²): слабая на низких, мягкий предел на высоких
	var e0 := Hero.effective({"def": 0, "spd": 0, "surv": 0})
	_check(absf(e0["def_pct"]) < 0.001, "без защиты снижение урона 0%")
	var e5 := Hero.effective({"def": 5, "spd": 0, "surv": 0})
	_check(e5["def_pct"] > 0.05 and e5["def_pct"] < 0.08, "защита 5 → ~6%% (равноценно старой базе)")
	var e15 := Hero.effective({"def": 15, "spd": 0, "surv": 0})
	_check(e15["def_pct"] > 0.35 and e15["def_pct"] < 0.42, "защита 15 → ~38%%")
	var e30 := Hero.effective({"def": 30, "spd": 0, "surv": 0})
	_check(e30["def_pct"] > 0.56 and e30["def_pct"] < 0.61, "защита 30 → ~58%% (софт-кап уменьшил прирост)")
	var inc1: float = e15["def_pct"] - e5["def_pct"]
	var e45 := Hero.effective({"def": 45, "spd": 0, "surv": 0})
	_check(e45["def_pct"] > 0.63 and e45["def_pct"] < 0.68, "защита 45 → ~66%% (хард-кап уменьшил ещё сильнее)")
	var inc2: float = e45["def_pct"] - e30["def_pct"]
	_check(inc2 < inc1, "прирост защиты затухает на высоких значениях (45→30 слабее 5→15)")
	_check(e5["def_pct"] < e15["def_pct"] / 3.0, "на низких значениях эффект занижен (S-кривая)")

	# Софт- и хард-капы очков: до 15 — полная сила, 15–30 — прирост ×0.5, сверх 30 — ×0.25
	_check(absf(Hero.cap_points(10.0) - 10.0) < 0.001, "до софт-капа очки без изменений")
	_check(absf(Hero.cap_points(Hero.STAT_SOFT_CAP) - Hero.STAT_SOFT_CAP) < 0.001, "на софт-капе очки без изменений")
	_check(absf(Hero.cap_points(20.0) - 17.5) < 0.001, "между капами прирост ×0.5 (20 → 17.5)")
	_check(absf(Hero.cap_points(50.0) - 27.5) < 0.001, "сверх хард-капа прирост ×0.25 (50 → 27.5)")
	_check(absf(Hero.cap_points(-5.0) + 5.0) < 0.001, "штрафы проходят без капов")
	_check(absf(Hero.effective({"atk": 40.0})["atk"] - 25.0) < 0.001, "сила тоже проходит капы (40 → 25)")
	_check(absf(Hero.effective({"atk": 8.0})["atk"] - 8.0) < 0.001, "сила ниже софт-капа без изменений")

	_check(absf(e0["aps"] - 1.0) < 0.001, "без очков ловкости — базовый темп 1.00 уд/с")
	var s5 := Hero.effective({"spd": 5, "def": 0, "surv": 0})
	_check(s5["aps"] > 1.05 and s5["aps"] < 1.15, "ловкость 5 → ~1.10 уд/с (равноценно старой базе)")
	var s10 := Hero.effective({"spd": 10, "def": 0, "surv": 0})
	_check(s10["aps"] > 1.30 and s10["aps"] < 1.38, "ловкость 10 → ~1.34 уд/с")
	_check(s10["aps"] < 1.0 + Hero.SPD_CAP, "темп ниже максимума формулы")
	var s_neg := Hero.effective({"spd": -2, "def": 0, "surv": 0})
	_check(s_neg["aps"] < 1.0 and s_neg["aps"] >= 0.9, "штраф ловкости снижает темп (знак сохраняется)")

	# Выносливость: здоровье и регенерация с затуханием
	_check(absf(e0["max_hp"]) < 0.001 and absf(e0["regen_hp"]) < 0.001, "без выносливости нет ни здоровья, ни регенерации")
	var v5 := Hero.effective({"surv": 5, "def": 0, "spd": 0})
	_check(absf(v5["max_hp"] - 28.0) < 0.5, "выносливость 5 → 28 HP (равноценно старой базе)")
	_check(v5["regen_hp"] > 0.6 and v5["regen_hp"] < 0.8, "выносливость 5 → ~0.7 HP/с")
	var v15 := Hero.effective({"surv": 15, "def": 0, "spd": 0})
	var v30 := Hero.effective({"surv": 30, "def": 0, "spd": 0})
	_check(absf(v30["max_hp"] - 117.0) < 0.5, "выносливость 30 → ~117 HP (с капами)")
	var v80 := Hero.effective({"surv": 80, "def": 0, "spd": 0})
	_check(v80["regen_hp"] > 6.4 and v80["regen_hp"] < 6.8, "выносливость 80 → ~6.6 HP/с (с капами)")
	var hp_inc1: float = v15["max_hp"] - v5["max_hp"]
	var hp_inc2: float = v30["max_hp"] - v15["max_hp"]
	_check(hp_inc2 < hp_inc1, "прирост здоровья от выносливости затухает")

	# Уворот/блок — прямые проценты (без формулы затухания), предел 60%
	var d15 := Hero.effective({"dodge": 15})
	_check(absf(d15["class_pct"] - 0.15) < 0.001, "уворот 15%% → шанс ровно 15%%")
	var d100 := Hero.effective({"dodge": 100})
	_check(absf(d100["class_pct"] - Hero.CLASS_CAP) < 0.001, "шанс уворота ограничен пределом %d%%" % roundi(Hero.CLASS_CAP * 100.0))

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
	_check(rr.allocate("surv"), "выносливость качается очками (базовая характеристика)")
	var kk := Hero.new("knight")
	kk.stat_points = 3
	_check(not kk.allocate("block"), "блок нельзя качать очками — только предметы")
	_check(rr.stat_order().has("dodge") and not rr.stat_order().has("block"), "у Вора отображается уворот, а не блок")


func _make_ring(p_name: String) -> Item:
	var r := Item.new()
	r.name = p_name
	r.slot = "ring"
	r.rarity = 0
	r.bonuses = {"surv": 2}
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

	# Выносливость: вложение очков и бонус предмета складываются (чистый герой)
	var h2 := Hero.new()
	var surv_base: float = h2.get_stats()["surv"]
	h2.add_xp(10)
	h2.allocate("surv")
	var surv_ring := Item.new()
	surv_ring.name = "Кольцо стойкости"
	surv_ring.slot = "ring"
	surv_ring.rarity = 0
	surv_ring.bonuses = {"surv": 3}
	h2.inventory.append(surv_ring)
	h2.equip(surv_ring)
	var expected: float = surv_base + Hero.PER_POINT["surv"] + 3.0
	_check(absf(h2.get_stats()["surv"] - expected) < 0.001, "выносливость = база + очко + кольцо (%.0f очков)" % expected)

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
	_check(comp1.size() == 2 and comp1.all(func(t): return t == "slime"), "волна 1 — два слизня")
	_check(Enemies.wave_composition(Enemies.TOTAL_WAVES) == ["boss"], "волна %d — босс" % Enemies.TOTAL_WAVES)
	_check(Enemies.TOTAL_WAVES == 20, "в локации 20 волн")

	# Бюджетная система: сумма цен закрывает бюджет (с округлением вверх),
	# не больше MAX_ENEMIES врагов, типы — не раньше своей волны допуска
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var budget_ok := true
	var capped := true
	var unlock_ok := true
	for w in range(1, Enemies.TOTAL_WAVES):
		var max_v := 1
		for t in Enemies.VALUES:
			if w >= Enemies.MIN_WAVE[t]:
				max_v = maxi(max_v, Enemies.VALUES[t])
		for i in 30:
			var comp := Enemies.wave_composition(w, rng)
			var sum := 0
			for t in comp:
				sum += Enemies.VALUES[t]
				if w < Enemies.MIN_WAVE[t]:
					unlock_ok = false
			var budget := Enemies.wave_value(w)
			if sum < budget or sum >= budget + max_v:
				budget_ok = false
			if comp.size() > Enemies.MAX_ENEMIES or comp.is_empty():
				capped = false
	_check(budget_ok, "сумма цен врагов закрывает бюджет волны (с округлением вверх)")
	_check(capped, "в волне от 1 до %d врагов" % Enemies.MAX_ENEMIES)
	_check(unlock_ok, "волк не раньше %d-й волны, голем — не раньше %d-й" % [Enemies.MIN_WAVE["wolf"], Enemies.MIN_WAVE["golem"]])
	_check(Enemies.wave_composition(2).all(func(t): return t == "slime"), "волна 2 — только слизни")

	# Поздние волны разнообразны: волк и голем встречаются, составы не повторяются
	rng.seed = 11
	var saw_wolf := false
	var saw_golem := false
	var seen := {}
	for i in 50:
		var comp: Array = Enemies.wave_composition(19, rng)
		if comp.has("wolf"):
			saw_wolf = true
		if comp.has("golem"):
			saw_golem = true
		var key := ""
		for t in comp:
			key += t + ","
		seen[key] = true
	_check(saw_wolf and saw_golem, "на 19-й волне встречаются и волки, и големы")
	_check(seen.size() >= 3, "состав 19-й волны разнообразен (%d вариантов за 50 бросков)" % seen.size())

	var base: Dictionary = Enemies.TYPES["slime"]
	var scaled := Enemies.scaled("slime", 5)
	_check(int(scaled["hp"]) > int(base["hp"]), "враги усиливаются к 5 волне")

	_check(Enemies.BASE_CHESTS == 1, "1 гарантированный сундук за волну")
	_check(Enemies.CHEST_DROP_CHANCE > 0.0 and Enemies.CHEST_DROP_CHANCE < 0.5, "шанс доп. сундука разумный")


func _test_poison() -> void:
	print("-- Отравление: стаки, затухание, снижение характеристик --")
	_check(absf(Hero.poison_pct(0)) < 0.001, "без стаков снижения нет")
	_check(absf(Hero.poison_pct(1) - 0.05) < 0.001, "1 стак отравления → −5%")
	_check(absf(Hero.poison_pct(2) - 0.08) < 0.001, "2 стака отравления → −8% (с затуханием)")
	_check(Hero.poison_pct(3) > Hero.poison_pct(2) and Hero.poison_pct(3) < 0.10, "3 стака → между 8% и 10%")
	_check(Hero.poison_pct(10) < 0.13, "затухание: даже 10 стаков далеки от 50%")

	var h := Hero.new()
	var b := BattleScreen.new()
	b.hero = h
	b.wave = 1
	b._ready()
	var clean_atk: float = b._hero_actor.stats["atk"]

	b._hero_actor.add_poison()
	_check(b._hero_actor.poison_times.size() == 1, "стак отравления наложен")
	var atk1: float = b._hero_actor.stats["atk"]
	_check(atk1 < clean_atk, "сила героя снижена отравлением")
	_check(b._hero_actor._badges["poison"].visible and b._hero_actor._badges["poison"].stacks == 1, "значок показывает 1 стак")

	b._hero_actor.add_poison()
	_check(float(b._hero_actor.stats["atk"]) < atk1, "второй стак усиливает снижение")
	_check(b._hero_actor._badges["poison"].stacks == 2, "значок показывает 2 стака")
	_check("%" in b._hero_actor._badges["poison"].tooltip_text, "в подсказке значка — конкретный процент снижения")

	# У каждого стака свой таймер: первый истекает раньше второго
	b._hero_actor.poison_times[0] = 0.05
	b._hero_actor.step(0.1)
	_check(b._hero_actor.poison_times.size() == 1, "истёк только самый старый стак")
	b._hero_actor.step(10.0)
	_check(b._hero_actor.poison_times.is_empty(), "все стаки истекли")
	_check(float(b._hero_actor.stats["atk"]) == clean_atk, "после отравления сила восстановилась")
	_check(not b._hero_actor._badges["poison"].visible, "значок скрыт без стаков")
	b.free()


func _test_bleed_stun() -> void:
	print("-- Кровотечение, оглушение, сброс эффектов после боя --")
	# Кровотечение: стаки со своими таймерами, урон в секунду, мимо уворота
	var a := Actor.new()
	a.setup("герой", {"hp": 200, "atk": 5, "spd": 1.0}, Color.WHITE, "rect", 10.0, "hero")
	a.engaged = true
	a.evasion = 1.0  # кровотечение игнорирует уворот
	a.add_bleed()
	a.add_bleed()
	_check(a.bleed_times.size() == 2, "кровотечение стакается")
	# Затухание стаков: база неизменна, каждый следующий стак добавляет меньше
	_check(absf(Hero.bleed_dps(1) - Hero.BLEED_DPS) < 0.001, "один стак — полные %d HP/с (база не изменилась)" % roundi(Hero.BLEED_DPS))
	_check(absf(Hero.bleed_dps(2) - 3.2) < 0.001, "2 стака — 3.2 HP/с (было 4 при линейном сложении)")
	_check(Hero.bleed_dps(3) - Hero.bleed_dps(2) < Hero.bleed_dps(2) - Hero.bleed_dps(1), "прирост от каждого следующего стака затухает")
	_check(Hero.bleed_dps(0) == 0.0, "без стаков урона нет")
	_check(a._badges["bleed"].visible and a._badges["bleed"].stacks == 2, "значок кровотечения показывает 2 стака")
	_check("HP/с" in a._badges["bleed"].tooltip_text, "в подсказке кровотечения — урон в секунду")
	var hp0: float = a.hp
	a.step(1.0)
	_check(absf(a.hp - (hp0 - floorf(Hero.bleed_dps(2)))) < 0.01, "2 стака кровотечения: −%d HP/с мимо уворота (урон капает целыми HP)" % floori(Hero.bleed_dps(2)))
	a.step(10.0)
	_check(a.bleed_times.is_empty(), "стаки кровотечения истекли")
	_check(not a._badges["bleed"].visible, "значок кровотечения скрыт без стаков")
	a.free()

	# Оглушение: герой не атакует, таймер атаки сброшен, не стакается
	var tgt := Actor.new()
	tgt.setup("цель", {"hp": 500, "atk": 1, "spd": 1.0}, Color.WHITE, "rect", 10.0, "enemy")
	var s := Actor.new()
	s.setup("герой", {"hp": 100, "atk": 5, "spd": 2.0}, Color.WHITE, "rect", 10.0, "hero")
	s.engaged = true
	s.target = tgt
	s._atk_timer = 0.4
	s.add_stun(0.5)
	_check(s._atk_timer == 0.0, "стан сбрасывает таймер атаки")
	_check(s._badges["stun"].visible and "Оглушение" in s._badges["stun"].tooltip_text, "значок оглушения с подсказкой")
	s.step(0.3)
	_check(tgt.hp == 500.0, "во время стана герой не атакует")
	s.step(0.3)  # стан кончился, таймер атаки накопил 0.3 < интервала 0.5
	_check(tgt.hp == 500.0, "после стана таймер атаки идёт заново")
	s.step(0.3)  # 0.6 >= 0.5 — атака
	_check(tgt.hp < 500.0, "после окончания стана герой снова атакует")
	s.add_stun(0.5)
	s.step(0.2)
	s.add_stun(0.5)
	_check(absf(s.stun_left - 0.5) < 0.001, "повторный стан обновляет таймер, а не складывается")
	s.free()
	tgt.free()

	# У голема и босса стан прописан, у босса сильнее; у слизня и волка стана нет
	_check(Enemies.STUN_CHANCE.has("golem") and Enemies.STUN_CHANCE.has("boss"), "стан накладывают голем и босс")
	_check(int(Enemies.TYPES["golem"]["hp"]) > 36 and int(Enemies.TYPES["golem"]["atk"]) > 5, "голем усилен (было 36 HP и 5 атаки, теперь %d HP и %d)" % [int(Enemies.TYPES["golem"]["hp"]), int(Enemies.TYPES["golem"]["atk"])])
	_check(Enemies.STUN_CHANCE["boss"] > Enemies.STUN_CHANCE["golem"], "у босса шанс стана выше")
	_check(Enemies.STUN_DURATION["boss"] > Enemies.STUN_DURATION["golem"], "у босса стан дольше")
	_check(not Enemies.STUN_CHANCE.has("slime") and not Enemies.STUN_CHANCE.has("wolf"), "слизень и волк стан не накладывают")

	# Эффекты сбрасываются при завершении фазы боя
	var h := Hero.new()
	var b := BattleScreen.new()
	b.hero = h
	b.wave = 1
	b._ready()
	b._hero_actor.add_poison()
	b._hero_actor.add_bleed()
	b._hero_actor.add_stun(0.5)
	var poisoned_hp: float = b._hero_actor.max_hp
	b._start_loot_phase()
	_check(b._state == "loot", "фаза боя завершилась (сундуки)")
	_check(b._hero_actor.poison_times.is_empty() and b._hero_actor.bleed_times.is_empty(), "отравление и кровотечение сброшены после боя")
	_check(b._hero_actor.stun_left == 0.0, "стан сброшен после боя")
	_check(b._hero_actor.max_hp > poisoned_hp, "характеристики восстановились после снятия отравления")
	_check(not b._hero_actor._badges["poison"].visible and not b._hero_actor._badges["bleed"].visible and not b._hero_actor._badges["stun"].visible, "все значки скрыты после боя")
	b.free()


func _test_enemy_tooltip() -> void:
	print("-- Подсказка при наведении на врага --")
	var h := Hero.new()
	var b := BattleScreen.new()
	b.hero = h
	b.wave = 9
	b._ready()

	var wolf_tip := b._enemy_tooltip("wolf", Enemies.scaled("wolf", 9))
	_check("Волк" in wolf_tip and "Здоровье" in wolf_tip and "Атака" in wolf_tip and "Защита" in wolf_tip, "подсказка содержит имя и характеристики врага")
	_check("Кровотечение" in wolf_tip, "подсказка волка упоминает кровотечение")
	_check("Отравление" in b._enemy_tooltip("slime", Enemies.scaled("slime", 1)), "подсказка слизня упоминает отравление")
	_check("Оглушение" in b._enemy_tooltip("golem", Enemies.scaled("golem", 9)), "подсказка голема упоминает оглушение")
	_check("Оглушение" in b._enemy_tooltip("boss", Enemies.scaled("boss", 20)), "подсказка босса упоминает оглушение")
	_check(Enemies.effect_desc("slime") != "" and Enemies.effect_desc("wolf") != "", "описания эффектов заданы у слизня и волка")

	# У врагов на поле есть зона наведения с заполненной подсказкой
	var ok := true
	for e in b._enemies:
		var found := false
		for c in e.get_children():
			if c is Control and c.tooltip_text != "":
				found = true
		if not found:
			ok = false
	_check(ok, "у каждого врага на поле есть подсказка при наведении")

	# После гибели врага его зоны наведения перестают принимать мышь —
	# иначе они перекрывают клики по сундуку, упавшему на место врага
	var e0: Actor = b._enemies[0]
	b._on_enemy_died(e0)
	var all_ignore := true
	for c in e0.get_children():
		if c is Control and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			all_ignore = false
	_check(all_ignore, "зона наведения мёртвого врага не перехватывает клики (сундук под ним доступен)")
	b.free()


func _test_summon_taunt() -> void:
	print("-- Умение босса: призыв и провокация --")
	_check(Enemies.SUMMON_INTERVAL > 0.0, "у призыва задан интервал")
	_check(Enemies.SUMMON_INTERVAL < 6.0, "босс призывает чаще, чем раньше (интервал %d с)" % roundi(Enemies.SUMMON_INTERVAL))
	_check(Enemies.SUMMON_VALUE > 0, "у призыва задан бюджет (ценность комбинации)")
	_check(int(Enemies.TYPES["boss"]["hp"]) > 110, "здоровье босса увеличено (было 110, теперь %d)" % int(Enemies.TYPES["boss"]["hp"]))
	_check("Призыв" in Enemies.ability_desc("boss"), "у босса описано умение призыва")
	_check(Enemies.ability_desc("slime") == "", "у обычных врагов умения нет")

	var h := Hero.new()
	var b := BattleScreen.new()
	b.hero = h
	b.wave = Enemies.TOTAL_WAVES
	b._ready()
	_check(b._enemies.size() == 1, "волна босса начинается с одного босса")
	# Героя делаем условно бессмертным: тест про призыв, а не про выживание
	b._hero_actor.max_hp = 100000.0
	b._hero_actor.hp = 100000.0
	var boss: Actor = b._enemies[0]
	_check(boss.cast_interval == Enemies.SUMMON_INTERVAL, "у босса задан интервал умения (прогресс-бар)")
	_check(not boss.taunt, "у самого босса провокации нет")

	# Прогресс-бар заполняется: по готовности босс призывает союзников —
	# случайную комбинацию на сумму бюджета призыва (последний может округлить вверх)
	boss.step(Enemies.SUMMON_INTERVAL + 0.1)
	var summons := []
	for e in b._enemies:
		if e != boss:
			summons.append(e)
	_check(summons.size() >= 1, "босс призвал союзников (%d)" % summons.size())
	var spent := 0
	for s in summons:
		spent += Enemies.VALUES[s.stats.get("type", "slime")]
	_check(spent >= Enemies.SUMMON_VALUE and spent < Enemies.SUMMON_VALUE + 4, "комбинация закрывает бюджет призыва (%d очков)" % spent)
	_check(b._enemy_total == 1 + summons.size(), "призванные считаются врагами волны")
	_check(boss.cast_timer < 1.0, "после призыва прогресс умения сброшен")

	var all_taunt := true
	for s in summons:
		if not s.taunt:
			all_taunt = false
	_check(all_taunt, "все призванные — с провокацией")
	_check(b._hero_actor.target != null and b._hero_actor.target.taunt, "герой переключился на призванных (провокация)")

	# В подсказке призванного указаны провокация и отсутствие наград
	var tip_found := false
	for c in summons[0].get_children():
		if c is Control and "Провокация" in c.tooltip_text and "не даёт опыта" in c.tooltip_text:
			tip_found = true
	_check(tip_found, "в подсказке призванного: провокация и отсутствие наград")

	# Призванные не дают ни опыта, ни сундуков
	var xp_before: int = h.xp
	var lvl_before: int = h.level
	var chests_before: int = b._chests.size()
	summons[0].alive = false
	b._on_enemy_died(summons[0])
	_check(h.xp == xp_before and h.level == lvl_before, "призванные не дают опыта")
	_check(b._chests.size() == chests_before, "призванные не оставляют сундуков")
	_check(not summons[0].visible, "труп призванного пропадает сразу")

	# Пока жив хоть один провоцирующий — герой не бьёт босса
	for i in range(1, summons.size()):
		if b._hero_actor.target != null:
			_check(b._hero_actor.target.taunt, "пока живы призванные — герой бьёт их")
		summons[i].alive = false
		b._on_enemy_died(summons[i])
	_check(b._hero_actor.target == boss, "когда призванные мертвы — герой снова бьёт босса")

	# Перезарядка призыва не идёт, пока живы призванные: таймер и прогресс-бар стоят
	# (все призванные из первой партии мертвы — перезарядка возобновилась)
	_check(not boss.cast_blocked, "без живых призванных перезарядка призыва идёт")
	boss.step(Enemies.SUMMON_INTERVAL + 0.1)  # новый призыв
	var wave2 := []
	for e in b._enemies:
		if e != boss and e.alive:
			wave2.append(e)
	_check(wave2.size() >= 1, "босс призвал новую партию (%d)" % wave2.size())
	_check(boss.cast_blocked, "пока живы призванные — перезарядка на паузе")
	var timer_frozen: float = boss.cast_timer
	boss.step(Enemies.SUMMON_INTERVAL + 0.1)
	_check(absf(boss.cast_timer - timer_frozen) < 0.001, "таймер призыва не идёт, пока живы призванные")
	var alive_blocked := 0
	for e in b._enemies:
		if e != boss and e.alive:
			alive_blocked += 1
	_check(alive_blocked == wave2.size(), "повторного призыва нет, пока жива предыдущая партия")

	# Все призванные погибли — перезарядка возобновляется, босс призывает снова
	for s in wave2:
		s.alive = false
		b._on_enemy_died(s)
	_check(not boss.cast_blocked, "после гибели призванных перезарядка возобновилась")
	boss.step(Enemies.SUMMON_INTERVAL + 0.1)
	var alive_resumed := 0
	for e in b._enemies:
		if e != boss and e.alive:
			alive_resumed += 1
	_check(alive_resumed >= 1, "после гибели предыдущих босс призывает снова")
	_check(alive_resumed <= Enemies.SUMMON_MAX_ACTIVE, "живых призванных не больше лимита %d" % Enemies.SUMMON_MAX_ACTIVE)
	b.free()


func _test_hero_abilities() -> void:
	print("-- Способности героев: Рёв и Смертельный удар --")
	# Кулдаун: база на 1 уровне, уменьшается с уровнем, ограничен минимумом
	var k := Hero.new("knight")
	_check(absf(k.ability_cooldown() - Hero.ABILITY_BASE_CD) < 0.001, "на 1 уровне — базовый кулдаун %.1f с" % Hero.ABILITY_BASE_CD)
	k.level = 5
	_check(k.ability_cooldown() < Hero.ABILITY_BASE_CD, "кулдаун уменьшается с уровнем героя")
	k.level = 100
	_check(absf(k.ability_cooldown() - Hero.ABILITY_MIN_CD["roar"]) < 0.001, "кулдаун Рёва ограничен минимумом %.1f с" % Hero.ABILITY_MIN_CD["roar"])
	var r_max := Hero.new("rogue")
	r_max.level = 100
	_check(absf(r_max.ability_cooldown() - Hero.ABILITY_MIN_CD["execute"]) < 0.001, "кулдаун Смертельного удара ограничен минимумом %.1f с" % Hero.ABILITY_MIN_CD["execute"])
	_check(Hero.ABILITY_MIN_CD["execute"] < Hero.ABILITY_MIN_CD["roar"], "минимальный кулдаун Вора ниже, чем у Рыцаря")
	_check(k.ability_name() == "Рёв", "способность Рыцаря — «Рёв»")
	var r := Hero.new("rogue")
	_check(r.ability_name() == "Смертельный удар", "способность Вора — «Смертельный удар»")
	_check("Перезарядка" in k.ability_tooltip() and "Перезарядка" in r.ability_tooltip(), "в подсказке способности указан кулдаун")

	# Рёв: срабатывает по кулдауну, сбрасывает атаку всех врагов, не трогает призыв босса
	var b := BattleScreen.new()
	b.hero = Hero.new("knight")
	b.wave = Enemies.TOTAL_WAVES
	b.rng_seed = 11
	b._ready()
	_check(b._ability_timer == 0.0 and b._ability_icon.fill == 0.0, "каждый новый бой кулдаун начинается с нуля")
	_check(b._ability_icon.tooltip_text != "", "у иконки способности есть подсказка")
	var boss: Actor = b._enemies[0]
	boss._atk_timer = 0.4
	boss.cast_timer = 3.0
	var cd: float = b.hero.ability_cooldown()
	b.step(cd + 0.1)
	_check(boss.stun_left > 0.0, "Рёв оглушил врага")
	_check(boss._atk_timer == 0.0, "Рёв сбросил таймер атаки врага")
	_check(absf(boss.cast_timer - 3.0) < 0.001, "Рёв не сбросил призыв босса")
	_check(b._ability_timer == 0.0 and b._ability_icon.fill == 0.0, "после Рёва перезарядка пошла заново")
	b.free()

	# Смертельный удар: заряд ждёт атаки, удваивает урон, перезарядка после удара
	var b2 := BattleScreen.new()
	b2.hero = Hero.new("rogue")
	b2.wave = 1
	b2.rng_seed = 12
	b2._ready()
	b2.step(cd + 0.1)
	_check(b2._ability_armed, "Смертельный удар зарядился")
	_check(b2._hero_actor.dmg_mult_next == Hero.EXECUTE_MULT, "следующий удар усилен ×%d" % int(Hero.EXECUTE_MULT))
	_check(b2._ability_icon.fill == 1.0, "иконка цветная, пока способность готова")
	b2.step(2.0)
	_check(b2._ability_armed and b2._ability_timer >= b2._ability_cd - 0.001, "пока заряд не потрачен — перезарядка не копится")
	var enemy: Actor = b2._enemies[0]
	enemy.def_pct = 0.0
	enemy.max_hp = 500.0  # цель условно живучая: тест про урон, а не про гибель
	enemy.hp = 500.0
	var atk: float = b2._hero_actor.stats["atk"]
	var hp0: float = enemy.hp
	b2._hero_actor.target = enemy
	b2._hero_actor._attack()
	_check(absf(enemy.hp - (hp0 - floorf(atk * Hero.EXECUTE_MULT))) < 0.01, "удар под способностью — двойной урон (%d)" % floori(atk * Hero.EXECUTE_MULT))
	_check(b2._hero_actor.dmg_mult_next == 1.0, "усиление потрачено ударом")
	_check(not b2._ability_armed and b2._ability_timer == 0.0 and b2._ability_icon.fill == 0.0, "перезарядка началась заново после атаки")
	var hp1: float = enemy.hp
	b2._hero_actor._attack()
	_check(absf(enemy.hp - (hp1 - floorf(atk))) < 0.01, "следующий удар — обычный урон")
	b2.free()


func _test_battle_layout() -> void:
	print("-- Раскладка боя: клики по сундукам, строй на поле --")
	# Экран боя не должен перехватывать клики мыши: полноразмерный Control
	# над полем боя не дал бы открывать сундуки (Area2D под ним)
	var b := BattleScreen.new()
	b.hero = Hero.new("knight")
	b.wave = 1
	b._ready()
	_check(b.mouse_filter == Control.MOUSE_FILTER_IGNORE, "экран боя не перехватывает мышь — сундуки кликаются")
	b.free()

	# Строй не уходит на задний фон: ноги врагов не выше верхней кромки поля
	# (вне дерева — окно по умолчанию 1280×720)
	var min_y := 720.0 * BattleScreen.Backdrop.FIELD_TOP + 20.0
	var rows_ok := true
	var clamped_seen := false
	var spacing_ok := true
	for s in range(1, 8):
		var bf := BattleScreen.new()
		bf.hero = Hero.new("knight")
		bf.wave = 19  # поздняя волна: много врагов, высокие строи
		bf.rng_seed = s
		bf._ready()
		for e in bf._enemies:
			if e.position.y < min_y - 0.01:
				rows_ok = false
			if absf(e.position.y - min_y) < 0.01:
				clamped_seen = true
		# Прижатие к полю — единый сдвиг строя: расстояния между врагами
		# не схлопываются, никто не стоит друг в друге (минимум в строях ~85 px)
		for i in bf._enemies.size():
			for j in range(i + 1, bf._enemies.size()):
				if bf._enemies[i].position.distance_to(bf._enemies[j].position) < 70.0:
					spacing_ok = false
		bf.free()
	_check(rows_ok, "ни один враг не стоит выше поля боя (7 зёрен на 19-й волне)")
	_check(clamped_seen, "прижатие к полю реально срабатывает (верхние ряды строя)")
	_check(spacing_ok, "враги не накладываются друг на друга (единый сдвиг строя)")


func _test_attack_jitter() -> void:
	print("-- Разброс темпа атаки врагов --")
	var tgt := Actor.new()
	tgt.setup("цель", {"hp": 100000, "atk": 1, "spd": 1.0}, Color.WHITE, "rect", 10.0, "hero")
	var e := Actor.new()
	e.setup("враг", {"hp": 50, "atk": 1, "spd": 1.0}, Color.WHITE, "rect", 10.0, "enemy")
	e.engaged = true
	e.target = tgt
	var rec := {"t": 0.0, "hits": []}
	e.attacked.connect(func(_s, _d): rec["hits"].append(rec["t"]))
	var dt := 0.01
	while rec["hits"].size() < 30:
		rec["t"] += dt
		e.step(dt)
	# Первый удар — в базовом темпе (1 уд/с), без разброса
	_check(absf(rec["hits"][0] - 1.0) < 0.02, "первый удар в базовом темпе")
	# Следующие удары выбирают скорость из разброса: интервалы различаются,
	# но не выходят за пределы ±ATK_JITTER
	var lo := 1.0 * (1.0 - Enemies.ATK_JITTER) - 0.02
	var hi := 1.0 * (1.0 + Enemies.ATK_JITTER) + 0.02
	var in_range := true
	var distinct := {}
	for i in range(1, rec["hits"].size()):
		var iv: float = rec["hits"][i] - rec["hits"][i - 1]
		if iv < lo or iv > hi:
			in_range = false
		distinct[roundi(iv * 100.0)] = true
	_check(in_range, "интервалы ударов в пределах ±%d%%" % roundi(Enemies.ATK_JITTER * 100.0))
	_check(distinct.size() >= 5, "темп атаки различается от удара к удару (%d вариантов)" % distinct.size())
	# Герой бьёт в стабильном темпе, без разброса
	var h2 := Actor.new()
	h2.setup("герой", {"hp": 50, "atk": 1, "spd": 1.0}, Color.WHITE, "rect", 10.0, "hero")
	h2.engaged = true
	h2.target = tgt
	var rec2 := {"t": 0.0, "hits": []}
	h2.attacked.connect(func(_s, _d): rec2["hits"].append(rec2["t"]))
	while rec2["hits"].size() < 10:
		rec2["t"] += dt
		h2.step(dt)
	var stable := true
	for i in range(1, rec2["hits"].size()):
		var iv2: float = rec2["hits"][i] - rec2["hits"][i - 1]
		if absf(iv2 - 1.0) > 0.02:
			stable = false
	_check(stable, "герой атакует в стабильном темпе")
	e.free()
	h2.free()
	tgt.free()


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
	b.rng_seed = 303  # воспроизводимая симуляция
	seed(303)
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


func _run_battle(h: Hero, wave: int, battle_seed := -1) -> BattleScreen:
	var b := BattleScreen.new()
	b.hero = h
	b.wave = wave
	b.rng_seed = battle_seed
	if battle_seed >= 0:
		seed(battle_seed)  # глобальный ГСЧ (разброс темпа атаки врагов)
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

	# Сильный герой должен стабильно побеждать босса (с учётом его призыва):
	# 5 воспроизводимых прогонов с разными зернами, минимум 4 победы.
	# Сборка — разумная, а не «всё в две характеристики»: после капов наивный
	# стакинг проигрывает боссу всегда (замер scratch-симуляцией, 0/10),
	# равномерная прокачка со смешанным шмотом побеждает (10/10).
	var wins := 0
	for s in 5:
		var strong := Hero.new()
		strong.add_xp(900)
		var order := ["surv", "atk", "def", "spd"]
		var i := 0
		while strong.stat_points > 0:
			strong.allocate(order[i % 4])
			i += 1
		for slot in ["weapon", "shield", "helmet", "armor", "boots", "amulet", "ring1", "ring2"]:
			var it := Item.new()
			it.name = "Легенда"
			it.slot = slot
			it.rarity = 4
			it.bonuses = {"atk": 5, "spd": 3, "def": 4, "surv": 5}
			strong.inventory.append(it)
			strong.equip(it)
		var b := _run_battle(strong, Enemies.TOTAL_WAVES, 101 + s)
		if b._state == "done" and b._hero_actor.alive and b._boss_dead:
			wins += 1
			if wins == 1:
				_check(b._chests.is_empty(), "победа над боссом — сразу, без фазы сундуков")
		b.free()
	_check(wins >= 4, "прокачанный герой победил босса в %d из 5 прогонов" % wins)

	# Голый герой 1 уровня должен проиграть (и игра это корректно обрабатывает)
	var weak := Hero.new()
	var b2 := _run_battle(weak, Enemies.TOTAL_WAVES, 202)
	_check(b2._state == "done", "бой слабого героя завершился")
	_check(not b2._hero_actor.alive, "слабый герой пал — путь поражения работает")
	b2.free()
