## One-sided serializer fixture; capture must reject an incomplete protocol pair.
extends RefCounted


func snapshot_state() -> Dictionary:
	return {"mutable": true}
