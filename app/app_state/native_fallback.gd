extends RefCounted
## Classifies a session's physics-backend status (`stage_backend_status()`) so a native request that silently fell
## back to the slower GDScript reference is visible (legacy modes audit, 2026-11-20). Pure; reads no global state.
##
## Kinds:
##   native    - the native evaluator is installed.
##   selected  - the reference was requested explicitly (tools, replay, Creator trials).
##   domain    - an expected refusal outside the native domain (lake, weather, custom spawn, servo law...).
##   stale     - a native build or package exists but no longer matches this source, engine or executable.
##   missing   - no usable native library on this host.

## Refusals from native_stage.gd and native_package.gd that mean a native build or package was refused for its
## identity. Any "native package" refusal is a broken shipped build. Matched case-insensitively.
const STALE_MARKERS: Array[String] = [
	"native package", "mac native package", "mac native receipt", "mac native bundle", "mac native manifest",
	"mac native licence", "mac native default", "mac package", "artifact receipt", "mirrored source differs",
	"receipt lists no mirrored sources", "receipt is malformed", "does not match its receipt", "identity does not match",
	"binary differs", "descriptor differs", "manifest differs", "requires the exact verified godot executable",
	"requires the exact verified macos version", "restart required", "loaded before verification",
	"receipt differs from the loaded library", "contract differs from the loaded application",
	"package default changed after admission",
]
## Reasons that mean no native library is installed or loadable.
const MISSING_MARKERS: Array[String] = ["library not installed", "library failed to load", "class is missing"]
## Hosts whose shipped packages carry the native kernel (NK-3/NK-4); a missing library there is a defect.
const NATIVE_HOSTS: Array[String] = ["Windows", "Linux"]


static func classify(status: Dictionary) -> String:
	var identity: Variant = status.get("identity", {})
	if identity is Dictionary and str((identity as Dictionary).get("backend", "")) == "native":
		return "native"
	if str(status.get("requested", "")) != "native":
		return "selected"
	var reason := str(status.get("reason", "")).to_lower()
	for marker: String in STALE_MARKERS:
		if reason.contains(marker):
			return "stale"
	for marker: String in MISSING_MARKERS:
		if reason.contains(marker):
			return "missing"
	return "domain"


## The warning to raise for this status, or "" when the fallback is expected. `os_name` and `architecture` are
## OS.get_name() and Engine.get_architecture_name(); `release` is OS.has_feature("template_release"). The public
## macOS package deliberately ships the reference (legacy modes audit), so it never warns.
static func warning(status: Dictionary, os_name: String, architecture: String, release: bool) -> String:
	if os_name == "macOS" and release:
		return ""
	var kind := classify(status)
	var shipped_native := os_name in NATIVE_HOSTS and architecture == "x86_64"
	if kind == "stale" or (kind == "missing" and shipped_native):
		return ("Native physics is not running (%s); flights use the GDScript reference, about twice the physics "
			+ "CPU. Rebuild or reinstall the native kernel: research/native-kernel/README.md") \
			% str(status.get("reason", ""))
	return ""


## Compact form for the debug bridge and logs.
static func summary(status: Dictionary) -> Dictionary:
	var identity: Variant = status.get("identity", {})
	return {
		backend = str((identity as Dictionary).get("backend", "")) if identity is Dictionary else "",
		requested = str(status.get("requested", "")),
		kind = classify(status),
		reason = str(status.get("reason", "")),
	}
