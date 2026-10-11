#!/usr/bin/env python3
"""FIELD-WORLD-PLAN FW-24: the naked-eye stars, from the Yale Bright Star Catalogue (assets/sky/bsc5.dat.gz).

Keeps every star with V <= 6.0 and writes integer rows [ra_mdeg, dec_mdeg, vmag_centi, bv_centi] (J2000 right
ascension and declination in millidegrees, visual magnitude and B-V colour index in hundredths), brightest first.
Precession since J2000 (about 0.36 degrees by 2026) is not applied: below the plan's 0.5 degree target.
Stdlib only; integer output, so the bytes are platform independent.
  python3 tools/world/stars.py            write app/data/sky/stars.json
  python3 tools/world/stars.py --check    fail if the committed list differs from a fresh run
"""
import gzip
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "sky" / "bsc5.dat.gz"
SOURCE_SHA256 = "0471ced07fc241e625613baa689b2fa5f4b59fd733f731003e57d2d436036cdb"
OUT = ROOT / "app" / "data" / "sky" / "stars.json"
LIMIT_VMAG = 6.0
DEFAULT_BV = 0.6  # a few entries have no colour index: a sun-like white (estimate)


def field(line, first, last):
    """Bytes first..last (1-based, inclusive) of a fixed-width catalogue line, stripped."""
    return line[first - 1:last].strip()


def parse(line):
    ra_h, ra_m, ra_s = field(line, 76, 77), field(line, 78, 79), field(line, 80, 83)
    vmag = field(line, 103, 107)
    if not ra_h or not vmag:
        return None  # novae and other entries without a J2000 position or magnitude
    ra = (int(ra_h) + int(ra_m) / 60.0 + float(ra_s) / 3600.0) * 15.0
    sign = -1.0 if field(line, 84, 84) == "-" else 1.0
    dec = sign * (int(field(line, 85, 86)) + int(field(line, 87, 88)) / 60.0 + int(field(line, 89, 90)) / 3600.0)
    bv = field(line, 110, 114)
    return [round(ra * 1000.0), round(dec * 1000.0), round(float(vmag) * 100.0),
            round((float(bv) if bv else DEFAULT_BV) * 100.0)]


def stars():
    raw = SOURCE.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != SOURCE_SHA256:
        sys.exit(f"{SOURCE}: SHA-256 {digest} does not match PROVENANCE.json")
    rows = []
    for line in gzip.decompress(raw).decode("latin-1").splitlines():
        row = parse(line)
        if row is not None and row[2] <= LIMIT_VMAG * 100:
            rows.append(row)
    rows.sort(key=lambda r: (r[2], r[0], r[1]))
    return {
        "format": "openrc-stars v1",
        "generator": "tools/world/stars.py",
        "metadata": {
            "kind": "derived",
            "source": "Yale Bright Star Catalogue 5th Revised Ed. (assets/sky/PROVENANCE.json), V <= 6.0, J2000, "
                      "no precession (about 0.36° by 2026).",
            "row_encoding": {"columns": ["ra_mdeg", "dec_mdeg", "vmag_centi", "bv_centi"],
                             "unit": ["millidegree", "millidegree", "0.01 mag", "0.01 mag"]},
            "default_bv": {"value": DEFAULT_BV, "unit": "mag", "kind": "estimated",
                           "source": "Used for the few stars without a catalogued B-V"},
        },
        "source_sha256": SOURCE_SHA256,
        "rows": rows,
    }


def main():
    data = stars()
    text = json.dumps(data, separators=(",", ":"), sort_keys=True) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8").replace("\r\n", "\n") != text:
            sys.exit(f"{OUT} is stale: run tools/world/stars.py")
        print("star list current")
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUT} ({len(data['rows'])} stars, V <= {LIMIT_VMAG})")


if __name__ == "__main__":
    main()
