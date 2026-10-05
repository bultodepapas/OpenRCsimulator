#!/usr/bin/env python3
"""Check repeated PNG capture hashes and build a local, answer-keyed review page."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path
from typing import Any


SURFACE_CHOICES = ["upper side", "underside", "unclear"]
BANK_CHOICES = ["left", "right", "level", "unclear"]
DIRECTION_CHOICES = ["toward", "away", "unclear"]


def sha256(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def png_hashes(folder: Path) -> dict[str, str]:
	return {path.name: sha256(path) for path in sorted(folder.glob("*.png"))}


def select_html(label: str, field: str, choices: list[str], case_id: str) -> str:
	options = ['<option value="">Choose…</option>']
	for choice in choices:
		value = html.escape(choice, quote=True)
		options.append(f'<option value="{value}">{html.escape(choice)}</option>')
	return (
		f'<label>{html.escape(label)}'
		f'<select name="{html.escape(field)}" data-case="{html.escape(case_id, quote=True)}">'
		+ "".join(options)
		+ "</select></label>"
	)


def render_card(capture: dict[str, Any]) -> str:
	case_id = str(capture["case_id"])
	answer = capture["reference_answer"]
	filename = html.escape(str(capture["file"]), quote=True)
	case = html.escape(case_id)
	condition = html.escape(str(capture["condition"]))
	answers = " · ".join(
		f"{html.escape(label)}: {html.escape(str(answer[key]))}"
		for label, key in [("Surface", "surface"), ("Bank", "bank"), ("Direction", "direction")]
	)
	return f"""
<article class="card" data-distance="{float(capture['distance_m']):g}" data-background="{html.escape(str(capture['background']))}">
  <div class="image-wrap"><a href="{filename}" target="_blank" rel="noopener" aria-label="Open native 1280 by 720 PNG"><img src="{filename}" width="1280" height="720" alt="{case} airplane orientation capture" loading="lazy"></a></div>
  <div class="card-body">
    <h2>{case}</h2>
    <p class="condition">{condition}</p>
    <p class="scale-note">Image shown at native 1280×720 CSS-pixel size. Click the image to open its PNG; use 100% browser zoom when answering.</p>
    <div class="responses">
      {select_html("Visible wing face", "surface", SURFACE_CHOICES, case_id)}
      {select_html("Bank", "bank", BANK_CHOICES, case_id)}
      {select_html("Nose direction", "direction", DIRECTION_CHOICES, case_id)}
    </div>
    <details><summary>Reference answer</summary><p>{answers}</p></details>
  </div>
