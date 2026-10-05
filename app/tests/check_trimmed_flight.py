"""App-level check (run by test.sh): the real app, started headless with --trace, glides on trim.

Catches wiring bugs that unit tests cannot see (e.g. trim not applied on the synchronous --trace path):
the trimmed glide must hold its speed and pitch, and sink at a steady rate.
"""
import csv
import sys

rows = [r for r in csv.reader(open(sys.argv[1])) if r and not r[0].startswith('#')]
head, data = rows[0], [dict(zip(rows[0], r)) for r in rows[1:]]
first, last = data[0], data[-1]
t = float(last['t_s'])
sink = (float(first['alt_m']) - float(last['alt_m'])) / t
problems = []
if abs(float(last['speed_mps']) - float(first['speed_mps'])) > 0.01:
    problems.append(f"speed drifts {float(first['speed_mps']):.3f} → {float(last['speed_mps']):.3f} m/s")
if abs(float(last['pitch_deg']) - float(first['pitch_deg'])) > 0.05:
    problems.append(f"pitch drifts {float(first['pitch_deg']):.3f}° → {float(last['pitch_deg']):.3f}°")
if not 1.0 < sink < 2.5:
    problems.append(f"sink rate {sink:.3f} m/s is not a trimmed glide (expected ~1.76)")
if abs(float(first['cmd_pitch'])) < 1e-6:
    problems.append("no elevator trim applied (cmd_pitch = 0)")
print(f"trimmed glide: sink {sink:.4f} m/s, speed {float(last['speed_mps']):.4f} m/s, trim {float(first['cmd_pitch']):+.4f}")
if problems:
    print("FAIL " + "; ".join(problems))
    sys.exit(1)
