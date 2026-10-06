#!/usr/bin/env python3
"""L6c: the airplane against the treeline, the treetop edge, the sky and the grass, at 100 m from the pilot.

Numbers (the L0c metric plus what the surrounding pixels are) are recorded for Gate L, not enforced. The only
guards check that every case is what its name says: the airplane is found, and its surroundings are mostly the
intended background. The 24 game-view images (six attitudes × four backgrounds) also become the blinded kit for
the human playtest of VISUAL-QUALITY-PLAN §8: numbered copies in a fixed order that is independent of the case
names, the answer key kept apart, a viewer that writes a response sheet, and a scorer (≥ 22/24 to pass).

    python3 app/tests/treeline_readability.py capture --app app --godot "$(app/get-godot.sh)" --out app/captures/l6c
    python3 app/tests/treeline_readability.py score <responses.csv> --kit app/captures/l6c/kit

Run with the pinned environment from app/tests/visual-env.sh (Pillow, numpy).
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import html
import json
import math
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
from typing import Any

import numpy as np

from capture_runner import run_capture
from compare_captures import difference_mask, load, measure_pair
import visual_quality_cases as vq

FORMAT = "openrc-l6c-readability v1"
KIT_FORMAT = "openrc-l6c-kit v1"
KEY_FORMAT = "openrc-l6c-kit-key v1"
SCORE_FORMAT = "openrc-l6c-score v1"
FAMILY = "treeline-readability"
DISTANCE_M = 100.0
AIRCRAFT_ID = "jensen-das-ugly-stik-60"
POSES = vq.POSES
# Where the airplane is seen from the pilot's eyes: azimuth from north and the CG's elevation above the eyes
# (degrees), side-on with the nose to the pilot's right. Design values measured on wide renders of the committed
# L6b treeline (docs/research/visual-quality-implementation/L6c): due north the trees are sparse and gapped at
# 100 m, at azimuth 9° a solid tree band fills 0.5–4.1° of elevation. So 2.3° centres the airplane in the trees,
# 4.1° sits it on the treetop edge, 10° is VQ-01b's clear sky and −0.5° puts the CG 0.83 m over the grass (a
# knife-edge wingtip keeps 7 cm; the trunks 300 m behind show above its top rows). The same azimuth and light for
# all four. `expected` is the minimum share of the ring around the airplane that must be that background for the
# case to count (a guard on the case, not a quality threshold).
AZIMUTH_DEG = 9.0
BACKGROUNDS: dict[str, dict[str, Any]] = {
    "sky": {"elevation_deg": 10.0, "expected": {"sky": 0.9}},
    "horizon": {"elevation_deg": 4.1, "expected": {"sky": 0.15, "trees": 0.15}},
    "trees": {"elevation_deg": 2.3, "expected": {"trees": 0.6}},
    "ground": {"elevation_deg": -0.5, "expected": {"ground": 0.6}},
}
# game: auto-zoom on, what the pilot sees (the FOV narrows so the span covers 30 px); fixed: the 50° L0c fixture.
VIEWS = {"game": True, "fixed": False}
REFERENCES = {"noplane": ("--hide_airplane",), "notrees": ("--hide_airplane", "--hide_treeline")}
KIT_VIEW = "game"
KIT_SEED = 20261006  # fixes the blinded order; it has nothing to do with any render seed
KIT_PASS = 22
KIT_FLIGHT_ROWS = ("flight-pass", "flight-turn")
ANSWER_LABELS = {
    "level": "Horizontal, derecho", "inverted": "Horizontal, invertido",
    "knife_left": "Cuchillo, panza hacia la izquierda", "knife_right": "Cuchillo, panza hacia la derecha",
    "climb": "Morro arriba 45°", "dive": "Morro abajo 45°",
}


def group_id(view: str, background: str) -> str:
    return f"{view}-{background}"


def capture_cases() -> list[vq.CaptureCase]:
    """The fixed, ordered inventory: per view and background, two references then the six attitudes (64 cases)."""
    cases: list[vq.CaptureCase] = []
    for view, autozoom in VIEWS.items():
        for background, spec in BACKGROUNDS.items():
            group = group_id(view, background)
            base = (
                "--scripted", f"--visual_distance={DISTANCE_M:g}", f"--visual_elevation={spec['elevation_deg']:g}",
                f"--visual_azimuth={AZIMUTH_DEG:g}", f"--autozoom={1 if autozoom else 0}", "--shadow=off",
                f"--aircraft={AIRCRAFT_ID}", "--t=1.5",
            )
            for reference, extra in REFERENCES.items():
                case_id = f"l6c-{group}-{reference}"
                cases.append(vq.CaptureCase(
                    case_id=case_id, family=FAMILY, aircraft=AIRCRAFT_ID, route="synthetic-inspection",
                    arguments=("--visual_pose=level", *base, *extra, f"--case={case_id}"),
                    repeat_group=group, visual_pose="level", visual_distance_m=DISTANCE_M,
                    pilot_visible=False, autozoom=autozoom,
                ))
            for pose in POSES:
                case_id = f"l6c-{group}-{pose}"
                cases.append(vq.CaptureCase(
                    case_id=case_id, family=FAMILY, aircraft=AIRCRAFT_ID, route="synthetic-inspection",
                    arguments=(f"--visual_pose={pose}", *base, f"--case={case_id}"),
                    repeat_group=group, visual_pose=pose, visual_distance_m=DISTANCE_M,
                    pilot_visible=True, autozoom=autozoom,
                ))
    return cases


def validate_evidence(case: vq.CaptureCase, manifest: dict[str, Any]) -> dict[str, Any]:
    """VQ-01b's checks plus L6c's: the elevation that was rendered and whether the trees were there."""
    evidence = vq.validate_capture_evidence(case, manifest)
    background = case.repeat_group.split("-", 1)[1]
    elevation = vq._number(evidence.get("visual_elevation_deg"), f"{case.case_id} visual_elevation_deg")
    if abs(elevation - BACKGROUNDS[background]["elevation_deg"]) > 1e-6:
        raise RuntimeError(f"{case.case_id}: rendered elevation {elevation} deg, expected {BACKGROUNDS[background]['elevation_deg']}")
    azimuth = vq._number(evidence.get("visual_azimuth_deg"), f"{case.case_id} visual_azimuth_deg")
    if abs(azimuth - AZIMUTH_DEG) > 1e-6:
        raise RuntimeError(f"{case.case_id}: rendered azimuth {azimuth} deg, expected {AZIMUTH_DEG}")
    trees_visible = evidence["state"].get("treeline_visible")
    if type(trees_visible) is not bool:
        raise RuntimeError(f"{case.case_id}: state.treeline_visible must be boolean")
    if trees_visible is case.case_id.endswith("-notrees"):
        raise RuntimeError(f"{case.case_id}: treeline visibility {trees_visible} disagrees with the case")
    return evidence


def horizon_row(evidence: dict[str, Any]) -> float:
    """Image row of the true horizon for the recorded camera (vertical FOV; rows grow downwards)."""
    camera = evidence["camera"]
    z_axis = camera["transform"]["basis_columns"][2]
    forward_y = -float(z_axis[1])  # a Godot camera looks along −z
    pitch = math.asin(max(-1.0, min(1.0, forward_y)))
    height = float(camera["viewport"][1])
    focal = (height / 2.0) / math.tan(math.radians(float(camera["fov_deg"])) / 2.0)
    return height / 2.0 + focal * math.tan(pitch)


def check_background(case_id: str, background: str, composition: dict[str, Any]) -> None:
    for part, minimum in BACKGROUNDS[background]["expected"].items():
        if composition.get(part, 0.0) < minimum:
            raise RuntimeError(f"{case_id}: only {100 * composition.get(part, 0.0):.0f} % of the airplane's surroundings are "
                               f"{part} (the case needs ≥ {100 * minimum:.0f} %): {composition}")


def measure_group(output_dir: Path, view: str, background: str, evidence_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    group = group_id(view, background)
    with_trees = load(str(output_dir / f"l6c-{group}-noplane.png"))
    without_trees = load(str(output_dir / f"l6c-{group}-notrees.png"))
    tree_mask = difference_mask(with_trees, without_trees)
    reference = evidence_by_id[f"l6c-{group}-noplane"]
    row = horizon_row(reference)
    poses: dict[str, Any] = {}
    for pose in POSES:
        case_id = f"l6c-{group}-{pose}"
        result = measure_pair(load(str(output_dir / f"{case_id}.png")), with_trees, tree_mask, row)
        if result["pixels"] == 0:
            raise RuntimeError(f"{case_id}: the airplane is not visible (no difference from the view without it)")
        check_background(case_id, background, result["background"])
        poses[pose] = result
        print(f"{case_id}: {result['pixels']} px ({result['bbox_px']['width']}×{result['bbox_px']['height']}), "
              f"Weber {result['weber_contrast']:+.3f}, {100 * result['share_low_contrast']:.1f} % nearly invisible, "
              f"ΔE {result['delta_e']:.1f} (p10 {result['delta_e_p10']:.1f}), surroundings "
              f"{100 * result['background']['trees']:.0f} % trees / {100 * result['background']['sky']:.0f} % sky / "
              f"{100 * result['background']['ground']:.0f} % ground", flush=True)
    return {
        "view": view, "background": background, "autozoom": VIEWS[view],
        "elevation_deg": BACKGROUNDS[background]["elevation_deg"], "azimuth_deg": AZIMUTH_DEG, "distance_m": DISTANCE_M,
        "fov_deg": float(reference["camera"]["fov_deg"]), "horizon_row": round(row, 1),
        "tree_pixels_in_view": int(tree_mask.sum()),
        "poses": poses,
        "summary": {
            "weber_contrast_min": min(p["weber_contrast"] for p in poses.values()),
            "weber_contrast_max": max(p["weber_contrast"] for p in poses.values()),
            "weber_abs_min": min(abs(p["weber_contrast"]) for p in poses.values()),
            "share_low_contrast_max": max(p["share_low_contrast"] for p in poses.values()),
            "delta_e_min": min(p["delta_e"] for p in poses.values()),
            "delta_e_p10_min": min(p["delta_e_p10"] for p in poses.values()),
            "pixels_min": min(p["pixels"] for p in poses.values()),
            "pixels_max": max(p["pixels"] for p in poses.values()),
        },
    }


def kit_item_ids() -> list[str]:
    return [f"l6c-{group_id(KIT_VIEW, background)}-{pose}" for background in BACKGROUNDS for pose in POSES]


def kit_order() -> list[str]:
    order = kit_item_ids()
    random.Random(KIT_SEED).shuffle(order)
    return order


def build_kit(output_dir: Path, sha256_by_id: dict[str, str]) -> dict[str, Any]:
    """Numbered copies of the 24 game-view images, the key apart, a viewer and a response template."""
    kit = output_dir / "kit"
    shutil.rmtree(kit, ignore_errors=True)
    (kit / "images").mkdir(parents=True)
    (kit / "key").mkdir()
    items: list[dict[str, Any]] = []
    for number, case_id in enumerate(kit_order(), start=1):
        name = f"{number:02d}.png"
        shutil.copyfile(output_dir / f"{case_id}.png", kit / "images" / name)
        _, _, background, pose = case_id.split("-", 3)
        items.append({"image": name, "case_id": case_id, "background": background, "pose": pose,
                      "sha256": sha256_by_id[case_id]})
    key = {"format": KEY_FORMAT, "seed": KIT_SEED, "view": KIT_VIEW, "distance_m": DISTANCE_M, "azimuth_deg": AZIMUTH_DEG,
           "pass_correct": KIT_PASS, "total": len(items), "items": items}
    vq._write_json_atomic(kit / "key" / "answer-key.json", key)
    with (kit / "responses-template.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["image", "answer", "notes"])
        for item in items:
            writer.writerow([item["image"][:2], "", ""])
        for row in KIT_FLIGHT_ROWS:
            writer.writerow([row, "", ""])
    (kit / "index.html").write_text(viewer_html(len(items)), encoding="utf-8")
    (kit / "README.md").write_text(kit_readme(len(items)), encoding="utf-8")
    manifest = {
        "format": KIT_FORMAT, "view": KIT_VIEW, "distance_m": DISTANCE_M, "pass_correct": KIT_PASS,
        "images": [{"image": item["image"], "sha256": item["sha256"]} for item in items],
        "answer_key": "key/answer-key.json",
        "answer_key_sha256": vq.sha256_file(kit / "key" / "answer-key.json"),
        "viewer": "index.html", "responses_template": "responses-template.csv",
    }
    vq._write_json_atomic(kit / "kit.json", manifest)
    return manifest


def viewer_html(count: int) -> str:
    options = "".join(
        f'<button data-answer="{answer}"><kbd>{index + 1}</kbd> {html.escape(label)}</button>'
        for index, (answer, label) in enumerate(ANSWER_LABELS.items())
    )
    flight_rows = "".join(
        f'<tr><td>{row}</td><td><select data-flight="{row}"><option value="">—</option>'
        + "".join(f'<option value="{rating}">{rating}</option>' for rating in range(1, 6))
        + f'</select></td><td><input data-flight-notes="{row}" placeholder="notas"></td></tr>'
        for row in KIT_FLIGHT_ROWS
    )
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>L6c kit de actitudes</title>
<style>
body{{margin:0;background:#111;color:#ddd;font:15px/1.4 system-ui,sans-serif}}
main{{max-width:1280px;margin:0 auto;padding:12px}}
img{{display:block;width:1280px;max-width:100%;height:auto;image-rendering:auto;background:#000}}
.bar{{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:10px 0}}
button{{font:inherit;padding:8px 12px;border-radius:6px;border:1px solid #555;background:#222;color:#eee;cursor:pointer}}
button.on{{background:#2b6;color:#000;border-color:#2b6}} kbd{{opacity:.7}}
table{{border-collapse:collapse;margin-top:12px}} td{{padding:4px 8px;border-bottom:1px solid #333}}
textarea{{width:100%;height:120px;background:#000;color:#ccc;font:12px monospace}}
.muted{{color:#999}}
</style></head><body><main>
<h1>Lectura de actitud a 100 m · {count} imágenes</h1>
<p class="muted">Mira cada imagen como en vuelo (unos segundos) y elige la actitud del avión. La vista es la del juego
(autozoom). Ver a zoom 100 % del navegador. Las respuestas se guardan en este navegador; al final descarga el CSV y
puntúalo con <code>treeline_readability.py score</code>. No abras <code>key/</code> hasta haber terminado.</p>
<div class="bar"><button id="prev">◀ Anterior</button><span id="pos"></span><button id="next">Siguiente ▶</button>
<span id="done" class="muted"></span></div>
<img id="img" alt="imagen del kit">
<div class="bar" id="answers">{options}</div>
<h2>Después, en el juego</h2>
<p class="muted">Vuela una pasada baja delante de los árboles (hacia el norte) y un viraje frente a ellos. Puntúa de 1
(no distingo la actitud) a 5 (la leo sin esfuerzo) y anota lo que te confunda.</p>
<table>{flight_rows}</table>
<div class="bar"><button id="download">Descargar responses.csv</button><button id="reset">Borrar respuestas</button></div>
<textarea id="csv" readonly></textarea>
<script>
const COUNT={count}, KEY="openrc-l6c-kit-responses";
let i=0, answers={{}}, flight={{}};
try{{const s=JSON.parse(localStorage.getItem(KEY)||"{{}}"); answers=s.answers||{{}}; flight=s.flight||{{}};}}catch(e){{}}
const id=n=>String(n).padStart(2,"0");
function save(){{try{{localStorage.setItem(KEY,JSON.stringify({{answers,flight}}));}}catch(e){{}} render();}}
function csv(){{const rows=[["image","answer","notes"]];for(let n=1;n<=COUNT;n++)rows.push([id(n),answers[id(n)]||"",""]);
 for(const r of {json.dumps(list(KIT_FLIGHT_ROWS))})rows.push([r,(flight[r]||{{}}).rating||"",(flight[r]||{{}}).notes||""]);
 return rows.map(r=>r.map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(",")).join("\\n")+"\\n";}}
function render(){{document.getElementById("img").src="images/"+id(i+1)+".png";
 document.getElementById("pos").textContent="Imagen "+id(i+1)+" de "+COUNT;
 const n=Object.keys(answers).filter(k=>answers[k]).length; document.getElementById("done").textContent=n+" respondidas";
 for(const b of document.querySelectorAll("#answers button"))b.classList.toggle("on",answers[id(i+1)]===b.dataset.answer);
 for(const s of document.querySelectorAll("select[data-flight]"))s.value=(flight[s.dataset.flight]||{{}}).rating||"";
 for(const t of document.querySelectorAll("input[data-flight-notes]"))t.value=(flight[t.dataset.flightNotes]||{{}}).notes||"";
 document.getElementById("csv").value=csv();}}
function answer(a){{answers[id(i+1)]=a; save(); if(i<COUNT-1){{i++; render();}}}}
document.getElementById("prev").onclick=()=>{{i=Math.max(0,i-1);render();}};
document.getElementById("next").onclick=()=>{{i=Math.min(COUNT-1,i+1);render();}};
for(const b of document.querySelectorAll("#answers button"))b.onclick=()=>answer(b.dataset.answer);
for(const s of document.querySelectorAll("select[data-flight]"))s.onchange=()=>{{flight[s.dataset.flight]=Object.assign(flight[s.dataset.flight]||{{}},{{rating:s.value}});save();}};
for(const t of document.querySelectorAll("input[data-flight-notes]"))t.oninput=()=>{{flight[t.dataset.flightNotes]=Object.assign(flight[t.dataset.flightNotes]||{{}},{{notes:t.value}});save();}};
document.getElementById("download").onclick=()=>{{const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([csv()],{{type:"text/csv"}}));a.download="responses.csv";a.click();}};
document.getElementById("reset").onclick=()=>{{if(confirm("¿Borrar todas las respuestas?")){{answers={{}};flight={{}};i=0;save();}}}};
document.addEventListener("keydown",e=>{{const keys={json.dumps(list(ANSWER_LABELS))};
 if(e.key>="1"&&e.key<="6")answer(keys[Number(e.key)-1]); else if(e.key==="ArrowLeft")document.getElementById("prev").click();
 else if(e.key==="ArrowRight")document.getElementById("next").click();}});
render();
</script></main></body></html>
"""


