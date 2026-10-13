class_name Hero
extends RefCounted

## Данные героя: характеристики, уровень, опыт, экипировка, рюкзак, прогресс забега.
## Никакой визуальной логики — только числа и правила.

## Базовые характеристики (качаются очками за уровень):
## Сила (урон), Ловкость (темп атаки), Защита (%), Выносливость (здоровье и регенерация).
## Здоровье и регенерация — не отдельные характеристики: обе выводятся
## из Выносливости по формуле затухания (Hero.effective).
const STAT_ORDER := ["atk", "spd", "def", "surv"]

## Классовая характеристика: есть только у своего класса.
## Очками за уровень не качается. Значение — прямой процент шанса:
## базовый шанс класса + проценты с предметов (предел — CLASS_CAP).
const CLASS_STAT := {"knight": "block", "rogue": "dodge"}

## Реестр героев (классы). Рыцарь — защитный: слот под щит, больше защитных
## характеристик и базовый шанс блока. Вор — боевой: два слота под оружие,
## больше атакующих характеристик и базовый шанс уворота.
## Имена, описания и внешность временные.
const KINDS := ["knight", "rogue"]
const ROSTER := {
	"knight": {
		"name": "Рыцарь",
		"color": Color(0.25, 0.45, 0.9),
		"shape": "rect",
		"desc": "Надёжный защитник долины. Носит щит, крепче и умеет блокировать вражеские атаки.",
	},
	"rogue": {
		"name": "Вор",
		"color": Color(0.5, 0.32, 0.62),
		"shape": "triangle",
		"desc": "Быстрый и смертоносный. Бьёт сильнее и чаще, сражается двумя клинками и уклоняется от атак.",
	},
}

## Слоты экипировки по классам.
const CLASS_SLOTS := {
	"knight": ["weapon", "shield", "helmet", "armor", "boots", "amulet", "ring1", "ring2"],
	"rogue": ["weapon1", "weapon2", "helmet", "armor", "boots", "amulet", "ring1", "ring2"],
}

# Базовые характеристики героя 1 уровня по классам (сырые очки, временные
# значения): Рыцарь — защитный уклон, Вор — атакующий
const BASE := {
	"knight": {"atk": 4, "def": 7, "spd": 5.0, "surv": 6.0},
	"rogue": {"atk": 7, "def": 4, "spd": 6.0, "surv": 5.0},
}
# Базовый шанс классовой характеристики, в процентах (временное значение)
const BASE_CLASS_PCT := {"knight": 5.0, "rogue": 5.0}
# Прирост за 1 очко характеристики
const PER_POINT := {"atk": 2, "def": 1, "spd": 1.0, "surv": 2.0}
# Очков характеристик за уровень
const POINTS_PER_LEVEL := 1

## Формула затухания: cap × raw² / (raw² + K²) — плавная S-образная кривая:
## на низких значениях эффект слабый, ближе к K — быстрый рост, дальше — мягкий
## выход на предел (затухание на высоких значениях слабее, чем у raw/(raw+K)).
## Константы подобраны так, чтобы при базе 5 эффект был равноценен прежнему
## старту; все значения временные, уточнить по игротестам.
const DEF_K := 19.0    # защита: доля снижения урона (асимптота 100%); 5 → ~6%, 15 → ~38%
const SPD_CAP := 2.0   # ловкость: до +200% к темпу атаки (максимум 3 уд/с)
const SPD_K := 22.0    # 5 → ~1.10 уд/с, 10 → ~1.34 уд/с
const SURV_HP_CAP := 140.0  # выносливость → макс. здоровье: до 140 HP
const SURV_HP_K := 10.0     # выносливость 5 → ~28 HP, 30 → ~117 HP (с капами)
const REGEN_CAP := 8.0  # выносливость → регенерация: до 8 HP/с
const REGEN_K := 16.0   # 5 → ~0.7 HP/с, 30 → ~5.3 HP/с (с капами)

## Софт- и хард-капы сырых очков характеристик: до софт-капа каждое очко
## работает в полную силу; между капами каждое очко считается за
## STAT_SOFT_MULT, сверх хард-капа — за STAT_HARD_MULT. Применяются к
## итоговой сумме очков (база + вложенные + предметы) в effective() перед
## формулами затухания; штрафы предметов проходят без изменений.
## Временные значения, уточнить по игротестам.
const STAT_SOFT_CAP := 15.0
const STAT_HARD_CAP := 30.0
const STAT_SOFT_MULT := 0.5
const STAT_HARD_MULT := 0.25
const CLASS_CAP := 0.6  # уворот/блок: жёсткий предел 60% (проценты складываются напрямую)
# Фиксированное восстановление здоровья за передышку между волнами
const REST_HEAL := 25.0
# Доля максимального здоровья, восстанавливаемая при повышении уровня в бою
# (временное значение, уточнить по игротестам)
const LEVEL_UP_HEAL := 0.3
# Вместимость рюкзака (ячеек)
const INVENTORY_SIZE := 30
# Опыт за продажу предмета по редкости (временные значения)
const SELL_XP := [2, 4, 7, 12, 20, 35]

