extends SceneTree

# Diagnostic only: compare standalone and production-style common RK paths.
# Expected faults are recorded as data, not treated as supported flight cases.

const Data = preload("res://physics/rotorcraft_data.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Sim = preload("res://sim/simulation.gd")

func _initialize() -> void:
    var loaded: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
    if not loaded.ok:
        print(JSON.stringify({"fatal": "profile_load", "errors": loaded.errors}))
        quit(2)
        return
    var context: Dictionary = loaded.context
    var sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
    var body: PackedFloat64Array = RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, 0.0),
        PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), M.v3(0.0, 0.0, 0.0))
    var start: PackedFloat64Array = body.duplicate()
    start.append_array(PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))

    _run_case("spool_from_rest_3mps_wind", start, context, sticks, false, M.v3(3.0, 0.0, 0.0))
    var coast: PackedFloat64Array = start.duplicate()
    coast[Flight.OMEGA] = 0.001
    _run_case("coast_down_0.001_rad_s_calm", coast, context, sticks, true, M.v3(0.0, 0.0, 0.0))
    quit(0)

func _run_case(label: String, state: PackedFloat64Array, context: Dictionary,
        sticks: PackedFloat64Array, zero_hold: bool, wind: PackedFloat64Array) -> void:
    var initial: Dictionary = Flight.evaluate(state, context, sticks, "normal", false, zero_hold, wind)
    var standalone: Dictionary = Flight.rk4_step_at(state, 0.0, 1.0 / 240.0, context,
        sticks, "normal", false, zero_hold, wind)

    var sim = Sim.new()
    sim.mass = context.mass_kg
    sim.gravity = context.gravity_m_s2
    sim.inertia = context.inertia_body_kg_m2.duplicate()
    sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
    sim.continuous = state.slice(RB.SIZE)
    var last_fault: Array[String] = [""]
    sim.model.stage = func(body_state: PackedFloat64Array, continuous: PackedFloat64Array,
            t: float) -> Dictionary:
        var full: PackedFloat64Array = body_state.duplicate()
        full.append_array(continuous)
        var result: Dictionary = Flight.evaluate(full, context, sticks, "normal", false, zero_hold, wind)
        if not result.ok:
            last_fault[0] = str(result.get("fault", "unknown")) + ": " + str(result.get("message", ""))
            return {}
        return {
            "loads": result.loads,
            "derivative": result.derivative,
            "rotor_momentum": result.rotor_momentum,
            "body_derivative": result.body_derivative,
        }
    var reset_ok: bool = sim.reset(state.slice(0, RB.SIZE))
    if reset_ok:
        sim.step()
    var common: Dictionary = {
        "reset_ok": reset_ok,
        "fault_reason": sim.fault_reason,
        "tick": sim.tick,
        "last_flight_fault": last_fault[0],
        "continuous_step_installed": sim.model.step_policy.is_valid(),
    }
    sim.free()
    print(JSON.stringify({
        "case": label,
        "wind_ned_m_s": Array(wind),
        "initial_evaluate": {
            "ok": initial.get("ok", false),
            "fault": initial.get("fault", ""),
            "message": initial.get("message", ""),
            "spin_acceleration_rad_s2": initial.get("derivative", PackedFloat64Array([NAN]))[0]
                if initial.get("ok", false) else null,
        },
        "standalone_rk4": {
            "ok": standalone.get("ok", false),
            "fault": standalone.get("fault", ""),
            "message": standalone.get("message", ""),
            "event": standalone.get("event", ""),
            "elapsed_s": standalone.get("elapsed_s", null),
            "remaining_s": standalone.get("remaining_s", null),
            "omega_end_rad_s": standalone.get("state", PackedFloat64Array())[Flight.OMEGA]
                if standalone.get("ok", false) else null,
        },
        "common_simulation": common,
    }))
