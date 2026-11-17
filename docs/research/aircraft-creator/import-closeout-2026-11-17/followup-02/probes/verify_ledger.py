#!/usr/bin/env python3
"""Check the retained lexical ledger against exact ZIPs and prior visual evidence.

This checks data transcription and identities, not physics or flight eligibility.
It does not download, extract, modify or execute third-party files.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
from typing import Any
import zipfile


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    here = Path(__file__).resolve().parents[1]
    ledger_bytes = (here / "evidence/eligibility-ledger.json").read_bytes()
    ledger = json.loads(ledger_bytes)
    prior_bytes = (here.parent / "evidence/corpus-summary.json").read_bytes()
    assert sha(prior_bytes) == ledger["visual_projection_sha256"]
    prior = json.loads(prior_bytes)
    visual = {(m["archive"], m["model_root"]): m for m in prior["models"]}
    counts: Counter[str] = Counter()
    record_locations: set[tuple[str, str, int, str, str]] = set()
    shared: dict[str, list[dict[str, str]]] = defaultdict(list)
    for name, identity in ledger["archives"].items():
        data = (args.corpus / name).read_bytes()
        assert sha(data) == identity["sha256"] and len(data) == identity["bytes"], name
        counts["archive_hashes"] += 1
    for model in ledger["models"]:
        assert model["archive_sha256"] == ledger["archives"][model["archive"]]["sha256"]
        with zipfile.ZipFile(args.corpus / model["archive"]) as archive:
            raw = archive.read(model["params_member"])
            assert sha(raw) == model["params_sha256"]
            counts["parameter_member_hashes"] += 1
            lines = raw.decode("utf-8-sig").splitlines()
            sections: dict[int, str] = {}
            section = ""
            for number, line in enumerate(lines, 1):
                text = line.strip()
                if text.startswith("#begin "):
                    section = text.split(None, 1)[1].strip()
                elif text.startswith("#end "):
                    section = ""
                sections[number] = section

            def visit(value: Any) -> None:
                if isinstance(value, dict):
                    if {"line", "key", "rhs"} <= value.keys():
                        line = lines[value["line"] - 1].strip()
                        key, rhs = line.split(None, 1)
                        assert (key, rhs.strip(), sections[value["line"]]) == (
                            value["key"], value["rhs"], value["section"]
                        ), (model["model_root"], value)
                        location = (model["archive"], model["params_member"],
                            value["line"], value["key"], value["section"])
                        assert location not in record_locations, location
                        record_locations.add(location)
                        counts["record_locations_checked"] += 1
                    for child in value.values():
                        visit(child)
                elif isinstance(value, list):
                    for child in value:
                        visit(child)

            visit(model)
            assert float(model["version_record"]["rhs"]) == model["dialect"]
            assert model["mass"]["record"]["rhs"] == model["mass"]["value_text"]
            assert model["mass"]["unit"] == "kg" and model["mass"]["is_measured"] is False
            assert model["mass"]["unit_confidence"] == (
                "documented_v5" if model["dialect"] == 5 else "inferred_shared_key_v6")
            for member in model["auxiliary_geometry"]:
                if "member" in member and "sha256" in member:
                    assert sha(archive.read(member["member"])) == member["sha256"]
                    counts["auxiliary_member_hashes"] += 1
                    shared[member["sha256"]].append({"archive": model["archive"],
                        "model_root": model["model_root"], "member": member["member"]})
        old = visual[model["archive"], model["model_root"]]
        for key in ("ok", "source_sha256", "triangles"):
            assert old.get(key) == model["visual"].get(key)
        assert [d for d in old.get("diagnostics", []) if d.get("severity") == "error"] == \
            model["visual"]["error_diagnostics"]
        counts["prior_visual_outcomes_checked"] += 1
    for group in ledger["shared_auxiliary_hash_groups"]:
        assert shared[group["sha256"]] == group["occurrences"]
    v5 = [float(m["mass"]["value_text"]) for m in ledger["models"] if m["dialect"] == 5]
    assert len(v5) == 20 and all(m > 4.0 for m in v5)
    result = {"format": "openrc-import-audit-ledger-check-v1", "ledger_sha256": sha(ledger_bytes),
        "counts": dict(counts), "v5_declared_mass_min": min(v5), "v5_declared_mass_max": max(v5),
        "v5_all_above_current_4kg_upper_bound": True,
        "scope": "Lexical and hash consistency only. Visual evidence remains the prior 2a3cf04d run. No physical eligibility or full mapping claimed.",
        "ok": True}
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
