#!/usr/bin/env python3
"""L6c-R1: 0.5-cutoff alpha coverage of each LandscapeLab leaf atlas per box-filtered mip level.

Run from the repository root with Pillow and NumPy (for example .tools/visual-venv/bin/python).
Prints coverage relative to mip 0 and the mean RGB of transparent texels, which explains why
un-premultiplying averaged colour over-brightens distant crowns.
"""
from pathlib import Path

import numpy as np
from PIL import Image

MODELS = Path("app/assets/landscape/vegetation/models/landscapelab_tree_2026")
ATLASES = {
    "fagus": MODELS / "fagus/Fagus_Image_4.png",
    "quercus2": MODELS / "quercus2/quercus2_Image_4.png",
    "quercus": MODELS / "quercus/quercus_Image_4.png",
    "pine": MODELS / "pine/pine_joined_Image_4.png",
}

for name, path in ATLASES.items():
    rgba = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
    alpha = rgba[..., 3]
    mips = [alpha]
    while min(mips[-1].shape) > 1:
        level = mips[-1][: mips[-1].shape[0] // 2 * 2, : mips[-1].shape[1] // 2 * 2]
        mips.append(0.25 * (level[0::2, 0::2] + level[1::2, 0::2] + level[0::2, 1::2] + level[1::2, 1::2]))
    base = (mips[0] >= 0.5).mean()
    ratios = " ".join(f"{(mip >= 0.5).mean() / base:.2f}" for mip in mips[1:10])
    transparent = rgba[..., :3][alpha < 0.1].mean(axis=0)
    print(f"{name:9s} mip0 coverage {base:.3f}; mips 1-9 relative: {ratios}; transparent RGB {np.round(transparent, 3)}")
