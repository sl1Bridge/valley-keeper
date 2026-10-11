class_name Hero
extends RefCounted

## Данные героя: характеристики, уровень, опыт, экипировка, рюкзак.
## Никакой визуальной логики — только числа и правила.

const STAT_ORDER := ["hp", "atk", "def", "spd"]

# Базовые характеристики героя 1 уровня
const BASE := {"hp": 30, "atk": 5, "def": 1, "spd": 1.0}
# Прирост за 1 очко характеристики
const PER_POINT := {"hp": 8, "atk": 2, "def": 1, "spd": 0.15}
# Очков характеристик за уровень
const POINTS_PER_LEVEL := 2

var level := 1
var xp := 0
var stat_points := 0
var allocated := {"hp": 0, "atk": 0, "def": 0, "spd": 0}
var equipment := {"weapon": null, "armor": null, "amulet": null}
var inventory := []  # массив Item


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


## Надеть предмет из рюкзака. Возвращает предмет, который был в слоте (или null).
func equip(item: Item) -> Item:
	var old: Item = equipment[item.slot]
	equipment[item.slot] = item
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
