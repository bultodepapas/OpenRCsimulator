# VQ-05: propeller blur from the live rotor speed (docs/VISUAL-QUALITY-PLAN.md). Presentation only: it reads the
# rotor speed main.gd already spins the propeller with (sim.aux[AUX_RPM]) and never writes simulation state.
#
# Solid blades strobe once they pass faster than frames are drawn: at flying speed each frame shows them at a random
# angle. Eyes fuse blade passings above roughly 15–60 Hz (flicker fusion) into a translucent disc whose darkness at a
# radius is the share of a revolution a blade covers there. profile() measures that share from the aircraft's own
# propeller meshes, with no per-aircraft numbers: the fraction of angle bins a blade triangle touches in each radius
# ring, the blade colour there, the blade count and the plane the blades sweep. update() then cross-fades by
# blade-passing frequency between the model's blades and a vertex-alpha disc lit like any other surface.
#
# Layout: this Node3D sits beside the model (a child of the flight scene, never inside `airplane`), copies the
# propeller's world transform every frame and owns the disc plus, while fading, an opaque hub copy and a faded blade
# copy of the rotating meshes (split by radius: the Lumber's spinner, backplate and bell share one mesh with its
# blades). The model's own blade nodes are only shown or hidden; their meshes and materials are never edited, so the
# Home preview, the projected silhouette (which skips `propeller`) and the crash wreck's duplicate stay as built.
# A prop strike (render/crash/prop_break.gd) marks the propeller broken: the blur then keeps the blades hidden and
# shows nothing of its own, and the broken stubs are never measured as blades.
# Evidence and limits: docs/research/visual-quality-implementation/VQ-05/README.md.
extends Node3D

const PropBreak := preload("res://render/crash/prop_break.gd")

## Blade-passing frequency (blades × rev/s) where the blades start to blur and where the disc is complete. Flicker
## fusion spans ~15 Hz (dim) to ~60 Hz (bright); 60 fps rendering aliases above 30 Hz. Perceptual estimates.
const BLUR_START_HZ := 12.0
const BLUR_FULL_HZ := 48.0
## Disc opacity = GAIN × measured coverage. 1.0 is the time-averaged occlusion; the value is an art control.
const GAIN := 1.0
## Coverage grid over [0, tip radius] × [0, 2π): numerical resolution, not aircraft data.
const RINGS := 36
const ANGLE_BINS := 240
## Bins of an angular hole closed inside one ring (sampling insurance; blade edges are never extended).
const CLOSE_GAP_BINS := 1
## Disc mesh segments around the axis.
const SEGMENTS := 72
## A rotating mesh surface reaching past this share of the tip radius carries blades (the rest is hub hardware).
const BLADE_SHARE := 0.5
## Rings covered at least this much from the axis outward are the hub (spinner, backplate, bell) and stay opaque.
const HUB_COVERAGE := 0.98
## Ring index (share of the tip radius) where blades are counted as runs of covered bins.
const COUNT_AT_SHARE := 0.7

var measured: Dictionary = {}
## Last applied blur fraction (0 = the model's own blades, 1 = disc only) and rotor speed.
var blur := 0.0
var rpm := 0.0
var _shown := false
var _broken := false
var _applied := false
var _propeller: Node3D
var _session: Node
var _disc: MeshInstance3D
var _disc_materials: Array[StandardMaterial3D] = []
var _originals: Array[MeshInstance3D] = []
var _hub_copies: Array[MeshInstance3D] = []
var _blade_copies: Array[MeshInstance3D] = []
var _fade_materials: Array[BaseMaterial3D] = []


## Attaches the blur beside `airplane` (render/airplane.gd build result) under `parent`, reading `session.sim.aux[0]`
## each frame; `session` may be null for callers that drive update() themselves (tests, captures). Returns null for
## an aircraft without a propeller (the Vantage Jet) and never touches the model until the first update() with speed.
static func attach(airplane: Dictionary, session: Node, parent: Node) -> Node3D:
	if airplane.is_empty() or not airplane.get("has_propeller", true) or airplane.get("propeller") == null:
		return null
	var measured := profile(airplane.propeller, airplane.root)
	if measured.is_empty():
		return null
	var node: Node3D = new()
	node.name = "PropellerBlur"
	node.measured = measured
	node._propeller = airplane.propeller
	node._session = session
	node._build()
	parent.add_child(node)
	return node