</article>"""


def render_page(manifest: dict[str, Any]) -> str:
	cards = "\n".join(render_card(capture) for capture in manifest["captures"])
	return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>US-06 · Ugly Stik orientation review</title>
  <style>
    :root {{ color-scheme: light; font: 16px/1.45 system-ui, sans-serif; color: #17232c; background: #edf2f5; }}
    body {{ margin: 0; }}
    header {{ position: sticky; top: 0; z-index: 2; padding: 18px max(20px, calc((100vw - 1440px) / 2)); background: #17232c; color: white; box-shadow: 0 2px 10px #0003; }}
    header h1 {{ margin: 0 0 4px; font-size: 1.35rem; }}
    header p {{ margin: 3px 0; color: #d6e0e6; }}
    main {{ max-width: 1440px; margin: 22px auto; padding: 0 20px 48px; }}
    .toolbar {{ display: flex; flex-wrap: wrap; gap: 12px; align-items: center; margin: 12px 0 20px; }}
    .toolbar label {{ display: flex; gap: 8px; align-items: center; }}
    input, select, textarea, button {{ font: inherit; }}
    input[type="text"] {{ padding: 7px; }}
    button {{ padding: 8px 12px; border: 1px solid #718391; border-radius: 5px; background: white; cursor: pointer; }}
    .status {{ font-weight: 650; }}
    .grid {{ display: grid; grid-template-columns: 1fr; gap: 16px; }}
    .card {{ width: 1280px; overflow: hidden; border: 1px solid #ccd6dc; border-radius: 8px; background: white; box-shadow: 0 2px 8px #17232c12; }}
    .image-wrap {{ background: #9bcef0; }}
    .image-wrap img {{ display: block; width: 1280px; height: 720px; object-fit: none; }}
    .card-body {{ padding: 12px 16px 16px; }}
    h2 {{ display: inline; margin: 0; font-size: 1.05rem; }}
    .condition {{ margin: 3px 0 12px; color: #536671; }}
    .scale-note {{ margin: 0 0 10px; color: #536671; font-size: .9rem; }}
    .responses {{ display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 9px; }}
    .responses label {{ display: grid; gap: 4px; font-size: .83rem; font-weight: 650; }}
    select {{ width: 100%; min-width: 0; padding: 6px; }}
    details {{ margin-top: 12px; color: #455863; }}
    details p {{ margin: 6px 0 0; }}
    .note {{ width: min(100%, 520px); min-height: 64px; }}
    @media print {{ header {{ position: static; }} .toolbar button {{ display: none; }} .card {{ break-inside: avoid; box-shadow: none; }} }}
  </style>
</head>
<body>
<header>
  <h1>US-06 · Orientation readability review</h1>
  <p>36 fixed captures · 20, 50 and 100 m · sky and ground · geometry and neutral hinges held constant.</p>
  <p>Responses are blank. Images retain native 1280×720 resolution. Open each “Reference answer” only after recording the pilot response.</p>
</header>
<main>
  <div class="toolbar">
    <label>Pilot / session ID <input id="pilot" type="text" autocomplete="off"></label>
    <label>Notes <textarea id="notes" class="note" placeholder="Doubts, missed cues, or viewing conditions"></textarea></label>
    <button id="download" type="button">Download blank/filled responses JSON</button>
    <button type="button" onclick="window.print()">Print review sheet</button>
    <span class="status" id="status">No pilot responses recorded · pending</span>
  </div>
  <p><strong>Prompt:</strong> For each still, choose the visible wing face, bank direction, and whether the nose points toward or away from the observer. Direction is a static heading cue, not a test of actual motion perception.</p>
  <section class="grid">{cards}
  </section>
</main>
<script>
  const fields = [...document.querySelectorAll('select[data-case]')];
  const status = document.getElementById('status');
  function updateStatus() {{
    const recorded = fields.filter(field => field.value !== '').length;
    status.textContent = recorded === 0 ? 'No pilot responses recorded · pending' : `${{recorded}} pilot responses recorded · human review pending`;
  }}
  fields.forEach(field => field.addEventListener('change', updateStatus));
  document.getElementById('download').addEventListener('click', () => {{
    const byCase = {{}};
    for (const field of fields) {{
      byCase[field.dataset.case] ??= {{}};
      byCase[field.dataset.case][field.name] = field.value || null;
    }}
    const data = {{
      status: 'pending_until_reviewed_by_owner',
      pilot_or_session_id: document.getElementById('pilot').value || null,
      notes: document.getElementById('notes').value || null,
      responses: byCase,
      prompt_scope: 'static orientation; direction means nose toward/away, not measured motion',
    }};
    const blob = new Blob([JSON.stringify(data, null, 2) + '\\n'], {{type: 'application/json'}});
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'us06-pilot-responses.json';
    link.click();
    URL.revokeObjectURL(link.href);
  }});
</script>
</body>
</html>
"""


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--captures", type=Path, required=True, help="primary run capture directory")
	parser.add_argument("--repeat-captures", type=Path, required=True, help="independent repeat run directory")
	args = parser.parse_args()
	captures_dir = args.captures.resolve()
	repeat_dir = args.repeat_captures.resolve()
	manifest_path = captures_dir / "manifest.json"
	if not manifest_path.is_file():
		parser.error(f"missing manifest: {manifest_path}")
	manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
	if manifest.get("capture_suite") != "readability36":
		parser.error("review kit only accepts the readability36 capture suite")
	if len(manifest.get("captures", [])) != 36:
		parser.error("readability36 manifest must contain exactly 36 captures")
	first_hashes = png_hashes(captures_dir)
	repeat_hashes = png_hashes(repeat_dir)
	if not first_hashes:
		parser.error("primary run contains no PNG captures")
	if first_hashes != repeat_hashes:
		missing = sorted(set(first_hashes) ^ set(repeat_hashes))
		different = sorted(name for name in set(first_hashes) & set(repeat_hashes) if first_hashes[name] != repeat_hashes[name])
		parser.error(f"repeat PNG hashes differ; missing={missing}, changed={different}")
	if set(first_hashes) != {str(capture["file"]) for capture in manifest["captures"]}:
		parser.error("PNG filenames do not exactly match the manifest capture list")
	for record in manifest["captures"]:
		filename = str(record["file"])
		if filename not in first_hashes:
			parser.error(f"manifest points at missing image: {filename}")
		record["png_sha256"] = first_hashes[filename]
	manifest["repeat_determinism"] = {
		"independent_runs": 2,
		"compared_png_count": len(first_hashes),
		"identical_png_sha256": True,
		"manifest_and_timing_compared": False,
		"png_sha256": first_hashes,
	}
	manifest["human_review"] = {
		"status": "pending",
		"pilot_response_count": 0,
		"owner_assessment": "pending",
		"response_kit": "review.html",
	}
	manifest_path.write_text(json.dumps(manifest, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
	(captures_dir / "review.html").write_text(render_page(manifest), encoding="utf-8")
	print(f"Verified {len(first_hashes)} repeat PNG SHA-256 hashes; wrote review.html")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
