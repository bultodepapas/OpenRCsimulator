"""Writes capability.json, OpenRC's GPU capability table (VQ-07h).

Run from the repository root: python tools/graphics/build_gpu_capability.py [--check]

Rows are matched in order against a normalized adapter name (app/render/gpu_capability.gd), so laptop rows
precede desktop rows and Ti/SUPER/XT variants precede their base model. `rel` is estimated 1080p raster
throughput relative to the RTX 3090 (1.00), the GPU OpenRC measured. It is an OpenRC estimate from public vendor
specifications and review aggregates, not a measurement. VRAM is the common configuration from vendor specs.
`steam_share_2026_10` is the Steam Hardware Survey video-card share (October 2026) for models in its top 45.
"""
import json
import sys
from pathlib import Path

ROWS: list[dict] = []


def add(row_id: str, match: str, rel: float, vram: int, kind: str, share: float | None = None) -> None:
    row = {"id": row_id, "match": match, "rel": rel, "vram_gb": vram, "class": kind}
    if share is not None:
        row["steam_share_2026_10"] = share
    ROWS.append(row)


def key(model: str) -> str:
    return model.replace(" ", "_")


LAPTOP = r"\b(laptop|max-q|mobile)\b"

# Entry RTX parts whose drivers omit "Laptop", and workstation laptops, before any broader RTX pattern.
add("rtx_2050", r"^rtx 2050\b", 0.13, 4, "laptop")
WORKSTATION = r"^(quadro rtx a?\d{4}|rtx a\d{4})\b"
add("rtx_workstation_laptop", WORKSTATION + r".*%s" % LAPTOP, 0.20, 4, "laptop")
# NVIDIA laptops: drivers name them "... Laptop GPU".
for model, rel, vram, share in [
        ("5090", 0.95, 24, None), ("5080", 0.85, 16, None), ("5070 ti", 0.65, 12, None), ("5070", 0.55, 8, 0.69),
        ("5060", 0.45, 8, 2.68), ("5050", 0.35, 8, None), ("4090", 0.85, 16, None), ("4080", 0.72, 12, None),
        ("4070", 0.50, 8, 0.92), ("4060", 0.40, 8, 3.60), ("4050", 0.30, 6, 1.76), ("3080 ti", 0.55, 16, None),
        ("3080", 0.50, 8, None), ("3070 ti", 0.45, 8, None), ("3070", 0.42, 8, None), ("3060", 0.36, 6, 1.74),
        ("3050 ti", 0.22, 4, 0.61), ("3050", 0.20, 4, 0.74), ("2080 super", 0.47, 8, None), ("2080", 0.45, 8, None),
        ("2070 super", 0.40, 8, None), ("2070", 0.38, 8, None), ("2060", 0.30, 6, None)]:
    add("rtx_%s_laptop" % key(model), r"^rtx %s\b.*%s" % (model, LAPTOP), rel, vram, "laptop", share)
for model, rel, vram in [("1660 ti", 0.26, 6), ("1650 ti", 0.15, 4), ("1650", 0.13, 4), ("1060", 0.18, 6),
                         ("1050 ti", 0.10, 4)]:
    add("gtx_%s_laptop" % key(model), r"^gtx %s\b.*%s" % (model, LAPTOP), rel, vram, "laptop")
add("mx_series", r"^mx\s?\d{3}\b", 0.06, 2, "laptop")

# NVIDIA desktop.
for model, rel, vram, share in [
        ("5090", 1.90, 32, None), ("5080", 1.48, 16, 1.78), ("5070 ti", 1.27, 16, 1.91), ("5070", 1.00, 12, 3.78),
        ("5060 ti", 0.68, 16, 2.70), ("5060", 0.57, 8, 3.15), ("5050", 0.45, 8, None),
        ("4090", 1.60, 24, 0.70), ("4080 super", 1.33, 16, 0.62), ("4080", 1.30, 16, 0.67),
        ("4070 ti super", 1.17, 16, 0.73), ("4070 ti", 1.07, 12, 0.89), ("4070 super", 1.00, 12, 1.43),
        ("4070", 0.80, 12, 1.71), ("4060 ti", 0.62, 8, 2.30), ("4060", 0.50, 8, 3.51),
        ("3090 ti", 1.10, 24, None), ("3090", 1.00, 24, None), ("3080 ti", 0.97, 12, None), ("3080", 0.87, 10, 1.36),
        ("3070 ti", 0.74, 8, 0.90), ("3070", 0.67, 8, 1.98), ("3060 ti", 0.60, 8, 2.13), ("3060", 0.43, 12, 3.78),
        ("3050", 0.30, 8, 3.25),
        ("2080 ti", 0.70, 11, None), ("2080 super", 0.60, 8, None), ("2080", 0.57, 8, None),
        ("2070 super", 0.52, 8, 0.66), ("2070", 0.46, 8, None), ("2060 super", 0.43, 8, 0.76), ("2060", 0.36, 6, 1.61)]:
    add("rtx_%s" % key(model), r"^rtx %s\b" % model, rel, vram, "discrete", share)
