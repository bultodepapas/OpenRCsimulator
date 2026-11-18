"""Authoritative proposed v1 schema source. No network, runtime probes or uploads."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCHEMA_URI = "https://json-schema.org/draft/2020-12/schema"
NOTICE = "2026-11-18"
# Match the inspected shipped catalog; do not accept an arbitrary slug from a player.
VEHICLES = [
    "none", "custom", "unknown", "jensen-das-ugly-stik-60",
    "stik-electric-6s", "gp-extra-300s-60", "p51d-mustang-120",
    "f4u-corsair-250", "sebart-avanti-s-a200-p100rx",
    "turbo-lumber-evolution", "moonrunner-x99", "xcell-60-research",
    "openrc-fpv5-x1", "rc-blimp-5m", "mt8-bisonte", "monster-car-2",
]
GPU_FAMILIES = [
    "nvidia_gtx", "nvidia_rtx", "amd_radeon", "intel_arc",
    "intel_integrated", "apple_silicon", "software", "other", "unknown",
]
HISTOGRAM_UPPER_US = [8333, 16667, 33333, 50000, 100000, 250000, 1000000, 5000000]


def enum(*values):
    return {"type": "string", "enum": list(values)}


def integer(low, high):
    return {"type": "integer", "minimum": low, "maximum": high}


def closed(properties):
    return {
        "type": "object", "additionalProperties": False,
        "required": list(properties), "properties": properties,
    }


def histogram():
    return {"type": "array", "minItems": 8, "maxItems": 8, "items": integer(0, 60000)}


def event(name, properties):
    return closed({"name": {"const": name}, "seq": integer(1, 1000000), **properties})


def schemas():
    context = closed({
        "os_family": enum("windows", "macos", "linux", "other", "unknown"),
        "architecture": enum("x86_64", "arm64", "other", "unknown"),
        "cpu_family": enum("intel_core", "amd_ryzen", "apple_silicon", "other", "unknown"),
        "logical_threads_bucket": enum("le4", "5_8", "9_16", "17_plus", "unknown"),
        "ram_gib_bucket": enum("le4", "5_8", "9_16", "17_32", "33_64", "65_plus", "unknown"),
        "gpu_family": enum(*GPU_FAMILIES),
        "renderer": enum("gl_compatibility", "mobile", "forward_plus", "unknown"),
        "driver": enum("opengl3", "opengl3_es", "opengl3_angle", "metal", "vulkan", "d3d12", "unknown"),
        "resolution_class": enum("below1080p", "1080p", "1440p", "2160p", "above2160p", "other", "unknown"),
        "resolution_basis": enum("viewport_coordinates", "native_drawable_verified", "unknown"),
        "vsync": enum("off", "on", "adaptive", "mailbox", "unknown"),
        "fps_cap_bucket": enum("unlimited", "le30", "31_60", "61_120", "121_plus", "unknown"),
        "graphics_profile": enum("current_default", "custom", "unknown"),
        "input_class": enum("keyboard", "gamepad", "rc", "other", "unknown"),
    })
    perf = event("performance_window", {
        "mode": enum("home", "flight", "workshop", "other"),
        "vehicle_id": enum(*VEHICLES),
        "phase": enum("warmup", "steady"),
        "window_complete": {"type": "boolean"},
        "interval_count": integer(1, 60000),
        "interval_sum_us": integer(1, 60000000),
        "rendered_frames": {"type": ["integer", "null"], "minimum": 0, "maximum": 60000},
        "draw_counter_status": enum("observed", "unavailable"),
        "interval_histogram": histogram(),
        "excluded_gap_count": integer(0, 1000),
        "gpu_status": enum("not_measured", "zero_ambiguous", "positive_freshness_unverified", "invalid_reading"),
        "gpu_ms": {"type": ["number", "null"], "exclusiveMinimum": 0, "maximum": 10000},
    })
    perf["allOf"] = [
        {"if": {"properties": {"draw_counter_status": {"const": "observed"}}},
         "then": {"properties": {"rendered_frames": {"type": "integer"}}},
         "else": {"properties": {"rendered_frames": {"type": "null"}}}},
        {"if": {"properties": {"gpu_status": {"const": "positive_freshness_unverified"}}},
         "then": {"properties": {"gpu_ms": {"type": "number"}}},
         "else": {"properties": {"gpu_ms": {"type": "null"}}}},
    ]
    activity = event("activity_summary", {
        "vehicle_id": enum(*[v for v in VEHICLES if v != "none"]),
        "active_seconds": integer(0, 1800),
        "simulated_seconds": integer(0, 3600),
        "outcome": enum("returned_home", "reset", "interrupted", "slice", "unknown"),
        "complete_observation": {"type": "boolean"},
        "classification": enum("accepted_fixed_wing", "unsupported"),
        "takeoffs": {"type": ["integer", "null"], "minimum": 0, "maximum": 1000},
        "landings": {"type": ["integer", "null"], "minimum": 0, "maximum": 1000},
        "aircraft_crashes": {"type": ["integer", "null"], "minimum": 0, "maximum": 1000},
    })
    activity["allOf"] = [{
        "if": {"properties": {"classification": {"const": "unsupported"}}},
        "then": {"properties": {k: {"type": "null"} for k in ("takeoffs", "landings", "aircraft_crashes")}},
        "else": {"properties": {k: {"type": "integer"} for k in ("takeoffs", "landings", "aircraft_crashes")}},
    }]
    batch = closed({
        "schema_version": {"const": 1},
        "notice_version": {"const": NOTICE},
        "session_id": {"type": "string", "minLength": 32, "maxLength": 32, "pattern": "^[0-9a-f]{32}$"},
        "batch_id": {"type": "string", "minLength": 32, "maxLength": 32, "pattern": "^[0-9a-f]{32}$"},
        "build": closed({
            "release_id": {"type": "string", "maxLength": 32,
                           "pattern": r"^v[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(-(alpha|beta|rc)[0-9]{1,3})?(?![\s\S])"},
            "channel": enum("stable", "preview"),
            "engine_minor": {"const": "4.8"},
        }),
        "context": context,
        "events": {"type": "array", "minItems": 1, "maxItems": 16, "items": {"oneOf": [
            event("session_started", {}), perf, activity,
            event("error_count", {
                "category": enum("renderer_unavailable", "asset_load_failed", "aircraft_validation_failed", "simulation_fault"),
                "count": integer(1, 1000),
            }),
        ]}},
    })
    batch.update({"$schema": SCHEMA_URI, "$id": "urn:openrc:telemetry:batch:1",
                  "title": "OpenRC proposed telemetry batch v1"})
    row = closed({
        "gpu_family": enum(*GPU_FAMILIES),
        "session_observations": integer(20, 1000000000),
        "interval_sum_us": integer(1, 10**16),
        "rendered_frames": integer(0, 10**12),
    })
    report = closed({
        "report_version": {"const": 1},
        "aggregation_scope": {"const": "closed_day"},
        "day": {"type": "string", "minLength": 10, "maxLength": 10, "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"},
        "release_id": batch["properties"]["build"]["properties"]["release_id"],
        "period": {"type": "string", "minLength": 8, "maxLength": 8, "pattern": "^[0-9]{4}-W[0-9]{2}$"},
        "status": enum("ready", "suppressed", "no_data"),
        "basis": {"const": "eligible_daily_session_observations"},
        "rows": {"type": "array", "maxItems": len(GPU_FAMILIES), "items": row},
    })
    report["allOf"] = [
        {"if": {"properties": {"status": {"const": "ready"}}},
         "then": {"properties": {"rows": {"minItems": 1}}},
         "else": {"properties": {"rows": {"maxItems": 0}}}},
    ]
    report.update({"$schema": SCHEMA_URI, "$id": "urn:openrc:telemetry:report:1",
                   "title": "OpenRC proposed fixed GPU aggregate report"})
    error = closed({"code": enum("invalid_request", "conflict", "too_large", "unsupported_media", "rate_limited", "unavailable", "suspended")})
    openapi = {
        "openapi": "3.1.0",
        "info": {"title": "OpenRC proposed telemetry ingress", "version": "0.1.0",
                 "description": "Design only. No live service; anonymous ingestion is untrusted input."},
        "servers": [{"url": "https://telemetry.example.invalid", "description": "Non-routable documentation placeholder"}],
        "paths": {"/v1/batches": {"post": {
            "operationId": "ingestBatch", "security": [],
            "description": "Accept a closed whole batch only after durable idempotent commit. No client credentials, cookies or redirect.",
            "x-max-body-bytes": 32768, "x-max-response-bytes": 4096,
            "requestBody": {"required": True, "content": {"application/json": {"schema": {"$ref": "batch.schema.json"}}}},
            "responses": {
                "202": {"description": "Whole batch durably accepted or identical retry. Empty response body."},
                **{str(code): {"description": description, "content": {"application/json": {"schema": error}}}
                   for code, description in [
                       (400, "Malformed request; drop"), (409, "Conflicting retry/event identity; drop"),
                       (413, "Body too large; drop"), (415, "Unsupported media/compression; drop"),
                       (422, "Invalid schema, semantics or unapproved build; drop"),
                       (401, "Misconfigured endpoint; suspend"), (403, "Endpoint refuses collection; suspend"),
                       (410, "Collection disabled; suspend"), (503, "No durable acceptance; bounded retry"),
                   ]},
                "429": {"description": "No acceptance; bounded retry subject to consent and queue expiry",
                        "headers": {"Retry-After": {"description": "Delay seconds or HTTP date; never shorten to fit queue TTL", "schema": {"type": "string"}}},
                        "content": {"application/json": {"schema": error}}},
            },
        }}},
    }
    return {"batch.schema.json": batch, "report.schema.json": report, "openapi.json": openapi}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    mismatch = []
    for name, schema in schemas().items():
        path = ROOT / "contracts" / name
        content = json.dumps(schema, indent=2, ensure_ascii=False) + "\n"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                mismatch.append(name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    if mismatch:
        raise SystemExit("Generated contracts differ: " + ", ".join(mismatch))
    print("Contracts match source" if args.check else "Wrote 3 contracts")


if __name__ == "__main__":
    main()
