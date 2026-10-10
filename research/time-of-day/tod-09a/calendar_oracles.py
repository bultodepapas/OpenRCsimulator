#!/usr/bin/env python3
"""Independent Gregorian clock fixtures using Python datetime, never host time or timezone."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUT = ROOT / 'app/tests/fixtures/time_of_day_clock.json'


def fixtures():
    cases = []
    def add(label, date, seconds, ticks, hz=240, offset=0, anchor=0, rate=1):
        instant = datetime.fromisoformat(date) + timedelta(seconds=seconds)
        whole, remainder = divmod(ticks * rate, hz)
        expected = instant + timedelta(seconds=whole)
        utc = expected.replace(tzinfo=timezone(timedelta(minutes=offset)))
        cases.append(dict(id=label, date=date, local_seconds=seconds, utc_offset_minutes=offset,
                          anchor_tick=anchor, tick=anchor + ticks, ticks_per_second=hz, rate=rate,
                          expected_date=expected.strftime('%Y-%m-%d'),
                          expected_local_seconds=expected.hour * 3600 + expected.minute * 60 + expected.second,
                          expected_subsecond_ticks=remainder, expected_utc_unix_seconds=int(utc.timestamp())))
    for year in range(2000, 2101):
        add(f'february-{year}', f'{year}-02-28', 86399, 241)
    for year in [2000, 2003, 2023, 2024, 2099]:
        add(f'year-{year}', f'{year}-12-31', 86399, 480)
    for offset in [-720, -300, 0, 330, 840]:
        add(f'offset-{offset}', '2026-12-31', 86399, 959, offset=offset)
    for fraction in [0, 1, 119, 120, 239, 240]:
        add(f'fraction-{fraction}', '2024-02-28', 86399, 480 + fraction, anchor=9007199254700000)
    rng = random.Random(90901)
    start = datetime(2000, 1, 1)
    for index in range(64):
        date = start + timedelta(days=rng.randrange(36000))
        add(f'random-{index}', date.strftime('%Y-%m-%d'), rng.randrange(86400),
            rng.randrange(240 * 86400 * 31), offset=rng.randrange(-720, 841), anchor=rng.randrange(100000))
    add('minimum-local-date-utc-previous-year', '2000-01-01', 0, 0, offset=840)
    add('maximum-local-date-utc-next-year', '2100-12-31', 86399, 239, offset=-720)
    add('fixed-endpoint', '2100-12-31', 86399, 9007199254740991, rate=0)
    return dict(format='openrc-solar-clock-oracles v1', source='Python standard-library datetime Gregorian arithmetic; seed 90901', cases=cases)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    encoded = json.dumps(fixtures(), indent=2, sort_keys=True) + '\n'
    if args.check:
        if args.out.read_text() != encoded:
            raise SystemExit('calendar fixtures differ from generator')
    else:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(encoded)
    print(f'{len(fixtures()["cases"])} independent calendar cases verified')


if __name__ == '__main__':
    main()
