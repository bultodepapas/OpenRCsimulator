#!/usr/bin/env python3
"""Validate a showcase manifest and write its self-contained offline gallery."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import struct
from pathlib import Path
from urllib.parse import quote


CATEGORIES = ("General", "Motor", "Montaje", "Servos", "Mandos")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as source:
        header = source.read(24)
    if len(header) < 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError(f"Not a valid PNG header: {path}")
    width, height = struct.unpack(">II", header[16:24])
    if width <= 0 or height <= 0:
        raise ValueError(f"Invalid PNG dimensions in {path}: {width}x{height}")
    return width, height


def declared_size(value: object, source: str) -> tuple[int, int] | None:
    if value is None:
        return None
    if (
        not isinstance(value, list)
        or len(value) != 2
        or any(not isinstance(part, int) or isinstance(part, bool) or part <= 0 for part in value)
    ):
        raise ValueError(f"Invalid pixel resolution at {source}: {value!r}")
    return value[0], value[1]


def validate_manifest(manifest_path: Path) -> tuple[dict, list[dict]]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Could not read manifest {manifest_path}: {error}") from error
    if not isinstance(manifest, dict):
        raise ValueError("Manifest root must be a JSON object")
    captures = manifest.get("captures")
    if not isinstance(captures, list) or not captures:
        raise ValueError("Manifest must contain a non-empty captures array")
    if "capture_count" in manifest and manifest["capture_count"] != len(captures):
        raise ValueError("capture_count does not match the captures array")

    design = manifest.get("capture_design", {})
    if not isinstance(design, dict):
        raise ValueError("capture_design must be a JSON object")
    root_size = declared_size(manifest.get("resolution_px"), "resolution_px")
    design_size = declared_size(design.get("resolution_px"), "capture_design.resolution_px")
    image_root = manifest_path.parent.resolve()
    validated: list[dict] = []

    for index, capture in enumerate(captures):
        label = f"captures[{index}]"
        if not isinstance(capture, dict):
            raise ValueError(f"{label} must be a JSON object")
        filename = capture.get("file")
        if not isinstance(filename, str) or not filename or Path(filename).is_absolute():
            raise ValueError(f"{label}.file must be a relative PNG filename")
        relative_file = Path(filename)
        if relative_file.suffix.lower() != ".png" or ".." in relative_file.parts:
            raise ValueError(f"{label}.file must be a safe relative PNG path: {filename!r}")
        image_path = (manifest_path.parent / relative_file).resolve()
        try:
            image_path.relative_to(image_root)
        except ValueError as error:
            raise ValueError(f"{label}.file escapes the manifest directory: {filename!r}") from error
        if not image_path.is_file():
            raise ValueError(f"Missing capture image for {label}: {image_path}")

        expected_hash = capture.get("png_sha256")
        if not isinstance(expected_hash, str) or re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash) is None:
            raise ValueError(f"{label}.png_sha256 must be a 64-digit SHA-256")
        actual_hash = sha256(image_path)
        if actual_hash.lower() != expected_hash.lower():
            raise ValueError(f"SHA-256 mismatch for {image_path}")

        camera = capture.get("camera", {})
        if not isinstance(camera, dict):
            raise ValueError(f"{label}.camera must be a JSON object")
        sizes = [
            declared_size(capture.get("resolution_px"), f"{label}.resolution_px"),
            declared_size(camera.get("viewport_px"), f"{label}.camera.viewport_px"),
            root_size,
            design_size,
        ]
        declared = [size for size in sizes if size is not None]
        if not declared:
            raise ValueError(f"{label} has no declared pixel resolution")
        if any(size != declared[0] for size in declared[1:]):
            raise ValueError(f"Conflicting declared pixel resolutions for {image_path}: {declared}")
        actual_size = png_dimensions(image_path)
        if actual_size != declared[0]:
            raise ValueError(
                f"PNG resolution mismatch for {image_path}: expected {declared[0]}, found {actual_size}"
            )

        category = capture.get("category") or "General"
        if not isinstance(category, str) or category not in CATEGORIES:
            raise ValueError(f"Unsupported category in {label}: {category!r}")
        condition = capture.get("condition")
        if not isinstance(condition, str) or not condition.strip():
            condition = "Vista del modelo"
        detail = capture.get("detail")
        if not isinstance(detail, str):
            detail = ""

        validated.append(
            {
                "category": category,
                "condition": condition.strip(),
                "detail": detail.strip(),
                "file": image_path,
            }
        )
    return manifest, validated


def relative_href(source: Path, target: Path) -> str:
    return quote(Path(os.path.relpath(target, source)).as_posix(), safe="/.-_~")


def build_gallery(manifest_path: Path, output_path: Path, captures: list[dict]) -> str:
    cards = []
    for index, capture in enumerate(captures):
        condition = html.escape(capture["condition"], quote=True)
        detail = html.escape(capture["detail"])
        category = html.escape(capture["category"], quote=True)
        image_href = html.escape(relative_href(output_path.parent, capture["file"]), quote=True)
        search = html.escape(f"{capture['condition']} {capture['detail']} {capture['category']}".lower(), quote=True)
        detail_html = f"<p class=detail>{detail}</p>" if detail else ""
        cards.append(
            f'<article class=card data-category="{category}" data-search="{search}">'
            f'<a class=photo href="{image_href}" target="_blank" rel="noopener" '
            f'title="Abrir PNG original en resolución completa">'
            f'<img loading="lazy" src="{image_href}" alt="{condition}"></a>'
            f'<h2>{condition}</h2>{detail_html}'
            f'<p class=category>{category}</p>'
            f'<button class=preview type=button data-index="{index}">Ver en galería</button>'
            "</article>"
        )

    manifest_href = html.escape(relative_href(output_path.parent, manifest_path), quote=True)
    category_buttons = ['<button class=category-filter data-category="Todas">Todas</button>']
    category_buttons.extend(
        f'<button class=category-filter data-category="{category}">{category}</button>'
        for category in CATEGORIES
    )
    category_html = "\n".join(category_buttons)
    cards_html = "\n".join(cards)
    return f"""<!doctype html>
