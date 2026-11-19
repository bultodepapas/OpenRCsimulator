#!/usr/bin/env python3
"""Closed-loop benchmark pilot for the OpenRC debug bridge (DT-MAC-03b graphics ladder).

Flies a wide clockwise orbit over Club Field that passes over the clubhouse, using only the bridge's
ordinary `state` and `sticks` commands, then optionally dives at a target point (the pilot station) to
end the run in a crash. The stick is a rate command, so a fixed deflection rolls the aircraft over: the
pilot closes the loop on bank, course and height. Python 3.9 compatible (macOS system Python).

Bridge NED frame: north = -godot_z, east = godot_x. The pilot station is the origin; the clubhouse
(pavilion) is at north -22 m, east 0 m (app/data/scenery/default.json).
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
import threading
import time
from pathlib import Path

CLUBHOUSE_NE = (-22.0, 0.0)


def import_debugctl(src: str | None = None):
    root = Path(src) if src else Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(root / "tools" / "debug"))
    sys.path.insert(0, str(root))
    import debugctl  # noqa: E402
    return debugctl


def wrap(deg: float) -> float:
    return (deg + 180.0) % 360.0 - 180.0


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


class CirclePilot:
    def __init__(self, debugctl, port: int, center_n: float = 68.0, center_e: float = 0.0, radius: float = 90.0,
                 altitude: float = 40.0, throttle: float = 0.6, rate_hz: float = 12.0, log_path: str | None = None):
        self.debugctl = debugctl
        self.port = port
        self.cn, self.ce, self.radius, self.altitude = center_n, center_e, radius, altitude
        self.throttle = throttle
        self.period = 1.0 / rate_hz
        self.log_path = log_path
        self.stop_event = threading.Event()
        self.samples = 0
        self.failure = ""
        self.ended = {}  # flight record at the first crash/pause seen in dive mode
        self.last = {}
        self.track = []  # (t, n, e, h)
        self.target = None  # (north, east, height) once the final dive starts

    def request(self, cmd: str, args: dict | None = None) -> dict:
        # 60 s: a first-use shader compile (OpenGL, D3D12) can stall the main thread for more than 10 s.
        reply = self.debugctl.request(cmd, args or {}, timeout=60.0, to_port=self.port)
        if not reply.get("ok"):
            raise RuntimeError("%s: %s" % (cmd, reply.get("error")))
        return reply.get("result") or {}

    def angle_on_circle(self) -> float | None:
        if not self.last:
            return None
        return math.degrees(math.atan2(self.last["e"] - self.ce, self.last["n"] - self.cn)) % 360.0

    def step(self) -> dict | None:
        state = self.request("state")
        flight = state.get("flight", state)
        if flight.get("crashed") or flight.get("paused"):
            if self.target is not None:
                self.ended = dict(flight)
                return None
            raise RuntimeError("flight crashed=%s paused=%s reason=%s" % (
                flight.get("crashed"), flight.get("paused"), flight.get("pause_reason")))
        n, e, d = flight["position_ned_m"]
        h = float(flight.get("height_m", -d))
        att = flight["attitude_deg"]
        roll, pitch, heading = float(att["roll"]), float(att["pitch"]), float(att["heading"])
        p, q, _r = flight.get("rates_body_degps", [0.0, 0.0, 0.0])
        speed = float(flight.get("speed_mps", 20.0))
        dn, de = n - self.cn, e - self.ce
        dist = math.hypot(dn, de)
        if self.target is None:
            # Vector-field orbit guidance, clockwise (right turns), with bank feed-forward.
            gamma = math.degrees(math.atan2(de, dn))
            course_cmd = gamma + 90.0 + math.degrees(math.atan(1.6 * (dist - self.radius) / self.radius))
            course_err = wrap(course_cmd - heading)
            bank_ff = math.degrees(math.atan(speed * speed / (9.81 * self.radius)))
            bank_cmd = clamp(bank_ff + 1.1 * course_err, -38.0, 38.0)
            alt_err = self.altitude - h
            pitch_cmd = clamp(2.0 + 0.45 * alt_err, -8.0, 12.0)
            throttle = clamp(self.throttle + 0.02 * alt_err, 0.35, 0.85)
            pitch_limits = (-0.35, 0.45)
        else:
            # Final dive: point the flight path at the target.
            tn, te, th = self.target
            to_n, to_e = tn - n, te - e
            ground = max(math.hypot(to_n, to_e), 1.0)
            course_err = wrap(math.degrees(math.atan2(to_e, to_n)) - heading)
            bank_cmd = clamp(1.6 * course_err, -50.0, 50.0) if ground > 12.0 else 0.0
            alt_err = th - h
            path_cmd = math.degrees(math.atan2(th - h, ground))
            pitch_cmd = clamp(path_cmd + 3.0, -45.0, 10.0)
            throttle = 0.5
            pitch_limits = (-0.6, 0.45)
        roll_stick = clamp(0.010 * (bank_cmd - roll) - 0.0020 * p, -0.35, 0.35)
        bank_comp = 0.0012 * min(abs(roll), 45.0) ** 1.5 / 10.0
        pitch_stick = clamp(0.030 * (pitch_cmd - pitch) - 0.0030 * q + bank_comp, *pitch_limits)
        self.request("sticks", {"roll": round(roll_stick, 4), "pitch": round(pitch_stick, 4), "yaw": 0.0,
                                "throttle": round(throttle, 4), "for_s": 0.6})
        self.last = dict(t=float(flight.get("time_s", 0.0)), n=n, e=e, h=h, roll=roll, pitch=pitch,
                         heading=heading, speed=speed, dist=dist, radial_err=dist - self.radius, alt_err=alt_err,
                         bank_cmd=bank_cmd, roll_stick=roll_stick, pitch_stick=pitch_stick, throttle=throttle,
                         mode="orbit" if self.target is None else "dive", fps=state.get("fps"))
        return self.last

    def run(self, duration_s: float) -> None:
        writer = None
        handle = open(self.log_path, "w", newline="") if self.log_path else None
        try:
            deadline = time.monotonic() + duration_s
            while not self.stop_event.is_set() and time.monotonic() < deadline:
                began = time.monotonic()
                try:
                    row = self.step()
                except Exception as exc:  # crash, pause or bridge loss ends the orbit
                    self.failure = str(exc)
                    break
                if row is None:
                    break
                self.samples += 1
                if handle is not None:
                    if writer is None:
                        writer = csv.DictWriter(handle, fieldnames=list(row.keys()))
                        writer.writeheader()
                    writer.writerow({k: (round(v, 3) if isinstance(v, float) else v) for k, v in row.items()})
                self.track.append((row["t"], row["n"], row["e"], row["h"]))
                self.stop_event.wait(max(0.0, self.period - (time.monotonic() - began)))
        finally:
            if handle is not None:
                handle.close()

    def stats_since(self, t0: float) -> dict:
        rows = [r for r in self.track if r[0] >= t0]
        if not rows:
            return {}
        radial = [abs(math.hypot(n - self.cn, e - self.ce) - self.radius) for _t, n, e, _h in rows]
        alt = [abs(h - self.altitude) for _t, _n, _e, h in rows]
        club = [math.hypot(n - CLUBHOUSE_NE[0], e - CLUBHOUSE_NE[1]) for _t, n, e, _h in rows]
        return dict(samples=len(rows), radial_err_max_m=round(max(radial), 1),
                    radial_err_mean_m=round(sum(radial) / len(radial), 1),
                    alt_err_max_m=round(max(alt), 1), alt_err_mean_m=round(sum(alt) / len(alt), 1),
                    closest_clubhouse_horizontal_m=round(min(club), 1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--src", help="repository/snapshot root holding tools/debug (default: this checkout)")
    parser.add_argument("--duration", type=float, default=90.0)
    parser.add_argument("--rate-hz", type=float, default=12.0)
    parser.add_argument("--log")
    args = parser.parse_args()
    pilot = CirclePilot(import_debugctl(args.src), args.port, rate_hz=args.rate_hz, log_path=args.log)
    pilot.run(args.duration)
    print(json.dumps({"samples": pilot.samples, "failure": pilot.failure, "last": pilot.last,
                      "stats_after_30s": pilot.stats_since(30.0)}))
    return 1 if pilot.failure else 0


if __name__ == "__main__":
    sys.exit(main())
