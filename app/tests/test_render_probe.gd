extends SceneTree

const Probe := preload("res://debug/render_probe.gd")
var failures := 0

func check(label: String, condition: bool, detail: String = "") -> void:
    if not condition:
        failures += 1
        printerr("FAIL ", label, " ", detail)
    else:
        print("ok   ", label)


class SyntheticProbe extends "res://debug/render_probe.gd":
    var phase_values: Array = []
    var sample_index := 0
    var status := "synthetic_valid"
    func _init(values: Array, timing_status: String = "synthetic_valid") -> void:
        super(null)
        phase_values = values
        status = timing_status
    func sample() -> Dictionary:
        var phase := floori(float(sample_index) / 5.0)
        sample_index += 1
        return {gpu_ms = phase_values[phase], draw_calls = 10, primitives = 100,
            objects = 5, root_cpu_ms = 0.1, gpu_timing_status = status}


func _init() -> void:
    var node := Node3D.new()
    var toggle: Dictionary = Probe._toggle("node", "layer", [[node, "visible"]], [false])
    node.visible = false # changed after target discovery, before its phase
    toggle.apply.call()
    check("already-off phase is flagged", not toggle.held.call())
    toggle.restore.call()
    check("phase-start value is restored, not discovery value", not node.visible)
    node.visible = true
    toggle.apply.call()
    node.visible = true # app takes ownership while the probe is active
    check("external change is detected", not toggle.held.call())
    toggle.restore.call()
    check("external change is not overwritten", node.visible)
    var light := OmniLight3D.new()
    var energy: Dictionary = Probe._toggle("light", "layer", [[light, "light_energy"]], [0.0])
    light.light_energy = 1.5 # changed after discovery; this phase cannot claim the original comparison
    energy.apply.call()
    check("pre-phase app change invalidates comparison", not energy.held.call())
    energy.restore.call()
    check("pre-phase app value is restored", is_equal_approx(light.light_energy, 1.5))
    energy = Probe._toggle("light", "layer", [[light, "light_energy"]], [0.0])
    energy.apply.call()
    light.light_energy = 2.0
    energy.restore.call()
    check("changed live value survives restore", is_equal_approx(light.light_energy, 2.0))
    var lost := Node3D.new()
    var survivor := Node3D.new()
    var missing: Dictionary = Probe._toggle("lost", "layer", [[lost, "visible"], [survivor, "visible"]], [false, false])
    missing.apply.call()
    lost.free()
    check("freed target is not held", not missing.held.call())
    missing.restore.call() # no invalid-instance script error
    check("freed target does not prevent restoring another binding", survivor.visible)

    var two := SyntheticProbe.new([1.0, 1.4, 2.0, 2.4, 3.0])
    var run := Probe.Ablation.new(two, [{name = "a", kind = "layer"}, {name = "b", kind = "layer"}], 2, 5)
    while not run.advance(): pass
    var result: Dictionary = run.result()
    check("two baseline steps cannot become zero noise", is_equal_approx(result.noise_ms, 1.0), str(result))
    check("drift-sized savings are not significant", not result.rows[0].significant and not result.rows[1].significant)

    var moving := Node3D.new()
    var moving_target: Dictionary = Probe._toggle("moving", "layer", [[moving, "visible"]], [false])
    var moving_probe := SyntheticProbe.new([2.0, 1.0, 2.0])
    var moving_run := Probe.Ablation.new(moving_probe, [moving_target], 2, 5)
    while true:
        if moving_run._index == 1 and moving_run._frame == 1: moving.visible = true
        if moving_run._index == 1 and moving_run._frame == 2: moving.visible = false
        if moving_run.advance(): break
    var moved: Dictionary = moving_run.result()
    check("temporary phase override is detected", moved.rows[0].overridden and not moved.rows[0].significant, str(moved))
    check("probe restores a still-owned toggle", moving.visible)

    for status: String in ["unverified_freshness", "unavailable_or_zero"]:
        var values := [2.0, 1.0, 2.0] if status == "unverified_freshness" else [0.0, 0.0, 0.0]
        var uncertain := SyntheticProbe.new(values, status)
        var trial := Probe.Ablation.new(uncertain, [{name = "a", kind = "layer"}], 2, 5)
        while not trial.advance(): pass
        var observed: Dictionary = trial.result()
        check("unverified timing cannot claim significance: " + status,
            not observed.rows[0].significant and observed.rows[0].gpu_timing_status == status)

    var invalid := SyntheticProbe.new([2.0, 0.0, 2.0])
    var invalid_run := Probe.Ablation.new(invalid, [{name = "a", kind = "layer"}], 2, 5)
    while not invalid_run.advance(): pass
    var invalid_result: Dictionary = invalid_run.result()
    check("zero overrides even a synthetic-valid claim", not invalid_result.rows[0].significant \
        and invalid_result.rows[0].gpu_timing_status == "mixed_or_unavailable")

    var viewport := SubViewport.new()
    var root_probe := Probe.new(viewport)
    check("half resolution refuses non-bilinear provider", not Probe._can_half_res(Viewport.SCALING_3D_MODE_FSR))
    check("half resolution permits bilinear", not root_probe._flag_target("@half_res").is_empty())
    node.free()
    light.free()
    moving.free()
    survivor.free()
    viewport.free()
    print("render probe: %d failed" % failures if failures else "all render probe checks passed")
    quit(1 if failures else 0)
