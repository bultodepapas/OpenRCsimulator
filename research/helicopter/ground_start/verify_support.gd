## Reproducible geometry and static skid-support evidence for HELI-20.
## Layout clearances are model bounds, not a real-world safety certification.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const RotorcraftData := preload("res://physics/rotorcraft_data.gd")
const GroundStart := preload("res://physics/rotorcraft/ground_start.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Math3D := preload("res://physics/math3d.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const SceneryModels := preload("res://scenery/models.gd")
const SceneryPrefabs := preload("res://scenery/prefabs.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const FlightlineBarrier := preload("res://render/flightline_barrier.gd")

const FIELD_PATH := "res://data/fields/default.json"
const AIRCRAFT_PATH := "res://data/aircraft/xcell_60_research.json"
const SCENERY_PATH := "res://data/scenery/default.json"
const LIGHTS_PATH := "res://data/fields/lights.json"
const RESULT_MARKER := "HELI_GROUND_SUPPORT_RESULT_JSON:"
const ERROR_MARKER := "HELI_GROUND_SUPPORT_ERROR_JSON:"


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--parse-only"):
		print("HELI_GROUND_SUPPORT_PARSE_OK")
		quit(0)
		return
	call_deferred("_run")


func _run() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from(FIELD_PATH)
	if not bool(loaded_field.get("ok", false)):
		_emit_error("default field failed validation: %s" % str(loaded_field.get("errors", [])))
		return
	var loaded_aircraft: Dictionary = RotorcraftData.load_file(AIRCRAFT_PATH)
	if not bool(loaded_aircraft.get("ok", false)):
		_emit_error("research trainer failed validation: %s" % str(loaded_aircraft.get("errors", [])))
		return
	var field: Dictionary = loaded_field.field
	var aircraft: Dictionary = loaded_aircraft
	var resolved: Dictionary = GroundStart.resolve(field, aircraft)
	if not bool(resolved.get("ok", false)):
		_emit_error("static pad solve failed: %s" % str(resolved.get("reason", "unknown reason")))
		return
	var scenery_result: Dictionary = SceneryLoader.load_from(SCENERY_PATH, field)
	if not bool(scenery_result.get("ok", false)):
		_emit_error("default scenery failed validation: %s" % str(scenery_result.get("errors", [])))
		return
	var lights_result: Dictionary = FieldLights.load_from(LIGHTS_PATH)
	if not bool(lights_result.get("ok", false)):
		_emit_error("default light data failed validation: %s" % str(lights_result.get("errors", [])))
		return
	var surface_result: Dictionary = GroundSurfaces.load_table()
	if not bool(surface_result.get("ok", false)):
		_emit_error("ground surface table failed validation: %s" % str(surface_result.get("errors", [])))
		return
	var report: Dictionary = _build_report(field, aircraft, resolved, scenery_result.scenery,
		lights_result.lights, surface_result.table)
	if not _report_is_finite(report):
		_emit_error("report contains a non-finite numeric value")
		return
	var output_text: String = JSON.stringify(report, "  ", true, true) + "\n"
	var output_path: String = _output_path()
	if not output_path.is_empty():
		var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if output_file == null:
			_emit_error("cannot write output file '%s' (error %d)" % [output_path, FileAccess.get_open_error()])
			return
		output_file.store_string(output_text)
		output_file.close()
	print(RESULT_MARKER + JSON.stringify({"ok": true, "output": output_path, "sha256": _sha256_text(output_text)}))
	quit(0)


func _build_report(field: Dictionary, aircraft: Dictionary, resolved: Dictionary,
		scenery: Dictionary, lights: Dictionary, surface_table: Dictionary) -> Dictionary:
	var pad: Dictionary = resolved.pad
	var state: PackedFloat64Array = resolved.state
	var pad_surface: Dictionary = _by_id(field.get("surfaces", []), str(pad.get("surface_id", "")))
	var runway: Dictionary = _by_id(field.get("surfaces", []), str(field.get("runway", "")))
	var pilot_station: Dictionary = _by_type(field.get("flight_cues", []), "pilot_station")
	var barrier: Dictionary = _by_type(field.get("flight_cues", []), "flightline_barrier")
	var actual_geometry: Dictionary = GroundStart._actual_envelope_radius(aircraft.context, aircraft.skids)
	var margin: float = float(pad.get("clearance_margin", 0.0))
	var actual_radius: float = float(resolved.actual_envelope_radius_m)
	var authored_radius: float = float(resolved.authored_envelope_radius_m)
	var actual_with_margin: float = actual_radius + margin
	var authored_with_margin: float = authored_radius + margin
	var pad_north: float = float(pad.north)
	var pad_east: float = float(pad.east)
	var runway_gap: float = _rect_edge_distance(pad_north, pad_east,
		float(runway.center_north), float(runway.center_east),
		float(runway.width_north_south) * 0.5, float(runway.length_east_west) * 0.5)
	var pad_runway_edge_gap: float = _rect_gap(
		pad_north - float(pad_surface.width_north_south) * 0.5,
		pad_north + float(pad_surface.width_north_south) * 0.5,
		float(runway.center_north) - float(runway.width_north_south) * 0.5,
		float(runway.center_north) + float(runway.width_north_south) * 0.5)
	var pad_runway_east_gap: float = _rect_gap(
		pad_east - float(pad_surface.length_east_west) * 0.5,
		pad_east + float(pad_surface.length_east_west) * 0.5,
		float(runway.center_east) - float(runway.length_east_west) * 0.5,
		float(runway.center_east) + float(runway.length_east_west) * 0.5)
	var pilot_gap: float = _rect_edge_distance(pad_north, pad_east,
		float(pilot_station.north), float(pilot_station.east),
		float(pilot_station.depth) * 0.5, float(pilot_station.width) * 0.5)
	var barrier_result: Dictionary = _nearest_barrier_post(pad_north, pad_east, barrier)
	var nearest_planes: Dictionary = _nearest_parked_aircraft(pad_north, pad_east, scenery)
	var nearest_prop: Dictionary = _nearest_scenery_instance(pad_north, pad_east, scenery)
	var nearest_light: Dictionary = _nearest_light_installation(pad_north, pad_east, lights)
	var nearest_keepout: Dictionary = _nearest_pad_keepout(pad_north, pad_east, pad)
	var support: Dictionary = _support_report(aircraft, resolved, surface_table)
	var pad_record_raw: Dictionary = _raw_quantity_group(FIELD_PATH, "rotorcraft_pad",
		["north", "east", "heading", "clearance_margin"])
	var rotor_envelope_raw: Dictionary = _raw_rotor_envelope(FIELD_PATH, str(aircraft.id))
	var source_quantities: Dictionary = _aircraft_quantities(aircraft.raw)
	var source_hashes: Dictionary = _source_hashes(scenery)
	var clearances: Array[Dictionary] = [
		_clearance_record("runway", runway_gap, actual_with_margin, authored_with_margin,
			"Distance from pad CG to the axis-aligned runway rectangle; rectangle from validated field surface."),
		_clearance_record("flightline_barrier_nearest_post", float(barrier_result.edge_distance_m),
			actual_with_margin, authored_with_margin,
			"Horizontal distance to the nearest rendered post footprint; posts are 0.08 m square."),
		_clearance_record("pilot_station_footprint", pilot_gap, actual_with_margin, authored_with_margin,
			"Distance from pad CG to the validated 1.5 m east by 1.2 m north station footprint."),
		_clearance_record("nearest_parked_aircraft_mesh_bound",
			float(nearest_planes.by_conservative_mesh_clearance.edge_distance_lower_bound_m),
			actual_with_margin, authored_with_margin,
			"Conservative point-to-circle lower bound from the baked mesh's horizontal half-diagonal."),
		_clearance_record("nearest_scenery_instance_proxy", float(nearest_prop.edge_distance_lower_bound_m),
			actual_with_margin, authored_with_margin,
			"Conservative point-to-circle lower bound from the prefab catalog horizontal half-diagonal."),
		_clearance_record("nearest_field_light_installation", float(nearest_light.edge_distance_m),
			actual_with_margin, authored_with_margin,
			"Point-to-circle lower bound using the light installation's authored collision-radius proxy."),
		_clearance_record("nearest_authored_pad_keepout", float(nearest_keepout.edge_distance_m),
			actual_with_margin, authored_with_margin,
			"Distance to the nearest axis-aligned estimated keepout rectangle in rotorcraft_pad."),
	]
	return {
		"format": "openrc-heli-ground-support-evidence-v1",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"generator": "research/helicopter/ground_start/verify_support.gd",
		"runtime": Engine.get_version_info().get("string", "unknown"),
		"reproduction": "Godot 4.7.2 --headless --path app --audio-driver Dummy --script research/helicopter/ground_start/verify_support.gd -- --out=<repository-root>/docs/research/helicopter/HELI-20/ground-support.json",
		"scope": "Static default-field pad geometry and zero-drive four-skid equilibrium snapshot. Geometry inputs are estimated visual/layout models; this is not a real-world separation standard or flight certification.",
		"inputs_sha256": source_hashes,
		"references": [
			"docs/plans/helicopter.md §14.2–§14.3",
			"docs/research/helicopter/HELI-16/ground-3d-audit-2026-10-14.md",
		],
		"candidate": {
			"field_id": str(field.get("id", "")),
			"aircraft_id": str(aircraft.id),
			"pad_id": str(pad.get("id", "")),
			"north_m": pad_north,
			"east_m": pad_east,
			"heading_rad": float(pad.heading),
			"heading_deg": rad_to_deg(float(pad.heading)),
			"heading_description": "NED nose east",
			"rotorpad_material": str(pad.get("material", "")),
			"pad_footprint_m": {
				"width_north_south": float(pad_surface.width_north_south),
				"length_east_west": float(pad_surface.length_east_west),
				"north_min": pad_north - float(pad_surface.width_north_south) * 0.5,
				"north_max": pad_north + float(pad_surface.width_north_south) * 0.5,
				"east_min": pad_east - float(pad_surface.length_east_west) * 0.5,
				"east_max": pad_east + float(pad_surface.length_east_west) * 0.5,
				"placement_kind": "estimated",
			},
			"clearance_margin_m": margin,
			"authored_geometry_quantities": pad_record_raw,
			"runway": {
				"north_bounds_m": [float(runway.center_north) - float(runway.width_north_south) * 0.5,
					float(runway.center_north) + float(runway.width_north_south) * 0.5],
				"east_bounds_m": [float(runway.center_east) - float(runway.length_east_west) * 0.5,
					float(runway.center_east) + float(runway.length_east_west) * 0.5],
				"pad_surface_edge_gap_m": _hypot(pad_runway_edge_gap, pad_runway_east_gap),
				"pad_north_edge_gap_m": pad_runway_edge_gap,
				"interpretation": "The 6 m pad ends at N=9 m, where the runway begins; the physical rectangles share an edge. The radial aircraft envelope plus margin remains inside the south side of the runway boundary.",
			},
		},
		"aircraft_envelope": {
			"actual_bound_m": actual_radius,
			"authored_conservative_radius_m": authored_radius,
			"clearance_margin_m": margin,
			"actual_bound_plus_margin_m": actual_with_margin,
			"authored_radius_plus_margin_m": authored_with_margin,
			"main_disc_reach_m": float(actual_geometry.main_disc_reach_m),
			"tail_disc_reach_m": float(actual_geometry.tail_disc_reach_m),
			"skid_reach_m": float(actual_geometry.skid_reach_m),
			"authored_envelope_quantity": rotor_envelope_raw,
			"actual_bound_method": "GroundStart._actual_envelope_radius: main hub vector norm plus main radius, tail hub offset norm plus tail radius, and maximum skid-arm norm; take maximum.",
			"basis": "Derived from the validated aircraft data, not measured clearance geometry.",
		},
		"clearances": clearances,
		"nearest_obstacles": {
			"barrier_post": barrier_result,
			"parked_aircraft_by_mesh_bound": nearest_planes.by_conservative_mesh_clearance,
			"parked_aircraft_by_center": nearest_planes.by_center_distance,
			"scenery_instance": nearest_prop,
			"field_light_installation": nearest_light,
			"authored_pad_keepout": nearest_keepout,
			"pilot_station": {
				"id": str(pilot_station.get("id", "")),
				"north_m": float(pilot_station.north),
				"east_m": float(pilot_station.east),
				"width_east_west_m": float(pilot_station.width),
				"depth_north_south_m": float(pilot_station.depth),
				"pad_cg_to_footprint_m": pilot_gap,
				"kind": "estimated visual field cue",
			},
		},
		"support": support,
		"model_evidence": {
			"source_quantities": source_quantities,
			"rotorpad_friction_factor": _raw_quantity_value("res://data/ground/surface_friction.json",
				["surfaces", "rotorpad", "friction_factor"]),
			"effective_skid_mu": float(aircraft.skids.friction) * float(surface_table.rotorpad.friction_factor),
			"contact_normals_and_residuals": "derived by GroundStart.resolve from estimated mass, CG, support arms, stiffness, gravity and flat-pad material.",
			"measured_ground_support_or_friction_data": [],
			"measurement_status": "No ground reaction, spring/damper or skid-friction measurement is represented in this artifact; solver reactions and torque bound are model-derived.",
		},
		"limitations": [
			"Candidate coordinates, field-cue dimensions, pad margin and visual keepouts are simulator layout estimates, not surveyed positions or safety standards.",
			"Scenery bounds are conservative catalog/mesh proxies. Collision-disabled scenery remains visual-only in the application.",
			"The support solve is qualified only for this zero-relief horizontal rotorpad; this evidence does not qualify slope parking.",
			"The reported yaw value is a Coulomb torque upper bound from the solved normal reactions. It does not itself prove drift-free spool-up, which is a separate session acceptance test.",
		],
	}


func _support_report(aircraft: Dictionary, resolved: Dictionary, surface_table: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = resolved.state
	var normals: PackedFloat64Array = resolved.normal_forces_n
	var compressions: PackedFloat64Array = resolved.compressions_m
	var points: PackedFloat64Array = aircraft.skids.points_body_frd_m
	var attitude: PackedFloat64Array = state.slice(6, 10)
	var friction_mu: float = float(aircraft.skids.friction) * float(surface_table.rotorpad.friction_factor)
	var per_skid_yaw: Array[Dictionary] = []
	var yaw_capacity_nm: float = 0.0
	for index: int in 4:
		var arm_body: PackedFloat64Array = points.slice(index * 3, index * 3 + 3)
		var arm_world: PackedFloat64Array = Math3D.q_rotate(attitude, arm_body)
		var horizontal_radius: float = _hypot(float(arm_world[0]), float(arm_world[1]))
		var torque: float = friction_mu * float(normals[index]) * horizontal_radius
		yaw_capacity_nm += torque
		per_skid_yaw.append({
			"index": index,
			"arm_body_frd_m": _packed_array(arm_body),
			"horizontal_lever_m": horizontal_radius,
			"normal_force_n": float(normals[index]),
			"friction_force_upper_bound_n": friction_mu * float(normals[index]),
			"yaw_torque_contribution_upper_bound_nm": torque,
		})
	var force_residual: PackedFloat64Array = resolved.force_residual_n
	var moment_residual: PackedFloat64Array = resolved.moment_residual_nm
	return {
		"solver": "GroundStart.resolve on validated default field and xcell-60-research data",
		"contact_count": int(resolved.contact_count),
		"state_float64": _packed_array(state),
		"state_order": ["north_m", "east_m", "down_m", "velocity_n_m_s", "velocity_e_m_s", "velocity_down_m_s",
			"quaternion_w", "quaternion_x", "quaternion_y", "quaternion_z", "body_rate_p_rad_s", "body_rate_q_rad_s", "body_rate_r_rad_s"],
		"state_north_m": float(state[0]),
		"state_east_m": float(state[1]),
		"state_down_m": float(state[2]),
		"state_cg_height_above_datum_m": -float(state[2]),
		"normal_force_n_by_skid": _packed_array(normals),
		"compression_m_by_skid": _packed_array(compressions),
		"support_points_body_frd_m": _triple_array(points),
		"force_residual_world_ned_n": _packed_array(force_residual),
		"moment_residual_world_ned_nm": _packed_array(moment_residual),
		"force_residual_magnitude_n": float(resolved.force_residual_magnitude_n),
		"moment_residual_magnitude_nm": float(resolved.moment_residual_magnitude_nm),
		"relative_force_residual": float(resolved.relative_force_residual),
		"relative_moment_residual": float(resolved.relative_moment_residual),
		"newton_iterations": int(resolved.iterations),
		"tangential_support": str(resolved.tangential_support),
		"yaw_capacity_upper_bound": {
			"value_nm": yaw_capacity_nm,
			"formula": "sum_i(mu_skid * normal_force_i * horizontal_skid_lever_i)",
			"effective_mu": friction_mu,
			"per_skid": per_skid_yaw,
			"basis": "Derived model bound; estimated skid friction and estimated rotorpad friction factor, with solver-derived normal reactions.",
		}
	}


func _nearest_barrier_post(pad_north: float, pad_east: float, cue: Dictionary) -> Dictionary:
	var post_size := Vector3.ZERO
	for part: Dictionary in FlightlineBarrier.parts(cue):
		if str(part.get("id", "")).contains(":post:"):
			post_size = part.size
			break
	if post_size == Vector3.ZERO:
		return {"edge_distance_m": INF, "error": "barrier has no rendered posts"}
	var best_distance := INF
	var best_east := 0.0
	var best_index := -1
	var posts: PackedVector3Array = FlightlineBarrier.post_positions(cue)
	for index: int in posts.size():
		var center_east: float = float(cue.east) + posts[index].x
		var d_north: float = maxf(absf(pad_north - float(cue.north)) - post_size.z * 0.5, 0.0)
		var d_east: float = maxf(absf(pad_east - center_east) - post_size.x * 0.5, 0.0)
		var distance: float = _hypot(d_north, d_east)
		if distance < best_distance:
			best_distance = distance
			best_east = center_east
			best_index = index
	return {
		"id": str(cue.get("id", "flightline_barrier")),
		"type": "rendered_post_footprint",
		"north_m": float(cue.north),
		"east_m": best_east,
		"post_index": best_index,
		"post_width_east_west_m": post_size.x,
		"post_depth_north_south_m": post_size.z,
		"gap_width_m": float(cue.gap_width),
		"edge_distance_m": best_distance,
		"kind": "estimated visual field cue geometry",
	}


func _nearest_parked_aircraft(pad_north: float, pad_east: float, scenery: Dictionary) -> Dictionary:
	var best_by_edge: Dictionary = {}
	var best_edge := INF
	var best_by_center: Dictionary = {}
	var best_center := INF
	for group: Dictionary in scenery.get("groups", []):
		if str(group.get("type", "")) != "fleet":
			continue
		for placement: Dictionary in group.get("placements", []):
			var aircraft_id: String = str(placement.get("aircraft", ""))
			var model_id := _fleet_model_id(aircraft_id)
			if model_id.is_empty():
				continue
			var arrays: Dictionary = SceneryModels.arrays(model_id)
			if arrays.is_empty():
				continue
			var size: Vector3 = arrays.size
			var proxy_radius: float = _hypot(size.x, size.z) * 0.5
			var center_distance: float = _hypot(float(placement.north) - pad_north,
				float(placement.east) - pad_east)
			var edge_distance: float = maxf(center_distance - proxy_radius, 0.0)
			var candidate: Dictionary = {
					"group_id": str(group.get("id", "fleet")),
					"aircraft_id": aircraft_id,
					"model_id": model_id,
					"north_m": float(placement.north),
					"east_m": float(placement.east),
					"heading_deg": float(placement.heading),
					"baked_mesh_size_m": [size.x, size.y, size.z],
					"horizontal_circumscribed_radius_m": proxy_radius,
					"center_distance_m": center_distance,
					"edge_distance_lower_bound_m": edge_distance,
					"basis": "Conservative circle around baked horizontal mesh bounds; orientation independent.",
				}
			if edge_distance < best_edge:
				best_edge = edge_distance
				best_by_edge = candidate
			if center_distance < best_center:
				best_center = center_distance
				best_by_center = candidate
	return {"by_conservative_mesh_clearance": best_by_edge, "by_center_distance": best_by_center}


func _nearest_scenery_instance(pad_north: float, pad_east: float, scenery: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_edge := INF
	for group: Dictionary in scenery.get("groups", []):
		if str(group.get("type", "")) != "instances":
			continue
		for placement: Dictionary in group.get("placements", []):
			var prefab: String = str(placement.get("prefab", ""))
			var spec: Dictionary = SceneryPrefabs.CATALOG.get(prefab, {})
			if spec.is_empty():
				spec = SceneryModels.CATALOG.get(prefab, {})
			if spec.is_empty():
				continue
			var size: Vector3 = spec.get("size", Vector3.ONE)
			var proxy_radius: float = _hypot(size.x, size.z) * 0.5
			var center_distance: float = _hypot(float(placement.north) - pad_north,
				float(placement.east) - pad_east)
			var edge_distance: float = maxf(center_distance - proxy_radius, 0.0)
			if edge_distance < best_edge:
				best_edge = edge_distance
				best = {
					"group_id": str(group.get("id", "")),
					"prefab": prefab,
					"north_m": float(placement.north),
					"east_m": float(placement.east),
					"heading_deg": float(placement.heading),
					"catalog_size_m": [size.x, size.y, size.z],
					"horizontal_circumscribed_radius_m": proxy_radius,
					"center_distance_m": center_distance,
					"edge_distance_lower_bound_m": edge_distance,
					"catalog_kind": str(spec.get("kind", "unknown")),
					"catalog_source": str(spec.get("source", "")),
					"basis": "Conservative circle from prefab catalog horizontal footprint; the catalog describes a visual mesh envelope, not collision geometry.",
				}
	return best


func _nearest_light_installation(pad_north: float, pad_east: float, lights: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_edge := INF
	for installation: Dictionary in lights.get("installations", []):
		if not installation.has_all(["north", "east"]):
			continue
		var radius: float = float(installation.get("collision_radius", 0.0))
		var center_distance: float = _hypot(float(installation.north) - pad_north,
			float(installation.east) - pad_east)
		var edge_distance: float = maxf(center_distance - radius, 0.0)
		if edge_distance < best_edge:
			best_edge = edge_distance
			best = {
				"id": str(installation.get("id", "")),
				"type": str(installation.get("type", "")),
				"north_m": float(installation.north),
				"east_m": float(installation.east),
				"collision_radius_proxy_m": radius,
				"center_distance_m": center_distance,
				"edge_distance_m": edge_distance,
				"basis": "Authored light-installation collision radius; the dimensions remain estimates.",
			}
	return best


func _nearest_pad_keepout(pad_north: float, pad_east: float, pad: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for keepout: Dictionary in pad.get("keepouts", []):
		var distance: float = _rect_edge_distance(pad_north, pad_east,
			float(keepout.north), float(keepout.east),
			float(keepout.width_north_south) * 0.5, float(keepout.length_east_west) * 0.5)
		if distance < best_distance:
			best_distance = distance
			best = {
				"id": str(keepout.get("id", "")),
				"north_m": float(keepout.north),
				"east_m": float(keepout.east),
				"length_east_west_m": float(keepout.length_east_west),
				"width_north_south_m": float(keepout.width_north_south),
				"edge_distance_m": distance,
				"source": str(keepout.get("source", "")),
			}
	return best


func _clearance_record(obstacle: String, edge_distance: float, actual_with_margin: float,
		authored_with_margin: float, method: String) -> Dictionary:
	return {
		"obstacle": obstacle,
		"edge_distance_from_pad_cg_m": edge_distance,
		"actual_rotorcraft_bound_plus_margin_clearance_m": edge_distance - actual_with_margin,
		"authored_radius_plus_margin_clearance_m": edge_distance - authored_with_margin,
		"method": method,
	}


func _aircraft_quantities(raw: Dictionary) -> Dictionary:
	return {
		"body.mass_kg": _quantity_node(raw, "body", "mass_kg"),
		"gravity_m_s2": _quantity_node(raw, "", "gravity_m_s2"),
		"main_rotor.hub_position_body_frd_m": _quantity_node(raw, "main_rotor", "hub_position_body_frd_m"),
		"main_rotor.rotor_radius_m": _quantity_node(raw, "main_rotor", "rotor_radius_m"),
		"tail_rotor.hub_distance_aft_m": _quantity_node(raw, "tail_rotor", "hub_distance_aft_m"),
		"tail_rotor.hub_height_above_cg_m": _quantity_node(raw, "tail_rotor", "hub_height_above_cg_m"),
		"tail_rotor.tail_rotor_radius_m": _quantity_node(raw, "tail_rotor", "tail_rotor_radius_m"),
		"skids.spring_n_m": _quantity_node(raw, "skids", "spring_n_m"),
		"skids.damping_n_s_m": _quantity_node(raw, "skids", "damping_n_s_m"),
		"skids.friction": _quantity_node(raw, "skids", "friction"),
		"skids.points_body_frd_m": _quantity_node(raw, "skids", "points_body_frd_m"),
	}


func _quantity_node(raw: Dictionary, module: String, key: String) -> Dictionary:
	var source: Variant = raw.get(key, {}) if module.is_empty() else raw.get(module, {}).get(key, {})
	return source.duplicate(true) if source is Dictionary else {}


func _raw_quantity_group(path: String, group_name: String, keys: Array[String]) -> Dictionary:
	var root: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not root is Dictionary:
		return {}
	var group: Dictionary = root.get(group_name, {})
	var result := {}
	for key: String in keys:
		var node: Variant = group.get(key, {})
		if node is Dictionary:
			result[key] = node.duplicate(true)
	return result


func _raw_rotor_envelope(path: String, aircraft_id: String) -> Dictionary:
	var root: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not root is Dictionary:
		return {}
	for envelope: Variant in root.get("rotorcraft_pad", {}).get("aircraft_envelopes", []):
		if envelope is Dictionary and str(envelope.get("aircraft_id", "")) == aircraft_id:
			return envelope.duplicate(true)
	return {}


func _raw_quantity_value(path: String, keys: Array[String]) -> Dictionary:
	var node: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	for key: String in keys:
		if not node is Dictionary:
			return {}
		node = node.get(key, {})
	return node.duplicate(true) if node is Dictionary else {}


func _source_hashes(scenery: Dictionary) -> Dictionary:
	var paths: Array[String] = [
		FIELD_PATH,
		AIRCRAFT_PATH,
		"res://data/ground/surface_friction.json",
		SCENERY_PATH,
		LIGHTS_PATH,
		"res://physics/rotorcraft/ground_start.gd",
		"res://physics/rotorcraft/skid_contact.gd",
		"res://physics/ground_surfaces.gd",
		"res://scenery/prefabs.gd",
		"res://scenery/models.gd",
		"res://render/flightline_barrier.gd",
		"res://render/pilot_station.gd",
	]
	for group: Dictionary in scenery.get("groups", []):
		if str(group.get("type", "")) != "fleet":
			continue
		for placement: Dictionary in group.get("placements", []):
			var model_id := _fleet_model_id(str(placement.get("aircraft", "")))
			if not model_id.is_empty():
				paths.append("res://data/scenery/models/%s.json" % model_id)
	var result := {}
	for path: String in paths:
		result[path.trim_prefix("res://")] = _sha256_file(path)
	return result


func _fleet_model_id(aircraft_id: String) -> String:
	for model_id: String in SceneryModels.FLEET:
		if str(SceneryModels.FLEET[model_id]) == aircraft_id:
			return model_id
	return ""


func _by_id(items: Array, wanted: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item.get("id", "")) == wanted:
			return item
	return {}


func _by_type(items: Array, wanted: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item.get("type", "")) == wanted:
			return item
	return {}


func _rect_edge_distance(north: float, east: float, center_north: float, center_east: float,
		half_north: float, half_east: float) -> float:
	var d_north: float = maxf(absf(north - center_north) - half_north, 0.0)
	var d_east: float = maxf(absf(east - center_east) - half_east, 0.0)
	return _hypot(d_north, d_east)


func _rect_gap(a0: float, a1: float, b0: float, b1: float) -> float:
	if a1 < b0:
		return b0 - a1
	if b1 < a0:
		return a0 - b1
	return 0.0


func _packed_array(values: PackedFloat64Array) -> Array[float]:
	var output: Array[float] = []
	for value: float in values:
		output.append(value)
	return output


func _triple_array(values: PackedFloat64Array) -> Array[Array]:
	var output: Array[Array] = []
	for index: int in range(0, values.size(), 3):
		output.append([float(values[index]), float(values[index + 1]), float(values[index + 2])])
	return output


func _hypot(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


func _sha256_file(path: String) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return "missing"
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK or hash.update(bytes) != OK:
		return "hash-error"
	return hash.finish().hex_encode()


func _sha256_text(value: String) -> String:
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK or hash.update(value.to_utf8_buffer()) != OK:
		return "hash-error"
	return hash.finish().hex_encode()


func _report_is_finite(value: Variant) -> bool:
	if value is float or value is int:
		return is_finite(float(value))
	if value is Dictionary:
		for child: Variant in value.values():
			if not _report_is_finite(child):
				return false
	elif value is Array:
		for child: Variant in value:
			if not _report_is_finite(child):
				return false
	return true


func _output_path() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			return argument.trim_prefix("--out=").strip_edges().trim_prefix('"').trim_suffix('"')
	return ""


func _emit_error(message: String) -> void:
	printerr(ERROR_MARKER + JSON.stringify({"ok": false, "error": message}))
	quit(1)
