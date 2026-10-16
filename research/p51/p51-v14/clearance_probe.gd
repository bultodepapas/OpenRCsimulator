# P51-V14: where is the rudder closest to its fixed neighbours? For each pose (rudder neutral, the flown throw and 45 deg
# both ways) prints the visual rudder's side area against the NACA rudder area, then the smallest vertex-to-triangle distance between two meshes and the model-frame point where it
# occurs, both ways round. Diagnostic for verify_p51_clearance.gd, which reports only the gap.
# Run: godot --headless --path app --script "$PWD/research/p51/p51-v14/clearance_probe.gd" [-- --a=rudder --b=fuselage]
# Other surfaces (P51-V15): -- --hinge=aileron_left --a=aileron_left --b=wing_left_tip (ailerons/elevator turn about x).
extends SceneTree

const P51 := preload("res://aircraft/p51d_model.gd")
const Clearance := preload("res://aircraft/extra_clearance.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Verify := preload("res://aircraft/verify_p51.gd")


func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return fallback


func _initialize() -> void:
	call_deferred("_run")


func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Ericson, Real-Time Collision Detection 5.1.5.
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


func _nearest(points: Array, tris: Array) -> Dictionary:
	var best := {d = INF}
	var box := AABB()
	for i in tris.size():
		var t: PackedVector3Array = tris[i]
		for v in t: box = AABB(v, Vector3.ZERO) if i == 0 and box.size == Vector3.ZERO and box.position == Vector3.ZERO else box.expand(v)
	box = box.grow(0.01)
	for p: Vector3 in points:
		if not box.has_point(p): continue
		for t: PackedVector3Array in tris:
			var q := _closest_on_triangle(p, t[0], t[1], t[2])
			var d := p.distance_to(q)
			if d < best.d: best = {d = d, at = p, on = q}
	return best


func _run() -> void:
	var a_name := _arg("a", "rudder")
	var b_name := _arg("b", "fuselage")
	var airplane := AirplaneBuilder.build(AirplaneBuilder.P51_ID)
	get_root().add_child(airplane.root)
	var table := {}
	Clearance._collect(airplane.root, table)
	var rudder: Node3D = airplane.hinges.rudder
	var hinge_name := _arg("hinge", "rudder")
	var moving: Node3D = airplane.hinges.get(hinge_name, rudder)
	var naca: float = 10.41 * pow(12.0 * 0.0254, 2) * pow(float(P51.D.scale.factor), 2)
	var area: float = Verify._side_area_aft(rudder)
	print("visual rudder side area aft of the hinge %.5f m2 = %.2f ft2 full size (NACA production rudder 10.41 ft2: %.5f m2, %+.1f %%)" % [
		area, area / pow(float(P51.D.scale.factor), 2) / pow(12.0 * 0.0254, 2), naca, 100.0 * (area / naca - 1.0)])
	for deg in [0.0, 18.0, -18.0, 30.0, -30.0, 45.0, -45.0]:
		moving.rotation = Vector3(0, deg_to_rad(deg), 0) if hinge_name == "rudder" else Vector3(deg_to_rad(deg), 0, 0)
		var a: Array = Clearance._triangles(table[a_name], airplane.root)
		var b: Array = Clearance._triangles(table[b_name], airplane.root)
		var a_points := []
		for t: PackedVector3Array in a: for v in t: a_points.append(v)
		var b_points := []
		for t: PackedVector3Array in b: for v in t: b_points.append(v)
		var ab := _nearest(a_points, b)
		var ba := _nearest(b_points, a)
		print("%s %+5.1f deg: %s vertex -> %s %.2f mm at %s | %s vertex -> %s %.2f mm at %s" % [hinge_name, deg, a_name, b_name, ab.d * 1000.0, ab.get("at"),
			b_name, a_name, ba.d * 1000.0, ba.get("at")])
	quit(0)
