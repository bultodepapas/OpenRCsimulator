"""The repeat-bake gate includes the source-material mask, not just color frames."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from verify_bakes import verify


class RepeatBakeTests(unittest.TestCase):
    def test_mask_drift_and_missing_frames_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folders = [Path(directory) / name for name in ('A', 'B')]
            for folder in folders:
                (folder / 'raw').mkdir(parents=True)
                (folder / 'atlas').mkdir()
                (folder / 'atlas/atlas.png').write_bytes(b'atlas')
                for name in ('CommonTree_1', 'CommonTree_3', 'Pine_1'):
                    for variant in ('source_lit', 'source_albedo', 'adapted_lit',
                                    'adapted_albedo', 'adapted_foliage_mask'):
                        (folder / 'raw' / f'{name}-{variant}.png').write_bytes(b'frame')
                manifest = {
                    'inputs_sha256': {'<source-recipe>': 'same-recipe'},
                    'outputs_sha256': {'atlas/atlas.png': hashlib.sha256(b'atlas').hexdigest()},
                    'godot': 'fixture', 'bake': {'adapter': 'fixture', 'species': [
                        {'id': name} for name in ('CommonTree_1', 'CommonTree_3', 'Pine_1')]},
                }
                (folder / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
            self.assertEqual(verify(*folders)['raw_png_count'], 15)
            mask = folders[1] / 'raw/CommonTree_3-adapted_foliage_mask.png'
            mask.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'Raw frame differs'):
                verify(*folders)
            mask.unlink()
            with self.assertRaisesRegex(ValueError, 'fifteen'):
                verify(*folders)


if __name__ == '__main__':
    unittest.main()
