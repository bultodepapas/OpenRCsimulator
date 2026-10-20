# Read-only timing wrapper, outside production code.
extends "res://main.gd"
var audit_main_usec := 0
func _process(delta: float) -> void:
	var begin := Time.get_ticks_usec()
	super._process(delta)
	audit_main_usec = Time.get_ticks_usec() - begin
