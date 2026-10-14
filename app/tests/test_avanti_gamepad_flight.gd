extends "res://tests/avanti_gamepad_base.gd"

var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	# Pilot feedback: a pure pull must not snap-roll in the ordinary normal-gamepad range.
	for pair in [[29.0, 0.5], [29.0, 0.75], [45.0, 1.0], [60.0, 1.0], [45.0, -0.75]]:
		var r := run_case(pair[0], pair[1])
		check("complete finite session %.0f / %.2f" % pair, r.completed)
		check("pure pitch stays channel-isolated", r.unwanted_command_max == 0.0)
		check("pull and release do not produce uncommanded axial roll", r.roll_rate_max < 5.0)
		check("moderate pitch retains most attached wing flow", r.stall_max < 0.5)
	# Isolate the aerodynamic correction: manufacturer's 15-degree gamepad normal travel, no R2 gain.
	physics_only = true
	var polar := run_case(45.0, 0.5)
	check("polar alone avoids the former mid-stick departure", polar.completed and polar.roll_rate_max < 5.0)
	# Positive defect control demonstrates that these bounds reject the reproduced old behavior.
	baseline = true
	var old := run_case(29.0, 0.5)
	check("old closure and gain reproduce the reported departure", old.completed and old.roll_rate_max > 100.0 and old.stall_max > 0.9)
	print("AV-17-R2 gamepad flight: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)
