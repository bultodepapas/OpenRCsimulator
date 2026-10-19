extends RefCounted
## Read-only technical launch. A bundle never imports into the player library or changes preferences.
const Bundle := preload("res://workshop/bundle.gd")
const Trial := preload("res://workshop/trial.gd")

static func from_args(args: Dictionary) -> Dictionary:
	if not args.has("aircraft-variant"): return {ok = true, requested = false, errors = []}
	for key: String in ["aircraft", "battery", "electric-demo", "experimental-aircraft-data", "scripted"]:
		if args.has(key): return {ok = false, requested = true, errors = ["--aircraft-variant cannot be combined with --%s." % key]}
	var path: Variant = args["aircraft-variant"]
	if typeof(path) != TYPE_STRING or str(path).is_empty():
		return {ok = false, requested = true, errors = ["--aircraft-variant needs a local JSON bundle path."]}
	var read := Bundle.read_file(path)
	if not read.ok: return {ok = false, requested = true, errors = read.errors}
	var frozen := Trial.freeze(read.payload)
	if not frozen.ok: return {ok = false, requested = true, errors = frozen.errors}
	return {ok = true, requested = true, errors = [], base_id = read.payload.base_id, trial = frozen}
