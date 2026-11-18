"""Offline publication protocol model; no GitHub client or durable store.

Demonstrates frozen disclosures and preservation of an uncertain create outcome.
A production adapter still needs authenticated approval, durable intent before
any remote write, single-writer coordination, and verified complete discovery.
"""
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
import json
import re

from reference import ContractError, render_report, validate_report


def canonical_repository(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}", value):
        raise ContractError("destination")
    return value.lower()


def canonical_author(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,100}(?:\[bot\])?", value):
        raise ContractError("publication_author")
    return value.lower()


@dataclass(frozen=True)
class Policy:
    repository: str
    bot_author: str
    approved_releases: frozenset[str]
    audience: str = "private"

    def __post_init__(self):
        object.__setattr__(self, "repository", canonical_repository(self.repository))
        object.__setattr__(self, "bot_author", canonical_author(self.bot_author))
        if self.audience not in ("private", "public"):
            raise ContractError("publication_policy")
        if (not isinstance(self.approved_releases, frozenset) or not self.approved_releases or
            any(not isinstance(release, str) for release in self.approved_releases)):
            raise ContractError("release_policy")


@dataclass(frozen=True)
class Approval:
    """Trusted review receipt in the model; not an authentication mechanism."""
    key: str
    repository: str
    bot_author: str
    digest: str
    inventory_digest: str


@dataclass(frozen=True)
class RemoteIssue:
    repository: str
    number: int
    author: str
    title: str
    body: str
    is_pull_request: bool


@dataclass(frozen=True)
class Decision:
    action: str
    key: str
    token: int | None = None
    body: str | None = None
    issue_number: int | None = None
    title: str | None = None


@dataclass
class Entry:
    policy: Policy
    key: str
    digest: str
    title: str
    body: str
    token: int
    state: str = "creating"
    issue_number: int | None = None
    inventory_digest: str | None = None


def report_title(report):
    return f"OpenRC telemetry: {report['day']} / {report['release_id']} / daily GPU v1"


