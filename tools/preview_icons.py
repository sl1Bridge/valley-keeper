"""Превью-лист иконок с рамкой цвета редкости (шаг верификации пайплайна).

Использование:
    python tools/preview_icons.py <папка> [редкость 0-5]

Собирает все *.png из папки (кроме preview.png) в один лист preview.png
рядом с ними: тёмный фон слота, рамка цвета редкости (цвета — зеркало
Item.RARITY_COLORS), подпись — имя файла. По листу проверяем центровку,
чистоту краёв и читаемость силуэта.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RARITY_COLORS = [
    (199, 199, 199),  # обычный — серый
    (89, 217, 102),   # необычный — зелёный
    (89, 153, 255),   # редкий — синий
    (204, 102, 255),  # мистический — фиолетовый
    (242, 204, 77),   # легендарный — золотой
    (230, 77, 64),    # артефакт — красный
]
CELL, LABEL_H, BORDER = 400, 52, 14
FONT_PATH = "C:/Windows/Fonts/arial.ttf"


def build(folder: Path, rarity: int) -> Path:
    files = sorted(p for p in folder.glob("*.png") if p.stem != "preview")
    if not files:
        raise SystemExit("В папке нет PNG: %s" % folder)
    color = RARITY_COLORS[rarity]
    font = ImageFont.truetype(FONT_PATH, 30)

    sheet = Image.new("RGBA", (CELL * len(files), CELL + LABEL_H), (24, 24, 28, 255))
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(files):
        icon = Image.open(p).convert("RGBA")
        icon.thumbnail((CELL - 2 * BORDER - 24, CELL - 2 * BORDER - 24), Image.LANCZOS)
        cell = Image.new("RGBA", (CELL, CELL), (40, 40, 46, 255))
        cd = ImageDraw.Draw(cell)
        cd.rounded_rectangle([4, 4, CELL - 5, CELL - 5], radius=18,
                             outline=color + (255,), width=BORDER)
        cell.alpha_composite(icon, ((CELL - icon.width) // 2, (CELL - icon.height) // 2))
        sheet.alpha_composite(cell, (i * CELL, 0))
        tw = d.textlength(p.stem, font=font)
        d.text((i * CELL + (CELL - tw) / 2, CELL + 8), p.stem,
               font=font, fill=(240, 240, 240, 255))

    out = folder / "preview.png"
    sheet.convert("RGB").save(out)
    return out


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    folder = Path(sys.argv[1])
    rarity = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    out = build(folder, rarity)
    print("Готово: %s (%d иконок)" % (out, len(list(folder.glob('*.png'))) - 1))


if __name__ == "__main__":
    main()
