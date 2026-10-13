class_name AbilityIcon
extends Control

## Иконка способности героя: серая, по мере перезарядки заливается цветом
## сверху вниз; полностью цветная — способность готова. Без цифрового таймера.
## Используется на экране боя (живая заливка, BattleScreen) и статично
## в главном меню и лагере (заполнена, с подсказкой).
## Заливка сделана обрезкой: под серой иконкой лежит цветная копия внутри
## области-клипа высотой fill × высота иконки.

var ability := ""  # "roar" | "execute"
var fill := 1.0    # доля заряда 0..1 (1 — способность готова)
var icon_color := Color(0.9, 0.7, 0.3)

var _fill_clip: Control = null
var _glyph: _Glyph = null


func _init(p_ability := "", p_color := Color(0.9, 0.7, 0.3), p_size := 56.0) -> void:
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_default_cursor_shape = Control.CURSOR_HELP
	_fill_clip = Control.new()
	_fill_clip.clip_contents = true  # заливка сверху вниз: клип по высоте fill
	_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill_clip)
	_glyph = _Glyph.new()
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_clip.add_child(_glyph)
	setup(p_ability, p_color)


## Сменить способность/цвет (иконка переиспользуется в меню при выборе героя).
func setup(p_ability: String, p_color: Color) -> void:
	ability = p_ability
	icon_color = p_color
	if _glyph != null:
		_glyph.ability = ability
		_glyph.color = icon_color
		_glyph.queue_redraw()
	queue_redraw()


func _ready() -> void:
	_sync()


## Обновить заливку (0 — серая, 1 — цветная, готова).
func set_fill(f: float) -> void:
	fill = clampf(f, 0.0, 1.0)
	_sync()
	queue_redraw()


func _sync() -> void:
	if _fill_clip == null:
		return
	_fill_clip.position = Vector2.ZERO
	_fill_clip.size = Vector2(size.x, size.y * fill)
	if _glyph != null:
		_glyph.position = Vector2.ZERO
		_glyph.size = size


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.14, 0.16, 0.21))
	var ready := fill >= 1.0
	var base := icon_color if ready else Color(0.55, 0.56, 0.6)
	draw_glyph(self, ability, size / 2.0, size.x * 0.72, base)
	# Рамка заливается цветом вместе с иконкой: серая → цветная по мере заряда
	draw_rect(r, Color(0.3, 0.33, 0.4).lerp(icon_color, fill), false, 2.0)


## Символ способности: рупор для «Рёва», кинжал остриём вниз для
## «Смертельного удара». c — центр, s — размер символа.
static func draw_glyph(cv: CanvasItem, ability_key: String, c: Vector2, s: float, color: Color) -> void:
	match ability_key:
		"roar":
			# Рупор: корпус-трапеция раскрывом вправо + звуковые дуги
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.42 * s, -0.10 * s),
				c + Vector2(0.04 * s, -0.30 * s),
				c + Vector2(0.04 * s, 0.30 * s),
				c + Vector2(-0.42 * s, 0.10 * s),
			]), color)
			cv.draw_arc(c + Vector2(0.10 * s, 0), 0.26 * s, -0.95, 0.95, 12, color, 0.07 * s)
			cv.draw_arc(c + Vector2(0.10 * s, 0), 0.42 * s, -0.85, 0.85, 12, color, 0.06 * s)
		"execute":
			# Кинжал остриём вниз: лезвие, гарда, рукоять, навершие
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, 0.5 * s),
				c + Vector2(0.1 * s, -0.06 * s),
				c + Vector2(-0.1 * s, -0.06 * s),
			]), color)
			cv.draw_rect(Rect2(c + Vector2(-0.26 * s, -0.16 * s), Vector2(0.52 * s, 0.08 * s)), color)
			cv.draw_rect(Rect2(c + Vector2(-0.06 * s, -0.40 * s), Vector2(0.12 * s, 0.24 * s)), color)
			cv.draw_circle(c + Vector2(0, -0.45 * s), 0.07 * s, color)


## Цветная копия символа внутри области-клипа (рисует в координатах иконки,
## видна только в заполненной сверху части).
class _Glyph:
	extends Control

	var ability := ""
	var color := Color.WHITE


	func _draw() -> void:
		AbilityIcon.draw_glyph(self, ability, size / 2.0, size.x * 0.72, color)
