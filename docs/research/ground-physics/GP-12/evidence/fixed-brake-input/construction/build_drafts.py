from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
PATHS = ['app/sim/flight_session.gd', 'app/main.gd', 'app/sim/trace.gd']
base = {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in PATHS}

def swap(s, old, new, count=1):
    assert s.count(old) == count, (old[:100], s.count(old), count)
    return s.replace(old, new)

s = (ROOT/PATHS[0]).read_text(encoding='utf-8')
s = swap(s, 'var _wheel_brake_demand := 0.0', 'const FIXED_BRAKE_INPUT_LAW := "fixed-gear-shared-wheel-brake-input-v1"\nvar _wheel_brake_demand := 0.0')
s = swap(s, '\t\tvalues.append(_wheel_brake_demand)', '\tif wheel_brake_input_index() >= 0:\n\t\tvalues.append(_wheel_brake_demand)')
s = swap(s, 'return 4 + (2 if gear_is_retractable() else 0) + (1 if flaps_available() else 0)', 'return 4 + (1 if gear_is_retractable() else 0) + (1 if wheel_brake_input_index() >= 0 else 0) + (1 if flaps_available() else 0)')
s = swap(s, 'return (6 if gear_is_retractable() else 4) if flaps_available() else -1', 'return (_input_count() - 1) if flaps_available() else -1')
anchor = 'func set_wheel_brake(amount: float) -> bool:'
helper = '''## Shared demand is admitted only for explicitly installed, provenance-bearing brake hardware.
## Retraction and brake hardware are independent capabilities; the old retractable input layout stays fixed.
func wheel_brake_available() -> bool:
	if typeof(aircraft.get("ok")) != TYPE_BOOL or not aircraft.ok or not aircraft.get("model") is Dictionary:
		return false
	var profile: Variant = aircraft.model.get("wheel_profile")
	var gear: Variant = aircraft.model.get("landing_gear")
	if not profile is Dictionary or typeof(profile.get("status")) != TYPE_STRING or profile.status != "applied" \\
			or not gear is Dictionary or not gear.get("contacts") is Array \\
			or gear.contacts.is_empty() or gear.contacts.size() > 16:
		return false
	var available := false
	for candidate: Variant in gear.contacts:
		if not candidate is Dictionary: return false
		var contact: Dictionary = candidate
		var source: Variant = contact.get("wheel_provenance")
		var torque: Variant = contact.get("brake_torque")
		if typeof(contact.get("brake_availability")) != TYPE_STRING \\
				or contact.brake_availability not in ["none", "unspecified", "available"] \\
				or not source is Dictionary or typeof(source.get("brake_availability")) != TYPE_STRING \\
				or source.brake_availability != contact.brake_availability or not source.get("brake_torque") is Dictionary \\
				or typeof(torque) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(torque)) or float(torque) < 0.0:
			return false
		var quantity: Dictionary = source.brake_torque
		if typeof(quantity.get("value")) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(quantity.value)) \\
				or float(quantity.value) != float(torque) or typeof(quantity.get("unit")) != TYPE_STRING or quantity.unit != "N·m" \\
				or typeof(quantity.get("kind")) != TYPE_STRING or quantity.kind not in ["manual", "measured", "borrowed", "estimated", "derived"] \\
				or typeof(quantity.get("source")) != TYPE_STRING or quantity.source.strip_edges().is_empty():
			return false
		if contact.brake_availability == "available":
			if float(torque) <= 0.0: return false
			available = true
		elif float(torque) != 0.0:
			return false
	return available


func wheel_brake_input_index() -> int:
	return 5 if gear_is_retractable() else 4 if wheel_brake_available() else -1


'''
s = swap(s, anchor, helper + anchor)
a = s.index('func set_wheel_brake('); b = s.index('\nfunc ', a + 1)
segment = s[a:b]
segment = swap(segment, 'if not gear_is_retractable() or not physics_enabled or not input_enabled', 'if not wheel_brake_available() or not physics_enabled or not input_enabled')
s = s[:a] + segment + s[b:]
s = swap(s, 'elif not gear_is_retractable():\n\t\t\terrors.append("brake is unsupported without retractable landing gear")', 'elif float(normalized_packet.brake) > 0.0 and not wheel_brake_available():\n\t\t\terrors.append("brake is unsupported without explicitly available wheel brake hardware")')
s = swap(s, 'var brake: float = sim.inputs[5] if retractable else 0.0', 'var brake_index: int = wheel_brake_input_index()\n\tvar brake: float = sim.inputs[brake_index] if brake_index >= 0 else 0.0')
old = '\tif flaps_available() and (not _flap_aux_valid('
# Both pre-step and checkpoint validate the new input even without flaps or gear AUX.
for fn, arr in [('func _pre_step(', 'inputs'), ('func checkpoint()', 'sim.inputs')]:
    at = s.index(fn)
    end = s.find('\nfunc ', at+1)
    segment = s[at:end if end >= 0 else len(s)]
    needle = old
    assert needle in segment
    failure = 'return PackedFloat64Array([NAN])' if arr == 'inputs' else 'return {}'
    insert = f'\tif not gear_is_retractable() and wheel_brake_input_index() >= 0 and ({arr}.size() != _input_count() \\\n\t\t\tor not RetractableGear.valid_fraction({arr}[wheel_brake_input_index()])):\n\t\t{failure}\n'
    segment = segment.replace(needle, insert + needle, 1)
    s = s[:at] + segment + s[end:]
