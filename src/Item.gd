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
const SLOT_NAMES := {"weapon": "Оружие", "shield": "Щит", "armor": "Броня", "amulet": "Амулет", "ring": "Кольцо", "helmet": "Шлем", "boots": "Сапоги"}
const STAT_NAMES := {"atk": "Сила", "spd": "Ловкость", "def": "Защита", "surv": "Выносливость", "dodge": "Шанс уворота", "block": "Шанс блока"}
const STAT_ORDER := ["atk", "spd", "def", "surv", "dodge", "block"]

# Множитель силы бонусов по редкости; применяется только к плюсам,
# штрафы (минусы) с редкостью не растут (временные значения, уточнить по игротестам)
const RARITY_MULT := [1.0, 1.3, 1.6, 2.0, 2.5, 3.2]

## Нарисованные иконки предметов (пайплайн — docs/art-style.md).
## Ключ — имя шаблона; если иконки нет, интерфейс рисует примитив слота.
## ВАЖНО: только preload, не load() в icon_texture(). Текстура, впервые
## загруженная через load() внутри _draw() (в фазе отрисовки), не успевает
## попасть на видеокарту и рисуется белым квадратом. preload грузит
## текстуры при загрузке скрипта — задолго до первой отрисовки.
const ICON_TEXTURES := {
	"Ржавый меч": preload("res://assets/icons/items/sword_rusty.png"),
	"Топор лесника": preload("res://assets/icons/items/axe_forester.png"),
	"Кинжал странника": preload("res://assets/icons/items/dagger_wanderer.png"),
	"Молот кузнеца": preload("res://assets/icons/items/hammer_blacksmith.png"),
	"Кинжал акробата": preload("res://assets/icons/items/dagger_acrobat.png"),
}

# Базовые веса редкостей на 1-й волне (временные значения)
const RARITY_BASE_WEIGHTS := [70.0, 20.0, 7.0, 2.2, 0.7, 0.1]
# Сдвиг весов к старшим редкостям за каждую волну после первой
const RARITY_WAVE_SHIFT := 0.03
# Дополнительный сдвиг для финального сундука волны
const RARITY_RICH_SHIFT := 0.5

