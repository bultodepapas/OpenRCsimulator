"""Instrument and reduce simulation cost in a disposable prepared-cost app copy."""
from pathlib import Path


TIMERS = (
    "simulation_preflight",
    "simulation_pre_step_validation",
    "simulation_current_loads",
    "simulation_current_load_validation",
    "simulation_rotor_callback",
    "simulation_rotor_validation",
    "simulation_rk_stage_loads",
    "simulation_rk_load_validation",
    "simulation_rk_callback",
    "simulation_rigidbody_k1",
    "simulation_rigidbody_stages",
    "simulation_derivative_validation_k1",
    "simulation_derivative_validation_stages",
    "simulation_stage_state_validation",
    "simulation_final_state_validation",
    "simulation_k1_derivative_call",
    "simulation_rk_axpy",
    "simulation_rk_finish",
    "simulation_tick_commit",
    "simulation_checkpoint_bookkeeping",
    "simulation_signal_emit",
)

TIMER_DEFINITIONS = (
    {"name": "simulation_preflight", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "fixed-clock, state, configuration, inertia-cache and input guards"},
    {"name": "simulation_pre_step_validation", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "validation of the pre-step auxiliary result; pre_step_inclusive is reported separately"},
    {"name": "simulation_current_loads", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "k1 load callback, including its nested measured force components"},
    {"name": "simulation_current_load_validation", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "validation of the k1 load callback result"},
    {"name": "simulation_rotor_callback", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "rotor-momentum callback"},
    {"name": "simulation_rotor_validation", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "validation of rotor momentum"},
    {"name": "simulation_rk_stage_loads", "parent": "simulation_rk_callback", "calls_per_tick": 3,
     "meaning": "k2/k3/k4 load callbacks, including nested measured force components"},
    {"name": "simulation_rk_load_validation", "parent": "simulation_rk_callback", "calls_per_tick": 3,
     "meaning": "validation of k2/k3/k4 load results"},
    {"name": "simulation_rk_callback", "parent": "step_total", "calls_per_tick": 3,
     "meaning": "integrator dispatch into the k2/k3/k4 simulation derivative closure"},
    {"name": "simulation_rigidbody_k1", "parent": "simulation_k1_derivative_call", "calls_per_tick": 1,
     "meaning": "rigid-body derivative for the reused k1 load evaluation"},
    {"name": "simulation_rigidbody_stages", "parent": "simulation_rk_callback", "calls_per_tick": 3,
     "meaning": "rigid-body derivatives for k2/k3/k4"},
    {"name": "simulation_derivative_validation_k1", "parent": "simulation_k1_derivative_call", "calls_per_tick": 1,
     "meaning": "validation of the k1 rigid-body derivative"},
    {"name": "simulation_derivative_validation_stages", "parent": "simulation_rk_callback", "calls_per_tick": 3,
     "meaning": "validation of k2/k3/k4 rigid-body derivatives"},
    {"name": "simulation_stage_state_validation", "parent": "simulation_rk_callback", "calls_per_tick": 3,
     "meaning": "validation before each k2/k3/k4 load evaluation"},
    {"name": "simulation_final_state_validation", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "validation of the integrated state before commit"},
    {"name": "simulation_k1_derivative_call", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "k1 derivative dispatch; contains the k1 rigid-body derivative and validation"},
    {"name": "simulation_rk_axpy", "parent": "simulation_rk_callback", "calls_per_tick": 3,
     "meaning": "three RK4 stage-state axpy operations, evaluated as callback arguments"},
    {"name": "simulation_rk_finish", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "RK4 weighted sum and attitude normalization"},
    {"name": "simulation_tick_commit", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "previous/current state, tick, loads and smoothed timing assignments"},
    {"name": "simulation_checkpoint_bookkeeping", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "copying the latest valid simulation boundary"},
    {"name": "simulation_signal_emit", "parent": "step_total", "calls_per_tick": 1,
     "meaning": "stepped signal dispatch"},
)


def replace(source: str, old: str, new: str, path: Path) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"Expected one simulation instrumentation anchor in {path}: {old!r}")
    return source.replace(old, new, 1)


