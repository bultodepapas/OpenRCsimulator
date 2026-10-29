#!/usr/bin/env python3
"""Drive MoonRunner Blender phases through the official project MCP server."""
import argparse
import asyncio
from datetime import timedelta
import hashlib
import json
import os
from pathlib import Path
import tempfile
import sys
import time

EXPECTED_GLB = '54d67d9bbfe4ce4abdc4bafa523c3bf812422d6336ba1d0f151a2970e087b0f0'
EXPECTED_STOCK = '3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac'
EXPECTED_BOLIDO = '9ecaf7b49aec555bbea178b3b582378bb362bec3f816448932438db2c8da8f93'
PHASES = ('bake', 'baseline', 'blank', 'candidate', 'compose', 'export')


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def publish_copy(source, target, expected):
    if target.exists():
        raise RuntimeError(f'Refusing to overwrite {target}')
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.moonrunner-', suffix='.tmp', dir=target.parent, delete=False) as out:
            temporary = Path(out.name)
            with source.open('rb') as src:
                for chunk in iter(lambda: src.read(1024 * 1024), b''):
                    out.write(chunk)
            out.flush()
            os.fsync(out.fileno())
        if sha256(temporary) != expected:
            raise RuntimeError('Staged derivative hash mismatch')
        # Atomic creation without replacing an output created by another process.
        os.link(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    if sha256(target) != expected:
        raise RuntimeError(f'Installed output hash mismatch: {target}')
    print(f'Installed separate asset: {target} SHA256 {expected}')


def install(repo, work):
    source = work / 'moonrunner-experiment.glb'
    marker = work / 'export.complete'
    evidence = work / 'export-evidence.json'
    stock = repo / 'app/assets/aircraft/skywalker-x8/skywalker_x8.glb'
    target = repo / 'app/assets/aircraft/moonrunner-x99/moonrunner_x99.glb'
    if not marker.is_file() or marker.read_text(encoding='utf-8') != 'ok\n' or not evidence.is_file():
        raise RuntimeError('Verified export and evidence are required before install')
    proof = json.loads(evidence.read_text(encoding='utf-8'))
    if (proof.get('derived_glb_sha256') != EXPECTED_GLB or proof.get('source_glb_sha256') != EXPECTED_STOCK
            or sha256(source) != EXPECTED_GLB):
        raise RuntimeError('Verified export and evidence are required before install')
    if sha256(stock) != EXPECTED_STOCK:
        raise RuntimeError('The original stock GLB no longer matches')
    publish_copy(source, target, EXPECTED_GLB)


def install_bolido(repo):
    source = repo / 'app/assets/aircraft/skywalker-x8/skywalker_x8_bolido.glb'
    target = repo / 'app/assets/aircraft/moonrunner-x99/moonrunner_x99_bolido.glb'
    if sha256(source) != EXPECTED_BOLIDO:
        raise RuntimeError('The original BOLIDO GLB no longer matches')
    publish_copy(source, target, EXPECTED_BOLIDO)


async def call(repo, work, deps, phase, max_wait, server):
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
    script = repo / 'tools/aircraft/moonrunner/blender_phase.py'
    args = {'repo': str(repo), 'work': str(work), 'deps': str(deps), 'phase': phase}
    code = f"import runpy; runpy.run_path({str(script)!r}, init_globals={{'RUN_ARGS': {args!r}}})"
    params = StdioServerParameters(command=str(server))
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=360)) as session:
            await session.initialize()
            result = await session.call_tool('execute_blender_code', {'code': code})
            chunks = [item.text for item in result.content if item.type == 'text']
            message = '\n'.join(chunks)
            print(message, flush=True)
            timed_out = 'Blender connection timed out' in message
            if result.isError and not timed_out:
                raise RuntimeError('Official MCP call failed')
            if not timed_out:
                for chunk in chunks:
                    try:
                        payload = json.loads(chunk)
                    except json.JSONDecodeError:
                        continue
                    if payload.get('status') == 'error':
                        raise RuntimeError('Blender phase failed')
    # The official server returns after 300 s even when Blender is still working.
    # A timeout is never success: wait for the Blender-written completion/error file.
    complete, failed = work / f'{phase}.complete', work / f'{phase}.failed'
    deadline = time.monotonic() + max_wait
    while not complete.exists() and not failed.exists() and time.monotonic() < deadline:
        await asyncio.sleep(2)
    if failed.exists():
        raise RuntimeError(failed.read_text(encoding='utf-8'))
    if not complete.is_file() or complete.read_text(encoding='utf-8') != 'ok\n':
        raise RuntimeError(f'No verified completion marker for {phase}')
    print(f'Verified {phase}: {complete}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=(*PHASES, 'install', 'install-bolido'))
    parser.add_argument('--repo', type=Path, required=True, help='absolute repo path visible to Blender and client')
    parser.add_argument('--work', type=Path, help='scratch directory visible to Blender and client')
    parser.add_argument('--deps', type=Path, help='pinned scratch Python dependency directory')
    parser.add_argument('--server', type=Path, help='official MCP server wrapper (defaults to repo tools/blender/mcp-server.sh)')
    parser.add_argument('--max-wait', type=int, default=1800, help='seconds to wait for completion after bridge timeout')
    args = parser.parse_args()
    repo = args.repo.resolve()
    if args.phase == 'install-bolido':
        install_bolido(repo)
        return
    if args.work is None or args.deps is None:
        parser.error('--work and --deps are required for this phase')
    work, deps = args.work.resolve(), args.deps.resolve()
    if work == repo or work.is_relative_to(repo / 'app') or work.is_relative_to(repo / 'assets/source-deliveries'):
        parser.error('work must be scratch outside app and the source delivery')
    if args.max_wait < 1:
        parser.error('max-wait must be positive')
    if args.phase == 'install':
        install(repo, work)
    else:
        server = args.server.resolve() if args.server else repo / 'tools/blender/mcp-server.sh'
        asyncio.run(call(repo, work, deps, args.phase, args.max_wait, server))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