# Отравление (статусный эффект): время жизни каждого стака и снижение
# базовых характеристик. Стаки складываются с затуханием (временные значения)
const POISON_DURATION := 3.0    # секунд на стак, у каждого стака свой таймер
const POISON_PER_STACK := 5.0   # первый стак снижает характеристики на 5%
const POISON_STACK_DECAY := 0.6 # каждый следующий стак добавляет ×0.6 от предыдущего

# Кровотечение (статусный эффект): урон в секунду за стак, у каждого стака
# свой таймер. Стаки складываются с затуханием (как у отравления): базовый
# стак неизменен, но каждый следующий добавляет ×BLEED_STACK_DECAY
# (временные значения)
const BLEED_DURATION := 3.0  # секунд на стак
const BLEED_DPS := 2.0       # HP/с за один стак
const BLEED_STACK_DECAY := 0.6  # каждый следующий стак добавляет ×0.6 от предыдущего

var level := 1
var xp := 0
var stat_points := 0
var allocated := {"atk": 0, "def": 0, "spd": 0, "surv": 0}
# Слоты экипировки зависят от класса (CLASS_SLOTS), заполняются в _init
var equipment := {}
var inventory := []  # массив Item
# Текущее здоровье между волнами; < 0 — полное
var current_hp := -1.0
# Класс героя (ключ ROSTER): внешность, описание, набор слотов
var kind := "knight"
# Текущая волна забега этого героя (у каждого героя свой прогресс)
var wave := 1


func _init(p_kind: String = "knight") -> void:
	kind = p_kind
	for s in CLASS_SLOTS[kind]:
		equipment[s] = null


## Слоты экипировки этого героя (порядок — как на экране лагеря).
func equip_slots() -> Array:
	return CLASS_SLOTS[kind]


## Подходит ли предмет слоту экипировки: кольца — обоим кольцевым,
## оружие — обоим оружейным слотам Вора.
static func slot_accepts(equip_slot: String, item_slot: String) -> bool:
	if equip_slot == item_slot:
		return true
	if (equip_slot == "ring1" or equip_slot == "ring2") and item_slot == "ring":
		return true
	if (equip_slot == "weapon1" or equip_slot == "weapon2") and item_slot == "weapon":
		return true
	return false


## Имя героя из реестра.
func hero_name() -> String:
	return ROSTER[kind]["name"]


## Цвет фигуры героя на экране боя и в меню.
func body_color() -> Color:
	return ROSTER[kind]["color"]


## Форма фигуры героя: "rect" | "circle" | "triangle".
func body_shape() -> String:
	return ROSTER[kind]["shape"]


## Итоговые сырые очки: база класса + вложенные очки + бонусы предметов.
## Классовая характеристика (block/dodge) — прямые проценты: базовый шанс
## класса + проценты с предметов. Реальные боевые значения считает effective().
func get_stats() -> Dictionary:
	var s := {}
	for k in STAT_ORDER:
		s[k] = float(BASE[kind][k]) + float(PER_POINT[k]) * allocated[k]
	s[CLASS_STAT[kind]] = BASE_CLASS_PCT[kind]
	for slot in equipment:
		var it: Item = equipment[slot]
		if it != null:
			for k in it.bonuses:
				s[k] = s.get(k, 0.0) + it.bonuses[k]
	return s


## Формула затухания: cap × raw² / (raw² + K²). При raw = K достигается половина cap.
## Знак сохраняется: отрицательные очки (штрафы предметов) снижают значение.
static func diminish(raw: float, cap: float, k: float) -> float:
	return cap * raw * absf(raw) / (raw * raw + k * k)


## Эффективные очки с учётом софт- и хард-капов: сверх софт-капа каждое
## очко даёт STAT_SOFT_MULT, сверх хард-капа — STAT_HARD_MULT.
## Отрицательные значения (штрафы предметов) проходят без изменений.
static func cap_points(raw: float) -> float:
	if raw <= STAT_SOFT_CAP:
		return raw
	if raw <= STAT_HARD_CAP:
		return STAT_SOFT_CAP + (raw - STAT_SOFT_CAP) * STAT_SOFT_MULT
	return STAT_SOFT_CAP + (STAT_HARD_CAP - STAT_SOFT_CAP) * STAT_SOFT_MULT + (raw - STAT_HARD_CAP) * STAT_HARD_MULT


