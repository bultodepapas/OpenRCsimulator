"""Validate the temporal coverage of raw process-resource samples.

The resource sampler uses ``perf_counter`` for its origin, poll timings, and
finish anchor. This check does not join that clock to engine phases and does not
validate process identity, counters, or ``required_coverage``. Callers must
check those separately before treating resource monitoring as complete.
"""
from __future__ import annotations

from fractions import Fraction
import math


_FORMAT = "openrc-resource-samples v1"
_MAX_SAMPLES = 10_000  # ResourceSampler.validate_options limit
_MIN_SAMPLES = 2
# The sampler serializes rounded microsecond anchors and poll overheads, but
# keeps elapsed seconds as a float. Reconstructing a poll start can differ from
# an anchor by at most two microseconds due to those independent roundings.
_POLL_BOUNDARY_ROUNDING_USEC = 2
_SAMPLE_BOUNDARY_ROUNDING_USEC = 1


def _elapsed_usec(value):
    """Round a finite, nonnegative JSON number to microseconds without overflow."""
    if type(value) is int:
        return value * 1_000_000 if value >= 0 else None
    if type(value) is not float or not math.isfinite(value) or value < 0:
        return None
    return round(Fraction.from_float(value) * 1_000_000)


def validate_resource_timing(value) -> dict:
    """Return a bounded, independently computed timing assessment.

    A complete result requires at least two strictly ordered polls, valid
    sampler clock anchors, and no startup, between-poll, or finish gap above
    three declared sampling intervals plus 250 ms. Each reading can occur
    anywhere between its poll start and completion, so the between and finish
    gaps use the earlier poll's start. A complete result describes discrete
    host observations only; it does not imply continuous or phase coverage.

    Missing timing data return ``unavailable``; malformed or insufficient data
    and excessive gaps return ``incomplete``. Neither is a complete result.
    """
    result = {
        "status": "unavailable",
        "scope": "discrete process-resource polls on the host monotonic clock; no engine-phase attribution",
        "minimum_samples": _MIN_SAMPLES,
        "gap_policy": "three sampling intervals plus 250 ms scheduling slack",
        "gap_limit_usec": None,
        "bounds": {"origin_usec": None, "start_anchor_usec": None, "end_anchor_usec": None},
        "first_sample_delay_usec": None,
        "max_inter_sample_gap_usec": None,
        "last_sample_gap_usec": None,
        "max_poll_duration_usec": None,
        "sample_count": None,
        "reasons": [],
    }

    def fail(reason, *, missing=False, index=None):
        result["status"] = "unavailable" if missing else "incomplete"
        result["reasons"].append(reason)
        if index is not None:
            result["invalid_sample_index"] = index
        return result

    if not isinstance(value, dict):
        return fail("resource_report_unavailable", missing=value is None)
    if value.get("format") != _FORMAT:
        return fail("unsupported_resource_format", missing="format" not in value)

    if "interval_seconds" not in value:
        return fail("sampling_interval_unavailable", missing=True)
    interval = value["interval_seconds"]
    if (type(interval) not in (int, float) or not 0.1 <= interval <= 60
            or not math.isfinite(interval)):
        return fail("invalid_sampling_interval")
    result["gap_limit_usec"] = round((3 * interval + 0.25) * 1_000_000)

    if "samples" not in value:
        return fail("samples_unavailable", missing=True)
    samples = value["samples"]
    if not isinstance(samples, list):
        return fail("invalid_samples")
    result["sample_count"] = len(samples)
    if (type(value.get("sample_count")) is not int
            or value["sample_count"] != len(samples)):
        return fail("sample_count_mismatch")
    max_samples = value.get("max_samples")
    if (type(max_samples) is not int or not 1 <= max_samples <= _MAX_SAMPLES
            or len(samples) > max_samples):
        return fail("invalid_sample_limit", missing="max_samples" not in value)
    if len(samples) < _MIN_SAMPLES:
        return fail("fewer_than_two_samples")

    if "clock" not in value:
        return fail("clock_unavailable", missing=True)
    clock = value["clock"]
    if not isinstance(clock, dict):
        return fail("invalid_clock")
    if "source" not in clock:
        return fail("clock_source_unavailable", missing=True)
    if clock["source"] != "python_perf_counter":
        return fail("invalid_clock_source")
    if "origin_usec" not in clock or "start" not in clock or "end" not in clock:
        return fail("clock_bounds_unavailable", missing=True)
    origin, start, end = clock["origin_usec"], clock["start"], clock["end"]
    if type(origin) is not int or origin < 0:
        return fail("invalid_clock_origin")
    if not isinstance(start, dict) or not isinstance(end, dict):
        return fail("invalid_clock_anchor")
    anchor_fields = ("monotonic_usec", "unix_usec", "uncertainty_usec")
    if any(field not in anchor for anchor in (start, end) for field in anchor_fields):
        return fail("clock_anchor_unavailable", missing=True)
    if any(type(anchor[field]) is not int or anchor[field] < 0
           for anchor in (start, end) for field in anchor_fields):
        return fail("invalid_clock_anchor")
    # clock_anchor() applies a 20 ms floor even when its wall-clock read is
    # instantaneous; values below it cannot be produced by this v1 sampler.
    if any(anchor["uncertainty_usec"] < 20_000 for anchor in (start, end)):
        return fail("invalid_clock_anchor")
    start_us, end_us = start["monotonic_usec"], end["monotonic_usec"]
    result["bounds"] = {"origin_usec": origin, "start_anchor_usec": start_us, "end_anchor_usec": end_us}
    if not origin <= start_us <= end_us:
        return fail("invalid_clock_bounds")

    start_elapsed = start_us - origin
    stop_elapsed = end_us - origin
    poll_brackets = []
    previous_elapsed_seconds = None
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            return fail("invalid_sample", index=index)
        if "elapsed_seconds" not in sample or "poll_overhead_usec" not in sample:
            return fail("sample_timing_unavailable", missing=True, index=index)
        elapsed = _elapsed_usec(sample["elapsed_seconds"])
        overhead = sample["poll_overhead_usec"]
        if elapsed is None or type(overhead) is not int or overhead < 0:
            return fail("invalid_sample_timing", index=index)
        poll_start = elapsed - overhead
        if poll_start < -_POLL_BOUNDARY_ROUNDING_USEC:
            return fail("poll_before_origin", index=index)
        if poll_start + _POLL_BOUNDARY_ROUNDING_USEC < start_elapsed:
            return fail("poll_before_start_anchor", index=index)
        if elapsed > stop_elapsed + _SAMPLE_BOUNDARY_ROUNDING_USEC:
            return fail("sample_after_end_anchor", index=index)
        if previous_elapsed_seconds is not None and sample["elapsed_seconds"] <= previous_elapsed_seconds:
            return fail("sample_times_not_increasing", index=index)
        if poll_brackets and poll_start + _POLL_BOUNDARY_ROUNDING_USEC < poll_brackets[-1][1]:
            return fail("overlapping_polls", index=index)
        poll_brackets.append((max(0, poll_start), elapsed, overhead))
        previous_elapsed_seconds = sample["elapsed_seconds"]

    first = poll_brackets[0][1]
    between = max(later[1] - earlier[0] for earlier, later in zip(poll_brackets, poll_brackets[1:]))
    last = max(0, stop_elapsed - poll_brackets[-1][0])
    result.update(first_sample_delay_usec=first, max_inter_sample_gap_usec=between,
                  last_sample_gap_usec=last,
                  max_poll_duration_usec=max(poll[2] for poll in poll_brackets))
    limit = result["gap_limit_usec"]
    if first > limit:
        result["reasons"].append("first_observation_delayed")
    if between > limit:
        result["reasons"].append("inter_sample_gap")
    if last > limit:
        result["reasons"].append("last_observation_too_early")
    result["status"] = "incomplete" if result["reasons"] else "complete"
    return result


