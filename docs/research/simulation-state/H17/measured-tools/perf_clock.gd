extends RefCounted
static var enabled := false
static var rows: Dictionary = {}
static var stack: Array = []
static func begin() -> void:
	stack.append([Time.get_ticks_usec(), 0])
static func end(label: String) -> void:
	var frame: Array = stack.pop_back()
	var elapsed: int = Time.get_ticks_usec() - frame[0]
	if not stack.is_empty(): stack[-1][1] += elapsed
	if not enabled: return
	if not rows.has(label): rows[label] = {calls = 0, inclusive_usec = 0, self_usec = 0}
	rows[label].calls += 1
	rows[label].inclusive_usec += elapsed
	rows[label].self_usec += elapsed - frame[1]
