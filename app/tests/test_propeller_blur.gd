# VQ-05 regression checks: measured propeller profiles, the speed cross-fade, node lifecycle and an untouched model.
# Run: godot --headless --path app --script res://tests/test_propeller_blur.gd
extends SceneTree

const Blur := preload("res://render/propeller_blur.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const ExtraGeometry := preload("res://aircraft/extra_300s_geometry.gd")
const P51Geometry := preload("res://aircraft/p51d_geometry.gd")

## Known blade counts: the Stik's generated blades (ugly_stik_equipment.gd builds two), the Extra's and P-51's
## geometry data, and the Timber's r1 rotor (geometry.json: "rotating: 3 blades, spinner, backplate, outrunner bell").
const BLADES := {AirplaneBuilder.STIK_ID: 2, AirplaneBuilder.EXTRA_ID: int(ExtraGeometry.DATA.propeller.blades),
	AirplaneBuilder.P51_ID: int(P51Geometry.DATA.propeller.blades), AirplaneBuilder.TIMBER_ID: 3}

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run()


## Tip radius from the propeller's vertices, independently of the module (every mesh under the node).
func _tip_radius(propeller: Node3D) -> float:
	var tip := 0.0
	for item in propeller.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		var t := Blur.relative(propeller, mi)
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := t * v
				tip = maxf(tip, Vector2(p.x, p.y).length())
	return tip


func _snapshot(root: Node3D) -> Array:
	var out := []
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		var materials := []
		for s in mi.mesh.get_surface_count():
			materials.append(mi.get_surface_override_material(s))
		out.append([mi.get_path(), mi.visible, mi.mesh, mi.transform, materials])
	return out


func _run() -> void:
	await process_frame
	_blur_fraction()
	for id in BLADES:
		await _aircraft(id)
	_no_propeller()
	print("propeller blur: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _blur_fraction() -> void:
	_check("stopped rotor is sharp", Blur.blur_fraction(0.0, 2) == 0.0)
	_check("below the start frequency is sharp", Blur.blur_fraction(Blur.BLUR_START_HZ * 60.0 / 2.0 - 1.0, 2) == 0.0)
	_check("above the full frequency is a disc", Blur.blur_fraction(Blur.BLUR_FULL_HZ * 60.0 / 2.0 + 1.0, 2) == 1.0)
	var previous := -1.0
	var monotone := true
	for i in 50:
		var f := Blur.blur_fraction(i * 40.0, 2)
		monotone = monotone and f >= previous and f >= 0.0 and f <= 1.0
		previous = f
	_check("fraction is monotone in speed within [0, 1]", monotone)
	var two := Blur.blur_fraction(600.0, 2)
	var four := Blur.blur_fraction(600.0, 4)
	_check("more blades blur at lower speed", four > two and four == Blur.blur_fraction(1200.0, 2), "%f %f" % [two, four])
	_check("reverse rotation blurs too", Blur.blur_fraction(-3000.0, 2) == Blur.blur_fraction(3000.0, 2))


func _aircraft(id: String) -> void:
	var airplane: Dictionary = AirplaneBuilder.build(id)
	_check(id + " builds", not airplane.is_empty())
	if airplane.is_empty():
		return
	root.add_child(airplane.root)
	var before := _snapshot(airplane.root)
	var measured: Dictionary = Blur.profile(airplane.propeller, airplane.root)
	_check(id + " has a profile", not measured.is_empty())
	if measured.is_empty():
		airplane.root.free()
		return
	var tip := _tip_radius(airplane.propeller)
	_check(id + " tip radius matches the propeller vertices", absf(measured.radius - tip) < 1e-6, "%f vs %f" % [measured.radius, tip])
	_check(id + " blade count", measured.blades == BLADES[id], "%d vs %d" % [measured.blades, BLADES[id]])
	var coverage: PackedFloat64Array = measured.coverage
	var in_range := true
	for c in coverage:
		in_range = in_range and c >= 0.0 and c <= 1.0
	_check(id + " coverage within [0, 1]", in_range)
	var root_ring := clampi(ceili(measured.inner_radius / measured.ring_width), 0, Blur.RINGS - 1)
	_check(id + " blades cover more near the root than at the tip", coverage[root_ring] > coverage[Blur.RINGS - 1] and coverage[Blur.RINGS - 1] > 0.0,
		"%f at ring %d vs %f at the tip" % [coverage[root_ring], root_ring, coverage[Blur.RINGS - 1]])
	# Time-averaged occlusion: no ring can exceed the blades' own share of a revolution at that radius by much, and
	# a two-blade propeller cannot cover more than two chords of arc. Half a turn per blade is a generous bound.
	var bounded := true
	for ring in range(root_ring, Blur.RINGS):
		bounded = bounded and coverage[ring] <= 0.5 * measured.blades
	_check(id + " coverage bounded by the blade count", bounded)
	_check(id + " inner radius is at least the opaque hub", measured.inner_radius >= measured.hub_radius and measured.inner_radius < measured.radius)
	_check(id + " blade plane sits near the spin pivot", absf(measured.plane_z) < 0.1 * measured.radius, str(measured.plane_z))
	var first_colored: Material = null
	for ring in range(root_ring, Blur.RINGS):
		if measured.colors[ring] != null:
			first_colored = measured.colors[ring]
			break
	_check(id + " ring colours come from the blade materials", first_colored is BaseMaterial3D)
	if id == AirplaneBuilder.P51_ID:
		var tip_material: BaseMaterial3D = measured.colors[Blur.RINGS - 1]
		var root_material: BaseMaterial3D = measured.colors[root_ring]
		_check("P-51 tip rings carry the yellow tip material", tip_material != root_material and tip_material.albedo_color.g > root_material.albedo_color.g)
	if id == AirplaneBuilder.TIMBER_ID:
		_check("Timber spinner, backplate and bell form an opaque hub", measured.hub_radius > 0.01 and measured.hub_radius < 0.5 * measured.radius, str(measured.hub_radius))
	# Attach and drive it.
	var holder := Node3D.new()
	root.add_child(holder)
	var node: Node3D = Blur.attach(airplane, null, holder)
	_check(id + " attaches", node != null and node.get_parent() == holder and node.name == "PropellerBlur")
	await process_frame
	_check(id + " attach leaves the model untouched", _snapshot(airplane.root) == before)
	_check(id + " no node was added inside the model", airplane.root.find_child("PropellerBlur", true, false) == null and airplane.root.find_child("disc", true, false) == null)
	node.update(0.0)
	_check(id + " stopped: model untouched and nothing of the blur shown", _snapshot(airplane.root) == before and not node._disc.visible and node.blur == 0.0)
	var mid_rpm: float = 0.5 * (Blur.BLUR_START_HZ + Blur.BLUR_FULL_HZ) * 60.0 / float(measured.blades)
	node.update(mid_rpm)
	_check(id + " mid speed: fraction between 0 and 1", node.blur > 0.0 and node.blur < 1.0, str(node.blur))
	var originals_hidden := true
	for original: MeshInstance3D in node._originals:
		originals_hidden = originals_hidden and not original.visible
	_check(id + " mid speed: the model's blades give way to the faded copies", originals_hidden and node._blade_copies.size() > 0 and node._blade_copies[0].visible)
	_check(id + " mid speed: blade copy alpha is the complement of the disc", absf(node._fade_materials[0].albedo_color.a - (1.0 - node.blur)) < 1e-6
		and absf(node._disc_materials[0].albedo_color.a - Blur.GAIN * node.blur) < 1e-6)
	_check(id + " mid speed: disc shown", node._disc.visible)
	_check(id + " hub copies present only with an opaque hub", (node._hub_copies.size() > 0) == (measured.hub_radius > 0.0))
	var fast_rpm: float = Blur.BLUR_FULL_HZ * 60.0 / float(measured.blades) * 2.0
	node.update(fast_rpm)
	_check(id + " fast: disc only", node.blur == 1.0 and node._disc.visible and not node._blade_copies[0].visible)
	# Removing the observer restores originals; reattachment must reapply even
	# when RPM, model visibility and broken state are unchanged.
	for speed in [0.0, mid_rpm, fast_rpm]:
		node.update(speed)
		var expected_blur: float = node.blur
		var expected_disc: bool = node._disc.visible
		var expected_blade: bool = node._blade_copies[0].visible
		holder.remove_child(node)
		_check(id + " detach restores originals at " + str(speed), _snapshot(airplane.root) == before)
		holder.add_child(node)
		node.update(speed)
		var correct_originals := true
		for original: MeshInstance3D in node._originals:
			correct_originals = correct_originals and original.visible == (expected_blur <= 0.0)
		_check(id + " reattach reapplies presentation at " + str(speed), correct_originals
			and node.blur == expected_blur and node._disc.visible == expected_disc
			and node._blade_copies[0].visible == expected_blade)
	airplane.propeller.set_meta(Blur.PropBreak.BROKEN_META, true)
	node.update(fast_rpm)
	holder.remove_child(node)
	holder.add_child(node)
	node.update(fast_rpm)
	var broken_hidden: bool = not node._disc.visible
	for original: MeshInstance3D in node._originals:
		broken_hidden = broken_hidden and not original.visible
	_check(id + " broken rotor stays hidden through reattachment", broken_hidden)
	airplane.propeller.remove_meta(Blur.PropBreak.BROKEN_META)
	node.update(fast_rpm)
	_check(id + " repaired rotor resumes the disc", node._disc.visible and node.blur == 1.0)
	# The blur follows the propeller through the model's pose and the spin phase.
	airplane.root.transform = Transform3D(Basis.from_euler(Vector3(0.3, 1.2, -0.4)), Vector3(12.0, 30.0, -40.0))
	airplane.propeller.rotation.z = 2.1
	node.update(fast_rpm)
	_check(id + " follows the propeller", node.global_transform.is_equal_approx(airplane.propeller.global_transform))
	# Hidden model (crash twin shown, --hide_airplane): nothing of the blur shows and the model is restored.
	airplane.root.visible = false
	node.update(fast_rpm)
	_check(id + " hidden model hides the blur", not node._disc.visible and node.blur == 0.0)
	airplane.root.visible = true
	node.update(0.0)
	_check(id + " back to stopped restores the model exactly", _snapshot(airplane.root) == before and not node._disc.visible)
	# Draw list: one disc, copies only for blade surfaces (and a hub when the rotor mesh holds one).
	var surfaces: int = measured.surfaces.size()
	_check(id + " one blade copy per blade surface", node._blade_copies.size() == surfaces, "%d vs %d" % [node._blade_copies.size(), surfaces])
	_check(id + " disc casts no shadow and is one mesh", node._disc.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and node._disc.mesh.get_surface_count() >= 1)
	node.update(fast_rpm)
	holder.free()
	await process_frame
	_check(id + " freeing the blur restores the model's blades", _snapshot(airplane.root) == before)
	airplane.root.free()


func _no_propeller() -> void:
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.AVANTI_ID)
	root.add_child(airplane.root)
	var holder := Node3D.new()
	root.add_child(holder)
	_check("the Avanti gets no blur", Blur.attach(airplane, null, holder) == null and holder.get_child_count() == 0)
	_check("an empty build gets no blur", Blur.attach({}, null, holder) == null)
	holder.free()
	airplane.root.free()
