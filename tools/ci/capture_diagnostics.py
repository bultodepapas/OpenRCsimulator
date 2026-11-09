#!/usr/bin/env python3
"""Create a bounded review bundle; complete raw captures remain a separate artifact."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

from capture_groups import UI_IMAGES, VQ_CASES, excluded_output


def prepare(captures: Path, out: Path, *, budget: int = 64 * 1024 * 1024,
            per_file: int = 4 * 1024 * 1024) -> dict:
    captures = captures.resolve(strict=True)
    if budget <= 0 or per_file <= 0:
        raise ValueError("diagnostic size limits must be positive")
    if not captures.is_dir() or out.resolve().is_relative_to(captures):
        raise ValueError("diagnostic output must be outside the capture tree")
    out.mkdir(parents=True, exist_ok=False)
    selected, omitted, used = [], [], 0
    candidates, failed_dirs = [], set()
    ui_images = set(UI_IMAGES) | {f'vq01b/{case}.png' for case in VQ_CASES if case.startswith('ui-')}
    ui_paths = ui_images | {Path(p).with_suffix('.json').as_posix() for p in ui_images}
    for directory, dirs, names in os.walk(captures, followlinks=False):
        parent = Path(directory)
        dirs[:] = sorted(name for name in dirs if not (parent / name).is_symlink()
                         and not excluded_output((parent / name).relative_to(captures).as_posix()))
        for name in sorted(names):
            source = parent / name
            relative = source.relative_to(captures).as_posix()
            if source.is_symlink() or not source.is_file() or excluded_output(relative):
                continue
            if relative not in ui_paths and source.suffix.lower() not in {'.json', '.log', '.tsv'}:
                continue
            size = source.stat().st_size
            candidates.append((source, relative, size))
            if name == 'report.json' and size <= per_file:
                try:
                    value = json.loads(source.read_bytes())
                    if isinstance(value, dict) and value.get('format') == 'openrc-godot-check v1' and value.get('ok') is not True:
                        failed_dirs.add(parent)
                except (ValueError, UnicodeDecodeError):
                    failed_dirs.add(parent)

    def priority(item):
        source, relative, _ = item
        if source.parent in failed_dirs and source.name in {'report.json', 'engine.log'}:
            return (0, source.name != 'report.json', relative)
        if relative in ui_paths or source.name.endswith('-metrics.json'):
            return (1, False, relative)
        if source.name == 'report.json':
            return (2, False, relative)
        if source.suffix == '.log':
            return (3, False, relative)
        return (4, False, relative)

    for source, relative, size in sorted(candidates, key=priority):
        if size > per_file or used + size > budget:
            omitted.append({"path": relative, "bytes": size, "reason": "size limit"})
            continue
        target = out / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        # A failing prefix is diagnostic, never a replacement for raw evidence.
        with source.open('rb') as incoming, target.open('xb') as copied:
            remaining = min(per_file, budget - used)
            while remaining:
                block = incoming.read(min(65536, remaining))
                if not block:
                    break
                copied.write(block)
                remaining -= len(block)
            overflow = bool(incoming.read(1))
        if overflow:
            target.unlink()
            omitted.append({"path": relative, "bytes": source.stat().st_size, "reason": "grew past size limit"})
            continue
        copied_size = target.stat().st_size
        used += copied_size
        selected.append({"path": relative, "bytes": copied_size,
                         "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    report = {"format": "openrc-capture-diagnostics v1", "qualification": False,
              "payload_bytes": used, "budget_bytes": budget, "per_file_bytes": per_file,
              "files": selected, "omitted": omitted}
    (out / 'diagnostics-index.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    lines = ['# Capture diagnostics', '', 'Review aid only; complete raw evidence is in `captures-app`.', '',
             f'{len(selected)} files, {used} payload bytes; {len(omitted)} files omitted by size limits.', '']
    lines += [f'- [{row["path"]}](<{row["path"]}>) ({row["bytes"]} bytes)' for row in selected]
    (out / 'README.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        report = prepare(args.captures, args.out)
    except (OSError, ValueError) as error:
        parser.exit(1, f'capture diagnostics: {error}\n')
    print(f'Capture diagnostics: {len(report["files"])} files, {report["payload_bytes"]} bytes; '
          f'{len(report["omitted"])} omitted. Raw evidence retained separately.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
