extends RefCounted
## Explicit source/package association for an independently authored installation. This records
## a workflow declaration, never proof of human action, source authenticity or physical accuracy.
const R := preload("res://workshop/creator/result.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Source := preload("res://workshop/creator/inspected_source.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const FORMAT := "openrc-source-installation v1"
const MODE := "independent_estimated"
const NAMESPACE := "openrc_clearview"
const KEYS := ["format","mode","source_sha256","report_state","report_sha256","airframe_package","power_package"]
const REQUIRED := "Choose an estimated OpenRC configuration for this model and review its retained values."
const STALE := "The model or configuration changed. Review the configuration choice again."
const INVALID := "The saved configuration choice is invalid."
## Saved-aircraft (Home/published) flight. Unsaved test flights follow the ordinary Creator gate.
const FLIGHT_UNAVAILABLE := "Flight for ClearView models is not numerically qualified yet. You can edit and save this draft."
## Shown once the configuration is confirmed: physics come only from the OpenRC packages.
const EXPERIMENTAL := "Test flights use this estimated OpenRC configuration, not the ClearView flight model. They are experimental."

static func required(source: Source) -> bool:
	return source != null and source.is_admitted() and source.has_asset_metadata(NAMESPACE)

static func make(source: Source,context: Dictionary,airframe: String,power: String) -> Dictionary:
	if not required(source):
		return {}
	return {format = FORMAT,mode = MODE,source_sha256 = source.sha256(),
		report_state = "unavailable" if context.is_empty() else "available",
		report_sha256 = "" if context.is_empty() else Observations.digest(context),
		airframe_package = airframe,power_package = power}

static func validate(value: Variant,context: Dictionary,airframe: String,power: String) -> Dictionary:
	if not value is Dictionary or value.size() != KEYS.size():
		return _invalid()
	for key: Variant in value:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or str(key) not in KEYS:
			return _invalid()
	for key: String in KEYS:
		if typeof(value[key]) != TYPE_STRING or value[key].length() > 128:
			return _invalid()
	if value.format != FORMAT or value.mode != MODE or not Bytes.is_sha256(value.source_sha256) \
			or value.airframe_package != airframe or value.power_package != power:
		return _invalid()
	if context.is_empty():
		if value.report_state != "unavailable" or not value.report_sha256.is_empty():
			return _invalid()
	else:
		var checked := Observations.validate(context)
		if not checked.ok or value.report_state != "available" or value.source_sha256 != context.visual_sha256 \
				or not Bytes.is_sha256(value.report_sha256) or value.report_sha256 != Observations.digest(context):
			return _invalid()
	return R.ok(value.duplicate(true))

## Called at the source/candidate join, including when a source tag has been removed from a
## different GLB. Ordinary v1 candidates retain the existing ordinary-source pairing behavior.
static func check_pair(summary: Dictionary,source: Source) -> Dictionary:
	if not summary.has("source_installation"):
		return R.fail(R.UNSUPPORTED_CAPABILITY,REQUIRED,"source_installation","import") if required(source) else R.ok()
	var identities: Variant = summary.get("identities")
	var context: Variant = summary.get("source_observations",{})
	if not identities is Dictionary or not context is Dictionary \
			or typeof(identities.get("airframe_package")) != TYPE_STRING or typeof(identities.get("power_package")) != TYPE_STRING:
		return _invalid()
	var checked := validate(summary.source_installation,context,identities.airframe_package,identities.power_package)
	if not checked.ok:
		return checked
	if source == null or checked.value.source_sha256 != source.sha256():
		return R.fail(R.IDENTITY_MISMATCH,STALE,"source_installation","import")
	return R.ok()

static func _invalid() -> Dictionary:
	return R.fail(R.RECORD_INVALID,INVALID,"source_installation","import")
