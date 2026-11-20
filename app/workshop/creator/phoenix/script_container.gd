extends RefCounted
## Bounded reader for the Phoenix RC `.mod` / `.sim` script container (AC-PX). Pure data.
##
## Port of `research/aircraft-creator/phoenix/inspect_luac.py` (profile `openrc-phoenix-luac50-observed-v1`).
## The file is a 8-byte magic followed by byte pairs whose sum modulo 256 is the logical byte; the
## logical stream is a standard Lua 5.0 binary chunk. This reader never runs Lua: it parses the chunk
## and abstractly evaluates only the straight-line data-construction subset (constants, tables, globals
## as symbols). Any other opcode stops evaluation with a diagnostic. Functions are opaque closures.
##
## Plain output values: tables become Dictionaries (or Arrays for 1..n keys), numbers whole in float64
## become int, strings are Latin-1 text, an unknown global is `{"$symbol": "physics.airplane"}`, a
## closure `{"$closure": pc}` and an unevaluated operation `{"$expr": ...}`.

const R := preload("res://workshop/creator/result.gd")

const PROFILE := "openrc-phoenix-luac50-observed-v1"
const MAX_INPUT := 8 << 20
const MAX_CONSTANTS := 1 << 16
const MAX_CODE := 1 << 18
const MAX_DEPTH := 16
const MAX_PROTOS := 4096
const MAX_UPVALUES := 255
const MAX_STEPS := 2000000
const MAX_PLAIN_DEPTH := 64
## Plain-data nodes per evaluation; the largest stock definition needs a few thousand.
const MAX_PLAIN_NODES := 200000
const MAX_SYMBOL_PATH := 1024
const MAXSTACK := 250
const FIELDS_PER_FLUSH := 32
const REGISTERS := 256
const STEP := "import"
const _MAGIC: PackedByteArray = [0, 1, 2, 4, 8, 16, 32, 64]
const _HEADER: PackedByteArray = [0x1B, 0x4C, 0x75, 0x61, 0x50, 0x01, 0x04, 0x04, 0x04, 0x06, 0x08, 0x09]
const _TEST_NUMBER := 3.14159265358979323846E7
const _OPNAMES: PackedStringArray = ["MOVE", "LOADK", "LOADBOOL", "LOADNIL", "GETUPVAL", "GETGLOBAL", "GETTABLE",
	"SETGLOBAL", "SETUPVAL", "SETTABLE", "NEWTABLE", "SELF", "ADD", "SUB", "MUL", "DIV", "POW", "UNM", "NOT",
	"CONCAT", "JMP", "EQ", "LT", "LE", "TEST", "CALL", "TAILCALL", "RETURN", "FORLOOP", "TFORLOOP", "TFORPREP",
	"SETLIST", "SETLISTO", "CLOSE", "CLOSURE"]

enum Op {
	MOVE = 0, LOADK = 1, LOADBOOL = 2, LOADNIL = 3, GETGLOBAL = 5, GETTABLE = 6, SETGLOBAL = 7, SETTABLE = 9,
	NEWTABLE = 10, ADD = 12, SUB = 13, MUL = 14, DIV = 15, UNM = 17, SETLIST = 31, SETLISTO = 32, RETURN = 27,
	CLOSURE = 34,
}


## Reads and evaluates a script. `value` is `{profile, source, globals, assigned, diagnostics,
## instructions, constants, functions}`.
static func read(data: PackedByteArray, cancelled := Callable()) -> Dictionary:
	var parsed := parse(data)
	if not parsed.ok:
		return parsed
	var function: Dictionary = parsed.value
	var evaluated := evaluate(function, MAX_STEPS, cancelled)
	if not evaluated.ok:
		return evaluated
	var found: Dictionary = evaluated.value
	return R.ok({profile = PROFILE, source = function.source, globals = found.globals, assigned = found.assigned,
		diagnostics = found.diagnostics, instructions = function.code.size(), constants = function.constants.size(),
		functions = function.protos.size()})


