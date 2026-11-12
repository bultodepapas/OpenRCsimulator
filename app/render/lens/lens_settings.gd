## LENS-01 (docs/plans/lens-screen-effects.md): lens and screen effect preferences. Presentation only; the simulation
## never reads them. The app applies the saved preference once (set_preference); a flight resolves it with its own
## command-line overrides (resolve). Scripted, capture and trace routes get nothing unless --lens-effects is explicit.
extends RefCounted

const QUALITIES: Array[String] = ["off", "low", "medium", "high", "ultra"]
const IMPACT_STYLES: Array[String] = ["off", "curtain", "splatter"]
const IMPACT_COLOURS: Array[String] = ["red", "dark", "desaturated"]
const SWITCHES: Array[String] = ["off", "on"]

## Owner decision D1 (2026-11-12): the classic curtain is on by default and can be switched off.
const DEFAULTS := {
	"lens_effects": "medium",
	"impact_effects": "curtain",
	"impact_colour": "red",
	"lens_rain": "on",
	"lens_glasses": "off",
	"lens_grime": "on",
	"lens_clear_centre": "off",
}

## Per-tier budgets. Disabled tiers allocate nothing; a lower tier frees the higher one's buffers on the next flight.
const TIERS := {
	"low": {"drops": 24, "streaks": 2000, "stamps": 8, "trails": false, "wetness": false, "focus_lod": 1.0},
	"medium": {"drops": 64, "streaks": 5000, "stamps": 16, "trails": true, "wetness": true, "focus_lod": 1.5},
	"high": {"drops": 128, "streaks": 9000, "stamps": 24, "trails": true, "wetness": true, "focus_lod": 1.5},
	"ultra": {"drops": 192, "streaks": 14000, "stamps": 32, "trails": true, "wetness": true, "focus_lod": 2.0},
}

static var _preference: Dictionary = DEFAULTS.duplicate()


## Validated copy of the saved preference; unknown or malformed values fall back to the defaults.
static func validate(raw: Variant) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var source: Dictionary = raw
	_pick(out, source, "lens_effects", QUALITIES)
	_pick(out, source, "impact_effects", IMPACT_STYLES)
	_pick(out, source, "impact_colour", IMPACT_COLOURS)
	for key: String in ["lens_rain", "lens_glasses", "lens_grime", "lens_clear_centre"]:
		_pick(out, source, key, SWITCHES)
	return out


static func set_preference(config: Dictionary) -> void:
	_preference = validate(config)


static func preference() -> Dictionary:
	return _preference.duplicate()


## Resolves what one flight shows. `automatic_route` is false for scripted, capture and trace routes.
## Command-line overrides (`-- --key=value`): --lens-effects=off|on|low|medium|high|ultra, --impact-fx=off|curtain|splatter,
## --impact-colour=red|dark|desaturated, --lens-rain=off|on, --lens-rain-mmph=<mm/h>, --lens-grime=off|on,
## --lens-glasses=off|on, --lens-clear-centre=off|on.
static func resolve(args: Dictionary, automatic_route: bool, saved: Dictionary = _preference) -> Dictionary:
	var pref: Dictionary = validate(saved)
	var quality: String = pref.lens_effects
	if args.has("lens-effects"):
		var requested := str(args["lens-effects"])
		quality = pref.lens_effects if requested == "on" and pref.lens_effects != "off" else ("medium" if requested == "on" else requested)
		if quality not in QUALITIES:
			quality = "off"
	elif not automatic_route:
		quality = "off"
	var impact: String = _override(args, "impact-fx", pref.impact_effects, IMPACT_STYLES)
	var colour: String = _override(args, "impact-colour", pref.impact_colour, IMPACT_COLOURS)
	var rain: bool = _override(args, "lens-rain", pref.lens_rain, SWITCHES) == "on"
	var grime: bool = _override(args, "lens-grime", pref.lens_grime, SWITCHES) == "on"
	var glasses: bool = _override(args, "lens-glasses", pref.lens_glasses, SWITCHES) == "on"
	var clear_centre: bool = _override(args, "lens-clear-centre", pref.lens_clear_centre, SWITCHES) == "on"
	var rain_override := NAN
	if args.has("lens-rain-mmph"):
		var text := str(args["lens-rain-mmph"])
		if text.is_valid_float():
			rain_override = clampf(text.to_float(), 0.0, 200.0)
	var enabled := quality != "off"
	return {
		"enabled": enabled and (impact != "off" or rain or grime),
		"quality": quality,
		"tier": TIERS.get(quality, TIERS.medium),
		"impact": impact if enabled else "off",
		"colour": colour,
		"rain": enabled and rain,
		"grime": enabled and grime,
		"glasses": glasses,
		"clear_centre": clear_centre,
		"rain_override_mmph": rain_override,
	}


static func _pick(out: Dictionary, source: Dictionary, key: String, allowed: Array[String]) -> void:
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_STRING and String(value) in allowed:
		out[key] = String(value)


static func _override(args: Dictionary, key: String, fallback: String, allowed: Array[String]) -> String:
	if not args.has(key):
		return fallback
	var value := str(args[key])
	return value if value in allowed else fallback
