# FIELD-WORLD-PLAN FW-24: the real night sky. 5,080 stars (V ≤ 6.0, app/data/sky/stars.json from the Yale Bright Star
# Catalogue) placed on a 19 km sphere around the pilot and turned by local sidereal time and latitude, so the
# constellations stand where they stand that night. One MultiMesh (1 draw). Brightness is physical: a star's
# irradiance relative to the sun, spread over its quad, so the time-of-day exposure decides what shows.
extends RefCounted

const Frames := preload("res://render/frames.gd")
const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const SkyAppearance := preload("res://render/weather/sky_appearance.gd")
const SHADER := preload("res://render/world/stars.gdshader")
const DATA_PATH := "res://data/sky/stars.json"

## Inside the camera's far plane (Spec.CAMERA.far 21 km); ground, hills and trees in front hide the stars by depth.
const RADIUS_M := 19000.0
## A V = 0 star's illuminance relative to the sun's (borrowed: ~2.5·10⁻⁶ lux against ~1.2·10⁵ lux).
const VEGA_RATIO := 2.1e-11
const SIZE_PX := 3.0
## Display compensation (estimate, checked on captures): a monitor cannot reproduce a point source's contrast for a
## dark-adapted eye, and Godot's ACES fit maps linear values below ~0.002 to black. Targets: V ≈ 6 just visible on a
## moonless night, about V ≈ 5 under a full moon, none in civil twilight. (The shader encodes for the engine's ALBEDO
## linearisation, render/world/engine_srgb.gdshaderinc; before that fix the stars were ~40× too dim.)
const DISPLAY_GAIN := 25.0
## Mean of the quad's profile exp(−4r²) over [−1, 1]² ((∫e^(−4x²)dx)²/4).
const PROFILE_MEAN := 0.1945

# One content-keyed catalogue; placements and render resources remain detached.
static var _catalogue_source := ""
static var _catalogue_stars: Array = []


## Unit vector in render axes for an (azimuth from north clockwise, elevation) in degrees.
static func _local(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)])


## The rotation from equatorial axes (X toward RA 0°, Y toward RA 90°, Z the north celestial pole) to render axes,
## for a local sidereal time and latitude. The meridian's equator point stands 90° − latitude above the south.
static func equatorial_basis(lst_deg: float, latitude_deg: float) -> Basis:
	var lat := deg_to_rad(latitude_deg)
	var north := _local(0.0, 0.0)
	var east := _local(90.0, 0.0)
	var zenith := _local(0.0, 90.0)
	var pole := north * cos(lat) + zenith * sin(lat)
	var meridian := -north * sin(lat) + zenith * cos(lat)
	var lst := deg_to_rad(lst_deg)
	var x := meridian * cos(lst) - east * sin(lst)
	var y := meridian * sin(lst) + east * cos(lst)
	return Basis(x, y, pole)


## Equatorial unit vector for J2000 right ascension and declination (degrees).
static func equatorial(ra_deg: float, dec_deg: float) -> Vector3:
	var ra := deg_to_rad(ra_deg)
	var dec := deg_to_rad(dec_deg)
	return Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))


## Approximate star colour from the B−V index: Ballesteros' temperature, then Tanner Helland's blackbody fit,
## half-desaturated (the eye sees most stars nearly white).
static func colour(bv: float) -> Color:
	var t := 4600.0 * (1.0 / (0.92 * bv + 1.7) + 1.0 / (0.92 * bv + 0.62)) / 100.0
	var r := 1.0 if t <= 66.0 else clampf(1.292936 * pow(t - 60.0, -0.1332047592), 0.0, 1.0)
	var g := clampf(0.3900816 * log(t) - 0.6318414, 0.0, 1.0) if t <= 66.0 else clampf(1.1298909 * pow(t - 60.0, -0.0755148492), 0.0, 1.0)
	var b := 1.0 if t >= 66.0 else (0.0 if t <= 19.0 else clampf(0.5432068 * log(t - 10.0) - 1.1962541, 0.0, 1.0))
	var c := Color(r, g, b).lerp(Color.WHITE, 0.5)
	return c / maxf(maxf(c.r, c.g), c.b)


static func rows() -> Array:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return []
	return _rows_from_source(f.get_as_text())


static func _rows_from_source(source: String) -> Array:
	var data: Variant = JSON.parse_string(source)
	if not (data is Dictionary) or data.get("format", "") != "openrc-stars v1":
		push_warning("star list missing or invalid; the night sky stays empty")
		return []
	return data.rows


static func _placements_for_source(source: String, to_render: Basis) -> Array:
	var out := []
	if source == _catalogue_source and not _catalogue_stars.is_empty():
		for star: Array in _catalogue_stars:
			out.append({dir = to_render * star[0], colour = star[1], flux = star[2]})
		return out
	var prepared := _rows_from_source(source)
	for row: Array in prepared:
		var direction := equatorial(float(row[0]) / 1000.0, float(row[1]) / 1000.0)
		var star_colour := colour(float(row[3]) / 100.0)
		var flux := pow(10.0, -0.4 * float(row[2]) / 100.0)
		out.append({dir = to_render * direction, colour = star_colour, flux = flux})
		# Reuse this private parsed row rather than allocate another per-star container.
		row[0] = direction
		row[1] = star_colour
		row[2] = flux
		row.resize(3)
	# Empty or rejected source retires the previous prepared catalogue.
	_catalogue_source = source if not prepared.is_empty() else ""
	_catalogue_stars = prepared
	return out


