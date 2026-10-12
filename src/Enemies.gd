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
const MAX_ENEMIES := 6

## Цена каждого типа в бюджете волны (временные значения, уточнить по игротестам).
const VALUES := {"slime": 1, "wolf": 2, "golem": 4}

## С какой волны тип допускается в волну: допуск, а не гарантия появления.
const MIN_WAVE := {"slime": 1, "wolf": 3, "golem": 9}


## Бюджет волны: стартует с 2 и растёт примерно на 0.8 за волну (временное значение).
static func wave_value(wave: int) -> int:
	return roundi(2.0 + (wave - 1) * 0.8)


## Состав волны: случайная комбинация врагов на сумму бюджета волны
## (если ровно не набирается — округление вверх), не больше MAX_ENEMIES.
## Последняя волна — только босс.
static func wave_composition(wave: int, rng: RandomNumberGenerator = null) -> Array:
	if wave >= TOTAL_WAVES:
		return ["boss"]
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var budget := wave_value(wave)
	# Типы, допущенные на этой волне, и самая высокая цена среди них
	var eligible: Array = []
	var max_value := 1
	for t in VALUES:
		if wave >= MIN_WAVE[t]:
			eligible.append(t)
			max_value = maxi(max_value, VALUES[t])
	var list: Array = []
	var spent := 0
	while spent < budget and list.size() < MAX_ENEMIES:
		var remaining: int = budget - spent
		var slots_left: int = MAX_ENEMIES - list.size()
		var options: Array = []
		if slots_left == 1:
			# Последний слот: добираем до бюджета, при необходимости округляя вверх.
			for t in eligible:
				if VALUES[t] >= remaining:
					options.append(t)
			if options.is_empty():
				# Даже самый дорогой тип не дотягивает — берём его, так ближе всего.
				for t in eligible:
					if VALUES[t] == max_value:
						options.append(t)
		else:
			# Обычный слот: случайный тип, который влезает в остаток бюджета
			# и не делает его недостижимым для оставшихся слотов.
			for t in eligible:
				if VALUES[t] <= remaining and remaining - VALUES[t] <= (slots_left - 1) * max_value:
					options.append(t)
		var pick: String = options[rng.randi() % options.size()]
		list.append(pick)
		spent += VALUES[pick]
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
## Шанс слизня наложить отравление при атаке (временное значение).
const POISON_CHANCE := 0.15
