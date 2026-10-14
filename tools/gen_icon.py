"""Генерация иконки предмета через локальный ComfyUI (HTTP API, без MCP).

Использование:
    python tools/gen_icon.py "<описание предмета>" <имя_файла> [seed] ["<фон>"]

Берёт workflow sdxl_simple_example.json, подставляет описание предмета
в позитивные промпты (ноды 6 и 15), выставляет seed и filename_prefix,
отправляет на 127.0.0.1:8188 и скачивает готовый PNG в comfy_out/.
<фон> — необязательная замена "flat solid magenta background",
например "flat solid royal blue background" (фон по редкости).
"""

import json
import random
import shutil
import sys
import time
import urllib.request
from pathlib import Path

COMFY_URL = "http://127.0.0.1:8188"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = PROJECT_ROOT / "sdxl_simple_example.json"
OUT_DIR = PROJECT_ROOT / "comfy_out"

# В workflow промпт разбит на «описание предмета» + «общий стиль».
# Стиль берём как есть из сохранённого workflow (узнал его по щиту).
POSITIVE_NODES = ["6", "15"]   # BASE и REFINER позитив
NEGATIVE_NODES = ["7", "16"]   # BASE и REFINER негатив
SEED_NODE = "10"               # KSampler BASE (noise_seed)
SAVE_NODE = "19"               # SaveImage (filename_prefix)


def build_prompt(item_description: str, seed: int, prefix: str, background: str = "", extra_negative: str = "") -> dict:
    wf = json.loads(WORKFLOW_PATH.read_text(encoding="utf-8"))

    shield_desc = "a sturdy tower shield made of aged oak wood and forged steel"
    for node_id in POSITIVE_NODES:
        text = wf[node_id]["inputs"]["text"]
        if shield_desc in text:
            # Подменяем только начало описания предмета, сохраняя хвост стиля.
            head, sep, tail = text.partition(shield_desc)
            # Остаток старого описания предмета (между shield_desc и первой
            # стилевой фразой) тоже заменяем: ищем первую запятую стилевого блока.
            style_marker = "stylized 2D fantasy game art"
            idx = tail.find(style_marker)
            style_tail = tail[idx:] if idx != -1 else tail
            text = head + item_description + ", " + style_tail
        if background:
            text = text.replace("flat solid magenta background", background)
        wf[node_id]["inputs"]["text"] = text

    for node_id in NEGATIVE_NODES:
        text = wf[node_id]["inputs"]["text"].replace(
            "multiple shields", "multiple objects"
        )
        if extra_negative:
            text += ", " + extra_negative
        wf[node_id]["inputs"]["text"] = text

    wf[SEED_NODE]["inputs"]["noise_seed"] = seed
    wf[SAVE_NODE]["inputs"]["filename_prefix"] = prefix
    return wf


def submit(wf: dict) -> str:
    body = json.dumps({"prompt": wf}).encode("utf-8")
    req = urllib.request.Request(
        COMFY_URL + "/prompt", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())["prompt_id"]


def wait_result(prompt_id: str, timeout_s: int = 280) -> dict:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        with urllib.request.urlopen(COMFY_URL + "/history/" + prompt_id, timeout=30) as resp:
            history = json.loads(resp.read())
        if prompt_id in history:
            entry = history[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError("ComfyUI вернул ошибку: " + json.dumps(status, ensure_ascii=False))
            if entry.get("outputs"):
                return entry["outputs"]
        time.sleep(2)
    raise TimeoutError("ComfyUI не закончил генерацию за %d с" % timeout_s)


def download(outputs: dict, prefix: str) -> Path:
    OUT_DIR.mkdir(exist_ok=True)
    images = outputs[SAVE_NODE]["images"]
    saved = None
    for img in images:
        params = "filename=%s&subfolder=%s&type=%s" % (
            urllib.request.quote(img["filename"]),
            urllib.request.quote(img["subfolder"]),
            img["type"],
        )
        with urllib.request.urlopen(COMFY_URL + "/view?" + params, timeout=60) as resp:
            data = resp.read()
        saved = OUT_DIR / img["filename"]
        saved.write_bytes(data)
    return saved


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    description, prefix = sys.argv[1], sys.argv[2]
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else random.randrange(1, 2**62)
    background = sys.argv[4] if len(sys.argv) > 4 else ""
    extra_negative = sys.argv[5] if len(sys.argv) > 5 else ""

    print("Промпт-предмет: %s" % description)
    print("Seed: %d" % seed)
    wf = build_prompt(description, seed, prefix, background, extra_negative)
    prompt_id = submit(wf)
    print("Задача отправлена, id=%s, ждём..." % prompt_id)
    outputs = wait_result(prompt_id)
    path = download(outputs, prefix)
    # Копия рядом с оригиналом имени ComfyUI — удобно для вставки в игру позже.
    print("Готово: %s (%d байт)" % (path, path.stat().st_size))


if __name__ == "__main__":
    main()
