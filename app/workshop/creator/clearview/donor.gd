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


## {donor_id, placement, source_span_m, flown_span_m, message} for a model a donor can fly, or a refusal.
static func propose(source: InspectedSource) -> Dictionary:
	if not Setup.Installation.required(source):
		return R.fail(R.SOURCE_UNSUPPORTED, "Automatic setup is only available for converted ClearView models.", "source", "import")
	if Setup._model_type(source) == Setup.HELICOPTER_TYPE:
		return R.fail(R.UNSUPPORTED_CAPABILITY, Setup.HELICOPTER, "source", "import")
	var points: Dictionary = Setup._points(source)
	if not points.ok:
		return points
	if not points.mixed_controls:
		return R.fail(R.UNSUPPORTED_CAPABILITY, "This model has no donor configuration; use the automatic setup.", "source", "import")
	var edge: Dictionary = Setup.leading_edge(points.value)
	if not edge.ok:
		return edge
	var span := 2.0 * float(edge.value.half_span_m)
	var placement := {nose_axis = Setup.NOSE_AXIS, up_axis = Setup.UP_AXIS,
		unit_scale = float(Placement.UNITS[Setup.UNITS]) * FLYING_WING_SPAN_M / span, datum = edge.value.datum}
	if not Placement.resolve(placement).ok:
		return R.fail(R.DATUM_UNRESOLVED, Setup.UNAVAILABLE, "placement/datum", Placement.STEP)
	return R.ok({donor_id = FLYING_WING_DONOR, placement = placement, source_span_m = span,
		flown_span_m = FLYING_WING_SPAN_M, message = FLYING_WING})
