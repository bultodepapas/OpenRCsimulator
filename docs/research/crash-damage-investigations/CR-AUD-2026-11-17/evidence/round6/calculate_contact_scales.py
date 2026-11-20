#!/usr/bin/env python3
"""Arithmetic illustrations only; not measured flight or material limits."""
import json
import math

speed = 300.0 / 3.6
dt = 1.0 / 240.0
rows = []
for angle in [0.0, 0.1, 0.5, 1.0, 2.0, 5.0, 90.0]:
    vn = speed * math.sin(math.radians(angle))
    rows.append({"angle_to_static_plane_deg": angle,
                 "normal_speed_mps": vn,
                 "normal_incident_energy_J_per_kg_effective_mass": 0.5 * vn * vn,
                 "normal_travel_per_tick_m": vn * dt,
                 "time_to_close_1mm_ms": 1.0 / vn if vn > 0 else None})
print(json.dumps({"basis": "Constant translation, static plane, no body rotation; effective-mass energy is not aircraft-mass severity or strength.",
                  "speed_mps": speed, "tick_s": dt, "reference_distance_per_tick_m": speed * dt,
                  "angles": rows,
                  "illustrative_prop": {"radius_m": 0.15,
                    "basis": "Rotational tip-speed magnitude alone; not a stock prop specification or a nick threshold.",
                    "tip_speed_mps_by_rpm": {str(rpm): 2 * math.pi * rpm * 0.15 / 60 for rpm in [300, 5000]}}}, indent=2))
