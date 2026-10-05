#!/usr/bin/env python3
"""Build a small offline review gallery and diagnostic image comparison."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import runpy
import sys
from pathlib import Path

import PIL
from PIL import Image, ImageChops, ImageEnhance, ImageStat


EXPECTED_COUNTS = {
    "inspection": 9,
    "readability36": 36,
    "details": 12,
    "motion": 36,
    "beauty": 2,
}
BASELINE_IMAGES = ("top.png", "side.png", "three-quarter-neutral.png")
CAPTION_CUTOFF_PX = 90


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_suite(root: Path, suite: str) -> list[dict]:
    manifest_path = root / suite / "manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"Missing suite manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    captures = manifest.get("captures", [])
    if manifest.get("capture_count", len(captures)) != len(captures):
        raise ValueError(f"{suite}: capture_count does not match manifest captures")
    if len(captures) != EXPECTED_COUNTS[suite]:
        raise ValueError(f"{suite}: expected {EXPECTED_COUNTS[suite]} captures, found {len(captures)}")
    for capture in captures:
        filename = str(capture.get("file", ""))
        if not filename or Path(filename).name != filename:
            raise ValueError(f"{suite}: invalid capture filename {filename!r}")
        image_path = root / suite / filename
        if not image_path.is_file():
            raise ValueError(f"{suite}: missing capture image {image_path}")
        capture["_image_path"] = image_path
        capture["_suite"] = suite
    return captures


def find_baseline_image(baseline: Path, filename: str) -> Path | None:
    candidates = (
        baseline / "inspection" / filename,
        baseline / "captures" / "inspection" / filename,
        baseline / "captures" / filename,
        baseline / filename,
    )
    return next((candidate for candidate in candidates if candidate.is_file()), None)


def compare_baseline(root: Path, baseline: Path, out_dir: Path) -> dict:
    differences_dir = out_dir / "differences"
    differences_dir.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []
    for filename in BASELINE_IMAGES:
        current_path = root / "inspection" / filename
        baseline_path = find_baseline_image(baseline, filename)
        item = {
            "file": filename,
            "baseline_file": str(baseline_path.relative_to(baseline)) if baseline_path else None,
            "current_file": f"inspection/{filename}",
        }
        if baseline_path is None:
            item["status"] = "baseline_missing"
            results.append(item)
            continue

        with Image.open(baseline_path) as old_image, Image.open(current_path) as new_image:
            old = old_image.convert("RGB")
            new = new_image.convert("RGB")
        if old.size != new.size:
            item.update(status="size_mismatch", baseline_size_px=list(old.size), current_size_px=list(new.size))
            results.append(item)
            continue
        cutoff = min(CAPTION_CUTOFF_PX, old.height)
        old_region = old.crop((0, cutoff, old.width, old.height))
        new_region = new.crop((0, cutoff, new.width, new.height))
        diff_region = ImageChops.difference(old_region, new_region)
        stats = ImageStat.Stat(diff_region)
        pixels = max(1, diff_region.width * diff_region.height)
        changed_pixels = sum(1 for pixel in diff_region.getdata() if pixel != (0, 0, 0))
        full_diff = Image.new("RGB", old.size, (0, 0, 0))
        full_diff.paste(ImageEnhance.Brightness(diff_region).enhance(4.0), (0, cutoff))
        diff_name = Path(filename).stem + "-diff-x4.png"
        full_diff.save(differences_dir / diff_name, format="PNG", optimize=False)
        item.update(
            status="compared",
            difference_file=f"differences/{diff_name}",
            size_px=list(old.size),
            region_px={"left": 0, "top": cutoff, "right": old.width, "bottom": old.height},
            mean_absolute_channel_difference=sum(stats.mean) / 3.0,
            rms_channel_difference=sum(stats.rms) / 3.0,
            changed_pixel_count=changed_pixels,
            changed_pixel_fraction=changed_pixels / pixels,
            difference_display_gain=4.0,
        )
        results.append(item)
    return {
        "baseline_root": str(baseline),
        "caption_rows_excluded": CAPTION_CUTOFF_PX,
        "difference_metrics_use_unamplified_pixels": True,
        "comparisons": results,
    }


def compare_repeat(primary_dir: Path, repeat_dir: Path) -> dict:
    def files_by_name(directory: Path) -> dict[str, Path]:
        manifest_path = directory / "manifest.json"
        if not manifest_path.is_file():
            raise ValueError(f"Missing repeat manifest: {manifest_path}")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        records = manifest.get("captures", [])
        return {str(record.get("file", "")): directory / str(record.get("file", "")) for record in records}

    primary = files_by_name(primary_dir)
    repeat = files_by_name(repeat_dir)
    expected = EXPECTED_COUNTS["readability36"]
    names = sorted(set(primary) | set(repeat))
    missing_primary = [name for name in names if not primary.get(name, Path()).is_file()]
    missing_repeat = [name for name in names if not repeat.get(name, Path()).is_file()]
    mismatches = []
    for name in sorted(set(primary) & set(repeat)):
        left = primary[name]
        right = repeat[name]
        if left.is_file() and right.is_file() and sha256(left) != sha256(right):
            mismatches.append(name)
    matches = len(primary) == expected and len(repeat) == expected and not missing_primary and not missing_repeat and not mismatches
    return {
        "expected_png_count": expected,
        "primary_png_count": len(primary),
        "repeat_png_count": len(repeat),
        "exact_png_hashes_match": matches,
        "missing_primary": missing_primary,
        "missing_repeat": missing_repeat,
        "hash_mismatches": mismatches,
        "comparison_method": "SHA-256 over each PNG byte stream; the repeated readability36 run is temporary.",
    }


def capture_card(capture: dict) -> str:
    suite = html.escape(capture["_suite"], quote=True)
    relative_image = html.escape(f"{suite}/{capture['file']}", quote=True)
    title = html.escape(str(capture.get("condition", capture.get("case_id", capture["file"]))))
    case_id = html.escape(str(capture.get("case_id", "")))
    crop = "crop previsto" if capture.get("expected_crop", False) else "encuadre completo"
    if capture.get("actual_visible_geometry_crop_detected", False):
        crop += " · geometría visible recortada"
    meta = [html.escape(crop)]
    if capture.get("motion_kind"):
        meta.append(html.escape(str(capture["motion_kind"])))
        nominal = capture.get("motion_time_s")
        timestep = capture.get("fixed_timestep_s")
        if nominal is not None and timestep is not None:
            meta.append(f"t nominal {float(nominal):.4f} s · Δt {float(timestep):.5f} s")
    meta_text = " · ".join(meta)
    return (
        f'<article class="card" data-suite="{suite}" data-kind="{html.escape(str(capture.get("motion_kind", "")), quote=True)}" '
        f'data-title="{title.lower()} {case_id.lower()}">'
        f'<button class="image-button" data-image="{relative_image}" data-title="{title}" data-meta="{html.escape(meta_text, quote=True)}">'
        f'<img loading="lazy" src="{relative_image}" alt="{title}"></button>'
        f'<h3>{title}</h3><p>{case_id}</p><small>{meta_text}</small></article>'
    )


def write_gallery(root: Path, captures: dict[str, list[dict]], comparisons: dict) -> None:
    cards = "\n".join(capture_card(capture) for suite in EXPECTED_COUNTS for capture in captures[suite])
    tabs = ['<button class="tab active" data-suite="all">Todo</button>']
    tabs.extend(f'<button class="tab" data-suite="{suite}">{suite} ({EXPECTED_COUNTS[suite]})</button>' for suite in EXPECTED_COUNTS)
    comparison_cards = []
    for item in comparisons["comparisons"]:
        if item.get("status") == "compared":
            image_path = html.escape(str(item["difference_file"]), quote=True)
            filename = html.escape(str(item["file"]))
            mean = float(item["mean_absolute_channel_difference"])
            changed = float(item["changed_pixel_fraction"]) * 100.0
            comparison_cards.append(
                f'<article><img loading="lazy" src="{image_path}" alt="Diferencia {filename}">'
                f'<h3>{filename}</h3><p>MAE sin amplificar: {mean:.4f} · píxeles con diferencia: {changed:.2f}%</p></article>'
            )
        else:
            comparison_cards.append(f'<p>{html.escape(str(item["file"]))}: {html.escape(str(item["status"]))}</p>')
    comparison_html = "\n".join(comparison_cards) or "<p>Comparación v3 no disponible.</p>"
    version = html.escape(PIL.__version__)
    document = f"""<!doctype html>