## Removes the pair encoding. `value` is the logical Lua chunk.
static func unsplit(data: PackedByteArray) -> Dictionary:
	if data.size() < 8 or data.slice(0, 8) != _MAGIC:
		return R.fail(R.SOURCE_UNSUPPORTED, "The file is not the observed Phoenix script container.", "source", STEP)
	if (data.size() - 8) % 2 != 0:
		return R.fail(R.SOURCE_INVALID, "The Phoenix script has an odd payload length.", "source", STEP)
	var count := (data.size() - 8) / 2
	var out := PackedByteArray()
	out.resize(count)
	for index: int in count:
		out[index] = (data[8 + index * 2] + data[9 + index * 2]) & 0xFF
	return R.ok(out)


## Parses the container and the Lua 5.0 chunk. `value` is the main function (see `_function`).
static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_INPUT:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix script is larger than %s MiB.", "source", STEP, [str(MAX_INPUT >> 20)])
	var logical := unsplit(data)
	if not logical.ok:
		return logical
	var reader := Reader.new()
	reader.bytes = logical.value
	var header := reader.take(12)
	var sizes := [reader.byte(), reader.byte()]
	if reader.error.is_empty() and (header != _HEADER or sizes != [9, 8]):
		return R.fail(R.SOURCE_UNSUPPORTED, "The Phoenix script has an unexpected Lua header.", "source", STEP)
	var number := reader.number()
	if not reader.error.is_empty():
		return R.fail(reader.code, reader.error, "source", STEP, reader.arguments)
	if number != _TEST_NUMBER:
		return R.fail(R.SOURCE_UNSUPPORTED, "The Phoenix script has an unexpected Lua number format.", "source", STEP)
	var main := reader.function(0)
	if reader.error.is_empty() and reader.at != reader.bytes.size():
		return R.fail(R.SOURCE_INVALID, "The Phoenix script has %s unexpected trailing bytes.", "source", STEP,
			[str(reader.bytes.size() - reader.at)])
	if not reader.error.is_empty():
		return R.fail(reader.code, reader.error, "source", STEP, reader.arguments)
	return R.ok(main)


## Straight-line abstract evaluation of the main function. `value` is `{globals, assigned,
## diagnostics}`; `assigned` holds assignments into unknown globals such as `modelTypes.easystar`.
static func evaluate(function: Dictionary, max_steps := MAX_STEPS, cancelled := Callable()) -> Dictionary:
	var evaluator := Evaluator.new()
	evaluator.cancelled = cancelled
	return evaluator.run(function, max_steps)


## Latin-1 text of Lua string bytes (NUL has no place in an engine string and becomes U+2400).
static func latin1(raw: PackedByteArray) -> String:
	return Reader.latin1(raw)


