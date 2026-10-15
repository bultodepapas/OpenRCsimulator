"""Validate RCV-39 retained evidence and rebuild its summary (does not run Godot)."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = ROOT / "docs/research/rc-monster-truck/RCV-39"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(relative):
    return json.loads((EVIDENCE / relative).read_text(encoding="utf-8-sig"))


def clean_log(relative):
    log = (EVIDENCE / relative).read_text(encoding="utf-8-sig")
    assert not re.search(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ])", log, re.M), relative


def main():
    effects = read("effects/receipt.json")
    assert effects["complete"] and effects["equivalent"]
    assert effects["verification"]["failures"] == 0
    assert effects["verification"]["overlay_uniform_comparisons"] > 40000
    assert effects["structure"]["unique_overlay_materials"] == [70, 5]
    clean_log("effects/run.log")
    for source in effects["source_hashes"].values():
        # Receipts retain their original absolute paths; verify against this checkout.
        suffix = source["path"].replace("\\", "/").split("/OpenRCsimulator/", 1)[1]
        assert digest(ROOT / suffix) == source["sha256"], suffix
    checks = read("checks/verification.json")
    assert checks["complete"]
    for source, sha256 in checks["sources"].items():
        assert digest(ROOT / source) == sha256, source
    for test in checks["tests"]:
        assert test["passed"]
        assert digest(ROOT / "app/tests" / test["test"]) == test["test_sha256"]
        assert digest(EVIDENCE / "checks" / test["log"]) == test["log_sha256"]
        clean_log("checks/" + test["log"])
    native = {}
    for period in ("day", "night"):
        for label in ("baseline", "candidate"):
            name = f"{label}-{period}"
            report = read(name + "/activity.json")
            assert report["complete"] and report["accepted_ticks"] == 1080
            assert report["label"] == label and report["period"] == period
            assert report["effects"]["grime_overlay_count"] == 70
            assert report["effects"]["particle_budget_total"] == 96
            assert report["max_dust_active_wheels"] == 4
            expected_source = effects["source_hashes"][label + "_effects.gd"]["sha256"]
            assert report["source_sha256"]["effects"] == expected_source
            clean_log(name + "/run.log")
            native[name] = report
        before, after = native["baseline-" + period], native["candidate-" + period]
        assert before["draw_calls"] == after["draw_calls"]
        assert before["primitives"] == after["primitives"]
        for key in before["source_sha256"]:
            if key != "effects":
                assert before["source_sha256"][key] == after["source_sha256"][key], key
        for key in ("effects", "wet_effects", "exhaust"):
            candidate = after[key].copy()
            candidate.pop("grime_material_count", None)
            assert before[key] == candidate, key
    reference = native["baseline-day"]
    assert all(r["trajectory_sha256"] == reference["trajectory_sha256"] for r in native.values())
    assert all(r["backend_identity"] == reference["backend_identity"] for r in native.values())
    component = {}
    for case, values in effects["result"]["performance"]["case_results"].items():
        before, after = values["baseline_median_us_per_update"], values["candidate_median_us_per_update"]
        component[case] = {"baseline_us": before, "candidate_us": after,
                           "reduction_percent": (1 - after / before) * 100}
    summary = {
        "step": "RCV-39", "complete": True, "solver_changed": False,
        "trajectory_sha256": reference["trajectory_sha256"],
        "unique_grime_materials": [70, 5], "component_cpu": component,
        "equivalence": effects["verification"],
        "focused_checks": sum(int(re.search(r"(\d+) checks", t["summary"][0]).group(1))
                              for t in checks["tests"]),
        "native_callback_measurements": {name: {key: r[key] for key in (
            "render_callback_cost", "four_tick_batch_cost", "draw_calls", "primitives")}
            for name, r in native.items()},
        "scope": "Component CPU and resource reduction. Native pairs establish same-tape behavior and visual budgets; not an FPS or GPU-time qualification.",
        "evidence_sha256": {str(p.relative_to(EVIDENCE)).replace("\\", "/"): digest(p)
            for p in sorted(EVIDENCE.rglob("*")) if p.is_file() and p.suffix in (".json", ".log", ".png")
            and p.name != "summary.json"},
    }
    (EVIDENCE / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"complete": True, "component_cpu": component,
                      "focused_checks": summary["focused_checks"]}, indent=2))


if __name__ == "__main__":
    main()
