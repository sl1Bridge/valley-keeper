class_name Hero
extends RefCounted

## Данные героя: характеристики, уровень, опыт, экипировка, рюкзак.
## Никакой визуальной логики — только числа и правила.

const STAT_ORDER := ["hp", "atk", "def", "spd", "regen"]

# Базовые характеристики героя 1 уровня
const BASE := {"hp": 30, "atk": 5, "def": 1, "spd": 1.0, "regen": 0.0}
# Прирост за 1 очко характеристики (регенерация — HP в секунду)
const PER_POINT := {"hp": 8, "atk": 2, "def": 1, "spd": 0.15, "regen": 0.4}
# Очков характеристик за уровень
const POINTS_PER_LEVEL := 2
# Фиксированное восстановление здоровья за передышку между волнами
const REST_HEAL := 25.0
# Доля максимального здоровья, восстанавливаемая при повышении уровня в бою
# (временное значение, уточнить по игротестам)
const LEVEL_UP_HEAL := 0.3

var level := 1
var xp := 0
var stat_points := 0
var allocated := {"hp": 0, "atk": 0, "def": 0, "spd": 0, "regen": 0}
# Два слота под кольца: ring1 и ring2
var equipment := {"weapon": null, "armor": null, "amulet": null, "ring1": null, "ring2": null}
var inventory := []  # массив Item
# Текущее здоровье между волнами; < 0 — полное
var current_hp := -1.0


## Итоговые характеристики: база + вложенные очки + бонусы предметов.
func get_stats() -> Dictionary:
	var s := {}
	for k in STAT_ORDER:
		s[k] = float(BASE[k]) + float(PER_POINT[k]) * allocated[k]
	for slot in equipment:
		var it: Item = equipment[slot]
		if it != null:
			for k in it.bonuses:
				s[k] = s.get(k, 0.0) + it.bonuses[k]
	s["spd"] = maxf(0.3, snappedf(s["spd"], 0.01))
	s["hp"] = maxf(1.0, s["hp"])
	return s


## Сколько опыта нужно для следующего уровня.
func xp_to_next() -> int:
	return 10 + (level - 1) * 8


## Добавить опыт. Возвращает число полученных уровней.
func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		stat_points += POINTS_PER_LEVEL
		gained += 1
	return gained


## Вложить очко в характеристику. true — получилось.
func allocate(stat: String) -> bool:
	if stat_points <= 0 or not allocated.has(stat):
		return false
	stat_points -= 1
	allocated[stat] += 1
	return true


## Максимальное здоровье по текущим характеристикам.
func max_hp() -> float:
	return get_stats()["hp"]


## Здоровье, с которым герой входит в бой.
func start_hp() -> float:
	if current_hp < 0.0 or current_hp > max_hp():
		current_hp = max_hp()
	return current_hp


## Передышка между волнами: фиксированное восстановление (не полное).
func apply_rest() -> void:
	if current_hp < 0.0:
		current_hp = max_hp()
	else:
		current_hp = minf(max_hp(), current_hp + REST_HEAL)


## Полное восстановление (после смерти или победы над боссом).
func full_restore() -> void:
	current_hp = -1.0


## Надеть предмет из рюкзака. Кольца занимают ring1/ring2: сперва свободный
## слот, если оба заняты — заменяет ring1. Возвращает снятый предмет (или null).
func equip(item: Item) -> Item:
	var slot: String = item.slot
	if slot == "ring":
		if equipment["ring1"] == null:
			slot = "ring1"
		elif equipment["ring2"] == null:
			slot = "ring2"
		else:
			slot = "ring1"
	var old: Item = equipment[slot]
	equipment[slot] = item
	inventory.erase(item)
	if old != null:
		inventory.append(old)
	return old


## Снять предмет из слота в рюкзак.
func unequip(slot: String) -> void:
	var it: Item = equipment[slot]
	if it != null:
		equipment[slot] = null
		inventory.append(it)
