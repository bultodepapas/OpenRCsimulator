#!/usr/bin/env python3
"""Compare the model's transparent renders with the drawing's filled silhouettes: overlays and contour distances.

Metric (as research/avanti-s/refinement/review.py, but sampled on the whole outline instead of hand picks): for every
pixel of the drawing's outline (boundary of the filled silhouette, measure.py) the Euclidean distance to the nearest
render-alpha edge, and the reverse (render edge -> drawing outline), per view and per longitudinal bin; plus the
intersection-over-union of the two filled masks. Pixels only; nearest edge may belong to another part.

    python3 research/p51/p51-02/silhouette/review.py --candidate <renders dir> --output <dir> [--baseline <renders dir>]
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, binary_erosion, distance_transform_edt

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))
from measure import silhouette, picks  # noqa: E402

sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
COMPARE_PX = 2  # ignore pixels this close to the crop border


def edge(mask):
    return mask & ~binary_erosion(mask)


def metrics(real, model, view, scale, ignore=None):
    """Mean/percentile distances (px) both ways and IoU, overall and in 8 longitudinal bins (model axis). `ignore` marks
    pixels (exclusion boxes, dilated) whose outline pixels are dropped from the metric and whose area leaves both masks:
    the boxes cut the drawing's fill, so their borders are not contour."""
    if ignore is not None:
        real = real & ~ignore
        model = model & ~ignore
    d_real = distance_transform_edt(~edge(model))  # distance from any pixel to the model edge
    d_model = distance_transform_edt(~edge(real))
    re, me = edge(real), edge(model)
    if ignore is not None:
        grown = binary_dilation(ignore, iterations=3)
        re, me = re & ~grown, me & ~grown
    a, b = d_real[re], d_model[me]
    out = dict(real_to_model_mean_px=float(a.mean()), real_to_model_p90_px=float(np.percentile(a, 90)),
               model_to_real_mean_px=float(b.mean()), model_to_real_p90_px=float(np.percentile(b, 90)),
               iou=float((real & model).sum() / (real | model).sum()), mean_mm_model=float(a.mean() / scale * 1000))
    axis = 1 if view in ("side",) else 0  # side: along image x; top/front: rows (top) / columns (front)
    if view == "front":
        axis = 1
    coords = np.where(re)[axis]
    lo, hi = coords.min(), coords.max()
    bins = []
    for k in range(8):
        sel = (coords >= lo + (hi - lo) * k / 8) & (coords < lo + (hi - lo) * (k + 1) / 8 + (1 if k == 7 else 0))
        bins.append(float(a[sel].mean()) if sel.any() else None)
    out["real_to_model_bins_px"] = bins
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    fit = json.loads((HERE / "camera-fit.json").read_text())
    drawing = ROOT / picks["drawing"]
    assert sha(drawing) == fit["drawing_sha256"], "drawing changed"
    im = np.asarray(Image.open(drawing)).astype(np.uint8)
    dark = im < 140
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.candidate / "render-manifest.json").read_text())
    base_manifest = json.loads((args.baseline / "render-manifest.json").read_text()) if args.baseline else None
    rows = {}
    for view in fit["views"]:
        key = view["id"]
        v = picks["views"][key]
        real = silhouette(dark, v["box"], v["exclude"])
        if key == "front":  # left half only (the right wing's outline leaks in the drawing)
            real[:, int(view["anchors"]["centre"]["picked_px"][0]):] = False
        for box in v.get("mask_after", []):  # propeller blades: drawn in the three-view, not compared
            real[max(box[1] - v["box"][1], 0):box[3] - v["box"][1], max(box[0] - v["box"][0], 0):box[2] - v["box"][0]] = False
        crop = im[v["box"][1]:v["box"][3], v["box"][0]:v["box"][2]]
        result = {}
        for label, folder, man in (("after", args.candidate, manifest), ("before", args.baseline, base_manifest)):
            if folder is None:
                continue
            path = folder / f"{key}.png"
            rec = next(c for c in man["captures"] if c["id"] == key)
            assert sha(path) == rec["sha256"], "render changed since its manifest"
            rgba = np.asarray(Image.open(path).convert("RGBA"))
            assert rgba.shape[:2] == real.shape, (rgba.shape, real.shape)
            model = rgba[:, :, 3] >= 128
            if key == "front":
                model[:, int(view["anchors"]["centre"]["picked_px"][0]):] = False
            ignore = np.zeros(real.shape, bool)
            for box in v["exclude"]:
                ignore[max(box[1] - v["box"][1], 0):box[3] - v["box"][1], max(box[0] - v["box"][0], 0):box[2] - v["box"][0]] = True
            result[label] = metrics(real, model, key, view["display_scale_px_per_model_m"], ignore)
            if label == "after":
                # Composite for review: drawing in grey, model silhouette in translucent cyan, drawing outline in red.
                rgb = np.stack([crop] * 3, -1).astype(float)
                rgb[model] = rgb[model] * 0.45 + np.array([24, 220, 234]) * 0.55
                rgb[edge(real)] = [230, 40, 40]
                Image.fromarray(rgb.astype(np.uint8)).save(args.output / f"overlay_{key}.png")
                Image.fromarray(crop).save(args.output / f"drawing_{key}.png")
        rows[key] = result
    summary = dict(schema="openrc-silhouette-review-v1", label=args.label, fit_sha256=sha(HERE / "camera-fit.json"),
                   candidate=dict(geometry_sha256=manifest["geometry_sha256"], model_sha256=manifest["model_sha256"], visual_revision=manifest.get("visual_revision")),
                   baseline=dict(geometry_sha256=base_manifest["geometry_sha256"], model_sha256=base_manifest["model_sha256"]) if base_manifest else None,
                   metric="Euclidean distance (px) from each drawing-outline pixel to the nearest render-alpha>=128 edge and the reverse; IoU of the filled masks; 8 longitudinal bins nose->tail (side, top) or tip->centre (front). Propeller, wheels and dimension lines excluded by the drawing silhouette; the exclusion boxes (drop tanks, dimension boxes) are removed from both masks and their borders ignored. Not metric accuracy per component.",
                   views=rows)
    (args.output / "metrics.json").write_text(json.dumps(summary, indent=2) + "\n")
    write_viewer(args.output, fit, rows, args.candidate, args.baseline, args.label)
    for key, r in rows.items():
        a = r["after"]
        line = f"{key:6} real->model {a['real_to_model_mean_px']:5.1f} px (p90 {a['real_to_model_p90_px']:5.1f}) model->real {a['model_to_real_mean_px']:5.1f} px  IoU {a['iou']:.3f}  ≈{a['mean_mm_model']:.0f} mm on the model"
        if "before" in r:
            b = r["before"]
            line += f"   | before {b['real_to_model_mean_px']:5.1f} px, IoU {b['iou']:.3f}"
        print(line)
        print("        bins:", " ".join("  -- " if x is None else f"{x:5.1f}" for x in a["real_to_model_bins_px"]))
    print(args.output)


