#!/usr/bin/env python3
"""Static VRC plan/data verification. Does not launch Godot or qualify controls."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / "docs/research/vehicle-runtime-consolidation-2026-11-21"
PLAN = ROOT / "docs/plans/vehicle-runtime-consolidation.md"
BASE = "57abea025f62b20233ca281d58d2acbee4ab8b8e"
REVIEWED_PLAN = "542d92b304fc3b82678c4a90b848a88d82df0b22"
PRIOR_AUDIT = "895dd4352c5191f1539a8b8f4df1996cd33eb86f"
REFINEMENT_BASE = "8d61ca900a30686bc00eaf5ce80bee664e592a46"
VALID_STEPS = {f"VRC-{i:02}" for i in range(12)}
VALID_EXECUTION = {"UNRUN", "PASS", "FAIL", "INCOMPLETE"}


def git(*args: str, allow_error: bool = False) -> bytes:
    result = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True)
    if result.returncode and not allow_error:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return result.stdout


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def source_at(commit: str, path: str) -> bytes:
    return git("show", f"{commit}:{path}")


def matrix_text(data: dict) -> str:
    lines = [
        "# Controls acceptance matrix",
        "",
        "Generated from [control-cases.json](control-cases.json) by "
        "[verify_plan.py](../../../research/vehicle-runtime-consolidation/verify_plan.py) "
        "with `--write-matrix`. Edit the JSON, then regenerate. "
        "This is a proposed case ledger, not executed gameplay evidence.",
        "",
        "The [control contract](CONTROL-CONTRACT.md) defines semantics; "
        "[quality gates](QUALITY-GATES.md) define admission, identities and receipts. "
        "Apply cases only to their touched seams or claimed release scope. "
        "Existing suites are starting points and may need extensions; their names do not prove case coverage. "
        "All cases in this audit revision are **UNRUN**, with no passing runtime receipt.",
        "",
        "| Case | Obligation | VRC steps | Evidence level |",
        "| --- | --- | --- | --- |",
    ]
    for row in data["cases"]:
        lines.append(f'| [{row["id"]}](#{row["id"].lower()}) | {row["title"]} | '
                     f'{", ".join(row["steps"])} | {row["evidence_level"]} |')
    for row in data["cases"]:
        lines.extend([
            "", f'## {row["id"]}', "", f'**{row["title"]}.** '
            f'Owners: {", ".join(row["owners"])}. '
            f'Apply when: {row["when"]}', "",
            f'- **Fixture and trigger:** {row["trigger"]}',
            f'- **Required outcome:** {row["oracle"]}',
            '- **Existing test starting points:** ' +
            (", ".join(f'[{p.removeprefix("app/tests/")}](../../../{p})'
                       for p in row["existing_tests"]) if row["existing_tests"]
             else "No automated witness claimed; follow the named qualification owner") +
            '. The actual case/fixture must be reviewed or implemented before execution.',
            f'- **Evidence:** {row["evidence"]} '
            f'Status: **{row["execution"]["status"]}**; '
            f'receipt: {row["execution"]["receipt"] or "none"}.',
        ])
        if row.get("baseline_findings"):
            lines.append('- **Known baseline:** ' + ", ".join(row["baseline_findings"]) +
                         "; reproduce separately, then assert the repaired oracle.")
    return "\n".join(lines) + "\n"


def headings(text: str) -> set[str]:
    """GitHub-style anchors for the ordinary headings used by this package."""
    found: set[str] = set()
    counts: dict[str, int] = {}
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or not re.match(r"^#{1,6}\s", line):
            continue
        label = re.sub(r"^#{1,6}\s+", "", line).strip().rstrip("#").strip()
        label = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", label).lower()
        anchor = re.sub(r"[^\w\- ]", "", label).replace(" ", "-")
        number = counts.get(anchor, 0)
        counts[anchor] = number + 1
        found.add(anchor if number == 0 else f"{anchor}-{number}")
    return found


def verify_organization(require, checks: dict, case_ids: set[str]) -> list[Path]:
    """Verify dated design maps against Git objects, never infer executed support."""
    mapping_path = HOME / "organization-map.json"
    actions_path = HOME / "action-consumers.json"
    mapping = json.loads(mapping_path.read_text())
    actions = json.loads(actions_path.read_text())
    require(mapping["schema"] == "openrc-vrc-organization-map-v1", "Unknown organization schema")
    require(actions["schema"] == "openrc-vrc-action-consumer-map-v1", "Unknown action-map schema")
    require(mapping["source_commit"] == actions["source_commit"] == BASE, "Organization source mismatch")
    require(mapping["reviewed_plan_commit"] == REFINEMENT_BASE, "Organization review identity mismatch")
    require(git("rev-parse", f"{REFINEMENT_BASE}:app") == git("rev-parse", f"{BASE}:app"),
            "Refinement source app tree differs from baseline")
    for document in (mapping, actions):
        require(document["execution"]["status"] == "UNRUN" and document["execution"]["receipt"] is None,
                "Design map must not claim runtime execution")
    source_ids = [row["id"] for row in mapping["sources"]]
    require(len(source_ids) == len(set(source_ids)), "Duplicate organization source ID")
    symbols_checked = 0
    for source in mapping["sources"]:
        raw = source_at(BASE, source["path"])
        lines = raw.decode().splitlines()
        require(source["sha256"] == hashlib.sha256(raw).hexdigest(), f'Source SHA-256: {source["path"]}')
        require(source["blob_sha"] == git("rev-parse", f'{BASE}:{source["path"]}').decode().strip(),
                f'Source Git blob: {source["path"]}')
        require(source["line_count"] == len(lines), f'Source line count: {source["path"]}')
        names = [entry["name"] for entry in source["symbols"]]
        require(len(names) == len(set(names)), f'Duplicate symbol: {source["path"]}')
        for symbol in source["symbols"]:
            number = symbol["line"]
            valid_line = isinstance(number, int) and 1 <= number <= len(lines)
            require(valid_line, f'Symbol line outside source: {source["path"]}:{symbol["name"]}')
            if valid_line:
                require(lines[number - 1] == symbol["declaration"],
                        f'Symbol declaration mismatch: {source["path"]}:{symbol["name"]}')
                require(bool(re.match(r"^(?:static )?func\s+" + re.escape(symbol["name"]) + r"\(",
                                      lines[number - 1])), f'Symbol name mismatch: {symbol["name"]}')
            require(symbol["url"] == f'https://github.com/bultodepapas/OpenRCsimulator/blob/{BASE}/{source["path"]}#L{number}',
                    f'Symbol URL mismatch: {symbol["name"]}')
            symbols_checked += 1
    for collection in ("routes", "observations", "work_packages", "proposed_paths"):
        for row in mapping[collection]:
            require(set(row.get("source_ids", [])) <= set(source_ids), f'Unknown source in {collection}')
            require(set(row.get("cases", [])) <= case_ids, f'Unknown case in {collection}')
            require(set(row.get("owner_steps", [])) <= VALID_STEPS, f'Unknown step in {collection}')
            if "step" in row:
                require(row["step"] in VALID_STEPS, "Unknown work-package VRC step")
            require("status" not in row, "Work maps must not become a second implementation-status ledger")
    for row in mapping["proposed_paths"]:
        require(bool(row["create_only_if"]), "Proposed module lacks its creation gate")
        require(not git("cat-file", "-t", f'HEAD:{row["path"]}', allow_error=True),
                f'Proposed module presented as absent but already tracked: {row["path"]}')
    for path in mapping["existing_test_starting_points"]:
        require(bool(re.search(r"^extends SceneTree\s*$", source_at(BASE, path).decode(), re.M)),
                f'Organization test is not a SceneTree launcher: {path}')
    catalog_text = source_at(BASE, actions["catalog_path"]).decode()
    block = catalog_text.split("const ACTIONS: Array[Dictionary] = [", 1)[1].split("\n]", 1)[0]
    source_actions = [json.loads(raw) for raw in re.findall(r"\{[^\n]+\}", block)]
    actual_actions = [{key: row[key] for key in ("id", "label", "context", "mode")}
                      for row in actions["catalog"]]
    require(actual_actions == source_actions, "Action catalog differs from pinned definitions")
    for row in actions["catalog"]:
        require(row["consumer_coverage"] == "uncharacterized across activity/route/form combinations",
                f'Unproved consumer coverage for {row["id"]}')
    aux_match = re.search(r"const AUX_CHANNEL_IDS: PackedStringArray = (\[[^\n]+\])", catalog_text)
    require(aux_match is not None and actions["aux_channels"] == json.loads(aux_match[1]),
            "AUX catalog differs from pinned definitions")
    keys = set()
    for row in actions["examples"]:
        key = tuple(row[field] for field in actions["matrix_key"])
        require(key not in keys, "Duplicate action-consumer example")
        keys.add(key)
        require(row["action_id"] in {entry["id"] for entry in source_actions}, "Unknown example action")
        require(set(row["source_ids"]) <= set(source_ids), "Unknown example source")
        require(set(row["cases"]) <= case_ids, "Unknown example case")
        require(row["execution"]["status"] == "UNRUN" and row["execution"]["receipt"] is None,
                "Source action example must not claim a runtime pass")
    historical_receipt = HOME / "verification.json"
    require(historical_receipt.read_bytes() == source_at(REFINEMENT_BASE, relative(historical_receipt)),
            "Original audit receipt was rewritten instead of preserved")
    checks["organization_refinement"] = {
        "reviewed_plan_commit": REFINEMENT_BASE, "source_files": len(source_ids),
        "source_symbols": symbols_checked, "routes": len(mapping["routes"]),
        "source_observations_not_runtime_findings": len(mapping["observations"]),
        "existing_test_starting_points": len(mapping["existing_test_starting_points"]),
        "action_catalog_ids": len(source_actions), "aux_channels": len(actions["aux_channels"]),
        "source_action_examples_unrun": len(actions["examples"]),
        "historical_receipt_preserved": historical_receipt.read_bytes() == source_at(REFINEMENT_BASE, relative(historical_receipt)),
        "semantic_coverage_or_gameplay_execution": False,
    }
    return [mapping_path, actions_path, historical_receipt]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-matrix", action="store_true",
                        help="Regenerate only CONTROL-ACCEPTANCE.md from the canonical case JSON")
    parser.add_argument("--output", type=Path, help="Write a static-check JSON receipt to a new output path")
    args = parser.parse_args()
    errors: list[str] = []
    checks: dict = {}
    inventory = json.loads((HOME / "inventory.json").read_text())
    data = json.loads((HOME / "control-cases.json").read_text())
    findings = json.loads((HOME / "audit-findings.json").read_text())

    def require(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    require(inventory["base_commit"] == BASE, "Inventory baseline mismatch")
    require(data["base_commit"] == BASE and data["reviewed_plan_commit"] == REVIEWED_PLAN,
            "Case identities mismatch")
    require(findings["reviewed_plan_commit"] == REVIEWED_PLAN and findings["base_commit"] == BASE,
            "Finding identities mismatch")
    source_results = []
    for entry in inventory["files"]:
        blob = source_at(BASE, entry["path"])
        text = blob.decode("utf-8")
        actual = {"path": entry["path"], "lines": len(text.splitlines()),
                  "top_level_function_count": len(re.findall(r"^(?:static )?func\s", text, re.M)),
                  "blob_sha": git("rev-parse", f'{BASE}:{entry["path"]}').decode().strip(),
                  "sha256": hashlib.sha256(blob).hexdigest()}
        for key in ("lines", "top_level_function_count", "blob_sha"):
            require(entry[key] == actual[key], f'Inventory {entry["path"]}: wrong {key}')
        table_line = next((line for line in (HOME / "SOURCE-INVENTORY.md").read_text().splitlines()
                           if line.startswith(f'| [`{entry["path"]}`]')), "")
        require(f'| {actual["lines"]:,} | {actual["top_level_function_count"]} |' in table_line,
                f'Inventory Markdown count differs for {entry["path"]}')
        source_results.append(actual)
    checks["inventory"] = source_results

    finding_ids = [r["id"] for r in findings["findings"]]
    require(len(finding_ids) == len(set(finding_ids)), "Duplicate finding IDs")
    ids = [r["id"] for r in data["cases"]]
    require(len(ids) == len(set(ids)), "Duplicate case IDs")
    require(set(ids) == {f"C{i:02}" for i in range(1, 41)}, "Expected C01 through C40")
    test_paths: set[str] = set()
    for row in data["cases"]:
        for field in ("id", "title", "owners", "steps", "when", "trigger", "oracle", "evidence", "evidence_level"):
            require(bool(row.get(field)), f'{row["id"]}: missing {field}')
        require(set(row["steps"]) <= VALID_STEPS, f'{row["id"]}: invalid step')
        require(set(row["review_findings"]) <= set(finding_ids), f'{row["id"]}: unknown review finding')
        for finding_id in row["review_findings"]:
            finding = next((f for f in findings["findings"] if f["id"] == finding_id), None)
            require(finding is not None and row["id"] in finding["cases"],
                    f'{row["id"]}: finding/case reverse reference missing for {finding_id}')
        state = row["execution"]["status"]
        require(state in VALID_EXECUTION, f'{row["id"]}: invalid execution status')
        # This dated audit is a source-only proposal. Runtime results belong in a later evidence record.
        require(state == "UNRUN" and row["execution"]["receipt"] is None,
                f'{row["id"]}: this audit must not fabricate a runtime verdict')
        for path in row["existing_tests"]:
            test_paths.add(path)
            script = source_at(BASE, path).decode()
            require(bool(re.search(r"^extends SceneTree\s*$", script, re.M)),
                    f'{row["id"]}: {path} is not a SceneTree test launcher')
    evidence_hashes = {}
    for finding in findings["findings"]:
        require(set(finding["cases"]) <= set(ids), f'{finding["id"]}: unknown case')
        require(set(finding["cases"]) == {r["id"] for r in data["cases"] if finding["id"] in r["review_findings"]},
                f'{finding["id"]}: case traceability differs')
        require(finding["disposition"] == "addressed_in_plan_runtime_unqualified",
                f'{finding["id"]}: unsupported closure status')
        for evidence in finding["evidence"]:
            source_bytes = source_at(evidence["commit"], evidence["path"])
            evidence_hashes[f'{evidence["commit"]}:{evidence["path"]}'] = hashlib.sha256(source_bytes).hexdigest()
            blob = source_bytes.decode()
            start, end = evidence["lines"]
            require(1 <= start <= end <= len(blob.splitlines()),
                    f'{finding["id"]}: invalid source line range {evidence}')
    execution_counts = {state: sum(row["execution"]["status"] == state for row in data["cases"])
                        for state in sorted(VALID_EXECUTION)}
    checks["cases"] = {"count": len(ids), "execution_counts": execution_counts,
                       "pinned_test_paths_with_scenetree_declaration": sorted(test_paths)}
    checks["findings"] = {"count": len(finding_ids), "identifiers": finding_ids}
    checks["evidence_source_sha256"] = evidence_hashes
    refinement_files = verify_organization(require, checks, set(ids))
    refinement = data.get("organization_refinement", {})
    require(refinement.get("reviewed_plan_commit") == REFINEMENT_BASE, "Case-refinement identity mismatch")
    require(set(refinement.get("changed_cases", [])) <= set(ids), "Unknown refined case")
    checks["organization_refinement"]["refined_cases"] = refinement.get("changed_cases", [])
    expected = matrix_text(data)
    if args.write_matrix:
        if errors:
            print(json.dumps({"ok": False, "matrix_written": False,
                              "execution_counts": execution_counts, "errors": errors}, indent=2))
            return 1
        (HOME / "CONTROL-ACCEPTANCE.md").write_text(expected)
    require((HOME / "CONTROL-ACCEPTANCE.md").read_text() == expected,
            "Generated acceptance matrix differs; regenerate with --write-matrix")

    indices = [ROOT / "docs/README.md", ROOT / "docs/research/README.md"]
    markdown = [PLAN, *sorted(HOME.glob("*.md")), ROOT / "research/vehicle-runtime-consolidation/README.md", *indices]
    verified_links = 0
    external_links: set[str] = set()
    for doc in markdown:
        text = doc.read_text()
        if doc in indices:
            text = "\n".join(line for line in text.splitlines() if "vehicle-runtime-consolidation" in line)
        require(text.count("```") % 2 == 0, f"Unbalanced fenced blocks: {relative(doc)}")
        for raw in re.findall(r"\[[^]\n]+\]\(([^)\s]+)\)", text):
            parsed = urlsplit(raw)
            if parsed.scheme in ("https", "http"):
                pinned = re.fullmatch(r"/bultodepapas/OpenRCsimulator/blob/([0-9a-f]{40})/(.+)", parsed.path)
                if parsed.netloc == "github.com" and pinned:
                    commit, path = pinned.groups()
                    content = source_at(commit, unquote(path)).decode(errors="replace")
                    if parsed.fragment.startswith("L"):
                        line_ref = re.fullmatch(r"L(\d+)(?:-L(\d+))?", parsed.fragment)
                        require(line_ref is not None, f"Invalid line fragment: {raw}")
                        if line_ref:
                            start = int(line_ref[1]); end = int(line_ref[2] or line_ref[1])
                            require(1 <= start <= end <= len(content.splitlines()), f"Invalid lines: {raw}")
                    elif parsed.fragment:
                        require(unquote(parsed.fragment) in headings(content), f"Missing pinned anchor: {raw}")
                    verified_links += 1
                else:
                    external_links.add(raw)
                continue
            require(not parsed.scheme, f"Unexpected link scheme in {relative(doc)}: {raw}")
            target = (doc.parent / unquote(parsed.path)).resolve() if parsed.path else doc
            try:
                rel = relative(target)
            except ValueError:
                errors.append(f"Link escapes repo: {raw}")
                continue
            if target.is_file():
                content = target.read_text(errors="replace")
            else:
                record = git("cat-file", "-t", f"HEAD:{rel}", allow_error=True).decode().strip()
                require(record in ("tree", "blob"), f"Missing link {relative(doc)} -> {raw}")
                if record == "blob":
                    flags = git("ls-files", "-v", "--", rel).decode()
                    require(flags.startswith("S "), f"Missing tracked link outside sparse omission: {rel}")
                    content = source_at("HEAD", rel).decode(errors="replace")
                else:
                    content = ""
            if parsed.fragment:
                require(unquote(parsed.fragment) in headings(content),
                        f"Missing anchor {relative(doc)} -> {raw}")
            verified_links += 1
    checks["markdown"] = {"files": [relative(p) for p in markdown], "verified_destinations": verified_links,
                          "index_scope": "Only VRC entries in docs/README.md and docs/research/README.md",
                          "external_links_not_fetched": sorted(external_links)}
    # Only this branch's package/index additions are intended; an unchanged app tree is a scoped claim.
    app_diff = git("diff", "--name-only", BASE, "--", "app").decode().splitlines()
    app_index_diff = git("diff", "--cached", "--name-only", BASE, "--", "app").decode().splitlines()
    app_untracked = git("ls-files", "--others", "--exclude-standard", "--", "app").decode().splitlines()
    require(not app_diff and not app_index_diff and not app_untracked,
            "App tracked index/worktree or nonignored untracked files changed")
    checks["runtime"] = {"base_app_tree": git("rev-parse", f"{BASE}:app").decode().strip(),
                         "head_app_tree": git("rev-parse", "HEAD:app").decode().strip(),
                         "changed_app_paths": app_diff, "changed_app_index_paths": app_index_diff,
                         "nonignored_untracked_app_paths": app_untracked,
                         "executed": False}
    whitespace = subprocess.run(["git", "-C", str(ROOT), "diff", "--check", REVIEWED_PLAN], capture_output=True)
    require(whitespace.returncode == 0, "git diff --check: " + whitespace.stdout.decode(errors="replace"))
    staged_whitespace = subprocess.run(["git", "-C", str(ROOT), "diff", "--cached", "--check", REVIEWED_PLAN], capture_output=True)
    require(staged_whitespace.returncode == 0,
            "git diff --cached --check: " + staged_whitespace.stdout.decode(errors="replace"))
    checks["git_diff_check"] = {"worktree_ok": whitespace.returncode == 0,
                                "index_ok": staged_whitespace.returncode == 0,
                                "scope": "Tracked index and worktree candidate diff; stage new deliverables before final verification"}
    historical = json.loads(source_at(PRIOR_AUDIT, "docs/research/game-controls-audit-2026-11-21/verification.json"))
    summary = historical["existing_regressions"]["summary"]
    require(summary["passed"] == 22 and summary["failed"] == 5, "Historical results mismatch")
    checks["historical_controls_batch"] = {"commit": PRIOR_AUDIT, "passed": summary["passed"],
                                            "failed_or_incomplete": summary["failed"], "rerun": False}
    manifest = {}
    for path in [*markdown, HOME / "inventory.json", HOME / "control-cases.json", HOME / "audit-findings.json", *refinement_files, Path(__file__)]:
        manifest[relative(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    report = {"schema": "openrc-vrc-static-verification-v1", "date": "2026-11-21",
              "base_commit": BASE, "reviewed_plan_commit": REVIEWED_PLAN, "refinement_base_commit": REFINEMENT_BASE,
              "scope": "Static plan/data/source-reference checks only; no Godot, replay, CI, hardware or gameplay execution",
              "ok": not errors, "errors": errors, "checks": checks, "artifact_sha256": manifest}
    if args.output:
        if args.output.exists():
            raise RuntimeError("Refusing to replace an existing verification receipt; choose a new path")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"ok": report["ok"], "case_count": len(ids), "finding_count": len(finding_ids),
                      "verified_links": verified_links, "errors": errors}, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
