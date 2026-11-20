extends RefCounted
## Donor configurations for imported ClearView models the estimated Creator packages cannot represent
## (import closeout packet 6). A donor is a stock catalog aircraft whose exact, validated physics record
## flies unchanged; the imported model supplies only the appearance, fitted to the donor's span. It is
## always a labelled, different configuration, never the ClearView flight model, and never publishable.
const R := preload("res://workshop/creator/result.gd")
const Setup := preload("setup.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Placement := preload("res://workshop/creator/placement.gd")

## Elevon flying wings: the stock MoonRunner X99 (Skywalker X8: tailless, elevons, electric pusher).
const FLYING_WING_DONOR := "moonrunner-x99"
const FLYING_WING_SPAN_M := 2.1
const CONFIRM_TITLE := "Fly this flying wing?"
const CONFIRM_BUTTON := "Fly with the X8 physics"
const SCALE_NOTE := "The model is %s m across and is shown at %s %% of its size."
const FLYING_WING := "This flying wing flies with the stock Skywalker X8 (MoonRunner X99) physics, shown with this model's appearance fitted to its %s m span. It is not the ClearView flight model."


## Last resort for any other model the estimated configuration cannot fly (an autogyro, an airship, a
## tail-sitter, a multirotor, or an estimate the compiler refuses): the stock Ugly Stick electric 6S
## high-wing trainer. Airborne start only.
const TRAINER_DONOR := "stik-electric-6s"
const TRAINER_SPAN_M := 1.52
const TRAINER_TITLE := "Fly with trainer physics?"
const TRAINER_BUTTON := "Fly with the trainer physics"
const TRAINER := "The estimated OpenRC configuration cannot fly this model: %s\n\nIt can fly with the stock Ugly Stick electric trainer physics instead, shown with this model's appearance fitted to its %s m span. It is not the ClearView flight model."
const DONORS := [FLYING_WING_DONOR, TRAINER_DONOR]
## A slender body with no usable wing (an airship such as the Hindenburg) flies on OpenRC's own RC blimp
## physics instead of the trainer: the route id names the blimp activity, not a catalog aircraft.
const AIRSHIP_DONOR := "airship"
## Widest of width and height against length, below which a fallback model is treated as an airship.
const AIRSHIP_SLENDERNESS := 0.35
const AIRSHIP_TITLE := "Fly as a blimp?"
const AIRSHIP_BUTTON := "Fly with the blimp physics"
const AIRSHIP := "The estimated OpenRC configuration cannot fly this model: %s\n\nIts slender body is an airship, so it can fly with OpenRC's RC blimp physics instead, shown with this model's appearance fitted to the blimp's length. It is not the ClearView flight model."


## {donor_id, placement, source_span_m, flown_span_m, message} for a model a donor can fly, or a refusal.
## Elevon flying wings get the X8; with `fallback`, any other aeroplane model gets the trainer.
static func propose(source: InspectedSource, fallback := false) -> Dictionary:
	if not Setup.Installation.required(source):
		return R.fail(R.SOURCE_UNSUPPORTED, "Automatic setup is only available for converted ClearView models.", "source", "import")
	if Setup.is_helicopter(source):
		return R.fail(R.UNSUPPORTED_CAPABILITY, Setup.HELICOPTER, "source", "import")
	var points: Dictionary = Setup._points(source)
	if not points.ok:
		return points
	if not points.mixed_controls and not fallback:
		return R.fail(R.UNSUPPORTED_CAPABILITY, "This model has no donor configuration; use the automatic setup.", "source", "import")
	# A named rotor (an autogyro) is not an airship, however slender its fuselage.
	if fallback and not points.mixed_controls and not bool(points.get("rotor_found", false)) and is_airship(points.value):
		# The blimp scene fits the appearance to its own envelope; no wing placement is needed.
		return R.ok({donor_id = AIRSHIP_DONOR, placement = {}, source_span_m = _width(points.value),
			flown_span_m = 0.0, message = AIRSHIP})
	var donor_id := FLYING_WING_DONOR if points.mixed_controls else TRAINER_DONOR
	var donor_span := FLYING_WING_SPAN_M if points.mixed_controls else TRAINER_SPAN_M
	var edge: Dictionary = Setup.leading_edge(points.value)
	var span := 0.0
	var datum: Array = [0.0, 0.0, 0.0]
	if edge.ok:
		span = 2.0 * float(edge.value.half_span_m)
		datum = edge.value.datum
		# On the trainer, the larger of wingspan and length is fitted: an airship's tail fins or a long
		# fuselage must not be shown many times larger than the aircraft that flies.
		if fallback and donor_id == TRAINER_DONOR:
			span = maxf(span, _width(points.value))
	elif fallback:
		# No readable wing (an airship, a multirotor): the model's widest extent stands in for the span
		# and its ClearView origin (the reference point the author placed) for the leading edge.
		span = _width(points.value)
	else:
		return edge
	if not is_finite(span) or span < Setup.MIN_HALF_SPAN_M:
		return R.fail(R.DATUM_UNRESOLVED, Setup.UNAVAILABLE, "placement/datum", Placement.STEP)
	var placement := {nose_axis = Setup.NOSE_AXIS, up_axis = Setup.UP_AXIS,
		unit_scale = float(Placement.UNITS[Setup.UNITS]) * donor_span / span, datum = datum}
	if not Placement.resolve(placement).ok:
		return R.fail(R.DATUM_UNRESOLVED, Setup.UNAVAILABLE, "placement/datum", Placement.STEP)
	return R.ok({donor_id = donor_id, placement = placement, source_span_m = span,
		flown_span_m = donor_span, message = FLYING_WING if donor_id == FLYING_WING_DONOR else TRAINER})


## True for a slender body: its length (ClearView X) is long against both its width (Z) and height (Y).
static func is_airship(triangles: PackedFloat64Array) -> bool:
	var low := Vector3(INF, INF, INF)
	var high := -low
	for index: int in range(0, triangles.size() - 2, 3):
		var point := Vector3(triangles[index], triangles[index + 1], triangles[index + 2])
		low = low.min(point)
		high = high.max(point)
	var size := high - low
	return is_finite(size.x) and size.x > 0.0 and maxf(size.y, size.z) < AIRSHIP_SLENDERNESS * size.x


## The larger horizontal extent (ClearView X length or Z width) of the triangle points, in source metres.
static func _width(triangles: PackedFloat64Array) -> float:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for index: int in range(0, triangles.size() - 2, 3):
		low = Vector2(minf(low.x, triangles[index]), minf(low.y, triangles[index + 2]))
		high = Vector2(maxf(high.x, triangles[index]), maxf(high.y, triangles[index + 2]))
	return maxf(high.x - low.x, high.y - low.y) if is_finite(low.x) else 0.0
