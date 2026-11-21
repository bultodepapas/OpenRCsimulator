"""Read the served health report from an independent host and fail on stale or unhealthy builds."""
import argparse
from datetime import datetime, timezone
import json
import sys
from urllib.request import Request, urlopen


def check(report, now, max_age):
    if not isinstance(report, dict):
        raise ValueError("expected a JSON object")
    stamp = datetime.fromisoformat(report["built_utc"])
    if stamp.tzinfo is None:
        raise ValueError("build timestamp has no timezone")
    age = (now - stamp).total_seconds()
    if age < -300 or age > max_age:
        return f"dashboard build age {age:.0f}s is outside -300..{max_age}s"
    sources = report["sources"]
    if not isinstance(sources, dict) or not sources:
        raise ValueError("missing source health")
    unhealthy = ", ".join(f"{key}={value['status']}" for key, value in sources.items()
                          if value["status"] not in ("ok", "disabled"))
    receiver = ", ".join(report.get("receiver_issues", []))
    if report.get("status") != "ok" or unhealthy or receiver:
        detail = ", ".join(filter(None, (unhealthy, receiver)))
        return f"dashboard status {report.get('status')!r}" + (f" ({detail})" if detail else "")
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="private dashboard health.json URL")
    parser.add_argument("--max-age", type=int, default=2 * 3600)
    args = parser.parse_args(argv)
    try:
        req = Request(args.url, headers={"Cache-Control": "no-cache"})
        with urlopen(req, timeout=10) as response:
            report = json.loads(response.read(32_769))
        failure = check(report, datetime.now(timezone.utc), args.max_age)
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        failure = f"dashboard health check failed: {error}"
    if failure:
        print(failure, file=sys.stderr)
        return 1
    print(f"dashboard healthy, built {report['built_utc']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
