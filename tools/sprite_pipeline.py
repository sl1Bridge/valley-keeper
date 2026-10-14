"""Чистка и нарезка спрайтлистов от ИИ-сервиса.

Что делает:
1. Стирает серые кружки с номерами кадров (по цвету/форме компонентов).
2. Разбивает лист на связные компоненты и относит каждый к своему кадру
   по центроиду — так отсекаются дуги/части, залезшие из соседних ячеек.
3. Вырезает каждый кадр по bbox, выравнивает по низу (ступни) и центру,
   упаковывает в чистый лист фиксированных ячеек + отдельные PNG.

Запуск (из корня проекта):
  python tools/sprite_pipeline.py assets/sprites/knight/idle_sheet_raw.png   4 2 idle
  python tools/sprite_pipeline.py assets/sprites/knight/attack_sheet_raw.png 3 2 attack
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

CELL_OUT = 512      # размер ячейки в чистом листе
PAD = 16            # внутренний отступ от краёв ячейки
ALPHA_T = 100       # порог непрозрачности


def load(path):
    img = Image.open(path).convert("RGBA")
    return img, np.array(img)


def erase_number_badges(a, cols, rows):
    """Стереть серые кружки с цифрами.

    Кружок — единственный на листе объект из ПЛОСКОГО тёмно-серого цвета
    (mean 50..125, sat<12) площадью ~900px; тени доспеха дают блобы ≤550px.
    Берём блобы площадью >= 650 — это ровно кружки.
    """
    from scipy import ndimage  # type: ignore

    H, W = a.shape[:2]
    rgb = a[:, :, :3].astype(int)
    alpha = a[:, :, 3]
    mean = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    badge_col = (mean > 50) & (mean < 125) & (sat < 12) & (alpha > ALPHA_T)

    lab, n = ndimage.label(badge_col)
    removed = 0
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if len(xs) < 650:
            continue
        cy, cx = int(ys.mean()), int(xs.mean())
        r = 38
        y0, y1 = max(0, cy - r), min(H, cy + r + 1)
        x0, x1 = max(0, cx - r), min(W, cx + r + 1)
        yy, xx = np.ogrid[y0:y1, x0:x1]
        disk = (yy - cy) ** 2 + (xx - cx) ** 2 <= r * r
        region = a[y0:y1, x0:x1]
        rrgb = region[:, :, :3].astype(int)
        rmean = rrgb.mean(axis=2)
        rsat = rrgb.max(axis=2) - rrgb.min(axis=2)
        # стираем в диске только серое/белое (кружок и цифру), цветное не трогаем
        erase = disk & (((rsat < 40) & (rmean < 200)) | (rmean > 220))
        region[:, :, 3][erase] = 0
        removed += 1
    if removed != cols * rows:
        print(f"  ВНИМАНИЕ: стёрто кружков {removed}, ожидалось {cols * rows}")
    return a, removed


def components(alpha):
    from scipy import ndimage  # type: ignore

    mask = alpha > ALPHA_T
    lab, n = ndimage.label(mask)
    comps = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if len(xs) < 30:  # пыль
            continue
        comps.append(
            dict(id=i, xs=xs, ys=ys, area=len(xs),
                 cx=xs.mean(), cy=ys.mean(),
                 bbox=(xs.min(), ys.min(), xs.max(), ys.max()))
        )
    return comps


def process(path, cols, rows, name, outdir):
    img, a = load(path)
    H, W = a.shape[:2]
    cw, ch = W // cols, H // rows
    print(f"{path.name}: {W}x{H}, сетка {cols}x{rows}, ячейка {cw}x{ch}")

    a, removed = erase_number_badges(a, cols, rows)
    print(f"  стёрто кружков с номерами: {removed}")

    comps = components(a[:, :, 3])
    print(f"  компонентов на листе: {len(comps)}")

    frames = []
    for row in range(rows):
        for col in range(cols):
            idx = row * cols + col
            x0, y0, x1, y1 = col * cw, row * ch, (col + 1) * cw, (row + 1) * ch
            own = [c for c in comps if x0 <= c["cx"] < x1 and y0 <= c["cy"] < y1]
            if not own:
                print(f"  кадр {idx + 1}: ПУСТО")
                continue
            body = max(own, key=lambda c: c["area"])  # тело = самый большой
            keep = set(c["id"] for c in own)
            lab_mask = np.zeros((H, W), dtype=bool)
            for c in own:
                lab_mask[c["ys"], c["xs"]] = True
            # bbox всех своих компонентов
            xs_all = np.concatenate([c["xs"] for c in own])
            ys_all = np.concatenate([c["ys"] for c in own])
            bx0, bx1 = xs_all.min(), xs_all.max()
            by0, by1 = ys_all.min(), ys_all.max()
            clip = ""
            if bx0 <= x0: clip += " <-залез-слева"
            if bx1 >= x1 - 1: clip += " -залез-вправо->"
            frames.append(dict(
                idx=idx, mask=lab_mask, bbox=(bx0, by0, bx1, by1),
                body_bottom=body["bbox"][3],
                body_cx=(body["bbox"][0] + body["bbox"][2]) / 2,
            ))
            print(f"  кадр {idx + 1}: компонентов {len(own)}, "
                  f"bbox w={bx1 - bx0} h={by1 - by0}{clip}")

    # Вырезаем и упаковываем
    out_dir = Path(outdir) / name
    out_dir.mkdir(parents=True, exist_ok=True)
    max_w = max(f["bbox"][2] - f["bbox"][0] + 1 for f in frames)
    max_h = max(f["bbox"][3] - f["bbox"][1] + 1 for f in frames)
    scale = min((CELL_OUT - 2 * PAD) / max_w, (CELL_OUT - 2 * PAD) / max_h, 1.0)
    tw, th = int(max_w * scale), int(max_h * scale)
    sheet = Image.new("RGBA", (CELL_OUT * cols, CELL_OUT * rows), (0, 0, 0, 0))

    for f in frames:
        bx0, by0, bx1, by1 = f["bbox"]
        crop = np.zeros((by1 - by0 + 1, bx1 - bx0 + 1, 4), dtype=np.uint8)
        src = a[by0:by1 + 1, bx0:bx1 + 1]
        m = f["mask"][by0:by1 + 1, bx0:bx1 + 1]
        crop[m] = src[m]
        fimg = Image.fromarray(crop)
        fimg = fimg.resize((int(crop.shape[1] * scale), int(crop.shape[0] * scale)),
                           Image.LANCZOS)
        r, c = divmod(f["idx"], cols)
        # якорь: низ ТЕЛА -> низ ячейки минус PAD; по горизонтали — центр тела
        body_bottom_scaled = int((f["body_bottom"] - by0 + 1) * scale)
        body_cx_scaled = (f["body_cx"] - bx0) * scale
        ox = c * CELL_OUT + int(CELL_OUT / 2 - body_cx_scaled)
        oy = r * CELL_OUT + CELL_OUT - PAD - body_bottom_scaled
        sheet.paste(fimg, (ox, oy), fimg)
        fimg.save(out_dir / f"{name}_{f['idx'] + 1}.png")

    sheet_path = Path(outdir) / f"{name}_sheet_clean.png"
    sheet.save(sheet_path)
    print(f"  чистый лист: {sheet_path} ({cols}x{rows} по {CELL_OUT}px), кадры в {out_dir}")


if __name__ == "__main__":
    src, cols, rows, name = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    outdir = "assets/sprites/knight"
    process(Path(src), cols, rows, name, outdir)
