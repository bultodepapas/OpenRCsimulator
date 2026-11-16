import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('package_default_probe', HERE / 'macos_package_default_probe.py')
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class PackageProbeControls(unittest.TestCase):
    def setUp(self):
        self.case = Path('/qualification/openrc-package-default-probe-' + 'a' * 32)
        self.task_home = self.case / 'private-home'
        self.executable = self.case / 'OpenRC.app/Contents/MacOS/OpenRC'
        self.selection = dict(probe.SELECTION, start_sha256='1' * 64)
        self.reference = {key: key + '-value' for key in
                          ('kind', 'sha256', 'receipt_sha256', 'executable_sha256', 'pack_sha256',
                           'probe_sha256', 'architecture')}
        self.native = {key: key + '-value' for key in
                       ('kind', 'sha256', 'receipt_sha256', 'reference_receipt_sha256', 'manifest_sha256',
                        'library_sha256', 'descriptor_sha256')}

    def observation(self, mode):
        backend = 'native' if mode == 'candidate' else 'gdscript_reference'
        reason = 'Mac native default qualification is unavailable' if mode in ('missing', 'malformed') else ''
        def flight(name):
            return {'phase': name, 'backend': backend, 'tick': 40, 'soundscape_installed': True,
                    'selection': self.selection if mode != 'reference' else {},
                    'status': {'identity': {'backend': backend},
                               'requested': 'gdscript_reference' if mode == 'reference' else 'native', 'reason': reason},
                    'native_stats': {'context_calls': 1, 'stage_calls': 4} if mode == 'candidate' else {}}
        phases = ([flight('flight')] if mode == 'reference' else
                  [{'phase': 'home', 'aircraft': probe.SELECTION['aircraft'], 'menu_audio': True}, flight('flight'),
                   {'phase': 'pause', 'paused': True}, flight('restart'), {'phase': 'returned_home'}, flight('reentry')])
        phases.append({'phase': 'menu_audio_retired', 'receipt': {'complete': True, 'timed_out': False,
                                                                  'pending_playbacks': 0}})
        identity = dict(self.native, ok=True, reason='', reference_identity=dict(self.reference, ok=True, reason=''),
                        library_path=str(self.executable.parents[2] / 'Contents/Frameworks/libopenrc_native_kernel.dylib'),
                        descriptor_path=str(self.executable.parents[2] / 'Contents/Resources/openrc_native_kernel_macos.gdextension'))
        return {'verdict': 'pass', 'reason': '', 'mode': mode, 'pid': 123, 'executable': str(self.executable),
                'profile_home': str(self.task_home),
                'user_directory': str(self.task_home / 'Library/Application Support/Godot/app_userdata/OpenRC Simulator'),
                'profile_token_sha256': '2' * 64, 'marker_sha256': '' if mode == 'missing' else '3' * 64,
                'audio_driver': 'CoreAudio', 'package_identity': identity, 'phases': phases}

    def check(self, mode, data):
        probe.verify_observation(data, mode, executable=self.executable, task_home=self.task_home,
                                 token_sha='2' * 64, marker_sha='' if mode == 'missing' else '3' * 64,
                                 selection=self.selection, reference=self.reference, native=self.native)

    def test_four_distinct_route_contracts(self):
        for mode in probe.MODES:
            with self.subTest(mode=mode):
                self.check(mode, self.observation(mode))

    def test_same_screened_home_selection_is_required_after_fallback_and_restart(self):
        for mode in ('missing', 'malformed', 'candidate'):
            changed = self.observation(mode)
            changed['phases'][1]['selection'] = dict(self.selection, weather='gusty')
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.check(mode, changed)
        changed = self.observation('candidate')
        changed['phases'][3]['selection'] = dict(self.selection, start_sha256='4' * 64)
        with self.assertRaises(ValueError): self.check('candidate', changed)

    def test_fallback_smoke_uses_the_actual_fixed_home_selection(self):
        missing = self.observation('missing')
        selected = probe.observed_fallback_selection(missing)
        self.assertEqual(selected, self.selection)
        self.check('missing', missing)
        self.check('malformed', self.observation('malformed'))
        for mutation in (lambda value: value['phases'].pop(1),
                         lambda value: value['phases'][1]['selection'].update(start='runway'),
                         lambda value: value['phases'][1]['selection'].update(start_sha256='bad')):
            changed = copy.deepcopy(missing)
            mutation(changed)
            with self.assertRaises(ValueError): probe.observed_fallback_selection(changed)
        changed = self.observation('malformed')
        changed['phases'][1]['selection'] = dict(selected, start_sha256='4' * 64)
        with self.assertRaises(ValueError): self.check('malformed', changed)

    def test_missing_marker_bad_backend_and_package_mutations_are_refused(self):
        mutations = [lambda x: x.update(marker_sha256='3' * 64),
                     lambda x: x.update(user_directory='/Users/real/Library/Application Support/Godot/app_userdata/OpenRC Simulator'),
                     lambda x: x.update(audio_driver='Dummy'),
                     lambda x: x['phases'][1]['status'].update(reason='unrelated refusal'),
                     lambda x: x['package_identity'].update(library_sha256='other')]
        for mutate in mutations:
            changed = self.observation('missing')
            mutate(changed)
            with self.subTest(mutation=mutate), self.assertRaises(ValueError): self.check('missing', changed)

    def test_candidate_requires_native_activity_and_normal_menu_retirement(self):
        for mutate in (lambda x: x['phases'][1]['native_stats'].update(stage_calls=0),
                       lambda x: x['phases'][-1]['receipt'].update(pending_playbacks=1),
                       lambda x: x['phases'].pop(2)):
            changed = self.observation('candidate')
            mutate(changed)
            with self.subTest(mutation=mutate), self.assertRaises(ValueError): self.check('candidate', changed)

    def test_seed_selection_and_child_home_are_bounded_and_independent(self):
        marker = {'format': 'openrc-macos-native-package-default v2', 'scope': 'package-macos-arm64',
                  'allowed_selections': [self.selection]}
        self.assertEqual(probe.chosen_selection(marker), self.selection)
        bad = copy.deepcopy(marker)
        bad['allowed_selections'][0]['start'] = 'runway'
        with self.assertRaises(ValueError): probe.chosen_selection(bad)
        with patch.dict(probe.os.environ, {'HOME': '/Users/real', 'OPENRC_METALFX_TRIAL': '1',
                                           'OPENRC_TESTQUEUE_CONTEXT': 'test-context'}, clear=True):
            child = probe.child_environment(self.task_home, 'candidate', '3' * 64, '2' * 64)
            self.assertEqual(probe.os.environ['HOME'], '/Users/real')
            self.assertEqual(child['HOME'], str(self.task_home))
            self.assertNotIn('OPENRC_METALFX_TRIAL', child)
            self.assertEqual(child['OPENRC_TESTQUEUE_CONTEXT'], 'test-context')

    def test_linked_profile_parent_is_refused_when_platform_can_create_it(self):
        with tempfile.TemporaryDirectory(prefix='profile-link-control-', dir=HERE) as directory:
            root = Path(directory).resolve()
            self.assertTrue(root.is_relative_to(HERE.resolve()))
            real = root / 'private-home'
            real.mkdir()
            probe.no_links(real)
            link = root / 'linked-home'
            try:
                os.symlink(real, link, target_is_directory=True)
            except OSError as error:
                self.skipTest('platform refused a disposable symlink: ' + str(error))
            with self.assertRaises(ValueError): probe.no_links(link)

    def test_final_reader_reopens_checked_case_instead_of_trusting_summary(self):
        with tempfile.TemporaryDirectory(prefix='home-proof-control-', dir=HERE) as directory:
            root = Path(directory).resolve()
            self.assertTrue(root.is_relative_to(HERE.resolve()))
            original = root / 'original/OpenRC.app/Contents/MacOS/OpenRC'
            original.parent.mkdir(parents=True)
            original.write_bytes(b'fake-executable')
            marker = {'format': 'openrc-macos-native-package-default v2', 'scope': 'package-macos-arm64',
                      'allowed_selections': [self.selection]}
            marker_data = json.dumps(marker).encode()
            candidate = root / 'candidate.json'
            candidate.write_bytes(marker_data)
            proof_dir = root / 'proof'
            proof_dir.mkdir()
            rows = []
            for index, mode in enumerate(probe.MODES):
                self.case = proof_dir / (probe.CASE_PREFIX + f'{index:032x}')
                self.task_home = self.case / 'private-home'
                user_dir = self.task_home / 'Library/Application Support/Godot/app_userdata/OpenRC Simulator'
                user_dir.mkdir(parents=True)
                token = b'test-token-' + str(index).encode()
                (self.task_home / '.openrc-package-default-profile').write_bytes(token)
                bundle = self.case / 'OpenRC.app'
                self.executable = bundle / 'Contents/MacOS/OpenRC'
                self.executable.parent.mkdir(parents=True)
                self.executable.write_bytes(b'fake-executable')
                mode_marker = b'{' if mode == 'malformed' else marker_data if mode in ('candidate', 'reference') else b''
                if mode_marker:
                    bundle.with_name(bundle.name + '.openrc-native-default').write_bytes(mode_marker)
                observation = self.observation(mode)
                observation.update(pid=index + 100, profile_token_sha256=hashlib.sha256(token).hexdigest(),
                                   marker_sha256=hashlib.sha256(mode_marker).hexdigest() if mode_marker else '')
                command = [str(self.executable), '--rendering-method', 'forward_plus', '--rendering-driver', 'metal']
                if mode == 'reference':
                    command += ['--', '--quick-flight', '--physics-backend=gdscript_reference']
                checked_dir = self.case / 'checked/job'
                checked_dir.mkdir(parents=True)
                log = (probe.PREFIX + json.dumps(observation) + '\n').encode()
                log_path = checked_dir / 'engine.log'
                log_path.write_bytes(log)
                report_path = checked_dir / 'report.json'
                report = {'format': 'openrc-godot-check v1', 'complete': True, 'ok': True, 'reason': 'passed',
                          'process_exit': 0, 'warnings_as_errors': True, 'counts': {'error': 0, 'warning': 0},
                          'command': command, 'report': str(report_path), 'log': str(log_path),
                          'capture_id': 'capture-' + str(index), 'log_sha256': hashlib.sha256(log).hexdigest()}
                report_data = json.dumps(report).encode()
                report_path.write_bytes(report_data)
                rows.append({'mode': mode, 'case': str(self.case), 'pid': observation['pid'],
                             'checked_report': str(report_path), 'checked_sha256': hashlib.sha256(report_data).hexdigest(),
                             'engine_log_sha256': hashlib.sha256(log).hexdigest(), 'observation': observation})
            proof = {'format': 'openrc-package-default-home-proof v1', 'status': 'passed',
                     'candidate_sha256': hashlib.sha256(marker_data).hexdigest(), 'selection': self.selection,
                     'reference': self.reference, 'native': self.native, 'cases': rows}
            proof_path = proof_dir / 'home-proof.json'
            proof_path.write_text(json.dumps(proof))
            receipts = SimpleNamespace(bundle_from_executable=lambda exe: exe.parents[2],
                                       verify=lambda exe, arch: self.reference,
                                       verify_native=lambda exe, arch: self.native)
            with patch.object(probe, '_load_receipt_module', return_value=receipts), patch.object(probe, '_signature'):
                verified = probe.verify_home_proof(proof_path, original, candidate, hashlib.sha256(marker_data).hexdigest())
                self.assertEqual(verified['cases'], 4)
                fallback = dict(proof, format='openrc-package-default-fallback-smoke v1', cases=rows[:2])
                proof_path.write_text(json.dumps(fallback))
                with self.assertRaises(ValueError):
                    probe.verify_home_proof(proof_path, original, candidate, hashlib.sha256(marker_data).hexdigest())
                proof_path.write_text(json.dumps(proof))
                changed_log = Path(rows[1]['checked_report']).with_name('engine.log')
                changed_log.write_bytes(changed_log.read_bytes() + b'changed\n')
                with self.assertRaises(ValueError):
                    probe.verify_home_proof(proof_path, original, candidate, hashlib.sha256(marker_data).hexdigest())


if __name__ == '__main__':
    unittest.main(verbosity=2)
