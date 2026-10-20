## Adversarial protocol fixture: changes a local field before returning a refusal.
extends RefCounted

var continuation_token := 0


func snapshot_state() -> Dictionary:
	return {"continuation_token": continuation_token}


func restore_state(snapshot: Dictionary) -> Dictionary:
	if snapshot.size() != 1 or typeof(snapshot.get("continuation_token")) != TYPE_INT:
		return {"ok": false, "reason": "invalid probe snapshot"}
	continuation_token = snapshot.continuation_token
	if continuation_token == 13:
		return {"ok": false, "reason": "mutated before refusing"}
	return {"ok": true}
