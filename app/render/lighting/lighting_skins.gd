extends RefCounted
## Per-aircraft internal-film emission overlays. The shared opaque finish stays untouched.

const Appearance := preload("res://aircraft/ugly_stik_appearance.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")
const SkinShader := preload("res://render/lighting/rgb_skin.gdshader")

const MASK_PROFILE_ID := "jensen_stik_film_bays_v1"
const MASK_PROFILE_IDS := [MASK_PROFILE_ID]
const STRIP_ZONE_IDS := ["strip_left", "strip_right", "strip_top_left", "strip_top_right", "strip_belly"]
const MAX_SKIN_ROWS := 5
const MAX_TARGETS := 12
const MAX_INPUT_TEXTURE_SIZE := 2048
const MASK_SIZE := 512
const EMISSION_CAP := 0.15
# Keep broad film bays legible in the night preview without raising the daytime material cap.
const EXPOSURE_ENERGY_CAP := 1.2

static var _structural_mask: Image

var _root: Node3D
var _profile: Dictionary = {}
var _zones: Dictionary = {}
var _profile_brightness := 1.0
var _bindings: Array[Dictionary] = []
var _composed_textures: Dictionary = {}
var _warnings: Array[String] = []
var _last_advance_writes := 0
var _active_emission_passes := 0


