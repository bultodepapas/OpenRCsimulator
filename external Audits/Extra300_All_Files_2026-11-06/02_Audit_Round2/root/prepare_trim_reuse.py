"""Build isolated audit variants; never modify the checked-out application."""
from pathlib import Path
import difflib
import hashlib
import json

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "source" / "app"
RUNTIME = HERE / "runtime"
base = (SOURCE / "physics/trim.gd").read_text()
assert hashlib.sha256(base.encode()).hexdigest() == "a4d6be9967aa047464a11b00dcfbd24d7ca9822f98086ecf18460bff4dae8ea8", "Expected pinned 8e5f2f0 trim source"
assert (RUNTIME / "physics/trim.gd").read_text() == base

# Every exit in _solve_from has x_rpm belonging to the accepted x, including
# an unsuccessful line search. Limit the new reuse to finite-glow level trim.
prefix, suffix = base.split("## Electric trim uses the same six-axis equations", 1)
old_tail = "iterations, throws, model, g, rho, engine_charge_ratio)"
new_tail = "iterations, throws, model, g, rho, engine_charge_ratio, x_rpm if bounded_glow_level else NAN)"
assert prefix.count(old_tail) == 5
candidate = prefix.replace(old_tail, new_tail) + "## Electric trim uses the same six-axis equations" + suffix
old_signature = "static func _result(ok: bool, message: String, x: PackedFloat64Array, mode: String, V: float, r: PackedFloat64Array, iterations: int, throws: Dictionary, model: Dictionary, g: float, rho: float, engine_charge_ratio: float) -> Dictionary:"
new_signature = old_signature.replace("engine_charge_ratio: float)", "engine_charge_ratio: float, steady_rpm := NAN)")
assert candidate.count(old_signature) == 1
candidate = candidate.replace(old_signature, new_signature)
old_body = "\tvar e := _evaluate(x, mode, V, model, g, rho, engine_charge_ratio)\n\tvar rpm: float = float(e.rpm) if Propulsion.is_electric(model.propulsion) else _rpm(throttle, e.state, mode, model, rho, engine_charge_ratio)"
new_body = "\t# The bounded glow solve already owns the exact equilibrium at this final x.\n\t# Reuse that value for both the final loads and the reported RPM.\n\tvar e := _evaluate(x, mode, V, model, g, rho, engine_charge_ratio, steady_rpm)\n\tvar rpm: float = float(e.rpm) if Propulsion.is_electric(model.propulsion) else (steady_rpm if not is_nan(steady_rpm) else _rpm(throttle, e.state, mode, model, rho, engine_charge_ratio))"
assert candidate.count(old_body) == 1
candidate = candidate.replace(old_body, new_body)
(HERE / "trim_final_rpm_reuse.patch").write_text("".join(difflib.unified_diff(
    base.splitlines(True), candidate.splitlines(True),
    fromfile="a/app/physics/trim.gd", tofile="b/app/physics/trim.gd")))
(RUNTIME / "physics/audit_trim_candidate.gd").write_text(candidate)

def counted(code):
    code = code.replace("const N := 6", "static var audit_rpm_calls: int = 0\nstatic var audit_result_calls: int = 0\n\nconst N := 6", 1)
    rpm_line = "\treturn Propulsion.steady_rpm(throttle, u, model.propulsion, rho, engine_charge_ratio)"
    assert code.count(rpm_line) == 1
    code = code.replace(rpm_line, "\tif Propulsion.is_glow(model.propulsion):\n\t\taudit_rpm_calls += 1\n" + rpm_line)
    lines = code.splitlines(True)
    for index, line in enumerate(lines):
        if line.startswith("static func _result("):
            lines.insert(index + 1, "\taudit_result_calls += 1\n")
            break
    return "".join(lines)

(RUNTIME / "physics/audit_trim_counted_baseline.gd").write_text(counted(base))
(RUNTIME / "physics/audit_trim_counted_candidate.gd").write_text(counted(candidate))
cruise = (SOURCE / "physics/cruise_trim.gd").read_text()
for label, trim in [("candidate", "audit_trim_candidate"), ("counted_baseline", "audit_trim_counted_baseline"), ("counted_candidate", "audit_trim_counted_candidate")]:
    alt = cruise.replace("class_name CruiseTrim\n", "").replace('preload("res://physics/trim.gd")', 'preload("res://physics/' + trim + '.gd")')
    (RUNTIME / ("physics/audit_cruise_" + label + ".gd")).write_text(alt)
identity = {
    "source_commit": "8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd",
    "baseline_trim_sha256": hashlib.sha256(base.encode()).hexdigest(),
    "candidate_trim_sha256": hashlib.sha256(candidate.encode()).hexdigest(),
    "scope": "Only finite-glow level finalization reuses the accepted iterate's RPM; instrumented variants are never timed.",
}
(HERE / "trim_reuse_identity.json").write_text(json.dumps(identity, indent=2) + "\n")
print(json.dumps(identity))