_REQUIRED_FIELDS = ("rss_bytes", "cpu_user_seconds", "cpu_system_seconds",
                    "virtual_memory_available_bytes")
_OWNER_INTERVAL_SECONDS = 1
_OWNER_MAX_SAMPLES = 4000


def _valid_required_number(value, *, integer=False):
    if type(value) not in ((int,) if integer else (int, float)) or value < 0:
        return False
    try:
        # ResourceSampler normalizes every number through float() before
        # retaining it, including integer byte counters.
        return math.isfinite(float(value))
    except (OverflowError, TypeError, ValueError):
        return False


def validate_resource_required_fields(value) -> dict:
    """Recheck the sampler's required field/stop contract using raw samples.

    This independently checks producer invariants rather than trusting the
    ``required_coverage`` label. Optional metrics and their errors do not make
    required field coverage incomplete. Process/source identity and temporal
    coverage remain separate checks for the caller.
    """
    result = {"status": "unavailable", "required_fields": list(_REQUIRED_FIELDS),
              "sample_count": None, "required_field_counts": None, "reasons": []}

    def fail(reason, *, missing=False, index=None):
        result["status"] = "unavailable" if missing else "incomplete"
        result["reasons"].append(reason)
        if index is not None:
            result["invalid_sample_index"] = index
        return result

    if not isinstance(value, dict):
        return fail("resource_report_unavailable", missing=value is None)
    if value.get("format") != _FORMAT:
        return fail("unsupported_resource_format", missing="format" not in value)
    metadata = ("samples", "sample_count", "max_samples", "capped", "stop_reason",
                "required_coverage", "required_field_counts")
    if any(key not in value for key in metadata):
        return fail("required_coverage_metadata_unavailable", missing=True)
    samples = value["samples"]
    if not isinstance(samples, list):
        return fail("invalid_samples")
    result["sample_count"] = len(samples)
    if type(value["sample_count"]) is not int or value["sample_count"] != len(samples):
        return fail("sample_count_mismatch")
    maximum = value["max_samples"]
    if type(maximum) is not int or not 1 <= maximum <= _MAX_SAMPLES or len(samples) > maximum:
        return fail("invalid_sample_limit")
    if len(samples) < _MIN_SAMPLES:
        return fail("fewer_than_two_samples")
    if type(value["capped"]) is not bool:
        return fail("invalid_cap_status")
    if value["capped"] or len(samples) >= maximum:
        return fail("sample_limit_reached")
    if value["stop_reason"] != "caller_finished":
        return fail("sampler_did_not_finish_cleanly")
    if value["required_coverage"] != "complete":
        return fail("producer_required_coverage_incomplete")
    summary = value.get("summary")
    if isinstance(summary, dict) and "counter_resets" in summary:
        resets = summary["counter_resets"]
        if not isinstance(resets, list) or any(not isinstance(item, str) for item in resets):
            return fail("invalid_counter_resets")
        if any(key in resets for key in ("cpu_user_seconds", "cpu_system_seconds")):
            return fail("cpu_counter_reset_reported")
    declared = value["required_field_counts"]
    if not isinstance(declared, dict):
        return fail("invalid_required_field_counts")
    if any(key not in declared for key in _REQUIRED_FIELDS):
        return fail("required_field_counts_unavailable", missing=True)

    counts = {key: 0 for key in _REQUIRED_FIELDS}
    previous = None
    for index, row in enumerate(samples):
        if not isinstance(row, dict):
            return fail("invalid_sample", index=index)
        if "field_status" not in row or any(key not in row for key in _REQUIRED_FIELDS):
            return fail("required_fields_unavailable", missing=True, index=index)
        statuses = row["field_status"]
        if not isinstance(statuses, dict):
            return fail("invalid_field_status", index=index)
        if any(key not in statuses for key in _REQUIRED_FIELDS):
            return fail("required_field_status_unavailable", missing=True, index=index)
        if any(statuses[key] != "ok" for key in _REQUIRED_FIELDS):
            return fail("required_field_not_ok", index=index)
        for key in _REQUIRED_FIELDS:
            if not _valid_required_number(row[key], integer=key in ("rss_bytes", "virtual_memory_available_bytes")):
                return fail("invalid_required_field", index=index)
            counts[key] += 1
        if previous is not None and any(row[key] < previous[key]
                                        for key in ("cpu_user_seconds", "cpu_system_seconds")):
            return fail("cpu_counter_decreased", index=index)
        previous = row
    result["required_field_counts"] = counts
    if any(type(declared[key]) is not int or declared[key] != counts[key] for key in _REQUIRED_FIELDS):
        return fail("required_field_count_mismatch")
    result["status"] = "complete"
    return result


