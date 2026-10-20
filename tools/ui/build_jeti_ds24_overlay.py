"""Cut the official frontal DS-24 II photo out for the flight overlay.

Source and permission record: assets/ui/jeti-ds24-ii/README.md.
Dependencies are pinned in tools/ui/requirements.txt (asset tooling only).
"""

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/ui/jeti-ds24-ii/front-original.jpg"
TARGET = ROOT / "app/assets/ui/jeti_ds24_ii_orange.png"
CROP = (150, 25, 1070, 1160)
OUTPUT_SIZE = (360, 444)


def main() -> None:
    photo = Image.open(SOURCE).convert("RGB").crop(CROP)
    rgb = np.asarray(photo)
    near_white = np.all(rgb >= 240, axis=2)
    height, width = near_white.shape
    outside = np.zeros((height, width), dtype=bool)
    queue = deque()
    for x in range(width):
        if near_white[0, x]:
            queue.append((x, 0))
        if near_white[height - 1, x]:
            queue.append((x, height - 1))
    for y in range(height):
        if near_white[y, 0]:
            queue.append((0, y))
        if near_white[y, width - 1]:
            queue.append((width - 1, y))
    while queue:
        x, y = queue.popleft()
        if outside[y, x] or not near_white[y, x]:
            continue
        outside[y, x] = True
        if x:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))
    alpha = Image.fromarray(np.where(outside, 0, 255).astype("uint8"))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    photo.putalpha(alpha)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    photo.resize(OUTPUT_SIZE, Image.Resampling.LANCZOS).save(TARGET, optimize=True)
    print(TARGET.relative_to(ROOT))


if __name__ == "__main__":
    main()