# Шаблоны предметов: имя, слот, базовые бонусы (для обычной редкости).
# Бонусы — сырые очки (ловкость и выносливость тоже в очках, не в готовых
# значениях); уворот/блок — прямые проценты шанса.
# Поле "class" — классовый предмет: выпадает только герою этого класса.
# Правила пула (временные, уточнить по игротестам):
# - большинство предметов имеет негативную сторону: сумма плюсов чуть
#   больше, но за неё платят минусом;
# - предметы без минусов чуть слабее по сумме очков — сила сопоставима;
# - штрафы не растут с редкостью (на RARITY_MULT множатся только плюсы);
# - внутри одного слота суммы плюсов различаются не больше чем на 2 очка
#   и ни один предмет не хуже другого по всем характеристикам сразу.
const TEMPLATES := [
	{"name": "Ржавый меч", "slot": "weapon", "bonuses": {"atk": 4}},
	{"name": "Топор лесника", "slot": "weapon", "bonuses": {"atk": 4, "surv": 2, "spd": -1}},
	{"name": "Кинжал странника", "slot": "weapon", "bonuses": {"atk": 2, "spd": 3, "surv": -1}},
	{"name": "Молот кузнеца", "slot": "weapon", "bonuses": {"atk": 6, "spd": -2}},
	{"name": "Кинжал акробата", "slot": "weapon", "bonuses": {"atk": 3, "dodge": 3, "def": -1}, "class": "rogue"},
	{"name": "Щит ополченца", "slot": "shield", "bonuses": {"def": 2, "surv": 2}, "class": "knight"},
	{"name": "Башенный щит", "slot": "shield", "bonuses": {"def": 5, "spd": -2}, "class": "knight"},
	{"name": "Щит бастиона", "slot": "shield", "bonuses": {"def": 2, "block": 3, "atk": -1}, "class": "knight"},
	{"name": "Кожаный шлем", "slot": "helmet", "bonuses": {"def": 1, "surv": 2}},
	{"name": "Железный шлем", "slot": "helmet", "bonuses": {"def": 4, "spd": -1}},
	{"name": "Шлем стражника", "slot": "helmet", "bonuses": {"def": 1, "block": 2}, "class": "knight"},
	{"name": "Капюшон тени", "slot": "helmet", "bonuses": {"spd": 1, "dodge": 2}, "class": "rogue"},
	{"name": "Кожаная куртка", "slot": "armor", "bonuses": {"def": 2, "surv": 2}},
	{"name": "Кольчуга", "slot": "armor", "bonuses": {"def": 4, "spd": -1}},
	{"name": "Плащ тени", "slot": "armor", "bonuses": {"def": 2, "spd": 3, "surv": -1}},
	{"name": "Плащ ускользания", "slot": "armor", "bonuses": {"def": 1, "dodge": 3}, "class": "rogue"},
	{"name": "Старые сапоги", "slot": "boots", "bonuses": {"spd": 2, "surv": 1}},
	{"name": "Сапоги следопыта", "slot": "boots", "bonuses": {"spd": 4, "def": -1}},
	{"name": "Сапоги бастиона", "slot": "boots", "bonuses": {"surv": 2, "block": 2, "spd": -1}, "class": "knight"},
	{"name": "Сапоги акробата", "slot": "boots", "bonuses": {"spd": 1, "dodge": 2}, "class": "rogue"},
	{"name": "Каменный оберег", "slot": "amulet", "bonuses": {"surv": 4, "spd": -1}},
	{"name": "Оберег волка", "slot": "amulet", "bonuses": {"atk": 2, "spd": 2, "def": -1}},
	{"name": "Солнечный медальон", "slot": "amulet", "bonuses": {"surv": 2, "def": 1}},
	{"name": "Перо ветра", "slot": "amulet", "bonuses": {"spd": 4, "surv": -1}},
	{"name": "Кольцо жизни", "slot": "ring", "bonuses": {"surv": 3}},
	{"name": "Кольцо клинка", "slot": "ring", "bonuses": {"atk": 3, "surv": -1}},
	{"name": "Кольцо прилива", "slot": "ring", "bonuses": {"surv": 2, "spd": 1, "def": -1}},
	{"name": "Кольцо стража", "slot": "ring", "bonuses": {"block": 3, "atk": -1}, "class": "knight"},
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
## hero_kind — класс героя: классовые предметы (поле "class" в шаблоне)
## выпадают только своему классу (щиты — только Рыцарю).
static func generate(rng: RandomNumberGenerator = null, rarity: int = -1, wave: int = 1, exclude_names: Array = [], rich: bool = false, hero_kind: String = "") -> Item:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if rarity < 0:
		rarity = roll_rarity(rng, wave, rich)
	var candidates := []
	for t in TEMPLATES:
		if exclude_names.has(t["name"]):
			continue
		if t.get("class", "") != "" and t["class"] != hero_kind:
			continue
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
		var base: float = t["bonuses"][k]
		if base > 0:
			it.bonuses[k] = maxi(1, roundi(base * mult))
		else:
			# Штрафы не растут с редкостью: чем выше редкость, тем выгоднее предмет
			it.bonuses[k] = int(base)
	return it


func rarity_name() -> String:
	return RARITY_NAMES[rarity]


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


func slot_name() -> String:
	return SLOT_NAMES.get(slot, slot)


## Текстура нарисованной иконки предмета или null, если её нет
## (тогда интерфейс рисует примитив слота — GearScreen.draw_slot_icon).
func icon_texture() -> Texture2D:
	var tex: Texture2D = ICON_TEXTURES.get(name, null)
	return tex


## Текст вида "Сила +3, Шанс уворота +2%" (бонусы — целые числа;
## уворот/блок — прямые проценты, остальные — сырые очки)
func bonuses_text() -> String:
	var parts := []
	for k in STAT_ORDER:
		if bonuses.has(k):
			if k == "dodge" or k == "block":
				parts.append("%s %+d%%" % [STAT_NAMES[k], int(bonuses[k])])
			else:
				parts.append("%s %+d" % [STAT_NAMES[k], int(bonuses[k])])
	return ", ".join(parts)