## Peak quad radiance of a V = 0 star in scene units (sun irradiance = 1), display compensation included.
static func radiance_scale() -> float:
	var rad_per_px := deg_to_rad(Spec.CAMERA.fov_deg) / 720.0 # reference 1280×720 view
	return DISPLAY_GAIN * VEGA_RATIO / (rad_per_px * rad_per_px * SIZE_PX * SIZE_PX * PROFILE_MEAN)


## Per star, brightest first: {dir (render axes, unit), colour, flux (10^(−0.4·V))}. Pure, so tests can read it
## (the headless renderer keeps no MultiMesh instance data).
static func placements(state: Dictionary, latitude_deg: float) -> Array:
	var out := []
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_catalogue_source = ""
		_catalogue_stars = []
		return out
	return _placements_for_source(file.get_as_text(), equatorial_basis(state.lst_deg, latitude_deg))


## The star field for a time-of-day state (render/world/sky_state.gd) at a latitude. Uses the sky material's cloud
## settings so the deck hides the same stars it covers.
static func build(state: Dictionary, latitude_deg: float, cloud_snapshot: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Stars"
	var list := placements(state, latitude_deg)
	if list.is_empty():
		return root
	var a: Dictionary = Spec.ATMOSPHERE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("radiance_scale", radiance_scale())
	material.set_shader_parameter("size_px", SIZE_PX)
	material.set_shader_parameter("rad_per_px", deg_to_rad(Spec.CAMERA.fov_deg) / 720.0)
	_apply_cloud_snapshot(material, cloud_snapshot if not cloud_snapshot.is_empty() else Atmosphere.cloud_state_snapshot())
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = list.size()
	for i in list.size():
		var star: Dictionary = list[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, star.dir * RADIUS_M))
		mm.set_instance_color(i, star.colour)
		mm.set_instance_custom_data(i, Color(star.flux, 0.0, 0.0, 0.0))
	var node := MultiMeshInstance3D.new()
	node.name = "StarField"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3.ONE * -RADIUS_M * 1.01, Vector3.ONE * RADIUS_M * 2.02) # always in view
	root.add_child(node)
	root.set_meta("stars", list.size())
	return root


## Refreshes one active star field after a paused preset edit or a quantized cloud transport step.
static func update_cloud_appearance(root: Node, cloud_snapshot: Dictionary) -> void:
	if root == null or not is_instance_valid(root):
		return
	var field := root.get_node_or_null("StarField") as MultiMeshInstance3D
	if field == null or field.multimesh == null:
		return
	var quad := field.multimesh.mesh as QuadMesh
	if quad == null:
		return
	var material := quad.material as ShaderMaterial
	if material == null:
		return
	_apply_cloud_snapshot(material, cloud_snapshot)


## A MultiMesh sorts as one object at its origin, not at each star's 19 km position.
## Draw it before a world cloud's blended alpha, while retaining opaque depth occlusion.
static func set_distant_cloud_order(root: Node, enabled: bool) -> void:
	var field := root.get_node_or_null("StarField") as MultiMeshInstance3D
	if field == null or field.multimesh == null:
		return
	var material := field.multimesh.mesh.material as ShaderMaterial
	var priority := -1 if enabled else 0
	if material != null and material.render_priority != priority:
		material.render_priority = priority


static func _apply_cloud_snapshot(material: ShaderMaterial, snapshot: Dictionary) -> void:
	var spec_atmosphere: Dictionary = Spec.ATMOSPHERE
	material.set_shader_parameter("cloud_coverage", float(spec_atmosphere.cloud_coverage))
	material.set_shader_parameter("cloud_scale", float(spec_atmosphere.cloud_scale))
	material.set_shader_parameter("cloud_seed", int(snapshot.get("seed", spec_atmosphere.cloud_seed)))
	material.set_shader_parameter("cluster_strength", float(spec_atmosphere.cloud_cluster_strength))
	material.set_shader_parameter("cloud_offset", _offset(snapshot.get("offset", Vector2.ZERO)))
	if str(snapshot.get("profile_id", "classic")) == "classic":
		material.set_shader_parameter("layered_appearance", false)
		material.set_shader_parameter("appearance_cloud_density", 1.0)
		return
	var layers: Array = snapshot.get("cloud_layers", [])
	var offsets: Array = []
	for layer_value: Variant in layers:
		var layer: Dictionary = layer_value
		offsets.append(layer.get("offset", Vector2.ZERO))
	var arrays := SkyAppearance.shader_arrays(layers, offsets,
		float(snapshot.get("cloud_cover", 0.0)), float(snapshot.get("cloud_density", 0.0)))
	material.set_shader_parameter("layered_appearance", true)
	material.set_shader_parameter("appearance_layer_count", arrays.layer_count)
	material.set_shader_parameter("appearance_layer_parameters", arrays.layer_parameters)
	material.set_shader_parameter("appearance_layer_motion", arrays.layer_motion)
	material.set_shader_parameter("appearance_layer_seeds", arrays.layer_seeds)
	material.set_shader_parameter("appearance_cloud_density", arrays.cloud_density)


static func _offset(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	if typeof(raw) == TYPE_ARRAY and raw.size() == 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO
