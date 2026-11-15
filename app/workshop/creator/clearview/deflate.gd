extends RefCounted
## RFC 1951 raw DEFLATE, with exact compressed consumption and a caller-bounded output.
## No native decoder is called on malformed input. Stored, fixed and dynamic blocks are supported.
const R := preload("res://workshop/creator/result.gd")
const LENGTH_BASE := [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258]
const LENGTH_EXTRA := [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]
const DIST_BASE := [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577]
const DIST_EXTRA := [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]
const ORDER := [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]
const MAX_BLOCKS := 8192
const MAX_WORK := 32 * 1024 * 1024
var _data := PackedByteArray()
var _bit := 0
var _bad := false
var _output := PackedByteArray()
var _written := 0
var _cancel := Callable()
var _fixed_trees: Array = []
var _work := 0
var _limit := false

static func decode(data: PackedByteArray, expected: int, cancel := Callable()) -> Dictionary:
	if expected < 0 or expected > 32 * 1024 * 1024:
		return R.fail(R.SOURCE_LIMIT, "A ZIP member exceeds the import size limit.", "source", "import")
	var reader := new()
	reader._data = data
	reader._output.resize(expected)
	reader._cancel = cancel
	return reader._run()

func _run() -> Dictionary:
	var final := false
	var blocks := 0
	while not final and not _bad:
		blocks += 1
		if blocks > MAX_BLOCKS:
			_limit = true
			_bad = true
			break
		if _cancel.is_valid() and bool(_cancel.call()):
			return R.fail(R.SOURCE_INVALID, "The import was cancelled.", "source", "import")
		final = _bits(1) == 1
		var kind := _bits(2)
		if _bad:
			break
		if kind == 0:
			_bit = (_bit + 7) & ~7
			var count := _bits(16)
			var inverse := _bits(16)
			if _bad or (count ^ inverse) != 65535 or _written + count > _output.size() or _bit / 8 + count > _data.size():
				_bad = true
				break
			for index: int in count:
				_output[_written + index] = _data[_bit / 8 + index]
			_written += count
			_bit += count * 8
		elif kind == 1 or kind == 2:
			var trees: Array = _fixed() if kind == 1 else _dynamic()
			if _bad or trees.size() != 2:
				_bad = true
				break
			_codes(trees[0], trees[1])
		else:
			_bad = true
	if _limit:
		return R.fail(R.SOURCE_LIMIT, "The ZIP member exceeds the decompression work limit.", "source", "import")
	if _bad or _written != _output.size() or (_bit + 7) / 8 != _data.size():
		return R.fail(R.SOURCE_INVALID, "The ZIP member has invalid, truncated or overlong compressed data.", "source", "import")
	return R.ok(_output)

func _bits(count: int) -> int:
	_work += count
	if _work > MAX_WORK:
		_limit = true
		_bad = true
	if _bad or _bit + count > _data.size() * 8:
		_bad = true
		return 0
	var value := 0
	for offset: int in count:
		value |= ((_data[_bit >> 3] >> (_bit & 7)) & 1) << offset
		_bit += 1
	return value

## Canonical Huffman codes, indexed by (1 << bit length) | wire-order code.
func _tree(lengths: Array, max_bits: int, allow_empty := false) -> Dictionary:
	_work += lengths.size() * max_bits
	if _work > MAX_WORK:
		_limit = true
		_bad = true
		return {}
	var counts: Array[int] = []
	counts.resize(max_bits + 1)
	counts.fill(0)
	for length: int in lengths:
		if length < 0 or length > max_bits:
			_bad = true
			return {}
		counts[length] += 1
	var total := lengths.size() - counts[0]
	if total == 0:
		if not allow_empty:
			_bad = true
		return {}
	var left := 1
	for bits: int in range(1, max_bits + 1):
		left = (left << 1) - counts[bits]
		if left < 0:
			_bad = true
			return {}
	# RFC 1951 allows the single-code literal/distance alphabet. Other incomplete trees are invalid.
	if left != 0 and not (total == 1 and counts[1] == 1):
		_bad = true
		return {}
	var next: Array[int] = []
	next.resize(max_bits + 1)
	next.fill(0)
	var code := 0
	for bits: int in range(1, max_bits + 1):
		code = (code + (counts[bits - 1] if bits > 1 else 0)) << 1
		next[bits] = code
	var result := {}
	for symbol: int in lengths.size():
		var length: int = lengths[symbol]
		if length == 0:
			continue
		var reversed := 0
		var number := next[length]
		for bit: int in length:
			reversed = (reversed << 1) | ((number >> bit) & 1)
		result[(1 << length) | reversed] = symbol
		next[length] += 1
	return result

