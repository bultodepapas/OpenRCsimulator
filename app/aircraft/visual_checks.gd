# Checks atlas/winding, engine bores and head fins on built triangles, and engine clearance.
extends RefCounted
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")
var checks := 0
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures.append(label)

# US-V13: the engine is the bundled O.S. 61 GLB (~140k indexed triangles); probes use one BVH in model millimetres.
func _engine_bvh(engine: MeshInstance3D, root_node: Node3D, material := "") -> TriangleMesh:
	var root_from_mesh: Transform3D = root_node.global_transform.affine_inverse() * engine.global_transform
	var faces := PackedVector3Array()
	for surface in range(engine.mesh.get_surface_count()):
		var surface_material := engine.mesh.surface_get_material(surface)
		if not material.is_empty() and (surface_material == null or surface_material.resource_name != material):
			continue
		var arrays := engine.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices == null:
			for vertex in vertices: faces.append(root_from_mesh * vertex * 1000.0)
		else:
			for index: int in indices: faces.append(root_from_mesh * vertices[index] * 1000.0)
	var bvh := TriangleMesh.new()
	bvh.create_from_faces(faces)
	return bvh


## Distance from `from` to the first engine triangle on the segment to `to` (model metres), or -1 when it is free.
func _engine_hit(bvh: TriangleMesh, from: Vector3, to: Vector3) -> float:
	var hit: Dictionary = bvh.intersect_segment(from * 1000.0, to * 1000.0)
	return -1.0 if hit.is_empty() else (hit.position as Vector3).distance_to(from * 1000.0) / 1000.0


## Distances from a point inside a round bore to its wall along four directions across `axis`.
func _bore_walls(bvh: TriangleMesh, centre: Vector3, axis: Vector3) -> Array[float]:
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u).normalized()
	var walls: Array[float] = []
	for direction in [u, -u, v, -v]:
		walls.append(_engine_hit(bvh, centre, centre + direction * 0.02))
	return walls


