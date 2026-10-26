## Software force/instantaneous-power parity; no physical/acoustic calibration.
extends SceneTree
const H = preload("res://physics/hull_contact.gd")
const REFERENCE := "res://tests/fixtures/hull_friction_reference.bin"
const REFERENCE_SHA256 := "66f4a8e91c6b5161db938ac3a3deadbed9993829703fcffdd00755937e082811"
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
var checks := 0
var failed := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label)
func _initialize() -> void:
	var raw := FileAccess.get_file_as_bytes(REFERENCE)
	check("frozen pre-change force bytes retain source-pinned fixture identity",FileAccess.get_sha256(REFERENCE)==REFERENCE_SHA256)
	if raw.is_empty():
		quit(1)
		return
	var reference: Dictionary=bytes_to_var(raw)
	var hull := PackedFloat64Array([0.0,0.0,0.0,0.3,-0.2,0.01,-0.1,0.4,-0.02])
	var inertia := PackedFloat64Array([1.0,1.2,1.4,0.01,0.02,-0.01])
	var prepared := H.prepare(hull,2.0,inertia)
	var old: PackedByteArray=reference.prepared
	check("preparation bytes unchanged", old==var_to_bytes(prepared))
	for i in 180:
		var q := M.q_from_euler(0.17*i,0.01*(i%7),-0.03*(i%5))
		var s := RB.make_state(M.v3(12.0,-3.0,-0.01+0.0004*(i%60)),M.v3(-4.0+0.07*i,0.2*(i%6),-0.2+0.01*(i%30)),q,M.v3(0.1,-0.2,0.05))
		var rows: Array = [{old = true}]
		var loads := H.loads(s,prepared,[],rows)
		check("default bytes unchanged case%d"%i, var_to_bytes(reference.loads[i])==var_to_bytes(H.loads(s,prepared)) and var_to_bytes(loads)==var_to_bytes(H.loads(s,prepared)))
		var body_power := 0.0
		if not loads.is_empty():
			for axis in 3: body_power += loads[axis]*s[RB.VEL+axis]+loads[axis+3]*s[RB.RATE+axis]
		var expected := 0.0
		var passive := true
		for row: Dictionary in rows:
			var r := hull.slice(3*row.index,3*row.index+3)
			var v := M.q_rotate(q,M.add(s.slice(RB.VEL,RB.VEL+3),M.cross(s.slice(RB.RATE,RB.RATE+3),r)))
			var dot := M.dot(row.tangent_force_ned_n,row.relative_tangent_velocity_ned_mps)
			expected += -row.friction_power_w-row.normal_force_n*v[2]
			passive = passive and row.normal_force_n>0.0 and row.friction_power_w>=0.0 and absf(dot+row.friction_power_w)<1e-10
		check("independent rigid-body virtual work/passivity case%d"%i, passive and absf(body_power-expected)<1e-9*maxf(1.0,absf(expected)))
	var one := H.prepare(PackedFloat64Array([0.0,0.0,0.0]),1.0,PackedFloat64Array([1.,1.,1.,0.,0.,0.]))
	var state := RB.make_state(M.v3(0,0,.002),M.v3(10,0,-1),M.q_identity(),M.v3(0,0,0))
	var rows: Array = []
	check("opening geometric contact has no loaded friction rows",H.loads(state,one,[],rows).is_empty() and rows.is_empty() and H.contacts(state,state,one).size()==1)
	state[RB.VEL+2]=0.0
	var load := H.loads(state,one,[],rows)
	check("independent 28.8W force oracle",rows.size()==1 and absf(rows[0].friction_power_w-28.8)<1e-12 and absf(load[0]+2.88)<1e-12)
	state[RB.VEL]=0.0
	H.loads(state,one,[],rows)
	check("stationary support has exactly zero friction power",rows.size()==1 and rows[0].friction_power_w==0.0)
	# Dynamic geometry uses the accepted mass/inertia owner, not frozen coefficients.
	var geometry := H.prepare_geometry(hull)
	var props := {ok=true,mass_kg=2.0,cg_body_m=M.v3(.12,-.04,.02),inertia=inertia,inverse=RB.inertia_inverse(inertia)}
	state[RB.POS+2]=.002
	state[RB.VEL]=4.0
	var result := H.loads_at_properties(state,geometry,props,rows)
	check("dynamic-property default and observation loads exact",result.ok and var_to_bytes(result)==var_to_bytes(reference.dynamic[0]))
	var full_force: PackedFloat64Array = result.loads.duplicate()
	props.mass_kg=1.0
	props.inertia=inertia.duplicate()
	for axis in 6: props.inertia[axis]*=.5
	props.inverse=RB.inertia_inverse(props.inertia)
	var lighter := H.loads_at_properties(state,geometry,props,rows)
	check("live mass sampling changes the same-law contact response",lighter.ok and rows.size()>0 and var_to_bytes(lighter)==var_to_bytes(reference.dynamic[1]) and lighter.loads[2]!=full_force[2])
	print("Hull scrape metrics: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
