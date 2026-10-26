extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
func _initialize() -> void:
	Engine.physics_ticks_per_second=240
	var session:=Flight.new();session.input_enabled=false;session.setup()
	var adapter:=Adapter.new();adapter.configure(session,"jensen-das-ugly-stik-60",func(_v):pass)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(adapter.sample()))
	print("Pre-change absent producer SHA ",hash.finish().hex_encode())
	session.free();quit(0)