## Blur fraction for a rotor speed: 0 below BLUR_START_HZ blade passings per second, 1 above BLUR_FULL_HZ.
static func blur_fraction(rotor_rpm: float, blades: int) -> float:
	var passing_hz := maxi(blades, 1) * absf(rotor_rpm) / 60.0
	return smoothstep(BLUR_START_HZ, BLUR_FULL_HZ, passing_hz)


## Transform of `node` relative to `root` through the node tree (works before the tree is in a scene).
static func relative(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Measures the propeller under `propeller` (local +Z = spin axis, as main.gd spins propeller.rotation.z).
## Returns {} without blade geometry. Otherwise: radius (tip, m), hub_radius (opaque core, m), inner_radius (where the
## disc starts: the core or any other mesh the blade plane cuts, m), blades (count), plane_z (m along the axis),
## coverage (PackedFloat64Array, share of a revolution covered per ring from the axis), ring_width (m),
## colors (Array[Material] per ring), surfaces (the blade-carrying mesh surfaces: node, surface, transform, arrays).
static func profile(propeller: Node3D, root: Node3D = null) -> Dictionary:
	var surfaces: Array = []
	var radius := 0.0
	for item in propeller.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		if mi.mesh == null or mi.has_meta(PropBreak.STUBS_META):
			continue
		var t := relative(propeller, mi)
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var rmax := 0.0
			for v in verts:
				var p := t * v
				rmax = maxf(rmax, Vector2(p.x, p.y).length())
			surfaces.append({node = mi, surface = s, material = mi.get_active_material(s), transform = t, arrays = arrays, rmax = rmax})
			radius = maxf(radius, rmax)
	if radius <= 0.0:
		return {}
	var blade_surfaces: Array = surfaces.filter(func(e: Dictionary) -> bool: return e.rmax >= BLADE_SHARE * radius)
	if blade_surfaces.is_empty():
		return {}
	# Coverage grid: a cell is set when a blade triangle covers it. Triangles are rasterized in polar space (ring
	# rows, angle bins), so cost follows covered area, not triangle size.
	var grid := PackedByteArray()
	grid.resize(RINGS * ANGLE_BINS)
	var hits: Array = [] # per ring: {blade surface index: cells}
	for _i in RINGS:
		hits.append({})
	var ring_width := radius / RINGS
	var z_sum := 0.0
	var z_count := 0
	for k in blade_surfaces.size():
		var e: Dictionary = blade_surfaces[k]
		var t: Transform3D = e.transform
		var arrays: Array = e.arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = _indices(arrays, verts.size())
		for first in range(0, index.size() - 2, 3):
			var a := t * verts[index[first]]
			var b := t * verts[index[first + 1]]
			var c := t * verts[index[first + 2]]
			_rasterize(grid, hits, k, a, b, c, ring_width)
			for p in [a, b, c]:
				if Vector2(p.x, p.y).length() >= 0.5 * radius:
					z_sum += p.z
					z_count += 1
	var coverage := PackedFloat64Array()
	coverage.resize(RINGS)
	var colors: Array = []
	var runs_at_count := 0
	var count_ring := clampi(int(COUNT_AT_SHARE * RINGS), 0, RINGS - 1)
	for ring in RINGS:
		var row := grid.slice(ring * ANGLE_BINS, (ring + 1) * ANGLE_BINS)
		_close_gaps(row)
		var covered := 0
		var runs := 0
		for bin in ANGLE_BINS:
			if row[bin] != 0:
				covered += 1
				if row[posmod(bin - 1, ANGLE_BINS)] == 0:
					runs += 1
		coverage[ring] = float(covered) / ANGLE_BINS
		if ring == count_ring:
			runs_at_count = runs if covered < ANGLE_BINS else 1
		var best := -1
		var best_hits := 0
		for k in hits[ring]:
			if int(hits[ring][k]) > best_hits:
				best_hits = int(hits[ring][k])
				best = int(k)
		colors.append(blade_surfaces[best].material if best >= 0 else null)
	var hub_rings := 0
	while hub_rings < RINGS and coverage[hub_rings] >= HUB_COVERAGE:
		hub_rings += 1
	var hub_radius := hub_rings * ring_width
	var plane_z := z_sum / z_count if z_count > 0 else 0.0
	var inner_radius := maxf(hub_radius, _cut_radius(propeller, root, blade_surfaces, plane_z, radius) if root != null else 0.0)
	return {radius = radius, hub_radius = hub_radius, inner_radius = inner_radius, blades = maxi(runs_at_count, 1),
		plane_z = plane_z, coverage = coverage, ring_width = ring_width, colors = colors, surfaces = blade_surfaces}


## Index triples of a surface: its own index array, or sequential triangles when it has none.
static func _indices(arrays: Array, vertex_count: int) -> PackedInt32Array:
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	if index != null and index.size() > 0:
		return index
	var out := PackedInt32Array()
	out.resize(vertex_count - vertex_count % 3)
	for i in out.size():
		out[i] = i
	return out


## Marks the grid cells a triangle covers. Polar coordinates: row = r / ring_width, column = angle in bins. A
## triangle that contains or touches the axis is filled as the sectors of its edges seen from the axis (a
## conservative cover for spinner caps); any other triangle is clipped row by row, where a convex polygon's angular
## extent is the extent of its clipped vertices.
static func _rasterize(grid: PackedByteArray, hits: Array, surface: int, a: Vector3, b: Vector3, c: Vector3, ring_width: float) -> void:
	var rows := PackedFloat64Array([Vector2(a.x, a.y).length() / ring_width, Vector2(b.x, b.y).length() / ring_width, Vector2(c.x, c.y).length() / ring_width])
	var near_axis := minf(rows[0], minf(rows[1], rows[2])) < 1e-3
	if near_axis or _contains_origin(a, b, c):
		var points := [a, b, c]
		for i in 3:
			var p: Vector3 = points[i]
			var q: Vector3 = points[(i + 1) % 3]
			if Vector2(p.x, p.y).length() < 1e-6 or Vector2(q.x, q.y).length() < 1e-6:
				continue
			var top := mini(int(maxf(rows[i], rows[(i + 1) % 3])), RINGS - 1)
			var from := _column(p)
			var to := _unwrap(_column(q), from)
			for row in top + 1:
				_mark_span(grid, hits, surface, row, minf(from, to), maxf(from, to))
		return
	var columns := PackedFloat64Array([_column(a), 0.0, 0.0])
	columns[1] = _unwrap(_column(b), columns[0])
	columns[2] = _unwrap(_column(c), columns[0])
	var lowest := int(minf(rows[0], minf(rows[1], rows[2])))
	var highest := mini(int(maxf(rows[0], maxf(rows[1], rows[2]))), RINGS - 1)
	for row in range(lowest, highest + 1):
		var lo := INF
		var hi := -INF
		for i in 3:
			if rows[i] >= row and rows[i] < row + 1:
				lo = minf(lo, columns[i])
				hi = maxf(hi, columns[i])
			var j := (i + 1) % 3
			for level in [float(row), float(row + 1)]:
				if (rows[i] - level) * (rows[j] - level) < 0.0:
					var column: float = columns[i] + (columns[j] - columns[i]) * (level - rows[i]) / (rows[j] - rows[i])
					lo = minf(lo, column)
					hi = maxf(hi, column)
		if lo <= hi:
			_mark_span(grid, hits, surface, row, lo, hi)


static func _column(p: Vector3) -> float:
	return fposmod(atan2(p.y, p.x), TAU) / TAU * ANGLE_BINS


## The column within half a turn of `reference` (triangles never span more than that).
static func _unwrap(column: float, reference: float) -> float:
	if column - reference > ANGLE_BINS * 0.5:
		return column - ANGLE_BINS
	if reference - column > ANGLE_BINS * 0.5:
		return column + ANGLE_BINS
	return column


static func _contains_origin(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var d1 := a.x * b.y - a.y * b.x
	var d2 := b.x * c.y - b.y * c.x
	var d3 := c.x * a.y - c.y * a.x
	return (d1 >= 0.0 and d2 >= 0.0 and d3 >= 0.0) or (d1 <= 0.0 and d2 <= 0.0 and d3 <= 0.0)


static func _mark_span(grid: PackedByteArray, hits: Array, surface: int, row: int, lo: float, hi: float) -> void:
	var counts: Dictionary = hits[row]
	var first := int(floor(lo))
	var last := mini(int(floor(hi)), first + ANGLE_BINS - 1)
	for column in range(first, last + 1):
		var bin := posmod(column, ANGLE_BINS)
		grid[row * ANGLE_BINS + bin] = 1
		counts[surface] = int(counts.get(surface, 0)) + 1


## Fills angular holes of at most CLOSE_GAP_BINS bins between covered bins of one ring (circular).
static func _close_gaps(row: PackedByteArray) -> void:
	var n := row.size()
	for bin in n:
		if row[bin] != 0:
			continue
		var gap := 0
		var next := bin
		while gap <= CLOSE_GAP_BINS and row[posmod(next, n)] == 0:
			gap += 1
			next += 1
		if gap <= CLOSE_GAP_BINS and row[posmod(bin - 1, n)] != 0 and row[posmod(next, n)] != 0:
			for fill in gap:
				row[posmod(bin + fill, n)] = 1


## Largest radius at which any other model mesh (spinner, cowl, hub hardware) crosses the blade plane, in the
## propeller frame, so the disc starts outside it instead of cutting through an opaque surface.
static func _cut_radius(propeller: Node3D, root: Node3D, blade_surfaces: Array, plane_z: float, radius: float) -> float:
	var blade_nodes: Array = []
	for e in blade_surfaces:
		blade_nodes.append(e.node)
	var to_propeller := relative(root, propeller).affine_inverse()
	var cut := 0.0
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		if mi.mesh == null or blade_nodes.has(mi):
			continue
		var t := to_propeller * relative(root, mi)
		var box := t * mi.get_aabb()
		if box.position.z > plane_z or box.end.z < plane_z:
			continue
		if box.position.x > radius or box.end.x < -radius or box.position.y > radius or box.end.y < -radius:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index := _indices(arrays, verts.size())
			for first in range(0, index.size() - 2, 3):
				var a := t * verts[index[first]]
				var b := t * verts[index[first + 1]]
				var c := t * verts[index[first + 2]]
				var lo := minf(a.z, minf(b.z, c.z))
				var hi := maxf(a.z, maxf(b.z, c.z))
				if lo <= plane_z and hi >= plane_z:
					for p in [a, b, c]:
						cut = maxf(cut, Vector2(p.x, p.y).length())
	return minf(cut, radius)


func _build() -> void:
	_build_copies()
	_build_disc()


## Hub (opaque) and blade (faded) copies of every blade-carrying surface, split per triangle at the hub radius.
func _build_copies() -> void:
	var fade_by_material: Dictionary = {}
	for e in measured.surfaces:
		var node: MeshInstance3D = e.node
		if not _originals.has(node):
			_originals.append(node)
		var arrays: Array = e.arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index := _indices(arrays, verts.size())
		var t: Transform3D = e.transform
		var hub_index := PackedInt32Array()
		var blade_index := PackedInt32Array()
		var limit: float = measured.hub_radius + 1e-6
		for first in range(0, index.size() - 2, 3):
			var inside := true
			for k in 3:
				var p := t * verts[index[first + k]]
				if Vector2(p.x, p.y).length() > limit:
					inside = false
					break
			var target := hub_index if inside else blade_index
			target.append(index[first])
			target.append(index[first + 1])
			target.append(index[first + 2])
		var original: Material = e.material
		if not hub_index.is_empty():
			_hub_copies.append(_copy(node, e.surface, arrays, hub_index, t, original, "hub"))
		if not blade_index.is_empty():
			if not fade_by_material.has(original):
				fade_by_material[original] = _fade_material(original)
				_fade_materials.append(fade_by_material[original])
			_blade_copies.append(_copy(node, e.surface, arrays, blade_index, t, fade_by_material[original], "blade"))


func _copy(node: MeshInstance3D, surface: int, arrays: Array, index: PackedInt32Array, t: Transform3D, material: Material, label: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var own: Array = arrays.duplicate()
	own[Mesh.ARRAY_INDEX] = index
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, own)
	mesh.surface_set_material(0, material)
	var copy := MeshInstance3D.new()
	copy.name = "%s_%s_%d" % [node.name, label, surface]
	copy.mesh = mesh
	copy.transform = t
	copy.cast_shadow = node.cast_shadow
	copy.visible = false
	add_child(copy)
	return copy


## The blade's own material with alpha blending; a plain grey stand-in for materials without albedo.
static func _fade_material(original: Material) -> BaseMaterial3D:
	var faded: BaseMaterial3D
	if original is BaseMaterial3D:
		faded = (original as BaseMaterial3D).duplicate() as BaseMaterial3D
	else:
		faded = StandardMaterial3D.new()
		faded.albedo_color = Color(0.5, 0.5, 0.5)
	faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return faded


## Vertex-alpha annulus from the disc's inner radius to the tip, one surface per blade material along the radius.
func _build_disc() -> void:
	var coverage: PackedFloat64Array = measured.coverage
	var ring_width: float = measured.ring_width
	var mesh := ArrayMesh.new()
	var first_ring := clampi(ceili(measured.inner_radius / ring_width - 1e-6), 0, RINGS)
	var ring := first_ring
	while ring < RINGS:
		var material: Material = measured.colors[ring]
		var last := ring
		while last + 1 < RINGS and measured.colors[last + 1] == material:
			last += 1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in range(ring, last + 1):
			var inner := _boundary_alpha(coverage, r)
			var outer := _boundary_alpha(coverage, r + 1)
			if inner <= 0.0 and outer <= 0.0:
				continue
			_annulus_band(st, r * ring_width, (r + 1) * ring_width, inner, outer)
		st.generate_normals()
		var band := st.commit()
		if band.get_surface_count() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, band.surface_get_arrays(0))
			var disc_material := _disc_material(material)
			mesh.surface_set_material(mesh.get_surface_count() - 1, disc_material)
			_disc_materials.append(disc_material)
		ring = last + 1
	_disc = MeshInstance3D.new()
	_disc.name = "disc"
	_disc.mesh = mesh
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.visible = false
	add_child(_disc)


## Coverage at a ring boundary: the mean of the rings on both sides (zero outside the grid).
static func _boundary_alpha(coverage: PackedFloat64Array, boundary: int) -> float:
	var inner: float = coverage[boundary - 1] if boundary - 1 >= 0 else 0.0
	var outer: float = coverage[boundary] if boundary < coverage.size() else 0.0
	return clampf(0.5 * (inner + outer), 0.0, 1.0)


## One band of quads between two radii; alpha in the vertex colour. generate_normals() derives the normal from the
## winding, and the engine flips it on back faces, so both sides of the disc read as lit (VQ-05 renderer probe).
func _annulus_band(st: SurfaceTool, r0: float, r1: float, a0: float, a1: float) -> void:
	var z: float = measured.plane_z
	for s in SEGMENTS:
		var t0 := TAU * s / SEGMENTS
		var t1 := TAU * (s + 1) / SEGMENTS
		var p00 := Vector3(r0 * cos(t0), r0 * sin(t0), z)
		var p01 := Vector3(r0 * cos(t1), r0 * sin(t1), z)
		var p10 := Vector3(r1 * cos(t0), r1 * sin(t0), z)
		var p11 := Vector3(r1 * cos(t1), r1 * sin(t1), z)
		for tri in [[p00, a0, p10, a1, p01, a0], [p01, a0, p10, a1, p11, a1]]:
			for k in 3:
				st.set_color(Color(1, 1, 1, tri[2 * k + 1]))
				st.add_vertex(tri[2 * k])


static func _disc_material(source: Material) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if source is BaseMaterial3D:
		var b := source as BaseMaterial3D
		m.albedo_color = Color(b.albedo_color.r, b.albedo_color.g, b.albedo_color.b, 0.0)
		m.roughness = b.roughness
		m.metallic = b.metallic
	else:
		m.albedo_color = Color(0.5, 0.5, 0.5, 0.0)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process(_dt: float) -> void:
	if _session == null or not is_instance_valid(_session) or _session.get("sim") == null:
		return
	update(float(_session.sim.aux[0]))


## Applies the blur for a rotor speed (rev/min) and follows the propeller. Idempotent; cheap when nothing changed.
func update(rotor_rpm: float) -> void:
	rpm = rotor_rpm
	var broken := is_instance_valid(_propeller) and _propeller.has_meta(PropBreak.BROKEN_META)
	var shown := not broken and is_instance_valid(_propeller) and _propeller.is_inside_tree() and _propeller.is_visible_in_tree()
	if shown:
		global_transform = _propeller.global_transform
	var fraction := blur_fraction(rpm, measured.blades) if shown else 0.0
	if _applied and fraction == blur and shown == _shown and broken == _broken:
		return
	blur = fraction
	_shown = shown
	_broken = broken
	_applied = true
	for node in _originals:
		# The aircraft can be freed before this sibling observer. Still retire
		# our owned copies below instead of aborting on a borrowed mesh.
		if is_instance_valid(node):
			node.visible = fraction <= 0.0 and not broken
	for node in _hub_copies:
		node.visible = shown and fraction > 0.0
	for node in _blade_copies:
		node.visible = shown and fraction > 0.0 and fraction < 1.0
	for material in _fade_materials:
		material.albedo_color.a = 1.0 - fraction
	_disc.visible = shown and fraction > 0.0
	for material in _disc_materials:
		material.albedo_color.a = clampf(GAIN * fraction, 0.0, 1.0)


## Restores the model's own blades (for callers that detach the blur), unless a prop strike broke them.
func _exit_tree() -> void:
	# Restoration changes visibility outside update(); a retained observer must
	# reapply its state after reattachment even when RPM has not changed.
	_applied = false
	for node in _originals:
		if is_instance_valid(node):
			node.visible = not _broken