## Projects validated companion IDs to live mesh/surface references. Skin rows never accept raw paths.
static func project_bindings(root: Node3D, companion: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var bindings: Array[Dictionary] = []
	if root == null or not is_instance_valid(root):
		return {"bindings": bindings, "warnings": ["aircraft root is unavailable for lighting skin projection"]}
	var layout: Variant = companion.get("lighting_layout", {})
	if not (layout is Dictionary):
		return {"bindings": bindings, "warnings": ["lighting skin layout is malformed"]}
	var skins: Variant = layout.get("skins", [])
	var raw_slots: Variant = companion.get("paint_slots", [])
	if not (skins is Array) or not (raw_slots is Array):
		return {"bindings": bindings, "warnings": ["lighting skin rows or paint slots are malformed"]}
	var family_id := str(companion.get("visual_family", ""))
	if family_id != "jensen-das-ugly-stik-60" and not skins.is_empty():
		return {"bindings": bindings, "warnings": ["lighting skin bindings are not registered for %s" % family_id]}
	if skins.size() > MAX_SKIN_ROWS:
		warnings.append("lighting skin rows exceed the %d-row projection budget" % MAX_SKIN_ROWS)
	var paint_targets_by_slot: Dictionary = {}
	for slot_value: Variant in raw_slots:
		if not (slot_value is Dictionary):
			continue
		var slot_id := str(slot_value.get("id", ""))
		var targets: Variant = slot_value.get("targets", [])
		if slot_id.is_empty() or not (targets is Array):
			continue
		var targets_by_id: Dictionary = {}
		for target_value: Variant in targets:
			if target_value is Dictionary and target_value.get("target_id") is String:
				var target_id := str(target_value.target_id)
				if not targets_by_id.has(target_id):
					targets_by_id[target_id] = target_value
		paint_targets_by_slot[slot_id] = targets_by_id
	var seen_zones: Dictionary = {}
	var used_target_ids: Dictionary = {}
	var used_surfaces: Dictionary = {}
	var target_count := 0
	for row_index in mini(skins.size(), MAX_SKIN_ROWS):
		var skin_value: Variant = skins[row_index]
		if not (skin_value is Dictionary):
			warnings.append("lighting skin row %d is malformed" % row_index)
			continue
		var zone_id := str(skin_value.get("zone_id", ""))
		var mask_id := str(skin_value.get("mask_profile_id", ""))
		if zone_id not in STRIP_ZONE_IDS or seen_zones.has(zone_id):
			warnings.append("lighting skin zone '%s' is unsupported or duplicated" % zone_id)
			continue
		seen_zones[zone_id] = true
		if mask_id not in MASK_PROFILE_IDS:
			warnings.append("lighting skin mask '%s' is unsupported for %s" % [mask_id, zone_id])
			continue
		var paint_slot_id := str(skin_value.get("paint_slot_id", ""))
		var target_ids: Variant = skin_value.get("target_ids", [])
		if not paint_targets_by_slot.has(paint_slot_id) or not (target_ids is Array):
			warnings.append("lighting skin '%s' does not resolve to an authored paint slot" % zone_id)
			continue
		var targets: Array[Dictionary] = []
		for target_id_value: Variant in target_ids:
			if target_count >= MAX_TARGETS:
				warnings.append("lighting skin targets exceed the %d-surface projection budget" % MAX_TARGETS)
				break
			if not (target_id_value is String):
				warnings.append("lighting skin '%s' has a malformed target ID" % zone_id)
				continue
			var target_id := str(target_id_value)
			if used_target_ids.has(target_id):
				warnings.append("lighting skin target '%s' is reused" % target_id)
				continue
			var target_value: Variant = paint_targets_by_slot[paint_slot_id].get(target_id)
			if not (target_value is Dictionary):
				warnings.append("lighting skin target '%s' does not resolve inside paint slot '%s'" % [target_id, paint_slot_id])
				continue
			var node_path := str(target_value.get("node_path", ""))
			if node_path.is_empty() or node_path.contains("..") or node_path.begins_with("/"):
				warnings.append("lighting skin target '%s' has an unsafe paint target path" % target_id)
				continue
			var mesh := root.get_node_or_null(NodePath(node_path)) as MeshInstance3D
			var surface := _surface_index(target_value.get("surface"))
			if mesh == null or not is_instance_valid(mesh) or (mesh != root and not root.is_ancestor_of(mesh)):
				warnings.append("lighting skin target '%s' has no live descendant mesh" % target_id)
				continue
			if mesh.mesh == null or surface < 0 or surface >= mesh.mesh.get_surface_count():
				warnings.append("lighting skin target '%s' has an invalid mesh surface" % target_id)
				continue
			var surface_key := "%d#%d" % [mesh.get_instance_id(), surface]
			if used_surfaces.has(surface_key):
				warnings.append("lighting skin surface '%s' is reused" % target_id)
				continue
			used_target_ids[target_id] = true
			used_surfaces[surface_key] = true
			target_count += 1
			targets.append({"target_id": target_id, "mesh": mesh, "surface": surface})
		if not targets.is_empty():
			bindings.append({"zone_id": zone_id, "mask_profile_id": mask_id, "targets": targets})
	return {"bindings": bindings, "warnings": warnings}


## Duplicates only supported opaque covering materials and owns only the surface overrides it installs.
func configure(root: Node3D, profile: Dictionary) -> Dictionary:
	dispose()
	_warnings.clear()
	if root == null or not is_instance_valid(root):
		return {"ok": false, "errors": ["aircraft root is unavailable"], "warnings": []}
	_root = root
	_profile = profile.duplicate(true)
	_profile_brightness = _bounded_number(profile.get("brightness", 1.0), 1.0, 0.0, 2.0)
	_zones = _zone_map(profile.get("zones", []))
	var selection := str(profile.get("selection", "custom"))
	if selection in ["inherit", "disabled"]:
		return _result()
	var raw_bindings: Variant = root.get_meta("lighting_skin_bindings", [])
	if not (raw_bindings is Array):
		_warnings.append("lighting_skin_bindings metadata is malformed")
		return _result()
	if raw_bindings.size() > MAX_SKIN_ROWS:
		_warnings.append("projected lighting skin rows exceed the %d-row runtime budget" % MAX_SKIN_ROWS)
	var target_count := 0
	var seen_surfaces: Dictionary = {}
	for row_index in mini(raw_bindings.size(), MAX_SKIN_ROWS):
		var row_value: Variant = raw_bindings[row_index]
		if not (row_value is Dictionary):
			_warnings.append("projected lighting skin row is malformed")
			continue
		var zone_id := str(row_value.get("zone_id", ""))
		var zone: Dictionary = _zones.get(zone_id, {})
		if zone_id not in STRIP_ZONE_IDS or zone.is_empty() or not bool(zone.get("enabled", false)):
			continue
		if str(row_value.get("mask_profile_id", "")) not in MASK_PROFILE_IDS:
			_warnings.append("lighting skin zone '%s' uses an unsupported mask" % zone_id)
			continue
		var targets: Variant = row_value.get("targets", [])
		if not (targets is Array):
			_warnings.append("lighting skin zone '%s' has malformed targets" % zone_id)
			continue
		for target_value: Variant in targets:
			if target_count >= MAX_TARGETS:
				_warnings.append("lighting skin bindings exceed the %d-surface runtime budget" % MAX_TARGETS)
				break
			if not (target_value is Dictionary):
				_warnings.append("lighting skin zone '%s' has a malformed target" % zone_id)
				continue
			var mesh := target_value.get("mesh") as MeshInstance3D
			var surface_value: Variant = target_value.get("surface")
			var target_id := str(target_value.get("target_id", ""))
			if mesh == null or not is_instance_valid(mesh) or (_root != mesh and not _root.is_ancestor_of(mesh)):
				_warnings.append("lighting skin target '%s' has no live descendant mesh" % target_id)
				continue
			var surface := _surface_index(surface_value)
			if mesh.mesh == null or surface < 0 or surface >= mesh.mesh.get_surface_count():
				_warnings.append("lighting skin target '%s' has an invalid mesh surface" % target_id)
				continue
			var key := "%d#%d" % [mesh.get_instance_id(), surface]
			if seen_surfaces.has(key):
				_warnings.append("lighting skin surface '%s' is duplicated" % target_id)
				continue
			seen_surfaces[key] = true
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			if original == null:
				_warnings.append("lighting skin target '%s' is not a StandardMaterial3D; opaque surface kept" % target_id)
				continue
			if mesh.material_override != null:
				_warnings.append("lighting skin target '%s' has a mesh-wide material override; surface kept unchanged" % target_id)
				continue
			if original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				_warnings.append("lighting skin target '%s' is not opaque; surface kept unchanged" % target_id)
				continue
			if original.cull_mode != BaseMaterial3D.CULL_BACK:
				_warnings.append("lighting skin target '%s' uses unsupported culling; surface kept unchanged" % target_id)
				continue
			if original.vertex_color_use_as_albedo:
				_warnings.append("lighting skin target '%s' uses vertex color as albedo; surface kept unchanged" % target_id)
				continue
			if original.next_pass != null:
				_warnings.append("lighting skin target '%s' already has a next pass; surface kept unchanged" % target_id)
				continue
			if not _supports_uv1_transform(original):
				_warnings.append("lighting skin target '%s' uses an unsupported UV1 transform; surface kept unchanged" % target_id)
				continue
			if original.emission_enabled or original.emission_texture != null:
				_warnings.append("lighting skin target '%s' already has authored emission; surface kept unchanged" % target_id)
				continue
			var composed_texture := _emission_texture_for(original)
			if composed_texture == null:
				_warnings.append("lighting skin target '%s' has no composable albedo image; opaque surface kept" % target_id)
				continue
			var overlay := ShaderMaterial.new()
			overlay.shader = SkinShader
			overlay.set_shader_parameter("emission_map", composed_texture)
			var clone := original.duplicate() as StandardMaterial3D
			if clone == null:
				_warnings.append("lighting skin target '%s' material could not be duplicated; opaque surface kept" % target_id)
				continue
			var previous_override := mesh.get_surface_override_material(surface)
			mesh.set_surface_override_material(surface, clone)
			_bindings.append({
				"zone_id": zone_id,
				"target_id": target_id,
				"mesh": mesh,
				"surface": surface,
				"original_override": previous_override,
				"material": clone,
				"overlay": overlay,
				"last_color": Color.WHITE,
				"color_set": false,
				"last_energy": 0.0,
				"energy_set": false,
			})
			target_count += 1
	return _result()


## Updates the owned additive pass; the cloned opaque material keeps all source shading intact.
func advance(seconds: float, telemetry: Dictionary, mode: String, gain: float) -> Dictionary:
	_last_advance_writes = 0
	_active_emission_passes = 0
	if _root == null or not is_instance_valid(_root):
		return {"writes": 0}
	var clock := _bounded_number(seconds, 0.0, 0.0, 1.0e12)
	var exposure := _bounded_number(telemetry.get("exposure", 1.0), 1.0, 0.0001, 1000000.0)
	var user_gain := _bounded_number(gain, 0.0, 0.0, 2.0)
	var active_mode := mode if mode in ["all", "nav", "off"] else "off"
	var sequence: Array = _profile.get("sequence", []) if _profile.get("sequence", []) is Array else []
	for binding: Dictionary in _bindings:
		var material := binding.get("material") as StandardMaterial3D
		var overlay := binding.get("overlay") as ShaderMaterial
		if material == null or not is_instance_valid(material) or overlay == null or not is_instance_valid(overlay):
			continue
		var zone_id := str(binding.get("zone_id", ""))
		var zone: Dictionary = _zones.get(zone_id, {})
		var show := active_mode == "all" and user_gain > 0.0 and bool(zone.get("enabled", false))
		var color := Color.WHITE
		var energy := 0.0
		if show:
			var pattern: Dictionary = zone.get("pattern", {})
			color = LightingPolicy.sample(pattern, clock, 0.5, sequence, zone_id)
			var reaction := LightingPolicy.reaction(zone.get("reactive", {}), telemetry)
			var reaction_gain := _bounded_number(reaction.get("multiplier", 1.0), 1.0, 0.0, 2.0)
			var zone_brightness := _bounded_number(zone.get("brightness", 1.0), 1.0, 0.0, 2.0)
			var exposure_cap := minf(EMISSION_CAP, EXPOSURE_ENERGY_CAP / exposure)
			energy = exposure_cap * _profile_brightness * zone_brightness * user_gain * reaction_gain
			show = energy > 0.0
		if show:
			if material.next_pass != overlay:
				material.next_pass = overlay
				_last_advance_writes += 1
			_active_emission_passes += 1
			var previous_color: Color = binding.get("last_color", Color.WHITE)
			if not bool(binding.get("color_set", false)) or not previous_color.is_equal_approx(color):
				overlay.set_shader_parameter("emission_color", color)
				binding["last_color"] = color
				binding["color_set"] = true
				_last_advance_writes += 1
			var previous_energy := float(binding.get("last_energy", 0.0))
			var energy_tolerance := maxf(0.000000001, maxf(absf(previous_energy), absf(energy)) * 0.001)
			if not bool(binding.get("energy_set", false)) or absf(previous_energy - energy) > energy_tolerance:
				overlay.set_shader_parameter("energy", energy)
				binding["last_energy"] = energy
				binding["energy_set"] = true
				_last_advance_writes += 1
		elif material.next_pass == overlay:
			material.next_pass = null
			_last_advance_writes += 1
	return {"writes": _last_advance_writes}


## Restores a prior override only while this helper still owns the installed one.
func dispose() -> void:
	for binding: Dictionary in _bindings:
		var mesh := binding.get("mesh") as MeshInstance3D
		var material := binding.get("material") as StandardMaterial3D
		var surface := int(binding.get("surface", -1))
		if mesh == null or not is_instance_valid(mesh) or mesh.mesh == null \
				or surface < 0 or surface >= mesh.mesh.get_surface_count():
			continue
		if mesh.get_surface_override_material(surface) == material:
			mesh.set_surface_override_material(surface, binding.get("original_override") as Material)
	_bindings.clear()
	_composed_textures.clear()
	_zones.clear()
	_profile.clear()
	_profile_brightness = 1.0
	_last_advance_writes = 0
	_active_emission_passes = 0
	_root = null


func budget_info() -> Dictionary:
	var mask := _structural_mask
	var composed_pixel_bytes := _composed_textures.size() * MASK_SIZE * MASK_SIZE * 4
	var composed_mipped_bytes := _composed_textures.size() * _mipped_image_bytes(MASK_SIZE, MASK_SIZE, 4)
	return {
		"targets": _bindings.size(),
		"active_emission_passes": _active_emission_passes,
		"max_targets": MAX_TARGETS,
		"composed_textures": _composed_textures.size(),
		"structural_mask_pixel_bytes": mask.get_width() * mask.get_height() if mask != null else 0,
		"composed_texture_pixel_bytes": composed_pixel_bytes,
		"composed_texture_mipped_bytes": composed_mipped_bytes,
		"max_composed_texture_mipped_bytes": MAX_TARGETS * _mipped_image_bytes(MASK_SIZE, MASK_SIZE, 4),
		"last_advance_writes": _last_advance_writes,
		"structural_mask_pixels": mask.get_width() * mask.get_height() if mask != null else 0,
	}


static func mask_value(span_m: float, chord_fraction: float) -> float:
	var mask := _structural_mask_image()
	if mask == null or not is_finite(span_m) or not is_finite(chord_fraction):
		return 0.0
	var wing: Dictionary = Geometry.DATA.wing
	var chord := float(wing.chord)
	var point := Vector3(span_m, 0.0, clampf(chord_fraction, 0.0, 1.0) * chord)
	var uv := Finish.uv(point, "wing")
	var x := clampi(floori(uv.x * float(mask.get_width())), 0, mask.get_width() - 1)
	var y := clampi(floori(uv.y * float(mask.get_height())), 0, mask.get_height() - 1)
	return mask.get_pixel(x, y).r


func _emission_texture_for(source: StandardMaterial3D) -> Texture2D:
	var albedo_texture := source.albedo_texture as Texture2D
	var texture_key := "none" if albedo_texture == null else str(albedo_texture.get_instance_id())
	var key := texture_key + "#" + source.albedo_color.to_html()
	if _composed_textures.has(key):
		return _composed_textures[key] as Texture2D
	var mask := _structural_mask_image()
	if mask == null:
		return null
	var source_image: Image = albedo_texture.get_image() if albedo_texture != null else null
	if albedo_texture != null and (source_image == null or source_image.is_empty()):
		return null
	if source_image != null and (source_image.get_width() > MAX_INPUT_TEXTURE_SIZE or source_image.get_height() > MAX_INPUT_TEXTURE_SIZE):
		return null
	var source_size := source_image.get_size() if source_image != null else Vector2i.ONE
	var source_pixels := PackedByteArray()
	if source_image != null:
		var rgba_image := source_image.duplicate() as Image
		if rgba_image.is_compressed() and rgba_image.decompress() != OK:
			return null
		if rgba_image.get_format() != Image.FORMAT_RGBA8:
			rgba_image.convert(Image.FORMAT_RGBA8)
		if rgba_image.get_format() != Image.FORMAT_RGBA8:
			return null
		source_pixels = rgba_image.get_data()
	var mask_size := mask.get_size()
	var mask_pixels := mask.get_data()
	var output := PackedByteArray()
	output.resize(mask_size.x * mask_size.y * 4)
	var tint := source.albedo_color
	for pixel_index in mask_size.x * mask_size.y:
		var out_index := pixel_index * 4
		var mask_amount := float(mask_pixels[pixel_index]) / 255.0
		if mask_amount > 0.0:
			var sample_x := int(pixel_index % mask_size.x)
			var sample_y := int(pixel_index / mask_size.x)
			var source_x := mini(source_size.x - 1, int(float(sample_x) * float(source_size.x) / float(mask_size.x)))
			var source_y := mini(source_size.y - 1, int(float(sample_y) * float(source_size.y) / float(mask_size.y)))
			var source_index := (source_y * source_size.x + source_x) * 4
			var source_r := float(source_pixels[source_index]) / 255.0 if source_image != null else 1.0
			var source_g := float(source_pixels[source_index + 1]) / 255.0 if source_image != null else 1.0
			var source_b := float(source_pixels[source_index + 2]) / 255.0 if source_image != null else 1.0
			output[out_index] = clampi(roundi(source_r * tint.r * mask_amount * 255.0), 0, 255)
			output[out_index + 1] = clampi(roundi(source_g * tint.g * mask_amount * 255.0), 0, 255)
			output[out_index + 2] = clampi(roundi(source_b * tint.b * mask_amount * 255.0), 0, 255)
		output[out_index + 3] = 255
	var composed_image := Image.create_from_data(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8, output)
	if composed_image == null or composed_image.is_empty():
		return null
	composed_image.generate_mipmaps()
	var result := ImageTexture.create_from_image(composed_image)
	_composed_textures[key] = result
	return result


static func _structural_mask_image() -> Image:
	if _structural_mask != null:
		return _structural_mask
	var size := MASK_SIZE
	var appearance: Dictionary = Appearance.DATA.film_structure
	var wing: Dictionary = Geometry.DATA.wing
	var span := float(wing.span)
	var chord := float(wing.chord)
	var centers: Array = appearance.rib_centres_m
	var widths: Array = appearance.rib_widths_m
	if centers.is_empty() or centers.size() != widths.size():
		return null
	var rib_ranges: Array[Vector2] = []
	var false_ranges: Array[Vector2] = []
	for index in centers.size():
		var center := float(centers[index])
		var half_width := float(widths[index]) * 0.5
		rib_ranges.append(Vector2(maxf(0.0, center - half_width), center + half_width))
		if index > 0:
			var midpoint := (center + float(centers[index - 1])) * 0.5
			var false_half := float(appearance.false_rib_width_m) * 0.5
			false_ranges.append(Vector2(midpoint - false_half, midpoint + false_half))
	var secondary: Array = appearance.secondary_spar_fraction
	var main: Array = appearance.main_spar_fraction
	var leading := float(appearance.leading_edge_fraction)
	var trailing := float(appearance.trailing_sheet_front_fraction)
	var span_support := PackedByteArray()
	var false_support := PackedByteArray()
	var chord_bay := PackedInt32Array()
	span_support.resize(size)
	false_support.resize(size)
	span_support.fill(0)
	false_support.fill(0)
	chord_bay.resize(size)
	chord_bay.fill(-1)
	var last_rib_outboard := rib_ranges[-1].y
	var left_u := Finish.uv(Vector3(-span * 0.5, 0.0, 0.0), "wing").x
	var right_u := Finish.uv(Vector3(span * 0.5, 0.0, 0.0), "wing").x
	var leading_v := Finish.uv(Vector3(0.0, 0.0, 0.0), "wing").y
	var trailing_v := Finish.uv(Vector3(0.0, 0.0, chord), "wing").y
	for column in size:
		var u := (float(column) + 0.5) / float(size)
		var normalized_span := clampf((u - left_u) / maxf(right_u - left_u, 0.000001), 0.0, 1.0)
		var span_x := (normalized_span - 0.5) * span
		var absolute_span := absf(span_x)
		var rib := false
		var false_rib := false
		for support: Vector2 in rib_ranges:
			if absolute_span >= support.x and absolute_span <= support.y:
				rib = true
				break
		for support: Vector2 in false_ranges:
			if absolute_span >= support.x and absolute_span <= support.y:
				false_rib = true
				break
		span_support[column] = 1 if rib or absolute_span > last_rib_outboard else 0
		false_support[column] = 1 if false_rib else 0
	for row in size:
		var v := (float(row) + 0.5) / float(size)
		var fraction := (v - leading_v) / maxf(trailing_v - leading_v, 0.000001)
		if fraction > leading and fraction < float(secondary[0]):
			chord_bay[row] = 0
		elif fraction > float(secondary[1]) and fraction < float(main[0]):
			chord_bay[row] = 1
		elif fraction > float(main[1]) and fraction < trailing:
			chord_bay[row] = 2
	var mask_pixels := PackedByteArray()
	mask_pixels.resize(size * size)
	mask_pixels.fill(0)
	for row in size:
		var bay := chord_bay[row]
		if bay < 0:
			continue
		for column in size:
			if span_support[column] != 0 or (bay == 0 and false_support[column] != 0):
				continue
			mask_pixels[row * size + column] = 255
	_structural_mask = Image.create_from_data(size, size, false, Image.FORMAT_L8, mask_pixels)
	return _structural_mask


func _zone_map(raw_zones: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (raw_zones is Array):
		_warnings.append("lighting profile zones are malformed")
		return result
	for zone_value: Variant in raw_zones:
		if not (zone_value is Dictionary):
			continue
		var id := str(zone_value.get("id", ""))
		if id in STRIP_ZONE_IDS:
			result[id] = zone_value
	return result


func _result() -> Dictionary:
	return {"ok": true, "errors": [], "warnings": _warnings.duplicate(), "targets": _bindings.size()}


static func _bounded_number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)


static func _surface_index(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)) and floorf(float(value)) == float(value):
		return int(value)
	return -1


static func _supports_uv1_transform(material: StandardMaterial3D) -> bool:
	return not material.uv1_triplanar and not material.uv1_world_triplanar \
		and material.uv1_scale.is_equal_approx(Vector3.ONE) \
		and material.uv1_offset.is_equal_approx(Vector3.ZERO)


static func _mipped_image_bytes(width: int, height: int, bytes_per_pixel: int) -> int:
	var total := 0
	var current_width := width
	var current_height := height
	while true:
		total += current_width * current_height * bytes_per_pixel
		if current_width == 1 and current_height == 1:
			break
		current_width = maxi(1, int(current_width / 2))
		current_height = maxi(1, int(current_height / 2))
	return total
