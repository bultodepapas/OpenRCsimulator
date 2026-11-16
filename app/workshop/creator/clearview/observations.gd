extends RefCounted
## Review evidence, never flight inputs. The stored member can be checked; ZIP membership and
## physical truth cannot be authenticated without the original package/independent measurements.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Source := preload("res://workshop/creator/inspected_source.gd")
const Params := preload("params.gd")
const Archive := preload("archive.gd")
const FORMAT := "openrc-source-observations v1"
const PAYLOAD_FORMAT := "openrc-clearview-parameters v1"
const POLICY := "clearview-parameter-review-v1"
const MAX_ROWS := 128
const MAX_RAW := 256
const MAX_CONTEXT_BYTES := 128 * 1024
const LEGACY := "Original parameter bytes are absent. Re-import the ZIP to review source declarations."
const INVALID := "The source declarations could not be checked. Re-import the ZIP."
const OMITTED := "The original parameters exceed the converted model's metadata limit. Source declarations are unavailable for this model."
const CONTEXT_KEYS := ["format","policy","number_encoding","visual_sha256","archive_sha256","archive_association",
	"model_root","parameters_member","parameters_sha256","member_integrity","physical_verification","dialect","observations","omitted"]
const ROW_KEYS := ["section","key","line","raw","truncated","value","unit","unit_basis","normalized_value","normalized_unit","disposition"]
const SELECTED := ["modelmass","gravity","centerofgravity","pwingcg","pbodycg","xrotmass","yrotmass","zrotmass",
	"wingwingsize","bodywingsize","aelrate","elevrate","ruderrate","servospeed","propdiaminch","proppitchinch",
	"maxrpm","powercurvewatts","modelmotors","modelpropellers","planetype"]

## Worker-created receipt bound to this admitted object. Like InspectedSource, sealing is an
## in-process ownership convention, not a boundary against arbitrary trusted GDScript execution.
class CheckedReport extends RefCounted:
	var _source: Source
	var _context := {}
	func matches(source: Source) -> bool:
		return source != null and source == _source
	func context() -> Dictionary:
		return _context.duplicate(true)

static func inspect(source: Source) -> Dictionary:
	var derived := from_source(source)
	if not derived.ok:
		return derived
	var report := CheckedReport.new()
	report._source = source
	report._context = derived.value
	return R.ok(report,derived.diagnostics)

static func parameter_payload(member: String, bytes: PackedByteArray) -> Dictionary:
	return {format = PAYLOAD_FORMAT,member = member,sha256 = Bytes.sha256(bytes),encoding = "base64",data = Marshalls.raw_to_base64(bytes)}