s = swap(s, '\tif flaps_available():\n\t\tmetadata.flap_base_metadata_schema', '\tif not gear_is_retractable() and wheel_brake_available():\n\t\tmetadata.fixed_brake_input_law = FIXED_BRAKE_INPUT_LAW\n\t\tmetadata.wheel_brake_input_index = wheel_brake_input_index()\n\t\tmetadata.input_layout = JSON.stringify(["roll", "pitch", "yaw", "throttle", "wheel_brake"])\n\tif flaps_available():\n\t\tmetadata.flap_base_metadata_schema')
s = swap(s, '\t\tif gear_is_retractable(): layout.append_array(["gear_down", "wheel_brake"])', '\t\tif gear_is_retractable(): layout.append_array(["gear_down", "wheel_brake"])\n\t\telif wheel_brake_available(): layout.append("wheel_brake")')
s = swap(s, '\tif flaps_available():\n\t\tboundary.flap_law', '\tif not gear_is_retractable() and wheel_brake_available():\n\t\tboundary.fixed_brake_input_law = FIXED_BRAKE_INPUT_LAW\n\t\tboundary.wheel_brake_input_index = wheel_brake_input_index()\n\tif flaps_available():\n\t\tboundary.flap_law')
s = swap(s, '\tif flaps_available():\n\t\tparts.append(Flaps.LAW', '\tif not gear_is_retractable() and wheel_brake_available():\n\t\tparts.append(FIXED_BRAKE_INPUT_LAW + "; input=4; shared wheel brake demand")\n\tif flaps_available():\n\t\tparts.append(Flaps.LAW')
s = swap(s, '\tif flaps_available():\n\t\tif candidate.get("flap_law")', '\tif not gear_is_retractable() and wheel_brake_available():\n\t\tif typeof(candidate.get("fixed_brake_input_law")) != TYPE_STRING or candidate.fixed_brake_input_law != FIXED_BRAKE_INPUT_LAW \\\n\t\t\t\tor typeof(candidate.get("wheel_brake_input_index")) != TYPE_INT or candidate.wheel_brake_input_index != 4 \\\n\t\t\t\tor not snapshot.get("inputs") is PackedFloat64Array or snapshot.inputs.size() != _input_count() \\\n\t\t\t\tor not RetractableGear.valid_fraction(snapshot.inputs[4]):\n\t\t\treturn false\n\telif candidate.has("fixed_brake_input_law") or candidate.has("wheel_brake_input_index"):\n\t\treturn false\n\tif flaps_available():\n\t\tif candidate.get("flap_law")')
s = swap(s, '\t\t\t_wheel_brake_demand = snapshot.inputs[5]\n', '')
s = swap(s, '\t\t_flap_requested = snapshot.inputs[flap_input_index()] if flaps_available() else 0.0', '\t\t_wheel_brake_demand = snapshot.inputs[wheel_brake_input_index()] if wheel_brake_input_index() >= 0 else 0.0\n\t\t_flap_requested = snapshot.inputs[flap_input_index()] if flaps_available() else 0.0')
(OUT/'flight_session.gd').write_text(s,encoding='utf-8',newline='\n')

s = (ROOT/PATHS[1]).read_text(encoding='utf-8')
s = swap(s, 'or not session.gear_is_retractable()\n\t\tor not Input.is_physical_key_pressed(KEY_B)', 'or not session.wheel_brake_available()\n\t\tor not Input.is_physical_key_pressed(KEY_B)')
s = swap(s, 'and session.gear_is_retractable() and session.set_wheel_brake(1.0)', 'and session.wheel_brake_available() and session.set_wheel_brake(1.0)')
s = s.replace('preload("res://sim/flight_session.gd")', 'preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-fixed-brake-session/flight_session.gd")')
(OUT/'main.gd').write_text(s,encoding='utf-8',newline='\n')