class Reader extends RefCounted:
	var bytes := PackedByteArray()
	var at := 0
	var error := ""
	var code := R.SOURCE_INVALID
	var arguments: Array = []

	static func latin1(raw: PackedByteArray) -> String:
		var plain_ascii := true
		for value: int in raw:
			if value == 0 or value >= 0x80:
				plain_ascii = false
				break
		if plain_ascii:
			return raw.get_string_from_ascii()
		var text := ""
		for value: int in raw:
			text += String.chr(0x2400 if value == 0 else value)
		return text

	func fail(problem_code: String, message: String, args: Array = []) -> void:
		if error.is_empty():
			error = message
			code = problem_code
			arguments = args

	func take(length: int) -> PackedByteArray:
		if length < 0 or at + length > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script is truncated at byte %s.", [str(at)])
			return PackedByteArray()
		var piece := bytes.slice(at, at + length)
		at += length
		return piece

	func byte() -> int:
		if at + 1 > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script is truncated at byte %s.", [str(at)])
			return 0
		at += 1
		return bytes[at - 1]

	func integer() -> int:
		if at + 4 > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script is truncated at byte %s.", [str(at)])
			return 0
		var value := bytes.decode_s32(at)
		at += 4
		return value

	func count(limit: int) -> int:
		var value := integer()
		if error.is_empty() and (value < 0 or value > limit):
			fail(R.SOURCE_LIMIT, "The Phoenix script has a count outside its limit at byte %s.", [str(at)])
			return 0
		return value

	## Returns the Latin-1 text, or null for a zero length (Lua's absent string).
	func string() -> Variant:
		if at + 4 > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script is truncated at byte %s.", [str(at)])
			return null
		var length := bytes.decode_u32(at)
		at += 4
		if length == 0:
			return null
		if length > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script has an invalid string length at byte %s.", [str(at)])
			return null
		var raw := take(length)
		if not error.is_empty():
			return null
		if raw[length - 1] != 0:
			fail(R.SOURCE_INVALID, "The Phoenix script has a string that is not NUL terminated.")
			return null
		return latin1(raw.slice(0, length - 1))

	func number() -> float:
		if at + 8 > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script is truncated at byte %s.", [str(at)])
			return 0.0
		var value := bytes.decode_double(at)
		at += 8
		return value

	## Skips `n` whole 4-byte items after a bounds check.
	func skip_ints(n: int) -> void:
		if n < 0 or at + n * 4 > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script is truncated at byte %s.", [str(at)])
			return
		at += n * 4

	## `{source, line, nups, params, vararg, maxstack, constants, protos, code, line_count, locals,
	## upvalues}`. Line, local and upvalue tables are consumed and counted only.
	func function(depth: int) -> Dictionary:
		var result := {}
		if depth > MAX_DEPTH:
			fail(R.SOURCE_LIMIT, "The Phoenix script nests functions too deeply.")
			return result
		result.source = string()
		result.line = integer()
		result.nups = byte()
		result.params = byte()
		result.vararg = byte()
		result.maxstack = byte()
		if not error.is_empty():
			return result
		var lines := count(MAX_CODE)
		skip_ints(lines)
		result.line_count = lines
		var locals := count(MAX_CONSTANTS)
		for _index: int in locals:
			string()
			integer()
			integer()
			if not error.is_empty():
				return result
		result.locals = locals
		var upvalues := count(MAX_UPVALUES)
		for _index: int in upvalues:
			string()
			if not error.is_empty():
				return result
		result.upvalues = upvalues
		var constants: Array = []
		var constant_count := count(MAX_CONSTANTS)
		for _index: int in constant_count:
			var kind := byte()
			if not error.is_empty():
				return result
			if kind == 3:
				constants.append(number())
			elif kind == 4:
				constants.append(string())
			elif kind == 0:
				constants.append(null)
			else:
				fail(R.SOURCE_INVALID, "The Phoenix script has a constant of type %s.", [str(kind)])
			if not error.is_empty():
				return result
		result.constants = constants
		var protos: Array = []
		var proto_count := count(MAX_PROTOS)
		for _index: int in proto_count:
			protos.append(function(depth + 1))
			if not error.is_empty():
				return result
		result.protos = protos
		var instructions := count(MAX_CODE)
		var code := PackedInt64Array()
		if error.is_empty() and at + instructions * 4 > bytes.size():
			fail(R.SOURCE_INVALID, "The Phoenix script is truncated at byte %s.", [str(at)])
		if error.is_empty():
			code.resize(instructions)
			for index: int in instructions:
				code[index] = bytes.decode_u32(at + index * 4)
			at += instructions * 4
		result.code = code
		return result


## Ordered Lua table; a later assignment replaces. Keys keep their Lua type (float, text, bool, nil).
class LTable extends RefCounted:
	var keys: Array = []
	var values: Array = []
	var _index := {}

	static func _slot(key: Variant) -> Variant:
		match typeof(key):
			TYPE_FLOAT, TYPE_STRING, TYPE_BOOL, TYPE_NIL:
				return key
		return [typeof(key), var_to_str(key)]

	func put(key: Variant, value: Variant) -> void:
		var slot: Variant = _slot(key)
		if _index.has(slot):
			values[_index[slot]] = value
			return
		_index[slot] = keys.size()
		keys.append(key)
		values.append(value)

	func fetch(key: Variant) -> Variant:
		var slot: Variant = _slot(key)
		if _index.has(slot):
			return values[_index[slot]]
		return null


