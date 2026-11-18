"""Environment-driven configuration. Every setting has a safe default."""
from __future__ import annotations

from dataclasses import dataclass, field
import os
from pathlib import Path

PACKAGE_DIR = Path(__file__).resolve().parent
DEFAULT_SCHEMA_DIR = (PACKAGE_DIR.parent / ".." / ".." / "research" / "telemetry" / "contracts").resolve()


def _int(env, name, default):
    raw = env.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        raise SystemExit(f"{name} must be an integer") from None


def _float(env, name, default):
    raw = env.get(name)
    if raw is None or raw == "":
        return default
    try:
        value = float(raw)
    except ValueError:
        raise SystemExit(f"{name} must be a number") from None
    if not value >= 0:
        raise SystemExit(f"{name} must be non-negative")
    return value


@dataclass(frozen=True)
class Config:
    data_dir: Path = Path("./data")
    # Separate directories let the raw database live on a volume that is never backed up or snapshotted.
    raw_dir: Path | None = None
    aggregates_dir: Path | None = None
    schema_dir: Path = DEFAULT_SCHEMA_DIR
    releases: frozenset = frozenset()
    # Operator off switch: these releases (or every batch) get 410, which suspends clients for the process.
    suspended_releases: frozenset = frozenset()
    suspend_all: bool = False
    # serve purges raw rows itself this often (and earlier than 48 h by the same margin), so the retention
    # promise does not depend on an external timer.
    purge_interval_s: int = 300
    trust_proxy: bool = False
    client_burst: float = 20.0
    client_refill_per_s: float = 10 / 60
    global_burst: float = 200.0
    global_refill_per_s: float = 50.0
    max_clients: int = 100_000
    max_raw_bytes: int = 2 * 1024**3
    report_token: str = field(default="", repr=False)
    github_api: str = "https://api.github.com"
    bot_author: str = ""
    issue_label: str = "telemetry"

    @property
    def raw_path(self):
        return Path(self.raw_dir or self.data_dir) / "raw.sqlite"

    @property
    def aggregates_path(self):
        return Path(self.aggregates_dir or self.data_dir) / "aggregates.sqlite"

    @classmethod
    def from_env(cls, env=None):
        env = os.environ if env is None else env
        releases = frozenset(x.strip() for x in env.get("OPENRC_TELEMETRY_RELEASES", "").split(",") if x.strip())
        suspended = frozenset(x.strip() for x in env.get("OPENRC_TELEMETRY_SUSPEND_RELEASES", "").split(",") if x.strip())
        defaults = cls()
        interval = _int(env, "OPENRC_TELEMETRY_PURGE_INTERVAL_S", defaults.purge_interval_s)
        if not 30 <= interval <= 3600:
            raise SystemExit("OPENRC_TELEMETRY_PURGE_INTERVAL_S must be between 30 and 3600")
        return cls(
            data_dir=Path(env.get("OPENRC_TELEMETRY_DATA_DIR") or "./data"),
            raw_dir=Path(env["OPENRC_TELEMETRY_RAW_DIR"]) if env.get("OPENRC_TELEMETRY_RAW_DIR") else None,
            aggregates_dir=(Path(env["OPENRC_TELEMETRY_AGGREGATES_DIR"])
                            if env.get("OPENRC_TELEMETRY_AGGREGATES_DIR") else None),
            schema_dir=Path(env.get("OPENRC_TELEMETRY_SCHEMA_DIR") or DEFAULT_SCHEMA_DIR),
            releases=releases,
            suspended_releases=suspended,
            suspend_all=env.get("OPENRC_TELEMETRY_SUSPEND_ALL") == "1",
            purge_interval_s=interval,
            trust_proxy=env.get("OPENRC_TELEMETRY_TRUST_PROXY") == "1",
            client_burst=_float(env, "OPENRC_TELEMETRY_CLIENT_BURST", defaults.client_burst),
            client_refill_per_s=_float(env, "OPENRC_TELEMETRY_CLIENT_REFILL_PER_S", defaults.client_refill_per_s),
            global_burst=_float(env, "OPENRC_TELEMETRY_GLOBAL_BURST", defaults.global_burst),
            global_refill_per_s=_float(env, "OPENRC_TELEMETRY_GLOBAL_REFILL_PER_S", defaults.global_refill_per_s),
            max_clients=_int(env, "OPENRC_TELEMETRY_MAX_CLIENTS", defaults.max_clients),
            max_raw_bytes=_int(env, "OPENRC_TELEMETRY_MAX_RAW_BYTES", defaults.max_raw_bytes),
            report_token=env.get("OPENRC_TELEMETRY_REPORT_TOKEN", ""),
            github_api=env.get("OPENRC_TELEMETRY_GITHUB_API") or defaults.github_api,
            bot_author=env.get("OPENRC_TELEMETRY_BOT_AUTHOR", ""),
            issue_label=env.get("OPENRC_TELEMETRY_ISSUE_LABEL") or defaults.issue_label,
        )
