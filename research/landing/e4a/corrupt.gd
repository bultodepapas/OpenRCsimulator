# Disposable tape corruptions for verifying E4a's consumer; never changes an app script.
extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(2)
		return
	var source: FileAccess = FileAccess.open(args[0], FileAccess.READ)
	if source == null:
		quit(2)
		return
	var value: Dictionary = source.get_var(false)
	source.close()
	match args[2]:
		"missing-input":
			value.inputs.pop_back()
		"nonfinite-input":
			value.inputs[0][0] = NAN
		"missing-final":
			value.samples.pop_back()
		"clock":
			value.samples[1].tick += 1
		"position":
			value.samples[1].state[0] += 2e-6 # Twice the H9 1e-6 m position budget.
		"auxiliary":
			value.samples[1].aux[1] += 2e-9 # Twice the H9 1e-9 servo budget.
		"initial":
			value.initial.simulation.state[0] += 2e-6
		"anchor-mode":
			value.samples[1].aux[6] += 1e-7 # Inside a numeric anchor tolerance, but not a valid discrete flag.
		"policy":
			value.policy = null
		"stamp":
			value.stamp.erase("os")
		_:
			quit(2)
			return
	var target: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if target == null or not target.store_var(value, false):
		quit(2)
		return
	target.close()
	quit(0)
