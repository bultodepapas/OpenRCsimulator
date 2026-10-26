#!/usr/bin/env python3
"""Recompute descriptive Reddit snapshot tables from reviewed annotations.

Uses only Python's standard library. Does not fetch Reddit or infer sentiment.
"""

import argparse
import csv
import hashlib
import re
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'docs/research/reddit-launch-feedback-2026-10-26'
THEMES = {
    'AI': 'AI use and development process',
    'CREDIBILITY': 'Credibility, evidence and realism claims',
    'PHYSICS': 'Handling, physical methods and validation questions',
    'CONTROLS': 'Radios, calibration and mapping',
    'PRACTICE': 'Training, menus, starts, resets and crash workflow',
    'SCENERY': 'Scenery quality, local fields and terrain',
    'AUTHORING': 'Aircraft/field import, creation and sharing',
    'ACTIVITIES': 'Soaring, drones, autopilots and other activities',
    'PLATFORMS': 'Platforms, VR, multiplayer and language availability',
    'COLLABORATION': 'Offers, contributions and technical exchanges',
    'VALUE': 'Free/open source and competitor differentiation',
    'COMMUNICATION': 'Public wording, presentation and discoverability',
    'SUPPORT': 'Explicit encouragement or positive interest',
    'OFF_TOPIC': 'Jokes and tangential non-product conversation',
    'PERFORMANCE': 'Runtime performance observations',
    'CAMERAS': 'Ground-pilot and onboard/FPV views',
}
REQUESTS = {
    'aircraft_import': 'Custom aircraft import/integration, including Flyout',
    'local_fields': 'Create/import/share a familiar field or lake',
    'panorama': 'Specifically import a 360-degree airfield photograph',
    'radio_setup': 'Easier radio setup or move-to-bind mapping',
    'spektrum': 'Spektrum compatibility question/request',
    'crash_optional': 'Optional/unobtrusive crash costs and practice workflow',
    'ground_view': 'Ground-pilot camera',
    'fpv': 'FPV/first-person view or support',
    'soaring': 'Sailplanes or thermals/high-start soaring',
    'structural_damage': 'Visible flex/deformation or continued damaged flight',
    'field_mcp': 'AI/MCP-assisted field creation',
    'flightcoach': 'FlightCoach/FlightScore real-flight interchange',
    'vr': 'VR support',
    'multiplayer': 'Multiplayer',
    'scenery_packs': 'Downloadable scenery packs',
    'drones': 'Drone support',
    'mac': 'Mac availability',
    'autopilot': 'ArduPilot and simultaneous manual control',
    'mobile': 'Mobile/desktop availability clarification',
    'terrain': 'Variable terrain and mountain surfing',
    'rockets': 'Steerable rockets',
    'external_games': 'Port aircraft physics into other game worlds',
    'language': 'Language availability/discoverability',
}


def collect():
    source = (EVIDENCE / 'comments.md').read_text()
    annotations = list(csv.DictReader(Path(__file__).with_name('annotations.tsv').open(), delimiter='\t'))
    by_id = {r['id']: r for r in annotations}
    assert len(by_id) == len(annotations), 'Duplicate annotation IDs'
    records = []
    for section in source.split('<a id="comment-')[1:]:
        ident = section.split('"', 1)[0]
        author = re.search(r'### \d+ · u/(.*?) ·', section).group(1)
        op = author.endswith(' (OP)')
        record = dict(id=ident, author=author.removesuffix(' (OP)'), op=op,
                      score=int(re.search(r'score at retrieval: (-?\d+)', section).group(1)),
                      created=re.search(r'Created: (.*?); edited:', section).group(1))
        if op:
            record.update(kind='op_context', exposure='not_coded', themes=[], requests=[],
                          note='OP response/context; excluded from community recurrence and score tables.')
        else:
            a = by_id.pop(ident)
            record.update({k: a[k] for k in ('kind', 'exposure', 'note')})
            for key, allowed in [('themes', THEMES), ('requests', REQUESTS)]:
                record[key] = [] if a[key] == '-' else a[key].split(',')
                assert len(record[key]) == len(set(record[key])), (ident, key)
                assert set(record[key]) <= set(allowed), (ident, key)
        records.append(record)
    assert not by_id, f'Annotations without source: {by_id}'
    assert len({r['id'] for r in records}) == len(records) == 169
    assert sum(r['op'] for r in records) == 54
    assert len({r['author'] for r in records if not r['op']}) == 67
    return records


def ref(r):
    return f'[{r["id"]}](comments.md#comment-{r["id"]})'


