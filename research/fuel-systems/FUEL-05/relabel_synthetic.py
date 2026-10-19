"""FUEL-05d (D7): label the synthetic electric Stik fixtures' glow-donor inventory as donor mass.

The four fixtures keep the original Stik mass distribution on purpose ("original inventory mass
distribution"), but their item names claimed a glow engine, a tank and half a tank of fuel. This rewrites
names only: no mass, position, size or energy tag changes, so every trajectory is unchanged.
The fixtures have no identity module, so inventory ids stay absent (orphan ids are refused).

Usage: python3 -I research/fuel-systems/FUEL-05/relabel_synthetic.py [--check]
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FILES = ["synthetic_stik_electric_%s.json" % s for s in ("4s", "6s", "4s_battery", "6s_battery")]
DONOR = {
    "engine O.S. MAX-61FX": "donor mass at the glow engine station (no engine modeled)",
    "muffler E-4010": "donor mass at the glow muffler station",
    "fuel tank (empty)": "donor mass at the fuel-tank station (no tank)",
    "fuel (half tank)": "donor mass at the fuel station (no fuel)",
}
NOTE = (" FUEL-05d: inventory items named 'donor mass' keep the glow Stik's mass distribution only;"
        " the fixture carries no engine, tank or fuel.")


def relabel(raw):
    for item in raw["inventory"]:
        if item["name"] in DONOR:
            item["name"] = DONOR[item["name"]]
    if NOTE.strip() not in raw["description"]:
        raw["description"] += NOTE
    return raw


def render(raw):
    # The fixtures are stored with CRLF line endings and literal non-ASCII characters.
    return (json.dumps(raw, indent=2, ensure_ascii=False) + "\n").replace("\n", "\r\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for name in FILES:
        path = ROOT / "app/data/aircraft" / name
        current = path.read_bytes()
        rendered = render(relabel(json.loads(current.decode("utf-8"))))
        if rendered != current:
            if args.check:
                stale.append(name)
            else:
                path.write_bytes(rendered)
    if stale:
        sys.exit("stale: " + ", ".join(stale))
    print("synthetic fixtures labelled" if not args.check else "synthetic fixtures current")


if __name__ == "__main__":
    main()
