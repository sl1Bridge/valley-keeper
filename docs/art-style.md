# Иконки предметов: визуальный стиль и пайплайн

Зафиксировано 2026-10-14. История решений — в `docs/decisions.md`.

## Принцип

Иконки генерируются локально через ComfyUI Desktop (SDXL base + refiner).
Результат — PNG с прозрачным фоном, предмет отцентрован на квадратном
холсте. Редкость показывается **рамкой** цвета из `Item.RARITY_COLORS`,
которую рисует игра; фон в иконке не заливается.

## Инфраструктура

- ComfyUI Desktop должен быть запущен (`127.0.0.1:8188`). Workflow —
  `sdxl_simple_example.json` в корне проекта (API-формат); это источник
  истины для стилевого блока и негатива — при его правке обновить этот файл.
- Скрипты: `tools/gen_icon.py` (генерация), `tools/cut_bg.py` (вырезание
  фона + центровка), `tools/preview_icons.py` (превью с рамкой редкости).
  Зависимости: Pillow + numpy (системный python).
- Папки: `comfy_out/` — staging (в `.gitignore`); утверждённые иконки —
  `comfy_out/final/`, имена `snake_case` по существу предмета
  (`sword_rusty.png`). Перенос в `assets/` — отдельным решением.
- Неудачные генерации удаляются сразу после отбора. Удачные seed
  фиксируются в таблице ниже — вариант воспроизводим.

## Промпт-шаблон

Структура позитива: `<описание предмета>, <стилевой блок>`.

Описание — коротко, материалами, обязательно «a single …, one … only»;
для вертикальных предметов добавлять «upright / vertical composition».
Пример (утверждённый топор):

> a single rugged forester's axe, one axe only, worn oak haft and a broad
> forged steel head, leather grip wrap, subtle nicks on the blade edge

Стилевой блок (константа, зеркало workflow):

> stylized 2D fantasy game art, semi-realistic hand-painted game asset,
> restrained cartoon influence, crisp pixel-inspired shading, subtle pixel
> texture, slightly blocky clusters of color, clean stepped edges in small
> details, textured wood grain, brushed metal, controlled highlights, matte
> materials, strong readable silhouette, bold dark outlines, rich but
> balanced colors, front three-quarter view, centered single object,
> isolated on a flat solid royal blue background, consistent game art
> style, no frame, no text

Фон в промпте — **royal blue** (причины отказа от мадженты — в decisions).

Негатив (база):

> overly cute cartoon, childish, chibi, toy-like, plastic, glossy 3D
> render, excessive shiny highlights, smooth airbrushed gradients,
> exaggerated bevels, oversaturated yellow gold, photorealism, realistic
> photography, blurry, low contrast, noisy texture, excessive tiny
> details, smooth vector art, extremely large pixels, 8-bit retro game,
> tiny unreadable object, multiple objects, cropped object, background
> scenery, text, watermark, decorative border, inventory frame

Добавки под оружие/инструменты: `weapon set, collection, display,
showcase, multiple items, crossed weapons, scabbard, sheath, ornate
frame, filigree corners, item card, square panel, parchment, pedestal,
stone slab, second object, glow, orb, circle`.

## Критерии брака (перегенерация с новым seed)

- больше одного предмета или line-up («витрина» из нескольких);
- сломанная анатомия (лишние части, лезвия не с той стороны);
- рамка, эмблема, панель или «шар» под/за предметом;
- предмет обрезан краем кадра или мелкий;
- остатки фона или ореол после вырезания.

## Пайплайн

1. Генерация: `python tools/gen_icon.py "<описание>" <имя> [seed] [фон]
   [доп.негатив]` → PNG в `comfy_out/`. Seed печатается — записать.
2. Отбраковка по критериям выше; брак — перегенерация с новым seed.
3. Вырезание: `python tools/cut_bg.py comfy_out/<имя>_00001_.png` —
   заливка от краёв по цвету (предмет не страдает), растушёвка края,
   обрезка, центровка на квадратном холсте → `*_cut.png`. Допуск (30)
   и паддинг (24) можно передать 3-м и 4-м аргументом, если край
   получился рваным или с ореолом.
4. Превью: `python tools/preview_icons.py comfy_out/final <редкость 0-5>`
   → `preview.png`. Проверить центровку, чистоту краёв, читаемость.
5. Утверждённое — в `comfy_out/final/<имя>.png`; брак и промежуточные
   файлы удалить.
6. Верификация гейм-директором — до интеграции в игру.

## Эталонные seed (утверждённый сет)

| Файл | Предмет | Seed |
|---|---|---|
| `sword_rusty.png` | Ржавый меч | `1112223334445556667` |
| `axe_forester.png` | Топор лесника | `1556677889901122334` |
| `dagger_wanderer.png` | Кинжал странника | `3334445556667778881` |
| `hammer_blacksmith.png` | Молот кузнеца | `1357924680135792468` |
| `dagger_acrobat.png` | Кинжал акробата | `7778889990001112221` |
