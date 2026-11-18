#!/usr/bin/env python3
"""Read an observed Phoenix MOD subset as data, without evaluating source code.

Research only: no GEO decoding, file/reference resolution, unit conversion,
mechanism binding, physics adoption or runtime qualification. Unsupported
syntax is outside this profile, not necessarily invalid Phoenix syntax.
"""
import argparse
from bisect import bisect_right
from collections import Counter, defaultdict
from dataclasses import dataclass
from fractions import Fraction
import json
import math
from pathlib import Path
import re
import sys

from inspect_pkg import display_name, read_regular_file, sha

PROFILE = 'openrc-phoenix-mod-observed-v1'
MAX_INPUT = 512 * 1024
MAX_TOKENS = 60_000
MAX_NODES = 25_000
MAX_DEPTH = 32
MAX_STRING = 4096
MAX_IDENTIFIER = 128
MAX_NUMBER = 64
MAX_DIAGNOSTICS = 512
MAX_REPORT_BYTES = 1024 * 1024
IDENTIFIER = re.compile(rb'[A-Za-z_][A-Za-z0-9_]*')
NUMBER = re.compile(rb'-?[0-9]+(?:\.[0-9]+)?')
SYMBOLS = {b'physics.airplane', b'physics.helicopter'}
GEOMETRY_CONTEXTS = {('body',), ('airfoils', '*', 'sides', '*'),
                     ('gear', '*', 'sides', '*'), ('widgets', '*', 'sides', '*')}
PIVOT_CONTEXTS = {('airfoils', '*', 'controlSurfaces', '*'), ('airfoils', '*', 'flaps', '*'),
                  ('gear', '*'), ('widgets', '*')}
AXIS_CONTEXTS = {('gear', '*', 'wheels', '*')}


class DefinitionError(ValueError):
    def __init__(self, code, message, source, offset):
        self.code, self.offset = code, offset
        self.line = source.count(b'\n', 0, offset) + 1
        self.column = offset - source.rfind(b'\n', 0, offset)
        super().__init__(f'{code} at byte {offset}, line {self.line}, byte column {self.column}: {message}')


@dataclass(frozen=True)
class Token:
    kind: str
    raw: bytes
    start: int
    end: int


@dataclass(frozen=True)
class Entry:
    key: str | None
    key_start: int
    value: 'Node'


@dataclass(frozen=True)
class Node:
    kind: str
    value: object
    start: int
    end: int


@dataclass(frozen=True)
class Definition:
    source: bytes
    target: str
    root: Node
    token_count: int
    node_count: int


def tokenize(source):
    if len(source) > MAX_INPUT:
        raise DefinitionError('INPUT_LIMIT', 'definition byte limit exceeded', source, 0)
    for index, byte in enumerate(source):
        if byte == 13 and (index + 1 == len(source) or source[index + 1] != 10):
            raise DefinitionError('UNSUPPORTED_LINE_ENDING', 'only LF or CRLF line endings are in this profile', source, index)
    tokens, position = [], 0

    def fail(code, message, at=None):
        raise DefinitionError(code, message, source, position if at is None else at)

    def add(kind, raw, start, end):
        if len(tokens) >= MAX_TOKENS:
            fail('TOKEN_LIMIT', 'token limit exceeded', start)
        tokens.append(Token(kind, raw, start, end))

    while position < len(source):
        byte = source[position]
        if byte in b' \t\r\n':
            position += 1
            continue
        if source.startswith(b'--', position):
            if source.startswith(b'--[', position):
                fail('UNSUPPORTED_COMMENT', 'only line comments are in the observed profile')
            end = source.find(b'\n', position)
            position = len(source) if end == -1 else end + 1
            continue
        start = position
        if byte == 34:
            position += 1
            value_start = position
            while position < len(source) and source[position] != 34:
                if source[position] == 92:
                    fail('UNSUPPORTED_ESCAPE', 'string escapes need a separately evidenced profile')
                if source[position] < 32 or source[position] == 127:
                    fail('STRING_CONTROL', 'control byte in quoted string')
                if position - value_start >= MAX_STRING:
                    fail('STRING_LIMIT', 'quoted string byte limit exceeded', start)
                position += 1
            if position == len(source):
                fail('UNTERMINATED_STRING', 'missing closing quote', start)
            add('string', source[value_start:position], start, position + 1)
            position += 1
        elif 48 <= byte <= 57 or byte == 45:
            match = NUMBER.match(source, position)
            if match is None:
                fail('UNSUPPORTED_NUMBER', 'expected an observed fixed-point decimal')
            raw = match.group()
            if len(raw) > MAX_NUMBER:
                fail('NUMBER_LIMIT', 'numeric token byte limit exceeded')
            numeric = float(raw)
            if not math.isfinite(numeric) or (numeric == 0 and Fraction(raw.decode('ascii')) != 0):
                fail('NUMBER_RANGE', 'number cannot be represented as a finite non-underflowing float64')
            add('number', raw, position, match.end())
            position = match.end()
        elif (65 <= byte <= 90) or (97 <= byte <= 122) or byte == 95:
            match = IDENTIFIER.match(source, position)
            raw = match.group()
            if len(raw) > MAX_IDENTIFIER:
                fail('IDENTIFIER_LIMIT', 'identifier byte limit exceeded')
            add('identifier', raw, position, match.end())
            position = match.end()
        elif byte in b'{}=,.':
            add(chr(byte), bytes([byte]), position, position + 1)
            position += 1
        else:
            fail('UNSUPPORTED_BYTE', 'byte outside the observed data grammar')
    tokens.append(Token('eof', b'', len(source), len(source)))
    return tokens


