extends RefCounted
## Result envelope and stable diagnostic codes shared by the Aircraft Creator services (AC-01).
##
## Every non-flight Creator service returns `{ok, value, diagnostics}`. `value` is absent on failure.
## A dictionary with `ok = true` is data, never an accepted handle: trusted owners are RefCounted
## objects created by their own factories after validation.

const SOURCE_UNSUPPORTED := "SOURCE_UNSUPPORTED"
const SOURCE_INVALID := "SOURCE_INVALID"
const SOURCE_LIMIT := "SOURCE_LIMIT"
const SOURCE_MISSING := "SOURCE_MISSING"
const FIELD_INVALID := "FIELD_INVALID"
const DATUM_UNRESOLVED := "DATUM_UNRESOLVED"
const DEPENDENCY_MISSING := "DEPENDENCY_MISSING"
const UNSUPPORTED_CAPABILITY := "UNSUPPORTED_CAPABILITY"
const BALANCE_INFEASIBLE := "BALANCE_INFEASIBLE"
const DOMAIN_REFUSED := "DOMAIN_REFUSED"
const BUILD_INVALID := "BUILD_INVALID"
const START_REFUSED := "START_REFUSED"
const IDENTITY_MISMATCH := "IDENTITY_MISMATCH"
const RECORD_INVALID := "RECORD_INVALID"
const WRITE_FAILED := "WRITE_FAILED"
const SAVE_CONFLICT := "SAVE_CONFLICT"
const STORAGE_QUOTA := "STORAGE_QUOTA"
const ROOT_LOCK_BUSY := "ROOT_LOCK_BUSY"

const SEVERITY_ERROR := "error"
const SEVERITY_WARNING := "warning"
const SEVERITY_INFO := "info"


## One diagnostic. `message` is an English source string with `%s` placeholders filled from
## `arguments` at the UI boundary, where it is also translated. `field` is a stable field path
## and `step` one of the canonical wizard step IDs, so the UI can focus the exact control.
static func diagnostic(code: String, message: String, field := "", step := "",
		arguments: Array = [], severity := SEVERITY_ERROR) -> Dictionary:
	return {code = code, severity = severity, message = message, field = field, step = step,
		arguments = arguments.duplicate()}


static func ok(value: Variant = null, diagnostics: Array = []) -> Dictionary:
	return {ok = true, value = value, diagnostics = diagnostics.duplicate()}


static func fail(code: String, message: String, field := "", step := "", arguments: Array = []) -> Dictionary:
	return {ok = false, diagnostics = [diagnostic(code, message, field, step, arguments)]}


static func fail_all(diagnostics: Array) -> Dictionary:
	return {ok = false, diagnostics = diagnostics.duplicate()}


## True when any diagnostic is an error. Warnings and notes never block an operation.
static func has_errors(diagnostics: Array) -> bool:
	for entry: Variant in diagnostics:
		if entry is Dictionary and str((entry as Dictionary).get("severity", SEVERITY_ERROR)) == SEVERITY_ERROR:
			return true
	return false


## Untranslated one-line text for logs and tests. The UI formats and translates on its own.
static func text(entry: Dictionary) -> String:
	var message := str(entry.get("message", ""))
	var arguments: Array = entry.get("arguments", [])
	if not arguments.is_empty() and message.count("%s") == arguments.size():
		message = message % arguments
	return "%s: %s" % [str(entry.get("code", "")), message]


static func texts(result: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for entry: Variant in result.get("diagnostics", []):
		if entry is Dictionary:
			lines.append(text(entry))
	return lines
