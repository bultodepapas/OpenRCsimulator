from pathlib import Path
import hashlib

directory = Path(__file__).resolve().parent / 'reader'
draft = (directory/'test_flight_log_inputs.gd').read_text(encoding='utf-8')
draft = draft.replace('const Legacy := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/before.gd")\n', '')
draft = draft.replace('var destination := ""\n', 'var destination := ""\nvar historical: Dictionary = {}\n')
fixture = directory/'flight_log_input_columns.json'
sha = hashlib.sha256(fixture.read_bytes()).hexdigest()
draft = draft.replace('func _unit_contracts() -> void:\n', '''func _unit_contracts() -> void:
	var path := "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/flight_log_input_columns.json"
	var reference_text := FileAccess.get_file_as_string(path).replace("\\r\\n", "\\n")
	check("frozen original columns, normalized LF", reference_text.sha256_text() == "%s")
	historical = JSON.parse_string(reference_text).cases
''' % sha)
draft = draft.replace('var_to_bytes(Legacy.columns(layout))', 'var_to_bytes(PackedStringArray(historical[str(width)].columns))')
draft = draft.replace('\tvar original: Dictionary = Legacy.inspect(file_path)\n', '')
draft = draft.replace('"baseline and candidate reader agree complete " + id, original.ok and read.ok', '"actual stock recording is complete " + id, read.ok')
old='\t\tcheck("stock CSV columns unchanged " + id, var_to_bytes(Legacy.columns(read.header.layout)) == var_to_bytes(Reader.columns(read.header.layout, read.header.metadata)))\n'
assert draft.count(old)==1
draft=draft.replace(old, '')
old='\t\tcheck("baseline exposes valid-checksum role-confusion defect " + id, Legacy.inspect(bad_path).ok)\n'
assert draft.count(old)==1
draft=draft.replace(old, '')
(directory/'test_flight_log_inputs_production.gd').write_text(draft,encoding='utf-8',newline='\n')
print('Detached production test and frozen oracle prepared.')