def instrument(app: Path) -> dict:
    """Patch only the already-staged app and return JSON-serializable timer metadata."""
    simulation = app / "sim/simulation.gd"
    source = simulation.read_text(encoding="utf-8")
    if source.count("func step() -> void:") != 1 or source.count("\n\nfunc _physics_process") != 1:
        raise RuntimeError("Missing or ambiguous simulation step scope")
    before_step, source = source.split("func step() -> void:", 1)
    source, after_step = source.split("\n\nfunc _physics_process", 1)

    source = replace(source, "\tvar t := time()", "\tvar t := time()\n"
        "\tvar _sim_cost_preflight_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0", simulation)
    source = replace(source, "\tvar old_aux := aux.duplicate()", 
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_preflight\", Time.get_ticks_usec() - _sim_cost_preflight_started)\n"
        "\tvar old_aux := aux.duplicate()", simulation)
    source = replace(source,
        "\tif not _array_is_finite(next_aux) or next_aux.size() != old_aux.size():",
        "\tvar _sim_cost_aux_validation_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar _sim_cost_aux_valid: bool = _array_is_finite(next_aux) and next_aux.size() == old_aux.size()\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_pre_step_validation\", Time.get_ticks_usec() - _sim_cost_aux_validation_started)\n"
        "\tif not _sim_cost_aux_valid:", simulation)
    source = replace(source,
        "\tvar current_loads: Variant = _stage_loads(combined, t)\n\tif not _loads_are_valid(current_loads):",
        "\tvar _sim_cost_current_loads_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar current_loads: Variant = _stage_loads(combined, t)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_current_loads\", Time.get_ticks_usec() - _sim_cost_current_loads_started)\n"
        "\tvar _sim_cost_current_load_validation_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar _sim_cost_current_loads_valid: bool = _loads_are_valid(current_loads)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_current_load_validation\", Time.get_ticks_usec() - _sim_cost_current_load_validation_started)\n"
        "\tif not _sim_cost_current_loads_valid:", simulation)
    source = replace(source, "\tvar rotor: Variant = rotor_momentum.call(aux) # held constant during RK4, like aux\n"
        "\tif not _array_is_finite(rotor) or (not rotor.is_empty() and rotor.size() != 3):",
        "\tvar _sim_cost_rotor_callback_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar rotor: Variant = rotor_momentum.call(aux) # held constant during RK4, like aux\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_rotor_callback\", Time.get_ticks_usec() - _sim_cost_rotor_callback_started)\n"
        "\tvar _sim_cost_rotor_validation_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar _sim_cost_rotor_valid: bool = _array_is_finite(rotor) and (rotor.is_empty() or rotor.size() == 3)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_rotor_validation\", Time.get_ticks_usec() - _sim_cost_rotor_validation_started)\n"
        "\tif not _sim_cost_rotor_valid:", simulation)
    source = replace(source,
        "\tvar derive := func(s: PackedFloat64Array, l: PackedFloat64Array, stage_t: float) -> PackedFloat64Array:\n"
        "\t\tvar derivative := RB.derivative(s, mass, inertia, _inertia_inv, M.v3(l[0], l[1], l[2]), M.v3(l[3], l[4], l[5]), gravity, h)\n"
        "\t\tif not _array_is_finite(derivative, RB.SIZE):",
        "\tvar derive := func(s: PackedFloat64Array, l: PackedFloat64Array, stage_t: float, is_k1: bool) -> PackedFloat64Array:\n"
        "\t\tvar _sim_cost_rb_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\t\tvar derivative := RB.derivative(s, mass, inertia, _inertia_inv, M.v3(l[0], l[1], l[2]), M.v3(l[3], l[4], l[5]), gravity, h)\n"
        "\t\tif E0b6pProfiler.enabled:\n"
        "\t\t\tE0b6pProfiler.add(\"simulation_rigidbody_k1\" if is_k1 else \"simulation_rigidbody_stages\", Time.get_ticks_usec() - _sim_cost_rb_started)\n"
        "\t\tvar _sim_cost_derivative_validation_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\t\tvar _sim_cost_derivative_valid: bool = _array_is_finite(derivative, RB.SIZE)\n"
        "\t\tif E0b6pProfiler.enabled:\n"
        "\t\t\tE0b6pProfiler.add(\"simulation_derivative_validation_k1\" if is_k1 else \"simulation_derivative_validation_stages\", Time.get_ticks_usec() - _sim_cost_derivative_validation_started)\n"
        "\t\tif not _sim_cost_derivative_valid:", simulation)
    source = replace(source, "\t\tif not _stage_state_is_valid(s):\n"
        "\t\t\tstage_error.message = \"RK stage state is nonfinite, malformed, or has a degenerate quaternion\"\n"
        "\t\t\treturn _zero_derivative()\n"
        "\t\tvar l: Variant = _stage_loads(s, stage_t)\n"
        "\t\tif not _loads_are_valid(l):\n"
        "\t\t\tstage_error.message = \"RK stage loads are nonfinite or malformed\"\n"
        "\t\t\treturn _zero_derivative()\n"
        "\t\treturn derive.call(s, l, stage_t)",
        "\t\tvar _sim_cost_stage_state_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\t\tvar _sim_cost_stage_state_valid: bool = _stage_state_is_valid(s)\n"
        "\t\tif E0b6pProfiler.enabled:\n"
        "\t\t\tE0b6pProfiler.add(\"simulation_stage_state_validation\", Time.get_ticks_usec() - _sim_cost_stage_state_started)\n"
        "\t\tif not _sim_cost_stage_state_valid:\n"
        "\t\t\tstage_error.message = \"RK stage state is nonfinite, malformed, or has a degenerate quaternion\"\n"
        "\t\t\treturn _zero_derivative()\n"
        "\t\tvar _sim_cost_stage_load_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\t\tvar l: Variant = _stage_loads(s, stage_t)\n"
        "\t\tif E0b6pProfiler.enabled:\n"
        "\t\t\tE0b6pProfiler.add(\"simulation_rk_stage_loads\", Time.get_ticks_usec() - _sim_cost_stage_load_started)\n"
        "\t\tvar _sim_cost_rk_load_validation_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\t\tvar _sim_cost_rk_loads_valid: bool = _loads_are_valid(l)\n"
        "\t\tif E0b6pProfiler.enabled:\n"
        "\t\t\tE0b6pProfiler.add(\"simulation_rk_load_validation\", Time.get_ticks_usec() - _sim_cost_rk_load_validation_started)\n"
        "\t\tif not _sim_cost_rk_loads_valid:\n"
        "\t\t\tstage_error.message = \"RK stage loads are nonfinite or malformed\"\n"
        "\t\t\treturn _zero_derivative()\n"
        "\t\treturn derive.call(s, l, stage_t, false)", simulation)
    source = replace(source, "\tvar next_state := RK.rk4_step_at(combined, t, dt(), f, derive.call(combined, current_loads, t))",
        "\tvar _sim_cost_k1_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar k1: PackedFloat64Array = derive.call(combined, current_loads, t, true)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_k1_derivative_call\", Time.get_ticks_usec() - _sim_cost_k1_started)\n"
        "\tvar next_state := RK.rk4_step_at(combined, t, dt(), f, k1)", simulation)
    source = replace(source, "\tif not _stage_state_is_valid(next_state):\n"
        "\t\taux = old_aux\n"
        "\t\t_fail_safe(\"step rejected: integrated state is nonfinite, malformed, or has a degenerate quaternion\")",
        "\tvar _sim_cost_final_state_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar _sim_cost_final_state_valid: bool = _stage_state_is_valid(next_state)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_final_state_validation\", Time.get_ticks_usec() - _sim_cost_final_state_started)\n"
        "\tif not _sim_cost_final_state_valid:\n"
        "\t\taux = old_aux\n"
        "\t\t_fail_safe(\"step rejected: integrated state is nonfinite, malformed, or has a degenerate quaternion\")", simulation)
    source = replace(source, "\tprevious = state.duplicate()", "\tvar _sim_cost_commit_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tprevious = state.duplicate()", simulation)
    source = replace(source, "\t_remember_valid_state()\n\tstepped.emit(tick, time(), state, last_loads, inputs, aux)",
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_tick_commit\", Time.get_ticks_usec() - _sim_cost_commit_started)\n"
        "\tvar _sim_cost_checkpoint_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\t_remember_valid_state()\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_checkpoint_bookkeeping\", Time.get_ticks_usec() - _sim_cost_checkpoint_started)\n"
        "\tvar _sim_cost_signal_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tstepped.emit(tick, time(), state, last_loads, inputs, aux)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_signal_emit\", Time.get_ticks_usec() - _sim_cost_signal_started)", simulation)
    simulation.write_text(before_step + "func step() -> void:" + source + "\n\nfunc _physics_process" + after_step, encoding="utf-8")

    integrator = app / "physics/integrator.gd"
    source = integrator.read_text(encoding="utf-8")
    source = replace(source, "extends RefCounted", "extends RefCounted\n"
        "const E0b6pProfiler := preload(\"res://tests/e0b6p_attribution/profiler.gd\")", integrator)
    source = replace(source, "static func axpy(a: PackedFloat64Array, k: float, b: PackedFloat64Array) -> PackedFloat64Array:\n"
        "\tvar out := a.duplicate()", "static func axpy(a: PackedFloat64Array, k: float, b: PackedFloat64Array) -> PackedFloat64Array:\n"
        "\tvar _sim_cost_axpy_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar out := a.duplicate()", integrator)
    source = replace(source, "\treturn out\n\n\n## k1_given", "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_rk_axpy\", Time.get_ticks_usec() - _sim_cost_axpy_started)\n"
        "\treturn out\n\n\n## k1_given", integrator)
    for old, varname in (
        ("var k2: PackedFloat64Array = f.call(axpy(s, dt / 2.0, k1), t + dt / 2.0)", "k2"),
        ("var k3: PackedFloat64Array = f.call(axpy(s, dt / 2.0, k2), t + dt / 2.0)", "k3"),
        ("var k4: PackedFloat64Array = f.call(axpy(s, dt, k3), t + dt)", "k4"),
    ):
        started = f"_sim_cost_callback_{varname}_started"
        replacement = f"var {started}: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n\t{old}\n"
        replacement += f"\tif E0b6pProfiler.enabled:\n\t\tE0b6pProfiler.add(\"simulation_rk_callback\", Time.get_ticks_usec() - {started})"
        source = replace(source, "\t" + old, "\t" + replacement, integrator)
    source = replace(source,
        "static func _finish_step(s: PackedFloat64Array, dt: float, k1: PackedFloat64Array, k2: PackedFloat64Array, k3: PackedFloat64Array, k4: PackedFloat64Array) -> PackedFloat64Array:\n"
        "\tvar out := s.duplicate()",
        "static func _finish_step(s: PackedFloat64Array, dt: float, k1: PackedFloat64Array, k2: PackedFloat64Array, k3: PackedFloat64Array, k4: PackedFloat64Array) -> PackedFloat64Array:\n"
        "\tvar _sim_cost_finish_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar out := s.duplicate()", integrator)
    source = replace(source, "\treturn normalize_attitude(out)\n\n\nstatic func normalize_attitude", "\tvar normalized := normalize_attitude(out)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"simulation_rk_finish\", Time.get_ticks_usec() - _sim_cost_finish_started)\n"
        "\treturn normalized\n\n\nstatic func normalize_attitude", integrator)
    integrator.write_text(source, encoding="utf-8")
    return {"format": "openrc-e0b6p-simulation-timers v1", "timers": [dict(item) for item in TIMER_DEFINITIONS],
            "accounting": "reduced simulation buckets partition rest sim.step after subtracting pre_step_inclusive and the four measured force families"}


