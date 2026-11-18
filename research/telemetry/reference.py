"""Offline executable contract model, NOT a production sender or collector.

No sockets, hardware probes, player history, disk queue, or GitHub writes.
The transport methods model completion races; they do not qualify Godot HTTP.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
import json
import math
import re
from pathlib import Path
import secrets

from jsonschema import Draft202012Validator

from generate_contracts import GPU_FAMILIES, HISTOGRAM_UPPER_US, NOTICE, VEHICLES

ROOT = Path(__file__).resolve().parent
MAX_BODY = 32 * 1024
QUEUE_BYTES = 256 * 1024
QUEUE_BATCHES = 32
QUEUE_TTL = 600
RAW_TTL = 48 * 3600
MAX_ATTEMPTS_HOUR = 90
MAX_BYTES_HOUR = 256 * 1024


class ContractError(ValueError):
    """Safe category only: never echo a rejected body or field value."""


def _validator(filename):
    schema = json.loads((ROOT / "contracts" / filename).read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


BATCH_VALIDATOR = _validator("batch.schema.json")
REPORT_VALIDATOR = _validator("report.schema.json")


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


def _bounded_tree(value, depth=0):
    if depth > 16:
        raise ContractError("depth")
    if isinstance(value, float) and not math.isfinite(value):
        raise ContractError("nonfinite")
    if isinstance(value, dict):
        for item in value.values():
            _bounded_tree(item, depth + 1)
    elif isinstance(value, list):
        for item in value:
            _bounded_tree(item, depth + 1)


def encode(payload):
    try:
        return json.dumps(payload, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
    except (ValueError, TypeError, RecursionError):
        raise ContractError("not_json") from None


def validate_body(body):
    if not isinstance(body, bytes):
        raise ContractError("bytes_required")
    if len(body) > MAX_BODY:
        raise ContractError("body_too_large")
    try:
        payload = json.loads(body.decode("utf-8"), object_pairs_hook=_object, parse_constant=_constant)
        _bounded_tree(payload)
    except ContractError:
        raise
    except (ValueError, UnicodeError, RecursionError):
        raise ContractError("invalid_json") from None
    if not BATCH_VALIDATOR.is_valid(payload):
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


def hardware_family(raw, kind):
    """Transient source string -> fixed category; never return the source string."""
    value = raw.casefold() if isinstance(raw, str) else ""
    if not value:
        return "unknown"
    words = set(re.sub(r"[^a-z0-9]+", " ", value).split())
    matches = set()
    if kind == "cpu":
        if "intel" in words and "core" in words:
            matches.add("intel_core")
        if "amd" in words and "ryzen" in words:
            matches.add("amd_ryzen")
        if "apple" in words:
            matches.add("apple_silicon")
    elif kind == "gpu":
        if words.intersection({"llvmpipe", "swiftshader"}):
            matches.add("software")
        if "apple" in words:
            matches.add("apple_silicon")
        if "geforce" in words and "rtx" in words:
            matches.add("nvidia_rtx")
        if "geforce" in words and "gtx" in words:
            matches.add("nvidia_gtx")
        if "radeon" in words:
            matches.add("amd_radeon")
        if "intel" in words and "arc" in words:
            matches.add("intel_arc")
        if "intel" in words and words.intersection({"iris", "uhd", "hd"}):
            matches.add("intel_integrated")
    return next(iter(matches)) if len(matches) == 1 else "other"


def vehicle_id(raw, custom=False):
    if custom:
        return "custom"
    return raw if raw in VEHICLES else "unknown"


class FrameWindow:
    """Process cadence only. Callers own focus/drawability/context boundaries."""
    def __init__(self):
        self.histogram = [0] * len(HISTOGRAM_UPPER_US)
        self.interval_count = 0
        self.interval_sum_us = 0
        self.rendered_frames = 0
        self.draws_known = True
        self.excluded = 0

    def record(self, interval_us, draws=None):
        if type(interval_us) is not int or interval_us <= 0:
            raise ContractError("interval")
        if draws is not None and (type(draws) is not int or draws < 0):
            raise ContractError("draws")
        if interval_us > 5_000_000:
            if self.excluded >= 1000:
                raise ContractError("window_full")
            self.excluded += 1
            return False
        if self.interval_count >= 60000 or self.interval_sum_us + interval_us > 60_000_000:
            raise ContractError("window_full")
        if draws is not None and self.rendered_frames + draws > 60000:
            raise ContractError("window_full")
        for index, upper in enumerate(HISTOGRAM_UPPER_US):
            if interval_us <= upper:
                self.histogram[index] += 1
                break
        self.interval_count += 1
        self.interval_sum_us += interval_us
        if draws is None:
            self.draws_known = False
        else:
            self.rendered_frames += draws
        return True

    def event(self, seq=1, aircraft="f4u-corsair-250", complete=None):
        if self.interval_count == 0:
            raise ContractError("window_empty")
        if complete is None:
            complete = self.interval_sum_us >= 30_000_000
        if type(complete) is not bool:
            raise ContractError("window_complete")
        if complete and self.interval_sum_us < 30_000_000:
            raise ContractError("incomplete_window")
        known = self.draws_known
        return {
            "name": "performance_window", "seq": seq, "mode": "flight",
            "vehicle_id": vehicle_id(aircraft), "phase": "steady",
            "window_complete": complete, "interval_count": self.interval_count,
            "interval_sum_us": self.interval_sum_us,
            "rendered_frames": self.rendered_frames if known else None,
            "draw_counter_status": "observed" if known else "unavailable",
            "interval_histogram": list(self.histogram), "excluded_gap_count": self.excluded,
            "gpu_status": "not_measured", "gpu_ms": None,
        }


@dataclass
class Item:
    body: bytes
    epoch: int
    created: float
    due: float
    retries: int = 0


class ClientModel:
    """In-memory consent/queue/request model. No disk persistence or actual HTTP."""
    def __init__(self, eligible=True):
        self.eligible = eligible
        self.state = "pending"
        self.service_suspended = False
        self.epoch = 0
        self.session_id = None
        self.queue = deque()
        self.active = None
        self._request_serial = 0
        self.hour_start = None
        self.hour_attempts = 0
        self.hour_bytes = 0
        self.next_normal = 0.0

    @property
    def enabled(self):
        return self.eligible is True and not self.service_suspended and self.state == "enabled"

    def enable(self, notice=NOTICE):
        if self.service_suspended:
            return False
        self.disable("pending")
        if self.eligible is True and notice == NOTICE:
            self.state = "enabled"
            self.session_id = secrets.token_hex(16)
            return True
        return False

    def disable(self, state="off"):
        # An invalid disabled state must not reopen the probe gate.
        self.state = state if state in ("off", "pending", "suspended") else "off"
        if self.state == "suspended":
            self.service_suspended = True
        self.epoch += 1
        self.active = None
        self.queue.clear()
        self.session_id = None

    def expire(self, now):
        self.queue = deque(x for x in self.queue if now - x.created < QUEUE_TTL)
        if self.active and not any(x is self.active[1] for x in self.queue):
            self.active = None

    def collect(self, factory, now):
        # A factory can represent a hardware probe. It must not run before grant.
        if not self.enabled:
            return False
        epoch = self.epoch
        payload = factory()
        if not self.enabled or self.epoch != epoch:
            return False
        payload = dict(payload)
        payload["session_id"] = self.session_id
        body = encode(payload)
        validate_body(body)
        if not self.enabled or self.epoch != epoch:
            return False
        self.expire(now)
        while self.queue and (len(self.queue) >= QUEUE_BATCHES or
                              sum(len(x.body) for x in self.queue) + len(body) > QUEUE_BYTES):
            victim = self.queue.popleft()
            if self.active and self.active[1] is victim:
                self.active = None  # production adapter must cancel that request too
        self.queue.append(Item(body, epoch, now, now))
        return True

    def begin_send(self, now):
        self.expire(now)
        if not self.enabled or self.active or not self.queue:
            return None
        item = self.queue[0]
        if item.epoch != self.epoch or now < item.due or (not item.retries and now < self.next_normal):
            return None
        if self.hour_start is None or now - self.hour_start >= 3600:
            self.hour_start, self.hour_attempts, self.hour_bytes = now, 0, 0
        if self.hour_attempts >= MAX_ATTEMPTS_HOUR or self.hour_bytes + len(item.body) > MAX_BYTES_HOUR:
            return None
        self.hour_attempts += 1
        self.hour_bytes += len(item.body)
        self._request_serial += 1
        token = (self.epoch, self._request_serial)
        self.active = (token, item)
        # Real adapter adds 0..10 s jitter to normal cadence.
        self.next_normal = now + 60
        return token, item.body

    def complete(self, token, status, now, retry_after=0, jitter=0.5):
        if not self.enabled or not self.active or self.active[0] != token or token[0] != self.epoch:
            return False
        item = self.active[1]
        self.active = None
        if status in (401, 403, 410):
            self.disable("suspended")
            return True
        retryable = status in (0, 408, 429) or 500 <= status <= 599
        if retryable and item.retries < 5:
            delay = max(1.0, min(300, 5 * 2**item.retries) * max(0, min(1, jitter)))
            if isinstance(retry_after, (float, int)) and math.isfinite(retry_after) and retry_after >= 0:
                delay = max(delay, retry_after)
            item.retries += 1
            item.due = now + delay
            if item.due < item.created + QUEUE_TTL:
                return True
        self.queue = deque(x for x in self.queue if x is not item)
        return True


class IngressModel:
    """Single-process transactional specification, NOT durable database storage."""
    def __init__(self, max_batches=1000, approved_releases=frozenset({"v0.2.7"})):
        self.batches = {}
        self.events = {}
        self.max_batches = max_batches
        self.approved_releases = frozenset(approved_releases)

    def ingest(self, body, now):
        try:
            payload = validate_body(body)
        except ContractError as error:
            if str(error) == "body_too_large":
                return 413
            if str(error) in {"bytes_required", "invalid_json", "duplicate_key", "depth"}:
                return 400
            return 422
        if payload["build"]["release_id"] not in self.approved_releases:
            return 422
        self.batches = {key: item for key, item in self.batches.items() if now - item[0] < RAW_TTL}
        self.events = {key: stamp for key, stamp in self.events.items() if now - stamp < RAW_TTL}
        key, digest = payload["batch_id"], sha256(body).hexdigest()
        if key in self.batches:
            return 202 if self.batches[key][1] == digest else 409
        event_keys = [(payload["session_id"], event["seq"]) for event in payload["events"]]
        if any(key in self.events for key in event_keys):
            return 409
        if len(self.batches) >= self.max_batches:
            return 503
        # All validation/conflict checks precede this modeled atomic commit.
        self.batches[key] = (now, digest)
        self.events.update({key: now for key in event_keys})
        return 202


def aggregate_daily_gpu(records, day, release_id, minimum=20, *, as_of_utc):
    """One CLOSED day's fixed GPU table for one release; not a weekly scheduler.

    records contains (trusted_server_receipt_day, body) pairs. Caller supplies a
    trusted UTC instant; rollup is eligible from day close +1 h until day start +47 h.
    Input order is ingestion order. Cap each ephemeral session at 120 eligible
    windows. Suppress the whole table if any cell is below the threshold.
    Never lower the normative floor through this test seam.
    """
    if type(minimum) is not int or minimum < 20:
        raise ContractError("cohort_floor")
    try:
        closed = date.fromisoformat(day)
        current = datetime.fromisoformat(as_of_utc.replace("Z", "+00:00"))
        start = datetime.combine(closed, datetime.min.time(), tzinfo=timezone.utc)
        if (closed.isoformat() != day or current.utcoffset() != timedelta(0) or
            not start + timedelta(hours=25) <= current < start + timedelta(hours=47)):
            raise ValueError
    except (ValueError, TypeError, AttributeError, OverflowError):
        raise ContractError("day_not_eligible") from None
    iso = closed.isocalendar()
    period = f"{iso.year:04d}-W{iso.week:02d}"
    # Validate even a no-data request before consuming any record iterator.
    validate_report({"report_version": 1, "aggregation_scope": "closed_day", "day": day,
                     "period": period, "release_id": release_id, "status": "no_data",
                     "basis": "eligible_daily_session_observations", "rows": []})
    groups, seen, counts = {}, {}, {}
    for receipt_day, body in records:
        if receipt_day != day:
            raise ContractError("mixed_receipt_day")
        payload = validate_body(body)
        if payload["build"]["release_id"] != release_id:
            raise ContractError("mixed_release")
        session = payload["session_id"]
        family = payload["context"]["gpu_family"]
        for event in payload["events"]:
            key = (session, event["seq"])
            digest = sha256(encode([payload["build"], payload["context"], event])).digest()
            if key in seen:
                if seen[key] != digest:
                    raise ContractError("conflicting_event")
                continue
            seen[key] = digest
            if (event["name"] != "performance_window" or event["mode"] != "flight" or
                event["phase"] != "steady" or not event["window_complete"] or
                event["draw_counter_status"] != "observed"):
                continue
            if counts.get(session, 0) >= 120:
                continue
            counts[session] = counts.get(session, 0) + 1
            group = groups.setdefault(family, {"sessions": set(), "time": 0, "frames": 0})
            group["sessions"].add(session)
            group["time"] += event["interval_sum_us"]
            group["frames"] += event["rendered_frames"]
    status = "no_data" if not groups else "ready"
    if any(len(group["sessions"]) < minimum for group in groups.values()):
        status = "suppressed"
    rows = [] if status != "ready" else [
        {"gpu_family": family, "session_observations": len(group["sessions"]),
         "interval_sum_us": group["time"], "rendered_frames": group["frames"]}
        for family, group in sorted(groups.items())
    ]
    report = {"report_version": 1, "aggregation_scope": "closed_day", "day": day,
              "period": period, "release_id": release_id,
              "status": status, "basis": "eligible_daily_session_observations", "rows": rows}
    validate_report(report)
    return report


def validate_report(report):
    _bounded_tree(report)
    if not REPORT_VALIDATOR.is_valid(report):
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


def render_report(report):
    validate_report(report)
    lines = [
        "# OpenRC telemetry summary",
        "",
        f"UTC day: {report['day']} (daily subset of {report['period']}) · Release: {report['release_id']} · Status: {report['status']}",
        "",
        "Coverage: this closed day only; complete steady-flight windows with at least 30 s observed time and observed draw counts.",
        "This release-wide GPU table pools channels and other contexts; it cannot establish channel-specific or matched-settings regressions.",
        "Intervals over 5 s, including real foreground stalls, are excluded. This censored cadence estimate does not measure freeze incidence; gap counts are not in this table.",
        "Temporary sessions are not unique players or machines. FPS is an engine render-cadence estimate, not monitor presentation.",
        "",
    ]
    if report["status"] == "ready":
        lines.extend(["| GPU family | Session observations | Weighted FPS estimate |",
                      "| --- | ---: | ---: |"])
        for row in sorted(report["rows"], key=lambda x: x["gpu_family"]):
            fps = row["rendered_frames"] * 1_000_000 / row["interval_sum_us"]
            lines.append(f"| {row['gpu_family']} | {row['session_observations']} | {fps:.2f} |")
    else:
        lines.append("No cells are published. This status is not a claim of zero players or zero FPS.")
    content = "\n".join(lines) + "\n"
    if len(content.encode("utf-8")) > 32 * 1024:
        raise ContractError("report_too_large")
    return content
