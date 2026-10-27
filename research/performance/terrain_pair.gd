## GP-19g: bitwise parity and paired timing of the ground terrain sampler, an explicit prior ground_terrain.gd
## (reference, extracted outside app/) versus the working tree (candidate). Tables interleave the default field's
## surface table with ±0, NaN, invalid and edited-in-place variants to exercise the validity memo. Research-only.
## See research/performance/README.md#terrain-sampler-gp-19g.
extends SceneTree

const Candidate := preload("res://physics/ground_terrain.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Session := preload("res://sim/flight_session.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ref_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): ref_path = arg.trim_prefix("--reference=")
	var reference := GDScript.new()
	reference.source_code = FileAccess.get_file_as_string(ref_path)
	if reference.source_code.is_empty() or reference.reload() != OK:
		push_error("reference script failed to load: " + ref_path)
		quit(2)
		return
	var session: Node = Session.new()
	if not session.set_field(FieldLoader.load_from().field):
		push_error("field setup failed")
		quit(2)
		return
	var field: PackedFloat64Array = session.ground_surfaces
	session.free()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var signed_zero := field.duplicate()
	signed_zero[0] = 0.0
	var negative_zero := signed_zero.duplicate()
	negative_zero[0] = -0.0
	var with_nan := field.duplicate()
	with_nan[4] = NAN
	var bad_friction := field.duplicate()
	bad_friction[4] = 2.0
	var bad_outside := field.duplicate()
	bad_outside[field.size() - 6] = 0.0
	var tables: Array[PackedFloat64Array] = [field, signed_zero, negative_zero, with_nan, bad_friction, bad_outside,
		PackedFloat64Array(), PackedFloat64Array([1.0, 2.0, 3.0]), field.duplicate()]
	var rows: int = field.size() / Candidate.SURFACE_STRIDE
	var relief := PackedFloat64Array()
	for row: int in rows: relief.append(0.001 * (row + 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	var edited := field.duplicate()
	var mismatches := 0
	var calls := 0
	for step: int in 40000:
		if step % 89 == 0:
			edited[rng.randi_range(0, edited.size() - 1)] += rng.randf_range(-2.0, 2.0)
		var table: PackedFloat64Array = edited if step % 4 == 0 else tables[rng.randi_range(0, tables.size() - 1)]
		var n: float = rng.randf_range(-200.0, 200.0) if step % 7 else [NAN, INF, -0.0, 0.0][step % 4]
		var e: float = rng.randf_range(-200.0, 200.0)
		var with_lake: Dictionary = lake if step % 3 == 0 else {}
		var a := var_to_bytes([reference.is_valid_surface_table(table), reference.max_height(table),
			reference.sample(n, e, table, with_lake), reference.sample_profiled(n, e, table, relief, with_lake)])
		var b := var_to_bytes([Candidate.is_valid_surface_table(table), Candidate.max_height(table),
			Candidate.sample(n, e, table, with_lake), Candidate.sample_profiled(n, e, table, relief, with_lake)])
		calls += 1
		if a != b:
			mismatches += 1
			if mismatches <= 5: printerr("MISMATCH step=%d n=%s e=%s" % [step, n, e])
		if reference.is_valid_surface_table(table):
			var c := var_to_bytes([reference.sample_validated(n, e, table, with_lake), reference._sample_microrelief_validated(n, e, table)])
			var d := var_to_bytes([Candidate.sample_validated(n, e, table, with_lake), Candidate._sample_microrelief_validated(n, e, table)])
			calls += 1
			if c != d: mismatches += 1
	# A dense sweep across the runway, mown and rough edges of the default field.
	for i: int in 200000:
		var n: float = rng.randf_range(-120.0, 120.0)
		var e: float = rng.randf_range(-250.0, 250.0)
		if var_to_bytes(reference._sample_microrelief_validated(n, e, field)) != var_to_bytes(Candidate._sample_microrelief_validated(n, e, field)):
			mismatches += 1
		calls += 1
	print("TERRAIN_PARITY calls=%d mismatches=%d" % [calls, mismatches])
	var ref_us := PackedFloat64Array()
	var cand_us := PackedFloat64Array()
	for round: int in 12:
		for order: int in 2:
			var use_ref: bool = (round + order) % 2 == 0
			var started := Time.get_ticks_usec()
			for i: int in 20000:
				var n: float = 15.0 + i * 1e-5
				if use_ref:
					reference.is_valid_surface_table(field)
					reference.sample_validated(n, -47.0, field, lake)
				else:
					Candidate.is_valid_surface_table(field)
					Candidate.sample_validated(n, -47.0, field, lake)
			var us := float(Time.get_ticks_usec() - started) / 20000.0
			if use_ref: ref_us.append(us)
			else: cand_us.append(us)
	ref_us.sort()
	cand_us.sort()
	print("TERRAIN_TIMING table check + runway sample: reference_median_us=%.3f candidate_median_us=%.3f ratio=%.3f"
		% [ref_us[6], cand_us[6], cand_us[6] / ref_us[6]])
	quit(1 if mismatches else 0)
