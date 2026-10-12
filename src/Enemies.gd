class_name Enemies
extends RefCounted

## Описания врагов, состав волн и масштабирование сложности.
## Всё статическое — состояния тут нет.

const TOTAL_WAVES := 20  # 20-я волна — босс

const TYPES := {
	"slime": {
		"name": "Слизень", "hp": 12, "atk": 3, "def": 0, "spd": 0.8, "xp": 3,
		"color": Color(0.4, 0.85, 0.45), "shape": "circle", "size": 26.0, "move": 60.0,
	},
	"wolf": {
		"name": "Волк", "hp": 18, "atk": 4, "def": 1, "spd": 1.3, "xp": 5,
		"color": Color(0.55, 0.55, 0.62), "shape": "triangle", "size": 30.0, "move": 115.0,
	},
	"golem": {
		"name": "Голем", "hp": 36, "atk": 5, "def": 3, "spd": 0.5, "xp": 8,
		"color": Color(0.6, 0.45, 0.3), "shape": "rect", "size": 42.0, "move": 40.0,
	},
	"boss": {
		"name": "Каменный страж", "hp": 110, "atk": 7, "def": 4, "spd": 0.7, "xp": 40,
		"color": Color(0.82, 0.28, 0.28), "shape": "rect", "size": 62.0, "move": 45.0,
	},
}


## Максимум врагов в одной волне (босс — всегда один).
const MAX_ENEMIES := 5


## Веса типов в волне: чем дальше, тем чаще встречаются сильные враги.
## Слизень постепенно сходит на нет, волк и голем набирают вес.
static func type_weights(wave: int) -> Dictionary:
	return {
		"slime": maxf(1.0, 7.0 - wave),
		"wolf": clampf(float(wave - 1), 0.0, 4.0),
		"golem": clampf(float(wave - 3), 0.0, 4.0),
	}


## Состав волны: массив ключей типов, не больше MAX_ENEMIES. Последняя волна — только босс.
static func wave_composition(wave: int, rng: RandomNumberGenerator = null) -> Array:
	if wave >= TOTAL_WAVES:
		return ["boss"]
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var weights := type_weights(wave)
	var total := 0.0
	for k in weights:
		total += weights[k]
	var list := []
	# Размер волны растёт медленно: +1 враг каждые две волны (волна 1 — 2 врага)
	var n: int = mini(2 + wave / 2, MAX_ENEMIES)
	for i in n:
		var r := rng.randf() * total
		var acc := 0.0
		for k in weights:
			acc += weights[k]
			if r <= acc:
				list.append(k)
				break
	return list


## Характеристики врага с учётом волны. Рост +6% за волну (замедлено:
## прогрессия героя стала медленнее — 1 очко за уровень).
static func scaled(type: String, wave: int) -> Dictionary:
	var base: Dictionary = TYPES[type].duplicate()
	var f := 1.0 + 0.06 * (wave - 1)
	base["hp"] = maxi(1, roundi(base["hp"] * f))
	base["atk"] = maxi(1, roundi(base["atk"] * f))
	base["def"] = roundi(base["def"] * (1.0 + 0.06 * (wave - 1)))
	base["xp"] = maxi(1, roundi(base["xp"] * (1.0 + 0.06 * (wave - 1))))
	base["type"] = type
	return base


## Сундуки: 1 гарантированный в конце волны + небольшой шанс с каждого врага.
const BASE_CHESTS := 1
const CHEST_DROP_CHANCE := 0.15
## Сколько предметов на выбор предлагает сундук.
const CHEST_CHOICES := 3
