## Pure numeric entry point for the detached launch-trim worker.
## Arguments are produced from the cache's object-free var_to_bytes round trip on the main thread.
extends RefCounted

# Main-thread owner of one detached numeric solve. No session, model callbacks or scene nodes are retained.
var thread: Thread = null
var owner: String = "menu"
var complete := false
var joined := false
var result: Dictionary = {}


func start(arguments: Array, speculative := false) -> Error:
	thread = Thread.new()
	# LOW is a scheduling hint; Windows may ignore it.
	var error: Error = thread.start(Callable(get_script(), "solve").bind(arguments),
		Thread.PRIORITY_LOW if speculative else Thread.PRIORITY_NORMAL)
	if error != OK:
		thread = null
		result = {ok = false, message = "launch trim worker could not start (%d)" % error}
		complete = true
	return error


## Only join after the worker has stopped. All calls are from the main thread.
func poll() -> bool:
	if complete:
		return true
	if thread == null or thread.is_alive():
		return false
	var value: Variant = thread.wait_to_finish()
	joined = true
	result = value if typeof(value) == TYPE_DICTIONARY else {ok = false, message = "launch trim worker returned an invalid result"}
	complete = true
	return true


func result_copy() -> Dictionary:
	return result.duplicate(true)


const CruiseTrim := preload("res://physics/cruise_trim.gd")


static func solve(arguments: Array) -> Dictionary:
	return CruiseTrim.solve_level_at_throttle(
		float(arguments[0]), float(arguments[1]), float(arguments[2]), arguments[3],
		float(arguments[4]), arguments[5], float(arguments[6]), float(arguments[7]), float(arguments[8]))