func _check_engine_mesh(airplane: Dictionary) -> Dictionary:
	var root_node := airplane.root as Node3D
	var engine := root_node.find_child("engine_assembly", true, false) as MeshInstance3D
	check("engine assembly mesh present", engine != null and engine.mesh != null)
	if engine == null or engine.mesh == null:
		return {}
	check("engine is the bundled O.S. 61 SF model", root_node.get_meta("engine_revision", "") == Equipment.ENGINE_REVISION
		and engine.mesh.get_surface_count() >= 5 and engine.mesh.surface_get_material(0).resource_name == "M_RT_Body")
	var equipment: Dictionary = Geometry.DATA.equipment
	var hub_rear: float = float(equipment.prop_z) + Equipment.PROP_HUB_HALF_THICKNESS
	check("engine stays behind the propeller hub", engine.position.z + engine.get_aabb().position.z >= hub_rear - 0.0001)
	check("radial mount flange seats on F1", is_equal_approx(engine.position.z + Equipment.engine_anchor("engine_firewall_face").z, float(equipment.firewall_z)))
	var propeller := root_node.find_child("propeller", false, false) as Node3D
	var drive_rear := propeller.find_child("engine_drive_rear", false, false) as Node3D if propeller != null else null
	var drive_front := propeller.find_child("engine_drive_front", false, false) as Node3D if propeller != null else null
	var washer_face: float = Equipment.engine_anchor("engine_washer_face").z
	# The drive hub may sit inside the wooden hub (its 12 mm radius stays hidden), never ahead of the hub's rear face.
	check("propeller drive turns with the propeller, behind the wooden hub and its washer on the hub's front face", drive_rear != null and drive_front != null
		and is_equal_approx(propeller.position.z + drive_rear.position.z, engine.position.z)
		and drive_rear.position.z > -Equipment.PROP_HUB_HALF_THICKNESS and drive_rear.position.z <= Equipment.PROP_HUB_HALF_THICKNESS
		and is_equal_approx(drive_front.position.z + washer_face, -Equipment.PROP_HUB_HALF_THICKNESS))
	var bvh := _engine_bvh(engine, root_node)

	# Intake: an open 12 mm bore whose rays first meet the barrel and spray bar well below the mouth.
	var mouth: Vector3 = engine.get_meta("intake_mouth")
	var intake_axis: Vector3 = engine.get_meta("intake_axis")
	var intake_walls := _bore_walls(bvh, mouth - intake_axis * 0.004, intake_axis)
	check("carburetor bore is round, 5.5-7 mm radius", intake_walls.all(func(w: float) -> bool: return w >= 0.0055 and w <= 0.007))
	var side_axis: Vector3 = intake_axis.cross(Vector3.RIGHT).normalized()
	var up_axis: Vector3 = intake_axis.cross(side_axis).normalized()
	var intake_depths: Array[float] = []
	var obstructed := 0
	for offset in [Vector3.ZERO, side_axis * 0.002, -side_axis * 0.002, up_axis * 0.002, -up_axis * 0.002]:
		var depth := _engine_hit(bvh, mouth + offset, mouth + offset - intake_axis * 0.05)
		check("carburetor bore ray is open for 8 mm", depth < 0.0 or depth >= 0.008)
		if depth >= 0.0 and depth < 0.045: obstructed += 1
		intake_depths.append(depth)
	check("barrel and spray bar sit inside the carburetor bore", obstructed >= 3)

	# Gold head: downward rays on a 16 mm ring about the head axis land on fins and on slots at least 2 mm deeper.
	var head := _engine_bvh(engine, root_node, "M_RT_Head")
	var head_faces := head.get_faces()
	var low := Vector3.INF
	var high := -Vector3.INF
	for point in head_faces:
		low = low.min(point / 1000.0)
		high = high.max(point / 1000.0)
	check("gold head mesh present", not head_faces.is_empty())
	var head_tops: Array[float] = []
	for i in range(36):
		var angle := TAU * float(i) / 36.0
		var probe := Vector3((low.x + high.x) * 0.5 + cos(angle) * 0.016, high.y + 0.01, (low.z + high.z) * 0.5 + sin(angle) * 0.016)
		var depth := _engine_hit(head, probe, probe + Vector3.DOWN * 0.05)
		head_tops.append(probe.y - depth if depth >= 0.0 else NAN)
	check("gold head ring rays all hit the head", head_tops.all(func(y: float) -> bool: return not is_nan(y)))
	var head_relief: float = head_tops.max() - head_tops.min()
	check("gold head fins stand at least 2 mm above their slots", head_relief >= 0.002)

	# Outlet: the exhausts anchor is centred in the silencer tube, which stays open past its rim.
	var exhaust: Dictionary = root_node.get_meta("exhausts", [{}])[0]
	var outlet: Vector3 = exhaust.get("position", Vector3.ZERO)
	var outlet_axis: Vector3 = exhaust.get("direction", Vector3.BACK)
	var outlet_walls := _bore_walls(bvh, outlet - outlet_axis * 0.004, outlet_axis)
	check("exhaust anchor sits on the silencer tube axis", outlet_walls.all(func(w: float) -> bool: return absf(w - float(exhaust.get("radius_m", 0.0))) <= 0.0003))
	var outlet_depth := _engine_hit(bvh, outlet + outlet_axis * 0.001, outlet - outlet_axis * 0.05)
	check("silencer outlet tube is open for 10 mm", outlet_depth < 0.0 or outlet_depth >= 0.011)
	print("Engine mesh probes: intake walls m=%s depths m=%s; head relief m=%.4f; outlet walls m=%s depth m=%.4f" % [str(intake_walls), str(intake_depths), head_relief, str(outlet_walls), outlet_depth])
	return {"intake_walls_m": intake_walls, "intake_depths_m": intake_depths, "head_relief_m": head_relief, "outlet_walls_m": outlet_walls, "outlet_depth_m": outlet_depth}