def kit_readme(count: int) -> str:
    labels = "\n".join(f"| `{answer}` | {label} |" for answer, label in ANSWER_LABELS.items())
    return f"""# L6c · kit de lectura de actitud a 100 m

{count} imágenes de la vista del juego (autozoom, Ugly Stik a 100 m del piloto, seis actitudes × cielo, borde de
copas, árboles y hierba) en un orden fijo que no depende del caso. Las respuestas correctas están solo en
`key/answer-key.json`: no abrirlo hasta terminar.

1. Abrir `index.html` en un navegador a zoom 100 %. Mirar cada imagen como en vuelo y elegir la actitud
   (botones o teclas 1–6). Se puede volver atrás.
2. En el juego, volar una pasada baja delante de los árboles (al norte) y un viraje frente a ellos; puntuar
   de 1 a 5 y anotar lo que confunda (filas `flight-pass` y `flight-turn`).
3. Descargar `responses.csv` y puntuar:

```bash
"$(app/tests/visual-env.sh)" app/tests/treeline_readability.py score responses.csv --kit <esta carpeta>
```

Objetivo inicial del plan (§8): ≥ {KIT_PASS}/{count} correctas por perfil; umbral de diseño, no validación
estadística. Un fallo señala qué fondo y qué actitud se confunden, para reducir densidad o contraste de la
arboleda o abrir huecos antes de añadir detalle.

| Respuesta | Significado |
| --- | --- |
{labels}

`responses-template.csv` tiene el mismo formato que la descarga (`image,answer,notes`), por si se rellena a mano.
"""


