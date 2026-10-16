extends "res://tools/flight_log_cli.gd"

func _initialize() -> void:
	Engine.physics_ticks_per_second = 480
	super._initialize()
