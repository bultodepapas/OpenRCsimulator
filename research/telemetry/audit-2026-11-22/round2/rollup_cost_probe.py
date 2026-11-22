"""Bounded synthetic rollup measurements; no production capacity/FPS claim.

Each isolated worker measures an unchanged production run_rollup. Input setup is
outside the timed region. Timings use no allocation tracer; one separate run
records Python allocation peak, digest calls and SQL reads without treating its
instrumented duration as a performance result.
"""
import argparse
import gc
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time
import tracemalloc
from unittest.mock import patch


def worker(repo, count):
    sys.path.insert(0, str(repo / 'services/telemetry'))
    from openrc_telemetry.contract import load_contracts
    from openrc_telemetry.storage import RawStore, AggStore
    from openrc_telemetry import rollup
    from tests.support import batch, encode, make_config, perf_event, unix
    receipt = unix('2026-11-20T12:00:00Z')
    as_of = unix('2026-11-21T02:00:00Z')
    with tempfile.TemporaryDirectory(prefix='rollup-cost-') as tmp:
        cfg = make_config(tmp)
        contracts = load_contracts(cfg.schema_dir)
        raw, agg = RawStore(cfg.raw_path), AggStore(cfg.aggregates_path)
        body_bytes = 0
        for index in range(1, count + 1):
            payload = batch(index, events=[perf_event(i) for i in range(1, 17)])
            body = encode(payload)
            contracts.validate_body(body)
            body_bytes += len(body)
            outcome = raw.ingest(payload['batch_id'], hashlib.sha256(body).hexdigest(),
                                 payload['session_id'], list(range(1, 17)), body, receipt)
            assert outcome == 'accepted'
        durations = []
        for _ in range(3):
            gc.collect()
            started = time.perf_counter()
            rollup.run_rollup(contracts, raw, agg, '2026-11-20', as_of, cfg.releases)
            durations.append(time.perf_counter() - started)
        original_encode = rollup.encode
        calls = 0
        def counted_encode(value):
            nonlocal calls
            calls += 1
            return original_encode(value)
        queries = []
        with raw.connection() as conn:
            conn.set_trace_callback(queries.append)
        gc.collect()
        tracemalloc.start()
        with patch.object(rollup, 'encode', counted_encode):
            rollup.run_rollup(contracts, raw, agg, '2026-11-20', as_of, cfg.releases)
        _current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        result = {'batches': count, 'events_per_batch': 16, 'events': 16 * count,
                  'stored_body_bytes': body_bytes, 'wall_seconds_three_runs': durations,
                  'wall_median_seconds': statistics.median(durations),
                  'python_allocation_peak_bytes': peak, 'event_digest_encodes': calls,
                  'raw_body_selects': sum('SELECT receipt_day, body FROM batches' in q for q in queries),
                  'day_statuses': agg.day_statuses('2026-11-20'),
                  'rollup_committed': '2026-11-20' in agg.rollup_commits()}
        raw.close()
        agg.close()
        assert calls == 3 * count * 16 and result['rollup_committed']
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--worker', type=int)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    if args.worker:
        print(json.dumps(worker(args.repo, args.worker)))
        return
    if not args.out:
        parser.error('--out is required for the measurement series')
    outcomes = []
    for count in (40, 160, 480):
        run = subprocess.run([sys.executable, __file__, '--repo', str(args.repo), '--worker', str(count)],
                             text=True, capture_output=True, timeout=180, check=True)
        value = json.loads(run.stdout)
        outcomes.append(value)
        print(json.dumps(value), flush=True)
        args.out.write_text(json.dumps({'python': sys.version.split()[0], 'runs': outcomes,
            'limits': 'Synthetic local CPU/SQLite workload; traced allocations are not process RSS. No fix or production capacity is measured.'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
