#!/usr/bin/env python3
"""Schema/production-loader agreement and preflight failure tests."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from cases import build_cases
from check import FLEET, ROOT, SCHEMA, problems, read_json, validator

HERE = Path(__file__).resolve().parent


class ContractTests(unittest.TestCase):
    def test_schema_and_real_loader_agree_on_cases(self):
        cases = build_cases()
        self.assertEqual(len({case.name for case in cases}), len(cases), 'case names must be unique')
        contract = validator()
        godot = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(ROOT / 'app/get-godot.sh')], text=True).strip()
        with tempfile.TemporaryDirectory(prefix='openrc-schema-') as folder:
            paths = []
            for index, case in enumerate(cases):
                path = Path(folder) / f'{index}.json'
                path.write_text(json.dumps(case.data, allow_nan=False), encoding='utf-8')
                paths.append(str(path))
            manifest = Path(folder) / 'manifest.json'
            manifest.write_text(json.dumps(paths), encoding='utf-8')
            run = subprocess.run([godot, '--headless', '--path', str(ROOT / 'app'),
                                  '--script', str(HERE / 'loader_probe.gd'), '--', str(manifest)],
                                 text=True, capture_output=True, timeout=300)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotRegex(run.stdout + run.stderr, r'(?m)^(?:SCRIPT )?ERROR:')
        rows = [json.loads(line.removeprefix('DATA4A '))
                for line in run.stdout.splitlines() if line.startswith('DATA4A ')]
        self.assertEqual([r['index'] for r in rows], list(range(len(cases))))
        evidence = []
        for case, row in zip(cases, rows):
            errors = problems(case.data, contract)
            with self.subTest(case=case.name):
                self.assertEqual(not errors, case.schema_ok, errors[:3])
                self.assertEqual(row['ok'], case.loader_ok, row['errors'])
                if not case.loader_ok:
                    self.assertTrue(row['errors'], 'refusal must explain why')
            evidence.append({'case': case.name, 'schema_ok': not errors,
                             'loader_ok': row['ok'], 'expected_schema_ok': case.schema_ok,
                             'expected_loader_ok': case.loader_ok})
        report = os.environ.get('OPENRC_SCHEMA_REPORT')
        if report:
            inputs = [SCHEMA, ROOT / 'app/physics/aircraft_data.gd', HERE / 'cases.py',
                      HERE / 'boundary_cases.py',
                      HERE / 'check.py', HERE / 'loader_probe.gd', HERE / 'test_contract.py',
                      ROOT / 'app/tests/fixtures/stik_wash_profile.json',
                      *sorted(FLEET.glob('*.json'))]
            Path(report).write_text(json.dumps({
                'format': 'openrc-schema-agreement v1',
                'inputs_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in inputs},
                'cases': evidence,
            }, indent=2) + '\n', encoding='utf-8')
        print(f'{len(cases)} schema/loader cases; {sum(c.loader_ok for c in cases)} valid controls; '
              f'{sum(c.schema_ok != c.loader_ok for c in cases)} runtime-only checks', flush=True)

    def test_nonfinite_json_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.json'
            for value in ['NaN', 'Infinity', '-Infinity', '1e999', '-1e999', '9' * 400]:
                with self.subTest(value=value):
                    path.write_text('{"number":' + value + '}', encoding='utf-8')
                    with self.assertRaises(ValueError):
                        read_json(path)

    def test_contract_detects_schema_mutations(self):
        run = subprocess.run([sys.executable, str(HERE / 'check_mutations.py')],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertTrue(json.loads(run.stdout)['mutations'])

    def test_cli_exit_status_and_diagnostic(self):
        run = subprocess.run([sys.executable, str(HERE / 'check.py')], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('4 aircraft, 0 failed', run.stdout)
        with tempfile.TemporaryDirectory() as folder:
            bad = Path(folder) / 'bad.json'
            data = read_json(FLEET / 'jensen_ugly_stik_60.json')
            data['reference']['wing_span']['unit'] = 'ft'
            bad.write_text(json.dumps(data), encoding='utf-8')
            run = subprocess.run([sys.executable, str(HERE / 'check.py'), str(bad)],
                                 capture_output=True, text=True)
            self.assertEqual(run.returncode, 1)
            self.assertIn('/reference/wing_span/unit', run.stderr)
            bad.write_text('{broken', encoding='utf-8')
            run = subprocess.run([sys.executable, str(HERE / 'check.py'), str(bad)],
                                 capture_output=True, text=True)
            self.assertEqual(run.returncode, 1)
            self.assertNotIn('Traceback', run.stderr)


if __name__ == '__main__':
    unittest.main()
