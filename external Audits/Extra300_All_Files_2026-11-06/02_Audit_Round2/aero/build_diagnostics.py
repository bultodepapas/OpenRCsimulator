"""Create fixture-only aero alternatives. Neither alternative is a proposed repair."""
from pathlib import Path
import hashlib

here = Path(__file__).resolve().parent
base = (here.parent / "source/app/physics/aero.gd").read_text()
assert hashlib.sha256(base.encode()).hexdigest() == "062ce4711837db206906a9e67b27e756787a2b7a7bddb48deaac0e1c84184d1d"
target = here / "runtime/physics"
assert target.is_dir(), "First copy the imported pinned app to aero/runtime"

old = "\t\t\tsources.append((speeds[i]/reference_speed) * (1.0-stall))"
new = """\t\t\tvar retained: float = 1.0-stall
\t\t\tvar candidate_polar: Dictionary = env.get("wing_polar", {})
\t\t\tif not candidate_polar.is_empty():
\t\t\t\tvar factors: PackedFloat64Array = candidate_polar.get("strip_factor", PackedFloat64Array())
\t\t\t\tvar sample_alpha: float = source_angle if factors.is_empty() else source_angle*factors[i]
\t\t\t\tretained = WingPolar.evaluate(sample_alpha, 0.0, candidate_polar)[2]
\t\t\tsources.append((speeds[i]/reference_speed) * retained)"""
assert base.count(old) == 1
(target / "aero_polar_probe.gd").write_text(base.replace(old, new))
old_normalizer = "\t\treference_speed = maxf(reference_speed, sqrt(f0*f0 + f1*f1 + f2*f2))"
new_normalizer = "\t\treference_speed = 20.0 # diagnostic only: freeze normalizer at zero-rate value of this fixture"
assert base.count(old_normalizer) == 1
(target / "aero_fixed_normalizer_probe.gd").write_text(base.replace(old_normalizer, new_normalizer))
print("Created two fixture-only alternatives; production aero.gd unchanged")
