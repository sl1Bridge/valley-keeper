"""Вырезание плоского фона у сгенерированной иконки -> PNG с прозрачностью.

Использование:
    python tools/cut_bg.py <входной.png> [выходной.png] [допуск] [паддинг]

Алгоритм: берём цвет фона по краям картинки, затем «заливкой от краёв»
(flood fill с допуском) помечаем связанный фон — так предмет не пострадает,
даже если внутри него есть похожие на фон оттенки. Края слегка растушёвываем,
затем обрезаем картинку по содержимому с паддингом (пиксели).
По умолчанию результат пишется рядом с суффиксом _cut.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def cut_background(src: Path, dst: Path, tol: int = 30, pad: int = 24) -> None:
    img = Image.open(src).convert("RGB")
    arr = np.asarray(img).astype(np.int16)
    h, w, _ = arr.shape

    # Цвет фона — медиана пикселей по всем четырём краям.
    border = np.concatenate([arr[0], arr[-1], arr[:, 0], arr[:, -1]])
    bg = np.median(border, axis=0)

    # «Похожие на фон» пиксели (расстояние Чебышёва по каналам).
    near = np.abs(arr - bg).max(axis=2) <= tol

    # Flood fill от краёв: расширяем маску только по «похожим» пикселям,
    # пока она не перестанет расти.
    mask = np.zeros((h, w), dtype=bool)
    mask[0, :] = near[0, :]
    mask[-1, :] = near[-1, :]
    mask[:, 0] = near[:, 0]
    mask[:, -1] = near[:, -1]
    while True:
        grown = mask.copy()
        grown[1:, :] |= mask[:-1, :]
        grown[:-1, :] |= mask[1:, :]
        grown[:, 1:] |= mask[:, :-1]
        grown[:, :-1] |= mask[:, 1:]
        grown &= near
        if (grown == mask).all():
            break
        mask = grown

    alpha = np.where(mask, 0, 255).astype(np.uint8)
    # Лёгкая растушёвка границы, чтобы не было рваного края.
    alpha_img = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(1.2))

    out = img.convert("RGBA")
    out.putalpha(alpha_img)

    # Обрезка по видимому содержимому с паддингом.
    bbox = alpha_img.point(lambda a: 255 if a > 8 else 0).getbbox()
    if bbox:
        l, t, r, b = bbox
        l = max(0, l - pad)
        t = max(0, t - pad)
        r = min(w, r + pad)
        b = min(h, b + pad)
        out = out.crop((l, t, r, b))

    # Центровка на квадратном прозрачном холсте: иконки в слотах игры
    # квадратные, предмет должен сидеть ровно по центру.
    side = max(out.width, out.height)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(out, ((side - out.width) // 2, (side - out.height) // 2))
    out = square

    out.save(dst)
    print("Готово: %s (%dx%d)" % (dst, out.width, out.height))


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_name(src.stem + "_cut.png")
    tol = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    pad = int(sys.argv[4]) if len(sys.argv) > 4 else 24
    cut_background(src, dst, tol, pad)


if __name__ == "__main__":
    main()
