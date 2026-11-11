extends RefCounted
## AC-12 research helper: in-domain Aircraft Creator definitions for the modes probe and the numerical
## campaign. Every variant starts from Definition.template() and changes only stated fields, then asks
## the package for its own airframe mass proposal and balances the result. Nothing here is a runtime
## path: the variants compile through the unchanged Compiler and fly in the unchanged FlightSession.
## Positions are metres in the leading-edge frame [x_aft, y_right, z_up]; 64-bit float only.

const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")

const BALLAST_ID := "item_research_ballast"
## Where the battery may sit when a variant is balanced, as fractions of the fuselage: from just behind
## the motor to the wing trailing edge.
const BATTERY_NOSE_CLEARANCE_M := 0.11


## The template with every length multiplied by `k` (as Authoring.starting_values scales it), the
## airframe mass proposal refreshed for the new size, and the centre of mass left where it falls.
static func scaled(k: float) -> Dictionary:
	var d: Dictionary = Definition.template()
	for key: String in ["span", "root_chord", "tip_chord"]:
		d["wing"][key] = float(d["wing"][key]) * k
	for group: String in ["horizontal_tail", "vertical_tail"]:
		for key: String in d[group]:
			d[group][key] = _times(d[group][key], k)
	for key: String in d["fuselage"]:
		d["fuselage"][key] = float(d["fuselage"][key]) * k
	for key: String in ["hub_position", "battery_position", "esc_position"]:
		d["equipment"][key] = _times(d["equipment"][key], k)
	return _proposed(d)


## The template with the same wing area and tails and a rectangular wing of the given aspect ratio.
static func aspect(aspect_ratio: float) -> Dictionary:
	var d: Dictionary = Definition.template()
	var area: float = float(d["wing"]["span"]) * 0.5 * (float(d["wing"]["root_chord"]) + float(d["wing"]["tip_chord"]))
	var span: float = sqrt(aspect_ratio * area)
	d["wing"]["span"] = span
	d["wing"]["root_chord"] = area / span
	d["wing"]["tip_chord"] = area / span
	return _proposed(d)


## The same wing area and span with straight taper `ratio` (tip chord / root chord).
static func tapered(ratio: float) -> Dictionary:
	var d: Dictionary = Definition.template()
	var mean: float = 0.5 * (float(d["wing"]["root_chord"]) + float(d["wing"]["tip_chord"]))
	d["wing"]["root_chord"] = 2.0 * mean / (1.0 + ratio)
	d["wing"]["tip_chord"] = ratio * float(d["wing"]["root_chord"])
	return _proposed(d)


## Moves the battery along x until the static margin is `target` (fraction of the mean chord). When the
## battery's sensible range is not enough, the battery stays at its limit and a ballast item at the
## nose or the tail end supplies the rest; its mass is reported in the returned definition's inventory.
## Returns {} when no balance within 1.5 kg of ballast reaches the target.
static func balanced(definition: Dictionary, target: float) -> Dictionary:
	var d: Dictionary = definition.duplicate(true)
	var fuselage: Dictionary = d["fuselage"]
	var low: float = float(fuselage["nose_x"]) + BATTERY_NOSE_CLEARANCE_M
	var high: float = float(d["wing"]["root_chord"])
	# Static margin falls as the battery moves aft: bisection on the battery x.
	if _margin(_with_battery(d, low)) >= target and _margin(_with_battery(d, high)) <= target:
		for iteration: int in 60:
			var middle: float = 0.5 * (low + high)
			if _margin(_with_battery(d, middle)) > target:
				low = middle
			else:
				high = middle
		return _with_battery(d, 0.5 * (low + high))
	var forward: bool = _margin(_with_battery(d, low)) < target
	d = _with_battery(d, low if forward else high)
	var place: Array = [float(fuselage["nose_x"]) + 0.03, 0.0, float(fuselage["center_z"])] if forward \
		else [float(fuselage["tail_x"]) - 0.05, 0.0, float(fuselage["center_z"])]
	var light := 0.0
	var heavy := 1.5
	if (_margin(_with_ballast(d, place, heavy)) < target) == forward:
		return {}
	for iteration: int in 60:
		var middle: float = 0.5 * (light + heavy)
		if (_margin(_with_ballast(d, place, middle)) < target) == forward:
			light = middle
		else:
			heavy = middle
	return _with_ballast(d, place, 0.5 * (light + heavy))


## A lumped mass added to the inventory (a payload or a heavier airframe), at `place`.
static func with_mass(definition: Dictionary, id: String, mass: float, place: Array) -> Dictionary:
	var d: Dictionary = definition.duplicate(true)
	d["inventory"].append({"id": id, "name": id, "mass": mass, "position": place, "size": [0.0, 0.0, 0.0], "kind": "manual"})
	return d


## Read-out of a definition: {ok, text, summary}. `text` names the refusals.
static func describe(definition: Dictionary) -> Dictionary:
	var summary: Dictionary = Compiler.summarize(definition)
	var problems := PackedStringArray()
	for issue: Dictionary in summary.get("issues", []):
		problems.append("%s@%s" % [issue.code, issue.field])
	return {ok = problems.is_empty(), text = ", ".join(problems), summary = summary}


static func _margin(definition: Dictionary) -> float:
	return float(Compiler.summarize(definition).get("static_margin", NAN))


static func _with_battery(definition: Dictionary, x: float) -> Dictionary:
	var d: Dictionary = definition.duplicate(true)
	var battery: Array = d["equipment"]["battery_position"]
	d["equipment"]["battery_position"] = [x, battery[1], battery[2]]
	return d


static func _with_ballast(definition: Dictionary, place: Array, mass: float) -> Dictionary:
	var d: Dictionary = definition.duplicate(true)
	var kept: Array = []
	for item: Dictionary in d["inventory"]:
		if item["id"] != BALLAST_ID:
			kept.append(item)
	d["inventory"] = kept
	if mass > 0.001:
		kept.append({"id": BALLAST_ID, "name": "Research ballast", "mass": mass, "position": place,
			"size": [0.0, 0.0, 0.0], "kind": "manual"})
	return d


static func _proposed(definition: Dictionary) -> Dictionary:
	definition["inventory"] = []
	definition["inventory"] = Definition.propose_airframe_inventory(definition)
	return definition


static func _times(value: Variant, k: float) -> Variant:
	if value is Array:
		var out: Array = []
		for item: Variant in (value as Array):
			out.append(float(item) * k)
		return out
	return float(value) * k
