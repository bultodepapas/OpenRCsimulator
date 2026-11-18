"""Weekly report publisher with a durable intent ledger and reconcile-before-create.

Follows research/telemetry/publication.py: intent is committed before any remote write, an
unknown create outcome is never retried blindly, and any related-but-different issue or a
duplicate stops with review_required. Only urllib is used for HTTP; the token is never printed.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import re
import socket
import urllib.error
import urllib.request
from urllib.parse import urlparse

from . import report as report_mod
from .contract import ContractError

MAX_PAGES = 50
PER_PAGE = 100
MAX_RESPONSE = 16 * 1024 * 1024


def canonical_repository(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}", value):
        raise ContractError("destination")
    return value.lower()


def canonical_author(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,100}(?:\[bot\])?", value):
        raise ContractError("publication_author")
    return value.lower()


def _normalize(text):
    # GitHub may normalize line endings and trailing whitespace; nothing else is tolerated.
    return text.replace("\r\n", "\n").rstrip() if isinstance(text, str) else None


class GitHubError(Exception):
    """Fixed category: 'timeout', 'network', 'status_<code>' or 'invalid_response'."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class GitHub:
    def __init__(self, api_base, token, timeout=15.0):
        parsed = urlparse(api_base)
        local = parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost")
        if not (parsed.scheme == "https" or local) or not parsed.hostname:
            raise ContractError("github_api")
        self.base = api_base.rstrip("/")
        self._token = token
        self.timeout = timeout
        self._opener = urllib.request.build_opener(_NoRedirect)

    def _request(self, method, path, payload=None):
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(self.base + path, data=data, method=method, headers={
            "Authorization": f"Bearer {self._token}", "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "openrc-telemetry-publisher",
            **({"Content-Type": "application/json"} if data is not None else {})})
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                status, raw = response.status, response.read(MAX_RESPONSE + 1)
        except urllib.error.HTTPError as exc:
            exc.close()
            raise GitHubError(f"status_{exc.code}") from None
        except (socket.timeout, TimeoutError):
            raise GitHubError("timeout") from None
        except (urllib.error.URLError, OSError, ValueError):
            # http.client errors (RemoteDisconnected etc.) are OSError subclasses.
            raise GitHubError("network") from None
        if len(raw) > MAX_RESPONSE:
            raise GitHubError("invalid_response")
        return status, raw

    def list_issues(self, repository, max_pages=MAX_PAGES):
        """(issues, complete). Incomplete on any error or when the page bound is reached."""
        issues = []
        for page in range(1, max_pages + 1):
            try:
                status, raw = self._request(
                    "GET", f"/repos/{repository}/issues?state=all&per_page={PER_PAGE}&page={page}")
                batch = json.loads(raw.decode("utf-8"))
            except (GitHubError, ValueError, UnicodeError):
                return issues, False
            if status != 200 or not isinstance(batch, list):
                return issues, False
            issues.extend(batch)
            if len(batch) < PER_PAGE:
                return issues, True
        return issues, False

    def create_issue(self, repository, title, body, label):
        """('created', issue) | ('rejected', None) definitive no-create | ('unknown', None)."""
        payload = {"title": title, "body": body, "labels": [label]}
        try:
            status, raw = self._request("POST", f"/repos/{repository}/issues", payload)
        except GitHubError as error:
            category = str(error)
            if category.startswith("status_"):
                code = int(category[7:])
                # 408 and 5xx may follow a processed write; other 4xx are definitive refusals.
                if 400 <= code < 500 and code != 408:
                    return "rejected", None
            return "unknown", None
        try:
            issue = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeError):
            return "unknown", None
        if status != 201 or not isinstance(issue, dict):
            return "unknown", None
        return "created", issue


@dataclass
class Result:
    outcome: str
    message: str
    issue_number: int | None = None

    @property
    def exit_code(self):
        return {"dry_run": 0, "published": 0, "noop": 0, "digest_mismatch": 2, "not_closed": 2,
                "config_error": 2, "review_required": 3, "unknown": 4, "pending": 4, "rejected": 5}[self.outcome]


def _issue_view(issue, bot_author):
    """Normalized fields of a remote issue, or None for anything that is not an ordinary issue."""
    if not isinstance(issue, dict) or "pull_request" in issue:
        return None
    number, user = issue.get("number"), issue.get("user")
    login = user.get("login") if isinstance(user, dict) else None
    try:
        author = canonical_author(login)
    except ContractError:
        return None
    if type(number) is not int or number <= 0 or author != bot_author:
        return None
    return {"number": number, "title": issue.get("title"), "body": issue.get("body")}