func _symbol(tree: Dictionary, max_bits := 15) -> int:
	var code := 0
	for bits: int in range(1, max_bits + 1):
		code |= _bits(1) << (bits - 1)
		if _bad:
			return -1
		var key := (1 << bits) | code
		if tree.has(key):
			return int(tree[key])
	_bad = true
	return -1

func _fixed() -> Array:
	if not _fixed_trees.is_empty():
		return _fixed_trees
	var literal: Array = []
	for index: int in 288:
		literal.append(8 if index < 144 else (9 if index < 256 else (7 if index < 280 else 8)))
	var distance: Array = []
	distance.resize(32)
	distance.fill(5)
	_fixed_trees = [_tree(literal, 15), _tree(distance, 15)]
	return _fixed_trees

func _dynamic() -> Array:
	var nl := _bits(5) + 257
	var nd := _bits(5) + 1
	var nc := _bits(4) + 4
	if _bad or nl > 286:
		_bad = true
		return []
	var lengths: Array = []
	lengths.resize(19)
	lengths.fill(0)
	for index: int in nc:
		lengths[ORDER[index]] = _bits(3)
	var code_tree := _tree(lengths, 7)
	# A code-length alphabet must be complete, including the one-symbol case.
	if code_tree.size() == 1:
		_bad = true
	lengths = []
	while lengths.size() < nl + nd and not _bad:
		var symbol := _symbol(code_tree, 7)
		if symbol >= 0 and symbol <= 15:
			lengths.append(symbol)
		elif symbol >= 16 and symbol <= 18:
			if symbol == 16 and lengths.is_empty():
				_bad = true
				break
			var count := _bits(2 if symbol == 16 else (3 if symbol == 17 else 7)) + (3 if symbol < 18 else 11)
			var value: int = lengths[-1] if symbol == 16 else 0
			if lengths.size() + count > nl + nd:
				_bad = true
				break
			for index: int in count:
				lengths.append(value)
		else:
			_bad = true
	if _bad or lengths.size() != nl + nd or lengths[256] == 0:
		_bad = true
		return []
	return [_tree(lengths.slice(0, nl), 15), _tree(lengths.slice(nl), 15, true)]

func _codes(literal: Dictionary, distance: Dictionary) -> void:
	var steps := 0
	while not _bad:
		steps += 1
		if steps % 4096 == 0 and _cancel.is_valid() and bool(_cancel.call()):
			_bad = true
			return
		var symbol := _symbol(literal)
		if symbol < 0:
			return
		if symbol < 256:
			if _written == _output.size():
				_bad = true
				return
			_output[_written] = symbol
			_written += 1
		elif symbol == 256:
			return
		elif symbol <= 285:
			var index := symbol - 257
			var length: int = LENGTH_BASE[index] + _bits(LENGTH_EXTRA[index])
			var ds := _symbol(distance)
			if _bad or ds < 0 or ds > 29:
				_bad = true
				return
			var gap: int = DIST_BASE[ds] + _bits(DIST_EXTRA[ds])
			if _bad or gap > _written or _written + length > _output.size():
				_bad = true
				return
			_work += length
			if _work > MAX_WORK:
				_limit = true
				_bad = true
				return
			for offset: int in length:
				_output[_written] = _output[_written - gap]
				_written += 1
		else:
			_bad = true
