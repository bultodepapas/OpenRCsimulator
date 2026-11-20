extends RefCounted
## Mutable authoring document of one Aircraft Creator session (AC-10).
##
## Holds the admitted source, the placement and every typed field with its raw text. The UI only
## sends intents and reads state: it never infers physics. A required value starts unresolved —
## no numeric zero, assumed unit or hidden default. Invalid text stays visible, never replaces the
## last accepted value, and blocks compilation until corrected.

signal changed

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const Packages := preload("res://workshop/creator/packages.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")

const STEPS: PackedStringArray = ["import", "orient_size", "aircraft_layout", "weight_balance",
	"power_mount", "controls_ground", "paint_skins", "review_test"]
const STEP_TITLES := {
	import = "Import", orient_size = "Orient and size", aircraft_layout = "Aircraft layout",
	weight_balance = "Weight and balance", power_mount = "Power and mount",
	controls_ground = "Controls and ground", paint_skins = "Paint and skins", review_test = "Review and test",
}
const STATUS_NOT_STARTED := "Not started"
const STATUS_IN_PROGRESS := "In progress"
const STATUS_NEEDS_ATTENTION := "Needs attention"
const STATUS_COMPLETE := "Complete"

const SNAPSHOT_FORMAT := "openrc-creator-document v1"
const SOURCE_SNAPSHOT_FORMAT := "openrc-creator-document v2"
const INSTALLATION_SNAPSHOT_FORMAT := "openrc-creator-document v3"
const SERVO_SNAPSHOT_FORMAT := "openrc-creator-document v4"
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const PhoenixPhysics := preload("res://workshop/creator/phoenix/physics.gd")
const PhoenixSetup := preload("res://workshop/creator/phoenix/setup.gd")
const AIRFRAME_PACKAGE := "conventional-trainer-estimated-v1"
const POWER_PACKAGE := "electric-4s-800kv-apc12x6-estimated-v1"
## The same estimated installation as a pusher behind the wing, for models without a propeller (park jets).
const PUSHER_PACKAGE := "electric-4s-800kv-apc12x6-pusher-estimated-v1"
## Realism batch 2026-11-17: size classes of the automatic ClearView setup. Under 1.45 m a model is a foam
## park flyer (9 g servos, 3S 9x6); larger models keep the trainer airframe and 4S power. Models without a
## propeller (jets) get the class's pusher: the 3S 9x6 in a slot, or a fast 4S 1900 kV 6x4.5 standing in for
## a 70 mm ducted fan. The original 4S 12x6 pusher stays installed for drafts saved with it.
const PARKFLYER_AIRFRAME := "conventional-parkflyer-estimated-v1"
const SMALL_POWER := "electric-3s-1250kv-9x6-estimated-v1"
const SMALL_PUSHER := "electric-3s-1250kv-9x6-pusher-estimated-v1"
const JET_PUSHER := "electric-4s-1900kv-6x45-pusher-estimated-v1"
## Jets of LARGE_JET_SPAN_M or more (3-4 kg) get the 6S 90 mm EDF stand-in: the 4S one leaves them under
## the package's minimum thrust-to-weight.
const LARGE_JET_PUSHER := "electric-6s-1200kv-7x5-pusher-estimated-v1"
const LARGE_JET_SPAN_M := 1.9
const AIRFRAME_PACKAGES: PackedStringArray = [AIRFRAME_PACKAGE, PARKFLYER_AIRFRAME]
const POWER_PACKAGES: PackedStringArray = [POWER_PACKAGE, PUSHER_PACKAGE, SMALL_POWER, SMALL_PUSHER, JET_PUSHER, LARGE_JET_PUSHER]
const PUSHER_PACKAGES: PackedStringArray = [PUSHER_PACKAGE, SMALL_PUSHER, JET_PUSHER, LARGE_JET_PUSHER]