# US-V09b: the normal map needs tangents along dP/du. Without generate_tangents() Godot fills an arbitrary orthonormal
# frame, so orthogonality alone proves nothing; compare each triangle's UV-derived tangent with the stored one.
func _tangents_follow_uv(arrays: Array) -> bool:
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
	if tangents == null or tangents.size() != positions.size() * 4 or arrays[Mesh.ARRAY_INDEX] != null: return false
	var measured := 0
	var aligned := 0
	for i in range(0, positions.size(), 3):
		var e1 := positions[i + 1] - positions[i]
		var e2 := positions[i + 2] - positions[i]
		var d1 := uv[i + 1] - uv[i]
		var d2 := uv[i + 2] - uv[i]
		var det := d1.x * d2.y - d2.x * d1.y
		if absf(det) < 1e-12: continue # caps and edges that map to one atlas texel or line
		var t := (e1 * d2.y - e2 * d1.y) / det
		t -= normals[i] * normals[i].dot(t)
		if t.length() < 1e-9: continue
		measured += 1
		var stored := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		if stored.dot(t.normalized()) > 0.9: aligned += 1
	return measured > 0 and aligned >= int(ceil(0.98 * measured))


# US-V09e: the sides and belly unwrap into their own atlas rows; glow-oil residue sits only behind the exhaust (+X).
func _check_exhaust_residue(airplane: Dictionary, atlas: Image) -> void:
	var f: Dictionary = Finish.Appearance.DATA.fuselage_unwrap
	var fuselage := airplane.root.find_child("fuselage", false, false) as MeshInstance3D
	var uv: PackedVector2Array = fuselage.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = fuselage.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var unwrapped := 0
	var inside := true
	var sided := true
	for i in uv.size():
		var y := uv[i].y * 1024.0
		if y < float(f.y_px[0]) - 0.5 or y > float(f.y_px[1]) + 0.5: continue # dorsal top or plain end caps
		unwrapped += 1
		var x := uv[i].x * 1024.0
		inside = inside and x >= float(f.x_px[0]) - 0.01 and x <= float(f.x_px[1]) + 0.01
		# +X skin maps below the belly centre row (positive arc length), −X above it.
		var mid := 0.5 * (float(f.y_px[0]) + float(f.y_px[1]))
		if absf(vertices[i].x) > 0.004: sided = sided and signf(vertices[i].x) == signf(y - mid)
	check("fuselage sides and belly use the unwrap region (%d vertices)" % unwrapped, unwrapped > 100 and inside)
	check("fuselage unwrap keeps +X skin on the exhaust half", sided)
	var r: Dictionary = Finish.Appearance.DATA.exhaust_residue
	if not r.enabled: return
	var sample := func(z: float, arc_s: float) -> Color:
		var p := Finish.fuselage_uv(z, arc_s) * float(atlas.get_width())
		return atlas.get_pixel(int(p.x), int(p.y))
	# US-V13: the O.S. silencer exhausts just above the +X side, so the stain starts high on that side.
	var stained: Color = sample.call(-0.20, 0.12)
	var mirror: Color = sample.call(-0.20, -0.12)
	var tail: Color = sample.call(0.70, 0.02)
	check("exhaust residue darkens the +X side behind the outlet (%s)" % stained, stained.r < 0.6 * Finish.RED.r)
	check("no residue on the −X side or the tail (%s %s)" % [mirror, tail], mirror.is_equal_approx(Finish.RED) and tail.is_equal_approx(Finish.RED))


# US-V09f–h: stab underside spray (+X only), hatch seams on the plan's hatch bay, belly wear behind the nose wheel.
func _check_hatch_and_wear(atlas: Image) -> void:
	var scale := float(atlas.get_width())
	var mean_red := func(uv: Vector2) -> float:
		var total := 0.0
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				total += atlas.get_pixel(clampi(int(uv.x * scale) + dx, 0, atlas.get_width() - 1), clampi(int(uv.y * scale) + dy, 0, atlas.get_height() - 1)).r
		return total / 81.0
	var stations: Array = Geometry.DATA.fuselage_stations
	var h: Dictionary = Finish.Appearance.DATA.hatch
	check("hatch spans the first fuselage bay", is_equal_approx(float(h.z_m[0]), float(stations[0][0])) and is_equal_approx(float(h.z_m[1]), float(stations[1][0])))
	var rear_seam: Color = atlas.get_pixel(int(Finish.uv(Vector3(0, 0, float(h.z_m[1]) - float(h.seam_width_m)), "hatch").x * scale), int(Finish.uv(Vector3(0, 0, float(h.z_m[1]) - float(h.seam_width_m)), "hatch").y * scale))
	var lid: Color = atlas.get_pixel(int(Finish.uv(Vector3(0, 0, -0.22), "hatch").x * scale), int(Finish.uv(Vector3(0, 0, -0.22), "hatch").y * scale))
	check("hatch rear seam is drawn and the lid stays clean (%s %s)" % [rear_seam, lid], rear_seam.r < 0.75 * Finish.RED.r and lid.is_equal_approx(Finish.RED))
	var right_stab: float = mean_red.call(Finish.uv(Vector3(0.03, 0, -0.13), "stab_under"))
	var left_stab: float = mean_red.call(Finish.uv(Vector3(-0.03, 0, -0.13), "stab_under"))
	check("stabiliser spray only on the right underside (%.3f vs %.3f)" % [right_stab, left_stab], right_stab < 0.93 * Finish.RED.r and is_equal_approx(left_stab, Finish.RED.r))
	if Finish.Appearance.DATA.belly_wear.enabled:
		var front: float = mean_red.call(Finish.fuselage_uv(-0.21, 0.0))
		var clean: float = mean_red.call(Finish.fuselage_uv(0.35, -0.04))
		check("belly wear behind the nose wheel (%.3f) and a clean mid-belly (%.3f)" % [front, clean], front < 0.97 * Finish.RED.r and is_equal_approx(clean, Finish.RED.r))


