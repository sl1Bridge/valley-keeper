class_name Item
extends RefCounted

## Предмет экипировки. Всё данные, без визуала.
## Редкость: 0 — обычный, 1 — редкий, 2 — эпический.

const RARITY_NAMES := ["Обычный", "Редкий", "Эпический"]
const RARITY_COLORS := [
	Color(0.78, 0.78, 0.78),  # обычный — серый
	Color(0.35, 0.6, 1.0),    # редкий — синий
	Color(0.8, 0.4, 1.0),     # эпический — фиолетовый
]
const SLOT_NAMES := {"weapon": "Оружие", "armor": "Броня", "amulet": "Амулет", "ring": "Кольцо"}
const STAT_NAMES := {"hp": "Здоровье", "atk": "Сила атаки", "def": "Защита", "spd": "Скорость атаки", "regen": "Регенерация"}
const STAT_ORDER := ["hp", "atk", "def", "spd", "regen"]

# Множитель силы бонусов по редкости
const RARITY_MULT := [1.0, 1.6, 2.4]

# Шаблоны предметов (~11 штук по ТЗ): имя, слот, базовые бонусы (для обычной редкости)
const TEMPLATES := [
	{"name": "Ржавый меч", "slot": "weapon", "bonuses": {"atk": 3}},
	{"name": "Топор лесника", "slot": "weapon", "bonuses": {"atk": 2, "hp": 4}},
	{"name": "Кинжал странника", "slot": "weapon", "bonuses": {"atk": 2, "spd": 0.15}},
	{"name": "Молот кузнеца", "slot": "weapon", "bonuses": {"atk": 4, "spd": -0.1}},
	{"name": "Кожаная куртка", "slot": "armor", "bonuses": {"def": 1, "hp": 4}},
	{"name": "Кольчуга", "slot": "armor", "bonuses": {"def": 2}},
	{"name": "Плащ тени", "slot": "armor", "bonuses": {"def": 1, "spd": 0.1}},
	{"name": "Каменный оберег", "slot": "amulet", "bonuses": {"hp": 5, "regen": 0.3}},
	{"name": "Оберег волка", "slot": "amulet", "bonuses": {"atk": 1, "spd": 0.1}},
	{"name": "Солнечный медальон", "slot": "amulet", "bonuses": {"hp": 5, "def": 1}},
	{"name": "Перо ветра", "slot": "amulet", "bonuses": {"spd": 0.2}},
	{"name": "Кольцо жизни", "slot": "ring", "bonuses": {"hp": 6, "regen": 0.3}},
	{"name": "Кольцо клинка", "slot": "ring", "bonuses": {"atk": 2}},
	{"name": "Кольцо прилива", "slot": "ring", "bonuses": {"regen": 0.4}},
]

static var _next_id := 1

var id: int
var name: String
var slot: String
var rarity: int
var bonuses: Dictionary


## Бросок редкости. Из сундука шансы лучше.
static func roll_rarity(rng: RandomNumberGenerator, from_chest: bool) -> int:
	var r := rng.randf()
	if from_chest:
		if r < 0.5:
			return 0
		return 1 if r < 0.85 else 2
	else:
		if r < 0.7:
			return 0
		return 1 if r < 0.95 else 2


## Генерация случайного предмета. rarity = -1 — бросить жребий.
## exclude_names — шаблоны с такими именами не выпадут (для сундука «3 на выбор»).
static func generate(rng: RandomNumberGenerator = null, rarity: int = -1, from_chest: bool = false, exclude_names: Array = []) -> Item:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if rarity < 0:
		rarity = roll_rarity(rng, from_chest)
	var candidates := []
	for t in TEMPLATES:
		if not exclude_names.has(t["name"]):
			candidates.append(t)
	var t: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var mult: float = RARITY_MULT[rarity]
	var it := Item.new()
	it.id = _next_id
	_next_id += 1
	it.name = t["name"]
	it.slot = t["slot"]
	it.rarity = rarity
	it.bonuses = {}
	for k in t["bonuses"]:
		var v: float = t["bonuses"][k] * mult
		if k == "spd" or k == "regen":
			v = snappedf(v, 0.05)
			if is_zero_approx(v):
				v = 0.05 * signf(t["bonuses"][k])
		else:
			v = maxi(1, roundi(v)) if t["bonuses"][k] > 0 else mini(-1, roundi(v))
		it.bonuses[k] = v
	return it


func rarity_name() -> String:
	return RARITY_NAMES[rarity]


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


func slot_name() -> String:
	return SLOT_NAMES.get(slot, slot)


## Текст вида "Сила атаки +3, Регенерация +0.30"
func bonuses_text() -> String:
	var parts := []
	for k in STAT_ORDER:
		if bonuses.has(k):
			var v: float = bonuses[k]
			var txt := ("%+.2f" % v) if k == "spd" or k == "regen" else ("%+d" % int(v))
			parts.append("%s %s" % [STAT_NAMES[k], txt])
	return ", ".join(parts)
