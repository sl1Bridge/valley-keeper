class_name Item
extends RefCounted

## Предмет экипировки. Всё данные, без визуала.
## Редкость: 0 — Обычный, 1 — Необычный, 2 — Редкий, 3 — Мистический,
## 4 — Легендарный, 5 — Артефакт.

const RARITY_NAMES := ["Обычный", "Необычный", "Редкий", "Мистический", "Легендарный", "Артефакт"]
const RARITY_COLORS := [
	Color(0.78, 0.78, 0.78),  # обычный — серый
	Color(0.35, 0.85, 0.4),   # необычный — зелёный
	Color(0.35, 0.6, 1.0),    # редкий — синий
	Color(0.8, 0.4, 1.0),     # мистический — фиолетовый
	Color(0.95, 0.8, 0.3),    # легендарный — золотой
	Color(0.9, 0.3, 0.25),    # артефакт — красный
]
const SLOT_NAMES := {"weapon": "Оружие", "armor": "Броня", "amulet": "Амулет", "ring": "Кольцо"}
const STAT_NAMES := {"hp": "Здоровье", "atk": "Сила атаки", "def": "Защита", "spd": "Скорость атаки", "regen": "Регенерация"}
const STAT_ORDER := ["hp", "atk", "def", "spd", "regen"]

# Множитель силы бонусов по редкости (временные значения, уточнить по игротестам)
const RARITY_MULT := [1.0, 1.3, 1.6, 2.0, 2.5, 3.2]

# Базовые веса редкостей на 1-й волне (временные значения)
const RARITY_BASE_WEIGHTS := [70.0, 20.0, 7.0, 2.2, 0.7, 0.1]
# Сдвиг весов к старшим редкостям за каждую волну после первой
const RARITY_WAVE_SHIFT := 0.09
# Дополнительный сдвиг для финального сундука волны
const RARITY_RICH_SHIFT := 0.8

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


## Веса редкостей для волны. Чем выше волна, тем больше вес старших редкостей;
## финальный сундук волны (rich) даёт дополнительный сдвиг.
static func rarity_weights(wave: int, rich: bool = false) -> Array:
	var shift: float = (wave - 1) * RARITY_WAVE_SHIFT + (RARITY_RICH_SHIFT if rich else 0.0)
	var w := []
	for t in RARITY_BASE_WEIGHTS.size():
		w.append(RARITY_BASE_WEIGHTS[t] * pow(1.0 + shift, t))
	return w


## Бросок редкости по весам волны.
static func roll_rarity(rng: RandomNumberGenerator, wave: int = 1, rich: bool = false) -> int:
	var w := rarity_weights(wave, rich)
	var total := 0.0
	for x in w:
		total += x
	var r := rng.randf() * total
	var acc := 0.0
	for t in w.size():
		acc += w[t]
		if r <= acc:
			return t
	return w.size() - 1


## Генерация случайного предмета. rarity = -1 — бросить жребий по весам волны.
## exclude_names — шаблоны с такими именами не выпадут (для сундука «3 на выбор»).
## rich — финальный сундук волны: шансы редкости выше.
static func generate(rng: RandomNumberGenerator = null, rarity: int = -1, wave: int = 1, exclude_names: Array = [], rich: bool = false) -> Item:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if rarity < 0:
		rarity = roll_rarity(rng, wave, rich)
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
