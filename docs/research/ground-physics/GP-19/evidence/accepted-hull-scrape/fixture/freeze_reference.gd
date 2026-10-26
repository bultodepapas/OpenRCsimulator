## One-time old-source capture; never computes candidate expected outputs.
extends SceneTree
const Old = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/source/app/physics/hull_contact.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
func _initialize() -> void:
	var hull := PackedFloat64Array([0.0,0.0,0.0,0.3,-0.2,0.01,-0.1,0.4,-0.02])
	var inertia := PackedFloat64Array([1.0,1.2,1.4,0.01,0.02,-0.01])
	var prepared := Old.prepare(hull,2.0,inertia)
	var values: Array = []
	for i in 180:
		var q := M.q_from_euler(0.17*i,0.01*(i%7),-0.03*(i%5))
		var s := RB.make_state(M.v3(12.0,-3.0,-0.01+0.0004*(i%60)),M.v3(-4.0+0.07*i,0.2*(i%6),-0.2+0.01*(i%30)),q,M.v3(0.1,-0.2,0.05))
		values.append(Old.loads(s,prepared))
	var state := RB.make_state(M.v3(0,0,.002),M.v3(4,0,0),M.q_identity(),M.v3(0,0,0))
	var geometry := Old.prepare_geometry(hull)
	var props := {ok=true,mass_kg=2.0,cg_body_m=M.v3(.12,-.04,.02),inertia=inertia,inverse=RB.inertia_inverse(inertia)}
	var dynamic: Array = [Old.loads_at_properties(state,geometry,props)]
	props.mass_kg=1.0;props.inertia=inertia.duplicate()
	for axis in 6:props.inertia[axis]*=.5
	props.inverse=RB.inertia_inverse(props.inertia)
	dynamic.append(Old.loads_at_properties(state,geometry,props))
	var fixture := {format="openrc-hull-friction-reference-v1",source_sha256=FileAccess.get_sha256("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/source/app/physics/hull_contact.gd"),
		engine=Engine.get_version_info().string,prepared=var_to_bytes(prepared),loads=values,dynamic=dynamic}
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/promotion/app/tests/fixtures/hull_friction_reference.bin",FileAccess.WRITE)
	file.store_buffer(var_to_bytes(fixture));file.close()
	print("Frozen hull friction reference: complete")
	quit()
