import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('package_promotion', HERE / 'macos_package_promotion.py')
promotion = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(promotion)
PROBE_SPEC = importlib.util.spec_from_file_location('package_promotion_probe', HERE / 'macos_package_default_probe.py')
probe = importlib.util.module_from_spec(PROBE_SPEC)
PROBE_SPEC.loader.exec_module(probe)
BASELINE_SPEC = importlib.util.spec_from_file_location('package_promotion_baseline',
                                                       HERE.parent / 'performance/session_baseline.py')
baseline = importlib.util.module_from_spec(BASELINE_SPEC)
BASELINE_SPEC.loader.exec_module(baseline)


class SourceConfigurationControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=HERE)
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name).resolve()
        self.root = self.parent / 'checkout'
        self.root.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT='0')
        subprocess.run(['git', 'init', '-q', str(self.root)], env=self.env, check=True)
        self.git('config', 'core.autocrlf', 'false')
        self.git('config', 'user.name', 'OpenRC test')
        self.git('config', 'user.email', 'openrc-test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        (self.root / 'app').mkdir()
        (self.root / 'research').mkdir()
        self.preset = self.root / 'app/export_presets.cfg'
        self.original = ('[preset.0]\nname="Linux"\n[preset.0.options]\nkey="untouched"\n'
                         '[preset.2]\nname="macOS"\n[preset.2.options]\n'
                         'binary_format/architecture="universal"\n'
                         'application/bundle_identifier="org.openrc.public"\n').encode()
        self.preset.write_bytes(self.original)
        (self.root / 'app/settings.gd').write_text('const value = 1\n', encoding='utf-8')
        (self.root / 'research/source.py').write_text('value = 1\n', encoding='utf-8')
        self.git('add', '--', 'app', 'research')
        self.git('commit', '-q', '-m', 'fixture')
        self.template = self.parent / 'paired-template.zip'
        self.template.write_bytes(b'qualified template fixture')
        self.template_sha = hashlib.sha256(self.template.read_bytes()).hexdigest()
        self.reference = {'source_commit': self.git('rev-parse', 'HEAD').strip(),
                          'source_tree': self.git('rev-parse', 'HEAD^{tree}').strip(),
                          'source_worktree_sha256': 'a' * 64}
        self.snapshot = {'commit': self.reference['source_commit'], 'tree': self.reference['source_tree'],
                         'dirty': True, 'worktree_sha256': self.reference['source_worktree_sha256']}
        self.release = {'selection': {'pair': {'export_template': str(self.template)}},
                        'package': {'engine_pair': {'export_template_sha256': self.template_sha}}}
        self.expected = ('[preset.0]\nname="Linux"\n[preset.0.options]\nkey="untouched"\n'
                         '[preset.2]\nname="macOS"\n[preset.2.options]\n'
                         'binary_format/architecture="arm64"\n'
                         'application/bundle_identifier="org.openrc.research.metalfx.native26production"\n'
                         '\ncustom_template/release=' + json.dumps(str(self.template)) + '\n').encode()
        self.preset.write_bytes(self.expected)

    def git(self, *arguments):
        return subprocess.run(['git', '-C', str(self.root), *arguments], check=True, env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout

    def check_source(self):
        return promotion.verify_source_configuration(self.root, self.snapshot, self.reference, self.release, probe)

    def test_exact_dirty_preset_and_clean_checkout(self):
        result = self.check_source()
        self.assertEqual(result['kind'], 'paired-mac-local-export-preset')
        self.assertEqual(result['export_template_sha256'], self.template_sha)
        self.assertEqual(result['preset_sha256'], hashlib.sha256(self.expected).hexdigest())
        self.preset.write_bytes(self.original)
        self.snapshot['dirty'] = False
        self.assertEqual(self.check_source(), {'kind': 'clean'})

    def test_other_tracked_staged_or_untracked_file_is_rejected(self):
        other = self.root / 'research/source.py'
        other.write_text('value = 2\n', encoding='utf-8')
        with self.assertRaises(promotion.AdmissionError): self.check_source()
        other.write_text('value = 1\n', encoding='utf-8')
        for location in (self.root / 'app/untracked.gd', self.root / 'research/untracked.py'):
            location.write_text('extra\n', encoding='utf-8')
            with self.subTest(location=location), self.assertRaises(promotion.AdmissionError): self.check_source()
            location.unlink()
        self.git('add', '--', 'app/export_presets.cfg')
        with self.assertRaises(promotion.AdmissionError): self.check_source()

    def test_extra_override_or_other_preset_bytes_are_rejected(self):
        for value in (self.expected + b'other/override=true\n',
                      self.expected.replace(b'key="untouched"', b'key="changed"'),
                      self.expected.replace(b'architecture="arm64"', b'architecture="universal"'),
                      self.expected.replace(b'org.openrc.research.metalfx.native26production', b'org.other')):
            self.preset.write_bytes(value)
            with self.subTest(value=value[-80:]), self.assertRaises(promotion.AdmissionError): self.check_source()

    def test_different_template_path_or_bytes_are_rejected(self):
        other = self.parent / 'other-template.zip'
        other.write_bytes(self.template.read_bytes())
        self.release['selection']['pair']['export_template'] = str(other)
        with self.assertRaises(promotion.AdmissionError): self.check_source()
        self.release['selection']['pair']['export_template'] = str(self.template)
        self.template.write_bytes(b'changed template fixture')
        with self.assertRaises(promotion.AdmissionError): self.check_source()
        self.template.write_bytes(b'qualified template fixture')
        self.release['package']['engine_pair']['export_template_sha256'] = '0' * 64
        with self.assertRaises(promotion.AdmissionError): self.check_source()

    def test_hidden_index_flags_and_receipt_mismatch_are_rejected(self):
        self.git('update-index', '--assume-unchanged', 'app/settings.gd')
        with self.assertRaises(promotion.AdmissionError): self.check_source()
        self.git('update-index', '--no-assume-unchanged', 'app/settings.gd')
        self.git('update-index', '--skip-worktree', 'research/source.py')
        with self.assertRaises(promotion.AdmissionError): self.check_source()
        self.git('update-index', '--no-skip-worktree', 'research/source.py')
        for key, value in (('source_commit', 'b' * 40), ('source_tree', 'b' * 40),
                           ('source_worktree_sha256', 'b' * 64)):
            old = self.reference[key]
            self.reference[key] = value
            with self.subTest(key=key), self.assertRaises(promotion.AdmissionError): self.check_source()
            self.reference[key] = old

    def test_actual_capture_rejects_stale_receipt_after_preset_change(self):
        clean_environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        with patch.dict(os.environ, clean_environment, clear=True):
            captured = baseline.capture_mac_release_source(self.root)
            self.assertIs(captured['dirty'], True)
            reference = {'source_commit': captured['commit'], 'source_tree': captured['tree'],
                         'source_worktree_sha256': captured['worktree_sha256']}
            promotion.verify_source_configuration(self.root, captured, reference, self.release, probe)
            self.preset.write_bytes(self.expected + b'# later change\n')
            changed = baseline.capture_mac_release_source(self.root)
            self.assertNotEqual(changed['worktree_sha256'], captured['worktree_sha256'])
            with self.assertRaises(promotion.AdmissionError):
                promotion.verify_source_configuration(self.root, changed, reference, self.release, probe)

    def test_git_overrides_and_replacement_refs_are_rejected(self):
        promotion._require_git_environment({'PATH': 'fixture'})
        with self.assertRaises(promotion.AdmissionError):
            promotion._require_git_environment({'GIT_INDEX_FILE': '/different/index'})
        replacement = self.git('commit-tree', 'HEAD^{tree}', '-p', 'HEAD', '-m', 'replacement').strip()
        self.git('replace', self.snapshot['commit'], replacement)
        with self.assertRaises(promotion.AdmissionError): self.check_source()


def sample(role: str, capture: str, start: str) -> dict:
    scenario = {'trim': {'throttle': 0.5}, 'frame_generation_requested': False,
                'display_link_requested': False, 'metalfx_trial_requested': False,
                'aircraft_id': 'jensen-das-ugly-stik-60', 'weather': {'preset': 'calm'},
                'configuration': ('d' if role == 'gdscript_reference' else 'e') * 64,
                'screened_configuration_sha256': 'f' * 64,
                'screened_domain': {'selection': {'ok': True, 'reason': '', 'profile': 'production',
                    'aircraft': 'jensen-das-ugly-stik-60', 'battery': 'ideal', 'start': 'airborne',
                    'weather': 'calm', 'start_sha256': 'a' * 64},
                    'branches': {'soft_hull': True, 'flap_mix_owner': 'simulator', 'shaft_integrator': 'coupled-rk4',
                        'wheel_count': 3, 'wheel_layout': 'test', 'gear_retractable': False, 'wheel_brake': False,
                        'flaps': False, 'battery_dynamic': False, 'battery_pack': False, 'electric_law': 'test',
                        'turbine_continuous': False, 'glow': False, 'liquid': False, 'weather_calm': True,
                        'weather_atmosphere': False, 'weather_spatial': False, 'weather_vertical': False}},
                'arguments': ['--frametimes=' + capture, '--package-flight-receipt=' + capture,
                              '--physics-backend=' + role,
                              '--experimental-native-macos=' + ('true' if role == 'native' else 'false'),
                              '--warmup=30', '--t=120']}
    render = {'backend': 'forward_plus', 'driver': 'metal', 'window_size': [1920, 1080]}
    points = [{'start_tick': 1, 'end_tick': 6000, 'partial': False, 'sha256': 'a' * 64},
              {'start_tick': 6001, 'end_tick': 12000, 'partial': False, 'sha256': 'b' * 64}]
    return {'summary': {'collection_valid': True, 'promotion_eligible': False,
                        'route': 'app-root-direct-flight-fixed-circuit', 'capture_id': capture,
                        'duration': {'eligible': True, 'minimum_sample_s': 120}, 'rendering': {'eligible': True},
                        'pacing': {'pass': True}, 'drawable': {'actual_1080p': True},
                        'resources': {'host_state': {'status': 'complete',
                                                    'thermal': {'status': 'ok', 'values': ['nominal']},
                                                    'low_power': {'status': 'ok', 'values': [False]},
                                                    'power_source': {'status': 'ok', 'values': ['ac']},
                                                    'memory_pressure': {'events': [], 'boundary_uncertain_events': []}},
                                      'cpu': {'per_matched_simulated_second_estimate': 1.0},
                                      'process_memory': {'rss_bytes': {'status': 'ok', 'sampled_peak': 100}}},
                        'metrics': {'frame_ms': {'p95': 17.0, 'p99': 24.0}},
                        'scenario': copy.deepcopy(scenario), 'render_scope': copy.deepcopy(render)},
            'health': {'capture_id': capture, 'backend_identity': {'backend': role},
                       'scenario': scenario, 'render_scope': render,
                       'initial_checkpoint_sha256': ('c' if role == 'gdscript_reference' else 'e') * 64,
                       'initial_screened_checkpoint_sha256': '9' * 64,
                       'checkpoints': points, 'activation_samples': [
                           {'tick': tick, 'value': {'radio_connected': False, 'engine_audio_playing': True}}
                           for tick in range(0, 12001, 240)]},
            'frame': {'capture_id': capture, 'pid': 1 if role == 'gdscript_reference' else 2,
                      'frames': 7200, 'actual_sample_s': 120, 'actual_warmup_s': 30,
                      'measured_simulation': {'start_tick': 0, 'end_tick': 12000}},
            'checked': {'capture_id': capture, 'complete': True, 'ok': True, 'reason': 'passed',
                        'process_exit': 0, 'started_utc': start, 'elapsed_seconds': 150}}


class PairControls(unittest.TestCase):
    def setUp(self):
        self.reference = sample('gdscript_reference', 'reference', '2026-11-15T01:00:00+00:00')
        self.native = sample('native', 'native', '2026-11-15T01:03:00+00:00')

    def compare(self):
        return promotion.compare_pair(self.reference, self.native, set())

    def test_exact_windows_and_normalized_arguments_match(self):
        result = self.compare()
        self.assertEqual(result['first_role'], 'reference')
        self.assertEqual(len(result['windows']), 2)
        self.assertEqual(len(result['windows_sha256']), 64)
        self.assertNotEqual(self.reference['health']['initial_checkpoint_sha256'],
                            self.native['health']['initial_checkpoint_sha256'])
        self.assertNotEqual(self.reference['health']['scenario']['configuration'],
                            self.native['health']['scenario']['configuration'])

    def test_changed_screened_configuration_and_actual_identity_are_rejected(self):
        changed = copy.deepcopy(self.native)
        changed['health']['scenario']['screened_configuration_sha256'] = '0' * 64
        changed['summary']['scenario']['screened_configuration_sha256'] = '0' * 64
        with self.assertRaises(promotion.AdmissionError):
            promotion.compare_pair(self.reference, changed, set())

    def test_screened_start_must_match_the_qualified_fleet_row(self):
        actual = promotion.screened_selection(self.reference['health']['scenario'])
        promotion.verify_campaign_selection([self.reference, self.native], actual)
        wrong = dict(actual, start_sha256='b' * 64)
        with self.assertRaises(promotion.AdmissionError):
            promotion.verify_campaign_selection([self.reference, self.native], wrong)
        changed = copy.deepcopy(self.native)
        changed['health']['scenario']['screened_domain']['branches']['soft_hull'] = False
        with self.assertRaises(promotion.AdmissionError):
            promotion.verify_campaign_selection([self.reference, changed], actual)
        changed = copy.deepcopy(self.native)
        changed['health']['scenario']['configuration'] = 'not a hash'
        changed['summary']['scenario']['configuration'] = 'not a hash'
        with self.assertRaises(promotion.AdmissionError):
            promotion.compare_pair(self.reference, changed, set())

    def test_flight_evidence_binds_all_revalidated_attachments(self):
        fields = ('frame_report_sha256', 'frame_stream_sha256', 'health_sha256', 'checked_sha256', 'resource_sha256')
        for index, field in enumerate(fields): self.reference['summary'][field] = str(index) * 64
        first = promotion.flight_evidence(self.reference)
        self.assertEqual(first['capture_id'], 'reference')
        for field in fields:
            changed = copy.deepcopy(self.reference)
            changed['summary'][field] = 'a' * 64
            self.assertNotEqual(promotion.canonical_sha(first), promotion.canonical_sha(promotion.flight_evidence(changed)))
            changed['summary'].pop(field)
            with self.assertRaises(promotion.AdmissionError): promotion.flight_evidence(changed)

    def test_changed_or_missing_measured_window_refused(self):
        for mutation in (lambda n: n['health']['checkpoints'][1].update(sha256='d' * 64),
                         lambda n: n['health']['checkpoints'].pop(),
                         lambda n: n['frame']['measured_simulation'].update(start_tick=12000)):
            with self.subTest(mutation=mutation):
                changed = copy.deepcopy(self.native)
                mutation(changed)
                with self.assertRaises(promotion.AdmissionError):
                    promotion.compare_pair(self.reference, changed, set())

    def test_partial_or_warmup_only_windows_do_not_count(self):
        self.native['frame']['measured_simulation'] = {'start_tick': 12000, 'end_tick': 13000}
        with self.assertRaises(promotion.AdmissionError): self.compare()

    def test_scope_initial_state_and_experimental_graphics_mutations_refused(self):
        for mutation in (lambda n: n['health'].update(initial_checkpoint_sha256='malformed'),
                         lambda n: n['health'].update(initial_screened_checkpoint_sha256='e' * 64),
                         lambda n: n['health'].pop('initial_screened_checkpoint_sha256'),
                         lambda n: n['health']['scenario'].update(screened_configuration_sha256='0' * 64),
                         lambda n: n['health']['scenario'].update(aircraft_id='other'),
                         lambda n: n['health']['scenario']['arguments'].__setitem__(3, '--experimental-native-macos=false'),
                         lambda n: n['health']['render_scope'].update(driver='other'),
                         lambda n: n['summary']['drawable'].update(actual_1080p=False),
                         lambda n: n['summary']['pacing'].update({'pass': False}),
                         lambda n: n['summary']['resources']['host_state'].update(status='partial'),
                         lambda n: n['summary']['resources']['host_state']['thermal'].update(values=['serious']),
                         lambda n: n['summary']['resources']['host_state']['memory_pressure']['events'].append({'flags': 2}),
                         lambda n: n['health']['activation_samples'][2]['value'].update(engine_audio_playing=False),
                         lambda n: n['summary']['metrics']['frame_ms'].update(p95=18.0),
                         lambda n: n['summary']['resources']['process_memory']['rss_bytes'].update(sampled_peak=106),
                         lambda n: n['summary']['resources']['process_memory']['rss_bytes'].update(status='unknown'),
                         lambda n: n['summary']['resources']['cpu'].update(per_matched_simulated_second_estimate=1.06)):
            with self.subTest(mutation=mutation):
                changed = copy.deepcopy(self.native)
                mutation(changed)
                with self.assertRaises(promotion.AdmissionError):
                    promotion.compare_pair(self.reference, changed, set())

    def test_reused_ids_overlap_and_failed_checked_run_refused(self):
        for mutation in (lambda n: n['summary'].update(capture_id='reference'),
                         lambda n: n['checked'].update(started_utc='2026-11-15T01:01:00+00:00'),
                         lambda n: n['checked'].update(ok=False),
                         lambda n: n['checked'].update(started_utc='not-a-clock')):
            with self.subTest(mutation=mutation):
                changed = copy.deepcopy(self.native)
                mutation(changed)
                with self.assertRaises(promotion.AdmissionError):
                    promotion.compare_pair(self.reference, changed, set())

    def test_campaign_requires_durations_alternation_and_distinct_captures(self):
        from datetime import datetime, timedelta, timezone
        start = datetime(2026, 11, 15, 1, tzinfo=timezone.utc)
        groups = [[], []]
        for index in range(8):
            early = start + timedelta(minutes=index * 8) if index < 5 else start + timedelta(minutes=40, seconds=(index - 5) * 3700)
            late = early + timedelta(seconds=180 if index < 5 else 1850)
            rtime, ntime = (early, late) if index % 2 == 0 else (late, early)
            ref = sample('gdscript_reference', 'r' + str(index), rtime.isoformat())
            nat = sample('native', 'n' + str(index), ntime.isoformat())
            nat['summary']['resources']['cpu']['per_matched_simulated_second_estimate'] = 0.9
            ref['frame']['pid'], nat['frame']['pid'] = index * 2 + 1, index * 2 + 2
            if index >= 5:
                for item in (ref, nat):
                    item['summary']['duration']['minimum_sample_s'] = 1800
                    item['frame']['actual_sample_s'] = 1800
                    item['checked']['elapsed_seconds'] = 1830
                    item['summary']['edge_windows'] = {'status': 'available',
                                                       'early': copy.deepcopy(item['summary']['resources']),
                                                       'final': copy.deepcopy(item['summary']['resources'])}
            for item, ch in ((ref, 'e'), (nat, 'f')):
                item['summary']['frame_report_sha256'] = ch * 64
            groups[0 if index < 5 else 1].append((ref, nat))
        result = promotion.compare_campaign(*groups)
        self.assertEqual((len(result['short_pairs']), len(result['long_pairs'])), (5, 3))
        self.assertEqual(result['benefit']['short_pairs']['passing_metrics'],
                         ['whole_process_cpu_per_accepted_simulated_second'])
        unchanged = copy.deepcopy(groups)
        for _, candidate in unchanged[0]:
            candidate['summary']['resources']['cpu']['per_matched_simulated_second_estimate'] = 1.0
        with self.assertRaises(promotion.AdmissionError): promotion.compare_campaign(*unchanged)
        frame_gain = copy.deepcopy(groups)
        for group in frame_gain:
            for reference, candidate in group:
                candidate['summary']['resources']['cpu']['per_matched_simulated_second_estimate'] = 1.0
                candidate['frame']['frames'] = int(reference['frame']['frames'] * 1.06)
        result = promotion.compare_campaign(*frame_gain)
        self.assertEqual(result['benefit']['short_pairs']['passing_metrics'], ['callback_loop_fps'])
        self.assertEqual(result['benefit']['long_pairs']['passing_metrics'], ['callback_loop_fps'])
        changed = copy.deepcopy(groups)
        changed[1][0][0]['frame']['actual_sample_s'] = 120
        with self.assertRaises(promotion.AdmissionError): promotion.compare_campaign(*changed)
        changed = copy.deepcopy(groups)
        changed[1][0][1]['summary']['edge_windows']['final']['process_memory']['rss_bytes']['sampled_peak'] = 106
        with self.assertRaises(promotion.AdmissionError): promotion.compare_campaign(*changed)
        changed = copy.deepcopy(groups)
        changed[1][0][0]['health']['scenario']['weather'] = {'preset': 'wind'}
        changed[1][0][0]['summary']['scenario']['weather'] = {'preset': 'wind'}
        changed[1][0][1]['health']['scenario']['weather'] = {'preset': 'wind'}
        changed[1][0][1]['summary']['scenario']['weather'] = {'preset': 'wind'}
        with self.assertRaises(promotion.AdmissionError): promotion.compare_campaign(*changed)
        changed = copy.deepcopy(groups)
        changed[0][1][0]['checked']['started_utc'] = (start + timedelta(minutes=8)).isoformat()
        changed[0][1][1]['checked']['started_utc'] = (start + timedelta(minutes=11)).isoformat()
        with self.assertRaises(promotion.AdmissionError): promotion.compare_campaign(*changed)


class CIControls(unittest.TestCase):
    def test_actual_named_jobs_and_stable_exact_commit_are_required(self):
        run = {'id': 10, 'run_attempt': 1, 'head_sha': 'a' * 40, 'status': 'completed',
               'conclusion': 'success', 'path': '.github/workflows/ci.yml', 'event': 'push',
               'repository': {'full_name': promotion.REPOSITORY}}
        jobs = [{'name': name, 'id': index + 1, 'run_id': 10, 'status': 'completed', 'conclusion': 'success'}
                for index, name in enumerate(promotion.CI_GATES)]
        result = promotion.verify_ci_records(run, jobs, copy.deepcopy(run), 'a' * 40, 10)
        self.assertEqual(result['macos_job_id'], '2')
        self.assertEqual(jobs[1]['name'], 'NK-3 native kernel qualification (macOS ARM64) / Experimental fixed-wing source correctness')
        with self.assertRaises(promotion.AdmissionError):
            promotion.verify_ci_records(run, [jobs[0], dict(jobs[1], name='NK-3 native kernel qualification (macOS ARM64)')], run, 'a' * 40, 10)
        for bad in ([jobs[0]], [jobs[0], dict(jobs[1], conclusion='skipped')], jobs + [jobs[0]],
                    [jobs[0], dict(jobs[1], run_id=11)]):
            with self.subTest(jobs=bad), self.assertRaises(promotion.AdmissionError):
                promotion.verify_ci_records(run, bad, run, 'a' * 40, 10)
        for changed in (dict(run, head_sha='b' * 40), dict(run, run_attempt=2), dict(run, conclusion='failure'),
                        dict(run, repository='invalid')):
            with self.subTest(run=changed), self.assertRaises(promotion.AdmissionError):
                promotion.verify_ci_records(run, jobs, changed, 'a' * 40, 10)


class PackageCheckControls(unittest.TestCase):
    def test_host_witness_matches_actual_capture_and_brackets_checked_process(self):
        host = {'model': 'MacBookAir10,1', 'cpu_brand': 'Apple M1', 'memory_bytes': 8589934592,
                'boot_session_uuid': '01234567-89ab-cdef-0123-456789abcdef',
                'os_product_version': '27.0.1', 'os_build_version': '26A434'}
        before = {'utc_start': '2026-11-15T00:59:58+00:00', 'utc_end': '2026-11-15T00:59:59+00:00',
                  'monotonic_start_ns': 1, 'monotonic_end_ns': 2, 'host': host}
        middle = {'utc_start': '2026-11-15T00:59:59+00:00', 'utc_end': '2026-11-15T01:02:31+00:00',
                  'monotonic_start_ns': 3, 'monotonic_end_ns': 4, 'capture_id': 'capture', 'pid': 9,
                  'report_sha256': 'a' * 64, 'log_sha256': 'b' * 64}
        after = {'utc_start': '2026-11-15T01:02:32+00:00', 'utc_end': '2026-11-15T01:02:33+00:00',
                 'monotonic_start_ns': 5, 'monotonic_end_ns': 6, 'host': copy.deepcopy(host)}
        witness = {'format': 'openrc-package-flight-host-witness v1', 'before': before, 'checked': middle, 'after': after}
        frame = {'capture_id': 'capture', 'pid': 9}
        checked = {'capture_id': 'capture', 'started_utc': '2026-11-15T01:00:00+00:00',
                   'elapsed_seconds': 150.0, 'log_sha256': 'b' * 64}
        expected = {key: value for key, value in host.items() if key != 'boot_session_uuid'}
        result = promotion.verify_host_witness(witness, frame, checked, 'a' * 64, expected)
        self.assertEqual(result['boot_session_uuid'], host['boot_session_uuid'])
        campaign = [dict(result, capture_id=str(index), pid=index + 1) for index in range(16)]
        promotion.verify_campaign_hosts(campaign)
        campaign[-1]['boot_session_uuid'] = 'fedcba98-7654-3210-fedc-ba9876543210'
        with self.assertRaises(promotion.AdmissionError): promotion.verify_campaign_hosts(campaign)
        for bad_boot in ('00000000-0000-0000-0000-000000000000', '01234567-89AB-CDEF-0123-456789ABCDEF'):
            changed = copy.deepcopy(witness)
            changed['before']['host']['boot_session_uuid'] = bad_boot
            changed['after']['host']['boot_session_uuid'] = bad_boot
            with self.assertRaises(promotion.AdmissionError):
                promotion.verify_host_witness(changed, frame, checked, 'a' * 64, expected)
        for mutation in (lambda x: x['checked'].update(pid=10),
                         lambda x: x['checked'].update(report_sha256='c' * 64),
                         lambda x: x['after']['host'].update(memory_bytes=1),
                         lambda x: x['checked'].update(monotonic_end_ns=2),
                         lambda x: x['checked'].update(utc_end='2026-11-15T01:01:00+00:00')):
            changed = copy.deepcopy(witness)
            mutation(changed)
            with self.subTest(mutation=mutation), self.assertRaises(promotion.AdmissionError):
                promotion.verify_host_witness(changed, frame, checked, 'a' * 64, expected)

    def test_checked_stage_requires_actual_matching_command_markers_and_clean_log(self):
        command = ['/exact/OpenRC', '--headless', '--', '--native-qualification=stage']
        markers = ['NATIVE_QUALIFICATION preloaded=false', 'NK3_NATIVE_STAGE_NATIVE verdict=pass',
                   'NATIVE_QUALIFICATION mode=stage verdict=pass']
        log = ('\n'.join(markers) + '\n').encode()
        report = {'format': 'openrc-godot-check v1', 'complete': True, 'ok': True, 'reason': 'passed',
                  'process_exit': 0, 'command': command, 'log_sha256': hashlib.sha256(log).hexdigest(),
                  'counts': {'error': 0, 'warning': 0}}
        promotion.verify_checked_case(report, log, command, markers)
        for change in (dict(report, command=['/other/OpenRC']), dict(report, process_exit=1),
                       dict(report, counts={'error': 0, 'warning': 1}), dict(report, log_sha256='0' * 64)):
            with self.subTest(change=change), self.assertRaises(promotion.AdmissionError):
                promotion.verify_checked_case(change, log, command, markers)
        missing = ('\n'.join(markers[:2]) + '\n').encode()
        with self.assertRaises(promotion.AdmissionError):
            promotion.verify_checked_case(dict(report, log_sha256=hashlib.sha256(missing).hexdigest()), missing, command, markers)

    def test_package_identity_binds_library_and_reference_receipt(self):
        ref = {'kind': 'macos-reference-bundle-v1', 'sha256': '1' * 64, 'receipt_sha256': '2' * 64,
               'executable_sha256': '3' * 64, 'pack_sha256': '4' * 64}
        nat = {'kind': 'macos-arm64-native-bundle-v1', 'sha256': '5' * 64, 'receipt_sha256': '6' * 64,
               'reference_receipt_sha256': '2' * 64, 'manifest_sha256': '7' * 64,
               'descriptor_sha256': '8' * 64, 'library_sha256': '9' * 64}
        row = {'binary_sha256': '9' * 64, 'source_sha256': 'a' * 64, 'lock_sha256': 'b' * 64,
               'engine_sha256': 'c' * 64, 'mirrored_sources': {'app/sim/native_macos_domain.gd': 'd' * 64}}
        identity = promotion._package_identity(ref, nat, row)
        self.assertEqual(identity['domain_sha256'], 'd' * 64)
        for replacement in (dict(nat, library_sha256='0' * 64), dict(nat, reference_receipt_sha256='0' * 64)):
            with self.subTest(native=replacement), self.assertRaises(promotion.AdmissionError):
                promotion._package_identity(ref, replacement, row)

    def test_publication_is_exclusive_and_never_overwrites_existing_marker(self):
        probe_spec = importlib.util.spec_from_file_location('package_home_probe_test', HERE / 'macos_package_default_probe.py')
        probe = importlib.util.module_from_spec(probe_spec)
        probe_spec.loader.exec_module(probe)
        with tempfile.TemporaryDirectory(prefix='publish-control-', dir=HERE) as directory:
            root = Path(directory).resolve()
            self.assertTrue(root.is_relative_to(HERE.resolve()))
            target = root / 'OpenRC.app.openrc-native-default'
            promotion._atomic_publish(target, b'candidate-marker', probe)
            self.assertEqual(target.read_bytes(), b'candidate-marker')
            with self.assertRaises(promotion.AdmissionError):
                promotion._atomic_publish(target, b'different-marker', probe)
            self.assertEqual(target.read_bytes(), b'candidate-marker')

    def test_receipt_failure_cannot_publish_the_canonical_marker(self):
        probe_spec = importlib.util.spec_from_file_location('package_home_probe_receipt_test', HERE / 'macos_package_default_probe.py')
        probe = importlib.util.module_from_spec(probe_spec)
        probe_spec.loader.exec_module(probe)
        with tempfile.TemporaryDirectory(prefix='receipt-control-', dir=HERE) as directory:
            root = Path(directory).resolve()
            self.assertTrue(root.is_relative_to(HERE.resolve()))
            target, receipt = root / 'OpenRC.app.openrc-native-default', root / 'proof.json'
            result = {'status': 'verified_for_publication', 'candidate_sha256': 'a' * 64}
            with patch.object(probe, 'write_new', side_effect=OSError('injected write failure')):
                with self.assertRaises(OSError):
                    promotion.publish_with_receipt(target, b'marker', receipt, result, probe)
            self.assertFalse(target.exists())
            self.assertFalse(receipt.exists())
            promotion.publish_with_receipt(target, b'marker', receipt, result, probe)
            self.assertEqual(target.read_bytes(), b'marker')
            self.assertIn(b'verified_for_publication', receipt.read_bytes())


if __name__ == '__main__':
    unittest.main(verbosity=2)
