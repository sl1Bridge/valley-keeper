class_name Hero
extends RefCounted

## Данные героя: характеристики, уровень, опыт, экипировка, рюкзак, прогресс забега.
## Никакой визуальной логики — только числа и правила.

const STAT_ORDER := ["hp", "atk", "def", "spd", "regen"]

## Реестр героев (классы). Отличаются внешностью и набором слотов экипировки:
## у Рыцаря есть слот под щит, у Вора — два слота под оружие.
## Характеристики пока одинаковые. Имена, описания и внешность временные.
const KINDS := ["knight", "rogue"]
const ROSTER := {
	"knight": {
		"name": "Рыцарь",
		"color": Color(0.25, 0.45, 0.9),
		"shape": "rect",
		"desc": "Надёжный защитник долины. Носит щит — дополнительный слот снаряжения для защиты.",
	},
	"rogue": {
		"name": "Вор",
		"color": Color(0.5, 0.32, 0.62),
		"shape": "triangle",
		"desc": "Быстрый и смертоносный. Сражается двумя клинками — два слота под оружие.",
	},
}

## Слоты экипировки по классам.
const CLASS_SLOTS := {
	"knight": ["weapon", "shield", "armor", "amulet", "ring1", "ring2"],
	"rogue": ["weapon1", "weapon2", "armor", "amulet", "ring1", "ring2"],
}

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
# Вместимость рюкзака (ячеек)
const INVENTORY_SIZE := 30
# Опыт за продажу предмета по редкости (временные значения)
const SELL_XP := [2, 4, 7, 12, 20, 35]

var level := 1
var xp := 0
var stat_points := 0
var allocated := {"hp": 0, "atk": 0, "def": 0, "spd": 0, "regen": 0}
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
