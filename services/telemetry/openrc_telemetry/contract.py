"""Strict batch/report validation. Mirrors research/telemetry/reference.py semantics.

Errors carry a fixed category only; a rejected body or jsonschema message is never echoed.
"""
from __future__ import annotations

from datetime import date
from functools import lru_cache
from hashlib import sha256
import json
import math
from pathlib import Path

from jsonschema import Draft202012Validator

MAX_BODY = 32 * 1024
HISTOGRAM_UPPER_US = (8333, 16667, 33333, 50000, 100000, 250000, 1000000, 5000000)


class ContractError(ValueError):
    """Safe category only: never echo a rejected body or field value."""


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ContractError("duplicate_key")
        result[key] = value
    return result


def _constant(_value):
    # NaN and Infinity are not JSON numeric literals.
    raise ContractError("invalid_json")


def bounded_tree(value, depth=0):
    if depth > 16:
        raise ContractError("depth")
    if isinstance(value, float) and not math.isfinite(value):
        raise ContractError("nonfinite")
    if isinstance(value, dict):
        for item in value.values():
            bounded_tree(item, depth + 1)
    elif isinstance(value, list):
        for item in value:
            bounded_tree(item, depth + 1)


def encode(payload):
    try:
        return json.dumps(payload, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
    except (ValueError, TypeError, RecursionError):
        raise ContractError("not_json") from None


def http_status(error):
    """Same mapping as reference.IngressModel.ingest for validation errors."""
    category = str(error)
    if category == "body_too_large":
        return 413
    if category in {"bytes_required", "invalid_json", "duplicate_key", "depth"}:
        return 400
    return 422


class Contracts:
    """Validators built from the canonical generated JSON schemas."""

    def __init__(self, schema_dir):
        self.schema_dir = Path(schema_dir)
        self.batch_validator = self._validator("batch.schema.json")
        self.report_validator = self._validator("report.schema.json")
        # Vehicle ids an activity_summary may carry (the canonical enum), for checks at the publication boundary.
        events = self.batch_validator.schema["properties"]["events"]["items"]["oneOf"]
        activity = next(e for e in events if e["properties"]["name"].get("const") == "activity_summary")
        self.activity_vehicles = frozenset(activity["properties"]["vehicle_id"]["enum"])

    def _validator(self, filename):
        schema = json.loads((self.schema_dir / filename).read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        return Draft202012Validator(schema)

    def validate_body(self, body):
        if not isinstance(body, bytes):
            raise ContractError("bytes_required")
        if len(body) > MAX_BODY:
            raise ContractError("body_too_large")
        try:
            payload = json.loads(body.decode("utf-8"), object_pairs_hook=_object, parse_constant=_constant)
            bounded_tree(payload)
        except ContractError:
            raise
        except (ValueError, UnicodeError, RecursionError):
            raise ContractError("invalid_json") from None
        if not self.batch_validator.is_valid(payload):
            raise ContractError("schema")
        seqs, previous = set(), 0
        for event in payload["events"]:
            if event["seq"] in seqs:
                raise ContractError("duplicate_sequence")
            if event["seq"] <= previous:
                raise ContractError("sequence_order")
            seqs.add(event["seq"])
            previous = event["seq"]
            if event["name"] == "performance_window":
                if event["window_complete"] and event["interval_sum_us"] < 30_000_000:
                    raise ContractError("incomplete_window")
                hist = event["interval_histogram"]
                if sum(hist) != event["interval_count"]:
                    raise ContractError("histogram_count")
                lower, minimum, maximum = 1, 0, 0
                for count, upper in zip(hist, HISTOGRAM_UPPER_US):
                    minimum += count * lower
                    maximum += count * upper
                    lower = upper + 1
                if not minimum <= event["interval_sum_us"] <= maximum:
                    raise ContractError("histogram_duration")
        return payload

    def validate_ingest(self, body, approved_releases):
        """validate_body plus the deployment release allowlist (an empty set rejects all)."""
        payload = self.validate_body(body)
        if payload["build"]["release_id"] not in approved_releases:
            raise ContractError("unapproved_release")
        return payload

    def validate_report(self, report):
        """Daily GPU report check, identical to reference.validate_report."""
        bounded_tree(report)
        if not self.report_validator.is_valid(report):
            raise ContractError("report_schema")
        try:
            year, week = report["period"].split("-W")
            date.fromisocalendar(int(year), int(week), 1)
            report_day = date.fromisoformat(report["day"])
            iso = report_day.isocalendar()
            if report["period"] != f"{iso.year:04d}-W{iso.week:02d}":
                raise ValueError
        except (ValueError, TypeError, OverflowError):
            raise ContractError("report_period") from None
        families = [row["gpu_family"] for row in report["rows"]]
        if len(families) != len(set(families)):
            raise ContractError("duplicate_report_cell")
        for row in report["rows"]:
            sessions = row["session_observations"]
            if not sessions * 30_000_000 <= row["interval_sum_us"] <= sessions * 120 * 60_000_000:
                raise ContractError("report_exposure")
            if row["rendered_frames"] > sessions * 120 * 60000:
                raise ContractError("report_frames")
            # The summed interval histogram must bracket the observed time by its bucket bounds, like each window.
            histogram = row["interval_histogram"]
            lower, shortest, longest = 1, 0, 0
            for count, upper in zip(histogram, HISTOGRAM_UPPER_US):
                shortest += count * lower
                longest += count * upper
                lower = upper + 1
            if not shortest <= row["interval_sum_us"] <= longest or sum(histogram) > sessions * 120 * 60000:
                raise ContractError("report_histogram")
            if row["excluded_gap_count"] > sessions * 120 * 1000:
                raise ContractError("report_gaps")


@lru_cache(maxsize=4)
def _cached(schema_dir):
    return Contracts(schema_dir)


def load_contracts(schema_dir):
    return _cached(str(Path(schema_dir).resolve()))


def body_digest(body):
    return sha256(body).hexdigest()
