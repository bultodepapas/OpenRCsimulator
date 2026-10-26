from pathlib import Path
edits = {
    Path('tmp/gp12-fixed-brake-session/evidence-readme.md'): {
        'brake index4': 'brake index 4', 'flaps at5': 'flaps at 5',
        'and260 ticks': 'and 260 ticks', 'Python13 invoked directly': '13 Python tests invoked directly',
        'counts140/237': 'counts 140/237', 'repeated256': 'repeated 256',
        'across96 ticks': 'across 96 ticks', 'existing260-tick': 'existing 260-tick',
        'passes256 assertions': 'passes 256 assertions',
        'SHA2bc02a0f...': '`2bc02a0f...`', 'SHA1c529262...': '`1c529262...`',
    },
    Path('docs/research/ground-physics/GP-12/README.md'): {
        'suites pass714 assertions': 'suites pass 714 assertions',
        'input4, with optional flaps at5': 'input 4, with optional flaps at 5',
        'records256 focused assertions,3,247 existing flight-log assertions and13 Python tests':
            'records 256 focused assertions, 3,247 existing flight-log assertions and 13 Python tests',
        'pass96 candidate ticks': 'pass 96 candidate ticks',
        'cohort passes232 new': 'cohort passes 232 new',
        'plus48 independent assertions and16 Python': 'plus 48 independent assertions and 16 Python',
    },
    Path('docs/AIRCRAFT_CONTRACT.md'): {
        'at input index4, then optional flaps at index5': 'at input index 4, then optional flaps at index 5',
    },
}
for path, replacements in edits.items():
    value = path.read_text(encoding='utf-8')
    for before, after in replacements.items():
        assert before in value, (path, before)
        value = value.replace(before, after)
    path.write_text(value, encoding='utf-8')
