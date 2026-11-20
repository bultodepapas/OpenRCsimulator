extends RefCounted
## Automatic flight setup for a converted Phoenix aeroplane (AC-PX / IAQ-03).
##
## The proposal comes from the decoded definition stored in the admitted GLB's `openrc_phoenix` receipt
## (`creator_setup`). It has the shape `Authoring.apply_clearview_setup` consumes, so the declared
## configuration, size classes, balancing and guards are the ones ClearView models already use. When the
## receipt carries a Phoenix physics block (`physics.gd`), the chosen size class's packages are replaced
## by ones derived from the model's own weight, balance, airfoil polars and propeller. Like ClearView, a model outside the estimated packages' span range flies as an
## explicitly labelled scaled version, and a wing planform outside the package's taper/aspect range is
## replaced by the nearest supported shape and reported; the source values stay in the receipt.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const PhoenixPhysics := preload("res://workshop/creator/phoenix/physics.gd")

const RULE := "phoenix-decoded-v1"
const STEP := "import"
const NOSE_AXIS := "+z"
const UP_AXIS := "+y"
const FIT_MARGIN := 0.02
const TAPER_RANGE := [0.6, 1.0]
const ASPECT_RANGE := [4.0, 7.0]
const DIHEDRAL_RANGE := [0.0, 8.0]
const MAX_LAYOUT_FIELDS := 64
const PHYSICS_FORMAT := "openrc-phoenix-physics-v1"
## Control throws of the estimated packages (degrees, both packages share them).
const THROW_RANGES := {"controls/aileron_deg": [5.0, 30.0], "controls/elevator_deg": [5.0, 30.0], "controls/rudder_deg": [5.0, 35.0]}

const NOT_PHOENIX := "Automatic setup is only available for converted Phoenix aeroplanes."
const UNAVAILABLE := "The Phoenix flight data of this model is incomplete. Set the wing and tail in Aircraft layout."
const CONFIRM_FRAME := "Orientation, metres and the wing leading edge come from the Phoenix model. Its weight, balance, airfoils, wing, tail, propeller and control throws set the flight configuration; anything else is a labelled estimate."
const THROWS_FITTED := "Some Phoenix control throws are outside the estimated configuration's range and are limited to it."
const PLANFORM_FITTED := "The Phoenix wing (taper %s, aspect ratio %s) is outside the estimated configuration's range, so its chords are adjusted to the nearest supported shape."


## `value`: {placement, units, rule, estimated_datum, half_span_m, source_span_m, flown_span_m, scaled,
## owns_scale, propeller_found, pusher, range_index, span_range, root_chord_m, tip_chord_m, dihedral_deg,
## planform_fitted, source_taper, source_aspect, throws_fitted, layout}.
static func propose(source: InspectedSource, span_range: Array = []) -> Dictionary:
	if Installation.provider(source) != "phoenix":
		return R.fail(R.SOURCE_UNSUPPORTED, NOT_PHOENIX, "source", STEP)
	var data := creator_setup(source)
	if data.is_empty():
		return R.fail(R.SOURCE_INVALID, UNAVAILABLE, "wing/span", STEP)
	var half_span := float(data.half_span_m)
	var span := 2.0 * half_span
	var ranges: Array = span_range if not span_range.is_empty() and span_range[0] is Array else [span_range]
	var range_index := -1
	var distance := INF
	for index: int in ranges.size():
		var candidate: Array = ranges[index]
		if candidate.size() != 2 or not float(candidate[0]) > 0.0 or not float(candidate[1]) > float(candidate[0]):
			continue
		var off := maxf(float(candidate[0]) - span, span - float(candidate[1]))
		if off < distance:
			distance = off
			range_index = index
	var chosen: Array = ranges[range_index] if range_index >= 0 else []
	var flown := span
	if not chosen.is_empty() and (span < float(chosen[0]) or span > float(chosen[1])):
		flown = clampf(span, float(chosen[0]) * (1.0 + FIT_MARGIN), float(chosen[1]) * (1.0 - FIT_MARGIN))
	var scale := flown / span
	var scaled := absf(flown - span) > 1e-9
	var placement := {nose_axis = NOSE_AXIS, up_axis = UP_AXIS, unit_scale = scale, datum = (data.datum as Array).duplicate()}
	if not Placement.resolve(placement).ok:
		return R.fail(R.DATUM_UNRESOLVED, UNAVAILABLE, "placement/datum", Placement.STEP)
	var fitted := fit_planform(span, float(data.root_chord_m), float(data.tip_chord_m))
	var dihedral := clampf(float(data.dihedral_deg), float(DIHEDRAL_RANGE[0]), float(DIHEDRAL_RANGE[1]))
	var layout: Dictionary = (data.layout as Dictionary).duplicate()
	var throws_fitted := false
	for path: String in THROW_RANGES:
		if layout.has(path):
			var limited := clampf(float(layout[path]), float(THROW_RANGES[path][0]), float(THROW_RANGES[path][1]))
			throws_fitted = throws_fitted or limited != float(layout[path])
			layout[path] = limited
	return R.ok({placement = placement, units = "" if scaled else "m", rule = RULE, estimated_datum = false,
		half_span_m = half_span, source_span_m = span, flown_span_m = flown, scaled = scaled, owns_scale = true,
		propeller_found = bool(data.propeller_found), pusher = bool(data.pusher), range_index = range_index,
		span_range = chosen.duplicate(), root_chord_m = fitted.root, tip_chord_m = fitted.tip, dihedral_deg = dihedral,
		planform_fitted = fitted.changed, source_taper = fitted.taper, source_aspect = fitted.aspect,
		throws_fitted = throws_fitted, biplane = bool(data.biplane), layout = layout, physics = data.physics})


