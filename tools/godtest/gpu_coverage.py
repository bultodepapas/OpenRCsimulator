"""Recheck GPU sample timing against the runner's independent owner bracket.

This module checks host-clock timing only.  The caller must independently check
artifact/source identity, the worker lifecycle, device identity, utilization
values, summaries, and whether the observed GPU is relevant to the workload.
It does not join the Python clock to engine phases or imply continuous coverage.

Each query's observation can occur anywhere within its retained backend clock
bracket.  First, inter-observation, and tail gaps therefore use the latest
possible next observation and the earliest possible previous observation.  A
query that straddles the owner stop may finish and be retained, but is not
credited toward coverage because its measurement could have happened after the
owned observation ended.  The same rule applies to whole poll brackets.
"""
from __future__ import annotations

_FORMAT = "openrc-godtest-gpu-v1"
_OWNER_CLOCK = "python_perf_counter"
_GPU_CLOCK = "python_time_perf_counter"
_INTERVAL_SECONDS = 1
_MAX_SAMPLES = 4000
_MIN_SAMPLES = 2
_GAP_LIMIT_USEC = 3_250_000  # Three fixed 1 s intervals plus 250 ms scheduling slack.
# The runner timestamps just before stop(); its worker may already have passed
# the Event test before stop() sets it. Such post-stop reads cannot establish
# coverage, but a small scheduling race does not make earlier observations false.
_STOP_RACE_USEC = 50_000


def _clock(value) -> bool:
    return type(value) is int and 0 <= value <= 2**63 - 1


def _fixed_interval(value) -> bool:
    return type(value) in (int, float) and value == _INTERVAL_SECONDS