def _classify(issues, title, body, key, bot_author, known_number):
    """(exact_numbers, related_conflict) following publication.matches/related."""
    marker = f"<!-- openrc-telemetry:{key} -->"
    exact, related = set(), False
    for issue in issues:
        view = _issue_view(issue, bot_author)
        if view is None:
            continue
        if view["title"] == title and _normalize(view["body"]) == _normalize(body):
            exact.add(view["number"])
        elif (view["number"] == known_number or view["title"] == title or
              (isinstance(view["body"], str) and marker in view["body"])):
            related = True
    return exact, related


def publish(agg, contracts, *, week, release, repository, approved_digest, execute, now,
            releases, bot_author="", label="telemetry", github=None):
    """Recompute, verify the approved digest, record intent, reconcile, then create at most once."""
    repo = canonical_repository(repository)
    report_mod.parse_week(week)
    report_mod.check_release(release)
    if releases and release not in releases:
        raise ContractError("unapproved_release")
    title, body, digest = report_mod.material(contracts, agg, week, release)
    if digest != approved_digest:
        return Result("digest_mismatch", "approved digest does not match the recomputed report; nothing written")
    if not report_mod.week_closed(week, now):
        return Result("not_closed", "week is not yet closed (final day close + 1 h); nothing written")
    key = report_mod.report_key(week, release)
    if not execute:
        known = agg.get_publication(repo, key)
        state = known["state"] if known else "none"
        return Result("dry_run", f"dry-run: would post to {repo} (intent state: {state}); title: {title!r}; "
                                 f"body bytes: {len(body.encode('utf-8'))}; digest: {digest}")
    if github is None or not bot_author:
        return Result("config_error", "execute needs GITHUB_TOKEN and OPENRC_TELEMETRY_BOT_AUTHOR")
    author = canonical_author(bot_author)

    intent = agg.get_publication(repo, key)
    if intent is not None:
        if intent["state"] == "review_required":
            return Result("review_required", "earlier review_required is sticky; resolve manually")
        if intent["digest"] != digest or intent["bot_author"] != author:
            agg.update_publication(repo, key, now, state="review_required")
            return Result("review_required", "report digest or publisher changed since the recorded intent")
        if intent["state"] == "published":
            return Result("noop", "already published", intent["issue_number"])
    else:
        # Durable intent BEFORE any remote interaction.
        agg.create_publication(repo, key, digest, title, body, author, now)
        intent = agg.get_publication(repo, key)

    issues, complete = github.list_issues(repo)
    exact, related = _classify(issues, title, body, key, author, intent["issue_number"])
    if related or len(exact) > 1:
        agg.update_publication(repo, key, now, state="review_required")
        return Result("review_required", "related or duplicate issue found; stopped for review")
    if not complete:
        return Result("pending", "issue discovery incomplete; rerun to reconcile (no create attempted)")
    if exact:
        number = exact.pop()
        agg.update_publication(repo, key, now, state="published", issue_number=number)
        return Result("published", f"reconciled with existing issue #{number}", number)
    if intent["create_attempts"] > 0:
        agg.update_publication(repo, key, now, state="unknown")
        return Result("unknown", "a previous create has an unknown outcome and no issue is visible yet; "
                                 "not creating again, rerun later to reconcile")

    # Mark the attempt durable before the single create request.
    agg.update_publication(repo, key, now, state="creating", create_attempts=1)
    outcome, issue = github.create_issue(repo, title, body, label)
    if outcome == "created":
        view = _issue_view(issue, author)
        if view is None or view["title"] != title or _normalize(view["body"]) != _normalize(body):
            agg.update_publication(repo, key, now, state="review_required")
            return Result("review_required", "created issue does not match the frozen report")
        agg.update_publication(repo, key, now, state="published", issue_number=view["number"])
        return Result("published", f"created issue #{view['number']}", view["number"])
    if outcome == "rejected":
        agg.update_publication(repo, key, now, state="creating", create_attempts=0)
        return Result("rejected", "GitHub refused the create request; nothing was created")
    agg.update_publication(repo, key, now, state="unknown")
    return Result("unknown", "create outcome unknown; rerun later to reconcile instead of creating again")
