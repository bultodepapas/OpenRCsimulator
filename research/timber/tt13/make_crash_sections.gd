# TT-13c: crash section map for the Timber's merged `airframe` mesh, from the Godot-imported r1 asset (never Blender).
# Welds each surface into shells (the author's whole CAD part shells; no triangle is cut), classifies every shell by
# rules measured in TimberGeometry.DATA (TT-02), and writes app/aircraft/timber_crash_sections.gd: a run-length
# per-triangle section table that the crash wreck's SectionSplitter applies to its hidden twin only.
# Run from the repository root after `--import`:
#   "$(app/get-godot.sh)" --headless --path app --script "$PWD/research/timber/tt13/make_crash_sections.gd" -- [--check]
# --check regenerates and fails (exit 1) when the committed table differs: the asset, the importer or a rule changed.
extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const SectionSplitter := preload("res://render/crash/section_splitter.gd")
const OUT := "res://aircraft/timber_crash_sections.gd"
const SECTIONS := ["core", "wing_left", "wing_right", "horizontal_tail", "vertical_tail", "engine", "canopy"]
## Welding grid for shell detection (m): coincident vertices of one CAD part share a key.
const WELD_M := 1.0e-5
## Margins around measured stations (m): estimates, reviewed through the overlay capture.
const WING_BAND_MARGIN_M := 0.05
const TAIL_MARGIN_M := 0.05
const FIN_HALF_WIDTH_M := 0.05


func _initialize() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var model: Dictionary = Timber.build()
	var root: Node3D = model.root
	var airframe := root.find_child("airframe", true, false) as MeshInstance3D
	var rules := _rules()
	var table := classify(airframe, root, rules)
	var text := _render(table, rules)
	var path := ProjectSettings.globalize_path(OUT)
	if check:
		var ok := FileAccess.get_file_as_string(path) == text
		print("TT-13c Timber crash sections %s" % ("current" if ok else "STALE: regenerate with research/timber/tt13/make_crash_sections.gd"))
		root.free()
		quit(0 if ok else 1)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("wrote %s: %s" % [OUT, JSON.stringify(table.triangles_per_section)])
	root.free()
	quit(0)


## Thresholds in the imported root frame (+X right, +Y up, −Z nose, D0 origin), each from a measured station.
static func _rules() -> Dictionary:
	var d: Dictionary = TimberGeometry.DATA
	return {
		fuselage_half_width = float(d.wing.fuselage_half_width_at_wing.value),
		wing_le_z = float(d.wing.le_z.value) - WING_BAND_MARGIN_M,
		wing_te_z = float(d.wing.te_z.value) + WING_BAND_MARGIN_M,
		tail_z = minf(float(d.tail.le_z_centreline.value), float(d.fin.le_z_at_root.value)) - TAIL_MARGIN_M,
		fin_root_y = float(d.fin.root_y.value),
		fin_half_width = FIN_HALF_WIDTH_M,
		engine_z = float(d.fuselage.cowl_front_z.value) * 0.5,
	}


## The section of a shell from its triangle-centroid mean `c` (root frame) and its material name.
static func section_for(c: Vector3, material: String, r: Dictionary) -> String:
	if material == "glass":
		return "canopy"
	if c.z > float(r.tail_z):
		if absf(c.x) < float(r.fin_half_width):
			return "vertical_tail" if c.y > float(r.fin_root_y) else "core"
		return "horizontal_tail"
	if absf(c.x) > float(r.fuselage_half_width) and c.z > float(r.wing_le_z) and c.z < float(r.wing_te_z):
		return "wing_left" if c.x < 0.0 else "wing_right"
	if c.z < float(r.engine_z):
		return "engine"
	return "core"


## {surfaces: run-length lists, triangles_per_section, shells_per_section, triangles}.
static func classify(airframe: MeshInstance3D, root: Node3D, rules: Dictionary) -> Dictionary:
	var to_root := _relative(root, airframe)
	var mesh := airframe.mesh
	var surfaces: Array = []
	var tri_counts := {}
	var shell_counts := {}
	var total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := mesh.surface_get_material(s)
		var material_name: String = material.resource_name if material else ""
		var welded := PackedInt32Array()
		welded.resize(verts.size())
		var keys := {}
		for i in verts.size():
			var v := verts[i]
			var key := Vector3i(roundi(v.x / WELD_M), roundi(v.y / WELD_M), roundi(v.z / WELD_M))
			var id: int = keys.get(key, -1)
			if id < 0:
				id = keys.size()
				keys[key] = id
			welded[i] = id
		var parent := PackedInt32Array()
		parent.resize(keys.size())
		for i in parent.size():
			parent[i] = i
		for f in range(0, index.size(), 3):
			var a := _find(parent, welded[index[f]])
			for j in [1, 2]:
				var b := _find(parent, welded[index[f + j]])
				if a != b:
					parent[maxi(a, b)] = mini(a, b) # deterministic: the lower id is the root
					a = mini(a, b)
		var sums := {}
		var counts := {}
		for f in range(0, index.size(), 3):
			var shell := _find(parent, welded[index[f]])
			var centre := to_root * ((verts[index[f]] + verts[index[f + 1]] + verts[index[f + 2]]) / 3.0)
			sums[shell] = sums.get(shell, Vector3.ZERO) + centre
			counts[shell] = int(counts.get(shell, 0)) + 1
		var shell_section := {}
		for shell in sums:
			var section := section_for(sums[shell] / float(counts[shell]), material_name, rules)
			shell_section[shell] = SECTIONS.find(section)
			shell_counts[section] = int(shell_counts.get(section, 0)) + 1
		var runs: Array = []
		for f in range(0, index.size(), 3):
			var section_index: int = shell_section[_find(parent, welded[index[f]])]
			if not runs.is_empty() and int(runs[runs.size() - 2]) == section_index:
				runs[runs.size() - 1] = int(runs[runs.size() - 1]) + 1
			else:
				runs.append(section_index)
				runs.append(1)
			tri_counts[SECTIONS[section_index]] = int(tri_counts.get(SECTIONS[section_index], 0)) + 1
			total += 1
		surfaces.append(runs)
	return {surfaces = surfaces, triangles_per_section = tri_counts, shells_per_section = shell_counts, triangles = total}


static func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


static func _relative(root: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _render(table: Dictionary, rules: Dictionary) -> String:
	var data := {
		format = SectionSplitter.FORMAT,
		generator = "research/timber/tt13/make_crash_sections.gd",
		mesh = "airframe",
		glb_sha256 = String(TimberGeometry.DATA.inputs.glb_sha256),
		geometry_revision = String(TimberGeometry.DATA.revision),
		rules = rules,
		sections = SECTIONS,
		triangles = table.triangles,
		triangles_per_section = table.triangles_per_section,
		shells_per_section = table.shells_per_section,
		surfaces = table.surfaces,
	}
	return "# GENERATED by research/timber/tt13/make_crash_sections.gd (TT-13c); do not edit. Regenerate after the asset,\n" \
		+ "# the importer or TimberGeometry changes. Crash presentation only: the wreck splits its hidden twin with it.\n" \
		+ "extends RefCounted\n\nconst DATA := " + JSON.stringify(data, "\t", false) + "\n"
