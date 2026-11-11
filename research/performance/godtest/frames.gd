extends "res://render/frame_samples.gd"
## Event-bounded use of the existing collector. Its report deliberately has a
## distinct format: it does not satisfy fixed-duration native-summary gates.

const EVENT_FORMAT := "openrc-godtest-frames-v1"
var event_complete := false
var event_reason := ""


func seal_event(success: bool, reason: String) -> Dictionary:
	if not finished:
		event_complete = success and failure.is_empty()
		event_reason = reason
		finished = true
		if not _stream_path.is_empty() and not _seal_stream(event_complete):
			failure = _stream_error
			event_complete = false
	var result := report()
	result.collector_format = result.format
	result.format = EVENT_FORMAT
	result.completion_kind = "scenario_event"
	result.collection_bound_seconds = sample_s
	result.requested_seconds = null
	result.completion_reason = event_reason
	result.complete = event_complete and failure.is_empty()
	return result
