extends SceneTree
const Calibration := preload("res://input/rc_calibration.gd")
const Rc := preload("res://input/rc_input.gd")
func _initialize() -> void:
	var base: Dictionary = Rc.DEFAULT_PROFILE.duplicate(true)
	print("valid_default=%s" % Calibration.valid(base))
	var duplicate_axes := base.duplicate(true)
	duplicate_axes.pitch.axis = duplicate_axes.roll.axis
	print("accepts_duplicate_axes=%s" % Calibration.valid(duplicate_axes))
	var outside_center := base.duplicate(true)
	outside_center.roll.center = 3.0
	print("accepts_center_outside_endpoints=%s" % Calibration.valid(outside_center))
	var wide_endpoints := base.duplicate(true)
	wide_endpoints.roll.min = -5.0
	wide_endpoints.roll.max = 5.0
	print("accepts_out_of_hid_range_endpoints=%s" % Calibration.valid(wide_endpoints))
	var wrong_kind := base.duplicate(true)
	wrong_kind.kind = "unknown"
	print("accepts_unknown_profile_kind=%s" % Calibration.valid(wrong_kind))
	var nan_endpoint := base.duplicate(true)
	nan_endpoint.roll.min = NAN
	print("accepts_nan_endpoint=%s" % Calibration.valid(nan_endpoint))
	quit()
