"""BAT-06: compare runtime pack_ecm stage evaluations (law_probe.gd) with the independent reference.

Usage: python3 -I research/battery/bat-06/compare_law.py <probe.json> [--tolerance 1e-12]
Exit 0 when every accepted case agrees within the relative tolerance and refusals agree.
"""
import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "research/battery"))
import ecm_reference as ref  # noqa: E402


def load_pack(pack_id):
    pack = json.loads((ROOT / "app/data/batteries/packs" / f"{pack_id}.json").read_text(encoding="utf-8"))
    template = json.loads((ROOT / "app/data/batteries/cells" / f"{pack['cell_template']['id']}.json").read_text(encoding="utf-8"))
    return ref.normalize(pack, template)


def rel(a, b):
    return abs(a - b) / max(1.0, abs(b))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("probe")
    parser.add_argument("--tolerance", type=float, default=1e-12)
    args = parser.parse_args()
    probe = json.loads(Path(args.probe).read_text(encoding="utf-8"))
    packs = {}
    worst = {"bus_voltage_v": 0.0, "pack_current_a": 0.0, "motor_current_a": 0.0, "rates": 0.0}
    refusals = mismatched_refusals = failures = 0
    motor = ref.Motor(probe["motor"]["kv_rpm_per_volt"], probe["motor"]["resistance_ohm"])
    for case in probe["cases"]:
        pack = packs.setdefault(case["pack"], load_pack(case["pack"]))
        session = ref.Session(initial_soc=case["initial_soc"], auxiliary_current_a=case["auxiliary_current_a"],
                              cooling_airflow_fraction=case["cooling_airflow_fraction"], capacity_factor=case["capacity_factor"],
                              resistance_factor=case["resistance_factor"], soc_offset=case["soc_offset"],
                              voltage_filter_s=case["voltage_filter_s"])
        lay = ref.layout(pack)
        block = case["block"]
        y = block[:lay.size]
        limit = block[lay.size]  # §5: ESC output limit follows the sensed voltage
        inputs = ref.Inputs(rpm=case["rpm"], duty=case["duty"], enabled=case["enabled"], limit=limit,
                            ambient_k=case["ambient_k"], airspeed_mps=case["airspeed_mps"])
        try:
            result = ref.stage(pack, session, y, inputs, motor, exhausted=(y[lay.charge] <= 0.0))
            ok = True
        except (ValueError, ZeroDivisionError):
            ok = False
        if not ok or not case["ok"]:
            refusals += 1
            if ok != case["ok"]:
                mismatched_refusals += 1
            continue
        pairs = [("bus_voltage_v", case["bus_voltage_v"], result.voltage_v),
                 ("pack_current_a", case["pack_current_a"], result.current_a),
                 ("motor_current_a", case["motor_current_a"], result.motor_current_a)]
        for name, ours, theirs in pairs:
            worst[name] = max(worst[name], rel(ours, theirs))
        for ours, theirs in zip(case["rates"][:lay.size], result.rates):
            worst["rates"] = max(worst["rates"], rel(ours, theirs))
        if any(v > args.tolerance for v in worst.values()):
            failures += 1
    total = len(probe["cases"])
    print(json.dumps({"cases": total, "refusals": refusals, "mismatched_refusals": mismatched_refusals,
                      "max_relative_error": worst, "tolerance": args.tolerance}, indent=1))
    return 0 if mismatched_refusals == 0 and all(v <= args.tolerance for v in worst.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
