"""In-memory abuse limits. Client keys are keyed HMACs of the address, never stored or logged."""
from __future__ import annotations

import hashlib
import hmac
import ipaddress
import math
import os
import threading
import time

ROTATE_SECONDS = 15 * 60


def client_identity(address):
    """The limiter's client unit: an IPv4 address, or the /64 of an IPv6 address (one subscriber usually holds a
    whole /64, so per-address buckets would not limit it). Unparsable values are used as given."""
    try:
        ip = ipaddress.ip_address(str(address))
    except ValueError:
        return str(address)
    if ip.version == 6:
        if ip.ipv4_mapped is not None:
            return str(ip.ipv4_mapped)
        return str(ipaddress.ip_network(f"{ip}/64", strict=False))
    return str(ip)


class RateLimiter:
    """Per-client and global token buckets. check() returns 0 if allowed, else Retry-After seconds."""

    def __init__(self, client_burst, client_refill_per_s, global_burst, global_refill_per_s, *,
                 max_clients=100_000, rotate_seconds=ROTATE_SECONDS, monotonic=time.monotonic,
                 key_source=lambda: os.urandom(32)):
        self.client_burst, self.client_rate = float(client_burst), float(client_refill_per_s)
        self.global_burst, self.global_rate = float(global_burst), float(global_refill_per_s)
        self.max_clients = max_clients
        self.rotate_seconds = rotate_seconds
        self._monotonic = monotonic
        self._key_source = key_source
        self._lock = threading.Lock()
        now = monotonic()
        self._key = key_source()
        self._key_born = now
        self._clients = {}
        self._global = [self.global_burst, now]

    @staticmethod
    def _refill(bucket, now, burst, rate):
        elapsed = max(0.0, now - bucket[1])
        bucket[0] = min(burst, bucket[0] + elapsed * rate)
        bucket[1] = now

    @staticmethod
    def _wait(deficit, rate):
        if rate <= 0:
            return ROTATE_SECONDS
        return max(1, min(ROTATE_SECONDS, math.ceil(deficit / rate)))

    def _rotate_if_due(self, now):
        if now - self._key_born >= self.rotate_seconds:
            self._key = self._key_source()
            self._key_born = now
            self._clients = {}

    def _prune(self, now):
        idle = []
        for key, bucket in self._clients.items():
            self._refill(bucket, now, self.client_burst, self.client_rate)
            if bucket[0] >= self.client_burst:
                idle.append(key)
        for key in idle:
            del self._clients[key]

    def check(self, address):
        with self._lock:
            now = self._monotonic()
            self._rotate_if_due(now)
            key = hmac.new(self._key, client_identity(address).encode("utf-8", "replace"), hashlib.sha256).digest()
            bucket = self._clients.get(key)
            if bucket is None:
                if len(self._clients) >= self.max_clients:
                    self._prune(now)
                    if len(self._clients) >= self.max_clients:
                        return 1
                bucket = [self.client_burst, now]
                self._clients[key] = bucket
            else:
                self._refill(bucket, now, self.client_burst, self.client_rate)
            self._refill(self._global, now, self.global_burst, self.global_rate)
            if bucket[0] < 1:
                return self._wait(1 - bucket[0], self.client_rate)
            if self._global[0] < 1:
                return self._wait(1 - self._global[0], self.global_rate)
            bucket[0] -= 1
            self._global[0] -= 1
            return 0

    def tracked_clients(self):
        with self._lock:
            return len(self._clients)
