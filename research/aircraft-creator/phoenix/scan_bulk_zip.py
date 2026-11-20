#!/usr/bin/env python3
"""Read-only, bounded Phoenix bulk ZIP research census (not a runtime importer).

Never extracts files, executes model definitions or follows their author-local paths.
Requires the existing inspect_pkg.py in the same directory for optional PKG probes.
Third-party aircraft stay outside the repository. Python 3 standard library only.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import stat
import sys
import unicodedata
import zipfile
import zlib

from inspect_pkg import inspect as inspect_pkg, FormatError as PackageError

MAX_ARCHIVE_BYTES = 2 * 1024 ** 3
MAX_ENTRIES = 10000
MAX_CENTRAL_DIRECTORY_BYTES = 8 * 1024 ** 2
MAX_RUN_CAPTURE_BYTES = 256 * 1024 ** 2
MAX_DECLARED_BYTES = 8 * 1024 ** 3
MAX_PATH_BYTES = 512
MAX_PKG_BYTES = 64 * 1024 ** 2
MAX_SELECTED = 128
MAX_REPORT_BYTES = 1024 ** 2
KNOWN = {'.pkg', '.phx', '.mod', '.geo', '.var', '.zip', '.rar'}
HEX256 = re.compile(r'[0-9a-f]{64}\Z')


class CorpusError(ValueError):
    pass


def hash_file(file):
    file.seek(0)
    digest = hashlib.sha256()
    while True:
        chunk = file.read(1024 ** 2)
        if not chunk:
            break
        digest.update(chunk)
    return digest.hexdigest()


def preflight_zip32(file, size):
    """Bound metadata before zipfile constructs untrusted entry objects.

    Strictly a developer research ZIP32 profile: no prefixes, split sets or ZIP64.
    """
    count = min(size, 22 + 65535)
    file.seek(size - count)
    tail = file.read(count)
    for at in range(len(tail) - 22, -1, -1):
        if tail[at:at + 4] != b'PK\x05\x06':
            continue
        disk, disk_start, on_disk, total, central_size, central_start, comment = struct.unpack_from(
            '<HHHHIIH', tail, at + 4)
        if at + 22 + comment != len(tail):
            continue
        if disk or disk_start or on_disk != total or total == 65535 or central_size == 0xFFFFFFFF or central_start == 0xFFFFFFFF:
            raise CorpusError('split or ZIP64 archive unsupported by the research profile')
        if total > MAX_ENTRIES or central_size > MAX_CENTRAL_DIRECTORY_BYTES:
            raise CorpusError('ZIP central directory count/byte limit exceeded')
        if central_start + central_size != size - len(tail) + at:
            raise CorpusError('unsupported ZIP prefix or inconsistent central directory')
        return total
    raise CorpusError('strict ZIP32 end record missing or inconsistent')


def safe_name(name):
    """Validate decoded ZIP names for *identity*. Never turn them into disk paths."""
    if not name or len(name.encode('utf-8')) > MAX_PATH_BYTES or name.startswith('/') or '\\' in name or ':' in name:
        return False
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in name):
        return False
    parts = name.rstrip('/').split('/')
    return bool(parts[-1]) and len(parts) <= 16 and all(
        part and part not in ('.', '..') and not part.endswith(('.', ' ')) for part in parts)


def kind_of(name):
    suffix = Path(name).suffix.lower()
    return suffix if suffix in KNOWN else 'other'


def zip_mode(info):
    mode = (info.external_attr >> 16) & 0xF000
    return mode in (0, stat.S_IFREG if not info.is_dir() else stat.S_IFDIR)


def candidate_identity(info):
    return {'zip_name': info.filename, 'header_offset': info.header_offset,
            'zip_crc32': f'{info.CRC:08x}', 'declared_bytes': info.file_size,
            'compressed_bytes': info.compress_size}


def pkg_summary(data):
    inspected = inspect_pkg(data)
    kinds = Counter(kind_of('/'.join(m['path_components'])) for m in inspected['members'])
    return {'profile': 'observed-PKG-research-only',
            'pkg_header_numeric_string': inspected['pkg_header_numeric_string'],
            'member_count': inspected['member_count'], 'directory_count': inspected['directories'],
            'member_kinds': dict(sorted(kinds.items())),
            'body_sha256': inspected['body_sha256']}


def scan(archive, expected_sha256, *, start=0, limit=25, member_limit=MAX_PKG_BYTES):
    """Inspect one already-open, seekable regular file. Hash before and after scanning.

    Pre/post equal hashes detect many mutations but do NOT establish an atomic snapshot.
    The ZIP index is metadata, not proof of the declared member bytes.
    """
    if not HEX256.fullmatch(expected_sha256):
        raise CorpusError('expected SHA-256 must be 64 lowercase hex digits')
    if start < 0 or not 0 < limit <= MAX_SELECTED or not 0 < member_limit <= MAX_PKG_BYTES:
        raise CorpusError('invalid scan window or per-PKG byte ceiling')
    size = os.fstat(archive.fileno()).st_size
    if not 22 <= size <= MAX_ARCHIVE_BYTES:
        raise CorpusError('ZIP file length outside research limits')
    before = hash_file(archive)
    if before != expected_sha256:
        raise CorpusError('outer ZIP SHA-256 mismatch before inspection')
    try:
        declared_count = preflight_zip32(archive, size)
        archive.seek(0)
        with zipfile.ZipFile(archive, 'r', allowZip64=False) as z:
            entries = z.infolist()
            if len(entries) != declared_count or len(entries) > MAX_ENTRIES:
                raise CorpusError('ZIP entry count differs from checked directory')
            if sum(e.file_size for e in entries) > MAX_DECLARED_BYTES:
                raise CorpusError('aggregate declared expanded bytes exceed research limit')
            # Preserve each occurrence separately: a filename is not an identity.
            classified = [(e, kind_of(e.filename)) for e in entries]
            occurrences = Counter(k for e, k in classified if not e.is_dir())
            aliases = defaultdict(list)
            for e in entries:
                aliases[unicodedata.normalize('NFC', e.filename).casefold()].append(e.header_offset)
            ambiguous = {k for k, v in aliases.items() if len(v) > 1}
            pkgs = sorted((e for e, k in classified if not e.is_dir() and k == '.pkg'),
                          key=lambda e: (e.filename.encode('utf-8'), e.header_offset))
            selected = pkgs[start:start + limit]
            results = []
            work_bytes = 0
            for e in selected:
                item = candidate_identity(e)
                alias = unicodedata.normalize('NFC', e.filename).casefold()
                reject = None
                if not safe_name(e.filename):
                    reject = 'unsafe or unsupported decoded ZIP name'
                elif alias in ambiguous:
                    reject = 'case/Unicode-colliding ZIP name'
                elif not zip_mode(e):
                    reject = 'non-regular ZIP member or incompatible directory flag'
                elif e.flag_bits & ~0x080E or e.flag_bits & 1:
                    reject = 'encrypted or unsupported ZIP flags'
                elif e.extract_version >= 45:
                    reject = 'ZIP64-version member unsupported in this profile'
                elif e.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    reject = 'unsupported ZIP compression method'
                elif e.file_size == 0 or e.file_size > member_limit:
                    reject = 'member exceeds selected capture size or is empty'
                elif work_bytes + e.file_size > MAX_RUN_CAPTURE_BYTES:
                    reject = 'aggregate selected PKG capture budget exceeded'
                if reject:
                    item.update(status='skipped', reason=reject)
                    results.append(item)
                    continue
                work_bytes += e.file_size
                try:
                    # Read at most ceiling+1 bytes, without extracting or storing any paths.
                    with z.open(e, 'r') as stream:
                        data = stream.read(member_limit + 1)
                        if len(data) <= member_limit and stream.read(1):
                            raise CorpusError('member produced more than its limit')
                    if len(data) != e.file_size or len(data) > member_limit:
                        raise CorpusError('ZIP payload differs from declared length or exceeds limit')
                    item['pkg_sha256'] = hashlib.sha256(data).hexdigest()
                    try:
                        item.update(status='parsed', summary=pkg_summary(data))
                    except PackageError as exc:
                        item.update(status='unsupported_pkg_profile', reason=str(exc)[:200])
                except (OSError, EOFError, RuntimeError, ValueError, zlib.error, zipfile.BadZipFile, CorpusError) as exc:
                    item.update(status='damaged_zip_member', reason=str(exc)[:200])
                results.append(item)
    except (zipfile.BadZipFile, zipfile.LargeZipFile) as exc:
        raise CorpusError(f'invalid or unsupported ZIP directory: {exc}') from exc
    if hash_file(archive) != before:
        raise CorpusError('outer ZIP changed during inspection; reject the receipt')
    return {'schema': 'phoenix-bulk-zip-census-v1', 'research_only': True,
            'capture_guarantee': 'same open regular descriptor, equal pre/post SHA256; not atomic snapshot',
            'archive_sha256': before, 'archive_bytes': size, 'entry_count': len(entries),
            'candidate_occurrences': dict(sorted(occurrences.items())),
            'pkg_occurrences': len(pkgs), 'selected_start': start, 'selected_count': len(results),
            'selected_window_complete': start + limit >= len(pkgs) and not any(x['status'] == 'skipped' for x in results),
            'selected_declared_capture_bytes': work_bytes,
            'decoded_name_limitation': 'zipfile has decoded ZIP member names; original filename bytes are not authenticated',
            'colliding_name_groups': len(ambiguous), 'results': results,
            'unproven': ['ZIP listed entries not selected', 'GEO geometry', 'flight', 'model licenses']}


def serialize(report):
    data = (json.dumps(report, ensure_ascii=True, sort_keys=True, indent=2) + '\n').encode('utf-8')
    if len(data) > MAX_REPORT_BYTES:
        raise CorpusError('report size limit exceeded')
    return data


def scan_path(path, expected_sha256, *, start=0, limit=25, member_limit=MAX_PKG_BYTES):
    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
    if not hasattr(os, 'O_NOFOLLOW'):
        raise CorpusError('safe no-follow capture unavailable on this platform')
    with os.fdopen(os.open(path, flags), 'rb') as file:
        if not stat.S_ISREG(os.fstat(file.fileno()).st_mode):
            raise CorpusError('only regular ZIP files can be scanned')
        return scan(file, expected_sha256, start=start, limit=limit, member_limit=member_limit)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('zip', type=Path)
    parser.add_argument('--sha256', required=True, help='exact outer ZIP SHA-256, lowercase')
    parser.add_argument('--start', type=int, default=0, help='zero-based occurrence offset')
    parser.add_argument('--limit', type=int, default=25, help='PKGs to inspect in this window (1..128)')
    parser.add_argument('--report', type=Path, help='create a new JSON receipt; never overwrite')
    args = parser.parse_args(argv)
    try:
        if args.report is not None and os.path.lexists(args.report):
            raise CorpusError('report destination already exists')
        payload = serialize(scan_path(args.zip, args.sha256, start=args.start, limit=args.limit))
        if args.report is None:
            sys.stdout.buffer.write(payload)
        else:
            with open(args.report, 'xb') as output:
                output.write(payload)
    except (CorpusError, OSError, zipfile.BadZipFile) as exc:
        print(f'corpus scan refused: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