def score(responses_path: Path, kit_dir: Path) -> dict[str, Any]:
    key_path = Path(kit_dir) / "key" / "answer-key.json"
    key = json.loads(key_path.read_text(encoding="utf-8"))
    if key.get("format") != KEY_FORMAT:
        raise RuntimeError(f"{key_path}: not an {KEY_FORMAT} answer key")
    answers: dict[str, dict[str, str]] = {}
    with Path(responses_path).open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or [name.strip() for name in reader.fieldnames[:2]] != ["image", "answer"]:
            raise RuntimeError(f"{responses_path}: expected columns image,answer[,notes]")
        for row in reader:
            image = (row.get("image") or "").strip()
            if image.endswith(".png"):
                image = image[:-4]
            if not image:
                continue
            if image in answers:
                raise RuntimeError(f"{responses_path}: duplicate row for {image}")
            answers[image] = {"answer": (row.get("answer") or "").strip(), "notes": (row.get("notes") or "").strip()}
    expected = {item["image"][:2]: item for item in key["items"]}
    missing: list[str] = []
    wrong: list[dict[str, str]] = []
    by_background: dict[str, dict[str, int]] = {}
    confusion: dict[str, dict[str, int]] = {pose: {} for pose in POSES}
    correct = 0
    for image, item in sorted(expected.items()):
        answer = answers.get(image, {}).get("answer", "")
        background = item["background"]
        counts = by_background.setdefault(background, {"correct": 0, "total": 0})
        counts["total"] += 1
        if not answer:
            missing.append(image)
            continue
        if answer not in POSES:
            raise RuntimeError(f"{responses_path}: image {image} has an unknown answer {answer!r} (one of {', '.join(POSES)})")
        confusion[item["pose"]][answer] = confusion[item["pose"]].get(answer, 0) + 1
        if answer == item["pose"]:
            correct += 1
            counts["correct"] += 1
        else:
            wrong.append({"image": image, "background": background, "expected": item["pose"], "answer": answer,
                          "notes": answers[image]["notes"]})
    unknown_rows = sorted(set(answers) - set(expected) - set(KIT_FLIGHT_ROWS))
    if unknown_rows:
        raise RuntimeError(f"{responses_path}: rows that are not kit images or flight rows: {unknown_rows}")
    flight: dict[str, Any] = {}
    for row in KIT_FLIGHT_ROWS:
        rating_text = answers.get(row, {}).get("answer", "")
        rating: int | None = None
        if rating_text:
            if not rating_text.isdigit() or not 1 <= int(rating_text) <= 5:
                raise RuntimeError(f"{responses_path}: {row} rating must be 1–5, got {rating_text!r}")
            rating = int(rating_text)
        flight[row] = {"rating": rating, "notes": answers.get(row, {}).get("notes", "")}
    result = {
        "format": SCORE_FORMAT, "kit_view": key["view"], "distance_m": key["distance_m"],
        "total": len(expected), "correct": correct, "pass_correct": int(key["pass_correct"]),
        "passed": correct >= int(key["pass_correct"]) and not missing,
        "missing": missing, "wrong": wrong, "by_background": by_background, "confusion": confusion,
        "flight": flight, "flight_complete": all(flight[row]["rating"] is not None for row in KIT_FLIGHT_ROWS),
        "responses_sha256": vq.sha256_file(responses_path), "answer_key_sha256": vq.sha256_file(key_path),
    }
    return result


