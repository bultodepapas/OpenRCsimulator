"""Run one capture and accept only fresh, decodable evidence from a successful process.

Uses the existing visual Python environment. No screenshot thresholds live here.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

from PIL import Image


def run_capture(command: list[str], output: Path, kind: str, scene: str,
                timeout: float = 60.0) -> dict:
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = output.with_suffix('.json')
    log = output.with_suffix('.log')
    # Delete both before launching: success can never be inferred from an older run.
    for path in (output, manifest):
        path.unlink(missing_ok=True)
    try:
        with log.open('w') as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                status = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                # xvfb-run and Godot belong to this group; don't leave a renderer writing late evidence.
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise RuntimeError(f'capture timed out after {timeout}s') from error
        text = log.read_text(errors='replace')
        if status != 0:
            raise RuntimeError(f'capture process exited {status}')
        text = re.sub(r'\x1b\[[0-9;]*m', '', text)
        if re.search(r'^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:', text, re.M):
            raise RuntimeError('engine error during capture')
        with Image.open(output) as image:
            if image.format != 'PNG' or image.size != (1280, 720):
                raise RuntimeError('expected a 1280x720 PNG')
            image.load()  # A PNG header alone is not a valid screenshot.
        sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
        if kind == 'flight':
            data = json.loads(manifest.read_text())
            if data.get('image') != output.name or data.get('sha256') != sha256:
                raise RuntimeError('capture manifest image/hash mismatch')
            if data.get('capture_scene') != scene:
                raise RuntimeError('capture manifest scene mismatch')
            for key in ('draw_calls', 'primitives'):
                values = data.get(key, {})
                if not isinstance(values, dict) or any(type(values.get(p)) is not int or values[p] < 0 for p in ('visible', 'shadow')):
                    raise RuntimeError(f'invalid render counters: {key}')
                # A sky-only view legitimately has zero visible mesh draws (the sun case does).
            # Legacy landscape checks consume the sun/clock/shadow projection data from this line.
            saved = [line for line in text.splitlines() if line.startswith(f'saved {output} (error 0) draw_calls=')]
            if len(saved) != 1:
                raise RuntimeError('missing or ambiguous successful capture record')
        elif kind == 'ui':
            # capture_ui has no engine manifest; identify this as harness evidence, not GPU telemetry.
            data = {'format': 'openrc-ui-capture v1', 'producer': 'capture_runner',
                    'image': output.name, 'sha256': sha256, 'size': [1280, 720],
                    'capture_scene': scene, 'process_exit': status}
            manifest.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
        else:
            raise RuntimeError(f'unknown capture kind: {kind}')
        return data
    except Exception as error:
        # Retain diagnostics, never leave a partial PNG/JSON looking like accepted evidence.
        for path in (output, manifest):
            path.unlink(missing_ok=True)
        raise RuntimeError(f'{output.name}: {error}; log: {log}') from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--kind', choices=['flight', 'ui'], required=True)
    parser.add_argument('--scene', required=True)
    parser.add_argument('--timeout', type=float, default=60.0)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or args.timeout <= 0:
        parser.error('a command and positive timeout are required')
    try:
        run_capture(command, args.out, args.kind, args.scene, args.timeout)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    print(f'verified {args.out.name} ({args.scene})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
