"""Focused safety checks for installing the separate visual derivative."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import lab


def digest(data):
    return hashlib.sha256(data).hexdigest()


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.work = self.root / 'work'
        self.work.mkdir()
        self.stock = self.repo / 'app/assets/aircraft/skywalker-x8/skywalker_x8.glb'
        self.stock.parent.mkdir(parents=True)
        self.stock.write_bytes(b'legacy-stock')
        self.source = self.work / 'moonrunner-experiment.glb'
        self.source.write_bytes(b'verified-derivative')
        (self.work / 'export.complete').write_text('ok\n')
        (self.work / 'export-evidence.json').write_text(json.dumps({'derived_glb_sha256': digest(b'verified-derivative'), 'source_glb_sha256': digest(b'legacy-stock')}))
        self.target = self.repo / 'app/assets/aircraft/moonrunner-x99/moonrunner_x99.glb'
        self.patches = patch.multiple(lab, EXPECTED_GLB=digest(b'verified-derivative'), EXPECTED_STOCK=digest(b'legacy-stock'))
        self.patches.start()
        self.addCleanup(self.patches.stop)

    def test_install_creates_separate_output_and_preserves_stock(self):
        lab.install(self.repo, self.work)
        self.assertEqual(self.target.read_bytes(), b'verified-derivative')
        self.assertEqual(self.stock.read_bytes(), b'legacy-stock')

    def test_install_never_overwrites_existing_output(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b'existing')
        with self.assertRaisesRegex(RuntimeError, 'overwrite'):
            lab.install(self.repo, self.work)
        self.assertEqual(self.target.read_bytes(), b'existing')

    def test_install_failure_does_not_publish_partial_output(self):
        with patch.object(lab.os, 'link', side_effect=OSError('simulated failure')):
            with self.assertRaisesRegex(OSError, 'simulated failure'):
                lab.install(self.repo, self.work)
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.target.parent.iterdir()), [])
        self.assertEqual(self.stock.read_bytes(), b'legacy-stock')

    def test_install_requires_success_marker_and_matching_evidence(self):
        (self.work / 'export.complete').write_text('incomplete\n')
        with self.assertRaisesRegex(RuntimeError, 'Verified export'):
            lab.install(self.repo, self.work)
        (self.work / 'export.complete').write_text('ok\n')
        (self.work / 'export-evidence.json').write_text('{}')
        with self.assertRaisesRegex(RuntimeError, 'Verified export'):
            lab.install(self.repo, self.work)
        self.assertFalse(self.target.exists())

    def test_bolido_copy_preserves_original_and_rejects_unexpected_input(self):
        original = self.stock.parent / 'skywalker_x8_bolido.glb'
        target = self.target.parent / 'moonrunner_x99_bolido.glb'
        original.write_bytes(b'bolido-stock')
        with patch.object(lab, 'EXPECTED_BOLIDO', digest(b'bolido-stock')):
            lab.install_bolido(self.repo)
            self.assertEqual(target.read_bytes(), original.read_bytes())
            with self.assertRaisesRegex(RuntimeError, 'overwrite'):
                lab.install_bolido(self.repo)
            target.unlink()
            original.write_bytes(b'wrong-bolido')
            with self.assertRaisesRegex(RuntimeError, 'BOLIDO'):
                lab.install_bolido(self.repo)
        self.assertFalse(target.exists())
        self.assertEqual(original.read_bytes(), b'wrong-bolido')

    def test_install_rejects_modified_stock_and_unverified_output(self):
        self.stock.write_bytes(b'modified')
        with self.assertRaisesRegex(RuntimeError, 'original stock'):
            lab.install(self.repo, self.work)
        self.assertFalse(self.target.exists())
        self.stock.write_bytes(b'legacy-stock')
        self.source.write_bytes(b'unverified')
        with self.assertRaisesRegex(RuntimeError, 'Verified export'):
            lab.install(self.repo, self.work)
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
