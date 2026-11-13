"""Fail-closed source rebind checks; no Godot or historical outputs are generated."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('publication_pack_under_test', HERE / 'audit_fixture_pack.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)
ROOT = HERE.parents[1]


class PublicationSourceRebindTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='publication-source-rebind-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.base = 'a' * 40
        self.candidate = 'b' * 40
        self.original = json.loads((ROOT / 'app/tests/fixtures/publication_fixture_bridge.json').read_text())
        self.prior = copy.deepcopy(self.original)
        self.prior['candidate_commit'] = self.base
        self.prior['families'] = {'shaft': {}, 'weather': {}}
        self.old_bytes, self.new_bytes = {}, {}
        for name, item in self.prior['source_pins'].items():
            current = (ROOT / 'app' / name).read_bytes()
            if item['mode'] == 'script-lf':
                current = current.replace(b'\r\n', b'\n')
            self.new_bytes[name] = current
            self.old_bytes[name] = current + b'\n# historical Session\n' if name == pack.SOURCE_REBIND_SESSION else current
            item['sha256'] = pack.digest(self.old_bytes[name])
        self.prior['candidate_overlays'][pack.SOURCE_REBIND_SESSION] = self.prior['source_pins'][pack.SOURCE_REBIND_SESSION]['sha256']
        self.pins = {
            'baseline': {name: pack.digest(value) for name, value in self.old_bytes.items()},
            'candidate': {name: pack.digest(value) for name, value in self.new_bytes.items()},
        }
        self.trees = {role: {'app/' + name: {'git_blob': pack.digest(value)[:40], 'mode': '100644'}
                             for name, value in source.items()}
                      for role, source in (('baseline', self.old_bytes), ('candidate', self.new_bytes))}
        self.expected = {}
        for platform in ('Windows', 'Linux'):
            for family, names in (('shaft', ('coupled-rk4', 'split')),
                                  ('weather', ('calm', 'cool-dense', 'gusty', 'turbulent'))):
                cases = {}
                self.prior['families'][family][platform] = {}
                for name in names:
                    frames = [f'{name}-frame-{tick}'.encode() for tick in range(25)]
                    events = [f'{name}-event-{tick}'.encode() for tick in range(25)]
                    case_hash, event_hash = pack.digest(b''.join(frames)), pack.digest(b''.join(events))
                    cases[name] = {'frames': [part.hex() for part in frames], 'events': [part.hex() for part in events],
                                   'configuration': b'configuration'.hex(), 'sha256': case_hash}
                    self.prior['families'][family][platform][name] = {'current_sha256': case_hash,
                                                                      'events_sha256': event_hash}
                capture = {'format': f'ci-audit-{family}-capture-v1', 'os': platform,
                           'engine': {'hash': pack.ENGINE2}, 'cases': cases}
                raw = json.dumps(capture, sort_keys=True).encode()
                self.expected[(platform.lower(), family)] = ('unused', pack.digest(raw), 'unused')
                directory = self.directory / platform.lower()
                directory.mkdir(exist_ok=True)
                for role in ('baseline', 'candidate'):
                    (directory / f'{role}-{family}.json').write_bytes(raw)
        self.fixture = self.directory / 'prior.json'
        self.fixture.write_bytes((json.dumps(self.prior, sort_keys=True, separators=(',', ':')) + '\n').encode())
        self.prior_sha = pack.digest(self.fixture.read_bytes())
        for platform in ('Windows', 'Linux'):
            directory = self.directory / platform.lower()
            runs = {}
            for role in ('baseline', 'candidate'):
                for family in ('shaft', 'weather'):
                    name = f'{role}-{family}'
                    base = 'C:/fixture' if platform == 'Windows' else '/fixture'
                    engine = base + ('/godot_console.exe' if platform == 'Windows' else '/godot')
                    executable = base + ('/godot.exe' if platform == 'Windows' else '/godot')
                    project = base + '/' + role + '/app'
                    count = 2 if family == 'shaft' else 4
                    checks = 55 if family == 'shaft' else 109
                    marker = f'CI_AUDIT_{family.upper()}_CAPTURE checks={checks} failures=0 cases={count}'
                    log = (marker + '\n').encode()
                    report = {'format': 'openrc-godot-check v1', 'capture_id': platform + '-' + name,
                              'command': [engine, '--headless', '--path', project, '--script',
                                          base + f'/audit_fixture_{family}_capture.gd'],
                              'ok': True, 'complete': True, 'process_exit': 0, 'exit_code': 0, 'reason': 'passed',
                              'warnings_as_errors': True, 'counts': {'error': 0, 'warning': 0},
                              'missing_required_text': [], 'log_sha256': pack.digest(log)}
                    (directory / (name + '.log')).write_bytes(log)
                    (directory / (name + '-report.json')).write_text(json.dumps(report))
                    commit = self.base if role == 'baseline' else self.candidate
                    source = self.old_bytes if role == 'baseline' else self.new_bytes
                    files = {'app/' + path: {**self.trees[role]['app/' + path], 'sha256': pack.digest(data),
                                             'size': len(data)} for path, data in source.items()}
                    inventory = (json.dumps({'format': 'openrc-publication-source-inventory-v1',
                                             'commit': commit, 'attributes_sha256': pack.digest(('attributes-' + commit).encode()),
                                             'files': files}, sort_keys=True,
                                            separators=(',', ':')) + '\n').encode()
                    (directory / (name + '-before.json')).write_bytes(inventory)
                    (directory / (name + '-after.json')).write_bytes(inventory)
                    state = {'engine_sha256': pack.SOURCE_REBIND_ENGINES[platform],
                             'engine_executable_sha256': pack.SOURCE_REBIND_EXECUTABLES[platform],
                             'source_inventory_sha256': pack.digest(inventory),
                             'capture_script_sha256': pack.digest((HERE / f'audit_fixture_{family}_capture.gd').read_bytes().replace(b'\r\n', b'\n')),
                             'checked_runner_sha256': pack.digest((HERE / 'run_checked.py').read_bytes().replace(b'\r\n', b'\n')),
                             'source_pins': self.pins[role]}
                    prefix = platform.lower() + '/'
                    runs[name] = {'commit': commit, 'engine_path': engine, 'engine_executable': executable,
                                  'project_path': project, 'capture': prefix + name + '.json',
                                  'log': prefix + name + '.log', 'report': prefix + name + '-report.json',
                                  'inventory_before': prefix + name + '-before.json',
                                  'inventory_after': prefix + name + '-after.json',
                                  'capture_sha256': pack.digest((directory / (name + '.json')).read_bytes()),
                                  'log_sha256': pack.digest(log),
                                  'report_sha256': pack.digest((directory / (name + '-report.json')).read_bytes()),
                                  'capture_script_sha256': state['capture_script_sha256'],
                                  'checked_runner_sha256': state['checked_runner_sha256'],
                                  'before': state, 'after': copy.deepcopy(state),
                                  'composition': {'kind': role + '-commit-v1', 'base_commit': commit,
                                                  'overlay_commit': None, 'overlay_paths': [], 'overlay_tree_ids': {}}}
            (directory / 'manifest.json').write_text(json.dumps({'format': 'openrc-publication-rebind-capture-v1',
                'platform': platform, 'runs': runs,
                'mode_validation': 'git-index-only-windows' if platform == 'Windows' else 'git-and-posix-executable'}))
        self.out = self.directory / 'candidate.json'
        self.receipt = self.directory / 'receipt.json'

    def run_rebind(self):
        def source(_repo, commit, name, _mode):
            return (self.old_bytes if commit == self.base else self.new_bytes)[name]
        def tree(_repo, commit):
            return self.trees['baseline' if commit == self.base else 'candidate']
        def normalized(_repo, commit, path):
            if path == '.gitattributes':
                return ('attributes-' + commit).encode()
            return (ROOT / path).read_bytes().replace(b'\r\n', b'\n')
        with patch.object(pack, 'SOURCE_REBIND_PRIOR', self.prior_sha), patch.object(pack, 'SOURCE_REBIND_BASE', self.base), \
             patch.object(pack, 'V4_EVIDENCE', self.expected), patch.object(pack, 'source_rebind_git_bytes', side_effect=source), \
             patch.object(pack, 'source_rebind_tree', side_effect=tree), \
             patch.object(pack, 'source_rebind_git_normalized', side_effect=normalized):
            pack.rebind_source(self.directory, self.fixture, self.out, self.receipt, self.candidate)

    def change_manifest(self, platform, fn):
        path = self.directory / platform / 'manifest.json'
        data = json.loads(path.read_text())
        fn(data['runs'])
        path.write_text(json.dumps(data))

    def change_report(self, platform, name, fn):
        path = self.directory / platform / (name + '-report.json')
        data = json.loads(path.read_text())
        fn(data)
        path.write_text(json.dumps(data))
        self.change_manifest(platform, lambda runs: runs[name].update(report_sha256=pack.digest(path.read_bytes())))

    def forge_inventory(self, platform, name):
        directory = self.directory / platform
        before, after = directory / (name + '-before.json'), directory / (name + '-after.json')
        value = json.loads(before.read_text())
        value['files']['app/sim/flight_session.gd']['sha256'] = '0' * 64
        raw = (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()
        before.write_bytes(raw)
        after.write_bytes(raw)
        def change(runs):
            runs[name]['before']['source_inventory_sha256'] = pack.digest(raw)
            runs[name]['after']['source_inventory_sha256'] = pack.digest(raw)
        self.change_manifest(platform, change)

    def test_complete_rebind_preserves_frozen_frames_and_events(self):
        self.run_rebind()
        actual = json.loads(self.out.read_text())
        self.assertEqual(actual['families'], self.prior['families'])
        self.assertEqual(actual['reference_commit'], self.prior['reference_commit'])
        self.assertEqual(actual['requalification'], self.prior['requalification'])
        self.assertEqual(actual['candidate_commit'], self.candidate)
        self.assertEqual(actual['source_pins'][pack.SOURCE_REBIND_SESSION]['sha256'],
                         self.pins['candidate'][pack.SOURCE_REBIND_SESSION])
        self.assertEqual(len(json.loads(self.receipt.read_text())['captures']), 8)
        with self.assertRaises(ValueError):
            self.run_rebind()

    def test_rejects_failed_or_forged_evidence_without_writing_candidate(self):
        mutations = (
            lambda: self.change_manifest('windows', lambda runs: runs['candidate-shaft']['after'].update(engine_sha256='0' * 64)),
            lambda: self.change_manifest('linux', lambda runs: runs['candidate-weather']['before']['source_pins'].update({'sim/simulation.gd': '0' * 64})),
            lambda: self.change_manifest('linux', lambda runs: runs['baseline-shaft']['composition'].update(kind='candidate-commit-v1')),
            lambda: (self.directory / 'linux/candidate-shaft-after.json').write_bytes(b'changed'),
            lambda: self.forge_inventory('linux', 'candidate-shaft'),
            lambda: self.change_report('linux', 'candidate-shaft', lambda report: report.update(ok=False)),
            lambda: self.change_report('windows', 'candidate-shaft', lambda report: report.update(capture_id='Windows-baseline-shaft')),
            lambda: (self.directory / 'windows/candidate-shaft.json').write_bytes(b'changed'),
            lambda: (self.directory / 'linux/candidate-shaft.log').write_bytes(b'CI_AUDIT_SHAFT_CAPTURE checks=58 failures=1 cases=2\n'),
        )
        for change in mutations:
            with self.subTest(change=change):
                # Reset only the input documents touched by this case.
                backups = {path: path.read_bytes() for path in self.directory.rglob('*') if path.is_file()}
                try:
                    change()
                    with self.assertRaises(ValueError):
                        self.run_rebind()
                    self.assertFalse(self.out.exists())
                    self.assertFalse(self.receipt.exists())
                finally:
                    for path, raw in backups.items():
                        path.write_bytes(raw)

    def test_even_a_rehashed_capture_cannot_change_the_event_tape(self):
        path = self.directory / 'windows/candidate-shaft.json'
        capture = json.loads(path.read_text())
        capture['cases']['split']['events'][0] = b'altered'.hex()
        raw = json.dumps(capture, sort_keys=True).encode()
        with self.assertRaisesRegex(ValueError, 'typed frames or events differ'):
            pack.source_rebind_capture(raw, pack.digest(raw), 'Windows', 'shaft', self.prior)


if __name__ == '__main__':
    unittest.main()