<html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenRC · galería de modelo v4</title>
<style>
:root{{color-scheme:dark;font:15px system-ui,sans-serif;background:#111820;color:#eef2f5}}
body{{margin:0}}header{{position:sticky;top:0;z-index:2;padding:16px 22px;background:#17212b;border-bottom:1px solid #34404b}}
h1{{margin:0 0 8px;font-size:23px}}p{{color:#bdc7d1}}.note{{max-width:1000px;margin:8px 0}}
nav,.filters{{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}}button,input,select{{font:inherit;color:inherit;background:#253341;border:1px solid #526273;border-radius:6px;padding:7px 10px}}
.tab.active{{background:#a91d31;border-color:#f66}}main{{padding:18px 22px}}.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px}}
.card,section article{{background:#1b2630;border:1px solid #33414d;border-radius:8px;padding:10px;min-width:0}}.card img{{display:block;width:100%;height:auto;border-radius:4px}}
.image-button{{display:block;width:100%;padding:0;border:0;background:transparent;cursor:zoom-in}}h3{{font-size:15px;margin:8px 0 3px}}.card p,.card small{{display:block;margin:3px 0;color:#bbc5ce}}
section{{margin:28px 0}}section .grid{{grid-template-columns:repeat(auto-fit,minmax(260px,420px))}}.hidden{{display:none!important}}
dialog{{max-width:95vw;max-height:95vh;background:#111820;color:#eef2f5;border:1px solid #667;border-radius:8px;padding:12px}}
dialog img{{display:block;max-width:90vw;max-height:78vh;object-fit:contain}}.modal-bar{{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-top:8px}}
footer{{padding:18px 22px;border-top:1px solid #34404b;color:#bdc7d1}}
</style>
<header><h1>Jensen Ugly Stik · evidencia visual v4</h1>
<p class="note">Comparación visual y diagnóstico offline. Los valores y diferencias no son una aprobación automática ni usan umbrales.</p>
<p class="note">Movimiento: las etiquetas t nominal y Δt describen muestras fijas. El control de presentación cambia diapositivas a 700 ms; ese intervalo no es tiempo de simulación ni tiempo real del movimiento.</p>
<nav>{''.join(tabs)}</nav><div class="filters"><input id="search" type="search" placeholder="Filtrar por nombre"><select id="motion-kind"><option value="all">Todos los grupos de motion</option><option value="control_pose">Poses de mandos</option><option value="maintenance_control_pose">Mandos con mantenimiento abierto</option><option value="camera_sweep">Desplazamiento de cámara</option></select><button id="play">Iniciar slideshow de motion</button><span id="status"></span></div></header>
<main><p><a href="readability36/review.html">Ensayo de orientación: responder antes de revelar la clave</a></p><div id="gallery" class="grid">{cards}</div>
<section><h2>Diferencias diagnósticas frente a v3</h2><p>Se excluyen filas y&gt;=0 hasta y=89 para quitar captions. Las imágenes de diferencia se muestran con ganancia ×4; las métricas se calculan con los valores originales de ImageChops.</p><div class="grid">{comparison_html}</div></section>
</main><footer>Pillow {version} · diferencias Pillow ImageChops · revisión humana requerida para interpretar cada región.</footer>
<dialog id="viewer"><button id="close" style="float:right">Cerrar</button><img id="large" alt=""><div class="modal-bar"><button id="prev">Anterior</button><span id="modal-title"></span><button id="next">Siguiente</button></div><p id="modal-meta"></p></dialog>
<script>
const tabs=[...document.querySelectorAll('.tab')], cards=[...document.querySelectorAll('.card')], search=document.querySelector('#search'), kind=document.querySelector('#motion-kind');
let suite='all', current=0, timer=null;
function visibleCards(){{const q=search.value.toLowerCase();return cards.filter(c=>(suite==='all'||c.dataset.suite===suite)&&(!q||c.dataset.title.includes(q))&&(suite!=='motion'||kind.value==='all'||c.dataset.kind===kind.value));}}
function filter(){{for(const c of cards)c.classList.toggle('hidden',!visibleCards().includes(c));document.querySelector('#play').classList.toggle('hidden',suite!=='motion');kind.classList.toggle('hidden',suite!=='motion');}}
tabs.forEach(t=>t.addEventListener('click',()=>{{suite=t.dataset.suite;tabs.forEach(x=>x.classList.toggle('active',x===t));if(timer){{clearInterval(timer);timer=null;document.querySelector('#play').textContent='Iniciar slideshow de motion';}}filter();}}));
search.addEventListener('input',filter);kind.addEventListener('change',filter);
const dialog=document.querySelector('#viewer'), large=document.querySelector('#large'), title=document.querySelector('#modal-title'), meta=document.querySelector('#modal-meta');
function openCard(card){{const b=card.querySelector('.image-button');large.src=b.dataset.image;large.alt=b.dataset.title;title.textContent=b.dataset.title;meta.textContent=b.dataset.meta;current=visibleCards().indexOf(card);dialog.showModal();}}
cards.forEach(c=>c.querySelector('.image-button').addEventListener('click',()=>openCard(c)));
function step(delta){{const list=visibleCards();if(!list.length)return;current=(current+delta+list.length)%list.length;openCard(list[current]);}}
document.querySelector('#prev').onclick=()=>step(-1);document.querySelector('#next').onclick=()=>step(1);document.querySelector('#close').onclick=()=>dialog.close();
dialog.addEventListener('close',()=>{{if(timer){{clearInterval(timer);timer=null;}}document.querySelector('#play').textContent='Iniciar slideshow de motion';}});
document.querySelector('#play').onclick=()=>{{if(timer){{clearInterval(timer);timer=null;document.querySelector('#play').textContent='Iniciar slideshow de motion';return;}}suite='motion';tabs.forEach(x=>x.classList.toggle('active',x.dataset.suite==='motion'));filter();const list=visibleCards();if(!list.length)return;openCard(list[0]);document.querySelector('#play').textContent='Detener slideshow';timer=setInterval(()=>step(1),700);}};
document.addEventListener('keydown',e=>{{if(e.key==='ArrowRight'&&dialog.open)step(1);if(e.key==='ArrowLeft'&&dialog.open)step(-1);}});filter();
</script></html>"""
    (root / "review.html").write_text(document, encoding="utf-8")


def write_orientation_review(root: Path, baseline: Path) -> None:
    # Reuse the existing blind-response form without changing historical evidence.
    renderer = runpy.run_path(str(baseline / "make_review_kit.py"))["render_page"]
    path = root / "readability36/manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["human_review"] = {"status": "pending", "pilot_response_count": 0, "response_kit": "review.html"}
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    document = renderer(manifest).replace("status: 'pending_until_reviewed_by_owner',", "status: 'pending_until_reviewed_by_owner',\n      visual_revision: " + json.dumps(manifest["visual_revision"]) + ",\n      manifest_sha256: " + json.dumps(sha256(path)) + ",")
    document = document.replace("us06-pilot-responses.json", "us06-v4-pilot-responses.json")
    (path.parent / "review.html").write_text(document, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path, help="Evidence root containing inspection/readability36/details/motion/beauty")
    parser.add_argument("--baseline", type=Path, help="v3 evidence root; defaults to a sibling model-v3 directory")
    parser.add_argument("--repeat-dir", type=Path, help="temporary second readability36 capture directory for exact PNG hash comparison")
    args = parser.parse_args()
    if PIL.__version__ != "11.3.0":
        raise SystemExit(f"Pillow version mismatch: required 11.3.0, found {PIL.__version__}")
    root = args.root.resolve()
    baseline = args.baseline.resolve() if args.baseline else root.parent / "model-v3"
    repository_baseline = baseline / "research" / "ugly-stik" / "model-v3"
    if repository_baseline.is_dir():
        baseline = repository_baseline
    captures = {suite: read_suite(root, suite) for suite in EXPECTED_COUNTS}
    comparisons = compare_baseline(root, baseline, root)
    comparisons["repeat_readability36"] = compare_repeat(root / "readability36", args.repeat_dir.resolve()) if args.repeat_dir else None
    comparisons["dependency"] = {"name": "Pillow", "required_version": "11.3.0", "installed_version": PIL.__version__, "exact_version_match": True}
    comparisons["approval_threshold_used"] = False
    comparisons["interpretation"] = "Image differences and summary metrics are diagnostic only; no approval threshold is applied."
    (root / "comparison.json").write_text(json.dumps(comparisons, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_gallery(root, captures, comparisons)
    write_orientation_review(root, baseline)
    repeat = comparisons["repeat_readability36"]
    if repeat is not None and not repeat["exact_png_hashes_match"]:
        print("readability36 repeat PNG hashes differ; see comparison.json", file=sys.stderr)
        return 1
    print(f"Pillow {PIL.__version__}; wrote {root / 'review.html'}")
    print("Capture counts: " + ", ".join(f"{name}={len(captures[name])}" for name in EXPECTED_COUNTS))
    if repeat is not None:
        print("readability36 repeated PNG hashes: exact match (36/36)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
