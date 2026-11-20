extends SceneTree
## IAQ-00: the Creator import sequence over a local Phoenix installation, opt-in and never in CI.
##
## For every fixed-wing and glider `.mod`: convert, apply the decoded placement and bindings, "Set up for
## flight" (PhoenixSetup + Authoring.apply_clearview_setup), compile, and assess the airborne and hand-launch
## starts exactly as the Workshop does. Writes `<out>/corpus.json` (one row per model) and, with
## `--export-trials`, `<out>/trials/<model>.json` compiled records (`{aircraft_id, record}`) that
## `research/flight-test/flight_test.gd --record=` flies. Stock content stays in the output folder only:
## never commit it.
##
## Run (repository root):
##   <godot> --headless --path app --audio-driver Dummy --script "$PWD/research/aircraft-creator/phoenix/creator_corpus.gd" -- \
##       --install="<PhoenixRC folder>" --out=<new folder> [--only=<name part>] [--export-trials]

const Converter := preload("res://workshop/creator/phoenix/converter.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const PhoenixSetup := preload("res://workshop/creator/phoenix/setup.gd")
const PhoenixPhysics := preload("res://workshop/creator/phoenix/physics.gd")
const Packages := preload("res://workshop/creator/packages.gd")
const CreatorTrial := preload("res://workshop/creator/trial.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

const FORMAT := "openrc-phoenix-creator-corpus-v1"
const CLASSES := ["fixedWing", "gliders"]


func _initialize() -> void:
	var install := ""
	var out := ""
	var only := ""
	var export_trials := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--install="):
			install = arg.substr(10)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7).to_lower()
		elif arg == "--export-trials":
			export_trials = true
	var aircraft := install.path_join("resources/objects/aircraft")
	if install.is_empty() or out.is_empty() or not DirAccess.dir_exists_absolute(aircraft):
		push_error("usage: -- --install=<PhoenixRC folder> --out=<new folder> [--only=<name part>] [--export-trials]")
		quit(2)
		return
	if DirAccess.dir_exists_absolute(out) and not (DirAccess.get_files_at(out).is_empty() and DirAccess.get_directories_at(out).is_empty()):
		push_error("--out must be a new or empty folder")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out.path_join("trials") if export_trials else out)
	var mods: Array = []
	for family: String in CLASSES:
		_walk(aircraft.path_join(family), mods)
	mods.sort()
	var field: Dictionary = FieldLoader.load_from().field
	var rows: Array = []
	for path: String in mods:
		var label := path.get_file().get_basename()
		if not only.is_empty() and not label.to_lower().contains(only):
			continue
		var row := _assess(path, field, out.path_join("trials").path_join(label + ".json") if export_trials else "")
		row.model = label
		row.family = _family(path, aircraft)
		rows.append(row)
		print("%-28s %s" % [label, _line(row)])
	var totals := {models = rows.size(), compiled = 0, airborne = 0, hand_launch = 0, runway = 0, derived = 0}
	for row: Dictionary in rows:
		totals.compiled += 1 if row.get("compiled", false) else 0
		totals.airborne += 1 if row.get("airborne", false) else 0
		totals.hand_launch += 1 if row.get("hand_launch", false) else 0
		totals.runway += 1 if row.get("runway", false) else 0
		totals.derived += 1 if row.get("derived_physics", false) else 0
	var report := {format = FORMAT, engine = Engine.get_version_info().string, totals = totals, models = rows}
	var file := FileAccess.open(out.path_join("corpus.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false) + "\n")
	file.close()
	print("TOTAL models %d compiled %d airborne %d hand %d runway %d derived %d" % [totals.models, totals.compiled, totals.airborne,
		totals.hand_launch, totals.runway, totals.derived])
	quit(0)


func _assess(path: String, field: Dictionary, trial_path: String) -> Dictionary:
	var row := {}
	var result: Dictionary = Converter.convert(path)
	if not result.ok:
		row.stage = "convert"
		row.reason = _message(result)
		return row
	var doc := Authoring.new()
	doc.set_source(result.value.source)
	var placement: Dictionary = result.value.placement
	doc.set_axis("nose_axis", placement.nose_axis)
	doc.set_axis("up_axis", placement.up_axis)
	doc.set_units(placement.units)
	if not (placement.datum as Array).is_empty():
		doc.set_datum(placement.datum)
	if not (result.value.bindings as Dictionary).is_empty():
		var bound: Dictionary = VisualBuilder.validate_bindings(result.value.source, result.value.bindings)
		if bound.ok:
			doc.set_bindings(bound.value)
	var setup: Dictionary = PhoenixSetup.propose(result.value.source, Authoring.span_domain())
	if not setup.ok:
		row.stage = "setup"
		row.reason = _message(setup)
		return row
	var applied: Dictionary = doc.apply_clearview_setup(setup.value, doc.revision)
	if not applied.ok:
		row.stage = "apply"
		row.reason = _message(applied)
		return row
	row.scaled = bool(setup.value.scaled)
	row.planform_fitted = bool(setup.value.planform_fitted)
	var definition: Dictionary = doc.definition()
	row.derived_physics = PhoenixPhysics.is_derived(str(definition.get("power_package", "")))
	var summary: Dictionary = doc.summary()
	for key: String in ["mass_kg", "static_margin", "stall_speed_mps", "level_speed_mps", "thrust_to_weight", "wing_loading_kg_m2"]:
		if summary.has(key) and is_finite(float(summary[key])):
			row[key] = snappedf(float(summary[key]), 0.001)
	row.span_m = snappedf(float(applied.value.get("flown_span_m", 0.0)), 0.001)
	var built: Dictionary = doc.compile()
	row.compiled = built.ok
	if not built.ok:
		row.stage = "compile"
		row.reason = _message(built)
		return row
	var payload := {creator_candidate = built.value, creator_source = result.value.source, creator_placement = doc.placement(),
		creator_name = path.get_file().get_basename(), start_choice = "airborne", creator_bindings = doc.bindings(),
		creator_appearance = doc.appearance()}
	var trial: Dictionary = CreatorTrial.freeze(payload)
	if not trial.get("ok", false):
		row.stage = "freeze"
		row.reason = str(trial.get("errors", ["trial refused"])[0])
		return row
	row.gear = str(doc.landing_gear().get("layout", ""))
	for start: Array in [["airborne", Session.START_AIRBORNE], ["hand_launch", Session.START_HAND_LAUNCH], ["runway", Session.START_RUNWAY]]:
		var checked: Dictionary = CreatorTrial.check_start(trial, field, Weather.defaults(), start[1])
		row[start[0]] = checked.get("ok", false) and checked.get("available", false)
		if not row[start[0]]:
			row[start[0] + "_reason"] = str(checked.get("reason", "")).substr(0, 200)
	row.stage = "flyable"
	if not trial_path.is_empty():
		var file := FileAccess.open(trial_path, FileAccess.WRITE)
		# The exact compiled record: the card reloads it through the trial's own record loader.
		file.store_string(JSON.stringify({aircraft_id = str(trial.identity.aircraft_id),
			record = (trial.raw_bytes as PackedByteArray).get_string_from_utf8()}) + "\n")
		file.close()
	return row


func _family(path: String, aircraft: String) -> String:
	return path.substr(aircraft.length() + 1).split("/")[0]


func _message(result: Dictionary) -> String:
	var diagnostics: Array = result.get("diagnostics", [])
	if diagnostics.is_empty():
		return ""
	var first: Dictionary = diagnostics[0]
	var message := str(first.get("message", ""))
	var arguments: Array = first.get("arguments", [])
	return (message % arguments) if message.count("%s") == arguments.size() and not arguments.is_empty() else message


func _line(row: Dictionary) -> String:
	if row.get("stage") != "flyable":
		return "%s: %s" % [row.get("stage"), str(row.get("reason", "")).substr(0, 100)]
	return "mass %s kg  Vs %s  Vlevel %s  T/W %s  air %s hand %s gear %s runway %s %s" % [row.get("mass_kg", "?"),
		row.get("stall_speed_mps", "?"), row.get("level_speed_mps", "?"), row.get("thrust_to_weight", "?"), row.get("airborne"),
		row.get("hand_launch"), row.get("gear", ""), row.get("runway"), str(row.get("runway_reason", "")).substr(0, 120)]


func _walk(dir: String, out: Array) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for name: String in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(name), out)
	for name: String in DirAccess.get_files_at(dir):
		if name.get_extension().to_lower() == "mod":
			out.append(dir.path_join(name))
