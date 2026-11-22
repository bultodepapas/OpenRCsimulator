"""Local synthetic receiver capacity and configuration checks; no remote calls."""
import argparse
import json
from pathlib import Path
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.repo / 'services/telemetry'))
    from starlette.testclient import TestClient
    from openrc_telemetry.config import Config
    from openrc_telemetry.ingress import create_app
    from openrc_telemetry.limits import RateLimiter
    from tests.support import FakeClock, batch, encode, make_config, unix

    headers = {'Content-Type': 'application/json'}
    clock = FakeClock(unix('2026-11-22T12:00:00Z'))
    original_receipt = clock.now
    with tempfile.TemporaryDirectory(prefix='telemetry-boundaries-') as tmp:
        config = make_config(tmp)
        app = create_app(config, clock=clock)
        body = encode(batch(1))
        with TestClient(app) as client:
            first = client.post('/v1/batches', content=body, headers=headers).status_code
            with app.state.raw.connection() as conn:
                used = app.state.raw._size(conn)
        app.state.raw.close()
        app.state.aggregates.close()
        clock.now += 120
        # Reopen the actual database at a configured quota equal to its existing
        # live-page usage. This is the ordinary full-budget state, not disk-full.
        full = create_app(make_config(tmp, max_raw_bytes=used), clock=clock)
        with TestClient(full) as client:
            identical_full = client.post('/v1/batches', content=body, headers=headers).status_code
            new_full = client.post('/v1/batches', content=encode(batch(2)), headers=headers).status_code
            remaining = full.state.raw.count()
        full.state.raw.close()
        full.state.aggregates.close()
        clock.now += 120
        normal = create_app(make_config(tmp, max_raw_bytes=used + 1024 * 1024), clock=clock)
        with TestClient(normal) as client:
            identical_room = client.post('/v1/batches', content=body, headers=headers).status_code
            receipt_unchanged = normal.state.raw.oldest_receipt() == original_receipt
        normal.state.raw.close()
        normal.state.aggregates.close()

    settings = [
        ('OPENRC_TELEMETRY_CLIENT_REFILL_PER_S', 'inf', 'client_refill_per_s'),
        ('OPENRC_TELEMETRY_GLOBAL_REFILL_PER_S', 'inf', 'global_refill_per_s'),
        ('OPENRC_TELEMETRY_CLIENT_BURST', '0.5', 'client_burst'),
        ('OPENRC_TELEMETRY_MAX_CLIENTS', '-1', 'max_clients'),
        ('OPENRC_TELEMETRY_MAX_RAW_BYTES', '-1', 'max_raw_bytes'),
    ]
    accepted = []
    for name, value, attribute in settings:
        config = Config.from_env({name: value})
        accepted.append({'setting': name, 'input': value, 'accepted_value': str(getattr(config, attribute))})
    def allowed(rate):
        limiter = RateLimiter(1, rate, 100, 0, monotonic=lambda: 0.0)
        return sum(limiter.check('192.0.2.1') == 0 for _ in range(10))
    finite = allowed(0.0)
    infinite = allowed(float('inf'))
    fractional = RateLimiter(0.5, 1, 100, 0, monotonic=lambda: 0.0)
    negative = RateLimiter(20, 1, 100, 0, max_clients=-1, monotonic=lambda: 0.0)
    result = {
        'full_quota_retry': {'first_http': first, 'used_bytes': used,
                            'identical_retry_full_http': identical_full, 'new_batch_full_http': new_full,
                            'stored_rows': remaining, 'identical_retry_with_room_http': identical_room,
                            'seconds_elapsed_before_successful_retry': clock.now - original_receipt,
                            'receipt_unchanged': receipt_unchanged},
        'accepted_configuration': accepted,
        'rate_behavior': {'zero_refill_allowed_of_10': finite, 'infinite_refill_allowed_of_10': infinite,
                          'fractional_burst_first_wait': fractional.check('192.0.2.1'),
                          'negative_max_clients_first_wait': negative.check('192.0.2.1')},
    }
    print(json.dumps(result, indent=2))
    assert (first, identical_full, new_full, remaining, identical_room) == (202, 503, 503, 1, 202)
    assert clock.now > original_receipt and receipt_unchanged and finite == 1 and infinite == 10
    assert result['rate_behavior']['fractional_burst_first_wait'] > 0
    assert result['rate_behavior']['negative_max_clients_first_wait'] > 0


if __name__ == '__main__':
    main()