def validate_resource_owner_clock(value, execution) -> dict:
    """Bind raw CPU timing/configuration to the owning runner's clock receipt.

    The receipt brackets construction and finish on the same perf_counter
    domain. It does not align host observations to engine phases or prove that
    the observer ran continuously. Intrinsic between-poll coverage is checked
    separately by :func:`validate_resource_timing`.
    """
    result = {"status": "unavailable", "scope": "owner and sampler perf_counter clock; no engine-phase attribution",
              "gap_limit_usec": None, "bounds": None, "first_sample_delay_usec": None,
              "last_sample_gap_usec": None, "reasons": []}

    def fail(reason, *, missing=False):
        result["status"] = "unavailable" if missing else "incomplete"
        result["reasons"].append(reason)
        return result

    if not isinstance(execution, dict) or "resource_observation" not in execution:
        return fail("owner_clock_unavailable", missing=True)
    owner = execution["resource_observation"]
    if not isinstance(owner, dict):
        return fail("invalid_owner_clock")
    fields = ("clock_domain", "start_requested_usec", "stop_requested_usec", "finish_returned_usec",
              "interval_seconds", "max_samples")
    if any(field not in owner for field in fields):
        return fail("owner_clock_unavailable", missing=True)
    if owner["clock_domain"] != "python_perf_counter":
        return fail("invalid_owner_clock_domain")
    stamps = tuple(owner[field] for field in ("start_requested_usec", "stop_requested_usec", "finish_returned_usec"))
    if any(type(stamp) is not int or stamp < 0 for stamp in stamps) or not stamps[0] <= stamps[1] <= stamps[2]:
        return fail("invalid_owner_clock_bounds")
    owner_start, owner_stop, owner_finish = stamps
    result["bounds"] = {"start_requested_usec": owner_start, "stop_requested_usec": owner_stop,
                        "finish_returned_usec": owner_finish}
    if (type(owner["interval_seconds"]) not in (int, float) or owner["interval_seconds"] != _OWNER_INTERVAL_SECONDS
            or type(owner["max_samples"]) is not int or owner["max_samples"] != _OWNER_MAX_SAMPLES):
        return fail("unsupported_owner_sampling_config")
    if not isinstance(value, dict):
        return fail("resource_report_unavailable", missing=value is None)
    if "interval_seconds" not in value or "max_samples" not in value:
        return fail("sampler_config_unavailable", missing=True)
    if (type(value["interval_seconds"]) not in (int, float) or value["interval_seconds"] != _OWNER_INTERVAL_SECONDS
            or type(value["max_samples"]) is not int or value["max_samples"] != _OWNER_MAX_SAMPLES):
        return fail("sampler_config_mismatch")
    if "monitoring_started_perf_counter_s" in execution:
        recorded = _elapsed_usec(execution["monitoring_started_perf_counter_s"])
        if recorded is None or abs(recorded - owner_start) > _SAMPLE_BOUNDARY_ROUNDING_USEC:
            return fail("monitoring_start_mismatch")

    timing = validate_resource_timing(value)
    result["gap_limit_usec"] = timing["gap_limit_usec"]
    # Gaps may independently be incomplete, but a computed first delay means
    # the raw anchors and every poll bracket passed structural validation.
    if timing["first_sample_delay_usec"] is None:
        return fail("intrinsic_timing_unavailable", missing=timing["status"] == "unavailable")
    clock = timing["bounds"]
    origin, anchor_start, anchor_end = (clock["origin_usec"], clock["start_anchor_usec"], clock["end_anchor_usec"])
    if origin + _SAMPLE_BOUNDARY_ROUNDING_USEC < owner_start or anchor_start + _POLL_BOUNDARY_ROUNDING_USEC < owner_start:
        return fail("sampler_started_before_owner_request")
    if (anchor_end + _POLL_BOUNDARY_ROUNDING_USEC < owner_stop
            or anchor_end > owner_finish + _POLL_BOUNDARY_ROUNDING_USEC):
        return fail("sampler_finish_outside_owner_bracket")
    rows = value["samples"]
    first_end = origin + _elapsed_usec(rows[0]["elapsed_seconds"])
    last_end = origin + _elapsed_usec(rows[-1]["elapsed_seconds"])
    last_start = last_end - rows[-1]["poll_overhead_usec"]
    if last_end > owner_stop + _SAMPLE_BOUNDARY_ROUNDING_USEC:
        return fail("sample_after_owner_stop")
    first = max(0, first_end - owner_start)
    last = max(0, owner_stop - last_start)
    result.update(first_sample_delay_usec=first, last_sample_gap_usec=last)
    if first > result["gap_limit_usec"]:
        result["reasons"].append("first_observation_delayed_from_owner_start")
    if last > result["gap_limit_usec"]:
        result["reasons"].append("last_observation_too_early_for_owner_stop")
    result["status"] = "incomplete" if result["reasons"] else "complete"
    return result