# Meshes must actually sample the painted regions: stab/elevator undersides and the hatch lid.
func _check_painted_regions(airplane: Dictionary) -> void:
	var stab_rows: Array = Finish.Appearance.DATA.stab_unwrap.y_px
	for mesh_name in ["stab", "elevator"]:
		var node := airplane.root.find_child(mesh_name, true, false) as MeshInstance3D
		var arrays := node.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var under := 0
		var mapped := true
		for i in normals.size():
			if normals[i].y < -0.99:
				under += 1
				mapped = mapped and uv[i].y * 1024.0 >= float(stab_rows[0]) - 0.01 and uv[i].y * 1024.0 <= float(stab_rows[1]) + 0.01
			elif normals[i].y > 0.99:
				mapped = mapped and uv[i].is_equal_approx(Finish.uv(Vector3.ZERO, "red"))
		check("%s underside samples the painted stab rows, top stays plain (%d)" % [mesh_name, under], under > 0 and mapped)
	var fuselage := airplane.root.find_child("fuselage", false, false) as MeshInstance3D
	var arrays := fuselage.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var lid := 0
	var lid_mapped := true
	var h: Dictionary = Finish.Appearance.DATA.hatch
	for i in range(0, vertices.size(), 3):
		# Lid triangles: all three normals vertical, ahead of the rear seam (corner-arc triangles share edge vertices).
		var flat_top := true
		for k in 3: flat_top = flat_top and normals[i + k].y > 0.99 and vertices[i + k].z <= float(h.z_m[1]) + 1e-6
		if not flat_top: continue
		lid += 1
		for k in 3: lid_mapped = lid_mapped and uv[i + k].x * 1024.0 >= float(h.x_px[0]) - 0.01 and uv[i + k].x * 1024.0 <= float(h.x_px[1]) + 0.01 and uv[i + k].y * 1024.0 >= float(h.y_px[0]) - 0.01 and uv[i + k].y * 1024.0 <= float(h.y_px[1]) + 0.01
	check("hatch lid samples the hatch region (%d triangles)" % lid, lid > 0 and lid_mapped)


# US-V09d: varnished wooden blades with grain; the texture only darkens (0.79..1) and stays close to 1 on average so
# the propeller blur disc, which copies albedo_color, keeps the blade colour within a few percent.
func _check_propeller_wood(airplane: Dictionary) -> void:
	var blades := airplane.propeller.find_child("propeller_blades", true, false) as MeshInstance3D
	check("propeller blades exist", blades != null)
	if blades == null: return
	var mat := blades.mesh.surface_get_material(0) as StandardMaterial3D
	check("propeller uses the varnished grain material", mat != null and mat.albedo_texture == Finish.grain() and mat.roughness < 0.4)
	var image := Finish.grain().get_image()
	var lo := 1.0
	var hi := 0.0
	var total := 0.0
	var count := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var r := image.get_pixel(x, y).r
			lo = minf(lo, r)
			hi = maxf(hi, r)
			total += r
			count += 1
	var mean := total / count
	check("propeller grain only darkens within 0.79..1 (min %.3f max %.3f)" % [lo, hi], lo >= 0.78 and hi <= 1.0 and hi - lo > 0.05)
	check("propeller grain mean stays near the measured blade albedo (%.3f)" % mean, mean > 0.86)
	var uv: PackedVector2Array = blades.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = blades.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var valid := uv.size() == vertices.size() and uv.size() > 0
	for i in uv.size():
		valid = valid and uv[i].x >= 0.0 and uv[i].x <= 1.0 and uv[i].y >= 0.0 and uv[i].y <= 1.0
		# One blank: U follows the blade's spanwise position (left blade U < 0.5, right blade U > 0.5).
		valid = valid and (uv[i].x - 0.5) * vertices[i].y >= -1e-6
	check("propeller blade UVs run tip to tip through the hub", valid)