class Parser:
    def __init__(self, source):
        self.source = source
        self.tokens = tokenize(source)
        self.position = self.nodes = 0

    def fail(self, code, message, token=None):
        token = self.tokens[self.position] if token is None else token
        raise DefinitionError(code, message, self.source, token.start)

    def take(self, kind, raw=None):
        token = self.tokens[self.position]
        if token.kind != kind or (raw is not None and token.raw != raw):
            self.fail('UNSUPPORTED_SYNTAX', f'expected {kind}' + (f' {raw!r}' if raw else ''))
        self.position += 1
        return token

    def node(self, kind, value, start, end):
        self.nodes += 1
        if self.nodes > MAX_NODES:
            raise DefinitionError('NODE_LIMIT', 'node limit exceeded', self.source, start)
        return Node(kind, value, start, end)

    def value(self, depth):
        token = self.tokens[self.position]
        if token.kind == '{':
            if depth > MAX_DEPTH:
                self.fail('DEPTH_LIMIT', 'nested table limit exceeded')
            self.take('{')
            entries, seen, mode = [], set(), None
            while self.tokens[self.position].kind != '}':
                current = self.tokens[self.position]
                keyed = current.kind == 'identifier' and self.tokens[self.position + 1].kind == '='
                next_mode = 'keyed' if keyed else 'positional'
                if mode is not None and mode != next_mode:
                    self.fail('MIXED_TABLE', 'mixed keyed and positional entries need a separate profile')
                mode = next_mode
                key, key_start = None, current.start
                if keyed:
                    key = self.take('identifier').raw.decode('ascii')
                    self.take('=')
                    if key in seen:
                        self.fail('DUPLICATE_KEY', 'exact duplicate key would overwrite source data', current)
                    seen.add(key)
                entries.append(Entry(key, key_start, self.value(depth + 1)))
                if self.tokens[self.position].kind != ',':
                    break
                self.take(',')
            end = self.take('}').end
            return self.node('table', tuple(entries), token.start, end)
        if token.kind in ('string', 'number'):
            self.position += 1
            return self.node(token.kind, token.raw, token.start, token.end)
        if token.kind == 'identifier':
            first = self.take('identifier')
            self.take('.')
            second = self.take('identifier')
            symbol = first.raw + b'.' + second.raw
            if symbol not in SYMBOLS:
                self.fail('UNSUPPORTED_SYMBOL', 'symbol is not in the observed data allowlist', first)
            return self.node('symbol', symbol, first.start, second.end)
        self.fail('UNSUPPORTED_VALUE', 'expected a table, quoted bytes, decimal or allowed symbol')

    def parse(self):
        self.take('identifier', b'modelTypes')
        self.take('.')
        target = self.take('identifier').raw.decode('ascii')
        self.take('=')
        root = self.value(0)
        if root.kind != 'table':
            self.fail('ROOT_SHAPE', 'model assignment requires a table', self.tokens[0])
        if any(entry.key is None for entry in root.value):
            self.fail('ROOT_SHAPE', 'model assignment requires named fields', self.tokens[0])
        self.take('eof')
        return Definition(self.source, target, root, len(self.tokens) - 1, self.nodes)


