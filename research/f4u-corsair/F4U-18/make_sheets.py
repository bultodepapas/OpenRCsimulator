"""F4U-18: comparison sheets and a timing table from one run_bench.py result directory.

For every camera, a sheet with each model's screenshot side by side (one row per mode) and a label; and table.md
with load time, triangles, surfaces and, per camera, median frame time, render GPU time, draw calls and primitives.

    python research/f4u-corsair/F4U-18/make_sheets.py RESULT_DIR model1 model2 ...
"""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

result = Path(sys.argv[1])
models = sys.argv[2:]
sheets = result / "sheets"
sheets.mkdir(exist_ok=True)
font = ImageFont.load_default(size=28)
cameras = sorted(p.stem for p in (result / "shots" / f"{models[0]}-textured").glob("*.png"))
W, H = 960, 540
for camera in cameras:
    modes = [m for m in ["clay", "textured"] if (result / "shots" / f"{models[0]}-{m}" / f"{camera}.png").exists()]
    sheet = Image.new("RGB", (W * len(models), H * len(modes)), "white")
    for row, mode in enumerate(modes):
        for col, model in enumerate(models):
            path = result / "shots" / f"{model}-{mode}" / f"{camera}.png"
            if not path.exists():
                continue
            image = Image.open(path).convert("RGB").resize((W, H), Image.LANCZOS)
            draw = ImageDraw.Draw(image)
            draw.rectangle((0, 0, W, 40), fill=(0, 0, 0))
            draw.text((10, 4), f"{model} ({mode})", fill=(255, 255, 255), font=font)
            sheet.paste(image, (col * W, row * H))
    sheet.save(sheets / f"{camera}.png")

lines = ["| Model | Load ms | Triangles | Surfaces | Video MB |", "| --- | ---: | ---: | ---: | ---: |"]
data = {}
for model in models:
    path = result / f"{model}-textured.json"
    if path.exists():
        data[model] = json.loads(path.read_text(encoding="utf-8"))
        d = data[model]
        lines.append(f"| {model} | {d['load_ms']:.0f} | {d['triangles']:,} | {d['surfaces']} | {d['video_mem_mb']:.0f} |")
lines += ["", "Per camera: median frame ms / measured GPU render ms / draw calls / primitives (visible + shadow).", "",
          "| Camera | " + " | ".join(data) + " |", "| --- |" + " ---: |" * len(data)]
for i, camera in enumerate(cameras):
    cells = []
    for model, d in data.items():
        c = d["cameras"][i]
        cells.append(f"{c['frame_ms_median']:.2f} / {c['render_gpu_ms']:.2f} / {c['draw_calls']} / "
                     f"{(c['primitives'] + c['shadow_primitives']) / 1000:.0f}k")
    lines.append(f"| {camera} | " + " | ".join(cells) + " |")
(result / "table.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