def validate_gpu_timing(value, execution) -> dict:
    """Assess bounded GPU polling gaps using raw brackets and owner receipts.

    The current runner uses ``GpuSampler(interval=1, max_samples=4000)`` and
    records ``execution['gpu_observation']`` before construction, immediately
    before stop, and immediately after stop returns. Historical artifacts without
    that independent receipt are unavailable. Malformed data or excess gaps are
    incomplete. Neither outcome is a pass, and metric/device correctness remains
    the caller's responsibility.
    """
    result = {
        "status": "unavailable",
        "scope": "discrete GPU device observations on Python's host monotonic clock; no engine-phase attribution",
        "clock_domain": _OWNER_CLOCK,
        "interval_seconds": _INTERVAL_SECONDS,
        "max_samples": _MAX_SAMPLES,
        "minimum_samples": _MIN_SAMPLES,
        "gap_limit_usec": _GAP_LIMIT_USEC,
        "gap_policy": "fixed three 1-second intervals plus 250 ms; conservative query-bracket endpoints",
        "stop_race_tolerance_usec": _STOP_RACE_USEC,
        "bounds": {"owner_start_usec": None, "sampler_start_usec": None,
                   "owner_start_returned_usec": None,
                   "owner_stop_requested_usec": None, "sampler_stop_requested_usec": None,
                   "sampler_stop_usec": None, "owner_finish_returned_usec": None},
        "first_poll_gap_usec": None, "max_inter_poll_gap_usec": None,
        "last_poll_gap_usec": None, "max_poll_duration_usec": None,
        "worst_device_first_gap_usec": None, "worst_device_inter_gap_usec": None,
        "worst_device_tail_gap_usec": None, "max_backend_duration_usec": None,
        "sample_count": None, "completed_polls": 0, "straddled_polls": 0,
        "post_stop_polls": 0, "straddled_device_observations": 0,
        "post_stop_device_observations": 0, "devices": {}, "reasons": [],
    }

    def fail(reason, *, missing=False, index=None):
        result["status"] = "unavailable" if missing else "incomplete"
        result["reasons"].append(reason)
        if index is not None:
            result["invalid_sample_index"] = index
        return result

    if not isinstance(execution, dict):
        return fail("execution_receipt_unavailable", missing=execution is None)
    owner = execution.get("gpu_observation")
    if owner is None:
        return fail("owner_receipt_unavailable", missing=True)
    if not isinstance(owner, dict):
        return fail("invalid_owner_receipt")
    for name in ("clock_domain", "start_requested_usec", "stop_requested_usec",
                 "finish_returned_usec", "interval_seconds", "max_samples"):
        if name not in owner:
            return fail("owner_" + name + "_unavailable", missing=True)
    if owner["clock_domain"] != _OWNER_CLOCK:
        return fail("owner_clock_domain_mismatch")
    if not _fixed_interval(owner["interval_seconds"]) or type(owner["max_samples"]) is not int or owner["max_samples"] != _MAX_SAMPLES:
        return fail("owner_sampling_configuration_mismatch")
    owner_start, owner_stop, owner_finish = (owner[name] for name in
                                               ("start_requested_usec", "stop_requested_usec", "finish_returned_usec"))
    if not all(_clock(item) for item in (owner_start, owner_stop, owner_finish)) or not owner_start <= owner_stop <= owner_finish:
        return fail("invalid_owner_clock_bounds")
    result["bounds"].update(owner_start_usec=owner_start, owner_stop_requested_usec=owner_stop,
                            owner_finish_returned_usec=owner_finish)

    if not isinstance(value, dict):
        return fail("gpu_report_unavailable", missing=value is None)
    for name in ("format", "clock_domain", "interval_seconds", "max_samples", "start_monotonic_usec",
                 "stop_requested_monotonic_usec", "stop_monotonic_usec", "sample_count", "samples"):
        if name not in value:
            return fail("gpu_" + name + "_unavailable", missing=True)
    if value["format"] != _FORMAT:
        return fail("unsupported_gpu_format")
    if value["clock_domain"] != _GPU_CLOCK:
        return fail("gpu_clock_domain_mismatch")
    if not _fixed_interval(value["interval_seconds"]) or type(value["max_samples"]) is not int or value["max_samples"] != _MAX_SAMPLES:
        return fail("gpu_sampling_configuration_mismatch")
    sampler_start, sampler_stop, sampler_end = (value[name] for name in
                                                ("start_monotonic_usec", "stop_requested_monotonic_usec", "stop_monotonic_usec"))
    if (not all(_clock(item) for item in (sampler_start, sampler_stop, sampler_end))
            or not owner_start <= sampler_start <= owner_stop <= sampler_stop <= sampler_end <= owner_finish):
        return fail("invalid_sampler_owner_clock_bounds")
    # Some runners retain the return from start() as an additional independent
    # bound; keep compatibility with the required three-boundary receipt.
    start_returned = owner.get("start_returned_usec")
    if "start_returned_usec" in owner and (not _clock(start_returned) or
                                             not sampler_start <= start_returned <= owner_stop):
        return fail("invalid_owner_start_returned_bound")
    result["bounds"].update(sampler_start_usec=sampler_start,
                            owner_start_returned_usec=start_returned,
                            sampler_stop_requested_usec=sampler_stop, sampler_stop_usec=sampler_end)
    result["sampler_start_delay_usec"] = sampler_start - owner_start
    result["stop_signal_delay_usec"] = sampler_stop - owner_stop
    if sampler_stop - owner_stop > _STOP_RACE_USEC:
        return fail("owner_stop_signal_delayed")

    samples = value["samples"]
    if not isinstance(samples, list):
        return fail("invalid_samples")
    result["sample_count"] = len(samples)
    if type(value["sample_count"]) is not int or value["sample_count"] != len(samples) or len(samples) > _MAX_SAMPLES:
        return fail("sample_count_mismatch_or_cap_exceeded")
    if len(samples) < _MIN_SAMPLES:
        return fail("fewer_than_two_polls")

    # Only one state per device and one aggregate poll state are retained.
    devices = {}
    poll_count, first_poll_gap, last_poll_start, max_poll_gap = 0, None, None, None
    previous_poll_end = sampler_start
    previous_poll_start = None
    max_poll_duration, max_backend_duration = 0, 0
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            return fail("invalid_poll", index=index)
        if any(name not in sample for name in ("start_monotonic_usec", "end_monotonic_usec", "backends")):
            return fail("poll_fields_unavailable", missing=True, index=index)
        begin, end, backends = (sample[name] for name in ("start_monotonic_usec", "end_monotonic_usec", "backends"))
        if (not _clock(begin) or not _clock(end)
                or not previous_poll_end <= begin <= end <= sampler_end
                or (previous_poll_start is not None and begin <= previous_poll_start)):
            return fail("invalid_poll_clock_bracket", index=index)
        if begin > owner_stop + _STOP_RACE_USEC:
            return fail("poll_started_after_owner_stop", index=index)
        if not isinstance(backends, list) or not backends:
            return fail("invalid_backend_list", index=index)
        previous_poll_start, previous_poll_end = begin, end
        max_poll_duration = max(max_poll_duration, end - begin)
        if begin > owner_stop:
            result["post_stop_polls"] += 1
        elif end > owner_stop:
            result["straddled_polls"] += 1
        else:
            poll_count += 1
            if first_poll_gap is None:
                first_poll_gap = end - owner_start
            if last_poll_start is not None:
                gap = end - last_poll_start
                max_poll_gap = gap if max_poll_gap is None else max(max_poll_gap, gap)
            last_poll_start = begin
        seen = set()
        for backend in backends:
            if not isinstance(backend, dict):
                return fail("invalid_backend", index=index)
            if any(name not in backend for name in ("start_monotonic_usec", "end_monotonic_usec", "devices")):
                return fail("backend_fields_unavailable", missing=True, index=index)
            lower, upper, items = (backend[name] for name in ("start_monotonic_usec", "end_monotonic_usec", "devices"))
            if not _clock(lower) or not _clock(upper) or not begin <= lower <= upper <= end:
                return fail("invalid_backend_clock_bracket", index=index)
            if lower > owner_stop + _STOP_RACE_USEC:
                return fail("backend_started_after_owner_stop", index=index)
            if not isinstance(items, list):
                return fail("invalid_backend_devices", index=index)
            max_backend_duration = max(max_backend_duration, upper - lower)
            for device in items:
                if not isinstance(device, dict) or not isinstance(device.get("identity"), dict):
                    return fail("invalid_device_timing_identity", index=index)
                key = device["identity"].get("key")
                if not isinstance(key, str) or not key or key in seen:
                    return fail("missing_or_duplicate_device_timing_identity", index=index)
                seen.add(key)
                entry = devices.setdefault(key, {"completed_observations": 0, "first_gap_usec": None,
                                                  "max_inter_gap_usec": None, "last_gap_usec": None,
                                                  "_last_start_usec": None})
                if lower > owner_stop:
                    result["post_stop_device_observations"] += 1
                elif upper > owner_stop:
                    result["straddled_device_observations"] += 1
                else:
                    entry["completed_observations"] += 1
                    if entry["first_gap_usec"] is None:
                        entry["first_gap_usec"] = upper - owner_start
                    previous = entry["_last_start_usec"]
                    if previous is not None:
                        gap = upper - previous
                        entry["max_inter_gap_usec"] = (gap if entry["max_inter_gap_usec"] is None
                                                        else max(entry["max_inter_gap_usec"], gap))
                    entry["_last_start_usec"] = lower

    result.update(completed_polls=poll_count, first_poll_gap_usec=first_poll_gap,
                  max_inter_poll_gap_usec=max_poll_gap,
                  last_poll_gap_usec=owner_stop - last_poll_start if last_poll_start is not None else None,
                  max_poll_duration_usec=max_poll_duration, max_backend_duration_usec=max_backend_duration)
    reasons = result["reasons"]
    if poll_count < _MIN_SAMPLES:
        reasons.append("fewer_than_two_completed_polls")
    for field, reason in (("first_poll_gap_usec", "first_poll_gap_exceeded"),
                          ("max_inter_poll_gap_usec", "inter_poll_gap_exceeded"),
                          ("last_poll_gap_usec", "last_poll_gap_exceeded")):
        if result[field] is not None and result[field] > _GAP_LIMIT_USEC:
            reasons.append(reason)
    if not devices:
        reasons.append("no_identified_devices")
    for entry in devices.values():
        last_start = entry.pop("_last_start_usec")
        entry["last_gap_usec"] = owner_stop - last_start if last_start is not None else None
        if entry["completed_observations"] < _MIN_SAMPLES:
            reasons.append("fewer_than_two_completed_device_observations")
        for field, reason in (("first_gap_usec", "device_first_gap_exceeded"),
                              ("max_inter_gap_usec", "device_inter_gap_exceeded"),
                              ("last_gap_usec", "device_last_gap_exceeded")):
            if entry[field] is not None and entry[field] > _GAP_LIMIT_USEC:
                reasons.append(reason)
    result["devices"] = devices
    for output, field in (("worst_device_first_gap_usec", "first_gap_usec"),
                          ("worst_device_inter_gap_usec", "max_inter_gap_usec"),
                          ("worst_device_tail_gap_usec", "last_gap_usec")):
        gaps = [entry[field] for entry in devices.values() if entry[field] is not None]
        result[output] = max(gaps) if gaps else None
    result["reasons"] = sorted(set(reasons))
    result["status"] = "incomplete" if reasons else "complete"
    return result