def parse(source):
    if not isinstance(source, bytes):
        raise TypeError('MOD parsing requires captured bytes')
    return Parser(source).parse()


def fields(node):
    return {entry.key: entry.value for entry in node.value if entry.key is not None} if node.kind == 'table' else {}


def walk(node, path):
    yield path, node
    if node.kind == 'table':
        for index, entry in enumerate(node.value):
            yield from walk(entry.value, path + (entry.key if entry.key is not None else index,))


def string_identity(raw):
    display, decoding = display_name(raw)
    return {'display': display, 'raw_hex': raw.hex(), 'display_decoding': decoding}


def summarize(definition):
    source, root = definition.source, definition.root
    line_starts = [0] + [index + 1 for index, byte in enumerate(source) if byte == 10]
    diagnostics = []
    counts = Counter()
    reference_roles = Counter()
    repeated_names = defaultdict(list)
    semantic_field_kinds = defaultdict(Counter)

    def span(node):
        line = bisect_right(line_starts, node.start)
        return {'start_byte': node.start, 'end_byte_exclusive': node.end,
                'line': line, 'byte_column': node.start - line_starts[line - 1] + 1}

    def diagnostic(code, severity, path, node, detail):
        if len(diagnostics) >= MAX_DIAGNOSTICS:
            raise DefinitionError('DIAGNOSTIC_LIMIT', 'diagnostic count limit exceeded', source, node.start)
        diagnostics.append({'code': code, 'severity': severity, 'path': list(path),
                            'span': span(node), 'detail': detail})

    def vector(node):
        values = fields(node)
        if set(values) != {'x', 'y', 'z'} or any(value.kind != 'number' for value in values.values()):
            return None
        return tuple(Fraction(values[axis].value.decode('ascii')) for axis in ('x', 'y', 'z'))

    for path, node in walk(root, (definition.target,)):
        counts[node.kind] += 1
        if node.kind == 'string' and any(byte >= 128 for byte in node.value):
            counts['strings_with_non_ascii_bytes'] += 1
            diagnostic('DISPLAY_DECODING_ONLY', 'observation', path, node,
                       'Raw bytes are authoritative; UTF-8/Latin-1 display selection does not prove the source encoding.')
        if node.kind != 'table':
            continue
        entries = fields(node)
        context = tuple('*' if isinstance(part, int) else part for part in path[1:])
        by_case = defaultdict(list)
        for entry in node.value:
            if entry.key is not None:
                by_case[entry.key.casefold()].append(entry.key)
                if entry.key in ('Engine', 'Airfoil', 'material', 'blurTexture', 'node'):
                    semantic_field_kinds[entry.key][entry.value.kind] += 1
        for keys in by_case.values():
            if len(keys) > 1:
                diagnostic('CASE_VARIANT_KEYS', 'unresolved', path, node,
                           'Distinct keys preserved without case folding: ' + ', '.join(keys))
        if 'name' in entries and entries['name'].kind == 'string':
            repeated_names[entries['name'].value].append((path + ('name',), entries['name']))
        geometry = entries.get('geometry')
        if geometry is not None and context in GEOMETRY_CONTEXTS:
            if geometry.kind != 'table' or any(entry.key is not None or entry.value.kind != 'string'
                                               for entry in geometry.value):
                diagnostic('GEOMETRY_LIST_SHAPE', 'conversion_blocker', path + ('geometry',), geometry,
                           'The observed geometry role needs an ordered list of quoted object references.')
            elif not geometry.value:
                counts['empty_geometry_lists'] += 1
            else:
                reference_roles['geometry_object'] += len(geometry.value)
        for key in ('node', 'blurTexture', 'Airfoil', 'Engine'):
            value = entries.get(key)
            if value is not None and value.kind == 'string':
                # These are literal field observations, not established library
                # or asset roles merely because a key has a familiar spelling.
                reference_roles[key + '_string_field'] += 1
        pivots = ('root_pivot' in entries, 'tip_pivot' in entries)
        if any(pivots) and context in PIVOT_CONTEXTS:
            counts['pivot_pairs_declared'] += 1
            pair = [vector(entries[key]) if key in entries else None for key in ('root_pivot', 'tip_pivot')]
            if None in pair:
                diagnostic('PIVOT_PAIR_SHAPE', 'conversion_blocker', path, node,
                           'Both pivots need exactly three numeric x/y/z fields in this profile.')
            elif pair[0] == pair[1]:
                diagnostic('COINCIDENT_PIVOTS', 'conversion_blocker', path, node,
                           'Exactly coincident source pivots cannot define a hinge axis.')
            elif tuple(map(float, pair[0])) == tuple(map(float, pair[1])):
                diagnostic('PIVOT_PRECISION_LOSS', 'conversion_blocker', path, node,
                           'Distinct exact decimal pivots collapse under direct float64 coordinate conversion.')
        axis = entries.get('axis')
        if axis is not None and context in AXIS_CONTEXTS:
            value = vector(axis)
            if value is None:
                diagnostic('AXIS_SHAPE', 'conversion_blocker', path + ('axis',), axis,
                           'An observed axis needs exactly three numeric x/y/z fields.')
            elif all(component == 0 for component in value):
                diagnostic('ZERO_AXIS', 'conversion_blocker', path + ('axis',), axis,
                           'A zero source vector cannot be normalized; no unit-norm or broad epsilon rule is imposed.')
        for key, known in (('geometry', context in GEOMETRY_CONTEXTS), ('axis', context in AXIS_CONTEXTS),
                           ('root_pivot', context in PIVOT_CONTEXTS), ('tip_pivot', context in PIVOT_CONTEXTS)):
            if key in entries and not known:
                diagnostic('UNCLASSIFIED_FIELD_CONTEXT', 'unresolved', path + (key,), entries[key],
                           'The field name alone does not establish a geometry, hinge or axis role; source value retained.')
    repeated_count = 0
    for occurrences in repeated_names.values():
        if len(occurrences) > 1:
            repeated_count += 1
            for path, node in occurrences:
                diagnostic('REPEATED_NAME', 'observation', path, node,
                           'Display name repeats; retain ordered structural identity and every occurrence.')
    headers = {}
    for key in ('name', 'type', 'revision', 'formatVersion', 'minProgramVersion', 'physics', 'nodeCount'):
        node = fields(root).get(key)
        if node is not None and node.kind in ('string', 'number', 'symbol'):
            representation = {'symbol': 'canonical symbolic name', 'number': 'numeric source lexeme',
                              'string': 'quoted content bytes'}[node.kind]
            headers[key] = {'kind': node.kind, 'value': string_identity(node.value),
                            'value_representation': representation,
                            'source_lexeme_raw_hex': source[node.start:node.end].hex(), 'span': span(node)}
    report = {
        'schema': 'openrc-phoenix-definition-observations-v1', 'profile': PROFILE,
        'input_bytes': len(source), 'input_sha256': sha(source), 'target': definition.target,
        'token_count': definition.token_count, 'node_count': definition.node_count,
        'headers': headers, 'counts': dict(sorted(counts.items())),
        'repeated_name_groups': repeated_count,
        'selected_reference_and_string_field_counts': dict(sorted(reference_roles.items())),
        'context_sensitive_field_kinds': {key: dict(sorted(value.items()))
                                          for key, value in sorted(semantic_field_kinds.items())},
        'diagnostics': diagnostics,
        'status': 'parsed observations; source semantics and conversion remain unqualified',
        'unresolved': ['GEO object identity and all dependency resolution',
                       'units, coordinate frames, scale, mirroring and articulation semantics',
                       'source libraries, physical models, runtime admission and flight qualification'],
    }
    serialized_report(report)
    return report


def serialized_report(report):
    output = json.dumps(report, indent=2, ensure_ascii=True, allow_nan=False) + '\n'
    if len(output) > MAX_REPORT_BYTES:
        raise ValueError('definition report byte limit exceeded')
    return output


def inspect(source):
    return summarize(parse(source))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mod', type=Path)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    try:
        if not re.fullmatch(r'[0-9a-fA-F]{64}', args.sha256):
            raise ValueError('expected SHA-256 must be 64 hex characters')
        data = read_regular_file(args.mod, MAX_INPUT)
        if sha(data) != args.sha256.lower():
            raise ValueError('input SHA-256 mismatch')
        print(serialized_report(inspect(data)), end='')
    except (DefinitionError, ValueError, OSError) as exc:
        print(f'definition probe rejected file: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
