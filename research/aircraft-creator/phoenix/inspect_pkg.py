#!/usr/bin/env python3
"""Read-only research probe for observed Phoenix RC aircraft .pkg files.

This is not a complete specification or aircraft importer. It inspects .pkg
bytes only: it does not read installed simulator files, extract or execute
members, interpret source paths, decode geometry, or bypass any protection.
Use only with files you are authorized to inspect. Requires Python 3 stdlib.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
import zlib

MAX_INPUT = 64 * 1024 * 1024
MAX_BODY = 128 * 1024 * 1024
MAX_CHUNK = 1_024_000
MAX_MEMBERS = 2048
MAX_DEPTH = 32
MAX_TEXT = 4096
MAX_MEMBER = 32 * 1024 * 1024
MAX_ZERO_PADDING = 512
MAX_REPORTED_PATH_BYTES = 256 * 1024
MAX_REPORT_BYTES = 8 * 1024 * 1024

class FormatError(ValueError):
    pass

class Cursor:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, n):
        if n < 0 or n > len(self.data) - self.pos:
            raise FormatError(f'truncated at {self.pos}, wanted {n} bytes')
        value = self.data[self.pos:self.pos + n]
        self.pos += n
        return value

    def u8(self):
        return self.take(1)[0]

    def u16(self):
        return struct.unpack('<H', self.take(2))[0]

    def u32(self):
        return struct.unpack('<I', self.take(4))[0]

    def raw_string(self):
        n = self.u16()
        if n > MAX_TEXT:
            raise FormatError('string limit exceeded')
        return self.take(n)


def display_name(raw):
    # Display is separate from identity: different byte encodings can produce
    # identical text. Both raw bytes and the chosen display decoding are kept.
    try:
        return raw.decode('utf-8'), 'utf-8'
    except UnicodeDecodeError:
        return raw.decode('latin-1'), 'latin-1'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_regular_file(path, limit, *, dir_fd=None, nofollow=False):
    """Capture bounded regular-file bytes once; hash and parse this same buffer.

    Nonblocking open prevents a FIFO from hanging before fstat on supported
    hosts. This is not an atomic filesystem snapshot or a sandbox. Callers
    requiring a confined child use an already-open directory and nofollow.
    """
    flags = os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_BINARY', 0)
    if nofollow:
        if not hasattr(os, 'O_NOFOLLOW'):
            raise FormatError('no-follow file capture is unavailable on this platform')
        flags |= os.O_NOFOLLOW
    with os.fdopen(os.open(path, flags, dir_fd=dir_fd), 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise FormatError('only regular files are accepted')
        data = source.read(limit + 1)
    if len(data) > limit:
        raise FormatError('input size limit exceeded')
    return data


def json_size_bound(value):
    # At most eight additional indentation spaces per line when nested in the
    # final report. This bounds output before retaining the aggregate report.
    rendered = json.dumps(value, indent=2, ensure_ascii=True)
    return len(rendered) + 8 * (rendered.count('\n') + 1)


def serialized_report(value):
    rendered = json.dumps(value, indent=2, ensure_ascii=True) + '\n'
    if len(rendered) > MAX_REPORT_BYTES:
        raise FormatError('serialized report limit exceeded')
    return rendered


def classify(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n') and data[12:16] == b'IHDR' and len(data) >= 24:
        w, h = struct.unpack('>II', data[16:24])
        return {'kind': 'PNG signature and IHDR', 'width': w, 'height': h}
    if data.startswith(b'BM') and len(data) >= 54 and struct.unpack_from('<I', data, 14)[0] >= 40:
        w, h = struct.unpack_from('<ii', data, 18)
        return {'kind': 'BMP signature and DIB fields', 'width': w, 'height': abs(h)}
    if data.startswith(b'\xff\xd8\xff'):
        return {'kind': 'JPEG signature'}
    if data and sum(c in (9, 10, 13) or 32 <= c <= 126 for c in data) / len(data) > .98:
        return {'kind': 'mostly printable ASCII'}
    return {'kind': 'binary or unclassified'}


def inspect(data):
    if len(data) > MAX_INPUT:
        raise FormatError('input size limit exceeded')
    cur = Cursor(data)
    if cur.u8() != 0:
        raise FormatError('unrecognized package marker')
    try:
        version = cur.raw_string().decode('ascii')
    except UnicodeDecodeError as exc:
        raise FormatError('non-ASCII package header label') from exc
    if not re.fullmatch(r'[0-9]+\.[0-9]{6}', version):
        raise FormatError(f'unrecognized package header numeric string: {version!r}')
    chunk_count = cur.u16()
    if not 0 < chunk_count <= 2048:
        raise FormatError('invalid chunk count')
    chunks = []
    body_parts = []
    body_size = 0
    for index in range(chunk_count):
        compressed_size, plain_size = cur.u32(), cur.u32()
        if not 0 < plain_size <= MAX_CHUNK or not 0 < compressed_size <= MAX_INPUT:
            raise FormatError('invalid chunk size')
        body_size += plain_size
        if body_size > MAX_BODY:
            raise FormatError('body size limit exceeded')
        offset = cur.pos
        block = cur.take(compressed_size)
        try:
            dec = zlib.decompressobj()
            inflated = dec.decompress(block, plain_size + 1)
        except zlib.error as exc:
            raise FormatError(f'zlib failure in chunk {index}: {exc}') from exc
        if len(inflated) != plain_size or not dec.eof or dec.unused_data or dec.unconsumed_tail:
            raise FormatError(f'invalid zlib or declared size in chunk {index}')
        chunks.append({'offset': offset, 'compressed_bytes': compressed_size, 'inflated_bytes': plain_size})
        body_parts.append(inflated)
    if cur.pos != len(data):
        raise FormatError('unexpected bytes following package chunks')
    body = b''.join(body_parts)
    bc = Cursor(body)
    if bc.take(4) != b'\x01\x00\x01\x00':
        raise FormatError('unrecognized body prefix')
    members = []
    directory_count = 0
    reported_path_bytes = 0
    report_size_bound = 4096 + len(version) + json_size_bound(chunks)
    if report_size_bound > MAX_REPORT_BYTES:
        raise FormatError('report metadata limit exceeded')

    def children(parent, parent_raw, parent_decoding, depth):
        nonlocal directory_count, reported_path_bytes, report_size_bound
        if depth > MAX_DEPTH:
            raise FormatError('tree depth limit exceeded')
        count = bc.u16()
        if count > MAX_MEMBERS:
            raise FormatError('child count limit exceeded')
        for _ in range(count):
            kind, name_raw = bc.u8(), bc.raw_string()
            name, decoding = display_name(name_raw)
            if len(members) + directory_count >= MAX_MEMBERS:
                raise FormatError('total entry limit exceeded')
            path = parent + [name]  # display only; never used as a local path
            path_raw = parent_raw + [name_raw.hex()]
            path_decoding = parent_decoding + [decoding]
            if kind == 1:
                directory_count += 1
                children(path, path_raw, path_decoding, depth + 1)
            elif kind == 0:
                reported_path_bytes += sum(len(part) // 2 for part in path_raw)
                if reported_path_bytes > MAX_REPORTED_PATH_BYTES:
                    raise FormatError('cumulative reported-path byte limit exceeded')
                _stored_source_path = bc.raw_string()  # intentionally not emitted
                size = bc.u32()
                if size > MAX_MEMBER:
                    raise FormatError('member size limit exceeded')
                offset = bc.pos
                content = bc.take(size)
                member = {'path_components': path, 'path_components_raw_hex': path_raw,
                                'path_component_display_decodings': path_decoding, 'body_offset': offset,
                                'bytes': size, 'sha256': sha(content),
                                'prefix_hex': content[:16].hex(), 'classification': classify(content)}
                report_size_bound += json_size_bound(member)
                if report_size_bound > MAX_REPORT_BYTES:
                    raise FormatError('cumulative report output limit exceeded')
                members.append(member)
                if bc.u16() != 0:
                    raise FormatError('nonzero file child count outside observed profile')
            else:
                raise FormatError(f'unknown entry kind {kind}')
    children([], [], [], 0)
    remainder = body[bc.pos:]
    if len(remainder) > MAX_ZERO_PADDING:
        raise FormatError('zero padding limit exceeded')
    if any(remainder):
        raise FormatError('unexpected nonzero data following observed tree')
    return {'pkg_header_numeric_string': version, 'input_bytes': len(data), 'input_sha256': sha(data),
            'chunk_count': chunk_count, 'chunks': chunks, 'body_bytes': len(body),
            'body_sha256': sha(body), 'body_prefix_hex': '01000100',
            'trailing_zero_bytes': len(remainder), 'directories': directory_count,
            'member_count': len(members), 'members': members}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pkg', type=Path)
    parser.add_argument('--sha256', required=True, help='expected SHA-256 of the exact input .pkg bytes')
    args = parser.parse_args()
    try:
        if len(args.sha256) != 64 or any(c not in '0123456789abcdefABCDEF' for c in args.sha256):
            raise FormatError('expected SHA-256 must be 64 hex characters')
        data = read_regular_file(args.pkg, MAX_INPUT)
        if sha(data) != args.sha256.lower():
            raise FormatError('input SHA-256 mismatch')
        print(serialized_report(inspect(data)), end='')
    except (FormatError, OSError) as exc:
        print(f'probe rejected file: {exc}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
