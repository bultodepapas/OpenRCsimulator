extends SceneTree

const Probe := preload("res://debug/render_probe.gd")
const Bridge := preload("res://debug/debug_bridge.gd")
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


class FakeRadio extends RefCounted:
    var connected := false
    var armed := true
    var auxiliary_enabled := true


class FakeRoundedProperty extends RefCounted:
    var amount := 1.0:
        set(value):
            amount = float(PackedFloat32Array([value])[0])


class FakeSim extends Node:
    var paused := false
    func set_paused(value: bool) -> void:
        paused = value


class FakeSession extends Node:
    var sim := FakeSim.new()
    var radio := FakeRadio.new()
    var pending_mode := ""
    var holds := {}
    var crash := {}
    var pause_reason := ""
    var hold_calls := 0
    func _init() -> void:
        add_child(sim)
    # Model the real hold side effects; a refusal must occur before any of them.
    func hold(reason: String) -> void:
        hold_calls += 1
        pending_mode = ""
        radio.auxiliary_enabled = false
        if radio.connected: radio.armed = false
        holds[reason] = true
        sim.set_paused(true)
    func release(reason: String) -> void:
        holds.erase(reason)
    func resume() -> void:
        if holds.is_empty(): sim.set_paused(false)


func check_ablation_freeze() -> void:
    var bridge := Bridge.new() # Not added to the tree: never opens a debug TCP port.
    var session := FakeSession.new()
    session.radio.connected = true
    check("connected controller refusal is explicit", "connected controller" in bridge._ablation_freeze_refusal(session))
    check("connected controller is rejected before hold", not bridge._begin_ablation_pause(session) \
        and session.hold_calls == 0 and session.radio.armed and session.radio.auxiliary_enabled \
        and session.holds.is_empty() and not session.sim.paused)
    session.radio.connected = false
    session.pending_mode = "idle_up"
    check("pending helicopter mode refusal is explicit", "mode change is pending" in bridge._ablation_freeze_refusal(session))
    check("pending mode is rejected before hold", not bridge._begin_ablation_pause(session) \
        and session.hold_calls == 0 and session.pending_mode == "idle_up" and session.radio.auxiliary_enabled \
        and session.holds.is_empty() and not session.sim.paused)
    session.pending_mode = ""
    session.sim.set_paused(true)
    var metadata: Dictionary = bridge._ablation_freeze_metadata(true)
    session.sim.set_paused(false) # Another owner resumes during an unowned run.
    var after_resume: Dictionary = bridge._ablation_freeze_metadata(true)
    check("unowned paused start never claims a frozen run", metadata.paused_at_start and not metadata.frozen \
        and after_resume.paused_at_start and not after_resume.frozen)
    check("safe session can acquire an owned hold", bridge._begin_ablation_pause(session) and session.hold_calls == 1)
    metadata = bridge._ablation_freeze_metadata(false)
    check("owned valid hold reports frozen", not metadata.paused_at_start and metadata.frozen)
    bridge._finish_ablation_pause()
    bridge.free()
    session.free()


func _init() -> void:
    check_ablation_freeze()
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

    var rounded := FakeRoundedProperty.new()
    var converted: Dictionary = Probe._toggle("rounded", "flag", [[rounded, "amount"]], [0.3])
    converted.apply.call()
    check("float32-converted setter readback remains owned", rounded.amount != 0.3 and converted.held.call())
    converted.restore.call()
    check("float32-converted property restores its original value", rounded.amount == 1.0)
    var scale_viewport := SubViewport.new()
    var near: Dictionary = Probe._toggle("scale", "flag", [[scale_viewport, "scaling_3d_scale"]], [0.5])
    near.apply.call()
    scale_viewport.scaling_3d_scale = 0.500001
    var external_scale := scale_viewport.scaling_3d_scale
    check("nearby external float is not owned", external_scale != 0.5 and not near.held.call())
    near.restore.call()
    check("nearby external float survives restore", scale_viewport.scaling_3d_scale == external_scale)
    scale_viewport.free()

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
        check("GPU delta follows phase availability: " + status,
            (observed.rows[0].saved_gpu_ms != null and observed.rows[0].saved_pct != null) if status == "unverified_freshness" \
            else (observed.rows[0].saved_gpu_ms == null and observed.rows[0].saved_pct == null))

    var invalid := SyntheticProbe.new([2.0, 0.0, 2.0])
    var invalid_run := Probe.Ablation.new(invalid, [{name = "a", kind = "layer"}], 2, 5)
    while not invalid_run.advance(): pass
    var invalid_result: Dictionary = invalid_run.result()
    check("zero overrides even a synthetic-valid claim", not invalid_result.rows[0].significant \
        and invalid_result.rows[0].gpu_timing_status == "mixed_or_unavailable" \
        and invalid_result.rows[0].saved_gpu_ms == null and invalid_result.rows[0].saved_pct == null)

    var mixed := SyntheticProbe.new([0.0, 4.0, 10.0])
    var mixed_run := Probe.Ablation.new(mixed, [{name = "a", kind = "layer"}], 2, 5)
    while not mixed_run.advance(): pass
    var mixed_result: Dictionary = mixed_run.result()
    var mixed_row: Dictionary = mixed_result.rows[0]
    check("0/4/10 GPU phases cannot create a saving", mixed_row.saved_gpu_ms == null \
        and mixed_row.saved_pct == null and not mixed_row.significant \
        and mixed_row.gpu_timing_status == "mixed_or_unavailable", str(mixed_row))
    check("invalid phase keeps raw observations and non-GPU counters", mixed_row.baseline_before_gpu_ms == 0.0 \
        and mixed_row.gpu_ms == 4.0 and mixed_row.baseline_after_gpu_ms == 10.0 \
        and mixed_row.saved_draw_calls == 0, str(mixed_row))
    check("invalid aggregate baseline and noise have explicit status", \
        mixed_result.baseline.gpu_timing_status == "mixed_or_unavailable" \
        and mixed_result.noise_timing_status == "mixed_or_unavailable" \
        and mixed_row.baseline_before_gpu_timing_status == "unavailable_or_zero" \
        and mixed_row.baseline_after_gpu_timing_status == "synthetic_valid")

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
