# CR-09e: wreck breakup by physical parts and hidden fracture detail, on the real Ugly Stik model.
#   same-kind parts that do not touch fly as separate bodies (main strap with its wheels, nose leg, tail skid);
#   the fuselage boom splits off at its section map; a C3 tail hit carries stab and fin on the boom;
#   splinters, torn film and spar stubs stay hidden in flight and appear only with the section that breaks.
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const WreckScript := preload("res://render/crash/wreck.gd")

var _checks := 0
var _failed := 0
var _wreck: Node3D
var _pose := Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0))


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.STIK_ID)
	root.add_child(airplane.root)
	var hidden := true
	for name in ["fracture_fuselage_core", "fracture_fuselage_boom", "fracture_wing_root_left", "fracture_wing_root_right"]:
		var node := airplane.root.find_child(name, true, false) as Node3D
		hidden = hidden and node != null and not node.visible and node.has_meta("crash_reveal")
	_check("fracture detail exists and is hidden in the flying model", hidden)
	var fuselage := airplane.root.find_child("fuselage", false, false) as MeshInstance3D
	_check("the flying fuselage stays one mesh with a crash section map", fuselage != null and fuselage.has_meta("crash_section_map"))
	var lining := airplane.root.find_child("fuselage_lining", false, false) as MeshInstance3D
	var balsa := lining != null and (lining.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(Color("d9c08e"))
	_check("raw balsa lines the fuselage and splits with it", balsa and lining.has_meta("crash_section_map")
		and lining.get_aabb().size.x < fuselage.get_aabb().size.x and lining.get_aabb().size.y < fuselage.get_aabb().size.y)
	var root_panel := airplane.root.find_child("wing_right_0", true, false) as MeshInstance3D
	var has_rib := false
	for surface in root_panel.mesh.get_surface_count():
		var mat := root_panel.mesh.surface_get_material(surface) as StandardMaterial3D
		has_rib = has_rib or (mat != null and mat.albedo_color.is_equal_approx(Color("d9c08e")))
	_check("the wing root cap is a bare balsa rib", has_rib)
	_wreck = WreckScript.new()
	root.add_child(_wreck)
	_check("Stik twin prepares", _wreck.prepare(airplane.root))
	var gear := _groups("gear")
	_check("gear flies as separate physical parts (main strap + wheels, nose leg, tail skid)", gear.size() == 3, str(gear.size()))
	_check("each wheel is its own part (pops off in a destroying crash)", _groups("wheel").size() == 3)
	_check("hinged surfaces are their own parts", _groups("aileron_left").size() == 1 and _groups("aileron_right").size() == 1
		and _groups("elevator").size() == 1 and _groups("rudder").size() == 1)
	var shares := 0.0
	for g: Dictionary in gear:
		shares += float(_wreck._key_share[g.key])
	_check("same-kind parts split the kind's weight (no mass doubling)", is_equal_approx(shares, 1.0), str(shares))
	_check("the fuselage boom is its own section", _groups("tail_boom").size() == 1)

	_start("C3", "fin_top", _pose * Vector3(0, 0.05, 0.8))
	var boom: Dictionary = _first("tail_boom")
	_check("C3 tail hit releases the boom", bool(boom.get("detached", false)))
	_check("C3 tail hit carries stab, fin, elevator and rudder on the boom", (boom.get("carried_keys", []) as Array).size() == 4)
	await _settle(0.6)
	_check("C3 tail hit shows both sides of the fuselage break", _visible("fracture_fuselage_core") and _visible("fracture_fuselage_boom"))
	_check("C3 tail hit keeps the wing roots unbroken", not _visible("fracture_wing_root_left") and not _visible("fracture_wing_root_right"))

	_start("C3", "left_wing_tip", _pose * Vector3(-0.7, 0, 0.1))
	await _settle(0.6)
	_check("C3 left wing hit shows only the left root splinters", _visible("fracture_wing_root_left") and not _visible("fracture_wing_root_right") and not _visible("fracture_fuselage_core"))

	_start("C3", "left_wing_tip", _pose * Vector3(-0.7, 0, 0.1))
	var wing: Dictionary = _first("wing_left")
	_check("C3 wing hit: the aileron rides on its wing half", bool(wing.get("detached", false)) and (wing.get("carried_keys", []) as Array).has("aileron_left")
		and not bool(_first("aileron_left").get("detached", false)))
	_start("C2", "wheel", _pose * Vector3(0, -0.22, -0.25))
	var released := _groups("gear").filter(func(g: Dictionary) -> bool: return bool(g.detached))
	_check("C2 gear hit releases only the struck (nose) leg", released.size() == 1 and Vector3(released[0].center).z < 0.0)
	_check("C2 gear hit: the nose wheel rides on its leg", released.size() == 1 and (released[0].get("carried_keys", []) as Array).size() == 1)
	_start("C2", "left_aileron", _pose * Vector3(-0.5, 0, 0.2))
	_check("C2 aileron hit tears off only that aileron", bool(_first("aileron_left").get("detached", false)) and not bool(_first("wing_left").get("detached", false))
		and not bool(_first("aileron_right").get("detached", false)))
	await _settle(0.4)
	_check("a torn-off aileron shows its broken hinges, the other aileron does not", (_visible("fracture_hinges_wing_left") or _visible("fracture_hinges_aileron_left"))
		and not _visible("fracture_hinges_wing_right") and not _visible("fracture_hinges_aileron_right") and not _visible("fracture_hinges_elevator"))

	_start("C4", "fuselage", _pose * Vector3(0, -0.05, -0.3))
	await _settle(1.0)
	_check("C4 shows every fracture", _visible("fracture_fuselage_core") and _visible("fracture_fuselage_boom") and _visible("fracture_wing_root_left") and _visible("fracture_wing_root_right"))
	_check("C4 breaks the tail surfaces off the boom", (_first("tail_boom").get("carried_keys", []) as Array).is_empty())
	var all_free := true
	for kind in ["aileron_left", "aileron_right", "elevator", "rudder", "wheel"]:
		for g: Dictionary in _groups(kind):
			all_free = all_free and bool(g.detached)
	_check("C4 tears every hinged surface and wheel off", all_free)
	_wreck.reset()
	_check("reset hides the fracture detail again", not _visible("fracture_fuselage_core") and not _visible("fracture_wing_root_left"))
	print("CR-09e fracture: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


# The first group of a kind, or {} so a missing section fails its checks instead of aborting the run.
func _first(kind: String) -> Dictionary:
	var found := _groups(kind)
	return found[0] if not found.is_empty() else {}


func _groups(kind: String) -> Array:
	return _wreck._groups.filter(func(g: Dictionary) -> bool: return String(g.kind) == kind)


func _start(class_label: String, component: String, contact: Vector3) -> void:
	_wreck.start(_pose, Vector3(0, -8, -10), Vector3.ZERO, {"class": class_label, "mass_kg": 2.885, "cg_model": Vector3.ZERO,
		"normal_speed_mps": 12.0, "component": component, "seed": 909, "contact_point_world": contact})


func _settle(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _visible(name: String) -> bool:
	var node := _wreck.find_child(name, true, false) as Node3D
	return node != null and node.visible