def material(report):
    """Only the fixed daily report schema can reach this renderer."""
    validate_report(report)
    key = f"daily-gpu-v1/{report['day']}/{report['release_id']}"
    body = f"<!-- openrc-telemetry:{key} -->\n" + render_report(report)
    artifact = json.dumps({"title": report_title(report), "body": body},
                          sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return key, body, sha256(artifact.encode("utf-8")).hexdigest()


def closed_day(report, as_of_utc):
    try:
        current = datetime.fromisoformat(as_of_utc.replace("Z", "+00:00"))
        day = datetime.combine(date.fromisoformat(report["day"]), datetime.min.time(), timezone.utc)
        if current.utcoffset() != timedelta(0) or current < day + timedelta(hours=25):
            raise ValueError
    except (ValueError, TypeError, AttributeError, OverflowError):
        raise ContractError("publication_day") from None


class PublicationModel:
    """Sequential in-memory intent ledger, not a lock or exactly-once service."""
    def __init__(self):
        self.entries = {}
        self.serial = 0

    def inventory_digest(self):
        """All known public intents, including pending/unknown; no completeness proof."""
        inventory = [{"repository": entry.policy.repository, "key": entry.key,
                      "digest": entry.digest, "author": entry.policy.bot_author,
                      "state": entry.state, "issue": entry.issue_number}
                     for _, entry in sorted(self.entries.items())
                     if entry.policy.audience == "public"]
        body = json.dumps(inventory, sort_keys=True, separators=(",", ":"))
        return sha256(body.encode("utf-8")).hexdigest()

    def prepare(self, report, policy, *, as_of_utc, expected_key, approval=None):
        key, body, digest = material(report)
        title = report_title(report)
        closed_day(report, as_of_utc)
        if report["release_id"] not in policy.approved_releases:
            raise ContractError("unapproved_release")
        if expected_key != key:
            raise ContractError("unexpected_report")
        identity = (policy.repository, key)
        previous = self.entries.get(identity)
        if previous:
            if previous.state == "review_required":
                return Decision("review_required", key)
            # An audience or author change is a policy change, not a harmless retry.
            if previous.digest != digest or previous.policy != policy:
                return Decision("review_required", key)
            if previous.state == "published":
                return Decision("noop", key, issue_number=previous.issue_number)
            return Decision("reconcile", key)
        inventory = None
        if policy.audience == "public":
            if (not isinstance(approval, Approval) or approval.key != key or
                canonical_repository(approval.repository) != policy.repository or
                canonical_author(approval.bot_author) != policy.bot_author or approval.digest != digest or
                approval.inventory_digest != self.inventory_digest()):
                return Decision("review_required", key)
            inventory = approval.inventory_digest
        self.serial += 1
        self.entries[identity] = Entry(policy, key, digest, title, body, self.serial,
                                       inventory_digest=inventory)
        # Production must durably commit this intent before using the returned body.
        return Decision("create", key, self.serial, body, title=title)

    def uncertain(self, repository, key, token):
        entry = self.entries.get((canonical_repository(repository), key))
        if (not entry or type(token) is not int or entry.token != token or
            entry.state in ("published", "review_required")):
            return False
        entry.state = "unknown"
        return True

    @staticmethod
    def same_publisher(entry, issue):
        if not isinstance(issue, RemoteIssue):
            return False
        try:
            repository = canonical_repository(issue.repository)
            author = canonical_author(issue.author)
        except ContractError:
            return False
        return (issue.is_pull_request is False and
                type(issue.number) is int and issue.number > 0 and
                repository == entry.policy.repository and
                author == entry.policy.bot_author)

    @classmethod
    def matches(cls, entry, issue):
        return (cls.same_publisher(entry, issue) and
                issue.title == entry.title and issue.body == entry.body)

    @classmethod
    def related(cls, entry, issue):
        """Positive collision evidence; never sufficient to authorize binding."""
        if not cls.same_publisher(entry, issue):
            return False
        marker = f"<!-- openrc-telemetry:{entry.key} -->"
        return (issue.number == entry.issue_number or issue.title == entry.title or
                (isinstance(issue.body, str) and marker in issue.body))

    def confirmed(self, repository, key, token, issue):
        entry = self.entries.get((canonical_repository(repository), key))
        if not entry or type(token) is not int or entry.token != token:
            return False
        if entry.state == "review_required":
            return False
        if not self.matches(entry, issue):
            if self.related(entry, issue):
                entry.state = "review_required"
            return False
        if entry.state == "published":
            if entry.issue_number != issue.number:
                entry.state = "review_required"
                return False
            return True
        entry.state, entry.issue_number = "published", issue.number
        return True

    def reconcile(self, repository, key, candidates, *, discovery_complete):
        entry = self.entries.get((canonical_repository(repository), key))
        if entry is None:
            raise ContractError("unknown_intent")
        if entry.state == "review_required":
            return Decision("review_required", key)
        matches = set()
        for issue in candidates:
            if self.matches(entry, issue):
                matches.add(issue.number)
            elif self.related(entry, issue):
                entry.state = "review_required"
                return Decision("review_required", key)
        # Positive conflict evidence survives even an incomplete remote listing.
        if len(matches) > 1:
            entry.state = "review_required"
            return Decision("review_required", key)
        if discovery_complete is not True:
            return Decision("reconcile", key)
        if entry.state == "published":
            if matches == {entry.issue_number}:
                return Decision("noop", key, issue_number=entry.issue_number)
            entry.state = "review_required"
            return Decision("review_required", key)
        if not matches:
            # Even a completed listing cannot prove an earlier write will never finish.
            entry.state = "unknown"
            return Decision("reconcile", key)
        entry.state, entry.issue_number = "published", matches.pop()
        return Decision("noop", key, issue_number=entry.issue_number)
