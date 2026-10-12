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
