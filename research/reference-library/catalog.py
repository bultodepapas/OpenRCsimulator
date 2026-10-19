#!/usr/bin/env python3
"""Verify local research originals and regenerate the RC source catalogue."""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / "docs/research/flight-dynamics/rc-validation-library-2026-10-18"
FIELDS = (
    "category", "id", "title", "year", "type", "access", "source_url",
    "download_url", "local_path", "sha256", "bytes", "relevance", "limitations",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate catalog.csv, catalog.bib and inventory.json")
    args = parser.parse_args()
    rows, originals, failures, categories = [], {}, [], {}
    for manifest in sorted(LIBRARY.glob("*/sources.json")):
        entries = json.loads(manifest.read_text())
        category = manifest.parent.name
        identifiers = set()
        for entry in entries:
            ident = entry["id"]
            label = f"{category}:{ident}"
            if ident in identifiers:
                failures.append(f"Duplicate ID: {label}")
            identifiers.add(ident)
            for field in ("title", "source_url", "relevance", "limitations"):
                if not entry.get(field):
                    failures.append(f"Missing {field}: {label}")
            rows.append({"category": category, **entry})
            local = entry.get("local_path")
            if not local or local in originals:
                continue
            path = ROOT / local
            if not path.resolve().is_relative_to((ROOT / "references").resolve()):
                failures.append(f"Original outside ignored references/: {label}: {local}")
                continue
            try:
                data = path.read_bytes()
                digest = hashlib.sha256(data).hexdigest()
                if digest != entry.get("sha256") or len(data) != entry.get("bytes"):
                    raise ValueError("manifest hash/size mismatch")
                if path.suffix.lower() == ".pdf":
                    if not data.startswith(b"%PDF-"):
                        raise ValueError("missing PDF signature")
                    subprocess.run(
                        ["pdftotext", "-f", "1", "-l", "1", str(path), "-"],
                        capture_output=True, check=True, timeout=60,
                    )
                if path.suffix.lower() == ".zip":
                    with zipfile.ZipFile(io.BytesIO(data)) as archive:
                        if archive.testzip() is not None:
                            raise ValueError("ZIP CRC failure")
                originals[local] = {"sha256": digest, "bytes": len(data), "suffix": path.suffix.lower()}
            except (OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
                failures.append(f"{label}: {error}")
        categories[category] = {
            "records": len(entries),
            "records_with_local_file": sum(bool(e.get("local_path")) for e in entries),
        }
    # Every record pointing to a reused file must agree with that file, too.
    for row in rows:
        original = originals.get(row.get("local_path"))
        if original and (row.get("sha256") != original["sha256"] or row.get("bytes") != original["bytes"]):
            failures.append(f"Reused-file metadata mismatch: {row['category']}:{row['id']}")
    bibliography_rows = {}
    for row in rows:
        identity = row.get("sha256") or row["source_url"]
        bibliography_rows.setdefault(identity, row)
    summary = {
        "format": "openrc-literature-inventory v1",
        "generator": "research/reference-library/catalog.py --write",
        "checked_utc": datetime.now(timezone.utc).isoformat(),
        "records": len(rows),
        "bibliography_entries": len(bibliography_rows),
        "records_without_local_file": sum(not r.get("local_path") for r in rows),
        "verified_local_paths": len(originals),
        "distinct_local_contents": len({o["sha256"] for o in originals.values()}),
        "local_pdf_paths": sum(o["suffix"] == ".pdf" for o in originals.values()),
        "local_zip_paths": sum(o["suffix"] == ".zip" for o in originals.values()),
        "new_collection_paths": sum(p.startswith("references/rc-validation-library-2026-10-18/") for p in originals),
        "reused_reference_paths": sum(not p.startswith("references/rc-validation-library-2026-10-18/") for p in originals),
        "total_local_bytes": sum(o["bytes"] for o in originals.values()),
        "categories": categories,
        "failures": failures,
    }
    print(json.dumps(summary, indent=2))
    if failures:
        raise SystemExit(1)
    if args.write:
        with (LIBRARY / "catalog.csv").open("w", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=FIELDS, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(rows)
        def tex(value):
            escapes = {
                "\\": "\\textbackslash{}", "{": "\\{", "}": "\\}",
                "&": "\\&", "%": "\\%", "#": "\\#", "$": "\\$",
            }
            return "".join(escapes.get(character, character) for character in str(value))

        bibliography = ["% Generated by research/reference-library/catalog.py --write; source: topic sources.json manifests."]
        for row in bibliography_rows.values():
            key = re.sub(r"[^A-Za-z0-9_-]", "-", f"{row['category']}-{row['id']}")
            fields = {"title": tex(row["title"]), "url": row["source_url"]}
            if row.get("authors"):
                fields["author"] = " and ".join(tex(author) for author in row["authors"])
            if row.get("year"):
                fields["year"] = str(row["year"])
            if row.get("doi"):
                fields["doi"] = str(row["doi"]).removeprefix("https://doi.org/")
            if row.get("retrieved_utc"):
                fields["urldate"] = str(row["retrieved_utc"])[:10]
            bibliography.append("@misc{" + key + ",\n" + ",\n".join(f"  {name} = {{{value}}}" for name, value in fields.items()) + "\n}")
        (LIBRARY / "catalog.bib").write_text("\n\n".join(bibliography) + "\n")
        (LIBRARY / "inventory.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
