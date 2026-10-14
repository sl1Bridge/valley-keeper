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
  (`sword_rusty.png`). Интегрированные в игру иконки живут в
  `assets/icons/items/` и регистрируются в `Item.ICON_TEXTURES`
  (ключ — имя шаблона предмета; значения — только `preload`, см.
  комментарий в `Item.gd`: `load()` внутри `_draw()` даёт белый квадрат).
- Неудачные генерации удаляются сразу после отбора. Удачные seed
  фиксируются в таблице ниже — вариант воспроизводим. Если seed не
  записан, его можно восстановить из метаданных PNG: ComfyUI вшивает
  workflow в tEXt-чанк `prompt`, seed — в ноде `10` → `noise_seed`.

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

Добавка к негативу (универсальная, используется для всех предметов
с 2026-10-14; раньше была отдельная добавка «под оружие»):

> multiple items, showcase, display, collection, crossed weapons,
> ornate frame, filigree corners, item card, square panel, parchment,
> pedestal, stone slab, second object, character sheet, reference
> sheet, concept sheet, turnaround, multiple views, orthographic views,
> front and back view, grid of items, person, human, mannequin, wearer,
> vignette, gradient background, drop shadow, ground shadow

Под конкретный предмет добавляются точечные слова-блокеры (через
5-й аргумент gen_icon.py), когда модель упорно рисует лишнее:
`wooden bowl, crown, round shield, boots, water, puddle` и т.п.

## Критерии брака (перегенерация с новым seed)

- больше одного предмета или line-up («витрина» из нескольких) —
  самая частая причина (~половина генераций);
- сломанная анатомия (лишние части, лезвия не с той стороны);
- рамка, эмблема, панель, венок или «шар» под/за предметом;
- предмет обрезан краем кадра или мелкий;
- градиентный или виньеточный фон и тень-пятно под предметом — такой
  фон не вырезается чисто (flood fill идёт от краёв к одному цвету,
  перепад больше допуска остаётся ореолом);
- предмет цветом сливается с фоном — flood fill съедает и его
  (тёмно-зелёный плащ на сине-сером ушёл в прозрачность);
- другой предмет вместо заказанного (щит вместо кольца, корона),
  фотореализм, предмет на «деревянном столе»;
- остатки фона или ореол после вырезания.

Практика: модель часто игнорирует цвет фона в промпте — это нормально,
годится любой ПЛОСКИЙ фон. Если предмет не получается 3-4 раза
подряд, меняй формулировку описания, а не только seed (кольца
стабильно получались рецептом «a single silver ring, one ring only,
large <камень> gemstone in an ornate silver setting»).

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

Допуск вырезания указан, если отличается от стандартного 30.

| Файл | Предмет | Seed |
|---|---|---|
| `sword_rusty.png` | Ржавый меч | `1112223334445556667` |
| `axe_forester.png` | Топор лесника | `1556677889901122334` |
| `dagger_wanderer.png` | Кинжал странника | `3334445556667778881` |
| `hammer_blacksmith.png` | Молот кузнеца | `1357924680135792468` |
| `dagger_acrobat.png` | Кинжал акробата | `7778889990001112221` |
| `shield_militia.png` | Щит ополченца | `2026101417000011111` |
| `shield_tower.png` | Башенный щит | `2026101419000022222` |
| `shield_bastion.png` | Щит бастиона | `2026101419000033333` |
| `helmet_leather.png` | Кожаный шлем | `2026101419000044444` |
| `helmet_guard.png` | Шлем стражника | `2026101417000066666` |
| `helmet_iron.png` | Железный шлем | `2026101418000055555` |
| `hood_shadow.png` | Капюшон тени | `2026101416000077777` |
| `armor_leather.png` | Кожаная куртка | `2026101416000088888` |
| `armor_chainmail.png` | Кольчуга (допуск 55) | `2026101422000111111` |
| `cloak_shadow.png` | Плащ тени | `2026101419000088888` |
| `cloak_evasion.png` | Плащ ускользания | `2026101422000222222` |
| `boots_old.png` | Старые сапоги | `2026101421000222222` |
| `boots_pathfinder.png` | Сапоги следопыта | `2026101416000131313` |
| `boots_bastion.png` | Сапоги бастиона | `2026101416000141414` |
| `boots_acrobat.png` | Сапоги акробата (допуск 50) | `2026101416000151515` |
| `amulet_stone.png` | Каменный оберег | `2026101419000111111` |
| `amulet_wolf.png` | Оберег волка (допуск 55) | `2026101416000171717` |
| `amulet_sun.png` | Солнечный медальон (допуск 60) | `2026101417000121212` |
| `amulet_feather.png` | Перо ветра | `2026101416000191919` |
| `ring_life.png` | Кольцо жизни | `2026101419000131313` |
| `ring_blade.png` | Кольцо клинка | `2026101421000444444` |
| `ring_tide.png` | Кольцо прилива | `2026101423000666666` |
| `ring_guard.png` | Кольцо стража | `2026101423000222222` |