## Reads the immutable admitted source on the import worker. Absence is backward compatible.
static func from_source(source: Source) -> Dictionary:
	if source == null or not source.is_admitted() or source.format() != "glb":
		return R.ok({})
	var bytes := source.source_bytes()
	var length := bytes.decode_u32(12)
	if length > Limits.GLB_JSON_BYTES or 20+length > bytes.size():
		return _invalid()
	var document: Variant = JSON.parse_string(bytes.slice(20,20+length).get_string_from_utf8())
	if not document is Dictionary or not document.get("asset") is Dictionary:
		return R.ok({})
	var extras: Variant = document.asset.get("extras")
	if not extras is Dictionary or not extras.get("openrc_clearview") is Dictionary:
		return R.ok({})
	var receipt: Dictionary = extras.openrc_clearview
	if not _is(receipt.get("format"),"openrc-clearview-visual-v1"):
		return R.ok({})
	if not receipt.has("parameters"):
		var note := OMITTED if _is(receipt.get("parameters_omitted"),"metadata_limit") else LEGACY
		return R.ok({},[R.diagnostic(R.SOURCE_UNSUPPORTED,note,"source","import",[],R.SEVERITY_INFO)])
	var payload: Variant = receipt.parameters
	if not payload is Dictionary or not _keys(payload,["format","member","sha256","encoding","data"]) \
			or not _is(payload.format,PAYLOAD_FORMAT) or not _is(payload.encoding,"base64") or not _text(payload.data,1398104) \
			or not _text(payload.member,512) or not Archive.safe_name(payload.member,false) or not Bytes.is_sha256(payload.sha256) \
			or not Bytes.is_sha256(receipt.get("archive_sha256")) or not _text(receipt.get("model_root"),512):
		return _invalid()
	var root: String = receipt.model_root
	if not root.is_empty() and not Archive.safe_name(root,false):
		return _invalid()
	var expected := (root+"/" if not root.is_empty() else "")+"params.txt"
	if str(payload.member).to_lower() != expected.to_lower():
		return _invalid()
	var encoded: String = payload.data
	if encoded.is_empty() or encoded.length()%4 != 0 or RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$").search(encoded) == null:
		return _invalid()
	var member := Marshalls.base64_to_raw(encoded)
	if member.size() > Params.MAX_BYTES or Marshalls.raw_to_base64(member) != encoded or Bytes.sha256(member) != payload.sha256:
		return _invalid()
	var parsed := Params.read(member)
	if not parsed.ok:
		return _invalid()
	var context := {format = FORMAT,policy = POLICY,number_encoding = "ieee754-binary64-le-hex",visual_sha256 = source.sha256(),
		archive_sha256 = receipt.archive_sha256,archive_association = "declared",model_root = root,
		parameters_member = payload.member,parameters_sha256 = payload.sha256,member_integrity = "declared",
		physical_verification = "none",dialect = str(parsed.value.version),observations = [],omitted = "0"}
	var counts := {}
	for record: Dictionary in parsed.value.records:
		var key: String = record.section+"/"+record.key.to_lower()
		counts[key] = int(counts.get(key,0))+1
	var omitted := 0
	for record: Dictionary in parsed.value.records:
		if record.key.to_lower() not in SELECTED:
			continue
		if context.observations.size() >= MAX_ROWS:
			omitted += 1
			continue
		context.observations.append(_row(record.section,record.key,str(record.line),record.raw_rhs.left(MAX_RAW),
			record.raw_rhs.length()>MAX_RAW,str(parsed.value.version),counts[record.section+"/"+record.key.to_lower()] > 1))
	context.omitted = str(omitted)
	return validate(context)

## Closed serializable metadata. A standalone compiler can validate its shape, not authenticate its origin.
static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or not _keys(value,CONTEXT_KEYS):
		return _invalid()
	for key: String in CONTEXT_KEYS:
		if key != "observations" and not _text(value[key],512):
			return _invalid()
	if value.format != FORMAT or value.policy != POLICY or value.number_encoding != "ieee754-binary64-le-hex" \
			or value.archive_association != "declared" or value.member_integrity != "declared" or value.physical_verification != "none" \
			or value.dialect not in ["5","6"] or not Bytes.is_sha256(value.visual_sha256) \
			or not Bytes.is_sha256(value.archive_sha256) or not Bytes.is_sha256(value.parameters_sha256) \
			or not _text(value.model_root,512) or not _text(value.parameters_member,512) \
			or not Archive.safe_name(value.parameters_member,false) or not _integer_text(value.omitted,0,Params.MAX_RECORDS) \
			or not value.observations is Array or value.observations.size()>MAX_ROWS:
		return _invalid()
	if (not value.model_root.is_empty() and not Archive.safe_name(value.model_root,false)) \
			or value.parameters_member.to_lower() != ((value.model_root+"/" if not value.model_root.is_empty() else "")+"params.txt").to_lower():
		return _invalid()
	var lines := {}
	var counts := {}
	for entry: Variant in value.observations:
		if not entry is Dictionary or not _keys(entry,ROW_KEYS):
			return _invalid()
		for key: String in ROW_KEYS:
			if key != "truncated" and not _text(entry[key],MAX_RAW):
				return _invalid()
		if not _text(entry.section,128) or not _text(entry.key,128) \
				or entry.key.to_lower() not in SELECTED or not Params._identifier(entry.key) \
				or (not entry.section.is_empty() and not Params._identifier(entry.section)) \
				or not _integer_text(entry.line,1,Params.MAX_LINES) or lines.has(entry.line) \
				or not _text(entry.raw,MAX_RAW) or typeof(entry.truncated) != TYPE_BOOL:
			return _invalid()
		lines[entry.line] = true
		var key: String = entry.section+"/"+entry.key.to_lower()
		counts[key] = int(counts.get(key,0))+1
	var previous := 0
	for entry: Dictionary in value.observations:
		if int(entry.line)<=previous:
			return _invalid()
		previous = int(entry.line)
		var key: String = entry.section+"/"+entry.key.to_lower()
		# A duplicate outside the truncated view may explain this status. Never infer a unique value.
		var duplicate: bool = counts[key]>1 or entry.disposition == "duplicate"
		if entry != _row(entry.section,entry.key,entry.line,entry.raw,entry.truncated,value.dialect,duplicate):
			return _invalid()
	var written := Bytes.encode(value)
	if not written.ok or written.value.bytes.size()>MAX_CONTEXT_BYTES:
		return _invalid()
	return R.ok(value.duplicate(true))

