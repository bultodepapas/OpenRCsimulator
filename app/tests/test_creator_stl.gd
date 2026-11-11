extends SceneTree
## AC-02: strict bounded STL reader. Every fixture is generated here.
const StlReader := preload("res://workshop/creator/stl_reader.gd")
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")

# Tetrahedron A(0,0,0) B(1,0,0) C(0,2,0) D(0,0,3), outward winding. Each row: normal, three vertices.
const TETRA := [
	[0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 1.0, 0.0, 0.0],
	[0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 3.0],
	[-1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 0.0, 2.0, 0.0],
	[0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 3.0],
]
const TETRA_POSITIONS := [
	0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 3.0,
	0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 0.0, 2.0, 0.0,
	1.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 3.0,
]
const UNIT := [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
const UNIT_FACET := "facet normal 0 0 1 outer loop vertex 0 0 0 vertex 1 0 0 vertex 0 1 0 endloop endfacet\n"

var failures := 0
var checks := 0


func _initialize() -> void:
	binary_cases()
	ascii_layout_cases()
	ascii_number_cases()
	ascii_grammar_cases()
	ascii_text_cases()
	geometry_cases()
	size_cases()
	timing()
	print("Creator STL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func binary_cases() -> void:
	var tetra := binary_stl(TETRA, "tetra unit test")
	var read: Dictionary = StlReader.read(tetra)
	check("binary tetra ok", read.ok)
	if read.ok:
		var value: Dictionary = read.value
		check("binary format", value.format == "stl-binary")
		check("binary name is the printable header", value.name == "tetra unit test")
		check("binary count", value.triangle_count == 4)
		check("binary positions in file order", value.positions == PackedFloat32Array(TETRA_POSITIONS))
		check("binary bounds", value.bounds_min == PackedFloat64Array([0.0, 0.0, 0.0])
			and value.bounds_max == PackedFloat64Array([1.0, 2.0, 3.0]))
		check("binary counters are zero", value.dropped_degenerate == 0 and value.inconsistent_normals == 0
			and value.nonzero_attributes == 0)
		check("binary clean file has no diagnostics", read.diagnostics.is_empty())

	var solid_header: Dictionary = StlReader.read(binary_stl(TETRA, "solid looks_like_ascii"))
	check("binary with solid header is binary", solid_header.ok and solid_header.value.format == "stl-binary"
		and solid_header.value.triangle_count == 4)

	check("binary one byte short", code(StlReader.read(tetra.slice(0, tetra.size() - 1))) == R.SOURCE_INVALID)
	var longer := tetra.duplicate()
	longer.append(0)
	check("binary one byte extra", code(StlReader.read(longer)) == R.SOURCE_INVALID)
	var short_solid := binary_stl(TETRA, "solid looks_like_ascii")
	check("truncated binary with solid header", code(StlReader.read(short_solid.slice(0, short_solid.size() - 1)))
		== R.SOURCE_INVALID)

	var absurd := PackedByteArray()
	absurd.resize(84)
	absurd.encode_u32(80, 0xFFFFFFFF)
	check("absurd count in a header-only file", code(StlReader.read(absurd)) == R.SOURCE_INVALID)
	absurd.encode_u32(80, Limits.TRIANGLES + 1)
	check("header-only over-limit count is a length mismatch", code(StlReader.read(absurd)) == R.SOURCE_INVALID)
	absurd.encode_u32(80, 0)
	check("binary count zero", code(StlReader.read(absurd)) == R.SOURCE_INVALID)
	check("short non-STL bytes", code(StlReader.read(PackedByteArray([1, 2, 3, 4]))) == R.SOURCE_INVALID)

	# Consistent length and limit + 1 facets: refused by count before any facet is read.
	var over := PackedByteArray()
	over.resize(84 + 50 * (Limits.TRIANGLES + 1))
	over.encode_u32(80, Limits.TRIANGLES + 1)
	check("binary facet limit + 1", code(StlReader.read(over)) == R.SOURCE_LIMIT)

	var nan_vertex := TETRA.duplicate(true)
	nan_vertex[2][7] = NAN
	check("binary NaN vertex", code(StlReader.read(binary_stl(nan_vertex))) == R.SOURCE_INVALID)
	var inf_vertex := TETRA.duplicate(true)
	inf_vertex[3][11] = -INF
	check("binary infinite vertex", code(StlReader.read(binary_stl(inf_vertex))) == R.SOURCE_INVALID)
	var nan_normal := TETRA.duplicate(true)
	nan_normal[0][1] = NAN
	check("binary NaN normal", code(StlReader.read(binary_stl(nan_normal))) == R.SOURCE_INVALID)

	var attributed: Dictionary = StlReader.read(binary_stl(TETRA, "", [0, 0x7FFF, 0, 1]))
	check("attributes counted", attributed.ok and attributed.value.nonzero_attributes == 2
		and attributed.value.triangle_count == 4)
	check("attributes reported once as info", count_diagnostics(attributed, R.SOURCE_UNSUPPORTED, R.SEVERITY_INFO) == 1
		and attributed.diagnostics.size() == 1)


func ascii_layout_cases() -> void:
	var expected := PackedFloat32Array(TETRA_POSITIONS)
	var canonical: Dictionary = StlReader.read(tetra_text("tetra").to_utf8_buffer())
	check("ascii canonical ok", canonical.ok)
	if canonical.ok:
		var value: Dictionary = canonical.value
		check("ascii format", value.format == "stl-ascii")
		check("ascii name", value.name == "tetra")
		check("ascii count", value.triangle_count == 4)
		check("ascii positions", value.positions == expected)
		check("ascii bounds", value.bounds_min == PackedFloat64Array([0.0, 0.0, 0.0])
			and value.bounds_max == PackedFloat64Array([1.0, 2.0, 3.0]))
		check("ascii matches binary", value.positions == StlReader.read(binary_stl(TETRA)).value.positions)
		check("ascii clean file has no diagnostics", canonical.diagnostics.is_empty())

	var words := tetra_words()
	var layouts := {
		"one token per line": "solid t\n" + "\n".join(words) + "\nendsolid t\n",
		"all facets on one line": "solid t\n" + " ".join(words) + "\nendsolid t\n",
		"endsolid on the facet line": "solid t\n" + " ".join(words) + " endsolid t\n",
		"CRLF and tabs": "solid t\r\n\t" + "\t\r\n\t".join(words) + "\r\nendsolid t\r\n",
		"mixed runs of whitespace": " \r\n\t solid t\n\n" + " \t \r\n  ".join(words) + "\n\n  endsolid\n\n \t\n",
		"no final line feed": tetra_text("t").strip_edges(),
		"empty name": tetra_text("").replace("solid \n", "solid\n"),
	}
	for label: String in layouts:
		var read: Dictionary = StlReader.read((layouts[label] as String).to_utf8_buffer())
		check("ascii layout: " + label, read.ok and read.value.triangle_count == 4 and read.value.positions == expected)

	var named: Dictionary = StlReader.read(tetra_text(" \tÑandú 雪\tmodel v2 ").to_utf8_buffer())
	check("ascii name with spaces and UTF-8", named.ok and named.value.name == "Ñandú 雪\tmodel v2")
	var unnamed: Dictionary = StlReader.read((layouts["empty name"] as String).to_utf8_buffer())
	check("ascii empty name is empty", unnamed.ok and unnamed.value.name == "")

	var two: Dictionary = StlReader.read((tetra_text("first") + tetra_text("second")).to_utf8_buffer())
	check("two solids merged", two.ok and two.value.triangle_count == 8 and two.value.name == "first"
		and two.value.positions.slice(36) == expected and two.value.positions.slice(0, 36) == expected)

	var block := "solid s\n" + UNIT_FACET + "endsolid s\n"
	var most: Dictionary = StlReader.read(block.repeat(Limits.STL_ASCII_SOLIDS).to_utf8_buffer())
	check("solid limit accepted", most.ok and most.value.triangle_count == Limits.STL_ASCII_SOLIDS)
	check("solid limit + 1", code(StlReader.read(block.repeat(Limits.STL_ASCII_SOLIDS + 1).to_utf8_buffer()))
		== R.SOURCE_LIMIT)


func ascii_number_cases() -> void:
	# Spellings with independently known values, as float32.
	var accepted := {
		"1": 1.0, "+1": 1.0, "-1": -1.0, "1.": 1.0, ".5": 0.5, "-.5": -0.5, "+.5e-3": 0.0005,
		"1.0e+00": 1.0, "2E0": 2.0, "+1.5e+001": 15.0, "1e2": 100.0, "1E+2": 100.0, "0.25e1": 2.5,
		"007": 7.0, "0": 0.0, "-0.0": 0.0, "1e-999": 0.0, "0e999": 0.0, "1e+0000000000000000000000002": 100.0,
		"1.2345678901234567": 1.2345678901234567, "-1.2345678901234567e+001": -12.345678901234567,
		"123456789012345678901234567890": 1.2345678901234568e29, "3.4028234e38": 3.4028234e38,
		"1e-45": 1e-45, "1e38": 1e38, "0.1e39": 1e38, "1e-30": 1e-30,
	}
	# More than 18 mantissa digits: the engine parser alone would return zero for the first two.
	accepted["0." + "0".repeat(20) + "1"] = 1e-21
	accepted["0." + "0".repeat(43) + "1e45"] = 10.0
	accepted["1" + "0".repeat(38) + "e-37"] = 10.0
	accepted["0".repeat(30) + "2.5"] = 2.5
	for token: String in accepted:
		var rounded := PackedFloat32Array([accepted[token]])
		var read: Dictionary = StlReader.read(number_text(token).to_utf8_buffer())
		check("number accepted " + token, read.ok and read.value.positions[3] == rounded[0])
		var slow: Dictionary = StlReader.read(number_text(token, true).to_utf8_buffer())
		check("number accepted on the checked path " + token, slow.ok and slow.value.positions[3] == rounded[0])

	for token: String in ["nan", "NaN", "inf", "-inf", "Infinity", "1e999", "-1e999", "1e39", "0x10", "1.5abc",
			"1e", "1e+", "1e-", "e5", ".", "+", "-", "+-1", "--1", "1.2.3", "1,5", "1.5f", "1d5", "1_0", "0b1",
			"1e5.0", "1 e5", "１", "vertex", "1e99999999999999999999999999", "9".repeat(70), "1e+100", "1e0100"]:
		check("number refused " + token, code(StlReader.read(number_text(token).to_utf8_buffer())) == R.SOURCE_INVALID)
		check("number refused on the checked path " + token,
			code(StlReader.read(number_text(token, true).to_utf8_buffer())) == R.SOURCE_INVALID)

	var normal_text := "solid n\nfacet normal 0 0 nan outer loop vertex 0 0 0 vertex 1 0 0 vertex 0 1 0 endloop endfacet\nendsolid\n"
	check("nan normal refused", code(StlReader.read(normal_text.to_utf8_buffer())) == R.SOURCE_INVALID)
	check("overflowing normal refused", code(StlReader.read(normal_text.replace("nan", "1e39").to_utf8_buffer()))
		== R.SOURCE_INVALID)


func ascii_grammar_cases() -> void:
	var good := tetra_text("t")
	check("grammar baseline", StlReader.read(good.to_utf8_buffer()).ok)
	var vertex_line := "      vertex 0 2 0\n"
	var cases := {
		"misspelled keyword": replace_first(good, "outer loop", "outer lop"),
		"unknown keyword": replace_first(good, "endloop", "endlop"),
		"upper-case facet": replace_first(good, "facet normal", "FACET normal"),
		"capitalized vertex": replace_first(good, "vertex", "Vertex"),
		"upper-case solid": replace_first(good, "solid t", "SOLID t"),
		"upper-case endsolid": replace_first(good, "endsolid", "ENDSOLID"),
		"solid glued to name": replace_first(good, "solid t", "solidt"),
		"missing vertex": replace_first(good, vertex_line, ""),
		"four vertices": replace_first(good, vertex_line, vertex_line + vertex_line),
		"vertex with two numbers": replace_first(good, "vertex 0 2 0", "vertex 0 2"),
		"vertex with four numbers": replace_first(good, "vertex 0 2 0", "vertex 0 2 0 0"),
		"normal with two numbers": replace_first(good, "normal 0 0 -1", "normal 0 0"),
		"missing normal keyword": replace_first(good, "facet normal", "facet"),
		"missing outer loop": replace_first(good, "    outer loop\n", ""),
		"missing endloop": replace_first(good, "    endloop\n", ""),
		"missing endfacet": replace_first(good, "  endfacet\n", ""),
		"missing endsolid": replace_first(good, "endsolid t\n", ""),
		"ends inside a facet": good.substr(0, good.find("endloop")),
		"ends inside a vertex": good.substr(0, good.find("vertex 0 2 0") + 8),
		"trailing garbage": good + "garbage\n",
		"trailing facet": good + UNIT_FACET,
		"trailing number": good + "0\n",
		"trailing garbage after blank lines": good + "\n\n  x",
		"byte order mark": "﻿" + good,
		"solid without endsolid": "solid t\n",
		"vertical tab separator": replace_first(good, "outer loop", "outer\u000Bloop"),
		"no-break space separator": replace_first(good, "outer loop", "outer loop"),
	}
	for label: String in cases:
		check("grammar refused: " + label, code(StlReader.read((cases[label] as String).to_utf8_buffer()))
			== R.SOURCE_INVALID)
	check("solid without facets", code(StlReader.read("solid t\nendsolid t\n".to_utf8_buffer())) == R.SOURCE_INVALID)

	var missing: Dictionary = StlReader.read((cases["missing vertex"] as String).to_utf8_buffer())
	check("failure names the line", not missing.ok and (missing.diagnostics[0].arguments as Array).has("6"))
	check("failure is one error", not missing.has("value") and missing.diagnostics.size() == 1
		and missing.diagnostics[0].severity == R.SEVERITY_ERROR)
	var late: Dictionary = StlReader.read(("solid t\n" + UNIT_FACET.repeat(9000) + "bogus\nendsolid\n").to_utf8_buffer())
	check("line number survives chunk boundaries", code(late) == R.SOURCE_INVALID
		and (late.diagnostics[0].arguments as Array).has("9002"))


func ascii_text_cases() -> void:
	var good := tetra_text("t").to_utf8_buffer()
	var with_nul := good.duplicate()
	with_nul[good.size() - 3] = 0
	check("NUL byte", code(StlReader.read(with_nul)) == R.SOURCE_INVALID)
	var nul_in_name := "solid a".to_utf8_buffer()
	nul_in_name.append(0)
	nul_in_name.append_array(good.slice(7))
	check("NUL byte in the name", code(StlReader.read(nul_in_name)) == R.SOURCE_INVALID)

	var sequences := {
		"lone 0xFF": [0xFF], "lone continuation": [0x80], "overlong NUL": [0xC0, 0x80], "overlong slash": [0xE0, 0x80, 0xAF],
		"surrogate": [0xED, 0xA0, 0x80], "above U+10FFFF": [0xF4, 0x90, 0x80, 0x80], "five-byte form": [0xF8, 0x88, 0x80, 0x80, 0x80],
		"truncated two-byte": [0xC3], "truncated three-byte": [0xE2, 0x82], "bad continuation": [0xE2, 0x28, 0xA1],
	}
	for label: String in sequences:
		var bad := "solid ".to_utf8_buffer()
		bad.append_array(PackedByteArray(sequences[label]))
		bad.append_array(good.slice(7))
		check("invalid UTF-8: " + label, code(StlReader.read(bad)) == R.SOURCE_INVALID)
		var at_end := good.duplicate()
		at_end.append_array(PackedByteArray(sequences[label]))
		check("invalid UTF-8 at the end: " + label, code(StlReader.read(at_end)) == R.SOURCE_INVALID)
	var wide: Dictionary = StlReader.read(tetra_text("é € ퟿  ￿ \U010000 \U01F600 \U10FFFF").to_utf8_buffer())
	check("valid multi-byte UTF-8", wide.ok and wide.value.name == "é € ퟿  ￿ \U010000 \U01F600 \U10FFFF")

	var limit: int = Limits.STL_ASCII_LINE_BYTES
	var body := UNIT_FACET + "endsolid\n"
	check("line at the limit", StlReader.read(("solid " + "a".repeat(limit - 6) + "\n" + body).to_utf8_buffer()).ok)
	check("line over the limit", code(StlReader.read(("solid " + "a".repeat(limit - 5) + "\n" + body).to_utf8_buffer()))
		== R.SOURCE_LIMIT)
	var pairs := (limit - 6) >> 1
	check("multi-byte line at the limit", pairs * 2 + 6 == limit
		and StlReader.read(("solid " + "é".repeat(pairs) + "\n" + body).to_utf8_buffer()).ok)
	check("multi-byte line over the limit", code(StlReader.read(("solid " + "é".repeat(pairs) + "a\n"
		+ body).to_utf8_buffer())) == R.SOURCE_LIMIT)
	check("line longer than a chunk", code(StlReader.read(("solid " + "a".repeat(5 * limit) + "\n" + body).to_utf8_buffer()))
		== R.SOURCE_LIMIT)
	check("long line without line feed", code(StlReader.read(("solid " + "a".repeat(5 * limit)).to_utf8_buffer()))
		== R.SOURCE_LIMIT)
	check("over-long final line", code(StlReader.read(("solid t\n" + body + " ".repeat(limit + 1)).to_utf8_buffer()))
		== R.SOURCE_LIMIT)
	check("over-long number token", code(StlReader.read(number_text("1".repeat(limit + 1)).to_utf8_buffer()))
		== R.SOURCE_LIMIT)

	# 200,001 facets: refused at the facet keyword after the limit, without reading further.
	var many := ("solid m\n" + UNIT_FACET.repeat(Limits.TRIANGLES + 1) + "endsolid\n").to_utf8_buffer()
	var started := Time.get_ticks_msec()
	check("ascii facet limit + 1", code(StlReader.read(many)) == R.SOURCE_LIMIT)
	print("Creator STL timing: ASCII %d one-line facets (%d bytes) refused at the limit in %d ms"
		% [Limits.TRIANGLES + 1, many.size(), Time.get_ticks_msec() - started])


func geometry_cases() -> void:
	var duplicate_vertex := [0.0, 0.0, 1.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 9.0, 9.0, 9.0]
	var collinear := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0]
	var point := [0.0, 0.0, 0.0, 7.0, 7.0, 7.0, 7.0, 7.0, 7.0, 7.0, 7.0, 7.0]
	var mixed: Dictionary = StlReader.read(binary_stl([TETRA[0], duplicate_vertex, TETRA[1], collinear, TETRA[2], TETRA[3], point]))
	check("degenerate facets dropped, rest kept", mixed.ok and mixed.value.triangle_count == 4
		and mixed.value.dropped_degenerate == 3 and mixed.value.positions == PackedFloat32Array(TETRA_POSITIONS))
	check("dropped facets do not widen the bounds", mixed.ok and mixed.value.bounds_max == PackedFloat64Array([1.0, 2.0, 3.0]))
	check("dropped facets reported once as a warning", count_diagnostics(mixed, R.SOURCE_INVALID, R.SEVERITY_WARNING) == 1
		and mixed.diagnostics.size() == 1 and mixed.diagnostics[0].arguments == ["3"])
	check("all facets degenerate (binary)", code(StlReader.read(binary_stl([duplicate_vertex, collinear, point]))) == R.SOURCE_INVALID)
	var flat_text := "solid d\nfacet normal 0 0 1 outer loop vertex 1 1 1 vertex 1 1 1 vertex 2 3 4 endloop endfacet\n"
	check("all facets degenerate (ascii)", code(StlReader.read((flat_text + "endsolid\n").to_utf8_buffer())) == R.SOURCE_INVALID)
	var kept_text: Dictionary = StlReader.read((flat_text + UNIT_FACET + "endsolid\n").to_utf8_buffer())
	check("ascii degenerate dropped", kept_text.ok and kept_text.value.triangle_count == 1
		and kept_text.value.dropped_degenerate == 1 and kept_text.value.bounds_max == PackedFloat64Array([1.0, 1.0, 0.0]))

	# A thin sliver has a non-zero cross product and stays.
	var sliver := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 1e-30, 0.0]
	var thin: Dictionary = StlReader.read(binary_stl([sliver]))
	check("thin non-zero triangle kept", thin.ok and thin.value.triangle_count == 1 and thin.value.dropped_degenerate == 0)

	var flipped := TETRA.duplicate(true)
	flipped[0][2] = 1.0
	flipped[3] = [-6.0, -3.0, -2.0, 1.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 3.0]
	var against: Dictionary = StlReader.read(binary_stl(flipped))
	check("flipped normals counted, winding kept", against.ok and against.value.inconsistent_normals == 2
		and against.value.positions == PackedFloat32Array(TETRA_POSITIONS))
	check("flipped normals reported once as a warning", count_diagnostics(against, R.SOURCE_INVALID, R.SEVERITY_WARNING) == 1
		and against.diagnostics.size() == 1 and against.diagnostics[0].arguments == ["2"])
	var perpendicular := [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
	var sideways: Dictionary = StlReader.read(binary_stl([perpendicular, UNIT]))
	check("zero and perpendicular normals are not counted", sideways.ok and sideways.value.inconsistent_normals == 0)
	var ascii_flipped: Dictionary = StlReader.read(("solid f\n" + UNIT_FACET.replace("normal 0 0 1", "normal 0 0 -1")
		+ UNIT_FACET + "endsolid\n").to_utf8_buffer())
	check("ascii flipped normal counted", ascii_flipped.ok and ascii_flipped.value.inconsistent_normals == 1)

	# Extreme finite scale. Positions are float32 but the cross product is float64, so 1e-30 does
	# not underflow to zero and 1e30 does not overflow: both are kept.
	var scales := {"1e-30": 1e-30, "1e30": 1e30, "smallest float32": 1.0e-45, "3e38": 3.0e38}
	for label: String in scales:
		var s: float = PackedFloat32Array([scales[label]])[0]
		var scaled := [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, s, 0.0]
		var extreme: Dictionary = StlReader.read(binary_stl([scaled]))
		check("extreme scale kept: " + label, extreme.ok and extreme.value.triangle_count == 1
			and extreme.value.dropped_degenerate == 0 and extreme.value.bounds_max == PackedFloat64Array([s, s, 0.0])
			and is_finite(extreme.value.bounds_max[0]) and s > 0.0)
	var far := [0.0, 0.0, 0.0, -3.0e38, -3.0e38, -3.0e38, 3.0e38, -3.0e38, 3.0e38, -3.0e38, 3.0e38, 3.0e38]
	check("largest finite extent kept", StlReader.read(binary_stl([far])).ok)
	var tiny_text: Dictionary = StlReader.read(("solid e\n" + UNIT_FACET.replace("1", "1e-30") + "endsolid\n").to_utf8_buffer())
	check("ascii 1e-30 scale kept", tiny_text.ok and tiny_text.value.triangle_count == 1)
	# Below float32 range every coordinate rounds to zero: the facet has zero area and is dropped.
	var vanished := "solid e\n" + UNIT_FACET.replace("normal 0 0 1", "normal 0 0 0").replace("1", "1e-60")
	check("ascii 1e-60 scale underflows to a dropped facet", code(StlReader.read((vanished + "endsolid\n").to_utf8_buffer()))
		== R.SOURCE_INVALID)
	var partly: Dictionary = StlReader.read((vanished + UNIT_FACET + "endsolid\n").to_utf8_buffer())
	check("underflowed facet counted", partly.ok and partly.value.dropped_degenerate == 1 and partly.value.triangle_count == 1)


func size_cases() -> void:
	check("empty input", code(StlReader.read(PackedByteArray())) == R.SOURCE_LIMIT)
	var big := PackedByteArray()
	big.resize(Limits.MODEL_SOURCE_BYTES + 1)
	check("over the byte limit", code(StlReader.read(big)) == R.SOURCE_LIMIT)
	big.resize(Limits.MODEL_SOURCE_BYTES)
	check("at the byte limit the size is admitted", code(StlReader.read(big)) == R.SOURCE_INVALID)


func timing() -> void:
	# Exactly the facet limit, binary.
	var count: int = Limits.TRIANGLES
	var bytes := PackedByteArray()
	bytes.resize(84 + 50 * count)
	bytes.encode_u32(80, count)
	var offset := 84
	for index in count:
		var x := float(index % 1000)
		var y := floorf(index / 1000.0)
		bytes.encode_float(offset + 8, 1.0)
		bytes.encode_float(offset + 12, x)
		bytes.encode_float(offset + 16, y)
		bytes.encode_float(offset + 24, x + 1.0)
		bytes.encode_float(offset + 28, y)
		bytes.encode_float(offset + 36, x)
		bytes.encode_float(offset + 40, y + 1.0)
		bytes.encode_float(offset + 44, 0.5)
		offset += 50
	var started := Time.get_ticks_msec()
	var read: Dictionary = StlReader.read(bytes)
	var elapsed := Time.get_ticks_msec() - started
	check("binary facet limit accepted", read.ok and read.value.triangle_count == count
		and read.value.positions.size() == 9 * count and read.value.inconsistent_normals == 0
		and read.value.bounds_min == PackedFloat64Array([0.0, 0.0, 0.0])
		and read.value.bounds_max == PackedFloat64Array([1000.0, 200.0, 0.5]))
	print("Creator STL timing: binary %d facets (%d bytes) in %d ms" % [count, bytes.size(), elapsed])

	var lines := PackedStringArray(["solid timing"])
	var ascii_count := 50000
	for index in ascii_count:
		var x := float(index % 250) * 0.125
		var y := floorf(index / 250.0) * 0.125
		lines.append("  facet normal 0.000000e+00 0.000000e+00 1.000000e+00")
		lines.append("    outer loop")
		lines.append("      vertex %.6f %.6f 0.000000e+00" % [x, y])
		lines.append("      vertex %.6f %.6f 0.000000e+00" % [x + 0.125, y])
		lines.append("      vertex %.6f %.6f 2.500000e-01" % [x, y + 0.125])
		lines.append("    endloop")
		lines.append("  endfacet")
	lines.append("endsolid timing")
	var text := ("\n".join(lines) + "\n").to_utf8_buffer()
	started = Time.get_ticks_msec()
	read = StlReader.read(text)
	elapsed = Time.get_ticks_msec() - started
	check("ascii 50000 facets", read.ok and read.value.triangle_count == ascii_count and read.value.name == "timing"
		and read.value.bounds_min == PackedFloat64Array([0.0, 0.0, 0.0])
		and read.value.bounds_max == PackedFloat64Array([31.25, 25.0, 0.25]))
	print("Creator STL timing: ASCII %d facets (%d bytes) in %d ms" % [ascii_count, text.size(), elapsed])
	var positions: PackedFloat32Array = read.value.positions if read.ok else PackedFloat32Array()
	started = Time.get_ticks_msec()
	read = StlReader.read(("\r\n".join(lines) + "\r\n").to_utf8_buffer())
	elapsed = Time.get_ticks_msec() - started
	check("ascii 50000 facets with CRLF", read.ok and read.value.positions == positions)
	print("Creator STL timing: ASCII CRLF %d facets in %d ms" % [ascii_count, elapsed])
	# A zero spelled with 20 digits in every normal: every chunk takes the per-token checked path.
	text = ("\n".join(lines) + "\n").replace("normal 0.000000e+00", "normal 0.0000000000000000000").to_utf8_buffer()
	started = Time.get_ticks_msec()
	read = StlReader.read(text)
	elapsed = Time.get_ticks_msec() - started
	check("ascii 50000 facets on the checked path", read.ok and read.value.positions == positions)
	print("Creator STL timing: ASCII checked path %d facets in %d ms" % [ascii_count, elapsed])


func binary_stl(facets: Array, header := "", attributes: Array = []) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(84 + 50 * facets.size())
	var header_bytes := header.to_utf8_buffer()
	for index in mini(header_bytes.size(), 80):
		bytes[index] = header_bytes[index]
	bytes.encode_u32(80, facets.size())
	var offset := 84
	for index in facets.size():
		var facet: Array = facets[index]
		for part in 12:
			bytes.encode_float(offset + 4 * part, facet[part])
		bytes.encode_u16(offset + 48, attributes[index] if index < attributes.size() else 0)
		offset += 50
	return bytes


## The tetrahedron as facet tokens, with assorted number spellings.
func tetra_words() -> PackedStringArray:
	var words := PackedStringArray()
	var spellings := {0.0: "0.0", 1.0: "+1", 2.0: "2.0e+00", 3.0: ".3E1", -1.0: "-1."}
	for facet: Array in TETRA:
		words.append_array(PackedStringArray(["facet", "normal", spellings[facet[0]], spellings[facet[1]], spellings[facet[2]],
			"outer", "loop"]))
		for vertex in 3:
			words.append_array(PackedStringArray(["vertex", spellings[facet[3 + 3 * vertex]],
				spellings[facet[4 + 3 * vertex]], spellings[facet[5 + 3 * vertex]]]))
		words.append_array(PackedStringArray(["endloop", "endfacet"]))
	return words


## The tetrahedron in the conventional seven-lines-per-facet layout with integer spellings.
func tetra_text(name: String) -> String:
	var text := "solid %s\n" % name
	for facet: Array in TETRA:
		text += "  facet normal %d %d %d\n    outer loop\n" % [facet[0], facet[1], facet[2]]
		for vertex in 3:
			text += "      vertex %d %d %d\n" % [facet[3 + 3 * vertex], facet[4 + 3 * vertex], facet[5 + 3 * vertex]]
		text += "    endloop\n  endfacet\n"
	return text + "endsolid %s\n" % name


## One facet whose second vertex x coordinate is `token`; it has area for every finite value.
## `checked` spells the normal with 20 digits: valid, but it takes the chunk off the proven fast
## path, so every number goes through the per-token check.
func number_text(token: String, checked := false) -> String:
	return ("solid n\nfacet normal 0 0 %s\nouter loop\nvertex 0 0 0\nvertex %s 1 0\nvertex 0 1 1\nendloop\nendfacet\n"
		+ "endsolid n\n") % ["0.0000000000000000000" if checked else "0", token]


func replace_first(text: String, what: String, with: String) -> String:
	var at := text.find(what)
	if at < 0:
		check("fixture contains " + what, false)
		return text
	return text.substr(0, at) + with + text.substr(at + what.length())


func code(result: Dictionary) -> String:
	if result.ok or result.diagnostics.is_empty():
		return "ok"
	return str(result.diagnostics[0].code)


func count_diagnostics(result: Dictionary, wanted: String, severity: String) -> int:
	var found := 0
	for entry: Dictionary in result.diagnostics:
		if entry.code == wanted and entry.severity == severity:
			found += 1
	return found


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