# US-V09b: film sag between plan-traced ribs/spars. Samples the generated normal map in atlas pixels.
func _check_film_structure(skin: StandardMaterial3D) -> void:
	check("covering uses the film-structure normal map", skin.normal_enabled and skin.normal_texture == Finish.normal_map() and is_equal_approx(skin.normal_scale, 1.0 / Finish.NORMAL_MAP_GAIN))
	check("hinge gaps have no film structure", not Finish.hinge_gap().normal_enabled)
	var image := Finish.normal_map().get_image()
	var size := Finish.NORMAL_MAP_SIZE
	check("film normal map size and mip chain", image.get_size() == Vector2i(size, size) and image.has_mipmaps())
	var f: Dictionary = Finish.Appearance.DATA.film_structure
	var span := float(Geometry.DATA.wing.span)
	var column := func(x: float) -> int: return int(floor((x / span + 0.5) * size))
	var row := func(fraction: float) -> int: return int(floor((16.0 + 224.0 * fraction) * size / 1024.0))
	var tilt := func(x: float, fraction: float) -> Vector3:
		var c := image.get_pixel(column.call(x), row.call(fraction))
		return Vector3(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0, c.b * 2.0 - 1.0) / Finish.NORMAL_MAP_GAIN
	var flat := 1.5 / 255.0 / Finish.NORMAL_MAP_GAIN
	var fin_flat := true
	for pixel in [Vector2i(256, 760), Vector2i(776, 776), Vector2i(512, 1000)]:
		var c := image.get_pixel(pixel.x * size / 1024, pixel.y * size / 1024)
		fin_flat = fin_flat and c.r8 == 128 and c.g8 == 128 and c.b8 == 255
	check("film is flat on the fin and dorsal atlas regions", fin_flat)
	var lo := float(f.rib_centres_m[2])
	var hi := float(f.rib_centres_m[3])
	var on_rib := true
	for x in [lo, -lo, hi, -hi]:
		on_rib = on_rib and absf(tilt.call(x, 0.5).x) < flat
	check("film is supported on the traced ribs", on_rib)
	check("film is flat on the trailing-edge sheet and the sheet tip", absf(tilt.call(0.18, 0.85).x) < flat and absf(tilt.call(0.73, 0.5).x) < flat)
	var inboard: Vector3 = tilt.call(lo + 0.25 * (hi - lo), 0.5)
	var outboard: Vector3 = tilt.call(lo + 0.75 * (hi - lo), 0.5)
	var mirrored: Vector3 = tilt.call(-(lo + 0.25 * (hi - lo)), 0.5)
	# Concave sag: the inboard wall tilts outboard (+x on the right wing), mirrored on the left wing.
	check("film sags inward between ribs (concave, mirrored) %s %s %s" % [inboard, outboard, mirrored], inboard.x > 2.0 * flat and outboard.x < -2.0 * flat and mirrored.x < -2.0 * flat and absf(inboard.x + mirrored.x) <= 2.0 * flat)
	var forward: Vector3 = tilt.call(0.5 * (lo + hi), 0.35)
	var aft: Vector3 = tilt.call(0.5 * (lo + hi), 0.70)
	# Green points toward image-up (leading edge): the forward wall of the dent tilts aft (green < 0).
	check("film sags inward between spars (concave chordwise) %s %s" % [forward, aft], forward.y < -flat and aft.y > flat)
	var slope := 0.0
	for x in range(size):
		var c := image.get_pixel(x, row.call(0.5))
		slope = maxf(slope, Vector2(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0).length() / Finish.NORMAL_MAP_GAIN)
	check("film sag stays subtle (max tilt %.2f < 3 degrees)" % rad_to_deg(asin(minf(slope, 1.0))), slope > 0.0 and slope < sin(deg_to_rad(3.0)))


