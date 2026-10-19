## LU: one reversible comparison switch; production defaults to the complete field.
extends RefCounted

static func enabled() -> bool:
	var value := OS.get_environment("OPENRC_LANDSCAPE_UPGRADE")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--landscape-upgrade="):
			value = arg.get_slice("=", 1)
	return not value.to_lower() in ["off", "false", "0"]

static func glare_strength() -> float:
	var value := OS.get_environment("OPENRC_SUN_GLARE")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--sun-glare="):
			value = arg.get_slice("=", 1)
	if value.is_empty():
		return 1.0
	if value.to_lower() == "off":
		return 0.0
	if not value.is_valid_float() or not is_finite(float(value)):
		push_warning("Invalid sun-glare intensity; using 1 (valid range 0..2).")
		return 1.0
	return clampf(float(value), 0.0, 2.0)


## SUN-06: what the pilot wears against the sun: --pilot-eyewear=none|cap|sunglasses|cap+sunglasses, or
## OPENRC_PILOT_EYEWEAR. Default none. Returns {cap: bool, sunglasses: bool} (render/sun/sun_optics.gd applies them).
static func pilot_eyewear() -> Dictionary:
	var value := OS.get_environment("OPENRC_PILOT_EYEWEAR")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pilot-eyewear="):
			value = arg.get_slice("=", 1)
	var parsed := parse_eyewear(value)
	if not parsed.ok:
		push_warning("Invalid pilot eyewear '%s'; using none (none, cap, sunglasses, cap+sunglasses)." % value)
	return {cap = parsed.cap, sunglasses = parsed.sunglasses}


static func parse_eyewear(value: String) -> Dictionary:
	match value.strip_edges().to_lower():
		"", "none", "off":
			return {ok = true, cap = false, sunglasses = false}
		"cap":
			return {ok = true, cap = true, sunglasses = false}
		"sunglasses":
			return {ok = true, cap = false, sunglasses = true}
		"cap+sunglasses", "sunglasses+cap":
			return {ok = true, cap = true, sunglasses = true}
	return {ok = false, cap = false, sunglasses = false}

