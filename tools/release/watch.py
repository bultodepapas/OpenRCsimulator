#!/usr/bin/env python3
"""Read-only, bounded watch of one explicitly identified release CI run."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time


GATES = {"CI required", "Release builds (Windows, Linux, macOS)", "GitHub release (v* tags)"}
TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?\Z")
SHA = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")


class InvalidData(ValueError):
    """Identity mismatch or malformed API data; do not continue."""


class TransportError(Exception):
    """A bounded request failed or pagination changed while being read."""


def require(condition, message):
    if not condition:
        raise InvalidData(message)


def gh_json(endpoint, timeout):
    env = os.environ.copy()
    env.pop("GH_DEBUG", None)
    env["GH_PROMPT_DISABLED"] = "1"
    try:
        result = subprocess.run(["gh", "api", "--hostname", "github.com", "--method", "GET", endpoint],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
                                timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise TransportError("GitHub request failed or timed out") from error
    if result.returncode:
        # gh stderr may contain sensitive details; never copy it into this tool's output.
        raise TransportError(f"GitHub request failed (gh exit {result.returncode})")
    try:
        return json.loads(result.stdout)
    except (UnicodeDecodeError, ValueError) as error:
        raise InvalidData("GitHub returned invalid JSON") from error


def request(api, endpoint, deadline, clock):
    remaining = deadline - clock()
    if remaining <= 0:
        raise TimeoutError
    return api(endpoint, min(30.0, remaining))


def verify_tag(args, api, deadline, clock):
    base = f"repos/{args.repository}"
    ref = request(api, f"{base}/git/ref/tags/{args.expected_tag}", deadline, clock)
    require(isinstance(ref, dict) and ref.get("ref") == f"refs/tags/{args.expected_tag}",
            "tag ref differs")
    obj = ref.get("object")
    require(isinstance(obj, dict) and obj.get("type") == "tag", "expected an annotated tag")
    visited = set()
    for depth in range(5):
        tag_sha = obj.get("sha")
        require(isinstance(tag_sha, str) and SHA.fullmatch(tag_sha) and tag_sha not in visited,
                "invalid or cyclic annotated tag")
        visited.add(tag_sha)
        tag = request(api, f"{base}/git/tags/{tag_sha}", deadline, clock)
        require(isinstance(tag, dict) and tag.get("sha") == tag_sha, "tag object differs")
        if depth == 0:
            require(tag.get("tag") == args.expected_tag, "annotated tag name differs")
        obj = tag.get("object")
        require(isinstance(obj, dict), "invalid annotated tag target")
        if obj.get("type") == "commit":
            require(obj.get("sha") == args.expected_commit, "tag does not point to expected commit")
            return
        require(obj.get("type") == "tag", "annotated tag does not target a commit")
    raise InvalidData("annotated tag nesting exceeds limit")


def check_run(args, run):
    require(isinstance(run, dict), "invalid workflow run")
    repo = run.get("repository")
    require(run.get("id") == args.run_id, "workflow run ID differs")
    require(isinstance(repo, dict) and isinstance(repo.get("full_name"), str)
            and repo["full_name"].casefold() == args.repository.casefold(), "repository differs")
    require(run.get("head_sha") == args.expected_commit, "run commit differs")
    require(run.get("head_branch") == args.expected_tag, "run ref name differs")
    require(run.get("event") == "push", "run event is not push")
    require(run.get("path") == ".github/workflows/ci.yml", "workflow path differs")
    require(type(run.get("run_attempt")) is int and run["run_attempt"] > 0, "invalid run attempt")
    require(isinstance(run.get("status"), str) and "conclusion" in run and
            (run["conclusion"] is None or isinstance(run["conclusion"], str)), "invalid run status")


def read_jobs(args, api, deadline, clock):
    base = f"repos/{args.repository}/actions/runs/{args.run_id}/jobs"
    jobs, seen, expected = [], set(), None
    for page in range(1, 52):
        data = request(api, f"{base}?per_page=100&filter=latest&page={page}", deadline, clock)
        require(isinstance(data, dict) and type(data.get("total_count")) is int
                and 0 <= data["total_count"] <= 5000 and isinstance(data.get("jobs"), list)
                and len(data["jobs"]) <= 100, "invalid jobs page")
        if expected is not None and data["total_count"] != expected:
            raise TransportError("jobs changed during pagination")
        expected = data["total_count"]
        for job in data["jobs"]:
            require(isinstance(job, dict) and type(job.get("id")) is int and job["id"] > 0
                    and job.get("run_id") == args.run_id and isinstance(job.get("name"), str)
                    and isinstance(job.get("status"), str) and isinstance(job.get("steps"), list)
                    and "conclusion" in job
                    and (job["conclusion"] is None or isinstance(job["conclusion"], str)),
                    "invalid job")
            if job["id"] in seen:
                raise TransportError("duplicate job during pagination")
            seen.add(job["id"])
            for step in job["steps"]:
                require(isinstance(step, dict) and type(step.get("number")) is int
                        and isinstance(step.get("name"), str) and "conclusion" in step
                        and (step["conclusion"] is None or isinstance(step["conclusion"], str)),
                        "invalid job step")
            jobs.append(job)
        if len(jobs) == expected:
            return jobs
        if len(jobs) > expected or not data["jobs"]:
            raise TransportError("incomplete jobs pagination")
    raise InvalidData("jobs pagination exceeds limit")


def read_snapshot(args, api, deadline, clock):
    endpoint = f"repos/{args.repository}/actions/runs/{args.run_id}"
    first = request(api, endpoint, deadline, clock)
    check_run(args, first)
    jobs = read_jobs(args, api, deadline, clock)
    last = request(api, endpoint, deadline, clock)
    check_run(args, last)
    if first["run_attempt"] != last["run_attempt"]:
        raise TransportError("run attempt changed while reading jobs")
    if (first["status"], first["conclusion"]) != (last["status"], last["conclusion"]):
        raise TransportError("run changed while reading jobs")
    return last, jobs


def clean(value):
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", value)[:160]


def alert_failures(args, jobs, alerted, err):
    gate_failed = False
    for job in jobs:
        failed_steps = [step for step in job["steps"] if step["conclusion"] == "failure"]
        job_failed = job["conclusion"] in ("failure", "timed_out", "startup_failure", "action_required")
        if job_failed and job["name"] in GATES:
            gate_failed = True
        failures = [(f"step {step['number']}: {clean(step['name'])}", (job["id"], step["number"]))
                    for step in failed_steps]
        if job_failed:
            failures.append((f"job conclusion: {job['conclusion']}", (job["id"], "job")))
        for detail, key in failures:
            if key in alerted:
                continue
            alerted.add(key)
            url = f"https://github.com/{args.repository}/actions/runs/{args.run_id}/job/{job['id']}"
            print(f"ALERT: {clean(job['name'])} ({job['id']}) {detail}; {url}\n"
                  f"  When logs are available: gh run view {args.run_id} --repo {args.repository} "
                  f"--job {job['id']} --log", file=err, flush=True)
    return gate_failed


def watch(args, *, api=gh_json, clock=time.monotonic, sleep=time.sleep, out=sys.stdout, err=sys.stderr):
    deadline = clock() + args.timeout_seconds
    verified_tag, attempt, previous, alerted = False, None, None, set()
    interval, errors = args.poll_seconds, 0
    while True:
        if clock() >= deadline:
            print("TIMEOUT: observation deadline reached; the run may still be active", file=err, flush=True)
            return 5
        try:
            if not verified_tag:
                verify_tag(args, api, deadline, clock)
            run, jobs = read_snapshot(args, api, deadline, clock)
            if attempt is not None:
                require(run["run_attempt"] == attempt, "run attempt changed; restart to inspect the new attempt")
            if run["status"] == "completed" and run["conclusion"] in ("success", "failure"):
                verify_tag(args, api, deadline, clock)
            verified_tag = True
        except TimeoutError:
            print("TIMEOUT: observation deadline reached; the run may still be active", file=err, flush=True)
            return 5
        except InvalidData as error:
            print(f"ERROR: {error}", file=err, flush=True)
            return 2
        except TransportError as error:
            errors += 1
            if errors == 1:
                print(f"ALERT: {error}; retrying within the deadline", file=err, flush=True)
            if args.once or errors >= 3:
                print("ERROR: GitHub observation unavailable; inspect authentication/network and retry",
                      file=err, flush=True)
                return 6
            remaining = deadline - clock()
            if remaining <= 0:
                continue
            sleep(min(5 * 2 ** (errors - 1), remaining))
            continue
        if errors:
            print("GitHub observation recovered", file=out, flush=True)
            errors = 0
        if attempt is None:
            attempt = run["run_attempt"]
            print("Matched run fields and annotated tag commit; the run API does not prove ref type.",
                  file=out, flush=True)
        signature = (run["status"], run["conclusion"],
                     tuple(sorted((job["id"], job["status"], job["conclusion"]) for job in jobs)))
        if signature != previous:
            done = sum(job["status"] == "completed" for job in jobs)
            print(f"Run {args.run_id} attempt {attempt}: {run['status']}"
                  f"{('/' + run['conclusion']) if run['conclusion'] else ''}; jobs {done}/{len(jobs)} complete",
                  file=out, flush=True)
            interval = args.poll_seconds
        else:
            interval = min(args.max_poll_seconds, interval * 1.5)
        previous = signature
        gate_failed = alert_failures(args, jobs, alerted, err)
        if run["status"] == "completed" and run["conclusion"] == "cancelled":
            print("CANCELLED: workflow run was cancelled", file=err, flush=True)
            return 3
        if gate_failed:
            print("FAILURE: a release gate job failed", file=err, flush=True)
            return 1
        for job in jobs:
            if job["name"] in GATES and job["conclusion"] in ("cancelled", "skipped"):
                print(f"{job['conclusion'].upper()}: release gate {job['name']}", file=err, flush=True)
                return 3 if job["conclusion"] == "cancelled" else 4
        if run["status"] == "completed":
            conclusion = run["conclusion"]
            if conclusion == "skipped":
                print("SKIPPED: workflow run was skipped", file=err, flush=True)
                return 4
            if conclusion not in ("success", "failure"):
                print(f"INCONCLUSIVE: workflow conclusion is {clean(str(conclusion))}", file=err, flush=True)
                return 8
            for gate in sorted(GATES):
                matching = [job for job in jobs if job["name"] == gate]
                if len(matching) != 1 or matching[0]["status"] != "completed":
                    label = "FAILURE" if conclusion == "failure" else "INCONCLUSIVE"
                    print(f"{label}: missing, ambiguous or incomplete gate: {gate}", file=err, flush=True)
                    return 1 if conclusion == "failure" else 8
                if matching[0]["conclusion"] != "success":
                    label = "FAILURE" if conclusion == "failure" else "INCONCLUSIVE"
                    print(f"{label}: release gate {gate} did not succeed", file=err, flush=True)
                    return 1 if conclusion == "failure" else 8
            print(f"SUCCESS: all three release gates succeeded; overall workflow conclusion: {conclusion}. "
                  "Published assets and bytes are not verified here.", file=out, flush=True)
            return 0
        if args.once:
            print("PENDING: run has not completed", file=out, flush=True)
            return 7
        remaining = deadline - clock()
        if remaining > 0:
            sleep(min(interval, remaining))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog="""Exit codes:
  0  Terminal run; all three release gate jobs succeeded (overall run may have failed).
  1  Release gate failed, or the run failed without all gates succeeding.
  2  Invalid arguments, identity mismatch or malformed API response.
  3  Workflow or release gate cancelled.
  4  Workflow or release gate skipped.
  5  Observation deadline reached.
  6  GitHub request failed or a coherent snapshot could not be obtained.
  7  --once observed an unfinished run.
  8  Completed run or required gate outcome is inconclusive.

Gate success does not verify the published release or its bytes.""")
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--expected-tag", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--once", action="store_true", help="inspect once without sleeping")
    parser.add_argument("--poll-seconds", type=int, default=60, help="initial interval, at least 5 (default: 60)")
    parser.add_argument("--max-poll-seconds", type=int, default=300,
                        help="maximum interval, at most 300 (default: 300)")
    parser.add_argument("--timeout-seconds", type=int, default=21600,
                        help="deadline, at most 21600 (default: 21600)")
    args = parser.parse_args(argv)
    if (args.run_id <= 0 or not SHA.fullmatch(args.expected_commit) or not TAG.fullmatch(args.expected_tag)
            or not REPOSITORY.fullmatch(args.repository)):
        parser.error("supply a positive run ID, full lowercase commit, release tag and owner/repository")
    if not (5 <= args.poll_seconds <= args.max_poll_seconds <= 300 and 1 <= args.timeout_seconds <= 21600):
        parser.error("require 5 <= poll <= max poll <= 300 and 1 <= timeout <= 21600 seconds")
    return watch(args)


if __name__ == "__main__":
    sys.exit(main())
