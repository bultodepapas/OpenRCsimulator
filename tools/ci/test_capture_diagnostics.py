from pathlib import Path
import tempfile
import unittest
import json

from capture_diagnostics import prepare


class CaptureDiagnosticsTests(unittest.TestCase):
    def test_review_bundle_preserves_ui_sidecars_and_logs_without_project_copies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            captures, out = root / 'captures', root / 'diagnostics'
            files = {'ui-home-en.png': b'ui image', 'ui-home-en.json': b'{}',
                     'vq01b/ui-home-es.png': b'quality ui image', 'vq01b/ui-home-es.json': b'{}',
                     'lighting-pixels/run/engine.log': b'failure details',
                     'lighting-pixels/segment-metrics.json': b'{"metrics":{}}',
                     'l9c/stripes/raw-app/geometry.json': b'excluded',
                     'scenario/history/old/report.json': b'excluded',
                     '.capture-profile/settings.json': b'excluded', 'other.png': b'large image'}
            for name, data in files.items():
                path = captures / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            report = prepare(captures, out)
            expected = set(files) - {'l9c/stripes/raw-app/geometry.json', 'scenario/history/old/report.json',
                                     '.capture-profile/settings.json', 'other.png'}
            self.assertEqual({row['path'] for row in report['files']}, expected)
            self.assertFalse(report['qualification'])
            for name, data in files.items():
                self.assertEqual((captures / name).read_bytes(), data)
                if name in expected:
                    self.assertEqual((out / name).read_bytes(), data)
            with self.assertRaises(FileExistsError):
                prepare(captures, out)
            with self.assertRaises(ValueError):
                prepare(captures, captures / 'nested')

    def test_bundle_is_bounded_and_reports_omissions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            captures = root / 'captures'
            captures.mkdir()
            for name, size in [('a.log', 5), ('b.log', 5), ('c.json', 10)]:
                (captures / name).write_bytes(b'x' * size)
            report = prepare(captures, root / 'out', budget=8, per_file=6)
            self.assertEqual(report['payload_bytes'], 5)
            self.assertEqual([row['path'] for row in report['files']], ['a.log'])
            self.assertEqual({row['path'] for row in report['omitted']}, {'b.log', 'c.json'})
            self.assertTrue((root / 'out/diagnostics-index.json').is_file())

    def test_failed_checked_run_precedes_unrelated_bulk_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            captures = root / 'captures'
            failed = captures / 'z-last'
            failed.mkdir(parents=True)
            report = json.dumps({'format': 'openrc-godot-check v1', 'ok': False}).encode()
            (failed / 'report.json').write_bytes(report)
            (failed / 'engine.log').write_bytes(b'failure')
            (captures / 'a-first.json').write_bytes(b'x' * 60)
            result = prepare(captures, root / 'out', budget=100, per_file=80)
            self.assertEqual([row['path'] for row in result['files']], ['z-last/report.json', 'z-last/engine.log'])
            self.assertEqual(result['omitted'][0]['path'], 'a-first.json')


if __name__ == '__main__':
    unittest.main()
