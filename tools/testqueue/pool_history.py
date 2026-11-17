"""Robust, advisory duration history for checked-test placement and ETAs.

``history.json`` maps a host ID to per-script entries plus ``_setup_seconds``.
An entry is either a legacy positive number (one sample) or
``{"samples": [...], "ids": [...]}``, holding the newest ``WINDOW`` successful
durations and, when known, the pool job that produced each one. A repeated
collection of the same job never adds a second sample. Estimates use the
median, so one cold cache or a loaded desktop does not dominate placement.
History only ranks eligible hosts and orders submissions; it never admits,
reserves, cancels or retries work.

A host without its own sample for a script borrows the median of other hosts,
scaled by the median ratio of the scripts both hosts have run. That lets an
unmeasured host compete with a realistic figure instead of the full timeout.

The window format is one-way: code older than this module reads a window
entry as an invalid duration and refuses that script's history-based
placement. Keep history.json with the version that wrote it.
"""
from __future__ import annotations

import math
import statistics

WINDOW = 9
SETUP_KEY = "_setup_seconds"
MINIMUM_SECONDS = 0.001


def _positive(value):
    try:
        return type(value) in (int, float) and math.isfinite(value) and value > 0
    except (OverflowError, TypeError):
        return False


def _floor(value):
    return max(MINIMUM_SECONDS, float(value))


def samples(entry) -> list[float]:
    """Return valid samples from a legacy number or a sample-window entry."""
    if _positive(entry):
        return [_floor(entry)]
    if isinstance(entry, dict) and isinstance(entry.get("samples"), list):
        return [_floor(value) for value in entry["samples"] if _positive(value)][-WINDOW:]
    return []


def estimate(entry):
    """Median of the retained samples, or None without a valid sample."""
    values = samples(entry)
    if not values:
        return None
    value = statistics.median(values)
    return value if _positive(value) else None


def record(history: dict, host_id: str, key: str, seconds: float, sample_id: str | None = None) -> bool:
    """Append one measured duration; return False if ``sample_id`` was already recorded."""
    if not isinstance(host_id, str) or not host_id or not isinstance(key, str) or not key:
        raise ValueError("history host and key must be nonempty strings")
    if type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds < 0:
        raise ValueError("history duration must be finite and nonnegative")
    host = history.setdefault(host_id, {})
    if not isinstance(host, dict):
        raise ValueError("history host entry must be a mapping")
    entry = host.get(key)
    values = samples(entry)
    ids = entry.get("ids") if isinstance(entry, dict) else None
    ids = list(ids) if isinstance(ids, list) and len(ids) == len(values) else [None] * len(values)
    if sample_id is not None and sample_id in ids:
        return False
    values.append(_floor(seconds))
    ids.append(sample_id)
    host[key] = {"samples": values[-WINDOW:], "ids": ids[-WINDOW:]}
    return True


def _medians(history, host_id):
    host = history.get(host_id) if isinstance(history, dict) else None
    if not isinstance(host, dict):
        return {}
    result = {}
    for key, entry in host.items():
        if key == SETUP_KEY or not isinstance(key, str):
            continue
        value = estimate(entry)
        if value is not None:
            result[key] = value
    return result


def _setup(history, host_id):
    host = history.get(host_id) if isinstance(history, dict) else None
    return estimate(host.get(SETUP_KEY)) if isinstance(host, dict) else None


def host_view(history, host_id: str, default_setup: float):
    """Return ``(durations, sources, setup_seconds)`` for one host.

    ``sources`` names each duration's origin: ``history`` for this host's own
    samples, ``peer`` for a speed-scaled estimate from other hosts. A host
    without its own setup sample assumes at least the peers' median setup, so
    a cold host does not look cheaper than measured ones.
    """
    own = _medians(history, host_id)
    durations = dict(own)
    sources = {key: "history" for key in own}
    borrowed, peer_setups = {}, []
    for peer in (history if isinstance(history, dict) else {}):
        if peer == host_id or not isinstance(peer, str):
            continue
        setup = _setup(history, peer)
        if setup is not None:
            peer_setups.append(setup)
        medians = _medians(history, peer)
        if not medians:
            continue
        shared = [own[key] / medians[key] for key in own.keys() & medians.keys()]
        speed = statistics.median(shared) if shared else 1.0
        for key, value in medians.items():
            if key not in own:
                borrowed.setdefault(key, []).append(value * speed)
    for key, values in borrowed.items():
        value = statistics.median(values)
        if _positive(value):
            durations[key], sources[key] = _floor(value), "peer"
    setup = _setup(history, host_id)
    if setup is None:
        setup = max([default_setup] + ([statistics.median(peer_setups)] if peer_setups else []))
    return durations, sources, setup


def expected_seconds(history, key: str):
    """Best fleet-wide median for ``key`` (used for ordering and ETAs), or None."""
    values = [value for host in (history if isinstance(history, dict) else {})
              if isinstance(host, str) and (value := _medians(history, host).get(key)) is not None]
    return min(values) if values else None