## Scalar fields of the definition: path, English label, unit and owning step. Vector components
## use the index as the last path segment. Lengths are metres in the leading-edge frame.
const FIELDS: Array[Dictionary] = [
	{path = "wing/span", label = "Wingspan", unit = "m", step = "aircraft_layout"},
	{path = "wing/root_chord", label = "Wing root chord", unit = "m", step = "aircraft_layout"},
	{path = "wing/tip_chord", label = "Wing tip chord", unit = "m", step = "aircraft_layout"},
	{path = "wing/dihedral_deg", label = "Wing dihedral", unit = "deg", step = "aircraft_layout"},
	{path = "horizontal_tail/span", label = "Tailplane span", unit = "m", step = "aircraft_layout"},
	{path = "horizontal_tail/chord", label = "Tailplane chord", unit = "m", step = "aircraft_layout"},
	{path = "horizontal_tail/position/0", label = "Tailplane leading edge, distance aft", unit = "m", step = "aircraft_layout"},
	{path = "horizontal_tail/position/2", label = "Tailplane height", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/height", label = "Fin height", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/chord", label = "Fin chord", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/position/0", label = "Fin leading edge, distance aft", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/position/2", label = "Fin base height", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/nose_x", label = "Nose, distance aft (negative ahead of the wing)", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/tail_x", label = "Tail end, distance aft", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/width", label = "Fuselage width", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/height", label = "Fuselage height", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/center_z", label = "Fuselage centre height", unit = "m", step = "aircraft_layout"},
	{path = "equipment/battery_position/0", label = "Battery, distance aft", unit = "m", step = "weight_balance"},
	{path = "equipment/battery_position/1", label = "Battery, distance right", unit = "m", step = "weight_balance"},
	{path = "equipment/battery_position/2", label = "Battery height", unit = "m", step = "weight_balance"},
	{path = "equipment/hub_position/0", label = "Propeller hub, distance aft", unit = "m", step = "power_mount"},
	{path = "equipment/hub_position/1", label = "Propeller hub, distance right", unit = "m", step = "power_mount"},
	{path = "equipment/hub_position/2", label = "Propeller hub height", unit = "m", step = "power_mount"},
	{path = "equipment/esc_position/0", label = "Speed controller, distance aft", unit = "m", step = "power_mount"},
	{path = "equipment/esc_position/1", label = "Speed controller, distance right", unit = "m", step = "power_mount"},
	{path = "equipment/esc_position/2", label = "Speed controller height", unit = "m", step = "power_mount"},
	{path = "equipment/thrust_angles_deg/0", label = "Down thrust", unit = "deg", step = "power_mount"},
	{path = "equipment/thrust_angles_deg/1", label = "Right thrust", unit = "deg", step = "power_mount"},
	{path = "battery/initial_soc", label = "Battery charge at start (0 to 1)", unit = "", step = "power_mount"},
	{path = "controls/aileron_deg", label = "Aileron travel", unit = "deg", step = "controls_ground"},
	{path = "controls/elevator_deg", label = "Elevator travel", unit = "deg", step = "controls_ground"},
	{path = "controls/rudder_deg", label = "Rudder travel", unit = "deg", step = "controls_ground"},
	{path = "controls/servo_time_s", label = "Neutral to full command time", unit = "s", step = "controls_ground"},
]
## Vector fields of the definition and their fixed components (the centreline y of a tail is 0).
const _VECTORS := {
	"horizontal_tail/position": [-1, 0.0, -1], "vertical_tail/position": [-1, 0.0, -1],
	"equipment/battery_position": [-1, -1, -1], "equipment/hub_position": [-1, -1, -1],
	"equipment/esc_position": [-1, -1, -1], "equipment/thrust_angles_deg": [-1, -1],
}
const _INVENTORY_KINDS: PackedStringArray = ["estimated", "measured", "manual"]
## Inventory numbers `set_item_raw` accepts, with their English captions (the UI translates them).
const ITEM_KEYS := {"mass": "Mass", "x": "Aft", "y": "Right", "z": "Upward"}
## Field prefix of a diagnostic about rejected inventory text: `inventory_item/<item id>/<key>`.
const ITEM_FIELD_PREFIX := "inventory_item/"

var revision := 0
## Display name. Control characters are dropped: they cannot be stored and are never meant.
var name := "":
	set(value):
		name = clean_text(value)
var _uuid := ""
var _source: InspectedSource
var _placement := Placement.unresolved()
var _units := ""
var _raw := {}
var _values := {}
var _invalid := {}
## Field path -> "estimated" for values the starting-values action supplied and the player has not
## typed or confirmed. Anything the player enters is theirs and is removed from this map.
var _origin := {}
var _source_observations := {}
var _review_observations := {}
var _source_installation := {}
var _installation_proposal := {}
var _servo_integration := ""
var _inventory: Array = []
## The estimated power package; only the ClearView setup chooses the pusher variant.
var _power_package := POWER_PACKAGE
## The estimated airframe package; only the ClearView setup chooses the park-flyer class.
var _airframe_package := AIRFRAME_PACKAGE
## "<item id>/<key>" -> typed inventory text that is not a number (empty included). The item keeps
## its last accepted number only as a stale preview: compilation is refused until it is corrected.
var _item_invalid := {}
var _compiled := {}
var _compiled_revision := -1
## Presentation only: which model parts move with which control, and the paint. Neither changes
## the compiled physics. Shapes are owned by `visual_builder.gd`.
var _bindings := {}
var _appearance := {"mode": "original"}
## Storage identity: the draft this document is saved as, the record it was last saved to (the
## compare-and-swap token for the next save), and the published revision it was opened from or
## last published as (0 = never published).
var draft_id := ""
var saved_record_sha256 := ""
var published_revision := 0
var _saved_fingerprint := ""
static var _number_pattern: RegEx


func _init() -> void:
	_uuid = new_uuid()
	draft_id = new_uuid()


static func new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## Parses a complete number as typed. One decimal comma is accepted. Returns NAN when the whole
## text is not a finite decimal number: no partial parse, exponent overflow or empty text.
static func parse_number(text: String) -> float:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or trimmed.length() > Limits.RAW_NUMBER_CHARACTERS:
		return NAN
	if trimmed.count(",") == 1 and not trimmed.contains("."):
		trimmed = trimmed.replace(",", ".")
	if _number_pattern == null:
		_number_pattern = RegEx.new()
		_number_pattern.compile("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")
	var matched := _number_pattern.search(trimmed)
	if matched == null:
		return NAN
	# The engine logs a warning when it converts an overflowing exponent; refuse it here instead.
	var exponent := matched.get_string(2)
	if exponent.length() > 5 or (not exponent.is_empty() and absi(exponent.substr(1).to_int()) > 300):
		return NAN
	var value := trimmed.to_float()
	return value if is_finite(value) else NAN


static func format_number(value: float) -> String:
	return String.num(value, 4)


# --- Source and placement -------------------------------------------------------------------

func source() -> InspectedSource:
	return _source


func aircraft_uuid() -> String:
	return _uuid


## Adopts a newly admitted source. The placement and the part bindings are reset: axes, units,
## datum and node indices belong to a file. The paint choice is kept.
func set_source(admitted: InspectedSource, observations: Observations.CheckedReport = null) -> void:
	_source_observations = {}
	_source_installation = {}
	if observations != null and observations.matches(admitted):
		_source_observations = observations.context()
	_review_observations = _source_observations.duplicate(true)
	_source = admitted
	_power_package = POWER_PACKAGE
	_airframe_package = AIRFRAME_PACKAGE
	_installation_proposal = Installation.make(_source,_review_observations,_airframe_package,_power_package)
	_placement = Placement.unresolved()
	_units = ""
	_bindings = {}
	_touch()


func placement() -> Dictionary:
	return _placement.duplicate(true)


## References only. No observation is adopted into a physical field in this version.
func source_observations() -> Dictionary:
	return _source_observations.duplicate(true)


## Freshly checked references can be reviewed without migrating a historical document.
func review_source_observations() -> Dictionary:
	return _review_observations.duplicate(true)


func source_installation_proposal() -> Dictionary:
	return _installation_proposal.duplicate(true)


func source_installation() -> Dictionary:
	return _source_installation.duplicate(true) if not needs_source_installation() else {}


func needs_source_installation() -> bool:
	return Installation.required(_source) and (_source_installation.is_empty() or _source_installation != _installation_proposal)


## The declaration is source/package-bound; the revision guards queued UI actions after edits.
## Values/inventory are preserved. The player explicitly reviews those for this source.
func choose_source_installation(expected: Dictionary,expected_revision: int,reviewed: bool) -> Dictionary:
	if Installation.rotorcraft(_source):
		return R.fail(R.UNSUPPORTED_CAPABILITY,Installation.ROTORCRAFT,"source_installation","import")
	if not reviewed or not Installation.required(_source):
		return R.fail(R.UNSUPPORTED_CAPABILITY,Installation.REQUIRED,"source_installation","import")
	if expected_revision != revision or expected != _installation_proposal:
		return R.fail(R.IDENTITY_MISMATCH,Installation.STALE,"source_installation","import")
	var checked := Installation.validate(expected,_review_observations,_airframe_package,_power_package)
	if not checked.ok:
		return checked
	_source_observations = _review_observations.duplicate(true)
	_source_installation = checked.value
	_touch()
	return R.ok()


## One explicit player action for a converted ClearView model: complete what is still unresolved
## from `setup` (ClearView.Setup.propose: frame rule and an estimated leading edge), fill every
## still-empty field with labelled starting estimates, propose the inventory when it is empty and
## declare the independent estimated OpenRC configuration. Nothing the player already set is
## replaced, and no ClearView flight coefficient is read. `expected_revision` guards a stale dialog.
func apply_clearview_setup(setup: Dictionary, expected_revision: int) -> Dictionary:
	if not Installation.required(_source):
		return R.fail(R.UNSUPPORTED_CAPABILITY, "Automatic setup is only available for converted ClearView models.", "source", "import")
	if expected_revision != revision:
		return R.fail(R.IDENTITY_MISMATCH, Installation.STALE, "source_installation", "import")
	var proposed: Variant = setup.get("placement")
	var unit_name := str(setup.get("units", ""))
	if not proposed is Dictionary or not Placement.resolve(proposed).ok or (not unit_name.is_empty() and not Placement.UNITS.has(unit_name)):
		return R.fail(R.DATUM_UNRESOLVED, "The automatic setup is incomplete. Set the orientation, units and datum in Orient and size.", "placement/datum", Placement.STEP)
	var placed := _placement.duplicate(true)
	for which: String in ["nose_axis", "up_axis"]:
		if str(placed.get(which, "")).is_empty():
			placed[which] = proposed[which]
	var units_value := _units
	# A Phoenix setup may resize a model whose metres were pre-filled at import (`owns_scale`); a player
	# who changed the scale or units since import keeps them.
	var owns_scale := float(placed.get("unit_scale", 0.0)) <= 0.0 \
		or (bool(setup.get("owns_scale", false)) and _units == "m" and is_equal_approx(float(placed.unit_scale), 1.0))
	if owns_scale:
		placed["unit_scale"] = float(proposed.unit_scale)
		units_value = unit_name
	if (placed.get("datum", []) as Array).is_empty():
		placed["datum"] = (proposed.datum as Array).duplicate()
	if not Placement.resolve(placed).ok:
		return R.fail(R.FIELD_INVALID, "The existing orientation conflicts with the ClearView frame. Review Orient and size.", "placement/up_axis", Placement.STEP)
	# The setup's size class chooses the airframe and power; a model without a propeller (a jet) gets the
	# class's pusher. Both are chosen before the declaration is made.
	var kept_package := _power_package
	var kept_airframe := _airframe_package
	var kept_proposal: Variant = _installation_proposal
	var classes := setup_classes()
	if classes.is_empty():
		return R.fail(R.DEPENDENCY_MISSING, "Package %s is not installed.", "source_installation", "import", [PARKFLYER_AIRFRAME])
	# A setup proposed without size classes (index -1) keeps the trainer class.
	var class_index := int(setup.get("range_index", -1))
	var size_class: Dictionary = classes[class_index if class_index >= 0 and class_index < classes.size() else classes.size() - 1]
	if needs_source_installation():
		_airframe_package = size_class.airframe
		_power_package = size_class.tractor
		if not bool(setup.get("propeller_found", true)) or bool(setup.get("pusher", false)):
			_power_package = size_class.pusher
			if size_class.has("large_pusher") and float(setup.get("flown_span_m", 0.0)) >= LARGE_JET_SPAN_M:
				_power_package = size_class.large_pusher
		_installation_proposal = Installation.make(_source,_review_observations,_airframe_package,_power_package)
	# A source physics block (decoded Phoenix data) replaces the size class's borrowed values with the
	# model's own; the derived packages depend on the flown size, so they are made per attempt below.
	var physics: Variant = setup.get("physics")
	var source_physics: bool = physics is Dictionary and not (physics as Dictionary).is_empty() and needs_source_installation()
	var base_airframe := _airframe_package
	var base_power := _power_package
	# When this setup chose the size, a model too heavy for its wing (or overpowered) at that size is
	# tried a little larger, up to the package's maximum span: the result stays a labelled scaled
	# configuration. Every attempt starts again from the same untouched document state.
	var before := {placement = _placement.duplicate(true), units = _units, values = _values.duplicate(),
		raw = _raw.duplicate(), origin = _origin.duplicate(), inventory = _inventory.duplicate(true)}
	var source_span := float(setup.get("source_span_m", 0.0))
	var domain: Array = size_class.range if _airframe_package == size_class.airframe else []
	for attempt: int in SETUP_SIZE_ATTEMPTS:
		# A second pass re-derives the power for the mass the fitted equipment actually reaches when it is
		# off the scaled source mass (small replicas cannot always be made that light).
		var flying_mass := NAN
		for mass_pass: int in 2:
			_placement = placed.duplicate(true)
			_units = units_value
			# The measured wing (props, rotors and wheels excluded) sets the span, not the model's box.
			if not _values.has("wing/span") and not _invalid.has("wing/span") and float(setup.get("half_span_m", 0.0)) > 0.0:
				_set_estimate("wing/span", 2.0 * float(setup.half_span_m) * float(placed.unit_scale))
			# The measured planform (chords and dihedral, already inside the package domain) replaces the
			# template's AR 5 rectangle, so wing area, loading and roll stability follow the model.
			for measured: Array in [["wing/root_chord", "root_chord_m", float(placed.unit_scale)],
					["wing/tip_chord", "tip_chord_m", float(placed.unit_scale)], ["wing/dihedral_deg", "dihedral_deg", 1.0]]:
				var number := float(setup.get(measured[1], NAN)) * float(measured[2])
				if is_finite(number) and number >= 0.0 and not _values.has(measured[0]) and not _invalid.has(measured[0]):
					_set_estimate(measured[0], number)
			# Lengths of a source layout are metres at the source size; angles do not scale.
			var layout := {}
			var source_layout: Variant = setup.get("layout", {})
			if source_layout is Dictionary:
				for path: Variant in source_layout:
					var number := float(source_layout[path])
					layout[path] = number if str(path).ends_with("_deg") else number * float(placed.unit_scale)
			if source_physics:
				var flown_scale := float(placed.unit_scale)
				var derived: Dictionary = PhoenixPhysics.derive(physics, base_airframe, base_power, flown_scale, flying_mass)
				# Without derived packages the attempt keeps the base packages and their borrowed mass and balance.
				_airframe_package = derived.get("airframe", base_airframe)
				_power_package = derived.get("power", base_power)
				if not derived.is_empty():
					# A geometrically similar model at another size: mass ∝ s³, positions ∝ s.
					if is_finite(float(physics.get("mass_kg", NAN))):
						layout["mass/total_kg"] = float(physics.mass_kg) * pow(flown_scale, 3)
					if is_finite(float(physics.get("cg_aft_m", NAN))):
						layout["balance/cg_aft_m"] = float(physics.cg_aft_m) * flown_scale
			_fill_estimates(layout)
			if not source_physics or mass_pass == 1 or not layout.has("mass/total_kg"):
				break
			var fitted := float(Compiler.summarize(definition()).get("mass_kg", NAN))
			if not (is_finite(fitted) and fitted > 0.0) \
					or absf(fitted / float(layout["mass/total_kg"]) - 1.0) <= FLYING_MASS_TOLERANCE:
				break
			flying_mass = fitted
			_values = before.values.duplicate()
			_raw = before.raw.duplicate()
			_origin = before.origin.duplicate()
			_inventory = before.inventory.duplicate(true)
		var summary: Dictionary = Compiler.summarize(definition())
		var excess := _size_excess(summary)
		if not owns_scale or source_span <= 0.0 or domain.size() != 2:
			break
		var resized := float(placed.unit_scale)
		if excess > 1.0:
			var limit := float(domain[1]) * 0.98 / (source_span * float(Placement.UNITS["m"]))
			resized = minf(resized * sqrt(excess) * 1.03, limit)
		elif _unbalanced(summary):
			# Tail-heavy even with the battery forward and the nose weight capped by the mass range:
			# a slightly smaller version is lighter and leaves room to balance it.
			var floor_scale := float(domain[0]) * 1.02 / (source_span * float(Placement.UNITS["m"]))
			resized = maxf(resized * 0.9, minf(floor_scale, resized)) # shrinking never grows a model
		# The last attempt keeps its filled state: a remaining excess is then reported by the compiler.
		if absf(resized - float(placed.unit_scale)) <= float(placed.unit_scale) * 0.001 or attempt == SETUP_SIZE_ATTEMPTS - 1:
			break
		placed["unit_scale"] = resized
		units_value = ""
		_placement = before.placement.duplicate(true)
		_units = before.units
		_values = before.values.duplicate()
		_raw = before.raw.duplicate()
		_origin = before.origin.duplicate()
		_inventory = before.inventory.duplicate(true)
	_touch()
	if source_physics:
		_installation_proposal = Installation.make(_source,_review_observations,_airframe_package,_power_package)
	var chosen := choose_source_installation(_installation_proposal, revision, true)
	if not chosen.ok:
		# Nothing of a refused setup stays in the draft.
		_placement = before.placement
		_units = before.units
		_values = before.values
		_raw = before.raw
		_origin = before.origin
		_inventory = before.inventory
		_power_package = kept_package
		_airframe_package = kept_airframe
		_installation_proposal = kept_proposal
		_touch()
		return chosen
	var bounds := placed_bounds()
	return R.ok({scaled = units_value.is_empty() and owns_scale,
		flown_span_m = float(bounds.max[1]) - float(bounds.min[1]) if not bounds.is_empty() else 0.0})


const SETUP_SIZE_ATTEMPTS := 5
## Relative difference between the fitted and the scaled source mass above which the power is re-derived.
const FLYING_MASS_TOLERANCE := 0.05
const PUSHER_GAP_M := 0.04
const PUSHER_TAIL_CLEARANCE_M := 0.08

## Fills empty fields with starting estimates, proposes the inventory and fits the estimates.
func _fill_estimates(overrides: Dictionary = {}) -> void:
	var starting: Dictionary = starting_values()
	# Source-derived dimensions (a decoded Phoenix layout) replace the scaled template values; they are
	# still estimates, so the fit below may adjust them exactly as it adjusts the template's.
	for path: Variant in overrides:
		if starting.has(path) and is_finite(float(overrides[path])):
			starting[path] = float(overrides[path])
	var filled := {}
	for path: String in starting:
		if not _values.has(path) and not _invalid.has(path):
			_set_estimate(path, float(starting[path]))
			filled[path] = true
	# A pusher sits in a slot just behind the wing root, as on electric park jets: its thrust line
	# stays near the balance point. Only estimated mounts move.
	# A source-derived hub position (a decoded Phoenix pusher) is kept where the source puts it when the
	# package can carry it there (inside the fuselage section); a pylon-mounted pusher uses the slot.
	if _pusher_power() and filled.has("equipment/hub_position/0") and _values.has("wing/root_chord") \
			and not (overrides.has("equipment/hub_position/0") and _hub_in_fuselage()):
		var hub_x := float(_values["wing/root_chord"]) + PUSHER_GAP_M
		# A deep (or biplane-equivalent) root chord must not push the propeller past the tail.
		if _values.has("fuselage/tail_x"):
			hub_x = minf(hub_x, float(_values["fuselage/tail_x"]) - PUSHER_TAIL_CLEARANCE_M)
		_set_estimate("equipment/hub_position/0", hub_x)
		if filled.has("equipment/hub_position/2") and _values.has("fuselage/center_z"):
			_set_estimate("equipment/hub_position/2", float(_values["fuselage/center_z"]))
		if filled.has("equipment/esc_position/0"):
			_set_estimate("equipment/esc_position/0", hub_x - 0.12)
	if _inventory.is_empty():
		for item: Variant in Definition.propose_airframe_inventory(definition()):
			if item is Dictionary and _inventory.size() < Limits.INVENTORY_ITEMS:
				_inventory.append((item as Dictionary).duplicate(true))
	_setup_margin = SETUP_STATIC_MARGIN
	_fit_source_mass_and_balance(overrides)
	_fit_estimates(filled)


## Source-derived mass and balance (a decoded Phoenix model): "mass/total_kg" scales the estimated airframe
## items so the aircraft weighs what the source says; "balance/cg_aft_m" sets the static margin the fit
## balances to, from the source's centre of gravity, kept inside the package's static-margin range.
## Player-entered or measured items are never changed.
var _setup_margin := SETUP_STATIC_MARGIN

func _fit_source_mass_and_balance(overrides: Dictionary) -> void:
	var target_mass := float(overrides.get("mass/total_kg", NAN))
	var target_cg := float(overrides.get("balance/cg_aft_m", NAN))
	var airframe: Dictionary = Packages.airframe(_airframe_package)
	# The balance the fit aims at: the source's centre of gravity, as a static margin inside the package range.
	if is_finite(target_cg) and airframe.ok and airframe.value.domain.has("static_margin"):
		var summary: Dictionary = Compiler.summarize(definition())
		if summary.has("static_margin") and summary.has("mean_chord_m") and summary.has("cg_m") and float(summary.mean_chord_m) > 0.0:
			var margin := float(summary.static_margin) + (float((summary.cg_m as Array)[0]) - target_cg) / float(summary.mean_chord_m)
			if is_finite(margin):
				_setup_margin = clampf(margin, float(airframe.value.domain.static_margin.min) + 0.01,
					float(airframe.value.domain.static_margin.max) - 0.01)
	if not (is_finite(target_mass) and target_mass > 0.0):
		return
	var summary: Dictionary = Compiler.summarize(definition())
	if not summary.has("mass_kg") or not summary.has("cg_m"):
		return
	var mass := float(summary.mass_kg)
	if target_mass < mass:
		# Lighter than the estimate: the estimated airframe items shrink in proportion.
		var estimated := 0.0
		for item: Dictionary in _inventory:
			if str(item.get("kind", "")) == "estimated":
				estimated += float(item.get("mass", 0.0))
		if estimated > 0.0:
			var factor := clampf(1.0 - (mass - target_mass) / estimated, SOURCE_MASS_FACTOR_MIN, 1.0)
			for item: Dictionary in _inventory:
				if str(item.get("kind", "")) == "estimated":
					item.mass = float(item.mass) * factor
		return
	# Heavier than the estimate: the remainder is one source-mass item placed where the whole aircraft
	# balances at the target margin, inside the fuselage; the battery fit then refines the balance.
	var remainder := target_mass - mass
	if remainder < 0.005 or not summary.has("neutral_point_x_m") or not summary.has("mean_chord_m"):
		return
	var wanted_cg := float(summary.neutral_point_x_m) - _setup_margin * float(summary.mean_chord_m)
	var at := (target_mass * wanted_cg - mass * float((summary.cg_m as Array)[0])) / remainder
	var nose := float(_values.get("fuselage/nose_x", at)) + 0.03
	var tail := float(_values.get("fuselage/tail_x", at)) - 0.03
	at = clampf(at, minf(nose, tail), maxf(nose, tail))
	var height := float((summary.cg_m as Array)[2])
	# A repeated setup keeps the items an earlier one added (they count in the mass) and never reuses an id.
	var index := 0
	var added := 0
	while remainder > 0.0005 and added < SOURCE_MASS_ITEMS and _inventory.size() < Limits.INVENTORY_ITEMS:
		var id := "%s_%d" % [SOURCE_MASS_ID, index]
		index += 1
		if _has_item(id):
			continue
		var piece := minf(remainder, SOURCE_ITEM_MAX_KG)
		_inventory.append({id = id, name = SOURCE_MASS_NAME, mass = piece,
			position = [at, 0.0, height], size = [0.05, 0.05, 0.05], kind = "estimated"})
		remainder -= piece
		added += 1

const SOURCE_MASS_ID := "item_source_mass"
const SOURCE_MASS_NAME := "Source mass (Phoenix weight)"
const SOURCE_MASS_ITEMS := 4
const SOURCE_MASS_FACTOR_MIN := 0.3
## The flight loader accepts at most 5 kg per inventory item.
const SOURCE_ITEM_MAX_KG := 4.9


## A pusher installation, for installed and source-derived power packages alike.
func _pusher_power() -> bool:
	if _power_package in PUSHER_PACKAGES:
		return true
	var power: Dictionary = Packages.power(_power_package)
	return power.ok and Packages.is_pusher(power.value)


## True when the current hub lies inside the current fuselage cross-section (the packages' mount rule).
func _hub_in_fuselage() -> bool:
	for path: String in ["fuselage/width", "fuselage/height", "fuselage/center_z", "equipment/hub_position/1",
			"equipment/hub_position/2"]:
		if not _values.has(path) or not is_finite(float(_values[path])):
			return false
	return absf(float(_values["equipment/hub_position/1"])) <= 0.5 * float(_values["fuselage/width"]) \
		and absf(float(_values["equipment/hub_position/2"]) - float(_values["fuselage/center_z"])) <= 0.5 * float(_values["fuselage/height"])


## True when the estimate is still tail-heavy beyond the package's static-margin range.
func _unbalanced(summary: Dictionary) -> bool:
	var airframe: Dictionary = Packages.airframe(_airframe_package)
	return airframe.ok and summary.has("static_margin") and airframe.value.domain.has("static_margin") 		and float(summary.static_margin) < float(airframe.value.domain.static_margin.min)


## How far a size-driven quantity exceeds the package domain: >1 means the aircraft should be larger.
func _size_excess(summary: Dictionary) -> float:
	var airframe: Dictionary = Packages.airframe(_airframe_package)
	if not airframe.ok:
		return 1.0
	var domain: Dictionary = airframe.value.domain
	var excess := 1.0
	if summary.has("wing_loading_kg_m2") and domain.has("wing_loading_kg_m2"):
		excess = maxf(excess, float(summary.wing_loading_kg_m2) / (float(domain.wing_loading_kg_m2.max) * 0.95))
	if summary.has("thrust_to_weight") and domain.has("thrust_to_weight"):
		excess = maxf(excess, float(summary.thrust_to_weight) / (float(domain.thrust_to_weight.max) * 0.95))
	return excess


## The wingspan ranges [[min, max], ...] in metres the automatic setup chooses from, one per size class
## (setup_classes()), or [] if a package is unavailable.
static func span_domain() -> Array:
	var ranges: Array = []
	for size_class: Dictionary in setup_classes():
		ranges.append(size_class.range)
	return ranges


## [{airframe, tractor, pusher, range}] smallest first. Each range is the airframe package's span domain;
## the trainer starts at SETUP_MIN_SPAN_M, where the park-flyer class ends.
static func setup_classes() -> Array:
	var out: Array = []
	for entry: Array in [[PARKFLYER_AIRFRAME, SMALL_POWER, SMALL_PUSHER], [AIRFRAME_PACKAGE, POWER_PACKAGE, JET_PUSHER]]:
		var airframe: Dictionary = Packages.airframe(entry[0])
		if not airframe.ok or not airframe.value.domain.has("wing_span_m"):
			return []
		var low := float(airframe.value.domain.wing_span_m.min)
		var high := float(airframe.value.domain.wing_span_m.max)
		if entry[0] == AIRFRAME_PACKAGE:
			low = maxf(low, SETUP_MIN_SPAN_M)
		var size_class := {airframe = entry[0], tractor = entry[1], pusher = entry[2], range = [low, maxf(low, high)]}
		if entry[0] == AIRFRAME_PACKAGE:
			size_class.large_pusher = LARGE_JET_PUSHER
		out.append(size_class)
	return out


## Realism audit 2026-11-17: the trainer's 4S 800 kV 12x6 installation (about 1 kg of hardware) and balsa
## densities belong on a Stik-class 1.5 m airframe; below that they made estimates 2-3 times denser than real
## models (17 of 18 corpus models under 1.3 m diverged hands-off within 10 s). Smaller models use the foam
## park-flyer class with 3S power, which ends here.
const SETUP_MIN_SPAN_M := 1.45


func _set_estimate(path: String, number: float) -> void:
	_values[path] = number
	_raw[path] = format_number(number)
	_origin[path] = "estimated"


## Keeps the estimates this setup just made inside the estimated package's qualified domain, as a
## builder would: tail chords move the tail volumes inside their range, and the battery is moved to
## balance the aircraft at SETUP_STATIC_MARGIN. Only `filled` (estimated, never player) values change;
## source-derived dimensions are left as they are, so a model outside the domain stays refused.
const SETUP_STATIC_MARGIN := 0.15
const SETUP_FIT_ITERATIONS := 6

func _fit_estimates(filled: Dictionary) -> void:
	var airframe: Dictionary = Packages.airframe(_airframe_package)
	if not airframe.ok:
		return
	var domain: Dictionary = airframe.value.domain
	# A tail-heavy estimate whose battery is already at the nose gets the largest permitted estimated
	# tailplane, which moves the neutral point aft; a nose weight is the final resort.
	var tail_heavy := false
	for _iteration: int in SETUP_FIT_ITERATIONS:
		var summary: Dictionary = Compiler.summarize(definition())
		for pair: Array in [["tail_volume_h", "horizontal_tail/chord"], ["tail_volume_v", "vertical_tail/chord"]]:
			var key: String = pair[0]
			var path: String = pair[1]
			if not filled.has(path) or not summary.has(key) or not domain.has(key):
				continue
			var volume := float(summary[key])
			if not is_finite(volume):
				continue
			var target := clampf(volume, float(domain[key].min) * 1.1, float(domain[key].max) * 0.9)
			if tail_heavy and key == "tail_volume_h":
				target = float(domain[key].max) * 0.9
			if volume > 0.0 and absf(target - volume) > 1e-9:
				_set_estimate(path, float(_values[path]) * target / volume)
		# Keep each estimated tail's aspect ratio in range at the same area (span up, chord down).
		for shape: Array in [["tail_aspect_ratio", "horizontal_tail/span", "horizontal_tail/chord"],
				["fin_aspect_ratio", "vertical_tail/height", "vertical_tail/chord"]]:
			var ratio_key: String = shape[0]
			var length_path: String = shape[1]
			var chord_path: String = shape[2]
			if not filled.has(length_path) or not filled.has(chord_path) or not domain.has(ratio_key) \
					or not _values.has(length_path) or not _values.has(chord_path):
				continue
			var ratio := float(_values[length_path]) / float(_values[chord_path])
			var wanted := clampf(ratio, float(domain[ratio_key].min) * 1.05, float(domain[ratio_key].max) * 0.95)
			if ratio > 0.0 and absf(wanted - ratio) > 1e-9:
				var stretch := sqrt(wanted / ratio)
				_set_estimate(length_path, float(_values[length_path]) * stretch)
				_set_estimate(chord_path, float(_values[chord_path]) / stretch)
		var battery := "equipment/battery_position/0"
		if filled.has(battery) and summary.has("static_margin"):
			var before := float(summary.static_margin)
			if not is_finite(before) or absf(before - _setup_margin) <= 0.005:
				continue
			var at := float(_values[battery])
			_values[battery] = at + 0.01
			var moved: Dictionary = Compiler.summarize(definition())
			_values[battery] = at
			if not moved.has("static_margin"):
				continue
			var slope := (float(moved.static_margin) - before) / 0.01
			if not is_finite(slope) or absf(slope) < 1e-6:
				continue
			var low := float(_values.get("fuselage/nose_x", at)) + 0.02
			var high := float(_values.get("fuselage/tail_x", at)) - 0.02
			var wanted := at + (_setup_margin - before) / slope
			_set_estimate(battery, clampf(wanted, minf(low, high), maxf(low, high)))
			tail_heavy = tail_heavy or wanted < minf(low, high)
	if filled.has("equipment/battery_position/0"):
		_add_balance_weight()


## A light electric nose cannot balance a long tail: as a builder would, add one visible estimated
## nose weight that brings the balance point to SETUP_STATIC_MARGIN (at most BALANCE_MAX_KG).
const BALANCE_ID := "item_balance_estimated"
const BALANCE_NAME := "Nose balance weight (estimated)"
const BALANCE_MAX_KG := 1.0

func _add_balance_weight() -> void:
	if _has_item(BALANCE_ID) or _inventory.size() >= Limits.INVENTORY_ITEMS:
		return
	var summary: Dictionary = Compiler.summarize(definition())
	if not summary.has("static_margin") or float(summary.static_margin) >= _setup_margin - 0.005 \
			or not summary.has("mean_chord_m") or not summary.has("neutral_point_x_m") or not summary.has("mass_kg"):
		return
	var target := float(summary.neutral_point_x_m) - _setup_margin * float(summary.mean_chord_m)
	var cg := float((summary.cg_m as Array)[0])
	var at := float(_values.get("fuselage/nose_x", NAN)) + 0.03
	if not is_finite(at) or at >= target:
		return
	var mass := float(summary.mass_kg) * (cg - target) / (target - at)
	var airframe: Dictionary = Packages.airframe(_airframe_package)
	if airframe.ok and airframe.value.domain.has("mass_kg"):
		# Never balance an aircraft out of the package's mass range.
		mass = minf(mass, float(airframe.value.domain.mass_kg.max) * 0.98 - float(summary.mass_kg))
	if not is_finite(mass) or mass <= 0.0:
		return
	_inventory.append({id = BALANCE_ID, name = BALANCE_NAME, mass = minf(mass, BALANCE_MAX_KG),
		position = [at, 0.0, 0.0], size = [0.03, 0.03, 0.03], kind = "estimated"})


func units() -> String:
	return _units


func set_axis(which: String, axis: String) -> void:
	if which in ["nose_axis", "up_axis"] and (axis.is_empty() or Placement.AXES.has(axis)):
		_placement[which] = axis
		_touch()


## Chooses the unit the file was drawn in. An empty name returns the scale to unresolved.
func set_units(unit: String) -> void:
	_units = unit if Placement.UNITS.has(unit) else ""
	_placement["unit_scale"] = float(Placement.UNITS[unit]) if Placement.UNITS.has(unit) else 0.0
	_touch()


## Sets the scale from a known real wingspan instead of a unit. False when it cannot be derived.
func set_scale_from_wingspan(wingspan_m: float) -> bool:
	if _source == null:
		return false
	var scale := Placement.scale_for_wingspan(_placement, _source.bounds_min(), _source.bounds_max(), wingspan_m)
	if scale <= 0.0:
		return false
	_units = ""
	_placement["unit_scale"] = scale
	_touch()
	return true


## Datum in source coordinates: the wing leading edge on the centreline, picked or typed.
func set_datum(point: Array) -> void:
	_placement["datum"] = point.duplicate()
	_touch()


func placement_result() -> Dictionary:
	return Placement.resolve(_placement)


## Structural-frame bounds of the placed model in metres, or {} while the placement is unresolved.
func placed_bounds() -> Dictionary:
	if _source == null:
		return {}
	var resolved: Dictionary = Placement.resolve(_placement)
	if not resolved.ok:
		return {}
	return Placement.structural_bounds(resolved.value, _source.bounds_min(), _source.bounds_max())


# --- Typed fields ---------------------------------------------------------------------------

## The empty choice retains the historical servo law. A new law is always an explicit choice.
func servo_integration() -> String:
	return _servo_integration


## Returns false for unsupported choices; no-op and refused choices leave the revision unchanged.
func set_servo_integration(chosen: Variant) -> bool:
	if typeof(chosen) != TYPE_STRING:
		return false
	var law: String = chosen
	if not law.is_empty() and law != Definition.ServoLaw.LAW:
		return false
	if law == _servo_integration:
		return true
	_servo_integration = law
	_touch()
	return true


func raw(path: String) -> String:
	return str(_raw.get(path, ""))


func value(path: String) -> Variant:
	return _values.get(path)


func is_invalid(path: String) -> bool:
	return _invalid.has(path)


## Commits typed text. Empty text returns the field to unresolved. Invalid text is kept visible
## and flagged; the last accepted value stays for preview but compilation is blocked.
func set_raw(path: String, text: String) -> bool:
	text = clean_text(text)
	var trimmed := text.strip_edges()
	_raw[path] = text
	if trimmed.is_empty():
		_values.erase(path)
		_invalid.erase(path)
		_origin.erase(path)
		_touch()
		return true
	var parsed := parse_number(text)
	if is_nan(parsed):
		_invalid[path] = true
		_touch()
		return false
	_invalid.erase(path)
	_origin.erase(path)
	_values[path] = parsed
	_touch()
	return true


func set_value(path: String, number: float) -> void:
	_origin.erase(path)
	_values[path] = number
	_raw[path] = format_number(number)
	_invalid.erase(path)
	_touch()


## Applies several values at once. `estimated` marks them as unconfirmed starting values: the
## compiled record then labels them estimated, never as entered by the player.
func apply_values(values: Dictionary, estimated := false) -> void:
	for path: String in values:
		if estimated:
			_origin[path] = "estimated"
		else:
			_origin.erase(path)
		_values[path] = float(values[path])
		_raw[path] = format_number(float(values[path]))
		_invalid.erase(path)
	_touch()


## True while a value is an unconfirmed starting estimate.
func is_estimated(path: String) -> bool:
	return _origin.has(path) and _values.has(path)


static func field(path: String) -> Dictionary:
	for entry: Dictionary in FIELDS:
		if str(entry.path) == path:
			return entry
	return {}


static func fields_for(step: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in FIELDS:
		if str(entry.step) == step:
			found.append(entry)
	return found


# --- Inventory ------------------------------------------------------------------------------

func inventory() -> Array:
	return _inventory.duplicate(true)


## Replaces the airframe items with estimated ones proposed from the geometry. Items the player
## marked measured or manual are kept untouched.
func propose_inventory() -> void:
	var kept: Array = []
	var kept_ids := {}
	for item: Dictionary in _inventory:
		if str(item.get("kind", "")) != "estimated":
			kept.append(item)
			kept_ids[str(item.id)] = true
		else:
			_forget_item_text(str(item.id))
	for item: Variant in Definition.propose_airframe_inventory(definition()):
		if item is Dictionary and not kept_ids.has(str(item.id)) and kept.size() < Limits.INVENTORY_ITEMS:
			kept.append((item as Dictionary).duplicate(true))
	_inventory = kept
	_touch()


func add_item(item_name: String) -> String:
	if _inventory.size() >= Limits.INVENTORY_ITEMS:
		return ""
	var serial := 1
	var id := "item_custom_%d" % serial
	while _has_item(id):
		serial += 1
		id = "item_custom_%d" % serial
	_inventory.append({id = id, name = clean_text(item_name).substr(0, Limits.NAME_CHARACTERS), mass = 0.0, position = [0.0, 0.0, 0.0], size = [0.0, 0.0, 0.0], kind = "manual"})
	_touch()
	return id


func remove_item(id: String) -> void:
	for index: int in _inventory.size():
		if str(_inventory[index].id) == id:
			_inventory.remove_at(index)
			_forget_item_text(id)
			_touch()
			return


## Edits one inventory value from typed text. `key` is mass, x, y or z. False when not a number.
## Text that is not a number (empty included) belongs to the document and is an edit: revision,
## fingerprint and dirty state change, it is saved, backed up and restored, and it blocks
## compilation. The item keeps its last accepted number. A later valid edit clears it; repeating
## the same rejected text is not a new edit. Unknown items and keys record nothing.
func set_item_raw(id: String, key: String, text: String) -> bool:
	if not ITEM_KEYS.has(key):
		return false
	text = clean_text(text)
	var slot := _item_slot(id, key)
	for item: Dictionary in _inventory:
		if str(item.id) != id:
			continue
		# Over-long text is rejected whole: its stored prefix could otherwise read as a number.
		var parsed := parse_number(text) if text.length() <= Limits.RAW_NUMBER_CHARACTERS else NAN
		if is_nan(parsed):
			var kept := text.substr(0, Limits.RAW_NUMBER_CHARACTERS)
			if not _item_invalid.has(slot) or str(_item_invalid[slot]) != kept:
				_item_invalid[slot] = kept
				_touch()
			return false
		match key:
			"mass": item["mass"] = parsed
			"x": item.position[0] = parsed
			"y": item.position[1] = parsed
			"z": item.position[2] = parsed
		_item_invalid.erase(slot)
		_touch()
		return true
	return false


## True while an inventory number holds rejected text.
func is_item_invalid(id: String, key: String) -> bool:
	return _item_invalid.has(_item_slot(id, key))


## The rejected text of an inventory number, or "" when it holds none.
func item_invalid_text(id: String, key: String) -> String:
	return str(_item_invalid.get(_item_slot(id, key), ""))


func set_item_name(id: String, item_name: String) -> void:
	for item: Dictionary in _inventory:
		if str(item.id) == id:
			item["name"] = clean_text(item_name).substr(0, Limits.NAME_CHARACTERS)
			_touch()
			return


func set_item_kind(id: String, kind: String) -> void:
	if kind not in _INVENTORY_KINDS:
		return
	for item: Dictionary in _inventory:
		if str(item.id) == id:
			item["kind"] = kind
			_touch()
			return


func _has_item(id: String) -> bool:
	for item: Dictionary in _inventory:
		if str(item.id) == id:
			return true
	return false


static func _item_slot(id: String, key: String) -> String:
	return id + "/" + key


func _forget_item_text(id: String) -> void:
	for key: String in ITEM_KEYS:
		_item_invalid.erase(_item_slot(id, key))


func _sorted_item_slots() -> Array:
	var slots: Array = _item_invalid.keys()
	slots.sort()
	return slots


func _item_issue(slot: String) -> Dictionary:
	var parts := slot.rsplit("/", true, 1)
	var shown := parts[0]
	for item: Dictionary in _inventory:
		if str(item.id) == parts[0] and not str(item.get("name", "")).is_empty():
			shown = str(item.name)
	return R.diagnostic(R.FIELD_INVALID, "\"%s\" is not a number.", ITEM_FIELD_PREFIX + slot, "weight_balance",
		["%s · %s" % [shown, str(ITEM_KEYS.get(parts[1], parts[1]))]])


# --- Presentation: bound parts and appearance -----------------------------------------------

func bindings() -> Dictionary:
	return _bindings.duplicate(true)


## Whole numbers (part index, direction) are kept as integers whatever the caller or a stored
## record spelled them as, so the same bindings always have the same fingerprint.
func set_bindings(bound: Dictionary) -> void:
	_bindings = _whole_numbers(bound)
	_touch()


func appearance() -> Dictionary:
	return _appearance.duplicate(true)


func set_appearance(chosen: Dictionary) -> void:
	_appearance = chosen.duplicate(true)
	_touch()


# --- Saving ---------------------------------------------------------------------------------

## Everything needed to rebuild this document except the source bytes, as plain JSON data: typed
## values, raw text including invalid buffers, evidence, inventory, placement, bindings and paint.
## `step` is the wizard step to reopen on. The store treats the result as opaque.
##
## Every number is written with `exact`: the engine's JSON text does not round-trip a float64
## bit for bit, and a reopened draft must compile to the same bytes as before it was saved.
func snapshot(step := "") -> Dictionary:
	var invalid: Array = []
	for path: String in _invalid:
		invalid.append(path)
	var values := {}
	for path: String in _values:
		values[path] = exact(float(_values[path]))
	var items: Array = []
	for item: Dictionary in _inventory:
		items.append({"id": str(item.id), "name": str(item.name), "kind": str(item.kind), "mass": exact(float(item.mass)),
			"position": _exact_point(item.position), "size": _exact_point(item.size)})
	var saved := {
		"format": SNAPSHOT_FORMAT, "aircraft_uuid": _uuid, "name": name, "step": step,
		"source_sha256": _source.sha256() if _source != null else "",
		"placement": {"nose_axis": str(_placement.nose_axis), "up_axis": str(_placement.up_axis),
			"unit_scale": exact(float(_placement.unit_scale)), "datum": _exact_point(_placement.datum)},
		"units": _units, "raw": _raw.duplicate(), "values": values, "invalid": invalid,
		"origin": _origin.duplicate(), "inventory": items,
		"bindings": _bindings.duplicate(true), "appearance": _appearance.duplicate(true),
		"published_revision": published_revision,
	}
	if not _source_observations.is_empty():
		saved.format = SOURCE_SNAPSHOT_FORMAT
		saved.source_observations = _source_observations.duplicate(true)
	if not _source_installation.is_empty():
		saved.format = INSTALLATION_SNAPSHOT_FORMAT
		saved.source_installation = _source_installation.duplicate(true)
	if not _servo_integration.is_empty():
		saved.format = SERVO_SNAPSHOT_FORMAT
		saved.servo_integration = _servo_integration
	# Optional member, written only for the pusher variant: every other snapshot is unchanged.
	if _power_package != POWER_PACKAGE:
		saved.power_package = _power_package
	# Optional member, written only for the park-flyer class: every other snapshot is unchanged.
	if _airframe_package != AIRFRAME_PACKAGE:
		saved.airframe_package = _airframe_package
	# Optional member, written only when inventory text was rejected: other snapshots are unchanged.
	if not _item_invalid.is_empty():
		var rejected: Array = []
		for slot: String in _sorted_item_slots():
			var parts := slot.rsplit("/", true, 1)
			rejected.append({"item": parts[0], "key": parts[1], "text": str(_item_invalid[slot])})
		saved.inventory_raw = rejected
	return saved


## Rebuilds the document from a snapshot and the re-admitted source (null when the draft had no
## model yet). Nothing is taken on trust: unknown fields are dropped, numbers must be finite, and
## a source whose identity differs from the one the snapshot was saved with is refused.
## Returns the R envelope; on failure the document is unchanged.
func restore(saved: Dictionary, admitted: InspectedSource, observations: Observations.CheckedReport = null) -> Dictionary:
	if saved.get("format") not in [SNAPSHOT_FORMAT,SOURCE_SNAPSHOT_FORMAT,INSTALLATION_SNAPSHOT_FORMAT,SERVO_SNAPSHOT_FORMAT]:
		return R.fail(R.RECORD_INVALID, "This draft was saved by an incompatible version.")
	var servo := ""
	if saved.format == SERVO_SNAPSHOT_FORMAT:
		if typeof(saved.get("servo_integration")) != TYPE_STRING or saved.servo_integration != Definition.ServoLaw.LAW:
			return R.fail(R.RECORD_INVALID, "Choose a supported servo integration law.", "servo_integration", "controls_ground")
		servo = saved.servo_integration
	elif saved.has("servo_integration"):
		return R.fail(R.RECORD_INVALID, "Servo integration requires the versioned document format.", "servo_integration", "controls_ground")
	var context := {}
	if saved.format == SOURCE_SNAPSHOT_FORMAT or (saved.format in [INSTALLATION_SNAPSHOT_FORMAT,SERVO_SNAPSHOT_FORMAT] and saved.has("source_observations")):
		var checked := Observations.validate(saved.get("source_observations"))
		if not checked.ok or observations == null or not observations.matches(admitted) or checked.value != observations.context():
			return R.fail(R.IDENTITY_MISMATCH, "The saved source declarations do not match this model. Re-import the ZIP.","source_observations","import")
		context = checked.value
	var power_package: Variant = saved.get("power_package", POWER_PACKAGE)
	var airframe_package: Variant = saved.get("airframe_package", AIRFRAME_PACKAGE)
	# Phoenix-derived packages are re-derived from this source's own physics block, or refused.
	var derived := typeof(power_package) == TYPE_STRING and typeof(airframe_package) == TYPE_STRING \
		and PhoenixPhysics.is_derived(power_package) and PhoenixPhysics.is_derived(airframe_package) \
		and Installation.provider(admitted) == "phoenix" \
		and PhoenixPhysics.restore(PhoenixSetup.creator_setup(admitted).get("physics", {}), airframe_package, power_package)
	if typeof(power_package) != TYPE_STRING or (power_package not in POWER_PACKAGES and not derived):
		return R.fail(R.RECORD_INVALID, "This draft was saved by an incompatible version.")
	if typeof(airframe_package) != TYPE_STRING or (airframe_package not in AIRFRAME_PACKAGES and not derived):
		return R.fail(R.RECORD_INVALID, "This draft was saved by an incompatible version.")
	var installation := {}
	if saved.format == INSTALLATION_SNAPSHOT_FORMAT or (saved.format == SERVO_SNAPSHOT_FORMAT and saved.has("source_installation")):
		var checked := Installation.validate(saved.get("source_installation"),context,airframe_package,power_package)
		if not checked.ok:
			return checked
		if not Installation.required(admitted) or checked.value.source_sha256 != admitted.sha256():
			return R.fail(R.IDENTITY_MISMATCH,Installation.STALE,"source_installation","import")
		installation = checked.value
	var wanted := str(saved.get("source_sha256", ""))
	if (admitted == null) != wanted.is_empty() or (admitted != null and admitted.sha256() != wanted):
		return R.fail(R.IDENTITY_MISMATCH, "The saved model does not match this draft.")
	var uuid := str(saved.get("aircraft_uuid", ""))
	if not _is_uuid(uuid):
		return R.fail(R.RECORD_INVALID, "This draft has no aircraft identity.")
	var known := {}
	for entry: Dictionary in FIELDS:
		known[str(entry.path)] = true
	var values := {}
	var stored_values: Variant = saved.get("values", {})
	if stored_values is Dictionary:
		for path: Variant in stored_values:
			var number := from_exact(stored_values[path])
			if known.has(str(path)) and is_finite(number):
				values[str(path)] = number
	var raw_text := {}
	var stored_raw: Variant = saved.get("raw", {})
	if stored_raw is Dictionary:
		for path: Variant in stored_raw:
			if known.has(str(path)) and typeof(stored_raw[path]) == TYPE_STRING \
					and (stored_raw[path] as String).length() <= Limits.RAW_NUMBER_CHARACTERS:
				raw_text[str(path)] = clean_text(stored_raw[path])
	var invalid := {}
	for path: Variant in saved.get("invalid", []) if saved.get("invalid", []) is Array else []:
		if known.has(str(path)) and raw_text.has(str(path)) and is_nan(parse_number(raw_text[str(path)])) \
				and not str(raw_text[str(path)]).strip_edges().is_empty():
			invalid[str(path)] = true
	# What a field shows must be what the document holds: text is kept only when it is the typed
	# text of the stored value, the document's own display of it, or recorded as not being a number.
	for path: String in raw_text.keys():
		if invalid.has(path):
			continue
		if not values.has(path):
			raw_text.erase(path)
		elif parse_number(raw_text[path]) != float(values[path]) and raw_text[path] != format_number(float(values[path])):
			raw_text[path] = format_number(float(values[path]))
	var origin := {}
	var stored_origin: Variant = saved.get("origin", {})
	if stored_origin is Dictionary:
		for path: Variant in stored_origin:
			if values.has(str(path)) and str(stored_origin[path]) == "estimated":
				origin[str(path)] = "estimated"
	var items: Array = []
	for item: Variant in saved.get("inventory", []) if saved.get("inventory", []) is Array else []:
		var restored: Dictionary = _restored_item(item)
		if not restored.is_empty() and items.size() < Limits.INVENTORY_ITEMS:
			items.append(restored)
	var rejected_text := _restored_item_text(saved.get("inventory_raw", []), items)
	var placed := Placement.unresolved()
	var stored_placement: Variant = saved.get("placement", {})
	if stored_placement is Dictionary:
		for which: String in ["nose_axis", "up_axis"]:
			if Placement.AXES.has(str(stored_placement.get(which, ""))):
				placed[which] = str(stored_placement[which])
		var scale := from_exact(stored_placement.get("unit_scale"))
		if is_finite(scale) and scale > 0.0:
			placed["unit_scale"] = scale
		var datum: Array = _from_exact_point(stored_placement.get("datum"))
		if datum.size() == 3:
			placed["datum"] = datum
	_uuid = uuid
	name = clean_text(str(saved.get("name", ""))).substr(0, Limits.NAME_CHARACTERS)
	_source = admitted
	_source_observations = context
	_source_installation = installation
	_servo_integration = servo
	_review_observations = observations.context() if observations != null and observations.matches(admitted) else context.duplicate(true)
	_power_package = power_package
	_airframe_package = airframe_package
	_installation_proposal = Installation.make(_source,_review_observations,_airframe_package,_power_package)
	_placement = placed
	_units = str(saved.get("units", "")) if Placement.UNITS.has(str(saved.get("units", ""))) else ""
	_values = values
	_raw = raw_text
	_invalid = invalid
	_origin = origin
	_inventory = items
	_item_invalid = rejected_text
	_bindings = _whole_numbers(saved.get("bindings", {})) if saved.get("bindings", {}) is Dictionary and admitted != null else {}
	_appearance = (saved.get("appearance", {}) as Dictionary).duplicate(true) if saved.get("appearance", {}) is Dictionary \
		and not (saved.get("appearance", {}) as Dictionary).is_empty() else {"mode": "original"}
	var revision_saved: Variant = saved.get("published_revision", 0)
	published_revision = int(revision_saved) if (typeof(revision_saved) == TYPE_FLOAT or typeof(revision_saved) == TYPE_INT) \
		and float(revision_saved) >= 0.0 else 0
	_touch()
	return R.ok(str(saved.get("step", "")))


## Marks the current content as saved under `record_sha256` (the next save's compare-and-swap token).
func mark_saved(record_sha256: String) -> void:
	saved_record_sha256 = record_sha256
	_saved_fingerprint = fingerprint()


## True when the content differs from the last save, or was never saved and holds anything.
func has_unsaved_changes() -> bool:
	if _saved_fingerprint.is_empty():
		return _source != null or not _values.is_empty() or not _raw.is_empty() or not _inventory.is_empty() \
			or not name.is_empty() or not _servo_integration.is_empty()
	return fingerprint() != _saved_fingerprint


## Digest of the saved content. The step, camera and focus are not content.
func fingerprint() -> String:
	var written: Dictionary = CreatorBytes.encode(snapshot())
	return str(written.value.sha256) if written.ok else ""


## Text without control characters (C0 and DEL): they cannot be stored and a field never means them.
static func clean_text(text: String) -> String:
	var clean := ""
	var kept_from := 0
	for index: int in text.length():
		var code := text.unicode_at(index)
		if code < 0x20 or code == 0x7F:
			clean += text.substr(kept_from, index - kept_from)
			kept_from = index + 1
	return text if kept_from == 0 else clean + text.substr(kept_from)


## Deep copy with every whole-number float turned into an integer (a stored record returns every
## number as a float). Non-finite and fractional numbers are left for validation to refuse.
static func _whole_numbers(node: Variant) -> Variant:
	if node is Dictionary:
		var fields := {}
		for key: Variant in node:
			fields[key] = _whole_numbers(node[key])
		return fields
	if node is Array:
		var items: Array = []
		for item: Variant in node:
			items.append(_whole_numbers(item))
		return items
	if typeof(node) == TYPE_FLOAT and is_finite(node) and node == floorf(node) and absf(node) <= float(Limits.MAX_SAFE_INTEGER):
		return int(node)
	return node


## Lowercase version 4 UUID, as `Definition` requires of an aircraft identity.
static func _is_uuid(text: String) -> bool:
	if text.length() != 36:
		return false
	for index: int in 36:
		var character := text[index]
		if index in [8, 13, 18, 23]:
			if character != "-":
				return false
		elif character not in "0123456789abcdef":
			return false
	return text[14] == "4" and text[19] in "89ab"


static func _restored_item(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var id := str(item.get("id", ""))
	var kind := str(item.get("kind", ""))
	var mass := from_exact(item.get("mass"))
	var position: Array = _from_exact_point(item.get("position"))
	var size: Array = _from_exact_point(item.get("size"))
	if id.is_empty() or id.length() > 80 or kind not in _INVENTORY_KINDS or not is_finite(mass) \
			or position.size() != 3 or size.size() != 3:
		return {}
	return {id = id, name = clean_text(str(item.get("name", ""))).substr(0, Limits.NAME_CHARACTERS), mass = mass,
		position = position, size = size, kind = kind}


## Rejected inventory text of a snapshot, "<item id>/<key>" -> text. Like the field `invalid` list,
## entries that are not exactly {item, key, text} for a restored item, a known key and text that is
## still not a number are dropped; an absent member (every older snapshot) means none.
static func _restored_item_text(stored: Variant, items: Array) -> Dictionary:
	var found := {}
	if not stored is Array:
		return found
	var ids := {}
	for item: Dictionary in items:
		ids[str(item.id)] = true
	for entry: Variant in (stored as Array).slice(0, items.size() * ITEM_KEYS.size()):
		if not entry is Dictionary or (entry as Dictionary).size() != 3:
			continue
		var id: Variant = entry.get("item")
		var key: Variant = entry.get("key")
		var text: Variant = entry.get("text")
		if typeof(id) != TYPE_STRING or typeof(key) != TYPE_STRING or typeof(text) != TYPE_STRING \
				or not ids.has(id) or not ITEM_KEYS.has(key):
			continue
		var typed: String = text
		# Text cut at the limit is the stored prefix of an over-long rejection and may look numeric.
		if typed.length() > Limits.RAW_NUMBER_CHARACTERS or clean_text(typed) != typed \
				or (typed.length() < Limits.RAW_NUMBER_CHARACTERS and not is_nan(parse_number(typed))):
			continue
		found[_item_slot(id, key)] = typed
	return found


## A float64 as the 16 hex digits of its IEEE 754 bytes: exact through any text format.
static func exact(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


## The float64 written by `exact`, or NAN when the text is not exactly 16 hex digits or not finite.
static func from_exact(text: Variant) -> float:
	if typeof(text) != TYPE_STRING or (text as String).length() != 16:
		return NAN
	for character: String in (text as String):
		if character not in "0123456789abcdef":
			return NAN
	var value: float = (text as String).hex_decode().decode_double(0)
	return value if is_finite(value) else NAN


static func _exact_point(point: Variant) -> Array:
	var out: Array = []
	if point is Array or point is PackedFloat64Array:
		for component: Variant in point:
			out.append(exact(float(component)))
	return out


## Three finite numbers written by `_exact_point`, or [] when anything is off.
static func _from_exact_point(stored: Variant) -> Array:
	if not stored is Array or (stored as Array).size() != 3:
		return []
	var out: Array = []
	for component: Variant in stored:
		var value := from_exact(component)
		if not is_finite(value):
			return []
		out.append(value)
	return out


# --- Definition, starting values, issues ----------------------------------------------------

## The authoring definition from the accepted values. Unresolved values are simply absent, so
## complete-definition validation names exactly what is missing.
func definition() -> Dictionary:
	var record := {
		"format": Definition.FORMAT, "aircraft_uuid": _uuid,
		"airframe_package": _airframe_package, "power_package": _power_package,
		"inventory": _inventory.duplicate(true),
	}
	for path: String in _values:
		var segments := path.split("/")
		var vector_path := "/".join(segments.slice(0, segments.size() - 1))
		if _VECTORS.has(vector_path):
			continue
		_set_nested(record, segments, float(_values[path]))
	for vector_path: String in _VECTORS:
		var pattern: Array = _VECTORS[vector_path]
		var components: Array = []
		for index: int in pattern.size():
			if float(pattern[index]) != -1.0:
				components.append(float(pattern[index]))
			elif _values.has("%s/%d" % [vector_path, index]):
				components.append(float(_values["%s/%d" % [vector_path, index]]))
		if components.size() == pattern.size():
			_set_nested(record, vector_path.split("/"), components)
	var evidence := {}
	for path: String in _origin:
		if not _values.has(path):
			continue
		var segments := path.split("/")
		var group := "/".join(segments.slice(0, segments.size() - 1))
		# A vector is estimated while any of its components still is.
		evidence[group if _VECTORS.has(group) else path] = "estimated"
	if not evidence.is_empty():
		record["evidence"] = evidence
	if not _source_observations.is_empty():
		record.format = Definition.SOURCE_FORMAT
		record.source_observations = _source_observations.duplicate(true)
	if not _source_installation.is_empty():
		record.format = Definition.INSTALLATION_FORMAT
		record.source_installation = _source_installation.duplicate(true)
	if not _servo_integration.is_empty():
		record.format = Definition.SERVO_FORMAT
		record.servo_integration = _servo_integration
	return record


## Estimated starting values scaled from the reference trainer to the placed model: lengths scale
## with the wingspan, and the fuselage ends follow the model's own extent. They are estimates to
## correct, never measurements. Returns path -> value; apply with `apply_values`.
func starting_values() -> Dictionary:
	var template: Dictionary = Definition.template()
	var bounds: Dictionary = placed_bounds()
	var template_span: float = float(template.wing.span)
	var span: float = template_span
	if not bounds.is_empty():
		span = float(bounds.max[1]) - float(bounds.min[1])
	if _values.has("wing/span"):
		span = float(_values["wing/span"])
	var k: float = span / template_span if template_span > 0.0 and span > 0.0 else 1.0
	var values := {}
	for entry: Dictionary in FIELDS:
		var path: String = entry.path
		var found: Variant = _lookup(template, path.split("/"))
		if found == null:
			continue
		values[path] = float(found) * (k if str(entry.unit) == "m" else 1.0)
	values["wing/span"] = span
	if not bounds.is_empty():
		var nose: float = float(bounds.min[0])
		var tail: float = float(bounds.max[0])
		if nose < 0.0 and tail > 0.0:
			var shift: float = nose - float(values["fuselage/nose_x"])
			values["fuselage/nose_x"] = nose
			values["fuselage/tail_x"] = tail
			values["equipment/hub_position/0"] = float(values["equipment/hub_position/0"]) + shift
			values["horizontal_tail/position/0"] = tail - float(values["horizontal_tail/chord"])
			values["vertical_tail/position/0"] = tail - float(values["vertical_tail/chord"])
	return values


func summary() -> Dictionary:
	return Compiler.summarize(definition())


## Everything that blocks a test flight, as routed diagnostics.
func issues() -> Array:
	var found: Array = []
	if needs_source_installation():
		found.append(R.diagnostic(R.UNSUPPORTED_CAPABILITY,Installation.blocked(_source),"source_installation","import"))
	# A confirmed ClearView installation compiles to the same physical bytes as any other source
	# (compiler.gd strips source metadata), so it follows the ordinary experimental trial gate.
	if _source == null:
		found.append(R.diagnostic(R.SOURCE_MISSING, "Import a model first.", "source", "import"))
	else:
		var placed: Dictionary = Placement.resolve(_placement)
		if not placed.ok:
			found.append_array(placed.diagnostics)
	for path: String in _invalid:
		var entry: Dictionary = field(path)
		found.append(R.diagnostic(R.FIELD_INVALID, "\"%s\" is not a number.", path, str(entry.get("step", "")),
			[str(entry.get("label", path))]))
	for slot: String in _sorted_item_slots():
		found.append(_item_issue(slot))
	var checked: Dictionary = Definition.validate_complete(definition())
	if not checked.ok:
		found.append_array(checked.diagnostics)
	elif _invalid.is_empty() and _item_invalid.is_empty() and not needs_source_installation():
		var compiled: Dictionary = compile()
		if not compiled.ok:
			found.append_array(compiled.diagnostics)
	return found


## Compiles the current definition. The result is cached for the current document revision.
func compile() -> Dictionary:
	if _compiled_revision == revision:
		return _compiled
	if needs_source_installation():
		_compiled = R.fail(R.UNSUPPORTED_CAPABILITY,Installation.blocked(_source),"source_installation","import")
	elif not _invalid.is_empty():
		_compiled = R.fail(R.FIELD_INVALID, "Correct the highlighted values first.")
	elif not _item_invalid.is_empty():
		# Rejected inventory text: the last accepted number is a stale preview, never a flight input.
		var named: Array = []
		for slot: String in _sorted_item_slots():
			named.append(_item_issue(slot))
		_compiled = R.fail_all(named)
	else:
		_compiled = Compiler.compile_candidate(definition())
	_compiled_revision = revision
	return _compiled


func step_status(step: String) -> String:
	match step:
		"import":
			return STATUS_IN_PROGRESS if needs_source_installation() else (STATUS_COMPLETE if _source != null else STATUS_NOT_STARTED)
		"orient_size":
			if _source == null:
				return STATUS_NOT_STARTED
			if Placement.resolve(_placement).ok:
				return STATUS_COMPLETE
			var started: bool = not str(_placement.nose_axis).is_empty() or not str(_placement.up_axis).is_empty() \
				or float(_placement.unit_scale) > 0.0 or not (_placement.datum as Array).is_empty()
			return STATUS_IN_PROGRESS if started else STATUS_NOT_STARTED
		"paint_skins":
			return STATUS_COMPLETE if _source != null else STATUS_NOT_STARTED
		"review_test":
			if _source == null or _values.is_empty():
				return STATUS_NOT_STARTED
			return STATUS_COMPLETE if issues().is_empty() else STATUS_IN_PROGRESS
	var owned: Array[Dictionary] = fields_for(step)
	var resolved := 0
	var broken := false
	for entry: Dictionary in owned:
		if _values.has(entry.path):
			resolved += 1
		if _invalid.has(entry.path):
			broken = true
	if step == "weight_balance" and not _item_invalid.is_empty():
		broken = true
	if step == "weight_balance" and _inventory.is_empty():
		return STATUS_NEEDS_ATTENTION if broken else (STATUS_IN_PROGRESS if resolved > 0 else STATUS_NOT_STARTED)
	if broken:
		return STATUS_NEEDS_ATTENTION
	if step in ["aircraft_layout","power_mount","controls_ground"] and needs_source_installation():
		return STATUS_IN_PROGRESS
	if resolved == 0:
		return STATUS_NOT_STARTED
	if resolved < owned.size():
		return STATUS_IN_PROGRESS
	for entry: Variant in issues():
		if entry is Dictionary and str((entry as Dictionary).get("step", "")) == step:
			return STATUS_NEEDS_ATTENTION
	return STATUS_COMPLETE


func _touch() -> void:
	revision += 1
	changed.emit()


static func _set_nested(record: Dictionary, segments: PackedStringArray, leaf: Variant) -> void:
	var node: Dictionary = record
	for index: int in segments.size() - 1:
		if not node.has(segments[index]):
			node[segments[index]] = {}
		node = node[segments[index]]
	node[segments[segments.size() - 1]] = leaf


static func _lookup(record: Variant, segments: PackedStringArray) -> Variant:
	var node: Variant = record
	for segment: String in segments:
		if node is Dictionary and (node as Dictionary).has(segment):
			node = node[segment]
		elif node is Array and segment.is_valid_int() and int(segment) < (node as Array).size():
			node = node[int(segment)]
		else:
			return null
	return node if typeof(node) == TYPE_FLOAT or typeof(node) == TYPE_INT else null
