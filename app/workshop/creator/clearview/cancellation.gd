extends RefCounted
## A worker may outlive its wizard. Cancellation never calls a scene node from that worker.
var _mutex := Mutex.new()
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var result := _cancelled
	_mutex.unlock()
	return result