for model, rel, vram, share in [
        ("1660 super", 0.32, 6, 1.39), ("1660 ti", 0.31, 6, 0.86), ("1660", 0.28, 6, None),
        ("1650 super", 0.22, 4, None), ("1650", 0.16, 4, 2.44), ("1080 ti", 0.52, 11, None), ("1080", 0.40, 8, None),
        ("1070 ti", 0.36, 8, None), ("1070", 0.32, 8, None), ("1060", 0.21, 6, 1.45), ("1050 ti", 0.12, 4, 1.14),
        ("1050", 0.09, 2, None)]:
    add("gtx_%s" % key(model), r"^gtx %s\b" % model, rel, vram, "discrete", share)
add("gt_series", r"^gt \d{3,4}\b", 0.05, 2, "discrete")
add("rtx_workstation", WORKSTATION, 0.50, 8, "discrete")
add("rtx_unlisted_laptop", r"^rtx \d{4}\b.*%s" % LAPTOP, 0.25, 6, "laptop")
add("rtx_unlisted", r"^rtx \d{4}\b", 0.50, 8, "discrete")

# AMD Radeon laptops ("M"/"S" suffix) before desktop.
for model, rel, vram in [("7600m xt", 0.45, 8), ("7600m", 0.38, 8), ("7600s", 0.38, 8), ("6800s", 0.48, 8),
                         ("6700s", 0.42, 8), ("6600s", 0.35, 4), ("6850m xt", 0.65, 12), ("6800m", 0.60, 12),
                         ("6700m", 0.50, 10), ("6650m", 0.42, 8), ("6600m", 0.40, 8), ("6500m", 0.18, 4),
                         ("5600m", 0.25, 6), ("5500m", 0.20, 4)]:
    add("rx_%s" % key(model), r"^radeon rx %s\b" % model, rel, vram, "laptop")
# AMD desktop.
for model, rel, vram, share in [
        ("9070 xt", 1.20, 16, 1.59), ("9070", 1.05, 16, None), ("9060 xt", 0.66, 16, 0.89),
        ("7900 xtx", 1.45, 24, None), ("7900 xt", 1.25, 20, None), ("7900 gre", 1.05, 16, None),
        ("7800 xt", 0.92, 16, 0.63), ("7700 xt", 0.78, 12, None), ("7600 xt", 0.50, 16, None), ("7600", 0.48, 8, None),
        ("6950 xt", 1.05, 16, None), ("6900 xt", 1.00, 16, None), ("6800 xt", 0.93, 16, None), ("6800", 0.82, 16, None),
        ("6750 xt", 0.68, 12, None), ("6700 xt", 0.64, 12, None), ("6700", 0.57, 10, None), ("6650 xt", 0.50, 8, None),
        ("6600 xt", 0.47, 8, None), ("6600", 0.42, 8, 0.84), ("6500 xt", 0.20, 4, None), ("6400", 0.15, 4, None),
        ("5700 xt", 0.45, 8, None), ("5700", 0.40, 8, None), ("5600 xt", 0.37, 6, None), ("5500 xt", 0.25, 8, None),
        ("590", 0.22, 8, None), ("580", 0.20, 8, None), ("570", 0.17, 4, None), ("480", 0.19, 8, None)]:
    add("rx_%s" % key(model), r"^radeon rx %s\b" % model, rel, vram, "discrete", share)
add("rx_vega_64", r"^radeon rx vega 64\b", 0.33, 8, "discrete")
add("rx_vega_56", r"^radeon rx vega 56\b", 0.29, 8, "discrete")
add("rx_unlisted", r"^radeon rx [7-9]\d{3}\b", 0.60, 8, "discrete")
# AMD integrated: named Radeon 7x0M/8x0M parts, then the generic "Radeon Graphics".
for model, rel in [("890m", 0.12), ("880m", 0.10), ("8060s", 0.30), ("8050s", 0.22), ("780m", 0.09),
                   ("760m", 0.07), ("740m", 0.04), ("680m", 0.08), ("660m", 0.05), ("610m", 0.02)]:
    add("radeon_%s" % model, r"^radeon %s\b" % model, rel, 0, "integrated")
add("radeon_vega_igpu", r"^radeon vega \d+\b|^radeon (rx )?vega graphics\b", 0.03, 0, "integrated")
add("radeon_graphics_igpu", r"^radeon graphics\b", 0.05, 0, "integrated", 2.72)