## Реальные боевые значения из сырых очков. Сначала сумма очков проходит
## софт-/хард-капы (cap_points), затем формулы затухания:
## atk — эффективная сила (урон), def_pct — доля снижения урона,
## aps — атак в секунду, max_hp и regen_hp — здоровье и регенерация
## из Выносливости, class_pct — шанс уворота/блока (прямая сумма
## процентов, предел CLASS_CAP; без капов очков).
static func effective(stats: Dictionary) -> Dictionary:
	var e := {}
	e["atk"] = cap_points(stats.get("atk", 0.0))
	e["def_pct"] = diminish(maxf(0.0, cap_points(stats.get("def", 0.0))), 1.0, DEF_K)
	e["aps"] = maxf(0.2, 1.0 + diminish(cap_points(stats.get("spd", 0.0)), SPD_CAP, SPD_K))
	var surv_raw: float = maxf(0.0, cap_points(stats.get("surv", 0.0)))
	e["max_hp"] = diminish(surv_raw, SURV_HP_CAP, SURV_HP_K)
	e["regen_hp"] = diminish(surv_raw, REGEN_CAP, REGEN_K)
	var class_pct_raw: float = maxf(0.0, stats.get("dodge", stats.get("block", 0.0)))
	e["class_pct"] = minf(CLASS_CAP, class_pct_raw / 100.0)
	return e


## Характеристики для отображения в лагере: 5 общих + классовая.
func stat_order() -> Array:
	return STAT_ORDER + [CLASS_STAT[kind]]


## Суммарное снижение базовых характеристик от отравления (доля 0..1).
## Стаки складываются с затуханием: 1 стак → 5%, 2 → 8%, 3 → 9.8%
## (каждый следующий добавляет ×POISON_STACK_DECAY от предыдущего).
static func poison_pct(stacks: int) -> float:
	if stacks <= 0:
		return 0.0
	return POISON_PER_STACK / 100.0 * (1.0 - pow(POISON_STACK_DECAY, stacks)) / (1.0 - POISON_STACK_DECAY)


## Суммарный урон кровотечения в секунду: база стака неизменна, но стаки
## складываются с затуханием — каждый следующий добавляет ×BLEED_STACK_DECAY
## от предыдущего (1 стак = 2 HP/с, 2 = 3.2, 3 = 3.92, предел ~5 HP/с).
static func bleed_dps(stacks: int) -> float:
	if stacks <= 0:
		return 0.0
	return BLEED_DPS * (1.0 - pow(BLEED_STACK_DECAY, stacks)) / (1.0 - BLEED_STACK_DECAY)


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


## Максимальное здоровье: выводится из Выносливости по формуле затухания.
func max_hp() -> float:
	return maxf(1.0, effective(get_stats())["max_hp"])


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


## Добавить предмет в рюкзак с учётом вместимости.
## Если рюкзак полон — теряется один случайный предмет самой низкой
## из имеющихся редкостей. Возвращает потерянный предмет (или null).
func add_item(item: Item) -> Item:
	var lost: Item = null
	if inventory.size() >= INVENTORY_SIZE:
		var min_rarity := 999
		for it in inventory:
			min_rarity = mini(min_rarity, it.rarity)
		var candidates := []
		for it in inventory:
			if it.rarity == min_rarity:
				candidates.append(it)
		lost = candidates[randi() % candidates.size()]
		inventory.erase(lost)
	inventory.append(item)
	return lost


## Продать предмет из рюкзака за опыт. Возвращает полученный опыт (0 — предмета нет).
func sell_item(item: Item) -> int:
	if not inventory.has(item):
		return 0
	inventory.erase(item)
	var xp: int = SELL_XP[item.rarity]
	add_xp(xp)
	return xp


## Надеть предмет из рюкзака. Если указан target_slot (ячейка, на которую
## бросили предмет) — надевает именно туда, заменяя её содержимое.
## Без target_slot: первый свободный подходящий слот; если все заняты —
## заменяет первый подходящий. Возвращает снятый предмет (или null).
func equip(item: Item, target_slot := "") -> Item:
	var slot := ""
	if target_slot != "" and equipment.has(target_slot) and slot_accepts(target_slot, item.slot):
		slot = target_slot
	else:
		for s in equip_slots():
			if slot_accepts(s, item.slot) and equipment[s] == null:
				slot = s
				break
		if slot == "":
			for s in equip_slots():
				if slot_accepts(s, item.slot):
					slot = s
					break
	if slot == "":
		return null
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
