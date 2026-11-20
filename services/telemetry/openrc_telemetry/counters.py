"""TELEM-20: ID-free daily ingest counters (status category per request), held in memory and flushed in batches.

Categories are fixed strings from this package, never request data. Counting in memory keeps a request flood from
turning into one database write per request; serve flushes them to the aggregate database every minute.
"""
from __future__ import annotations

from collections import Counter
import re
import threading

from .storage import StorageUnavailable, utc_day

MAX_KEYS = 512
CATEGORY_RE = re.compile(r"^[a-z0-9_:]{1,64}$")


class IngestCounters:
    def __init__(self):
        self._lock = threading.Lock()
        self._counts = Counter()

    def add(self, category, now):
        if not CATEGORY_RE.fullmatch(category):
            category = "other"
        key = (utc_day(now), category)
        with self._lock:
            if key not in self._counts and len(self._counts) >= MAX_KEYS:
                key = (key[0], "other")
            self._counts[key] += 1

    def drain(self):
        """[(day, category, count)] accumulated since the last drain; the caller persists them."""
        with self._lock:
            items = [(day, category, count) for (day, category), count in sorted(self._counts.items())]
            self._counts.clear()
        return items

    def restore(self, items):
        """Put drained items back after a failed write so they are retried, not lost."""
        with self._lock:
            for day, category, count in items:
                self._counts[(day, category)] += count


def flush(counters, aggregates):
    """Persist drained counts; on a storage error keep them for the next flush. Returns the number of rows."""
    items = counters.drain()
    if not items:
        return 0
    try:
        aggregates.add_ingest_counts(items)
    except StorageUnavailable:
        counters.restore(items)
        raise
    return len(items)
