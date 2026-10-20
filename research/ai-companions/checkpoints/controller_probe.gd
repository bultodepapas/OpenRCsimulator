## Tiny serializer fixture for the offline checkpoint protocol test.
extends RefCounted

var continuation_token := 0


func snapshot_state() -> Dictionary:
	return {"continuation_token": continuation_token}


func restore_state(snapshot: Dictionary) -> Dictionary:
	if snapshot.size() != 1 or typeof(snapshot.get("continuation_token")) != TYPE_INT \
			or snapshot.continuation_token < 0:
		return {"ok": false, "reason": "invalid probe snapshot"}
	continuation_token = snapshot.continuation_token
	return {"ok": true}