s = (ROOT/PATHS[2]).read_text(encoding='utf-8')
s = swap(s, 'var _gear: bool = false', 'const FIXED_BRAKE_INPUT_LAW := "fixed-gear-shared-wheel-brake-input-v1"\nvar _fixed_brake: bool = false\nvar _gear: bool = false')
s = swap(s, '\t_gear = false', '\t_fixed_brake = false\n\t_gear = false')
s = swap(s, '\t_prepare_shaft_metadata()', '\t_prepare_fixed_brake_metadata()\n\tif _invalid_weather: return\n\t_prepare_shaft_metadata()')
helper = '''func _prepare_fixed_brake_metadata() -> void:
	if not meta.has("fixed_brake_input_law") and not meta.has("wheel_brake_input_index"):
		return
	var raw: Variant = meta.get("input_layout")
	var parser := JSON.new()
	if typeof(raw) != TYPE_STRING or raw.length() > 256 or parser.parse(raw) != OK:
		_invalid_weather = true
		return
	var layout: Variant = parser.data
	var expected := ["roll", "pitch", "yaw", "throttle", "wheel_brake"]
	if _has_flap_metadata_claim(): expected.append("flaps")
	if typeof(meta.get("fixed_brake_input_law")) != TYPE_STRING or meta.fixed_brake_input_law != FIXED_BRAKE_INPUT_LAW \\
			or typeof(meta.get("wheel_brake_input_index")) != TYPE_INT or meta.wheel_brake_input_index != 4 \\
			or not layout is Array or layout.size() != expected.size():
		_invalid_weather = true
		return
	for key: String in ["gear_law", "gear_aux_index", "gear_trace_schema", "recording_start_gear"]:
		if meta.has(key):
			_invalid_weather = true
			return
	for index: int in expected.size():
		if typeof(layout[index]) != TYPE_STRING or layout[index] != expected[index]:
			_invalid_weather = true
			return
	_fixed_brake = true
	_columns.append("cmd_wheel_brake")


'''
s = swap(s, 'func _has_gear_metadata_claim() -> bool:', helper + 'func _has_gear_metadata_claim() -> bool:')
s = swap(s, '\tif not meta.has("input_layout"):\n\t\treturn false\n\tvar raw_layout: Variant = meta.get("input_layout")', '\tif _fixed_brake: return false\n\tif not meta.has("input_layout"):\n\t\t\treturn false\n\tvar raw_layout: Variant = meta.get("input_layout")',count=2) if False else s
# Only gear claim ignores the correctly validated fixed layout.
a=s.index('func _has_gear_metadata_claim()'); b=s.index('\nfunc ',a+1)
seg=s[a:b].replace('\tif not meta.has("input_layout"):', '\tif _fixed_brake: return false\n\tif not meta.has("input_layout"):')
s=s[:a]+seg+s[b:]
s = swap(s, 'return 4 + (2 if _gear else 0) + (1 if _flaps else 0)', 'return 4 + (2 if _gear else 1 if _fixed_brake else 0) + (1 if _flaps else 0)')
s = swap(s, 'var expected_input_index: int = 6 if has_gear_claim else 4', 'var expected_input_index: int = 6 if has_gear_claim else 5 if _fixed_brake else 4')
s = swap(s, '\t\texpected_layout.append_array(GEAR_INPUT_LAYOUT.slice(4, 6))', '\t\texpected_layout.append_array(GEAR_INPUT_LAYOUT.slice(4, 6))\n\telif _fixed_brake:\n\t\texpected_layout.append("wheel_brake")')
s = swap(s, 'if not gear_claim or (meta.get("metadata_schema") != "openrc-flight-meta v8" \\\n\t\t\t\tand not (flap_claim and meta.get("metadata_schema") == "openrc-flight-meta v9"))', 'if (not gear_claim and not _fixed_brake) or (meta.get("metadata_schema") != "openrc-flight-meta v8" \\\n\t\t\t\tand not (_fixed_brake and meta.get("metadata_schema") == "openrc-flight-meta v6") \\\n\t\t\t\tand not (flap_claim and meta.get("metadata_schema") == "openrc-flight-meta v9"))')
s = swap(s, '\tif inputs.size() != _expected_input_count():', '\tif inputs.size() != _expected_input_count() or (_fixed_brake and (not is_finite(inputs[4]) or inputs[4] < 0.0 or inputs[4] > 1.0)):')
s = swap(s, 'inputs.slice(0, 4) if _gear or _flaps else inputs', 'inputs.slice(0, 4) if _gear or _flaps or _fixed_brake else inputs')
# Fixed brake column was registered before gear/flap/weather columns, but after the base columns.
s = swap(s, '\tif _electric:\n\t\t_rows.append_array(electric_row)', '\tif _fixed_brake:\n\t\t_rows.append(inputs[4])\n\tif _electric:\n\t\t_rows.append_array(electric_row)')
s = swap(s, '\tlines.append("# format: %s" % trace_format)', '\tvar fixed_brake_base_trace_format: String = trace_format\n\tif _fixed_brake: trace_format = "openrc-trace v17"\n\tlines.append("# format: %s" % trace_format)')
s = swap(s, '\tif _weather != null and _weather.is_spatial():\n\t\twritten_meta.spatial_base_trace_format', '\tif _fixed_brake:\n\t\twritten_meta.fixed_brake_base_trace_format = fixed_brake_base_trace_format\n\tif _weather != null and _weather.is_spatial():\n\t\twritten_meta.spatial_base_trace_format')
(OUT/'trace.gd').write_text(s,encoding='utf-8',newline='\n')
(OUT/'prehash.json').write_text(json.dumps(base,indent=2)+'\n')
print(json.dumps(base,indent=2))
