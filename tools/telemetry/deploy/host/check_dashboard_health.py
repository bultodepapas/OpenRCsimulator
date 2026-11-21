"""Read the served health report from an independent host and fail on stale or unhealthy builds."""
import argparse
from datetime import datetime, timezone
import json
import sys
from urllib.request import Request, urlopen

SOURCE_MAX_AGE = dict.fromkeys(("github_downloads", "github_views", "github_clones",
                               "github_community", "github_referrals", "github_stars"), 12 * 3600)
SOURCE_MAX_AGE["website"] = 2 * 3600


def age_seconds(stamp, now):
    parsed = datetime.fromisoformat(stamp)
    if parsed.tzinfo is None:
        raise ValueError("timestamp has no timezone")
    return (now - parsed).total_seconds()


def check(report, now, max_age):
    if not isinstance(report, dict):
        raise ValueError("expected a JSON object")
    age = age_seconds(report["built_utc"], now)
    if age < -300 or age > max_age:
        return f"dashboard build age {age:.0f}s is outside -300..{max_age}s"
    sources = report["sources"]
    if not isinstance(sources, dict) or SOURCE_MAX_AGE.keys() - sources.keys():
        raise ValueError("missing required source health")
    issues = list(report.get("receiver_issues", []))
    receiver_age = report.get("receiver_age_s")
    if type(receiver_age) is not int or not -300 <= receiver_age + age <= max_age:
        issues.append("receiver snapshot missing or stale")
    for key, max_source_age in SOURCE_MAX_AGE.items():
        source = sources[key]
        if source["status"] != "ok":
            issues.append(f"{key}={source['status']}")
        elif not -300 <= age_seconds(source["observed_utc"], now) <= max_source_age:
            issues.append(f"{key}=stale")
    if report.get("status") != "ok" or issues:
        detail = ", ".join(issues)
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
