# test_mt8.gd - verificacion automatica del .glb importado en Godot 4.7.2
# godot --headless --path . --import ; godot --headless --path . -s test_mt8.gd
extends SceneTree

const BJ_DY := 0.022
const SHOCK_BODY_LEN := 0.0
var fails := 0
var report := {}


func check(name: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + str(detail) if str(detail) != "" else ""))
	if not ok:
		fails += 1
	report[name] = {"ok": ok, "detail": str(detail)}


func _initialize() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://mt8_spec.json"))
	var ps: PackedScene = load("res://MT8_Bisonte.glb")
	var inst := ps.instantiate()
	var rig: Node3D = load("res://mt8_rig.gd").new()
	rig.name = "Rig"
	rig.root_path = NodePath(String(inst.name) + "/MT8_Root")
	root.add_child(rig)
	rig.add_child(inst)
	await process_frame
	var R: Node3D = inst.find_child("MT8_Root", true, false)
	check("root MT8_Root existe", R != null)

	# --- 1. nombres y jerarquia
	var needed := ["Chassis", "Body", "Bumper_F", "Bumper_R", "Propulsion", "Collision",
		"COL_Chassis", "COL_Roof", "COL_Side_L", "COL_Side_R", "COL_Bumper_F", "COL_Bumper_R"]
	for c in ["FL", "FR", "RL", "RR"]:
		for p in ["ArmLower", "ArmUpper", "Suspension", "Spin", "WheelMesh", "DriveshaftIn", "DriveshaftOut",
				"ShockA_Body", "ShockA_Spring", "ShockA_Shaft", "ShockB_Body", "ShockB_Spring", "ShockB_Shaft"]:
			needed.append(c + "_" + p)
		needed.append(c + ("_Steer" if c[0] == "F" else "_Carrier"))
		needed.append(c + ("_Knuckle" if c[0] == "F" else "_Carrier"))
	var missing := []
	for n in needed:
		if R.find_child(n, true, false) == null:
			missing.append(n)
	check("todas las piezas presentes (%d)" % needed.size(), missing.is_empty(), missing)
	check("WheelMesh es hijo de Spin", R.find_child("FL_WheelMesh", true, false).get_parent().name == "FL_Spin")
	check("Spin es hijo de Steer (delantera)", R.find_child("FL_Spin", true, false).get_parent().name == "FL_Steer")
	check("Steer es hijo de Suspension", R.find_child("FL_Steer", true, false).get_parent().name == "FL_Suspension")
	check("Shaft es hijo de ArmLower", R.find_child("FL_ShockA_Shaft", true, false).get_parent().name == "FL_ArmLower")

	# --- 2. sin escalas negativas
	var neg := []
	for n in R.find_children("*", "Node3D", true, false):
		var b: Basis = (n as Node3D).transform.basis
		if b.determinant() <= 0.0:
			neg.append(n.name)
	check("ninguna escala negativa ni determinante <= 0", neg.is_empty(), neg)

	# --- 3. ejes: ruedas en sus esquinas
	var pos := {}
	for c in ["FL", "FR", "RL", "RR"]:
		pos[c] = (R.find_child(c + "_Spin", true, false) as Node3D).global_position
	check("FL delante-izquierda (x<0, z<0)", pos["FL"].x < 0 and pos["FL"].z < 0, pos["FL"])
	check("FR delante-derecha (x>0, z<0)", pos["FR"].x > 0 and pos["FR"].z < 0, pos["FR"])
	check("RL detras-izquierda (x<0, z>0)", pos["RL"].x < 0 and pos["RL"].z > 0, pos["RL"])
	check("RR detras-derecha (x>0, z>0)", pos["RR"].x > 0 and pos["RR"].z > 0, pos["RR"])
	check("batalla = 0.420", is_equal_approx(pos["RL"].z - pos["FL"].z, 0.42), pos["RL"].z - pos["FL"].z)
	check("via (centro a centro) = 0.430", is_equal_approx(pos["FR"].x - pos["FL"].x, 0.43), pos["FR"].x - pos["FL"].x)
	var roof := (R.find_child("COL_Roof", true, false) as Node3D).global_position
	check("el techo queda en +Y", roof.y > 0.15, roof)

	# --- 4. AABB visual (sin proxies)
	var aabb := AABB()
	var first := true
	var tris := 0
	var mats := {}
	for mi in R.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with("COL_"):
			continue
		var m: MeshInstance3D = mi
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() / 3) if idx != null else (arr[Mesh.ARRAY_VERTEX].size() / 3)
			var mat = m.mesh.surface_get_material(si)
			if mat:
				mats[mat.resource_name] = mat.get_class()
	print("AABB pos=", aabb.position, " size=", aabb.size)
	report["aabb"] = {"position": [aabb.position.x, aabb.position.y, aabb.position.z], "size": [aabb.size.x, aabb.size.y, aabb.size.z]}
	report["triangles_godot"] = tris
	report["materials"] = mats
	check("largo total ~0.66 m", absf(aabb.size.z - 0.66) < 0.01, aabb.size.z)
	check("ancho total ~0.52 m", absf(aabb.size.x - 0.52) < 0.01, aabb.size.x)
	check("suelo a y = -0.125 (fondo de los neumaticos)", absf(aabb.position.y + 0.125) < 0.002, aabb.position.y)
	check("materiales StandardMaterial3D", mats.values().all(func(v): return v == "StandardMaterial3D"), mats.size())

	# --- 5. extras de glTF como metadatos
	var susp: Node3D = R.find_child("FL_Suspension", true, false)
	var has_extras := susp.has_meta("extras")
	check("extras glTF importados como metadata", has_extras, susp.get_meta("extras") if has_extras else susp.get_meta_list())

	# --- 6. pose cero del rig == pose exportada
	var rest := {}
	for n in R.find_children("*", "Node3D", true, false):
		rest[n.name] = (n as Node3D).transform
	rig._cache()
	rig._apply()
	var maxd := 0.0
	var worst := ""
	for n in R.find_children("*", "Node3D", true, false):
		var t0: Transform3D = rest[n.name]
		var t1: Transform3D = (n as Node3D).transform
		var d := t0.origin.distance_to(t1.origin) + (t0.basis.x - t1.basis.x).length() + (t0.basis.y - t1.basis.y).length() + (t0.basis.z - t1.basis.z).length()
		if d > maxd:
			maxd = d
			worst = n.name
	check("rig con entradas 0 reproduce la pose del .glb", maxd < 1e-4, "%s %.7f" % [worst, maxd])

	# --- 7. cierre de juntas en extremos
	var worst_joint := 0.0
	var worst_name := ""
	var spring_k := Vector2(10, 0)
	for t in [-0.07, -0.035, 0.0, 0.025, 0.05]:
		for sd in [-30.0, 0.0, 30.0]:
			for c in ["FL", "FR", "RL", "RR"]:
				rig.set_travel(c, t)
			rig.set_steer(deg_to_rad(sd))
			for c in ["FL", "FR", "RL", "RR"]:
				var s := -1.0 if c[1] == "L" else 1.0
				var L: float = spec["arm_length"]
				var hub: Node3D = R.find_child(c + ("_Steer" if c[0] == "F" else "_Suspension"), true, false)
				var al: Node3D = R.find_child(c + "_ArmLower", true, false)
				var au: Node3D = R.find_child(c + "_ArmUpper", true, false)
				var e1 := (al.global_transform * Vector3(s * L, 0, 0)).distance_to(hub.global_transform * Vector3(0, -BJ_DY, 0))
				var e2 := (au.global_transform * Vector3(s * L, 0, 0)).distance_to(hub.global_transform * Vector3(0, BJ_DY, 0))
				for w in ["A", "B"]:
					var sb: Node3D = R.find_child(c + "_Shock" + w + "_Body", true, false)
					var sh: Node3D = R.find_child(c + "_Shock" + w + "_Shaft", true, false)
					var sp: Node3D = R.find_child(c + "_Shock" + w + "_Spring", true, false)
					var axis_b := -(sb.global_transform.basis.y.normalized())
					var to_lo := (sh.global_position - sb.global_position).normalized()
					var e3 := axis_b.distance_to(to_lo)
					var axis_s := sh.global_transform.basis.y.normalized()
					var e4 := axis_s.distance_to(-to_lo)
					var tip := sh.global_transform * Vector3(0, spec["shock_shaft_len"], 0)
					var tip_d := sb.global_position.distance_to(tip)
					var inside: bool = tip_d > 0.016 and tip_d < float(spec["shock_body_len"]) - 0.0149
					if not inside:
						e3 += 1.0
					spring_k.x = minf(spring_k.x, sp.scale.y)
					spring_k.y = maxf(spring_k.y, sp.scale.y)
					for e in [e3, e4]:
						if e > worst_joint:
							worst_joint = e
							worst_name = "%s shock %s t=%s steer=%s" % [c, w, t, sd]
				var di: Node3D = R.find_child(c + "_DriveshaftIn", true, false)
				var dout: Node3D = R.find_child(c + "_DriveshaftOut", true, false)
				var cv := hub.global_transform * Vector3(-s * float(spec["cv_offset"]), 0, 0)
				var span := dout.global_position - di.global_position
				var ax_in := (di.global_transform.basis * Vector3(s, 0, 0)).normalized()
				var ax_out := (dout.global_transform.basis * Vector3(-s, 0, 0)).normalized()
				var overlap := float(spec["driveshaft_in_len"]) + float(spec["driveshaft_out_len"]) - span.length()
				var e5 := dout.global_position.distance_to(cv) + ax_in.distance_to(span.normalized()) + ax_out.distance_to(-span.normalized())
				if overlap < 0.008:
					e5 += 1.0
				for pair in [[e1, "brazo inf"], [e2, "bieleta sup"], [e5, "palier en copa"]]:
					if pair[0] > worst_joint:
						worst_joint = pair[0]
						worst_name = "%s %s t=%s steer=%s" % [c, pair[1], t, sd]
	check("juntas cerradas en 15 poses extremas (error max < 1e-4 m)", worst_joint < 1e-4, "%s %.7f" % [worst_name, worst_joint])
	report["spring_scale_range"] = [spring_k.x, spring_k.y]
	print("escala de muelle: ", spring_k)

	# --- 8. signos de direccion y giro
	for c in ["FL", "FR", "RL", "RR"]:
		rig.set_travel(c, 0.0)
	rig.set_steer(deg_to_rad(20))
	var fw: Vector3 = -(R.find_child("FL_Spin", true, false) as Node3D).global_transform.basis.z
	check("direccion + gira la rueda hacia la izquierda (-X)", fw.x < 0, fw)
	rig.set_steer(0.0)
	rig.set_spin("FL", -0.2)
	var spn: Node3D = R.find_child("FL_Spin", true, false)
	var top := spn.global_transform * Vector3(0, 0.1, 0) - spn.global_position
	check("giro negativo sobre +X: la parte alta va hacia delante (-Z)", top.z < 0, top)
	rig.set_spin("FL", 0.0)

	# --- 9. VehicleBody3D: que eje considera Godot como avance
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(50, 1, 50)
	gshape.shape = gbox
	ground.add_child(gshape)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)
	var vb := VehicleBody3D.new()
	vb.mass = 4.5
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.2, 0.12, 0.5)
	cs.shape = bx
	vb.add_child(cs)
	for c in ["FL", "FR", "RL", "RR"]:
		var wv := VehicleWheel3D.new()
		var p: Array = spec["corners"][c]["wheel_center_rest"]
		wv.position = Vector3(p[0], p[1] + 0.05, p[2])
		wv.wheel_radius = 0.1
		wv.wheel_rest_length = 0.08
		wv.suspension_stiffness = 40.0
		wv.use_as_traction = true
		vb.add_child(wv)
	vb.position = Vector3(0, 0.3, 0)
	world.add_child(vb)
	for i in 60:
		await physics_frame
	var z0 := vb.global_position.z
	vb.engine_force = 20.0
	for i in 90:
		await physics_frame
	var dz := vb.global_position.z - z0
	print("VehicleBody3D con engine_force>0 se desplaza dz = ", dz)
	report["vehiclebody3d_engine_positive_dz"] = dz
	check("dato: VehicleBody3D avanza hacia " + ("+Z" if dz > 0 else "-Z") + " con engine_force > 0", true, dz)

	var f := FileAccess.open("res://godot_check_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("FALLOS: ", fails)
	quit(fails)