# Intel.
for model, rel, vram in [("b580", 0.55, 12), ("b570", 0.48, 10), ("a770", 0.50, 16), ("a750", 0.45, 8),
                         ("a580", 0.38, 8), ("a380", 0.15, 6), ("a310", 0.10, 4)]:
    add("arc_%s" % model, r"^arc %s\b" % model, rel, vram, "discrete")
for model, rel, vram in [("a770m", 0.40, 16), ("a730m", 0.33, 12), ("a570m", 0.28, 8), ("a370m", 0.12, 4),
                         ("a350m", 0.09, 4)]:
    add("arc_%s" % model, r"^arc %s\b" % model, rel, vram, "laptop")
add("arc_140v_igpu", r"^arc 1[34]0[vt]\b", 0.10, 0, "integrated")
add("arc_igpu", r"^arc graphics\b|^graphics\b", 0.08, 0, "integrated")
add("iris_xe_igpu", r"^iris\b", 0.05, 0, "integrated", 1.78)
add("uhd_igpu", r"^(uhd|hd) graphics\b", 0.025, 0, "integrated", 1.99)

# Mesa radeonsi codenames, matched as "mesa <codename>" before the marketing name (app/render/gpu_capability.gd).
# Newer Mesa can report a generic "AMD Radeon Graphics" for discrete parts, so the chip decides.
for codename, rel, vram, kind in [
        ("gfx1201", 1.10, 16, "discrete"), ("gfx1200", 0.62, 16, "discrete"), ("navi31", 1.30, 20, "discrete"),
        ("navi32", 0.85, 16, "discrete"), ("navi33", 0.48, 8, "discrete"), ("navi21", 0.93, 16, "discrete"),
        ("navi22", 0.64, 12, "discrete"), ("navi23", 0.44, 8, "discrete"), ("navi24", 0.18, 4, "discrete"),
        ("navi10", 0.42, 8, "discrete"), ("navi14", 0.25, 4, "discrete"), ("vega10", 0.31, 8, "discrete"),
        ("polaris10", 0.20, 8, "discrete"), ("polaris11", 0.10, 4, "discrete"),
        ("gfx1151", 0.30, 0, "integrated"), ("gfx1150", 0.12, 0, "integrated"), ("phoenix", 0.09, 0, "integrated"),
        ("phoenix2", 0.04, 0, "integrated"), ("rembrandt", 0.08, 0, "integrated"), ("vangogh", 0.04, 0, "integrated"),
        ("renoir", 0.03, 0, "integrated"), ("cezanne", 0.03, 0, "integrated"), ("lucienne", 0.025, 0, "integrated"),
        ("raphael_mendocino", 0.02, 0, "integrated")]:
    add("mesa_%s" % codename, r"^mesa %s$" % codename, rel, vram, kind)
add("steam_deck", r"^custom gpu 0405\b|^custom gpu 0932\b", 0.04, 0, "integrated")

# Software rasterizers never qualify.
add("software", r"llvmpipe|softpipe|lavapipe|swiftshader|microsoft basic render|gdi generic|software rasterizer",
    0.0, 0, "software")

DOCUMENT = {
    "format": "openrc-gpu-capability v1",
    "generator": "tools/graphics/build_gpu_capability.py",
    "anchor": {
        "gpu": "NVIDIA GeForce RTX 3090", "rel": 1.0,
        "high_gpu_ms_1080p": 1.07, "high_gpu_ms_2160p": 3.09,
        "fixed_ms": 0.40, "ms_per_megapixel": 0.325,
        "source": "docs/research/visual-quality-implementation/VQ-07/rtx3090-matrix-2026-11-17/README.md",
    },
    "provenance": (
        "rel: OpenRC estimate (2026-11-18) of 1080p raster throughput relative to the RTX 3090, from public vendor "
        "specifications and review aggregates; only the anchor is measured. vram_gb: common vendor configuration. "
        "steam_share_2026_10: https://store.steampowered.com/hwsurvey/videocard/ (October 2026). "
        "No third-party benchmark table is copied."),
    "rows": ROWS,
}


def render() -> str:
    return json.dumps(DOCUMENT, indent=1) + "\n"


if __name__ == "__main__":
    out = Path(__file__).resolve().parents[2] / "app" / "data" / "gpu" / "capability.json"
    if "--check" in sys.argv[1:]:
        current = out.read_text(encoding="utf-8") if out.exists() else ""
        if current != render():
            sys.exit(f"{out} is stale; run python {Path(__file__).as_posix()}")
        print(f"{out} is current ({len(ROWS)} rows)")
    else:
        out.write_text(render(), encoding="utf-8", newline="\n")
        print(f"wrote {out} with {len(ROWS)} rows")
