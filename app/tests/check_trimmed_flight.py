"""App-level check (run by test.sh): the real app, started headless with --trace, flies trimmed and level.

Catches wiring bugs unit tests cannot see (trims or engine not applied on the synchronous --trace path):
speed, pitch and altitude hold; the engine runs at the trimmed rpm; trims are applied.
"""
import csv
import sys

rows = [r for r in csv.reader(open(sys.argv[1])) if r and not r[0].startswith('#')]
data = [dict(zip(rows[0], r)) for r in rows[1:]]
first, last = data[0], data[-1]
f = lambda row, key: float(row[key])
problems = []
if abs(f(last, 'speed_mps') - f(first, 'speed_mps')) > 0.01:
    problems.append(f"speed drifts {f(first, 'speed_mps'):.3f} → {f(last, 'speed_mps'):.3f} m/s")
if abs(f(last, 'pitch_deg') - f(first, 'pitch_deg')) > 0.05:
    problems.append(f"pitch drifts {f(first, 'pitch_deg'):.3f}° → {f(last, 'pitch_deg'):.3f}°")
if abs(f(last, 'alt_m') - f(first, 'alt_m')) > 0.05:
    problems.append(f"altitude drifts {f(first, 'alt_m'):.3f} → {f(last, 'alt_m'):.3f} m")
if not 0.05 < f(first, 'cmd_throttle') < 0.95 or f(first, 'engine_rpm') < 3000:
    problems.append(f"engine not at a trimmed setting (throttle {f(first, 'cmd_throttle'):.3f}, {f(first, 'engine_rpm'):.0f} rpm)")
if abs(f(last, 'engine_rpm') - f(first, 'engine_rpm')) > 1.0:
    problems.append(f"rpm drifts {f(first, 'engine_rpm'):.0f} → {f(last, 'engine_rpm'):.0f}")
if abs(f(first, 'cmd_pitch')) < 1e-6:
    problems.append("no elevator trim applied (cmd_pitch = 0)")
print(f"trimmed level flight: alt {f(first, 'alt_m'):.3f} → {f(last, 'alt_m'):.3f} m, speed {f(last, 'speed_mps'):.4f} m/s, "
      f"throttle {f(first, 'cmd_throttle'):.3f}, {f(first, 'engine_rpm'):.0f} rpm, trims ail {f(first, 'cmd_roll'):+.4f} elev {f(first, 'cmd_pitch'):+.4f}")
if problems:
    print("FAIL " + "; ".join(problems))
    sys.exit(1)