class Evaluator extends RefCounted:
	var regs: Array = []
	var constants: Array = []
	var failure := ""
	var diagnostics: Array = []
	var cancelled := Callable()
	## Remaining plain-data nodes for the whole evaluation: shared tables cannot multiply the work.
	var budget: Array = [MAX_PLAIN_NODES]

	func run(function: Dictionary, max_steps: int) -> Dictionary:
		constants = function.constants
		var code: PackedInt64Array = function.code
		var protos: Array = function.protos
		var globals_table := LTable.new()
		var assigned := LTable.new()
		regs.resize(REGISTERS)
		var pc := 0
		var steps := 0
		while pc < code.size() and failure.is_empty():
			steps += 1
			if steps > max_steps:
				diagnostics.append("step limit")
				break
			if steps % 4096 == 0 and cancelled.is_valid() and bool(cancelled.call()):
				return R.fail(R.SOURCE_INVALID, "The import was cancelled.", "source", STEP)
			var word := code[pc]
			var op := word & 0x3F
			var a := (word >> 24) & 0xFF
			var b := (word >> 15) & 0x1FF
			var c := (word >> 6) & 0x1FF
			var bx := (word >> 6) & 0x3FFFF
			pc += 1
			match op:
				Op.MOVE:
					_store(a, _reg(b))
				Op.LOADK:
					_store(a, _constant(bx))
				Op.LOADBOOL:
					_store(a, b != 0)
					if c != 0:
						pc += 1
				Op.LOADNIL:
					if b + 1 > REGISTERS:
						_bad("LOADNIL range", pc - 1)
					else:
						for index: int in range(a, b + 1):
							regs[index] = null
				Op.GETGLOBAL:
					var name: Variant = _constant(bx)
					var found: Variant = globals_table.fetch(name)
					_store(a, found if found != null else _symbol(_text(name)))
				Op.SETGLOBAL:
					globals_table.put(_constant(bx), _reg(a))
				Op.NEWTABLE:
					_store(a, LTable.new())
				Op.SETTABLE:
					var target: Variant = _reg(a)
					if target is LTable:
						(target as LTable).put(_rk(b), _rk(c))
					elif _is_symbol(target):
						assigned.put("%s.%s" % [target["$symbol"], _text(_rk(b))], _rk(c))
					else:
						diagnostics.append("SETTABLE on non-table at pc %d" % (pc - 1))
				Op.GETTABLE:
					var source: Variant = _reg(b)
					var key: Variant = _rk(c)
					if source is LTable:
						_store(a, (source as LTable).fetch(key))
					elif _is_symbol(source):
						var path := "%s.%s" % [source["$symbol"], _text(key)]
						if path.length() > MAX_SYMBOL_PATH:
							_bad("symbol path length", pc - 1)
						else:
							_store(a, _symbol(path))
					else:
						_store(a, null)
						diagnostics.append("GETTABLE on non-table at pc %d" % (pc - 1))
				Op.SETLIST, Op.SETLISTO:
					var list: Variant = _reg(a)
					var n := bx % FIELDS_PER_FLUSH + 1
					var base := bx - bx % FIELDS_PER_FLUSH
					if not list is LTable:
						diagnostics.append("SETLIST on non-table at pc %d" % (pc - 1))
						break
					for index: int in range(1, n + 1):
						(list as LTable).put(float(base + index), _reg(a + index))
				Op.UNM:
					var operand: Variant = _reg(b)
					_store(a, -float(operand) if typeof(operand) == TYPE_FLOAT else {"$expr": "-", "of": plain(operand, 0, budget)})
				Op.ADD, Op.SUB, Op.MUL, Op.DIV:
					var left: Variant = _rk(b)
					var right: Variant = _rk(c)
					if typeof(left) == TYPE_FLOAT and typeof(right) == TYPE_FLOAT:
						var x: float = left
						var y: float = right
						var value := NAN
						match op:
							Op.ADD:
								value = x + y
							Op.SUB:
								value = x - y
							Op.MUL:
								value = x * y
							Op.DIV:
								value = x / y if y != 0.0 else NAN
						_store(a, value)
					else:
						_store(a, {"$expr": _OPNAMES[op], "args": [plain(left, 0, budget), plain(right, 0, budget)]})
				Op.CLOSURE:
					if bx >= protos.size():
						_bad("CLOSURE prototype", pc - 1)
					else:
						_store(a, {"$closure": pc - 1})
						pc += int(protos[bx].get("nups", 0))
				Op.RETURN:
					break
				_:
					diagnostics.append("stopped at unsupported %s (pc %d)" % [
						_OPNAMES[op] if op < _OPNAMES.size() else "OP%d" % op, pc - 1])
					break
		if not failure.is_empty():
			return R.fail(R.SOURCE_INVALID, "The Phoenix script has an out-of-range operand: %s.", "source", STEP, [failure])
		var globals_plain: Variant = plain(globals_table, 0, budget)
		var assigned_plain: Variant = plain(assigned, 0, budget)
		if int(budget[0]) <= 0:
			return R.fail(R.SOURCE_LIMIT, "The Phoenix script builds more data than an aircraft definition needs.", "source", STEP)
		return R.ok({globals = globals_plain, assigned = assigned_plain, diagnostics = diagnostics})

	func _bad(what: String, pc: int) -> void:
		if failure.is_empty():
			failure = "%s at pc %d" % [what, pc]

	func _reg(index: int) -> Variant:
		if index < 0 or index >= REGISTERS:
			_bad("register %d" % index, -1)
			return null
		return regs[index]

	func _store(index: int, value: Variant) -> void:
		if index < 0 or index >= REGISTERS:
			_bad("register %d" % index, -1)
			return
		regs[index] = value

	func _constant(index: int) -> Variant:
		if index < 0 or index >= constants.size():
			_bad("constant %d" % index, -1)
			return null
		return constants[index]

	func _rk(index: int) -> Variant:
		return _constant(index - MAXSTACK) if index >= MAXSTACK else _reg(index)

	static func _symbol(path: String) -> Dictionary:
		return {"$symbol": path}

	static func _is_symbol(value: Variant) -> bool:
		return value is Dictionary and (value as Dictionary).has("$symbol")

	static func _text(value: Variant) -> String:
		return value if typeof(value) == TYPE_STRING else str(value)

	## Plain data for an evaluated value. Cyclic tables stop at `MAX_PLAIN_DEPTH`; `budget[0]` caps
	## the total number of nodes visited, so a table shared many times cannot explode the work.
	static func plain(value: Variant, depth := 0, budget: Array = [MAX_PLAIN_NODES]) -> Variant:
		budget[0] = int(budget[0]) - 1
		if int(budget[0]) <= 0:
			return "<limit>"
		if depth > MAX_PLAIN_DEPTH:
			return "<depth>"
		if value is LTable:
			var table: LTable = value
			var listed := not table.keys.is_empty()
			for index: int in table.keys.size():
				if typeof(table.keys[index]) != TYPE_FLOAT or table.keys[index] != float(index + 1):
					listed = false
					break
			if listed:
				var items: Array = []
				for item: Variant in table.values:
					items.append(plain(item, depth + 1, budget))
				return items
			var out := {}
			for index: int in table.keys.size():
				var key: Variant = table.keys[index]
				var name: String
				match typeof(key):
					TYPE_STRING:
						name = key
					TYPE_FLOAT:
						name = str(int(key)) if is_finite(key) and key == floorf(key) and absf(key) < 9.0e15 else str(key)
					TYPE_BOOL:
						name = "True" if key else "False"
					TYPE_NIL:
						name = "None"
					_:
						name = str(key)
				out[name] = plain(table.values[index], depth + 1, budget)
			return out
		if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value) and absf(value) < 9007199254740992.0:
			return int(value)
		return value