static func digest(value: Dictionary) -> String:
	var checked := validate(value)
	if not checked.ok:
		return ""
	return Bytes.sha256(Bytes.encode(checked.value).value.bytes)

static func _row(section: String,key: String,line: String,raw: String,truncated: bool,dialect: String,duplicate: bool) -> Dictionary:
	var out := {section = section,key = key,line = line,raw = raw,truncated = truncated,value = "",unit = "",unit_basis = "unknown",
		normalized_value = "",normalized_unit = "",disposition = "unresolved"}
	var numeric := _number(Params._without_comment(raw)) if not truncated else NAN
	var root_field := section == ("params" if dialect == "6" else "")
	if key == "modelMass" and root_field:
		out.unit = "kg"
		out.unit_basis = "documented_v5" if dialect == "5" else "inferred_shared_key"
		if numeric <= 0.0:
			numeric = NAN
	elif key in ["propDiamInch","propPitchInch"] and dialect == "6" and section.begins_with("propeller."):
		out.unit = "in"
		out.unit_basis = "inferred_field_name"
	elif key == "maxRPM" and dialect == "6" and section.begins_with("motor."):
		out.unit = "rpm"
		out.unit_basis = "inferred_field_name"
	if not out.unit.is_empty() and numeric <= 0.0:
		numeric = NAN
	if is_finite(numeric):
		out.value = _exact(numeric)
		if not out.unit.is_empty():
			out.normalized_unit = "m" if out.unit == "in" else out.unit
			out.normalized_value = _exact(numeric*0.0254 if out.unit == "in" else numeric)
		out.disposition = "reference" if not out.unit.is_empty() else "unresolved"
	if duplicate:
		out.disposition = "duplicate"
		out.value = ""
		out.normalized_value = ""
		out.normalized_unit = ""
	return out

static func number(encoded: String) -> float:
	return encoded.hex_decode().decode_double(0) if encoded.length()==16 and encoded.is_valid_hex_number(false) else NAN

static func _exact(value: float) -> String:
	var data := PackedByteArray()
	data.resize(8)
	data.encode_double(0,value)
	return data.hex_encode()

static func _number(text: String) -> float:
	if text.length()>MAX_RAW or RegEx.create_from_string("^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]{1,3})?$").search(text)==null:
		return NAN
	var exponent := text.to_lower().split("e")
	if exponent.size()==2 and absi(exponent[1].to_int())>38:
		return NAN
	var value := text.to_float()
	return value if is_finite(value) and absf(value)<=1.0e9 else NAN

static func _keys(value: Dictionary,keys: Array) -> bool:
	if value.size()!=keys.size():
		return false
	for key: Variant in value:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or str(key) not in keys:
			return false
	return true

static func _is(value: Variant,expected: String) -> bool:
	return typeof(value)==TYPE_STRING and value==expected

static func _text(value: Variant,maximum: int) -> bool:
	if typeof(value)!=TYPE_STRING or value.length()>maximum:
		return false
	for at: int in value.length():
		if value.unicode_at(at)<32 and value.unicode_at(at)!=9 or value.unicode_at(at)>126:
			return false
	return true

static func _integer_text(value: Variant,low: int,high: int) -> bool:
	return typeof(value)==TYPE_STRING and value.length()<=6 and value.is_valid_int() and str(value.to_int())==value \
		and value.to_int()>=low and value.to_int()<=high

static func _invalid() -> Dictionary:
	return R.fail(R.SOURCE_INVALID,INVALID,"source_observations","import")
