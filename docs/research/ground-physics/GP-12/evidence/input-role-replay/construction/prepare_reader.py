from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / 'reader'
OUT.mkdir(exist_ok=True)
source = ROOT / 'app/tools/flight_log_cli.gd'
original = source.read_text(encoding='utf-8')

def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)

draft = replace_once(original, 'columns(header.layout)', 'columns(header.layout, header.metadata)')
draft = replace_once(draft,
    '\tvar snapshot: Dictionary = header.checkpoint.simulation\n',
    '\tvar input_contract := input_names(layout, header.metadata)\n'
    '\tif not input_contract.ok:\n'
    '\t\treturn input_contract\n'
    '\tvar snapshot: Dictionary = header.checkpoint.simulation\n')
draft = replace_once(draft,
    '\treturn {ok = true, flight = flight}\n',
    '\tvar recorded := input_names(header.layout, header.metadata)\n'
    '\tvar installed := input_names({inputs = flight.sim.inputs.size()}, flight.trace_meta())\n'
    '\tif not recorded.ok or not installed.ok or recorded.names != installed.names:\n'
    '\t\tflight.free()\n'
    '\t\treturn {ok = false, error = "Recorded input roles differ from the selected aircraft; replay refused."}\n'
    '\treturn {ok = true, flight = flight}\n')
old = '''static func columns(layout: Dictionary) -> PackedStringArray:
	var result := PackedStringArray(["tick", "t_s", "loads_t_s"])
	result.append_array(PackedStringArray(RB.STATE_LAYOUT))
	result.append_array(PackedStringArray(["Fx_N", "Fy_N", "Fz_N", "Mx_Nm", "My_Nm", "Mz_Nm", "cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle"]))
	if layout.inputs in [6, 7]: result.append_array(PackedStringArray(["cmd_gear_down", "cmd_wheel_brake"]))
	if layout.inputs in [5, 7]: result.append("cmd_flaps")
'''
new = '''## GP-12: an input width does not identify its roles. Historical logs without
## input_layout retain their original 4/5/6/7-column interpretation. A declared
## layout is authoritative only after validation; never silently relabel it.
## The versioned fixed-brake branch is reader support, not aircraft admission.
const FIXED_BRAKE_INPUT_LAW := "fixed-gear-shared-wheel-brake-input-v1"


static func input_names(layout: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	var width: Variant = layout.get("inputs")
	if typeof(width) != TYPE_INT or width not in [4, 5, 6, 7]:
		return {ok = false, error = "Unsupported recorded input width."}
	var expected := PackedStringArray(["roll", "pitch", "yaw", "throttle"])
	var fixed_brake: bool = metadata.has("fixed_brake_input_law") or metadata.has("wheel_brake_input_index")
	if fixed_brake:
		if typeof(metadata.get("fixed_brake_input_law")) != TYPE_STRING \\
				or metadata.fixed_brake_input_law != FIXED_BRAKE_INPUT_LAW \\
				or typeof(metadata.get("wheel_brake_input_index")) != TYPE_INT \\
				or metadata.wheel_brake_input_index != 4 or width not in [5, 6] \\
				or not metadata.has("input_layout"):
			return {ok = false, error = "Invalid fixed-gear brake input contract."}
		for key: String in ["gear_law", "gear_aux_index", "gear_trace_schema", "recording_start_gear"]:
			if metadata.has(key):
				return {ok = false, error = "Conflicting fixed-brake and retractable gear input contracts."}
		expected.append("wheel_brake")
		if width == 6:
			expected.append("flaps")
	else:
		if width in [6, 7]:
			expected.append_array(PackedStringArray(["gear_down", "wheel_brake"]))
		if width in [5, 7]:
			expected.append("flaps")
	for key: String in ["gear_law", "gear_aux_index", "gear_trace_schema", "recording_start_gear"]:
		if metadata.has(key) and not expected.has("gear_down"):
			return {ok = false, error = "Gear metadata disagrees with recorded input roles."}
	for key: String in ["flap_law", "flap_aux_index", "flap_input_index", "flap_trace_schema", "flap_max_angle_deg", "recording_start_flap"]:
		if metadata.has(key) and not expected.has("flaps"):
			return {ok = false, error = "Flap metadata disagrees with recorded input roles."}
	if metadata.has("flap_input_index") and (typeof(metadata.flap_input_index) != TYPE_INT \\
			or metadata.flap_input_index != expected.find("flaps")):
		return {ok = false, error = "Flap input index disagrees with recorded input roles."}
	if metadata.has("input_layout"):
		var raw: Variant = metadata.input_layout
		if typeof(raw) != TYPE_STRING or raw.length() > 256:
			return {ok = false, error = "Invalid recorded input layout encoding."}
		var parser := JSON.new()
		if parser.parse(raw) != OK:
			return {ok = false, error = "Invalid recorded input layout JSON."}
		var decoded: Variant = parser.data
		if not decoded is Array or decoded.size() != expected.size():
			return {ok = false, error = "Recorded input layout width disagrees with its contract."}
		for i in expected.size():
			if typeof(decoded[i]) != TYPE_STRING or decoded[i] != expected[i]:
				return {ok = false, error = "Unsupported or conflicting recorded input roles."}
	return {ok = true, names = expected}


static func columns(layout: Dictionary, metadata: Dictionary = {}) -> PackedStringArray:
	var contract := input_names(layout, metadata)
	if not contract.ok:
		return PackedStringArray()
	var result := PackedStringArray(["tick", "t_s", "loads_t_s"])
	result.append_array(PackedStringArray(RB.STATE_LAYOUT))
	result.append_array(PackedStringArray(["Fx_N", "Fy_N", "Fz_N", "Mx_Nm", "My_Nm", "Mz_Nm"]))
	for role: String in contract.names:
		result.append("cmd_" + role)
'''
draft = replace_once(draft, old, new)
(OUT / 'flight_log_cli.gd').write_text(draft, encoding='utf-8', newline='\n')
(OUT / 'before.gd').write_bytes(source.read_bytes())
(OUT / 'manifest.json').write_text(json.dumps({
    'source': str(source.relative_to(ROOT)),
    'before_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'draft_sha256': hashlib.sha256((OUT/'flight_log_cli.gd').read_bytes()).hexdigest(),
    'scope': 'GP-12 input-role export/replay contract; no runtime fixed-brake activation'
}, indent=2)+'\n', encoding='utf-8')
print('Prepared detached CLI draft; production unchanged.')
