extends RefCounted

const META_KEY: StringName = &"openrc_loading_profile_spans"
const MAX_SPANS: int = 512


static func record(name: String, start_usec: int, end_usec: int, detail: Dictionary = {}) -> void:
	var spans: Array = Engine.get_meta(META_KEY, [])
	if spans.size() >= MAX_SPANS:
		return
	spans.append({"name": name, "start_usec": start_usec, "end_usec": end_usec, "detail": detail.duplicate(true)})
	Engine.set_meta(META_KEY, spans)
