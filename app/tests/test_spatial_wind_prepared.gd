extends SceneTree

const Field := preload("res://physics/wind_spatial_field.gd")
const FIXTURES := {
	"Windows": "res://tests/fixtures/spatial_wind_boundary_before.json",
	"Linux": "res://tests/fixtures/spatial_wind_boundary_before_linux.json",
}
var _checks := 0
var _failed := 0


func _check(label: String, success: bool) -> void:
	_checks += 1
	if not success:
		_failed += 1
		printerr("FAIL " + label)


func _initialize() -> void:
	var os_name: String = OS.get_name()
	if not FIXTURES.has(os_name):
		printerr("No pre-optimization boundary capture for OS: " + os_name)
		quit(1)
		return
	var fixture_path: String = FIXTURES[os_name]
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	_check("boundary fixture loads", typeof(raw) == TYPE_DICTIONARY)
	if typeof(raw) != TYPE_DICTIONARY:
		quit(1)
		return
	var fixture: Dictionary = raw
	_check("fixture identifies the pre-optimization field", fixture.format == "openrc-spatial-boundary-parity v1"
		and fixture.baseline_field_sha256 == "218908e722fa89347ccdd20423bedac9f0358f970b47661a4ec42cfa1bcf3130")
	_check("boundary matrix is complete", fixture.cases.size() == 4 and fixture.queries.size() == 190)
	var fields: Array = []
	for item: Dictionary in fixture.cases:
		var config: Dictionary = item.config.duplicate(true)
		var built: Dictionary = Field.build(config)
		_check("build " + str(item.id), built.ok)
		if not built.ok:
			quit(1)
			return
		var field: Variant = built.field
		fields.append(field)
		_check("identity " + str(item.id), field.content_hash() == item.content_hash)
		_check("speed envelope " + str(item.id), PackedFloat64Array([field.absolute_speed_bound_mps()]).to_byte_array().hex_encode() == item.bound_bytes_hex)
		var canonical_before: Dictionary = field.configuration()
		# The public configuration and the caller's input must not mutate prepared values.
		config.profile.reference_speed_mps = 13.0
		config.gusts.events.clear()
		var exposed: Dictionary = field.configuration()
		exposed.profile.reference_from_deg = 180.0
		exposed.gusts.events.clear()
		_check("detached configuration " + str(item.id), field.configuration() == canonical_before)
		_check("all expected bytes present " + str(item.id), item.wind_bytes_hex.size() == fixture.queries.size())
	# Interleave different providers and traverse time backwards too. No query may
	# cache a mutable time window or share returned packed storage with a later sample.
	for reverse_order: bool in [false, true]:
		for offset: int in fixture.queries.size():
			var index: int = fixture.queries.size() - 1 - offset if reverse_order else offset
			var query: Dictionary = fixture.queries[index]
			for field_index: int in fields.size():
				var result: Dictionary = fields[field_index].sample_world(PackedFloat64Array(query.position_ned_m), float(query.time_s))
				_check("exact field %d query %d reversed=%s" % [field_index, index, reverse_order], result.ok
					and result.wind_ned_mps.to_byte_array().hex_encode() == fixture.cases[field_index].wind_bytes_hex[index])
				if result.ok:
					result.wind_ned_mps[0] = NAN
	print("prepared spatial wind: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
