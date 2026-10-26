from pathlib import Path

# Godot 4d10419ca editor_file_system.cpp recognizes remap/importer="keep".
# These fixtures are raw numerical CSV, not translation tables.
for name in ['fixed_brake_trace_stik.csv', 'fixed_brake_trace_flaps.csv']:
    path = Path('app/tests/fixtures') / (name + '.import')
    assert 'importer="csv_translation"' in path.read_text(encoding='utf-8')
    path.write_text('[remap]\n\nimporter="keep"\n', encoding='utf-8')