def write_viewer(output, fit, rows, candidate, baseline, label):
    """index.html: the drawing crop with the model render(s) overlaid in SVG (opacity, contour, before/after), no edits."""
    import html as h
    import os
    import shutil
    rel = lambda p: os.path.relpath(p, output)
    blocks = []
    for view in fit["views"]:
        key = view["id"]
        w, hh = view["size_px"]
        after = rel(candidate / f"{key}.png")
        before = rel(baseline / f"{key}.png") if baseline else ""
        m = rows[key]["after"]
        caption = f"{view['title']} · real→modelo {m['real_to_model_mean_px']:.1f} px (p90 {m['real_to_model_p90_px']:.1f}), IoU {m['iou']:.3f}"
        if "before" in rows[key]:
            b = rows[key]["before"]
            caption += f" · antes {b['real_to_model_mean_px']:.1f} px, IoU {b['iou']:.3f}"
        blocks.append(f'''<section><h2>{h.escape(caption)}</h2>
<svg class="stage" viewBox="0 0 {w} {hh}" role="img"><image class="photo" href="drawing_{key}.png" width="{w}" height="{hh}"/>
<image class="before" href="{h.escape(before)}" width="{w}" height="{hh}" opacity="0" style="filter:url(#tint)"/>
<image class="after" href="{h.escape(after)}" width="{w}" height="{hh}" opacity=".45"/></svg></section>''')
    page = f'''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>P-51D · siluetas sobre la tres vistas AN 01-60-3</title><style>
*{{box-sizing:border-box}}body{{margin:0;background:#14212d;color:#edf3f6;font:16px system-ui}}main{{max-width:1600px;margin:auto;padding:24px}}
h1{{font-size:24px}}h2{{font-size:16px;font-weight:500;color:#a8d8e0}}p{{line-height:1.5;max-width:100ch}}.controls{{display:flex;gap:18px;align-items:center;flex-wrap:wrap;margin:16px 0}}
button,select{{font:inherit;padding:8px;background:#274357;color:inherit;border:1px solid #7698a9;border-radius:6px}}button[aria-pressed=true]{{background:#096b70}}
.stage{{width:100%;height:auto;display:block;background:#f4f1ea;border-radius:6px}}small{{color:#a8bfcd}}input{{accent-color:#2ae1d4}}
</style><main><h1>P-51D 1/4 · siluetas del modelo sobre la tres vistas oficial (AN 01-60-3, dominio público)</h1>
<p>{h.escape(label)}. Cámaras ortográficas fijadas por dos anclas por vista (punta del cono y timón; puntas de ala), escala uniforme, sin deformar el dibujo. El render cian es la silueta del modelo (material plano, sin hélice); «antes» es la primera maqueta en magenta.</p>
<div class="controls"><button data-mode="both" aria-pressed="true">Superponer</button><button data-mode="photo" aria-pressed="false">Solo dibujo</button><button data-mode="model" aria-pressed="false">Solo modelo</button>
<label>Opacidad <input id="opacity" type="range" min="0" max="100" value="45"><output id="value">45%</output></label><label><input id="contour" type="checkbox"> Contorno</label><label><input id="before" type="checkbox"> Mostrar «antes»</label></div>
<svg width="0" height="0" style="position:absolute"><defs><filter id="edge"><feMorphology in="SourceAlpha" operator="erode" radius="2" result="inner"/><feComposite in="SourceAlpha" in2="inner" operator="out"/></filter>
<filter id="tint"><feColorMatrix type="matrix" values="1 0 0 0 0.9  0 0 0 0 0.1  0 0 0 0 0.6  0 0 0 1 0"/></filter></defs></svg>
{"".join(blocks)}
<p><small>Métrica en metrics.json: distancia euclídea de cada píxel del contorno del dibujo al borde más cercano del alpha del render (y a la inversa), IoU de las máscaras rellenas. La vista frontal es cualitativa: las palas dibujadas no se separan del cuerpo.</small></p></main>
<script>const $=s=>document.querySelector(s);let mode='both';function update(){{const o=Number($('#opacity').value)/100;document.querySelectorAll('.photo').forEach(e=>e.style.display=mode==='model'?'none':'');
document.querySelectorAll('.after').forEach(e=>{{e.setAttribute('opacity',mode==='photo'?0:mode==='model'?1:o);e.setAttribute('filter',$('#contour').checked?'url(#edge)':'none');}});
document.querySelectorAll('.before').forEach(e=>e.setAttribute('opacity',$('#before').checked&&mode!=='photo'?o:0));$('#value').textContent=$('#opacity').value+'%';
document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.mode===mode));}}
document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{{mode=b.dataset.mode;update();}});for(const id of ['opacity','contour','before'])$('#'+id).oninput=update;update();</script></html>'''
    (output / "index.html").write_text(page)


if __name__ == "__main__":
    main()
