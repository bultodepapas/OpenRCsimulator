# P51-11b fit study: the main-gear hinge (axis and swing) that stows the wheel flat inside the wing root, and the tail
# pivot/swing that stows the tail wheel inside the tail cone. A stowed tyre is sampled at 48 rim/face points; each must lie
# between the wing skins (in the dihedral frame, with the root extension) or inside the fuselage section. For the main
# leg, the rotation taking (leg, stub axle) to (inboard-aft-slightly-up, down) is solved for each candidate stowed
# direction; any such rotation is one hinge axis and angle. The chosen values are authored in source.json gear.retraction.
# Research only. Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/gear_fit_probe.gd
extends SceneTree
const P51 := preload("res://aircraft/p51d_model.gd")
const D := preload("res://aircraft/p51d_geometry.gd")

var frames: Dictionary


func _inside(p: Vector3) -> String:
	# Fuselage: inside the superellipse section at station z.
	var hw: float = P51.profile(p.z, 1)
	if absf(p.x) <= hw:
		var lo: float = P51.skin_y(p.z, p.x, false)
		var hi: float = P51.skin_y(p.z, p.x, true)
		if lo > hi:
			var t := lo
			lo = hi
			hi = t
		if p.y >= minf(lo, -absf(lo)) and p.y <= hi:
			return "fuse"
	# Wing: in the dihedral frame of its side, between the lower and upper skin at that station/chord fraction.
	var side := "right" if p.x > 0.0 else "left"
	var local: Vector3 = (frames[side] as Transform3D).affine_inverse() * p
	var station: float = absf(local.x)
	var le: Vector3 = P51._wing_skin_point(signf(p.x) * station, 0.0, false, true)
	var te: Vector3 = P51._wing_skin_point(signf(p.x) * station, 1.0, false, true)
	var xc: float = (local.z - le.z) / (te.z - le.z)
	if xc < 0.0 or xc > 1.0:
		return ""
	var up: Vector3 = P51._wing_skin_point(signf(p.x) * station, xc, true, true)
	var dn: Vector3 = P51._wing_skin_point(signf(p.x) * station, xc, false, true)
	if local.y >= dn.y and local.y <= up.y:
		return "wing"
	return ""


func _wheel_points(center: Vector3, axle: Vector3, radius: float, half_width: float) -> Array:
	var u := axle.cross(Vector3.UP if absf(axle.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var v := axle.cross(u).normalized()
	var pts := []
	for k in 24:
		var a := TAU * k / 24.0
		for s in [-1.0, 1.0]:
			pts.append(center + (u * cos(a) + v * sin(a)) * radius + axle * half_width * s)
	return pts


func _initialize() -> void:
	var a: Dictionary = P51.build()
	frames = a.frames
	var g: Dictionary = D.DATA.gear
	var r: float = g.main_wheel_diameter / 2.0
	var hwid: float = g.main_wheel_width / 2.0
	# Right main: trunnion (top of the leg) and deployed axle from the current build.
	var axle := Vector3(g.track / 2.0, g.main_axle[1], g.main_axle[0])
	var x_strut: float = g.track / 2.0 - 0.03
	var top := Vector3(0.422871, -0.143869, 0.064108) # the builder's deployed leg top (skin iteration), now source data
	var d: Vector3 = (Vector3(x_strut, g.main_axle[1], g.main_axle[0]) - top)
	var L := d.length()
	var stub: float = g.track / 2.0 - x_strut
	var best := []
	for fz: float in [0.26, 0.28, 0.30, 0.32, 0.34]:
		for fy: float in [0.08, 0.10, 0.12, 0.14]:
			for sdir: float in [-1.0]:
				var f := Vector3(-1.0, fy, fz).normalized()
				var sv := (Vector3(0, sdir, 0) - f * f.dot(Vector3(0, sdir, 0))).normalized()
				# Rotation taking (leg d, stub +x) to (f, sv): R = E2 * E1^T.
				var a1 := (Vector3.RIGHT - d.normalized() * d.normalized().dot(Vector3.RIGHT)).normalized()
				var e1 := Basis(d.normalized(), a1, d.normalized().cross(a1))
				var e2 := Basis(f, sv, f.cross(sv))
				var R: Basis = e2 * e1.transposed()
				var c: Vector3 = top + R * (Vector3(g.track / 2.0, g.main_axle[1], g.main_axle[0]) - top)
				var ax: Vector3 = R * Vector3.RIGHT
				var outside := 0
				for pt: Vector3 in _wheel_points(c, ax, r, hwid):
					if _inside(pt) == "": outside += 1
				var q := R.get_rotation_quaternion()
				best.append([outside, fz, fy, sdir, c, q.get_axis(), rad_to_deg(q.get_angle())])
	best.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for row in best.slice(0, 10):
		print("outside %d  f(-1,%.2f,%.2f) stub %+.0f  centre %s  axis %s  angle %.1f" % [row[0], row[2], row[1], row[3], row[4], row[5], row[6]])
	# Tail: pivot candidates on the tail cone, wheel swings forward (rotation about +X, nose is -Z).
	var steer := Vector3(0, -0.119832, g.tail_axle[0])
	var tc := Vector3(0, g.tail_axle[1], g.tail_axle[0])
	var tr: float = g.tail_wheel_diameter / 2.0
	for dz: float in [0.0, 0.03, 0.06]:
		for dy: float in [0.0, 0.03]:
			var piv := steer + Vector3(0, dy, dz)
			for th_deg: float in [70.0, 85.0, 100.0]:
				var rot := Basis(Vector3.RIGHT, deg_to_rad(th_deg))
				var c: Vector3 = piv + rot * (tc - piv)
				var outside := 0
				for p: Vector3 in _wheel_points(c, Vector3.RIGHT, tr, 0.01):
					if _inside(p) == "": outside += 1
				print("tail pivot +%.2f up +%.2f aft, %.0f deg: centre %s, outside %d/48" % [dy, dz, th_deg, c, outside])
	a.root.free()
	quit(0)
