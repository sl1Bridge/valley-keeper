# Иконки предметов: визуальный стиль и пайплайн

Зафиксировано 2026-10-14 после тестовой серии (кольцо, топор лесника).
Эталонный результат: `comfy_out/axe_forester_rare_03_00001_.png`.

## Общий принцип

Иконки генерируются **локально** на ПК гейм-директора через ComfyUI Desktop
(SDXL base + refiner, workflow `sdxl_simple_example.json` в корне проекта,
API-формат). Фон вырезается скриптом, PNG с прозрачностью идёт в игру,
а **фон-заливку по редкости рисует сама игра** (цвета `Item.RARITY_COLORS`).
Так один и тот же предмет обслуживает все 6 редкостей, а смена палитры
в коде автоматически «перекрашивает» все иконки.

## Промпт-шаблон

Структура позитива: `<описание предмета>, <общий стиль>`.

Описание предмета пишется коротко, материалами:
> a single rugged forester's axe, one axe only, worn oak haft and a broad
> forged steel head, leather grip wrap, subtle nicks on the blade edge

Общий стиль (константа, не менять без согласования):
> stylized 2D fantasy game art, semi-realistic hand-painted game asset,
> restrained cartoon influence, crisp pixel-inspired shading, subtle pixel
> texture, slightly blocky clusters of color, clean stepped edges in small
> details, textured wood grain, brushed metal, controlled highlights, matte
> materials, strong readable silhouette, bold dark outlines, rich but
> balanced colors, front three-quarter view, centered single object,
> isolated on a flat solid magenta background, consistent game art style,
> no frame, no text

Фон в промпте — **маджента**: это хромакей под вырезание, в предметах её
не бывает. Цветные фоны в промпте не используем (решение 2026-10-14).

Негатив (константа + добавки под предмет):
> overly cute cartoon, childish, chibi, toy-like, plastic, glossy 3D render,
> excessive shiny highlights, smooth airbrushed gradients, exaggerated
> bevels, oversaturated yellow gold, photorealism, realistic photography,
> blurry, low contrast, noisy texture, excessive tiny details, smooth
> vector art, extremely large pixels, 8-bit retro game, tiny unreadable
> object, multiple objects, cropped object, background scenery, text,
> watermark, decorative border, inventory frame

## Критерии брака (перегенерировать с другим seed)

- больше одного предмета / скрещенные предметы;
- сломанная анатомия (лезвия не с той стороны, лишние части);
- рамка, эмблема, «монетный» круг вместо полного фона;
- предмет обрезан краем кадра или мелкий.

Добавки в негатив под конкретный предмет допустимы (для топора помогло:
`crossed axes, two axes, emblem, badge, circular frame, coat of arms`).
Усиление «a single … , one … only» в позитиве тоже работает.

## Пайплайн (команды)

ComfyUI Desktop должен быть запущен (127.0.0.1:8188).

```bash
# 1. Генерация (seed можно задать для воспроизводимости, иначе случайный)
python tools/gen_icon.py "<описание предмета>" <имя_файла> [seed] [фон] [доп.негатив]

# 2. Вырезание фона -> PNG с альфой, обрезка по содержимому
python tools/cut_bg.py comfy_out/<имя_файла>_00001_.png
```

- `tools/gen_icon.py` — подставляет описание в workflow, отправляет в
  ComfyUI, скачивает PNG в `comfy_out/`. Печатает seed — записывать его
  в комментарий/имя, удачные варианты воспроизводимы.
- `tools/cut_bg.py` — заливка от краёв с допуском по цвету (предмет не
  страдает, даже если в нём есть оттенки фона), лёгкая растушёвка края,
  обрезка с паддингом. Параметры: допуск (по умолч. 30), паддинг (24).

Сырые и обработанные PNG лежат в `comfy_out/` (в git не коммитятся);
в игру иконки переносятся отдельным решением (в `assets/`, с даунскейлом
до рабочего размера — определим при интеграции).

## Проверка результата

Перед принятием иконки — превью поверх игрового цвета редкости
(композит PIL, см. историю задачи от 2026-10-14). Края должны быть чистыми,
без ореола и остатков фона.
