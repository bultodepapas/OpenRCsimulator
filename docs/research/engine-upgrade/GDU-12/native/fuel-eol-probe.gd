extends SceneTree

const Fleet = preload("fleet.gd")
const NativeStage = preload("res://sim/native_stage.gd")

func _initialize() -> void:
    var collector = Fleet.new()
    var records = []
    for row: Dictionary in Fleet._fleet_declared_rows():
        if row.get("expected") != "reference-refusal" or not Fleet._fleet_is_runway_boundary(row):
            continue
        var observed: Dictionary = collector._build_fleet_session(row, NativeStage.BACKEND_REFERENCE)
        var proof: Dictionary = observed.get("startup_proof", {})
        var expected: Dictionary = Fleet.RUNWAY_START_BOUNDARIES[row.aircraft].batteries[row.battery]
        records.append({"row": row, "reason": observed.get("reason", ""), "phase": observed.get("phase", ""),
            "expected_refusal": Fleet._fleet_expected_refusal(row, observed),
            "proof_valid": Fleet._fleet_start_proof_valid(row, proof, NativeStage.BACKEND_REFERENCE),
            "expected": expected, "proof": proof})
        if observed.get("ok", false): observed.session.free()
    collector.free()
    var args = OS.get_cmdline_user_args()
    if args.size() != 1:
        push_error("Expected one output path")
        quit(1)
        return
    var file = FileAccess.open(args[0], FileAccess.WRITE)
    if file == null:
        push_error("Cannot write output")
        quit(1)
        return
    file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "records": records}, "  "))
    file.close()
    print("NK3_STARTUP_CAPTURE rows=", records.size(), " verdict=pass")
    quit(0)
