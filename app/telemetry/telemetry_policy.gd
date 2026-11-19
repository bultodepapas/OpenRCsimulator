## TELEM-02: the single admission decision for product telemetry. Pure: callers gather the facts (build, route,
## locale, saved choice, release configuration) and this decides. Anything unknown, mistyped or missing closes the
## gate. Collection, queueing and transmission all ask this first; nothing else may open them.
extends RefCounted

const Contract := preload("res://telemetry/telemetry_contract.gd")

## Notices reviewed by a person in that language. Other offered languages keep telemetry off and say so; a
## language change can never reactivate a grant without a reviewed notice (docs/plans/telemetry/consent.md).
const REVIEWED_NOTICE_LOCALES: Array[String] = ["en", "es"]

## States: "on" collects and sends; "ask" shows the first-launch choice and collects nothing until Enable;
## "off" offers telemetry but it is not active (reason says why); "unavailable" means this build or route never
## offers it (no UI prompt, no network).
const ON := "on"
const ASK := "ask"
const OFF := "off"
const UNAVAILABLE := "unavailable"

## Engine/user arguments a desktop launcher may add without changing the route (old macOS Finder launches).
const BENIGN_ARGUMENT_PREFIXES: Array[String] = ["-psn_"]
## Renderer selections the game's own restarts add (RendererGuard's Compatibility fallback after a renderer failure,
## a Settings graphics-mode change) or a player's renderer shortcut uses. They choose how the same interactive
## session draws, so those sessions are measured too; any other argument still closes the route.
const RENDERER_ARGUMENTS := {
	"--rendering-method": ["gl_compatibility", "mobile", "forward_plus"],
	"--rendering-driver": ["opengl3", "opengl3_angle", "opengl3_es", "vulkan", "d3d12", "metal"],
}
## Environment variables that make a run technical or automated even with no arguments.
const TECHNICAL_ENVIRONMENT: Array[String] = ["OPENRC_PACKAGE_DEFAULT_PROBE", "OPENRC_GODTEST_CONFIG",
	"OPENRC_DEBUG_BRIDGE", "OPENRC_UPDATE_URL", "OPENRC_TELEMETRY_DISABLE"]


## facts: {release: Dictionary from TelemetryRelease.current() ({ok, ...}), interactive: bool, locale: String,
## choice: "unset"|"enabled"|"disabled"|"unreadable", notice: String (the notice a saved grant accepted),
## suspended: bool}. Returns {state, reason}.
static func evaluate(facts: Variant) -> Dictionary:
	if not facts is Dictionary:
		return _result(UNAVAILABLE, "unknown")
	var release: Variant = facts.get("release")
	if not release is Dictionary or not Contract.is_true(release.get("ok")):
		return _result(UNAVAILABLE, "build")
	if not Contract.is_true(facts.get("interactive")):
		return _result(UNAVAILABLE, "route")
	if not Contract.is_false(facts.get("suspended")):
		return _result(OFF, "suspended")
	if typeof(facts.get("locale")) != TYPE_STRING or not language_of(facts.locale) in REVIEWED_NOTICE_LOCALES:
		return _result(OFF, "locale")
	var choice: Variant = facts.get("choice")
	if typeof(choice) != TYPE_STRING:
		return _result(OFF, "unknown")
	match str(choice):
		"enabled":
			var notice: Variant = release.get("notice")
			if typeof(notice) == TYPE_STRING and notice != "" and Contract.same_text(facts.get("notice"), notice):
				return _result(ON, "granted")
			return _result(ASK, "new_notice")
		"disabled":
			return _result(OFF, "declined")
		"unset":
			return _result(ASK, "unset")
		"unreadable":
			return _result(OFF, "unreadable")
	return _result(OFF, "unknown")


## The ordinary interactive route: Home exists, no user or engine arguments (beyond launcher noise and a renderer
## selection), a real
## display, the player's own settings file and no automation/diagnostic environment. Everything else is off.
static func interactive_route(has_home: Variant, user_args: Variant, engine_args: Variant, display: Variant,
		default_settings: Variant, environment: Variant) -> bool:
	if not Contract.is_true(has_home) or not Contract.is_true(default_settings) or typeof(display) != TYPE_STRING \
			or display == "headless":
		return false
	if not user_args is PackedStringArray or not user_args.is_empty() or not engine_args is PackedStringArray:
		return false
	var index := 0
	while index < engine_args.size():
		var argument: String = engine_args[index]
		var benign := false
		for prefix: String in BENIGN_ARGUMENT_PREFIXES:
			benign = benign or argument.begins_with(prefix)
		if not benign and RENDERER_ARGUMENTS.has(argument) and index + 1 < engine_args.size() \
				and engine_args[index + 1] in RENDERER_ARGUMENTS[argument]:
			benign = true
			index += 1 # the value
		if not benign:
			return false
		index += 1
	if not environment is Dictionary:
		return false
	for key: String in TECHNICAL_ENVIRONMENT:
		if str(environment.get(key, "")) != "":
			return false
	return true


## "es_ES" -> "es"; zh_Hans and pt_BR keep their script/region as the catalogs do.
static func language_of(locale: String) -> String:
	if locale in ["zh_Hans", "pt_BR"]:
		return locale
	return locale.get_slice("_", 0)


static func _result(state: String, reason: String) -> Dictionary:
	return {"state": state, "reason": reason}
