# P51-08: the P-51D 1/4 airborne envelope through the real session loop: flight modes at three speeds, maximum level
# speed with the propeller unloading, full-throttle climb, idle glide with the windmilling 4-blade, power-off and
# power-on 1-g stalls with wing drop and recovery, roll rate across speeds, a 60° level turn. Bands and sources:
# research/p51/p51-08/README.md. Run: godot --headless --path . --script res://tests/test_p51_envelope.gd
extends "res://tests/p51_envelope_base.gd"


func _run() -> void:
	_modes()
	_performance()
	_stalls()
	_handling()
