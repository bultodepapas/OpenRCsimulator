#!/usr/bin/env python3
"""Owned synthetic fixtures for the read-only bulk ZIP census."""
import hashlib
import io
import os
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import zlib

import scan_bulk_zip as census


def raw_string(value):
    return struct.pack('<H', len(value)) + value


def own_pkg(label=b'1.000000', content=b'modelTypes.Example = {}'):
    leaf = b'\x00' + raw_string(b'Fixture.mod') + raw_string(b'<owned-source>')
    leaf += struct.pack('<I', len(content)) + content + b'\x00\x00'
    body = b'\x01\x00\x01\x00' + struct.pack('<H', 1) + leaf
    packed = zlib.compress(body)
    return b'\x00' + raw_string(label) + struct.pack('<HII', 1, len(packed), len(body)) + packed


def owned_zip(entries, compression=zipfile.ZIP_DEFLATED):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as writer:
        for name, data in entries:
            writer.writestr(name, data, compress_type=compression)
    return buffer.getvalue()


def scan_bytes(raw, **kwargs):
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / 'pack.zip'
        source.write_bytes(raw)
        return census.scan_path(source, hashlib.sha256(raw).hexdigest(), **kwargs)


class BulkScannerTests(unittest.TestCase):
    def test_valid_and_unrelated_formats(self):
        raw = owned_zip([('b.phx', b'old'), ('b.pkg', own_pkg()),
                         ('a.pkg', own_pkg()), ('zip/in.zip', b'opaque'),
                         ('mods/a.mod', b'ignored'), ('other.bin', b'other')])
        report = scan_bytes(raw)
        self.assertEqual(report['pkg_occurrences'], 2)
        self.assertEqual(report['selected_count'], 2)
        self.assertEqual([x['zip_name'] for x in report['results']], ['a.pkg', 'b.pkg'])
        self.assertTrue(all(x['status'] == 'parsed' for x in report['results']))
        self.assertEqual(report['results'][0]['summary']['member_kinds'], {'.mod': 1})
        self.assertEqual(report['candidate_occurrences']['.phx'], 1)
        self.assertEqual(report['candidate_occurrences']['.zip'], 1)

    def test_windows_and_unicode_aliases_skipped(self):
        pkg = own_pkg()
        raw = owned_zip([('a.pkg', pkg), ('A.PKG', pkg), ('../escape.pkg', pkg),
                         ('sub\\evil.pkg', pkg), ('ok.pkg', pkg)])
        report = scan_bytes(raw)
        self.assertEqual(report['colliding_name_groups'], 1)
        result = {x['zip_name']: x for x in report['results']}
        self.assertEqual(result['ok.pkg']['status'], 'parsed')
        self.assertEqual(result['a.pkg']['status'], 'skipped')
        self.assertEqual(result['A.PKG']['status'], 'skipped')
        self.assertEqual(result['../escape.pkg']['status'], 'skipped')
        self.assertEqual(result['sub\\evil.pkg']['status'], 'skipped')

    def test_revisions_dont_merge_and_window_is_stable(self):
        a, b = own_pkg(content=b'a'), own_pkg(content=b'b')
        report = scan_bytes(owned_zip([('z.pkg', b), ('a.pkg', a)]), start=1, limit=1)
        self.assertEqual(report['selected_count'], 1)
        self.assertEqual(report['results'][0]['zip_name'], 'z.pkg')
        self.assertTrue(report['selected_window_complete'])
        self.assertNotEqual(hashlib.sha256(a).hexdigest(), hashlib.sha256(b).hexdigest())

    def test_bad_pkg_is_not_bad_zip(self):
        report = scan_bytes(owned_zip([('malformed.pkg', b'not-a-pkg')]))
        self.assertEqual(report['results'][0]['status'], 'unsupported_pkg_profile')
        self.assertTrue(report['results'][0]['pkg_sha256'])

    def test_oversize_declared_payload_skipped_before_read(self):
        raw = owned_zip([('big.pkg', own_pkg())])
        report = scan_bytes(raw, member_limit=12)
        self.assertEqual(report['results'][0]['status'], 'skipped')
        self.assertIn('capture size', report['results'][0]['reason'])

    def test_duplicate_exact_name_skipped(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            raw = owned_zip([('same.pkg', own_pkg()), ('same.pkg', own_pkg())])
        report = scan_bytes(raw)
        self.assertEqual(report['colliding_name_groups'], 1)
        self.assertEqual([x['status'] for x in report['results']], ['skipped', 'skipped'])

    def test_crc_damage_is_not_accepted(self):
        raw = bytearray(owned_zip([('bad.pkg', own_pkg())], zipfile.ZIP_STORED))
        needle = own_pkg()
        at = bytes(raw).find(needle)
        self.assertGreaterEqual(at, 0)
        raw[at + 5] ^= 0x01
        report = scan_bytes(bytes(raw))
        self.assertEqual(report['results'][0]['status'], 'damaged_zip_member')

    def test_exact_sha_required(self):
        raw = owned_zip([('okay.pkg', own_pkg())])
        with tempfile.TemporaryDirectory() as d:
            file = Path(d) / 'pack.zip'
            file.write_bytes(raw)
            with self.assertRaisesRegex(census.CorpusError, 'mismatch'):
                census.scan_path(file, '0' * 64)

    def test_refuses_output_collision(self):
        raw = owned_zip([('okay.pkg', own_pkg())])
        with tempfile.TemporaryDirectory() as d:
            file = Path(d) / 'pack.zip'
            file.write_bytes(raw)
            status = census.main([str(file), '--sha256', hashlib.sha256(raw).hexdigest(),
                                  '--report', str(file)])
            self.assertEqual(status, 1)
            self.assertEqual(file.read_bytes(), raw)

    def test_central_directory_preflight_fails_before_zipfile(self):
        raw = bytearray(owned_zip([('okay.pkg', own_pkg())]))
        # EOCD entry count field is 16-bit. Change only total entries.
        at = raw.rfind(b'PK\x05\x06')
        self.assertGreaterEqual(at, 0)
        struct.pack_into('<H', raw, at + 10, 9000)
        with self.assertRaises(census.CorpusError):
            scan_bytes(bytes(raw))

    def test_aggregate_declared_budget(self):
        from unittest.mock import patch
        raw = owned_zip([('okay.pkg', own_pkg())])
        with patch.object(census, 'MAX_DECLARED_BYTES', 1):
            with self.assertRaisesRegex(census.CorpusError, 'aggregate declared'):
                scan_bytes(raw)

    def test_per_scan_work_budget_preserves_partial_diagnostics(self):
        from unittest.mock import patch
        pkg = own_pkg()
        raw = owned_zip([('a.pkg', pkg), ('b.pkg', pkg)])
        with patch.object(census, 'MAX_RUN_CAPTURE_BYTES', len(pkg)):
            report = scan_bytes(raw)
        self.assertEqual([x['status'] for x in report['results']], ['parsed', 'skipped'])
        self.assertIn('aggregate', report['results'][1]['reason'])
        self.assertEqual(report['selected_declared_capture_bytes'], len(pkg))

    def test_source_symlink_rejected(self):
        if not hasattr(os, 'O_NOFOLLOW'):
            self.skipTest('O_NOFOLLOW unavailable')
        raw = owned_zip([('okay.pkg', own_pkg())])
        with tempfile.TemporaryDirectory() as d:
            file = Path(d) / 'pack.zip'
            file.write_bytes(raw)
            link = Path(d) / 'alias.zip'
            link.symlink_to(file)
            with self.assertRaises(OSError):
                census.scan_path(link, hashlib.sha256(raw).hexdigest())

    def test_report_budget(self):
        with self.assertRaisesRegex(census.CorpusError, 'report size'):
            census.serialize({'large': 'x' * (census.MAX_REPORT_BYTES + 1)})

    def test_limit_validation(self):
        raw = owned_zip([('okay.pkg', own_pkg())])
        for kwargs in ({'limit': 0}, {'start': -1}, {'member_limit': 0},
                       {'limit': census.MAX_SELECTED + 1}):
            with self.subTest(kwargs=kwargs), self.assertRaises(census.CorpusError):
                scan_bytes(raw, **kwargs)

    def test_dir_mode_and_path_checks(self):
        self.assertTrue(census.safe_name('A/B.PKG'))
        for n in ('/abs.pkg', 'C:/foo.pkg', 'a/./b.pkg', 'a//b.pkg', 'a/../b.pkg',
                  'a/space .pkg ', 'a\\foo.pkg', 'a\x00.pkg'):
            with self.subTest(n=n):
                self.assertFalse(census.safe_name(n))


if __name__ == '__main__':
    unittest.main(verbosity=2)