def reduce(profile: dict, ticks: int) -> dict[str, float]:
    """Return disjoint simulation buckets in µs/tick; their sum equals old rest sim.step."""
    if ticks <= 0:
        raise RuntimeError("Tick count must be positive")
    calls = profile.get("calls", {})
    elapsed = profile.get("elapsed_usec", {})
    required = set(TIMERS) | {"step_total", "pre_step_inclusive", "air_dynamics", "aero_loads",
                              "propulsion_loads", "slipstream_loads", "ground_loads"}
    if not required.issubset(calls) or not required.issubset(elapsed):
        raise RuntimeError("Missing simulation or whole-tick timer/counter")
    expected = {
        "simulation_preflight": ticks,
        "simulation_pre_step_validation": ticks,
        "simulation_current_loads": ticks,
        "simulation_current_load_validation": ticks,
        "simulation_rotor_callback": ticks,
        "simulation_rotor_validation": ticks,
        "simulation_rk_stage_loads": 3 * ticks,
        "simulation_rk_load_validation": 3 * ticks,
        "simulation_rk_callback": 3 * ticks,
        "simulation_rigidbody_k1": ticks,
        "simulation_rigidbody_stages": 3 * ticks,
        "simulation_derivative_validation_k1": ticks,
        "simulation_derivative_validation_stages": 3 * ticks,
        "simulation_stage_state_validation": 3 * ticks,
        "simulation_final_state_validation": ticks,
        "simulation_k1_derivative_call": ticks,
        "simulation_rk_axpy": 3 * ticks,
        "simulation_rk_finish": ticks,
        "simulation_tick_commit": ticks,
        "simulation_checkpoint_bookkeeping": ticks,
        "simulation_signal_emit": ticks,
    }
    expected.update({name: ticks for name in ("step_total", "pre_step_inclusive")})
    expected.update({name: 4 * ticks for name in (
        "air_dynamics", "aero_loads", "propulsion_loads", "slipstream_loads", "ground_loads")})
    for name, count in expected.items():
        if isinstance(calls[name], bool) or not isinstance(calls[name], int) or calls[name] != count:
            raise RuntimeError(f"Unexpected {name} call count: {calls[name]} != {count}")
    def e(name: str) -> int:
        value = elapsed[name]
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise RuntimeError(f"Invalid elapsed time for {name}: {value!r}")
        return value

    # These force timers are children of all four load callbacks. Splitting the
    # callback sites lets the RK callback's remaining closure cost be isolated.
    force_children = ("air_dynamics", "aero_loads", "propulsion_loads", "slipstream_loads", "ground_loads")
    all_force_usec = sum(e(name) for name in force_children)
    current_load = e("simulation_current_loads")
    stage_loads = e("simulation_rk_stage_loads")
    # Component timers aggregate four calls and are not individually attributable
    # to k1 versus k2/k3/k4; keep the aggregate dispatch residue as one bucket.
    load_dispatch_glue = current_load + stage_loads - all_force_usec

    stage_children = (
        e("simulation_rk_stage_loads"),
        e("simulation_rigidbody_stages"),
        e("simulation_rk_load_validation"),
        e("simulation_derivative_validation_stages"),
        e("simulation_stage_state_validation"),
        e("simulation_rk_axpy"),
    )
    callback_glue = e("simulation_rk_callback") - sum(stage_children)
    k1_glue = e("simulation_k1_derivative_call") - e("simulation_rigidbody_k1") - e("simulation_derivative_validation_k1")
    if min(load_dispatch_glue, callback_glue, k1_glue) < 0:
        raise RuntimeError("Overlapping nested simulation timers")

    result = {
        "simulation_preflight": e("simulation_preflight"),
        "simulation_pre_step_validation": e("simulation_pre_step_validation"),
        "simulation_load_callback_glue": load_dispatch_glue,
        "simulation_current_load_validation": e("simulation_current_load_validation"),
        "simulation_rotor_callback": e("simulation_rotor_callback"),
        "simulation_rotor_validation": e("simulation_rotor_validation"),
        "simulation_rk_callback_glue": callback_glue,
        "simulation_rigidbody_derivative": e("simulation_rigidbody_k1") + e("simulation_rigidbody_stages"),
        "simulation_derivative_validation": e("simulation_derivative_validation_k1") + e("simulation_derivative_validation_stages"),
        "simulation_load_validation": e("simulation_rk_load_validation"),
        "simulation_stage_state_validation": e("simulation_stage_state_validation"),
        "simulation_final_state_validation": e("simulation_final_state_validation"),
        "simulation_k1_dispatch_glue": k1_glue,
        "simulation_rk_arithmetic": e("simulation_rk_axpy") + e("simulation_rk_finish"),
        "simulation_tick_commit": e("simulation_tick_commit"),
        "simulation_checkpoint_bookkeeping": e("simulation_checkpoint_bookkeeping"),
        "simulation_signal_emit": e("simulation_signal_emit"),
    }
    rest = e("step_total") - e("pre_step_inclusive") - all_force_usec
    residual = rest - sum(result.values())
    if residual < 0:
        raise RuntimeError(f"Simulation phases overlap whole-tick remainder by {-residual} µs")
    result["simulation_unattributed_glue"] = residual
    if sum(result.values()) != rest:
        raise RuntimeError("Simulation exclusive buckets do not sum to rest sim.step")
    return {name: value / ticks for name, value in result.items()}