## Chords (metres, source size) inside the package's taper and aspect-ratio ranges at the same span.
## `changed` reports whether the decoded planform had to move.
static func fit_planform(span: float, root: float, tip: float) -> Dictionary:
	var taper := tip / root if root > 0.0 else 1.0
	var mean := 0.5 * (root + tip)
	var aspect := span / mean if mean > 0.0 else float(ASPECT_RANGE[0])
	var fitted_taper := clampf(taper, float(TAPER_RANGE[0]) * 1.005, float(TAPER_RANGE[1]))
	var fitted_aspect := clampf(aspect, float(ASPECT_RANGE[0]) * 1.01, float(ASPECT_RANGE[1]) * 0.99)
	var fitted_mean := span / fitted_aspect
	var fitted_root := 2.0 * fitted_mean / (1.0 + fitted_taper)
	var fitted_tip := fitted_taper * fitted_root
	var changed := absf(fitted_root - root) > 1e-6 * maxf(1.0, root) or absf(fitted_tip - tip) > 1e-6 * maxf(1.0, tip)
	return {root = fitted_root if changed else root, tip = fitted_tip if changed else tip, changed = changed,
		taper = taper, aspect = aspect}


## The validated `creator_setup` of the admitted GLB's Phoenix receipt, or {} when absent or malformed.
static func creator_setup(source: InspectedSource) -> Dictionary:
	if source == null or not source.is_admitted() or source.format() != InspectedSource.FORMAT_GLB:
		return {}
	var bytes := source.source_bytes()
	if bytes.size() < 20:
		return {}
	var length := bytes.decode_u32(12)
	if length > Limits.GLB_JSON_BYTES or 20 + length > bytes.size():
		return {}
	var document: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not document is Dictionary or not document.get("asset") is Dictionary:
		return {}
	var extras: Variant = document.asset.get("extras")
	if not extras is Dictionary or not extras.get("openrc_phoenix") is Dictionary:
		return {}
	var data: Variant = extras.openrc_phoenix.get("creator_setup")
	if not data is Dictionary:
		return {}
	for key: String in ["half_span_m", "root_chord_m", "tip_chord_m", "dihedral_deg"]:
		if not _finite(data.get(key)):
			return {}
	if not (float(data.half_span_m) > 0.0 and float(data.root_chord_m) > 0.0 and float(data.tip_chord_m) > 0.0):
		return {}
	var datum: Variant = data.get("datum")
	if not datum is Array or (datum as Array).size() != 3 or not (datum as Array).all(_finite):
		return {}
	var layout: Variant = data.get("layout", {})
	if not layout is Dictionary or (layout as Dictionary).size() > MAX_LAYOUT_FIELDS:
		return {}
	var clean_layout := {}
	for path: Variant in layout:
		if typeof(path) != TYPE_STRING or not _finite(layout[path]):
			return {}
		clean_layout[str(path)] = float(layout[path])
	return {half_span_m = float(data.half_span_m), root_chord_m = float(data.root_chord_m),
		tip_chord_m = float(data.tip_chord_m), dihedral_deg = float(data.dihedral_deg),
		datum = [float(datum[0]), float(datum[1]), float(datum[2])], layout = clean_layout,
		propeller_found = bool(data.get("propeller_found", false)), pusher = bool(data.get("pusher", false)),
		biplane = bool(data.get("biplane", false)), physics = _physics(data.get("physics"))}


## The receipt's physics block when it has the expected format, only finite numbers and plausible required
## facts (`PhoenixPhysics.valid_block`); {} otherwise.
static func _physics(value: Variant) -> Dictionary:
	if not value is Dictionary or (value as Dictionary).get("format") != PHYSICS_FORMAT or not _finite_tree(value, 0) \
			or not PhoenixPhysics.valid_block(value):
		return {}
	return (value as Dictionary).duplicate(true)


static func _finite_tree(value: Variant, depth: int) -> bool:
	if depth > 4:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if typeof(key) != TYPE_STRING or not _finite_tree(value[key], depth + 1):
				return false
		return true
	if value is Array:
		return false
	if value is String or value is bool:
		return true
	return _finite(value)


static func _finite(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