<html lang=es>
<meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Ugly Stik · galería de detalles</title>
<style>
:root{{color-scheme:dark;font:16px system-ui,sans-serif;background:#111820;color:#eef2f5}}
*{{box-sizing:border-box}}body{{margin:0}}header{{position:sticky;top:0;z-index:2;padding:16px 22px;background:#17212b;border-bottom:1px solid #34404b}}
h1{{font-size:23px;margin:0 0 10px}}.toolbar{{display:flex;gap:8px;flex-wrap:wrap;align-items:center}}
button,input{{font:inherit;color:inherit;background:#253341;border:1px solid #526273;border-radius:6px;padding:8px 11px}}
button{{cursor:pointer}}button.active{{background:#a91d31;border-color:#f66}}input{{min-width:220px;flex:1}}
a{{color:#aad6ff}}.manifest{{margin-left:auto}}main{{padding:20px 22px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(245px,1fr));gap:15px}}
.card{{background:#1b2630;border:1px solid #33414d;border-radius:9px;padding:11px;min-width:0}}
.photo{{display:block;background:#0d1319;border-radius:6px;overflow:hidden}}.photo img{{display:block;width:100%;height:auto}}
.card h2{{font-size:17px;margin:10px 0 4px}}.detail{{color:#c5ced6;margin:4px 0 8px;min-height:1.3em}}
.category{{color:#aebdca;font-size:14px;margin:6px 0}}.preview{{width:100%}}.hidden{{display:none!important}}
dialog{{width:min(96vw,1500px);max-width:96vw;max-height:96vh;background:#111820;color:#eef2f5;border:1px solid #667;border-radius:9px;padding:14px}}
dialog::backdrop{{background:#000c}}.viewer-image{{display:flex;align-items:center;justify-content:center;max-height:78vh;overflow:auto}}
.viewer-image img{{display:block;max-width:100%;max-height:76vh;object-fit:contain}}.viewer-bar{{display:flex;gap:10px;align-items:center;justify-content:space-between;margin-top:10px}}
.viewer-title{{flex:1;text-align:center}}footer{{padding:18px 22px;color:#aebdca;border-top:1px solid #34404b}}
</style>
<header>
  <h1>Jensen Ugly Stik · detalles del modelo</h1>
  <div class=toolbar aria-label="Filtros de galería">
    {category_html}
    <input id=search type=search placeholder="Filtrar por nombre o detalle" aria-label="Filtrar por nombre o detalle">
    <a class=manifest href="{manifest_href}">Manifiesto técnico (JSON)</a>
  </div>
</header>
<main><div id=gallery class=grid>{cards_html}</div></main>
<footer>Selecciona una imagen para abrir el PNG original a tamaño completo; usa “Ver en galería” para recorrer las vistas.</footer>
<dialog id=viewer aria-label="Visor de imágenes">
  <div class=viewer-image><a id=original href target=_blank rel=noopener><img id=large alt=""></a></div>
  <div class=viewer-bar>
    <button id=previous type=button>Anterior</button>
    <span id=viewer-title class=viewer-title></span>
    <button id=next type=button>Siguiente</button>
    <button id=close type=button>Cerrar</button>
  </div>
</dialog>
<script>
const cards=[...document.querySelectorAll('.card')];
const categoryButtons=[...document.querySelectorAll('.category-filter')];
const search=document.querySelector('#search');
const viewer=document.querySelector('#viewer');
const large=document.querySelector('#large');
const original=document.querySelector('#original');
const viewerTitle=document.querySelector('#viewer-title');
let category='Todas', current=0;
function visibleCards(){{
  const query=search.value.trim().toLocaleLowerCase('es');
  return cards.filter(card=>(category==='Todas'||card.dataset.category===category)&&(!query||card.dataset.search.includes(query)));
}}
function filter(){{
  const visible=new Set(visibleCards());
  cards.forEach(card=>card.classList.toggle('hidden',!visible.has(card)));
}}
function showCard(card){{
  const image=card.querySelector('.photo');
  large.src=image.href;
  large.alt=card.querySelector('h2').textContent;
  original.href=image.href;
  viewerTitle.textContent=card.querySelector('h2').textContent;
  current=visibleCards().indexOf(card);
  if(!viewer.open)viewer.showModal();
}}
categoryButtons.forEach(button=>button.addEventListener('click',()=>{{
  category=button.dataset.category;
  categoryButtons.forEach(item=>item.classList.toggle('active',item===button));
  filter();
}}));
search.addEventListener('input',filter);
cards.forEach(card=>card.querySelector('.preview').addEventListener('click',()=>showCard(card)));
function step(delta){{
  const visible=visibleCards();
  if(!visible.length)return;
  current=(current+delta+visible.length)%visible.length;
  showCard(visible[current]);
}}
document.querySelector('#previous').addEventListener('click',()=>step(-1));
document.querySelector('#next').addEventListener('click',()=>step(1));
document.querySelector('#close').addEventListener('click',()=>viewer.close());
document.addEventListener('keydown',event=>{{
  if(!viewer.open)return;
  if(event.key==='ArrowLeft')step(-1);
  if(event.key==='ArrowRight')step(1);
}});
categoryButtons[0].classList.add('active');
filter();
</script>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="capture manifest.json")
    parser.add_argument("--output", type=Path, help="HTML destination (default: review.html beside the manifest)")
    args = parser.parse_args()

    manifest_path = args.manifest.resolve()
    output_path = (args.output or manifest_path.with_name("review.html")).resolve()
    try:
        _, captures = validate_manifest(manifest_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(build_gallery(manifest_path, output_path, captures), encoding="utf-8")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"Wrote offline gallery for {len(captures)} images: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
