extends SceneTree
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const Fixture := preload("res://tests/test_creator_clearview_readers.gd")
const GlbFixture := preload("res://tests/creator_fixtures.gd")
const Report := preload("res://ui/aircraft_creator_source_report.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ",label)

static func _convert(params: String) -> Dictionary:
	var package := Package.inspect_bytes(Fixture._zip_bytes([["Plane/params.txt",params.to_ascii_buffer()],
		["Plane/data/body.ac",Fixture._ac_fixture().to_ascii_buffer()]]))
	return Converter.convert(package.value,"Plane") if package.ok else package

static func _header() -> String:
	return "verNumber 5\nmodelType 1\nmodelName body.ac\n"

static func _document(source: RefCounted) -> Dictionary:
	var bytes: PackedByteArray = source.source_bytes()
	return JSON.parse_string(bytes.slice(20,20+bytes.decode_u32(12)).get_string_from_utf8())

static func _replace(source: RefCounted,document: Dictionary) -> Dictionary:
	var bytes: PackedByteArray = source.source_bytes()
	var start := 20+bytes.decode_u32(12)
	return Importer.inspect_bytes(GlbFixture.glb(document,bytes.slice(start+8,start+8+bytes.decode_u32(start))),"edited.glb")

static func _row(context: Dictionary,key: String,section := "") -> Dictionary:
	for row: Dictionary in context.observations:
		if row.key == key and row.section == section:
			return row
	return {}

