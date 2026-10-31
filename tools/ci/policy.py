"""Conservative CI selection and required-job verification (standard library only).

Selection remains in shadow mode until the rollout evidence is accepted. A
recommendation never authorizes skipping a production gate in this version.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

FORMAT = "openrc-ci-selection-v2"
SHADOW = True
SHA = re.compile(r"[0-9a-f]{40}\Z")
SAFE_DOCS = frozenset({"docs/README.md", "docs/TOOLS.md",
                       "docs/DESKTOP-DELIVERY-PLAN.md", "CONTRIBUTING.md", "AGENTS.md",
                       "docs/plans/release-ci-efficiency.md"})
PRODUCTION = ("app", "visuals", "native-linux", "native-windows", "native-kernel-linux")
JOBS = (*PRODUCTION, "three", "site", "export")


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode("utf-8")


def recommend(paths: list[str], *, force: bool = False) -> dict[str, bool]:
    selected = dict(production=False, prototype=False, site=False)
    if force or not paths:
        return dict.fromkeys(selected, True)
    for name in paths:
        if name in SAFE_DOCS:
            continue
        if name.startswith("site/"):
            selected["site"] = True
        elif name.startswith("prototypes/stage0/three/"):
            selected["prototype"] = True
        else:
            # Includes hashed Markdown, shared tooling, locks and unknown paths.
            # Unknown dependencies require the union, not production alone.
            selected = dict.fromkeys(selected, True)
    return selected


def changed_paths(root: Path, event: str, ref: str, sha: str,
                  payload: dict, fetch: bool) -> tuple[str, str, list[str], str]:
    if not SHA.fullmatch(sha) or git(root, "rev-parse", "HEAD").strip() != sha:
        raise ValueError("checked-out source does not match the event SHA")
    if ref.startswith("refs/tags/") or event not in {"push", "pull_request"}:
        return "", sha, [], "tag/manual/other event requires full checks"
    if not isinstance(payload, dict):
        raise ValueError("event payload must be an object")
    head = sha
    base = payload.get("before", "")
    if event == "pull_request":
        pr = payload.get("pull_request", {})
        if not isinstance(pr, dict):
            return "", "", [], "missing PR identities"
        base_data, head_data = pr.get("base"), pr.get("head")
        if not isinstance(base_data, dict) or not isinstance(head_data, dict):
            return "", "", [], "missing PR identities"
        base = base_data.get("sha", "")
        head = head_data.get("sha", "")
        number = payload.get("number")
        if (not isinstance(head, str) or not SHA.fullmatch(head) or
                not isinstance(base, str) or not SHA.fullmatch(base) or
                type(number) is not int or number < 1 or ref != f"refs/pull/{number}/merge"):
            return "", "", [], "missing PR identities"
        try:
            parents = git(root, "show", "-s", "--format=%P", sha).strip().split()
        except subprocess.CalledProcessError:
            return "", head, [], "merge identity unavailable"
        if parents != [base, head]:
            return "", head, [], "PR merge parents do not match the event"
    elif (ref != "refs/heads/main" or payload.get("ref") != ref or
          payload.get("after") != sha or payload.get("deleted") is not False):
        return "", head, [], "push metadata does not match the event"
    if not isinstance(base, str) or not SHA.fullmatch(base) or base == "0" * 40:
        return "", head, [], "missing comparison base"
    try:
        git(root, "cat-file", "-e", base + "^{commit}")
    except subprocess.CalledProcessError:
        if fetch:
            try:
                git(root, "fetch", "--no-tags", "--depth=1", "origin", base)
            except subprocess.CalledProcessError:
                return base, head, [], "comparison history unavailable"
        else:
            return base, head, [], "comparison history unavailable"
    # Any execution, decoding or malformed diff is fatal, not a docs-only result.
    raw = git(root, "diff", "--no-renames", "--no-ext-diff", "--no-textconv",
              "--ignore-submodules=none", "--raw", "-z", base, sha)
    if not raw:
        return base, head, [], "empty comparison"
    parts = raw.split("\0")
    if parts[-1] != "" or len(parts) % 2 != 1:
        raise ValueError("invalid Git diff inventory")
    paths, regular_changes = [], True
    for index in range(0, len(parts) - 1, 2):
        metadata, name = parts[index:index + 2]
        match = re.fullmatch(r":(\d{6}) (\d{6}) [0-9a-f]+ [0-9a-f]+ ([A-Z])", metadata)
        if not match or not name or name.startswith("/") or any(
                part in {"", ".", ".."} for part in name.split("/")):
            raise ValueError("invalid Git diff entry")
        old_mode, new_mode, status = match.groups()
        regular_changes &= status in {"A", "M"} and new_mode == "100644" and old_mode in {"000000", "100644"}
        paths.append(name)
    if len(paths) != len(set(paths)):
        raise ValueError("duplicate Git diff entry")
    reason = "changed paths" if regular_changes else "deletion or non-regular change requires full checks"
    return base, head, sorted(paths), reason


def selection(root: Path, event: str, ref: str, sha: str, payload: dict,
              fetch: bool = False) -> dict:
    base, head, paths, reason = changed_paths(root, event, ref, sha, payload, fetch)
    proposed = recommend(paths, force=reason != "changed paths")
    effective = {**proposed}
    if SHADOW:
        effective.update(production=True, prototype=True)
    export = effective["production"] and (ref == "refs/heads/main" or
                                            ref.startswith("refs/tags/v") or
                                            event == "workflow_dispatch")
    required = {job: effective["production"] for job in PRODUCTION}
    required.update(three=effective["prototype"], site=effective["site"], export=export)
    return {"format": FORMAT, "mode": "shadow" if SHADOW else "active",
            "sha": sha, "event": event, "ref": ref, "base": base, "head": head,
            "paths": paths, "reason": reason, "recommended": proposed,
            "required": required,
            "policy_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}


def validate(receipt: dict, root: Path, sha: str, event: str, ref: str,
             payload: dict, fetch: bool = False) -> None:
    fields = {"format", "mode", "sha", "event", "ref", "base", "head", "paths", "reason",
              "recommended", "required", "policy_sha256"}
    if not isinstance(receipt, dict) or set(receipt) != fields:
        raise ValueError("invalid selection receipt fields")
    if (receipt["format"] != FORMAT or receipt["sha"] != sha or
            receipt["event"] != event or receipt["ref"] != ref or not SHA.fullmatch(sha)):
        raise ValueError("selection receipt event/source mismatch")
    if receipt["mode"] != ("shadow" if SHADOW else "active"):
        raise ValueError("selection mode mismatch")
    if receipt["policy_sha256"] != hashlib.sha256(Path(__file__).read_bytes()).hexdigest():
        raise ValueError("selection policy changed")
    paths = receipt["paths"]
    if (not isinstance(paths, list) or any(not isinstance(p, str) or not p for p in paths)
            or paths != sorted(set(paths))):
        raise ValueError("invalid changed-path inventory")
    for key in ("recommended", "required"):
        if not isinstance(receipt[key], dict) or any(type(v) is not bool for v in receipt[key].values()):
            raise ValueError(f"invalid {key} selection")
    # Recompute from the event and checkout, never from a receipt-controlled base.
    if receipt != selection(root, event, ref, sha, payload, fetch=fetch):
        raise ValueError("selection receipt differs from event and Git history")


def verify(receipt: dict, needs: dict, root: Path, sha: str, event: str, ref: str,
           payload: dict, fetch: bool = False) -> None:
    validate(receipt, root, sha, event, ref, payload, fetch=fetch)
    if (not isinstance(needs, dict) or set(needs) != {"scope", *JOBS} or
            any(not isinstance(row, dict) for row in needs.values()) or
            needs["scope"].get("result") != "success"):
        raise ValueError("scope failed or required job inventory differs")
    for job, required in receipt["required"].items():
        result = needs[job].get("result")
        accepted = {"success"} if required else {"skipped", "success"}
        if result not in accepted:
            raise ValueError(f"{job}: unexpected {result!r} (required={required})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("scope", "verify"))
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    sha, event, ref = (os.environ[k] for k in ("GITHUB_SHA", "GITHUB_EVENT_NAME", "GITHUB_REF"))
    payload = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
    if args.command == "scope":
        receipt = selection(args.root, event, ref, sha, payload, fetch=True)
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        with args.receipt.open("x", encoding="utf-8", newline="\n") as out:
            json.dump(receipt, out, indent=2, sort_keys=True)
            out.write("\n")
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            for name, value in receipt["required"].items():
                out.write(f"{name}={str(value).lower()}\n")
        print(json.dumps(receipt, indent=2))
    else:
        if git(args.root, "rev-parse", "HEAD").strip() != sha:
            raise ValueError("gate checkout does not match source")
        verify(json.loads(args.receipt.read_text(encoding="utf-8")),
               json.loads(os.environ["CI_NEEDS"]), args.root, sha, event, ref, payload, fetch=True)
        print("Required CI jobs passed; selection receipt verified.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"CI policy refused: {error}", file=sys.stderr)
        sys.exit(1)
