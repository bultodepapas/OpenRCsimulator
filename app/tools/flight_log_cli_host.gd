## Run the existing bounded flight-log reader inside the shipped executable.
## This entry point accepts only the reader's declared options, never a script path.
extends Node

const Reader := preload("res://tools/flight_log_cli.gd")
const FLAGS := ["quick-flight", "flight-log-cli", "replay", "recover"]
const VALUES := ["log", "csv", "report", "candidate"]

var _reader: Object


func start(args: PackedStringArray) -> void:
	var seen := {}
	for argument: String in args:
		if not argument.begins_with("--"):
			_fail("expected --name or --name=value options")
			return
		var pair := argument.trim_prefix("--").split("=", true, 1)
		var name: String = pair[0]
		if seen.has(name) or (name in FLAGS and pair.size() != 1) \
				or (name in VALUES and (pair.size() != 2 or pair[1].is_empty())) \
				or (name not in FLAGS and name not in VALUES):
			_fail("invalid, repeated or unknown option: " + argument)
			return
		seen[name] = true
	if not seen.has("flight-log-cli") or not seen.has("log") or not seen.has("csv") or not seen.has("report"):
		_fail("requires --flight-log-cli and --log, --csv and --report paths")
		return
	if (seen.has("candidate") and not seen.has("replay")) or (seen.has("recover") and seen.has("replay")):
		_fail("candidate requires replay; recovery is export only")
		return
	_reader = Reader.new()
	_reader.call("_initialize")
	call_deferred("_finish")


func _finish() -> void:
	if _reader == null or _reader.get("_completed") != true:
		_fail("reader did not complete")
		return
	var result: Variant = _reader.get("report")
	if not result is Dictionary or result.get("status") != "ok":
		_fail("reader refused the log or could not write its output")
		return
	print("FLIGHT_LOG_CLI_HOST verdict=pass")
	_reader.free()
	_reader = null
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("FLIGHT_LOG_CLI_HOST verdict=fail: " + reason)
	if _reader != null:
		_reader.free()
		_reader = null
	get_tree().quit(1)
