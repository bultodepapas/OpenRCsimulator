# FW-35b: night kit v2. Top-side white wing strips and a cyan fuselage belly strip (orientation: white = top, cyan =
# belly), the landing light in the left wing's leading edge clear of the propeller disc, ALL/NAV/OFF modes, and lights
# that ride on their own parts in a crash wreck without inflating its collision boxes.
extends SceneTree

const Builder := preload("res://render/airplane.gd")
const Kit := preload("res://render/world/aircraft_lights.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WreckScript := preload("res://render/crash/wreck.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Standalone native runs must register globals before model materials compile.
	ShaderClock.register()
	_belly_station_boundaries()
	# Fleet: every catalog aircraft gets top strips on both wings.
	for id in Catalog.ids():
		var plane: Dictionary = Builder.build(id)
		if plane.is_empty():
			continue
		root.add_child(plane.root)
		var kit := Kit.attach(plane.root)
		_check("%s has white top strips on both wings" % id, kit.get_node_or_null("strip_top_left") != null and kit.get_node_or_null("strip_top_right") != null)
		var top: MeshInstance3D = kit.get_node_or_null("strip_top_left")
		var bottom: MeshInstance3D = kit.get_node_or_null("strip_left")
		if top != null and bottom != null:
			_check("%s top strip runs above the underside strip" % id, top.get_aabb().get_center().y > bottom.get_aabb().get_center().y)
		plane.root.queue_free()

	var stik: Dictionary = Builder.build(Builder.STIK_ID)
	root.add_child(stik.root)
	var e: Dictionary = Geometry.DATA.equipment
	var half := Kit.span_half(Kit.vertices(stik.root)) # before the kit exists: its light quads are 1 m in the mesh
	var kit := Kit.attach(stik.root)
	var belly: MeshInstance3D = kit.get_node_or_null("strip_belly")
	_check("Stik has a cyan belly strip", belly != null)
	if belly != null:
		var box := belly.get_aabb()
		var stations: Array = Geometry.DATA.fuselage_stations
		var lowest := INF
		for st: Array in stations: lowest = minf(lowest, float(st[3]))
		_check("belly strip lies on the fuselage underside, not on a gear leg (y %.3f..%.3f)" % [box.position.y, box.end.y],
			box.position.y > lowest - 0.02 and box.end.y < -0.03 and absf(box.get_center().x) < 0.01)
		_check("belly strip runs along the fuselage (%.2f m)" % box.size.z, box.size.z > 0.5)
	var landing := kit.get_node("landing_light") as SpotLight3D
	_check("landing light sits in the left wing's leading edge %s" % landing.position, landing.position.x < -0.2 * half and landing.position.z < float(Geometry.DATA.wing.leading_z) + 0.03)
	# The beam (cone of half-angle spot_angle along −Z) must clear the propeller disc at the propeller plane.
	var prop_z := float(e.prop_z)
	var reach := (landing.position.z - prop_z) * tan(deg_to_rad(landing.spot_angle))
	var lateral := absf(landing.position.x) - reach
	_check("landing beam clears the propeller disc (%.3f m beyond its %.3f m radius)" % [lateral - 0.5 * float(e.prop_diameter), 0.5 * float(e.prop_diameter)],
		lateral > 0.5 * float(e.prop_diameter))
	Kit.set_mode(kit, "nav")
	var nav_ok := kit.visible and (kit.get_node("nav_left") as Node3D).visible and (kit.get_node("strobe_right") as Node3D).visible
	nav_ok = nav_ok and not (kit.get_node("strip_left") as Node3D).visible and not landing.visible and not (kit.get_node("strip_belly") as Node3D).visible
	_check("NAV mode keeps navigation lights and strobes only", nav_ok)
	Kit.set_mode(kit, "off")
	_check("OFF mode hides the kit", not kit.visible)
	Kit.set_mode(kit, "all")
	_check("ALL mode shows every light", kit.visible and (kit.get_node("strip_top_right") as Node3D).visible and landing.visible)
	var follows := true
	for name in ["strip_left", "strip_top_right", "nav_left", "landing_light"]:
		var item: Node = kit.get_node(name)
		follows = follows and item.has_meta("crash_follow") and item.has_meta("crash_no_bounds")
	_check("kit lights name their host part and stay out of crash boxes", follows)
	var wing_host := String(kit.get_node("strip_left").get_meta("crash_follow"))
	_check("the left underside strip is mounted on the left wing (%s)" % wing_host, wing_host.contains("wing_frame_left"))

	# Crash: lights ride with their part; the kit never inflates the airframe's box.
	var bare: Dictionary = Builder.build(Builder.STIK_ID)
	root.add_child(bare.root)
	var plain: Node3D = WreckScript.new()
	root.add_child(plain)
	plain.prepare(bare.root)
	var lit: Node3D = WreckScript.new()
	root.add_child(lit)
	lit.prepare(stik.root)
	_check("night kit does not inflate the wreck's airframe box", (lit._core_bounds as AABB).is_equal_approx(plain._core_bounds), "%s vs %s" % [lit._core_bounds, plain._core_bounds])
	var twin_strip: Node = lit._twin.find_child("strip_left", true, false)
	var on_wing := false
	var cursor: Node = twin_strip
	while cursor != null and cursor != lit._twin:
		on_wing = on_wing or String(cursor.name) == "wing_frame_left"
		cursor = cursor.get_parent()
	_check("in the wreck the left strip rides on the left wing", on_wing)
	print("FW-35b night kit: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _belly_station_boundaries() -> void:
	# All 14 stations coincide at z=0. Either triangle endpoint must be inclusive.
	for endpoint in [-1.0, 1.0]:
		var triangle := PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, endpoint)])
		var line := Kit.belly_line(triangle, AABB())
		var correct := line.size() == Kit.BELLY_STATIONS
		for point in line:
			correct = correct and point == Vector3(0, -Kit.STRIP_GAP_M, 0)
		_check("coincident belly stations include triangle endpoint %s" % endpoint, correct)
	# A continuous flat floor gives a known height even with descending stations.
	var floor_tris := PackedVector3Array([Vector3(-2, -.3, -2), Vector3(2, -.3, -2), Vector3(2, -.3, 2),
		Vector3(-2, -.3, -2), Vector3(2, -.3, 2), Vector3(-2, -.3, 2)])
	var descending := Kit.belly_line(floor_tris, AABB(Vector3(0, 0, 1), Vector3(1, 1, -2)))
	var floor_ok := descending.size() == Kit.BELLY_STATIONS
	for index in descending.size():
		floor_ok = floor_ok and absf(descending[index].y + .3 + Kit.STRIP_GAP_M) < 1e-6
		if index > 0:
			floor_ok = floor_ok and descending[index].z < descending[index - 1].z
	_check("descending belly stations retain the continuous floor", floor_ok)
	_check("belly stations outside the mesh stay empty", Kit.belly_line(floor_tris,
		AABB(Vector3(0, 0, 10), Vector3.ONE)).is_empty())
