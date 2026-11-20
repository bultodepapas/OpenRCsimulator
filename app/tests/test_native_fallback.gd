extends SceneTree
## Legacy modes audit (2026-11-20): a native physics request that falls back to the GDScript reference is classified,
## and stale or missing native builds raise a warning instead of a single log line.

const NativeFallback := preload("res://app_state/native_fallback.gd")
## Sources whose refusals reach `stage_backend_status().reason` while loading or verifying the native build.
const SOURCES: Array[String] = ["res://sim/native_stage.gd", "res://app_state/native_package.gd"]
## Refusals that use installation words but are not a broken build: a transient race inside one preparation, and the
## Mac reference bundle's own identity checks (the public macOS package never warns).
const NOT_INSTALLATION: Array[String] = ["preparation identity changed", "Mac bundle", "Mac executable",
	"Mac reference package",
	"executable is not in a Mac app bundle", "external project settings override"]
## A refusal literal that names the native build, its receipt, package or loading.
const INSTALLATION_WORDS := "(?i)receipt|binary|library|descriptor|mirrored|identity|executable|package|verified|loaded|manifest"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_kinds()
	_test_warnings()
	_test_summary()
	_test_source_reasons_are_classified()
	print("native fallback: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: %s %s" % [name, str(detail)])


func _fallback(reason: String, requested := "native") -> Dictionary:
	return {requested = requested, identity = {backend = "gdscript_reference"}, reason = reason}


func _test_kinds() -> void:
	var native := {requested = "native", identity = {backend = "native", abi_version = 2}, reason = ""}
	_check("installed native", NativeFallback.classify(native) == "native")
	_check("explicit reference", NativeFallback.classify(_fallback("", "gdscript_reference")) == "selected")
	_check("helicopter lake is domain", NativeFallback.classify(
		_fallback("native helicopter terrain does not support lakes; using gdscript_reference")) == "domain")
	_check("Mac custom spawn is domain",
		NativeFallback.classify(_fallback("custom spawn is outside the screened stock scope")) == "domain")
	_check("RC circuit is domain",
		NativeFallback.classify(_fallback("native stage does not model the RC circuit terrain")) == "domain")
	_check("Intel Mac is domain", NativeFallback.classify(
		_fallback("Mac native stage requires an Apple Silicon app session or explicit research opt-in")) == "domain")
	_check("stale mirrored source", NativeFallback.classify(_fallback(
		"mirrored source differs from the verified native build: app/sim/flight_session.gd")) == "stale")
	_check("stale package executable", NativeFallback.classify(
		_fallback("native package executable differs from its artifact receipt")) == "stale")
	_check("package engine mismatch is stale", NativeFallback.classify(
		_fallback("native package has no valid verified Windows receipt")) == "stale")
	_check("missing library", NativeFallback.classify(_fallback("native stage library not installed")) == "missing")
	_check("case-insensitive", NativeFallback.classify(_fallback(
		"native stage requires the exact verified Godot executable; reinstall after verification")) == "stale")
	_check("malformed status is not native", NativeFallback.classify({}) == "selected")


func _test_warnings() -> void:
	var stale := _fallback("mirrored source differs from the verified native build: app/sim/simulation.gd")
	var missing := _fallback("native stage library not installed")
	var lake := _fallback("native helicopter terrain does not support lakes; using gdscript_reference")
	var package := _fallback("native package manifest is missing, malformed or for another engine")
	_check("stale warns on Windows", NativeFallback.warning(stale, "Windows", "x86_64", false).contains("simulation.gd"))
	_check("broken package warns in a Windows release", not NativeFallback.warning(package, "Windows", "x86_64", true).is_empty())
	_check("broken package warns in a Linux release", not NativeFallback.warning(package, "Linux", "x86_64", true).is_empty())
	_check("stale warns on a Mac source run", not NativeFallback.warning(stale, "macOS", "arm64", false).is_empty())
	_check("Mac release never warns", NativeFallback.warning(
		_fallback("Mac native package descriptor differs from the verified loader contract"), "macOS", "arm64", true).is_empty())
	_check("missing warns on Linux x86_64", not NativeFallback.warning(missing, "Linux", "x86_64", false).is_empty())
	_check("missing stays quiet on a Mac source run", NativeFallback.warning(missing, "macOS", "arm64", false).is_empty())
	_check("missing stays quiet on arm64 Linux", NativeFallback.warning(missing, "Linux", "arm64", false).is_empty())
	_check("domain refusal stays quiet", NativeFallback.warning(lake, "Windows", "x86_64", true).is_empty())
	_check("explicit reference stays quiet",
		NativeFallback.warning(_fallback("", "gdscript_reference"), "Windows", "x86_64", false).is_empty())


func _test_summary() -> void:
	var summary := NativeFallback.summary(_fallback("native stage library not installed"))
	_check("summary fields", summary == {backend = "gdscript_reference", requested = "native", kind = "missing",
		reason = "native stage library not installed"}, summary)
	_check("summary tolerates a missing identity", NativeFallback.summary({}).backend == "")


## Every refusal that names the native build, its receipt, package or loading must be classified stale or missing,
## so a reworded or new reason cannot silently become an unannounced "domain" fallback.
func _test_source_reasons_are_classified() -> void:
	var literals := RegEx.create_from_string("(?:return|_refuse\\()\\s*\"([^\"]+)\"")
	var installation := RegEx.create_from_string(INSTALLATION_WORDS)
	var seen := 0
	for path: String in SOURCES:
		var source := FileAccess.get_file_as_string(path)
		_check("source readable: " + path, not source.is_empty())
		for found: RegExMatch in literals.search_all(source):
			var reason := found.get_string(1)
			if installation.search(reason) == null \
					or NOT_INSTALLATION.any(func(word: String) -> bool: return reason.contains(word)):
				continue
			seen += 1
			var kind := NativeFallback.classify(_fallback(reason))
			_check("refusal classified: " + reason, kind in ["stale", "missing"], kind)
	_check("refusals found", seen >= 40, seen)
	_check("class-missing refusal is missing",
		NativeFallback.classify(_fallback("native stage class is missing after loading")) == "missing")
