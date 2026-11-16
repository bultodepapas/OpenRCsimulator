"""Offline controls for the anonymous CI transport; no network is contacted."""
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


promotion = load('package_promotion_transport', HERE / 'macos_package_promotion.py')
watch = load('actual_release_watch', ROOT / 'tools/release/watch.py')
RUN = f'repos/{promotion.REPOSITORY}/actions/runs/91'
JOBS = RUN + '/jobs?per_page=100&filter=latest&page='


def envelope(status, body, headers=None):
    value = {'status': status, 'headers': headers or {},
             'body_base64': base64.b64encode(body).decode('ascii')}
    return subprocess.CompletedProcess([], 0, stdout=json.dumps(value).encode(), stderr=b'')


def run_record():
    return {'id': 91, 'run_attempt': 1, 'head_sha': 'a' * 40,
            'status': 'completed', 'conclusion': 'success', 'path': '.github/workflows/ci.yml',
            'event': 'push', 'repository': {'full_name': promotion.REPOSITORY}}


def job(number, name):
    return {'id': number, 'run_id': 91, 'name': name, 'status': 'completed',
            'conclusion': 'success', 'steps': []}


class PublicCiTransportControls(unittest.TestCase):
    def test_real_http_adapter_is_get_only_and_does_not_follow_redirects(self):
        calls = []
        class Response:
            status = 302
            def getheaders(self): return [('Location', 'https://other.invalid/')]
            def read(self, size):
                calls.append(('read', size))
                return b'{"message":"moved"}'
        class Connection:
            def request(self, method, path, headers): calls.append(('request', method, path, headers))
            def getresponse(self): return Response()
            def close(self): calls.append(('closed',))
        with patch.object(promotion.http.client, 'HTTPSConnection', return_value=Connection()) as connect:
            response = promotion._fetch_public_ci_http(RUN, 4.0)
        connect.assert_called_once_with('api.github.com', timeout=4.0)
        request = calls[0]
        self.assertEqual(request[:3], ('request', 'GET', '/' + RUN))
        self.assertEqual(request[3]['Accept'], 'application/vnd.github+json')
        self.assertIn('User-Agent', request[3])
        self.assertNotIn('Authorization', request[3])
        self.assertEqual(calls[-1], ('closed',))
        self.assertEqual(response['status'], 302)
        with patch.object(promotion.subprocess, 'run', return_value=envelope(302, b'{}')) as process:
            with self.assertRaises(watch.InvalidData): promotion._public_ci_json(watch, RUN, 4.0)
        command = process.call_args.args[0]
        self.assertEqual(command[1:3], ['-I', '-B'])
        self.assertEqual(command[-3:], [promotion.PUBLIC_CI_CHILD, RUN, '4.0'])
        self.assertNotIn('gh', command)

    def test_only_fixed_run_and_bounded_paginated_jobs_are_accepted(self):
        for endpoint in (RUN, JOBS + '1', JOBS + '51'):
            promotion._public_ci_endpoint(endpoint)
        for endpoint in (RUN + '/cancel', JOBS + '0', JOBS + '52', JOBS + '1&extra=true',
                         'https://evil.invalid/' + RUN, RUN.replace(promotion.REPOSITORY, 'other/repository')):
            with self.subTest(endpoint=endpoint), self.assertRaises(promotion.AdmissionError):
                promotion._public_ci_endpoint(endpoint)

    def test_http_error_timeout_and_malformed_data_fail_without_exposing_body(self):
        for status, headers, body in ((403, {'x-ratelimit-remaining': '0'}, b'{"message":"secret"}'),
                                      (429, {'retry-after': '10'}, b'{"message":"private"}'),
                                      (503, {}, b'not json')):
            with self.subTest(status=status), patch.object(promotion.subprocess, 'run',
                                                           return_value=envelope(status, body, headers)):
                with self.assertRaises(watch.TransportError) as error:
                    promotion._public_ci_json(watch, RUN, 3.0)
                self.assertNotIn('secret', str(error.exception))
                self.assertNotIn('private', str(error.exception))
        with patch.object(promotion.subprocess, 'run', side_effect=subprocess.TimeoutExpired('child', 3)):
            with self.assertRaises(watch.TransportError): promotion._public_ci_json(watch, RUN, 3.0)
        with patch.object(promotion.subprocess, 'run', return_value=envelope(200, b'{bad json')):
            with self.assertRaises(watch.InvalidData): promotion._public_ci_json(watch, RUN, 3.0)
        malformed = subprocess.CompletedProcess([], 0, stdout=b'{"status":200}', stderr=b'')
        with patch.object(promotion.subprocess, 'run', return_value=malformed):
            with self.assertRaises(watch.InvalidData): promotion._public_ci_json(watch, RUN, 3.0)
        failed = subprocess.CompletedProcess([], 1, stdout=b'', stderr=b'private subprocess detail')
        with patch.object(promotion.subprocess, 'run', return_value=failed):
            with self.assertRaises(watch.TransportError) as error:
                promotion._public_ci_json(watch, RUN, 3.0)
            self.assertNotIn('private', str(error.exception))
        cert = subprocess.CompletedProcess([], 1, stdout=b'',
                    stderr=b'public CI HTTPS certificate verification failed\n')
        with patch.object(promotion.subprocess, 'run', return_value=cert):
            with self.assertRaisesRegex(watch.TransportError, 'certificate verification failed'):
                promotion._public_ci_json(watch, RUN, 3.0)
        with patch.object(promotion.subprocess, 'run', return_value=envelope(200, b'{"ok":true}')) as process:
            self.assertEqual(promotion._public_ci_json(watch, RUN, 3.0), {'ok': True})
            self.assertEqual(process.call_args.kwargs['timeout'], 3.0)

    def test_oversized_body_is_refused_and_connection_closed(self):
        calls = []
        class Response:
            status = 200
            def getheaders(self): return []
            def read(self, size): return b'x' * size
        class Connection:
            def request(self, *_args, **_kwargs): pass
            def getresponse(self): return Response()
            def close(self): calls.append('closed')
        with patch.object(promotion.http.client, 'HTTPSConnection', return_value=Connection()):
            with self.assertRaises(promotion.AdmissionError): promotion._fetch_public_ci_http(RUN, 1.0)
        self.assertEqual(calls, ['closed'])

    def test_existing_snapshot_checks_both_run_reads_and_paginated_jobs(self):
        first_page = [job(i, f'other-{i}') for i in range(1, 100)] + [job(100, promotion.CI_GATES[0])]
        second_page = [job(101, promotion.CI_GATES[1])]
        results = {RUN: run_record(), JOBS + '1': {'total_count': 101, 'jobs': first_page},
                   JOBS + '2': {'total_count': 101, 'jobs': second_page}}
        calls = []
        def api(_watch, endpoint, timeout):
            calls.append(endpoint)
            self.assertGreater(timeout, 0)
            return results[endpoint]
        with patch.object(promotion, '_public_ci_json', side_effect=api), \
             patch.object(watch, 'gh_json', side_effect=AssertionError('authenticated gh must not run')):
            proof = promotion._ci_snapshot(watch, 'a' * 40, 91)
        self.assertEqual(calls, [RUN, JOBS + '1', JOBS + '2', RUN])
        self.assertEqual((proof['run_id'], proof['required_job_id'], proof['macos_job_id']), ('91', '100', '101'))
        results[JOBS + '2']['total_count'] = 102
        with patch.object(promotion, '_public_ci_json', side_effect=api):
            with self.assertRaisesRegex(promotion.AdmissionError, 'live CI evidence'):
                promotion._ci_snapshot(watch, 'a' * 40, 91)
        results[JOBS + '2']['total_count'] = 101
        results[RUN] = dict(run_record(), head_sha='b' * 40)
        with patch.object(promotion, '_public_ci_json', side_effect=api):
            with self.assertRaisesRegex(promotion.AdmissionError, 'CI run identity'):
                promotion._ci_snapshot(watch, 'a' * 40, 91)

        results[RUN] = run_record()
        snapshots = iter([run_record(), dict(run_record(), run_attempt=2)])
        def changing(_watch, endpoint, _timeout):
            return next(snapshots) if endpoint == RUN else results[endpoint]
        with patch.object(promotion, '_public_ci_json', side_effect=changing):
            with self.assertRaisesRegex(promotion.AdmissionError, 'CI run identity'):
                promotion._ci_snapshot(watch, 'a' * 40, 91)

    def test_internal_child_rejects_invalid_endpoint_without_network(self):
        result = subprocess.run([promotion.sys.executable, '-I', '-B', str(HERE / 'macos_package_promotion.py'),
                                 promotion.PUBLIC_CI_CHILD, 'https://other.invalid', '2'],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b'')
        self.assertIn(b'public CI HTTPS request failed', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
