extends SceneTree
## Audit 2026-11-19 F02: collision near-tie ordering must not depend on hit discovery order.
## Hits 0.75e-12 apart chain across FRACTION_TIE (1e-12); their stable IDs oppose time order, so the
## old pairwise tolerance comparator formed a cycle and the first hit depended on the input order.

const SceneryCollision := preload("res://sim/scenery_collision.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")

const PERMUTATIONS := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_scenery_order()
	_test_lake_winner()
	print("collision tie order: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_scenery_order() -> void:
	var fractions := [0.5, 0.5 + 0.75e-12, 0.5 + 1.5e-12]
	var ids := ["c", "b", "a"]
	var expected: Array = []
	for order: Array in PERMUTATIONS:
		var hits: Array = []
		for index: int in order:
			var event := SceneryCollision.Event.new()
			event.time_fraction = float(fractions[index])
			event.obstacle_id = str(ids[index])
			event.point_index = index
			hits.append(event)
		var ordered: Array = SceneryCollision._ordered(hits).map(
			func(event: SceneryCollision.Event) -> String: return event.obstacle_id)
		if expected.is_empty():
			expected = ordered
		_check("scenery order is independent of discovery " + str(order), ordered == expected, str(ordered))
	# The earliest hit "c" anchors the window: "b" ties with it, "a" (1.5e-12 later) does not.
	_check("scenery order anchors ties at the earliest hit", expected == ["b", "c", "a"], str(expected))
	var same := SceneryCollision.Event.new()
	same.time_fraction = 0.25
	same.obstacle_id = "x"
	same.point_index = 4
	var lower := SceneryCollision.Event.new()
	lower.time_fraction = 0.25 + 0.5e-12
	lower.obstacle_id = "x"
	lower.point_index = 1
	var far := SceneryCollision.Event.new()
	far.time_fraction = 0.3
	far.obstacle_id = "a"
	far.point_index = 0
	var mixed: Array = SceneryCollision._ordered([far, same, lower]).map(
		func(event: SceneryCollision.Event) -> String: return "%s%d" % [event.obstacle_id, event.point_index])
	_check("scenery point index breaks an obstacle tie; distinct times stay chronological",
		mixed == ["x1", "x4", "a0"], str(mixed))


func _test_lake_winner() -> void:
	var fractions := [0.5, 0.5 + 0.75e-12, 0.5 + 1.5e-12]
	var orders := [2, 1, 0]
	var expected := ""
	for order: Array in PERMUTATIONS:
		var seen: Array[LakeCollision.WaterEvent] = []
		var best: LakeCollision.WaterEvent = null
		for index: int in order:
			var event := LakeCollision.WaterEvent.new()
			event.time_fraction = float(fractions[index])
			event.probe_order = int(orders[index])
			event.obstacle_id = "lake"
			best = LakeCollision._admit(seen, event)
		var winner := "%d" % best.probe_order
		if expected.is_empty():
			expected = winner
		_check("lake winner is independent of discovery " + str(order), winner == expected, winner)
	_check("lake winner is the tie-window leader of the earliest hit", expected == "1", expected)
	var seen: Array[LakeCollision.WaterEvent] = []
	var bank := LakeCollision.WaterEvent.new()
	bank.time_fraction = 0.2
	bank.material = "bank_ground"
	var water := LakeCollision.WaterEvent.new()
	water.time_fraction = 0.2 + 0.5e-12
	water.material = "water"
	LakeCollision._admit(seen, bank)
	_check("lake water wins a same-probe material tie", LakeCollision._admit(seen, water) == water)
	var late := LakeCollision.WaterEvent.new()
	late.time_fraction = 0.4
	late.probe_order = -1
	_check("a later hit never displaces an earlier window", LakeCollision._admit(seen, late) == water)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1
