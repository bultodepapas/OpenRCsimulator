"""Read-only text and identity audit for the supplied helicopter PDF manual.

Run from the repository root with pypdf 6.14.2 and PyMuPDF installed:

    python research/helicopter/assets/audit_reference_pdf.py --out .tools/heli25/pdf

The source PDF is never modified. Page renders and JSON output default to
ignored .tools evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
from pathlib import Path

import pypdf


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PDF = ROOT / "assets/source-deliveries/hx-700-original" / "UYjm3SGvvYxnGgggCnqPGIuKhQHNNSeM98oX8uMr.pdf"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--out", type=Path, default=ROOT / ".tools" / "heli25" / "pdf")
    args = parser.parse_args()
    pdf_path = args.pdf.resolve()
    out_dir = args.out if args.out.is_absolute() else ROOT / args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    started = time.perf_counter()
    reader = pypdf.PdfReader(str(pdf_path), strict=False)
    pages = []
    full_text = []
    for page_index, page in enumerate(reader.pages):
        error = None
        try:
            text = page.extract_text() or ""
        except Exception as exc:  # preserve per-page extraction failures in the record
            text = ""
            error = f"{type(exc).__name__}: {exc}"
        full_text.append(text)
        pages.append({"page": page_index + 1, "native_text_characters": len(text), "error": error})

    text_all = "\n".join(full_text)
    license_terms = re.compile(r"copyright|all rights reserved|license|licence|permission to reproduce|prohibid", re.I)
    license_mentions = []
    for page_index, text in enumerate(full_text):
        if license_terms.search(text):
            matches = [line.strip() for line in text.splitlines() if license_terms.search(line)]
            license_mentions.append({"page": page_index + 1, "lines": matches[:8]})

    render_records = []
    render_error = None
    try:
        import pymupdf

        document = pymupdf.open(str(pdf_path))
        try:
            for page_number in (1, 3, 33):
                if page_number > len(document):
                    continue
                pixmap = document[page_number - 1].get_pixmap(matrix=pymupdf.Matrix(0.8, 0.8), alpha=False)
                image_path = out_dir / f"page-{page_number:02}.png"
                pixmap.save(str(image_path))
                render_records.append({"page": page_number, "image": str(image_path.relative_to(ROOT)),
                                      "width_px": pixmap.width, "height_px": pixmap.height})
        finally:
            document.close()
        pymupdf_version = pymupdf.__version__
    except Exception as exc:
        pymupdf_version = None
        render_error = f"{type(exc).__name__}: {exc}"

    page3_text = full_text[2] if len(full_text) >= 3 else ""
    page33_text = full_text[32] if len(full_text) >= 33 else ""
    meta = reader.metadata or {}
    result = {
        "schema": "openrc-heli-reference-pdf-audit-v1",
        "source": {"path": str(pdf_path.relative_to(ROOT)), "size_bytes": pdf_path.stat().st_size,
                   "sha256": sha256_file(pdf_path)},
        "parser": {"pypdf": pypdf.__version__, "strict": False, "elapsed_seconds": round(time.perf_counter() - started, 3),
                   "pymupdf": pymupdf_version},
        "document": {"page_count": len(pages), "encrypted": reader.is_encrypted,
                     "metadata": {str(key): str(value) for key, value in meta.items()},
                     "native_text_characters_total": len(text_all),
                     "empty_text_pages": [row["page"] for row in pages if row["native_text_characters"] == 0],
                     "extraction_errors": [row for row in pages if row["error"]],
                     "page_inventory": pages},
        "identity_evidence": {
            "page_2_mentions_vendor_site": "goblin-helicopter.com" in full_text[1].casefold() if len(full_text) >= 2 else False,
            "page_3_heading": next((line.strip() for line in page3_text.splitlines()
                                     if "TECHNICAL SPECIFICATIONS" in line.upper()), None),
            "page_3_key_specs": [line.strip() for line in page3_text.splitlines()
                                 if any(term in line.casefold() for term in ("rotor diameter", "main blade", "tail rotor diameter", "tail blade", "1382mm", "1580mm"))],
            "page_33_model_references": [line.strip() for line in page33_text.splitlines()
                                         if "canopy" in line.casefold() or "goblin" in line.casefold()],
        },
        "license_language_matches": license_mentions,
        "visual_renders": render_records,
        "visual_render_error": render_error,
    }
    out_path = out_dir / "reference-pdf-audit.json"
    out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"PDF audit: {out_path}")
    print(f"Pages: {len(pages)}; text characters: {len(text_all)}; empty pages: {result['document']['empty_text_pages']}; errors: {len(result['document']['extraction_errors'])}")
    print("Identity evidence:", json.dumps(result["identity_evidence"], ensure_ascii=False))


if __name__ == "__main__":
    main()
