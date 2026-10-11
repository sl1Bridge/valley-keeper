class_name Enemies
extends RefCounted

## Описания врагов, состав волн и масштабирование сложности.
## Всё статическое — состояния тут нет.

const TOTAL_WAVES := 10  # 10-я волна — босс

const TYPES := {
	"slime": {
		"name": "Слизень", "hp": 12, "atk": 3, "def": 0, "spd": 0.8, "xp": 3,
		"color": Color(0.4, 0.85, 0.45), "shape": "circle", "size": 26.0, "move": 60.0,
	},
	"wolf": {
		"name": "Волк", "hp": 18, "atk": 5, "def": 1, "spd": 1.3, "xp": 5,
		"color": Color(0.55, 0.55, 0.62), "shape": "triangle", "size": 30.0, "move": 115.0,
	},
	"golem": {
		"name": "Голем", "hp": 36, "atk": 6, "def": 3, "spd": 0.5, "xp": 8,
		"color": Color(0.6, 0.45, 0.3), "shape": "rect", "size": 42.0, "move": 40.0,
	},
	"boss": {
		"name": "Каменный страж", "hp": 110, "atk": 8, "def": 4, "spd": 0.7, "xp": 40,
		"color": Color(0.82, 0.28, 0.28), "shape": "rect", "size": 62.0, "move": 45.0,
	},
}


## Состав волны: массив ключей типов. 10-я волна — только босс.
static func wave_composition(wave: int) -> Array:
	if wave >= TOTAL_WAVES:
		return ["boss"]
	var list := []
	var n := 2 + wave
	for i in n:
		if wave >= 5 and i % 4 == 3:
			list.append("golem")
		elif wave >= 3 and i % 2 == 1:
			list.append("wolf")
		else:
			list.append("slime")
	return list


## Характеристики врага с учётом волны и числа побед над боссом (новый заход сложнее).
static func scaled(type: String, wave: int, wins: int) -> Dictionary:
	var base: Dictionary = TYPES[type].duplicate()
	var f := 1.0 + 0.15 * (wave - 1) + 0.3 * wins
	base["hp"] = maxi(1, roundi(base["hp"] * f))
	base["atk"] = maxi(1, roundi(base["atk"] * f))
	base["def"] = roundi(base["def"] * (1.0 + 0.1 * (wave - 1)))
	base["xp"] = maxi(1, roundi(base["xp"] * (1.0 + 0.1 * (wave - 1))))
	base["type"] = type
	return base


## Число сундуков на волне.
static func chest_count(wave: int) -> int:
	if wave >= TOTAL_WAVES:
		return 1
	return 2 if wave % 3 == 0 else 1
