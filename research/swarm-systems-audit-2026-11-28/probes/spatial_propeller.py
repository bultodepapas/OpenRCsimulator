"""Build two stage-header versions in a disposable directory; no Godot install required."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("repo", type=Path)
args = parser.parse_args()
src = args.repo.resolve() / "research/native-kernel/src"
original = (src / "nk_stage.hpp").read_text()
def replace_one(text, original, replacement):
    assert text.count(original) == 1
    return text.replace(original, replacement)
candidate = replace_one(original, "if (!aero_valid || !prop_air.ok) {",
    "std::array<R, 3> local_tq{};\n\tbool local_tq_available = false;\n\tif (!aero_valid || !prop_air.ok) {")
candidate = replace_one(candidate, """const auto local_tq = !turbine && !m.glow.ready && m.spatial_weather && m.wake.enabled ?
\t\t\tprop_thrust_torque(prop_air.velocity.data(), rpm, m.prop, rho) : std::array<R, 3>{};""",
    """local_tq_available = !turbine && !m.glow.ready && m.spatial_weather && m.wake.enabled;
\t\tif (local_tq_available) local_tq = prop_thrust_torque(prop_air.velocity.data(), rpm, m.prop, rho);""")
candidate = replace_one(candidate, "prop_thrust_torque(m.spatial_weather ? prop_air.velocity.data() : air.v, rpm, m.prop, rho);",
    "local_tq_available ? local_tq : prop_thrust_torque(m.spatial_weather ? prop_air.velocity.data() : air.v, rpm, m.prop, rho);")
candidate = replace_one(candidate, "const auto tq = prop_thrust_torque(m.spatial_weather && spatial_flow.ok ? prop_air.velocity.data() : air.v,",
    "const auto tq = local_tq_available && spatial_flow.ok ? local_tq : prop_thrust_torque(m.spatial_weather && spatial_flow.ok ? prop_air.velocity.data() : air.v,")
flags = ["-std=c++17", "-O2", "-fno-fast-math", "-ffp-contract=off"]
def run(tmp, stage):
    (tmp / "nk_stage.hpp").write_text(stage)
    exe = tmp / "probe"
    subprocess.run(["g++", *flags, "-I", str(tmp), "-I", str(src), str(HERE / "spatial_propeller.cpp"),
                    "-Wl,--wrap=pow", "-o", str(exe)], check=True)
    return [line.split() for line in subprocess.check_output([str(exe)], text=True).splitlines()]
with tempfile.TemporaryDirectory() as work:
    base = run(Path(work), original)
    test = run(Path(work), candidate)
    # Break only the proposed wake/transport handoff, keeping the propulsion loads correct.
    wrong_wake = replace_one(candidate, "local_tq_available ? local_tq :",
                             "local_tq_available ? std::array<R, 3>{} :")
    wrong_wake = replace_one(wrong_wake, "local_tq_available && spatial_flow.ok ? local_tq :",
                             "local_tq_available && spatial_flow.ok ? std::array<R, 3>{} :")
    mutant = run(Path(work), wrong_wake)
assert len(base) == len(test) == 480
stats = collections.defaultdict(lambda: dict(rows=0, finite=0, current_pow=0, candidate_pow=0))
words = 0
digest = hashlib.sha256()
mutant_counts = collections.Counter()
for a, b, wrong in zip(base, test, mutant):
    assert a[:-1] == b[:-1], (a, b)
    words += len(a) - 14
    digest.update((" ".join(a[:-1]) + "\n").encode())
    spatial, wake, _, rpm, _, domain = a[:6]
    eligible = spatial == "1" and wake != "0" and domain == "0" and float(rpm) >= 1
    group = ("quasistatic" if wake == "1" else "transported") if eligible else "control"
    delta = int(a[-1])-int(b[-1])
    assert delta == (int(wake)*2 if eligible else 0), (a, b, group)
    if a[13:-1] != wrong[13:-1]:
        mutant_counts[group] += 1
    row = stats[group]
    row["rows"] += 1
    row["finite"] += int(a[7])
    row["current_pow"] += int(a[-1])
    row["candidate_pow"] += int(b[-1])
assert mutant_counts["quasistatic"] > 0 and mutant_counts["transported"] > 0 and mutant_counts["control"] == 0
print(json.dumps(dict(mutant_changed_output_cases=dict(mutant_counts), compiler=subprocess.check_output(["g++","--version"],text=True).splitlines()[0],
    flags=flags, cases=len(base), words=words, rows_sha256=digest.hexdigest(), groups=stats), indent=2))
