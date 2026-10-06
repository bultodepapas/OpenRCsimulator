# P51-08/P51-12: the P-51D 1/4 on the field's grass runway through the real session loop: parked at its three-point
# attitude, idle, the takeoff run without rudder (left swing) and with a rudder pilot (roll, lift-off speed, heading),
# and an approach, flare, wheel landing and rollout. Bands and sources: research/p51/p51-08/README.md.
# Run: godot --headless --path . --script res://tests/test_p51_ground.gd
extends "res://tests/p51_envelope_base.gd"


func _run() -> void:
	_ground()
	_takeoff()
	_landing()