def run(app_dir: Path, godot: str, output_dir: Path, xvfb: str = "xvfb-run", timeout: float = 120.0) -> dict[str, Any]:
    app_dir = Path(app_dir).resolve()
    repo_root = app_dir.parent
    output_dir = Path(output_dir).resolve()
    if timeout <= 0 or not math.isfinite(timeout):
        raise ValueError("capture timeout must be finite and positive")
    if not Path(godot).is_file() and shutil.which(godot) is None:
        raise ValueError(f"Godot executable not found: {godot}")
    if shutil.which(xvfb) is None and not Path(xvfb).is_file():
        raise ValueError(f"display runner not found: {xvfb}")
    output_dir.mkdir(parents=True, exist_ok=True)
    with vq._output_lock(output_dir):
        return _run_locked(app_dir, repo_root, godot, output_dir, xvfb, timeout)


def import_resources(app_dir: Path, godot: str, log: Path, timeout: float = 180.0) -> None:
    """A fresh checkout has no imported tree atlas: import before rendering, and refuse any engine error."""
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run([godot, "--headless", "--path", str(app_dir), "--audio-driver", "Dummy", "--import"],
                                stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    text = re.sub(r"\x1b\[[0-9;]*m", "", log.read_text(errors="replace"))
    if result.returncode or re.search(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", text, re.M):
        raise RuntimeError(f"resource import failed (exit {result.returncode}); log: {log}")


def _run_locked(app_dir: Path, repo_root: Path, godot: str, output_dir: Path, xvfb: str, timeout: float) -> dict[str, Any]:
    complete_path = output_dir / "l6c-run-manifest.json"
    complete_path.unlink(missing_ok=True)
    os.environ.setdefault("LP_NUM_THREADS", "1")
    import_resources(app_dir, godot, output_dir / "import.log")
    revision, revision_source = vq.code_revision(repo_root)
    if revision != "unavailable":
        os.environ["OPENRC_CODE_REVISION"] = revision
    initial_input_hashes = vq.input_hashes(repo_root)
    cases = capture_cases()
    case_ids = [case.case_id for case in cases]
    if len(case_ids) != len(set(case_ids)) or len(cases) != len(VIEWS) * len(BACKGROUNDS) * (len(REFERENCES) + len(POSES)):
        raise RuntimeError("the L6c inventory is not the fixed 2 views × 4 backgrounds × (2 references + 6 attitudes)")
    entries: list[dict[str, Any]] = []
    for index, case in enumerate(cases, start=1):
        output = output_dir / case.filename
        command = vq.build_capture_command(app_dir, godot, xvfb, output, case)
        print(f"L6c capture {index}/{len(cases)} {case.case_id}", flush=True)
        try:
            manifest = run_capture(command, output, case.kind, case.expected_scene, timeout=timeout)
            evidence = validate_evidence(case, manifest)
            entries.append({
                "case_id": case.case_id, "family": case.family, "group": case.repeat_group,
                "image": output.name, "sha256": vq.sha256_file(output),
                "capture_manifest": output.with_suffix(".json").name,
                "capture_manifest_sha256": vq.sha256_file(output.with_suffix(".json")),
                "render_counters": vq._counter_signature(manifest), "visual_evidence": evidence,
            })
        except Exception as error:
            raise RuntimeError(f"case {index}/{len(cases)} {case.case_id} failed: {error}") from error
    if [entry["case_id"] for entry in entries] != case_ids:
        raise RuntimeError("completed capture inventory differs from the fixed case order")
    vq.validate_png_inventory(output_dir, cases)
    evidence_by_id = {entry["case_id"]: entry["visual_evidence"] for entry in entries}
    groups = {group_id(view, background): measure_group(output_dir, view, background, evidence_by_id)
              for view in VIEWS for background in BACKGROUNDS}
    readability = {
        "format": FORMAT, "aircraft": AIRCRAFT_ID, "distance_m": DISTANCE_M, "azimuth_deg": AZIMUTH_DEG,
        "metric": "compare_captures.measure_pair: airplane = pixels that differ from the view without it; ring = 6 px "
                  "around it; trees = pixels that differ between the views with and without the treeline; sky/ground "
                  "split at the recorded camera's horizon row",
        "backgrounds": {name: spec["elevation_deg"] for name, spec in BACKGROUNDS.items()},
        "views": {name: {"autozoom": autozoom} for name, autozoom in VIEWS.items()},
        "groups": groups,
    }
    readability_path = output_dir / "readability-trees.json"
    vq._write_json_atomic(readability_path, readability)
    kit = build_kit(output_dir, {entry["case_id"]: entry["sha256"] for entry in entries})
    final_input_hashes = vq.input_hashes(repo_root)
    if final_input_hashes != initial_input_hashes:
        raise RuntimeError("source/assets changed during the L6c run; no complete manifest was published")
    manifest = {
        "format": FORMAT + " run", "complete": True,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "code_revision": revision, "code_revision_source": revision_source,
        "input_sha256": initial_input_hashes,
        "harness_sha256": {
            "treeline_readability.py": vq.sha256_file(Path(__file__).resolve()),
            "visual_quality_cases.py": vq.sha256_file(Path(vq.__file__).resolve()),
            "compare_captures.py": vq.sha256_file(Path(__file__).resolve().with_name("compare_captures.py")),
        },
        "app": str(app_dir), "godot": str(Path(godot).resolve()) if Path(godot).exists() else godot,
        "rendering_driver": "opengl3", "display": {"size": [1280, 720], "runner": xvfb},
        "capture_timeout_s": timeout,
        "inventory": {"expected_case_ids": case_ids, "capture_count": len(entries)},
        "readability": "readability-trees.json", "readability_sha256": vq.sha256_file(readability_path),
        "kit": "kit/kit.json", "kit_sha256": vq.sha256_file(output_dir / "kit" / "kit.json"),
        "kit_images": len(kit["images"]),
        "human_playtest": "pending: score a responses.csv from kit/index.html with `treeline_readability.py score`",
        "captures": entries,
    }
    vq._write_json_atomic(complete_path, manifest)
    print(f"L6c complete: {len(entries)} captures, {len(groups)} measured groups, kit of {len(kit['images'])} images in {output_dir / 'kit'}")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("capture", help="render the 64 cases, measure them and build the kit")
    capture.add_argument("--app", type=Path, required=True)
    capture.add_argument("--godot", required=True)
    capture.add_argument("--out", type=Path, required=True)
    capture.add_argument("--xvfb", default="xvfb-run")
    capture.add_argument("--timeout", type=float, default=120.0)
    scorer = commands.add_parser("score", help="score a response sheet against the kit's answer key")
    scorer.add_argument("responses", type=Path)
    scorer.add_argument("--kit", type=Path, required=True)
    scorer.add_argument("--out", type=Path, default=None, help="results JSON (default: next to the responses)")
    args = parser.parse_args(argv)
    try:
        if args.command == "capture":
            run(args.app, args.godot, args.out, args.xvfb, args.timeout)
            return 0
        result = score(args.responses, args.kit)
        out = args.out or args.responses.with_name(args.responses.stem + "-results.json")
        vq._write_json_atomic(out, result)
        print(f"{result['correct']}/{result['total']} correct (pass ≥ {result['pass_correct']}): "
              f"{'PASS' if result['passed'] else 'FAIL'}; missing {len(result['missing'])}; wrong {len(result['wrong'])}; "
              f"flight rows {'complete' if result['flight_complete'] else 'incomplete'}; written {out}")
        return 0 if result["passed"] else 1
    except (RuntimeError, ValueError, OSError) as error:
        print(f"L6c: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
