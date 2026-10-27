"""Merge one OS's reference captures into app/tests/fixtures/fixed_brake_legacy_outputs.json.

Usage: python merge_legacy_os_capture.py <fixture.json> <capture-r0.json> <capture-r3.json>

Both captures come from capture_legacy_outputs.gd on one OS, run in trees built by
reconstruct_legacy_reference.py: r0 is the pinned pre-brake reference and r3 the same tree with
the NITRO-06-R3 carburettor. gp-extra-300s-60 (the only glow aircraft here) is expected from r3,
the others from r0, which must equal r3 for them. `outputs` stays the Windows capture; a
Windows capture must reproduce it exactly. Another OS adds `outputs_by_os[<os>][<id>]` with only
the differing digests. Comparison stays exact; provenance goes to `os_captures[<os>]`.
"""
import json
import sys

FORMAT = "openrc-fixed-brake-legacy-capture v1"
BASE_OS = "Windows"
GLOW_IDS = {"gp-extra-300s-60"}
FIELDS = ["after_three_ticks", "checkpoint", "metadata", "trace_csv"]
REFERENCE = dict(base_commit="fa9f387f6", pinned_inputs_verified=400)


def load_capture(path, fixture, r3):
    with open(path, encoding="utf-8") as handle:
        capture = json.load(handle)
    reference = capture.get("reference", {})
    if capture.get("format") != FORMAT:
        sys.exit("unknown capture format: " + path)
    if any(reference.get(k) != v for k, v in REFERENCE.items()):
        sys.exit("capture did not run on the verified pre-brake reference: %s" % reference)
    if reference.get("nitro_06_r3") != ("20662f264" if r3 else None):
        sys.exit("wrong carburettor variant in " + path)
    if (capture["session_sha256"], capture["trace_sha256"]) != (fixture["baseline_session_sha256"], fixture["baseline_trace_sha256"]):
        sys.exit("capture Session/Trace are not the frozen old owner: " + path)
    if (capture["engine"], capture["physics_hz"]) != (fixture["engine"], fixture["physics_hz"]):
        sys.exit("capture engine/physics rate differ: " + path)
    return capture


def main(fixture_path, r0_path, r3_path):
    with open(fixture_path, encoding="utf-8") as handle:
        fixture = json.load(handle)
    r0 = load_capture(r0_path, fixture, False)
    r3 = load_capture(r3_path, fixture, True)
    if r0["os"] != r3["os"]:
        sys.exit("captures come from different OSes")
    os_name = r0["os"]
    if sorted(r0["outputs"]) != sorted(fixture["outputs"]) or sorted(r3["outputs"]) != sorted(fixture["outputs"]):
        sys.exit("capture aircraft differ from the fixture")
    expected = {}
    for aircraft, base in fixture["outputs"].items():
        if aircraft not in GLOW_IDS and r0["outputs"][aircraft] != r3["outputs"][aircraft]:
            sys.exit("NITRO-06-R3 unexpectedly moved non-glow aircraft " + aircraft)
        got = (r3 if aircraft in GLOW_IDS else r0)["outputs"][aircraft]
        if any(not got.get(field) for field in FIELDS):
            sys.exit("capture incomplete for " + aircraft)
        differing = {field: got[field] for field in FIELDS if got[field] != base[field]}
        if differing and os_name == BASE_OS:
            sys.exit("Windows capture no longer reproduces outputs for %s: %s" % (aircraft, sorted(differing)))
        if differing:
            expected[aircraft] = differing
    by_os = fixture.setdefault("outputs_by_os", {})
    by_os.pop(os_name, None)
    if expected:
        by_os[os_name] = expected
    if not by_os:
        fixture.pop("outputs_by_os")
    fixture.setdefault("os_captures", {})[os_name] = dict(
        capture_tool="docs/research/ground-physics/GP-12/evidence/fixed-brake-input/construction/",
        engine=r0["engine"], reference=r0["reference"], nitro_06_r3_reference=r3["reference"],
        nitro_06_r3_aircraft=sorted(GLOW_IDS),
        differing_from_outputs={aircraft: sorted(fields) for aircraft, fields in expected.items()})
    with open(fixture_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(fixture, indent="\t", sort_keys=True, ensure_ascii=False) + "\n")
    print("%s: %d aircraft differ from outputs" % (os_name, len(expected)))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
