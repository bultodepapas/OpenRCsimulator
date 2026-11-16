"""Reproduce MP-00-R2 planning arithmetic; no sockets, SDKs or benchmarks.

Run from the repository root:
    python3 research/multiplayer/capacity_model.py > research/multiplayer/capacity-results.json

Provider values are a dated input, not live account metering. See
docs/research/multiplayer-2026-11-15/round-2.md for sources and exclusions.
"""
from __future__ import annotations

import json
import struct

DAY_SECONDS = 86_400
FREE_REQUESTS = 100_000
FREE_SQL_WRITES = 100_000
ALLOWANCE_PERCENT = 70
POSE_FORMAT = "<2sBBHHIIIIIIqQ3d4f3f3f4hfHH"


def directory(hosts: int, browsers: int, list_period: int = 30) -> dict:
    """One heartbeat row and one quota-counter row per accepted request.

    Every request invokes one Worker and one DO. These are separate quotas.
    No extra index, cleanup, retry, create/delete or other-account work is counted.
    Requests are steady-state throughout one complete day; this is not a CCU cap.
    """
    heartbeats = hosts * DAY_SECONDS // 30
    lists = browsers * DAY_SECONDS // list_period
    requests = heartbeats + lists
    writes = heartbeats + requests
    request_allowance = FREE_REQUESTS * ALLOWANCE_PERCENT // 100
    write_allowance = FREE_SQL_WRITES * ALLOWANCE_PERCENT // 100
    return {
        "hosts": hosts,
        "continuously_open_browsers": browsers,
        "heartbeat_seconds": 30,
        "list_seconds": list_period,
        "worker_requests_per_day": requests,
        "durable_object_requests_per_day": requests,
        "heartbeat_row_writes_per_day": heartbeats,
        "quota_counter_row_writes_per_day": requests,
        "modeled_minimum_sql_writes_per_day": writes,
        "listing_rows_read_per_day": hosts * lists,
        "request_headroom_to_operational_allowance": request_allowance - requests,
        "write_headroom_to_operational_allowance": write_allowance - writes,
        "within_both_modeled_allowances": requests <= request_allowance and writes <= write_allowance,
    }


def build_report() -> dict:
    size = struct.calcsize(POSE_FORMAT)
    return {
        "evidence_type": "analytical_planning_model_not_runtime_measurement",
        "research_date": "2026-11-16",
        "production_baseline": "cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b",
        "inputs": {
            "worker_free_daily_requests": FREE_REQUESTS,
            "do_free_daily_requests": FREE_REQUESTS,
            "do_free_daily_sql_writes": FREE_SQL_WRITES,
            "operational_allowance_percent": ALLOWANCE_PERCENT,
            "pose_hz": 20,
            "pose_struct_format": POSE_FORMAT,
            "pose_application_bytes": size,
        },
        "directory_scenarios": [
            directory(2, 2),
            directory(10, 10),
            directory(5, 10),
            directory(5, 20),
            directory(10, 10, 60),
            directory(5, 10, 60),
        ],
        "pose_payload_bytes_per_second": [
            {
                "total_pilots": n,
                "host_in": (n - 1) * size * 20,
                "host_out": (n - 1) ** 2 * size * 20,
                "each_guest_in": (n - 1) * size * 20,
                "each_guest_out": size * 20,
                "excludes": "Godot command byte, ENet/UDP/IP, acknowledgments and all control traffic",
            }
            for n in (2, 4, 8)
        ],
        "two_hop_interpolation_bound_ms": {
            "assumption": "symmetric 100 ms RTT per guest-host leg; up to +20 ms one-way delay per traversed leg; no loss",
            "source_period": 50,
            "guest_host_guest_base_propagation": 100,
            "worst_assumed_propagation": 140,
            "delay_to_cover_propagation_and_one_sample_period": 190,
            "original_render_delay": 100,
            "proposed_render_delay": 200,
            "proposed_loss_free_margin": 10,
            "excludes": "clock uncertainty, host processing, stalls, loss, queueing and runtime scheduling",
        },
        "nonhibernating_object_duration": {
            "assumption": "one object billed continuously for 24 hours at 0.128 GB",
            "gb_seconds_per_day": round(0.128 * DAY_SECONDS, 3),
            "free_daily_gb_seconds": 13_000,
            "operational_daily_gb_seconds": 13_000 * ALLOWANCE_PERCENT // 100,
            "within_operational_allowance": 0.128 * DAY_SECONDS <= 13_000 * ALLOWANCE_PERCENT / 100,
        },
    }


if __name__ == "__main__":
    print(json.dumps(build_report(), indent=2, sort_keys=True))
