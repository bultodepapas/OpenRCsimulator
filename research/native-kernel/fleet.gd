## NK-3 fleet run: try the app loader (app/sim/native_stage.gd) on every flyable fixed-wing catalog aircraft and on
## the Stik's weather and contact options. Each case runs twice from identical setups, once untouched and once after
## NativeStage.prepare()/install(); session_probe's fingerprint (600 warm-up + 2,400 sampled ticks, trim and runway
## where supported) must be equal. Every non-Stik aircraft and every unported option must be refused with a reason.
## Needs the installed library: run.py --script fleet.gd --app-library.
extends "trajectory.gd"

const NativeStage := preload("res://sim/native_stage.gd")
const WindConfig := preload("res://physics/wind_config.gd")


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["warmup", "samples"])


func _checks() -> void:
	_report.format = "openrc-nk3-fleet v1"
	_report.fleet = []
	_report.library = NativeStage.library_status()
	if not _report.library.ok:
		_failures.append("app native library unavailable: " + str(_report.library.reason))
		return
	var warmup: int = int(_options.get("warmup", "600"))
	var samples: int = int(_options.get("samples", "2400"))
	for id: String in Catalog.airplane_flyable_ids():
		for case: String in ["trim", "runway"]:
			if case == "runway" and not Session.runway_aircraft_supported(id):
				continue
			_fleet_case(id, case, "default", {}, true, warmup, samples)
	# Stik options: weather presets (uniform calm-wind atmospheres are ported; wind, gusts, turbulence, a vertical
	# column and spatial fields are not) and soft hull contacts off (ported).
	for preset: Dictionary in WindConfig.presets():
		if preset.id == "calm":
			continue
		_fleet_case(AIRCRAFT, "trim", "weather:" + str(preset.id), preset.config, true, warmup, samples)
	_fleet_case(AIRCRAFT, "runway", "soft_hull_off", {}, false, warmup, samples)


func _fleet_case(id: String, case: String, option: String, weather: Dictionary, soft_hull: bool, warmup: int,
		samples: int) -> void:
	var runs: Array = []
	for attempt: bool in [false, true]:
		var session := _build_session(id, case, true, weather, soft_hull)
		if session == null:
			_failures.append("fleet %s/%s/%s did not start" % [id, case, option])
			return
		session.read_raw = _reader(session, case)
		var stage := NativeStage.new()
		var prepared := {ok = false, reason = "not attempted"}
		var installed := false
		if attempt:
			prepared = stage.prepare(session)
			if prepared.ok:
				installed = stage.install(session).is_valid()
		for index in warmup:
			if not _advance(session):
				break
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		_hash_tick(digest, session)
		var ticks := 0
		for index in samples:
			if not _advance(session):
				break
			_hash_tick(digest, session)
			ticks += 1
		runs.append({prepared = prepared, installed = installed, ticks = ticks, end = _end_record(session),
			fingerprint = digest.finish().hex_encode(), identity = stage.identity_text(),
			stage = str(session.sim.model.stage.get_method())})
		if installed:
			stage.uninstall(session)
		session.free()
	var row := {aircraft = id, case = case, option = option, installed = runs[1].installed,
		reason = str(runs[1].prepared.reason), identity = runs[1].identity, stage_in_use = runs[1].stage,
		ticks = runs[1].ticks, end = runs[1].end, reference_fingerprint = runs[0].fingerprint,
		attempt_fingerprint = runs[1].fingerprint, fingerprint_equal = runs[0].fingerprint == runs[1].fingerprint}
	_report.fleet.append(row)
	_compare("fleet_fingerprint", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if row.fingerprint_equal else 0.0]),
		[id, case, option])
	var supported: bool = id == AIRCRAFT and (option in ["default", "soft_hull_off", "weather:hot-high", "weather:cool-dense"])
	if not supported and (row.installed or row.reason.is_empty()):
		_failures.append("fleet %s/%s/%s: expected a refusal with a reason" % [id, case, option])
	if supported and not row.installed:
		_failures.append("fleet %s/%s/%s: expected the native stage, refused: %s" % [id, case, option, row.reason])
	print("NK3_FLEET %s %s %s installed=%s equal=%s ticks=%d reason=%s" % [id, case, option, row.installed,
		row.fingerprint_equal, row.ticks, row.reason])