func run(airplane: Dictionary) -> Dictionary:
	var skin := Finish.covering()
	check("atlas loaded", skin.albedo_texture != null)
	if skin.albedo_texture == null: return {"checks": checks, "failures": failures, "ok": false}
	var image := skin.albedo_texture.get_image()
	check("atlas has mip chain", image.has_mipmaps())
	check("atlas is square and intended resolution", image.get_size() == Vector2i.ONE * int(Finish.Appearance.DATA.atlas_size_px))
	check("atlas does not multiply colored tint", skin.albedo_color.is_equal_approx(Color.WHITE))
	var total_uvs := 0
	var winding_triangles := 0
	for node in airplane.root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var mesh_arrays := instance.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = mesh_arrays[Mesh.ARRAY_NORMAL]
			var indices: Variant = mesh_arrays[Mesh.ARRAY_INDEX]
			var count: int = positions.size() if indices == null or indices.is_empty() else indices.size()
			var valid_winding := true
			for i in range(0, count, 3):
				var a: int = i if indices == null or indices.is_empty() else indices[i]
				var b: int = i+1 if indices == null or indices.is_empty() else indices[i+1]
				var c: int = i+2 if indices == null or indices.is_empty() else indices[i+2]
				var face := (positions[c] - positions[a]).cross(positions[b] - positions[a])
				if face.length_squared() < 1e-20: continue
				var expected := normals[a] + normals[b] + normals[c]
				valid_winding = valid_winding and face.dot(expected) > 0.000001 * face.length() * expected.length()
				winding_triangles += 1
			check("clockwise faces agree with normals " + String(instance.name) + ":" + str(surface), valid_winding)
			if instance.mesh.surface_get_material(surface) != skin: continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			check("film normal map tangents follow the atlas U direction " + String(instance.name), _tangents_follow_uv(arrays))
			check("UV vertex cardinality " + String(instance.name), vertices.size() == uv.size())
			if vertices.size() != uv.size(): continue
			var valid := true
			var aligned := true
			var frame: Node3D = null
			if String(instance.name).begins_with("wing_") or String(instance.name).begins_with("fixed_te_"):
				frame = instance.get_parent() as Node3D
			elif String(instance.name).begins_with("aileron_"):
				frame = instance.get_parent().get_parent() as Node3D
			for i in uv.size():
				valid = valid and is_finite(uv[i].x) and is_finite(uv[i].y) and uv[i].x >= 0 and uv[i].x <= 1 and uv[i].y >= 0 and uv[i].y <= 1
				if frame != null:
					var point := frame.to_local(instance.to_global(vertices[i]))
					aligned = aligned and uv[i].distance_to(Finish.uv(point, "wing")) < 0.00001
			check("finite atlas UV " + String(instance.name), valid)
			if frame != null: check("neutral fixed/moving atlas registration " + String(instance.name), aligned)
			total_uvs += uv.size()
	check("skin vertices audited", total_uvs > 100)
	var a := MeshInstance3D.new()
	var b := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.material = skin
	a.mesh = mesh
	b.mesh = mesh
	a.material_override = skin.duplicate() as StandardMaterial3D
	a.material_override.roughness = 0.99
	check("inspection override stays local", b.get_active_material(0) == skin and a.get_active_material(0) != skin and skin.roughness != 0.99)
	check("same color different finishes stay distinct", Finish.material(Color.GRAY, "rubber") != Finish.material(Color.GRAY, "steel"))
	_check_film_structure(skin)
	_check_propeller_wood(airplane)
	_check_exhaust_residue(airplane, image)
	_check_hatch_and_wear(image)
	_check_painted_regions(airplane)
	var engine_probe_report := _check_engine_mesh(airplane)
	a.free()
	b.free()
	return {"checks": checks, "failures": failures, "ok": failures.is_empty(), "textured_vertices": total_uvs, "winding_triangles": winding_triangles, "engine_probes": engine_probe_report}
