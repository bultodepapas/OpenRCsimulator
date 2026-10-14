extends SceneTree

const CloudTransport = preload("res://render/weather/cloud_transport.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	var layer := {type = "cumulus", seed = 42, scale_m = 1000.0, drift_multiplier = 1.0, cluster_strength = 0.65}
	var selection := {motion = "follow_wind", wind_aloft_speed_mps = 0.0, wind_aloft_from_deg = 0.0}
	var state := CloudTransport.build(selection, [layer], [10.0, 0.0, 0.0], 0.0, 1.0, Vector2(0.004, 0.0015), [Vector2(3.0, 4.0)])
	_check("valid transport checkpoint shape", CloudTransport.validate(state))
	_check("quantized time is stable inside a cloud step", CloudTransport.layer_offset(state, 0, 0.0) == CloudTransport.layer_offset(state, 0, 0.99))
	_check("northward wind moves the texture southward", CloudTransport.layer_offset(state, 0, 1.0).is_equal_approx(Vector2(3.0, 4.01)))
	var at_one := CloudTransport.layer_offset(state, 0, 1.0)
	_check("repeated time reproduces the same offset", CloudTransport.layer_offset(state, 0, 1.0) == at_one)
	_check("rewind restores the original offset", CloudTransport.layer_offset(state, 0, 0.0) == Vector2(3.0, 4.0))
	var at_two := CloudTransport.layer_offset(state, 0, 2.0)
	var rebased := CloudTransport.rebase(state, 2.0)
	_check("rebase is a valid independent checkpoint", CloudTransport.validate(rebased) and rebased != state)
	_check("rebase preserves cloud position", CloudTransport.layer_offset(rebased, 0, 2.0).is_equal_approx(at_two))
	_check("checkpoint validation does not mutate input", CloudTransport.validate(state) and state.layers[0].anchor_offset == [3.0, 4.0])
	var bad: Dictionary = state.duplicate(true)
	bad.layers[0].anchor_offset[0] = 64.0
	_check("offset at noise period is rejected", not CloudTransport.validate(bad))
	bad = state.duplicate(true)
	bad.layers[0].velocity_cells_s[1] = INF
	_check("nonfinite transport velocity is rejected", not CloudTransport.validate(bad))
	var still_selection := selection.duplicate(true)
	still_selection.motion = "still"
	var still := CloudTransport.build(still_selection, [layer], [10.0, 0.0, 0.0], 10.0, 1.0, Vector2.ZERO, [Vector2(8.0, 9.0)])
	_check("still motion preserves its initial offset", CloudTransport.layer_offset(still, 0, 1000.0) == Vector2(8.0, 9.0))
	var precise_selection := {motion = "follow_wind", wind_aloft_speed_mps = 0.0, wind_aloft_from_deg = 0.0}
	var precise := CloudTransport.build(precise_selection, [layer], [0.0, 123.456, 0.0], 0.0, 1.0,
		Vector2(0.004, 0.0015), [[3.123456789, 4.987654321]])
	var precise_rebase := CloudTransport.rebase(precise, 123456.0)
	var precise_layer: Dictionary = precise.layers[0]
	var expected_x := fposmod(float(precise_layer.anchor_offset[0]) + float(precise_layer.velocity_cells_s[0]) * 123456.0, 64.0)
	_check("checkpoint rebase keeps scalar float64 offsets", precise_rebase.layers[0].anchor_offset[0] == expected_x)
	var distant_time := 999999999.0
	var material_pair: Array = CloudTransport.offsets(precise, distant_time)[0]
	var material_offset := Vector2(float(material_pair[0]), float(material_pair[1]))
	_check("storm snapshots and shader offsets agree after long runs",
		CloudTransport.layer_offset(precise, 0, distant_time) == material_offset)
	var extra_key: Dictionary = state.duplicate(true)
	extra_key.extra = true
	_check("unknown checkpoint fields are rejected", not CloudTransport.validate(extra_key))
	var wrong_version: Dictionary = state.duplicate(true)
	wrong_version.version = 1.0
	_check("floating-point checkpoint versions are rejected", not CloudTransport.validate(wrong_version))
	var negative_time: Dictionary = state.duplicate(true)
	negative_time.anchor_time_s = -0.1
	_check("negative checkpoint anchor time is rejected", not CloudTransport.validate(negative_time))
	var classic_legacy := CloudTransport.build({motion = "legacy"}, [], [5.0, 2.0, 0.0], 0.0, 1.0,
		Vector2(0.004, 0.0015), [Vector2.ZERO], 250.0)
	_check("classic legacy mode keeps the calibrated drift", CloudTransport.legacy_offset(classic_legacy, 1.0).is_equal_approx(Vector2(0.004, 0.0015)))
	var classic_still := CloudTransport.build({motion = "still"}, [], [5.0, 2.0, 0.0], 0.0, 1.0,
		Vector2(0.004, 0.0015), [Vector2(3.0, 4.0)], 250.0)
	_check("classic still mode holds its anchor", CloudTransport.legacy_offset(classic_still, 100.0) == Vector2(3.0, 4.0))
	var classic_follow := CloudTransport.build({motion = "follow_wind"}, [], [10.0, -4.0, 0.0], 0.0, 1.0,
		Vector2(0.004, 0.0015), [Vector2(3.0, 4.0)], 250.0)
	_check("classic follow-wind uses mean wind at physical cell scale",
		CloudTransport.legacy_offset(classic_follow, 1.0).is_equal_approx(Vector2(3.016, 4.04)))
	var classic_aloft := CloudTransport.build({motion = "aloft", wind_aloft_speed_mps = 10.0,
		wind_aloft_from_deg = 90.0}, [], [0.0, 0.0, 0.0], 0.0, 1.0,
		Vector2(0.004, 0.0015), [Vector2(3.0, 4.0)], 250.0)
	var classic_aloft_offset := CloudTransport.legacy_offset(classic_aloft, 1.0)
	_check("classic aloft mode uses the selected aloft wind",
		is_equal_approx(classic_aloft_offset.x, 3.04) and absf(classic_aloft_offset.y - 4.0) < 1e-6)
	print("cloud transport: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label)
