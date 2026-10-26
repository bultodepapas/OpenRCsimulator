## Frozen pre-optimization complete returns, including moving axes and held rotors.
## Reusing this stage's factor may not alter any acceleration, ledger or refusal.
extends SceneTree
const Rotor := preload("res://physics/rotor_coupling.gd")
var checks := 0
var failed := 0
func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label)
func _initialize() -> void:
	var raw := FileAccess.get_file_as_bytes("res://tests/fixtures/rotor_stage_factor.bin")
	_check("frozen pre-change fixture identity", _sha256(raw) == "1a860bae3e791f6a2f86f16baf4e7d6bd372e7d705ea17da6b4da401e4e04e4c")
	var cases: Array = bytes_to_var(raw)
	_check("all frozen cases present", cases.size() == 34)
	var free_cases := 0
	var held_cases := 0
	var refusals := 0
	for row: Dictionary in cases:
		var args: Array = row.args.duplicate(true)
		var before := var_to_bytes(args)
		var actual: Dictionary = Rotor._evaluate_carrier.callv(args)
		_check("complete return equals pre-change source", var_to_bytes(actual) == var_to_bytes(row.expected))
		_check("all supplied operands unchanged", before == var_to_bytes(args))
		if actual.ok:
			if args[-1].is_empty(): free_cases += 1
			else: held_cases += 1
		else: refusals += 1
	_check("free moving systems exercise selected factor", free_cases == 12)
	_check("held reduced systems retain original solve", held_cases == 8)
	_check("overload and malformed inputs remain refused", refusals == 14)
	print("Rotor stage factor: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _sha256(bytes: PackedByteArray) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode()