def render(records):
    community = [r for r in records if not r['op']]
    lines = ['# Comment coding and descriptive statistics', '',
             'Generated from [annotations.tsv](../../../research/reddit-launch-feedback/annotations.tsv) and the [archived transcript](comments.md) by [analyze.py](../../../research/reddit-launch-feedback/analyze.py). See [interpretation and limits](insights.md).', '',
             'Regenerate: `python3 research/reddit-launch-feedback/analyze.py`; verify without writing: append `--check`.', '',
             '## Scope and denominators', '',
             '- 169 comment records; 54 OP replies retained as context but excluded from community statistics.',
             '- 115 community comments by 67 distinct handles. Handles are not verified unique humans or independent samples.',
             '- Multi-label manual coding: discussion is not necessarily a request, support, complaint or hands-on test.',
             '- Scores are archived net scores. They are not upvote counts, unique supporters or feature votes. No scores are refreshed here.',
             '- Theme score sums overlap when a comment has several tags; never add rows or treat these sums as priority scores.',
             '- Feature rows count explicit requests/questions/endorsements. Follow-ups by the same handle do not add a requester. Request families and subsets overlap.', '',
             '## Topic recurrence (community only)', '',
             '| Topic | Comments | Handles / 67 | % of handles | Sum of comment scores | Median | Maximum |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    groups = [(key, [r for r in community if key in r['themes']]) for key in THEMES]
    for key, rows in sorted(groups, key=lambda p: (-len({r['author'] for r in p[1]}), p[0])):
        authors = len({r['author'] for r in rows})
        scores = [r['score'] for r in rows]
        lines.append(f'| {THEMES[key]} (`{key}`) | {len(rows)} | {authors} | {100*authors/67:.1f}% | {sum(scores)} | {median(scores):g} | {max(scores)} |')
    lines += ['', '## Explicit feature and compatibility signals', '',
              'Scores below belong to whole comments, often containing several requests. The peak score must not be interpreted as votes for the named feature. This table deliberately does not sum feature scores.', '',
              '| Family | Distinct handles | Comments | Peak whole-comment score | All source comments |',
              '| --- | ---: | ---: | ---: | --- |']
    groups = [(key, [r for r in community if key in r['requests']]) for key in REQUESTS]
    for key, rows in sorted(groups, key=lambda p: (-len({r['author'] for r in p[1]}), p[0])):
        lines.append(f'| {REQUESTS[key]} | {len({r["author"] for r in rows})} | {len(rows)} | {max(r["score"] for r in rows):+d} | {", ".join(ref(r) for r in rows)} |')
    lines += ['', '## Highest-scoring community comments', '',
              '| Comment | Author | Net score | Coding note |', '| --- | --- | ---: | --- |']
    for r in sorted(community, key=lambda r: (-r['score'], r['created'], r['id']))[:15]:
        lines.append(f'| {ref(r)} | {r["author"]} | {r["score"]:+d} | {r["note"]} |')
    hands = [r for r in community if r['exposure'] == 'firsthand']
    lines += ['', '## Explicit OpenRC usage reports', '',
              f'{len(hands)} comments by {len({r["author"] for r in hands})} handles explicitly describe using/testing OpenRC. This is a conservative textual classification, not proof that other authors did not use it or that these reports were reproduced.', '',
              '| Comment | Author | Net score | Observation |', '| --- | --- | ---: | --- |']
    for r in hands:
        lines.append(f'| {ref(r)} | {r["author"]} | {r["score"]:+d} | {r["note"]} |')
    lines += ['', '## Complete coding ledger', '',
              'Every archived record appears once below. OP replies remain available through their source links. `unknown` means the comment does not establish exposure; `other_product` includes real-world experience and discussion of another product. `website` does not establish simulator use. Theme and request definitions are in the generator; individual inclusion judgments are in the annotation file.', '',
              '| Comment | Author | Score | Kind / exposure | Themes | Explicit requests | Interpretation |',
              '| --- | --- | ---: | --- | --- | --- | --- |']
    for r in records:
        lines.append(f'| {ref(r)} | {r["author"]}{" (OP)" if r["op"] else ""} | {r["score"]:+d} | {r["kind"]} / {r["exposure"]} | {", ".join(r["themes"]) or "—"} | {", ".join(r["requests"]) or "—"} | {r["note"]} |')
    lines += ['', '## Input identities', '',
              'Hashes identify this collection and coding pass, not the live Reddit page.', '']
    for path in [EVIDENCE / 'comments.md', Path(__file__).with_name('annotations.tsv')]:
        lines.append(f'- `{path.relative_to(ROOT)}`: SHA-256 `{hashlib.sha256(path.read_bytes()).hexdigest()}`.')
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    records = collect()
    result = render(records)
    output = EVIDENCE / 'coding.md'
    if args.check:
        if not output.exists() or output.read_text() != result:
            raise SystemExit('FAIL: coding.md differs from source/annotations; regenerate it.')
    else:
        output.write_text(result)
    print(f'PASS: {len(records)} unique source comments, 115 annotations, 54 OP context rows; all IDs and labels validated.')