func _run() -> void:
	var text := _header()+"modelMass 4.1\ngravity 11.1\nxRotMass 0.45\npWingCG 0\nservoSpeed 0.2\n"
	var converted := _convert(text)
	check("v5 conversion admitted",converted.ok)
	if not converted.ok:
		printerr(converted)
		quit(1)
		return
	var source: RefCounted = converted.value.source
	var result := Observations.from_source(source)
	check("original bytes produce a checked context",result.ok and not result.value.is_empty())
	if not result.ok:
		printerr(result)
		quit(1)
		return
	var context: Dictionary = result.value
	check("parameter identity is over original bytes",context.parameters_sha256 == Bytes.sha256(text.to_ascii_buffer()))
	check("visual identity covers embedded parameters",context.visual_sha256 == source.sha256())
	check("hash is not an authenticity or physical claim",context.archive_association == "declared" and context.physical_verification == "none")
	var mass := _row(context,"modelMass")
	check("documented v5 mass retained exactly",mass.unit == "kg" and mass.unit_basis == "documented_v5" and Observations.number(mass.value) == 4.1 and mass.line == "4")
	for key: String in ["gravity","xRotMass","pWingCG","servoSpeed"]:
		check("legacy tuning is unresolved: "+key,_row(context,key).unit.is_empty() and _row(context,key).disposition == "unresolved")
	check("context survives exact-byte and normal JSON roundtrip",Observations.validate(Bytes.decode(Bytes.encode(context).value.bytes).value.data).ok and Observations.validate(JSON.parse_string(JSON.stringify(context))).ok)
	var v6text := "#begin params\nverNumber 6\nmodelType 1\nmodelName body.ac\nmodelMass 10.1\n#end params\n#begin propeller.A\npropDiamInch 18\npropPitchInch 7\n#end propeller.A\n#begin motor.A\nmaxRPM 17000\n#end motor.A\n#begin motor.B\nmaxRPM 14000\n#end motor.B\n"
	var v6 := _convert(v6text)
	check("scoped v6 source converted",v6.ok)
	if v6.ok:
		var observed := Observations.from_source(v6.value.source)
		check("v6 shared mass key is only inferred",observed.ok and _row(observed.value,"modelMass","params").unit_basis == "inferred_shared_key")
		if observed.ok:
			var prop := _row(observed.value,"propDiamInch","propeller.A")
			check("inches convert using exact SI definition",prop.unit_basis == "inferred_field_name" and prop.normalized_unit == "m" and Observations.number(prop.normalized_value) == 18.0*0.0254)
			check("two motors remain separate declarations",Observations.number(_row(observed.value,"maxRPM","motor.A").value) == 17000.0 and Observations.number(_row(observed.value,"maxRPM","motor.B").value) == 14000.0)
	for rhs: String in ["nan","inf","4.1oops","1e999","1e-39","0","-2","1e10","1 2"]:
		var changed := _convert(_header()+"modelMass "+rhs+"\n")
		check("malformed or nonphysical mass stays unresolved: "+rhs,changed.ok and _row(Observations.from_source(changed.value.source).value,"modelMass").value.is_empty())
	var duplicate := _convert(_header()+"modelMass 4.1\nmodelmass 4.1\n")
	var repeated := Observations.from_source(duplicate.value.source)
	check("case-ambiguous duplicates never select a value",repeated.ok and repeated.value.observations.all(func(row: Dictionary) -> bool: return row.disposition == "duplicate" and row.value.is_empty()))
	var many := _header()
	for index: int in Observations.MAX_ROWS+1:
		many += "gravity 9.8\n"
	var limited := Observations.from_source(_convert(many).value.source)
	check("display rows are bounded and omission visible",limited.ok and limited.value.observations.size() == Observations.MAX_ROWS and limited.value.omitted == "1")
	var longtext := _convert(_header()+"modelMass "+"1".repeat(Observations.MAX_RAW+1)+"\n")
	var shortened := _row(Observations.from_source(longtext.value.source).value,"modelMass")
	check("shortened tokens cannot become numeric references",shortened.truncated and shortened.raw.length() == Observations.MAX_RAW and shortened.value.is_empty())
	for mutation: String in ["hash","data","padding","path","extra","format","member_type"]:
		var document := _document(source)
		var payload: Dictionary = document.asset.extras.openrc_clearview.parameters
		match mutation:
			"hash": payload.sha256 = "0".repeat(64)
			"data": payload.data = "!!!!"
			"padding": payload.data += "===="
			"path": payload.member = "../params.txt"
			"extra": payload.extra = true
			"format": payload.format = "future"
			"member_type": payload.member = []
		var admitted := _replace(source,document)
		check("hostile extras remain visual-only: "+mutation,admitted.ok and not Observations.from_source(admitted.value).ok)
	var legacy_document := _document(source)
	legacy_document.asset.extras.openrc_clearview.erase("parameters")
	var legacy := _replace(source,legacy_document)
	var legacy_report := Observations.from_source(legacy.value)
	check("legacy converted GLB requests reimport",legacy_report.ok and legacy_report.value.is_empty() and legacy_report.diagnostics[0].message == Observations.LEGACY)
	legacy_document.asset.extras.openrc_clearview.parameters_omitted = "metadata_limit"
	var omitted := Observations.from_source(_replace(source,legacy_document).value)
	check("metadata omission does not promise a reimport fix",omitted.ok and omitted.value.is_empty() and omitted.diagnostics[0].message == Observations.OMITTED)
	var large := _header()+"modelMass 2.0\n"
	for index: int in 3900:
		large += "unknownParameter "+"x".repeat(220)+"\n"
	var fallback := _convert(large)
	check("real JSON budget fallback retains visual admission",fallback.ok and fallback.value.receipt.get("parameters_omitted") == "metadata_limit" and not fallback.value.receipt.has("parameters"))
	if fallback.ok:
		var fallback_report := Observations.from_source(fallback.value.source)
		check("fallback explanation survives actual GLB reopen",fallback_report.ok and fallback_report.value.is_empty() and fallback_report.diagnostics[0].message == Observations.OMITTED)
	var ordinary := Importer.inspect_bytes(GlbFixture.airplane_glb(),"ordinary.glb")
	check("ordinary GLB has no source declarations",Observations.from_source(ordinary.value).value.is_empty() and Observations.from_source(ordinary.value).diagnostics.is_empty())
	for mutation: String in ["path","number","unit","line","unknown"]:
		var forged := context.duplicate(true)
		match mutation:
			"path": forged.model_root = "../Plane"
			"number": forged.observations[0].value = "0".repeat(16)
			"unit": forged.observations[0].unit_basis = "measured"
			"line": forged.observations[1].line = forged.observations[0].line
			"unknown": forged.authority = "trusted"
		check("closed report rejects altered derived metadata: "+mutation,not Observations.validate(forged).ok)
	for key: String in Observations.CONTEXT_KEYS:
		for hostile: Variant in [null,false,2.0,[],{}]:
			if key == "observations" and hostile is Array:
				continue # An empty report is valid when the parameter file has no selected keys.
			var forged := context.duplicate(true)
			forged[key] = hostile
			check("report field type refused: "+key,not Observations.validate(forged).ok)
	for key: String in Observations.ROW_KEYS:
		for hostile: Variant in [null,2.0,[],{}]:
			var forged := context.duplicate(true)
			forged.observations[0][key] = hostile
			check("row field type refused: "+key,not Observations.validate(forged).ok)
	_persistence(source,context,ordinary.value)
	_compiler(context)
	var panel := Report.new()
	root.add_child(panel)
	panel.show_context(context)
	check("report starts collapsed",panel.visible and not panel._body.visible and not panel._toggle.button_pressed)
	panel._toggle.button_pressed = true
	check("report expands without adopting anything",panel._body.visible and panel._body.get_child_count() > context.observations.size())
	for locale: String in ["es","pt_BR","de","fr","it","ru","ja","zh_Hans"]:
		TranslationServer.set_locale(locale)
		for caption: String in [Report.TITLE,Report.CAUTION,Report.INTEGRITY,Report.DOCUMENTED,Report.INFERRED,Report.UNKNOWN,Report.DUPLICATE,Report.TRUNCATED,Report.OMITTED,Report.MEMBER,Report.HASH,Report.POSITION,Observations.LEGACY,Observations.INVALID]:
			check("report translated: "+locale+" "+caption,TranslationServer.translate(caption) != caption)
	TranslationServer.set_locale("en")
	panel.queue_free()
	await process_frame
	print("ClearView observations: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _persistence(source: RefCounted,context: Dictionary,ordinary: RefCounted) -> void:
	var doc := Authoring.new()
	doc.set_source(source,Observations.inspect(source).value)
	doc.apply_values({"wing/span":1.875},true)
	var saved := doc.snapshot("import")
	check("source context uses versioned snapshot",saved.format == Authoring.SOURCE_SNAPSHOT_FORMAT)
	var reopened := Authoring.new()
	var exact: Dictionary = Bytes.decode(Bytes.encode(saved).value.bytes).value.data
	check("reopened snapshot rechecks embedded source",reopened.restore(exact,source,Observations.inspect(source).value).ok and reopened.source_observations() == context)
	check("reopened manual value preserved",reopened.value("wing/span") == 1.875)
	var before := reopened.snapshot()
	check("missing independently derived context is refused",not reopened.restore(saved,source).ok and reopened.snapshot() == before)
	check("receipt for another source fails reopen comparison",not reopened.restore(saved,source,Observations.inspect(ordinary).value).ok and reopened.snapshot() == before)
	doc.set_source(ordinary)
	check("replacement clears context but preserves manual fields",doc.source_observations().is_empty() and doc.value("wing/span") == 1.875 and doc.snapshot().format == Authoring.SNAPSHOT_FORMAT)
	check("v1 snapshot keeps legacy shape",not doc.snapshot().has("source_observations") and reopened.restore(doc.snapshot(),ordinary).ok)
	doc.set_source(source,Observations.inspect(source).value)
	var copy := doc.source_observations()
	copy.observations.clear()
	check("returned context cannot mutate the document",not doc.source_observations().observations.is_empty())
	var forged := context.duplicate(true)
	forged.visual_sha256 = ordinary.sha256()
	doc.set_source(ordinary,Observations.inspect(source).value)
	check("public setters cannot bless invented source declarations",doc.source_observations().is_empty())
	var invented := saved.duplicate(true)
	invented.source_sha256 = ordinary.sha256()
	invented.source_observations = forged
	check("public restore cannot trust caller-supplied member claims",not reopened.restore(invented,ordinary,Observations.inspect(source).value).ok)

func _compiler(context: Dictionary) -> void:
	var original := Definition.template()
	var base := Compiler.compile_candidate(original)
	var enriched := original.duplicate(true)
	enriched.format = Definition.SOURCE_FORMAT
	enriched.source_observations = context
	var checked := Definition.validate_complete(enriched)
	var compiled := Compiler.compile_candidate(enriched)
	check("reference context compiles through versioned definition",checked.ok and compiled.ok and base.ok)
	if compiled.ok and base.ok:
		check("review references never change physical record bytes",compiled.value.raw_bytes() == base.value.raw_bytes())
		check("definition identity includes review references",compiled.value.definition_sha256() != base.value.definition_sha256())
		check("summary links exact report identity",compiled.value.summary().source_observations_sha256 == Observations.digest(context))
		check("standalone compiler only validates metadata structure",compiled.value.summary().source_observations_validation == "structure_only" and compiled.value.summary().source_observations.member_integrity == "declared")
	var invented := enriched.duplicate(true)
	invented.source_observations.observations = []
	invented.source_observations.parameters_sha256 = "0".repeat(64)
	var fabricated := Compiler.compile_candidate(invented)
	check("a standalone declaration cannot imply source verification",fabricated.ok and fabricated.value.summary().source_observations_validation == "structure_only" and fabricated.value.summary().source_observations.member_integrity == "declared")
	original.source_observations = context
	check("v1 definitions cannot silently carry new metadata",not Definition.validate_complete(original).ok)
	enriched.erase("source_observations")
	check("v2 definitions require reference context",not Definition.validate_complete(enriched).ok)
