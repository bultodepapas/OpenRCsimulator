#!/usr/bin/env python3
"""Rehearse Mac default recording and replay in an isolated, non-promotable clone.

This uses the real installed candidate and independently revalidated production
fleet rows. It deliberately does not assert the long-run promotion evidence and
never installs a marker into the accepted or canonical app. The cloned receipt
gets a fixture-only envelope field, so its marker alone cannot activate the
canonical receipt. This is a test fixture, not a qualification or signature.
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stderr
import io
import json
import os
import platform
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
TMP = ROOT / "tmp"
sys.path.insert(0, str(HERE))
import macos_promotion as promotion  # noqa: E402
import test_macos_default_installation as fixtures  # noqa: E402

fleet = promotion.module("macos_default_fixture_fleet", HERE / "fleet_campaign.py")
package = promotion.module("macos_default_fixture_package", HERE / "package.py")
flight_log = promotion.module("macos_default_fixture_log", ROOT / "tools/flight_log/flight_log.py")


def require(value: bool, detail: str) -> None:
    if not value:
        raise ValueError(detail)


def rehearsal_marker(guard: dict[str, Any], domain_sha: str, fixture_receipt_sha: str,
                     original_receipt_sha: str, rows: list[dict], campaign: dict, token: str) -> dict:
    receipt = guard["receipt"]
    require(fixture_receipt_sha != original_receipt_sha, "fixture receipt was not isolated")
    require(any(row.get("aircraft") == "jensen-das-ugly-stik-60" and row.get("battery") == "ideal"
                and row.get("start") == "runway" and row.get("weather") == "calm"
                and row.get("soft_hull") is True for row in rows),
            "validated guarded fleet has no production Jensen runway/calm/soft-hull row for the test")
    return {"format": promotion.FORMAT, "scope": promotion.SCOPE, "receipt_sha256": fixture_receipt_sha,
            "binary_sha256": guard["binary_sha256"], "source_sha256": receipt["source_sha256"],
            "lock_sha256": receipt["lock_sha256"], "domain_sha256": domain_sha,
            "engine_sha256": guard["engine_sha256"], "os_version": receipt["runtime_os_version"],
            "os_build": receipt["runtime_os_build"], "hardware_model": promotion.MODEL, "cpu": promotion.CPU,
            "allowed_selections": rows,
            "evidence": {"fixture_only": True, "fixture_id": token, "original_receipt_sha256": original_receipt_sha,
                         "fleet": campaign,
                         "scope": "Disposable pre-promotion test only; no sustained or promotion qualification."}}


def install_fixture_marker(project: Path, guard: dict[str, Any], rows: list[dict], campaign: dict,
                           token: str) -> tuple[dict, dict]:
    receipt_path = project / fixtures.RECEIPT
    marker_path = project / fixtures.MARKER
    require(not marker_path.exists() and not marker_path.is_symlink(), "fixture project already has a marker")
    receipt, original_receipt_sha = promotion.read_json(receipt_path)
    require(original_receipt_sha == guard["receipt_sha256"] and receipt.get("platforms", {}).get("macos") == guard["receipt"],
            "cloned receipt differs from the verified installation")
    require("openrc_test_fixture" not in receipt, "receipt already carries a fixture field")
    receipt["openrc_test_fixture"] = {"purpose": "non-promotable-prepromotion-rehearsal", "id": token}
    with receipt_path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(receipt, stream, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")
    fixture_receipt_sha = promotion.sha(receipt_path)
    marker = rehearsal_marker(guard, promotion.sha(project / fixtures.DOMAIN), fixture_receipt_sha,
                              original_receipt_sha, rows, campaign, token)
    with marker_path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(marker, stream, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")
    return marker, {"original_receipt_sha256": original_receipt_sha, "fixture_receipt_sha256": fixture_receipt_sha,
                    "fixture_marker_sha256": promotion.sha(marker_path)}


def checked(command: list[str], output: Path, label: str, required: list[str]) -> tuple[dict, str]:
    with fixtures.isolated_environment(output / "homes" / label):
        result = fixtures.ROUTE.RUNNER.run_checked(command, output / "checks", timeout=1800,
                                                   required=required, label=label)
    log = Path(result["log"]).read_text(encoding="utf-8", errors="replace")
    require(result.get("ok") is True and result.get("complete") is True
            and result.get("process_exit") == 0 and result.get("counts", {}).get("error") == 0,
            f"{label}: checked run failed ({result.get('reason')}): {result.get('log')}")
    return result, log


def _state(path: Path) -> str | None:
    require(not path.is_symlink(), f"redirected canonical marker: {path}")
    return promotion.sha(path) if path.is_file() else None


def run(args: argparse.Namespace, output: Path) -> dict:
    require(sys.platform == "darwin" and platform.machine() == "arm64", "native macOS ARM64 Python is required")
    project, godot = args.project.resolve(), args.godot.resolve()
    context = {"project": str(project), "godot": str(godot), "tool_root": str(args.tool_root.resolve()),
               "qualification_root": str(args.qualification_root.resolve()), "trim_profile": "production"}
    require(project != (ROOT / "app").resolve() and (project / ".godot").is_dir(),
            "an imported, isolated prepared project is required")
    require(not (project / fixtures.MARKER).exists() and not (project / fixtures.MARKER).is_symlink(),
            "the original project must not already contain an admission marker")
    proof = fixtures.RUNNER.validate_project(project)
    require(bool(proof), "prepared project identity is missing")
    source_before = fixtures.RUNNER._project_inventory(project)
    preparation = project.parent / "research-preparation.json"
    preparation_sha = promotion.sha(preparation)
    engine_sha = promotion.sha(godot)
    canonical_marker = ROOT / "app" / fixtures.MARKER
    canonical_before = _state(canonical_marker)
    installed = package.verified_mac_install(Path(context["qualification_root"]), godot)
    guard = fleet.snapshot(context)
    require(installed["platforms"]["macos"] == guard["receipt"]
            and promotion.sha(ROOT / "app" / fixtures.RECEIPT) == guard["receipt_sha256"],
            "prepared project and verified canonical candidate differ")
    preflight, preflight_sha = promotion.read_json(args.preflight.resolve())
    promotion.validate_preflight(preflight, guard)
    campaign_path = args.campaign.resolve()
    rows, campaign = promotion.validate_fleet(fleet, campaign_path, context, guard)

    clone = output / "project/app"
    fixtures.clone_project(project, clone, fixtures.PREPARE._macos_clonefile())
    require(fixtures.RUNNER._project_inventory(clone) == source_before, "private project differs from the source")
    token = uuid.uuid4().hex
    marker, marker_evidence = install_fixture_marker(clone, guard, rows, campaign, token)
    require(marker["receipt_sha256"] != promotion.sha(ROOT / "app" / fixtures.RECEIPT),
            "fixture marker could match the canonical receipt")
    _marker, _row, expected = fixtures.expected_identity(clone, godot)
    fixture_inventory = fixtures.RUNNER._project_inventory(clone)

    recording, csv_path, replay_path = (output / name for name in ("main.orfl", "replay.csv", "replay.json"))
    main_command = [str(godot), "--headless", "--path", str(clone), "--audio-driver", "Dummy", "--script",
                    str(HERE / "test_macos_default.gd"), "--", f"--macos-default-log={recording}"]
    main_check, main_log = checked(main_command, output, "main-recording", ["MACOS_DEFAULT_ROUTE verdict=pass"])
    require(f"MACOS_DEFAULT_RECORDING path={recording}" in main_log and recording.is_file(),
            "Main did not retain the requested completed recording")
    recording_sha = promotion.sha(recording)
    replay_command = [str(godot), "--headless", "--path", str(clone), "--audio-driver", "Dummy", "--script",
                      "res://tools/flight_log_cli.gd", "--", f"--log={recording}", f"--csv={csv_path}",
                      f"--report={replay_path}", "--replay"]
    replay_check, _log = checked(replay_command, output, "ordinary-exact-replay", ["Flight log exact:"])
    report = flight_log._check_godot_report(replay_path)
    first, last, _dt, _events = flight_log._validate_exact_replay_report(report, recording)
    csv = flight_log._check_exported_csv(csv_path, report)
    require(last - first >= 4 and report.get("baseline_stage_backend") == expected
            and report.get("current_stage_backend") == expected and csv.get("rows") == report.get("rows")
            and promotion.sha(recording) == recording_sha, "ordinary exact replay did not preserve native identity and rows")
    require(fixtures.RUNNER._project_inventory(clone) == fixture_inventory, "rehearsal modified fixture sources")
    final_rows, final_campaign = promotion.validate_fleet(fleet, campaign_path, context, guard)
    require(final_rows == rows and final_campaign == campaign and fleet.snapshot(context) == guard
            and fixtures.RUNNER._project_inventory(project) == source_before
            and fixtures.RUNNER.validate_project(project) == proof and promotion.sha(preparation) == preparation_sha
            and promotion.sha(godot) == engine_sha and promotion.sha(args.preflight.resolve()) == preflight_sha
            and _state(canonical_marker) == canonical_before, "original project or evidence changed during rehearsal")
    return {"format": "openrc-macos-default-rehearsal v1", "verdict": "pass", "fixture_only": True,
            "scope": "Disposable APFS clone; no promotion, sustained qualification, or public package claim.",
            "project": str(project), "project_manifest_sha256": fixtures.RUNNER._inventory_hash(source_before),
            "engine_sha256": engine_sha, "preflight_sha256": preflight_sha, "campaign": campaign,
            "fixture": marker_evidence, "recording": str(recording), "recording_sha256": recording_sha,
            "main_check": main_check, "replay_check": replay_check, "replay_report": str(replay_path),
            "replay_report_sha256": promotion.sha(replay_path), "replay_csv_sha256": promotion.sha(csv_path),
            "first_tick": first, "final_tick": last, "rows": report["rows"], "native_identity": expected}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("godot", "project", "tool-root", "qualification-root", "preflight", "campaign", "out"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    try:
        require(sys.platform == "darwin" and platform.machine() == "arm64", "native macOS ARM64 Python is required")
        output_arg = args.out.expanduser().absolute()
        require(not output_arg.exists() and not output_arg.is_symlink(), "output already exists")
        output, temp_root = output_arg.resolve(), TMP.resolve()
        require(output.is_relative_to(temp_root) and output != temp_root, "output must be a new path under tmp/")
        for protected in (args.project.parent, args.tool_root, args.qualification_root, args.campaign.parent):
            path = protected.expanduser().resolve()
            require(not output.is_relative_to(path) and not path.is_relative_to(output),
                    "output must be separate from accepted project and evidence roots")
        output.mkdir(parents=True, exist_ok=False)
        result = run(args, output)
        destination = output / "rehearsal.json"
        with destination.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(result, stream, sort_keys=True, indent=2, allow_nan=False)
            stream.write("\n")
        print(f"MACOS_DEFAULT_REHEARSAL verdict=pass fixture_only=true report={destination}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, AssertionError, subprocess.SubprocessError,
            flight_log.FlightLogError) as error:
        print(f"MACOS_DEFAULT_REHEARSAL verdict=fail fixture_only=true: {error}", file=sys.stderr)
        return 1


class FixtureTests(unittest.TestCase):
    def test_fixture_receipt_cannot_match_original(self) -> None:
        guard = {"receipt": {"source_sha256": "source", "lock_sha256": "lock",
                              "runtime_os_version": "27", "runtime_os_build": "build"},
                 "binary_sha256": "binary", "engine_sha256": "engine"}
        rows = [{"aircraft": "jensen-das-ugly-stik-60", "battery": "ideal", "start": "runway",
                 "weather": "calm", "soft_hull": True}]
        marker = rehearsal_marker(guard, "domain", "fixture", "canonical", rows, {}, "token")
        self.assertEqual(marker["receipt_sha256"], "fixture")
        self.assertTrue(marker["evidence"]["fixture_only"])
        with self.assertRaises(ValueError):
            rehearsal_marker(guard, "domain", "canonical", "canonical", rows, {}, "token")
        with self.assertRaises(ValueError):
            rehearsal_marker(guard, "domain", "fixture", "canonical", [], {}, "token")

    def test_marker_is_only_written_to_disposable_project(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "clone"
            receipt_path = project / fixtures.RECEIPT
            receipt_path.parent.mkdir(parents=True)
            domain = project / fixtures.DOMAIN
            domain.parent.mkdir(parents=True)
            domain.write_text("domain", encoding="utf-8")
            row = {"source_sha256": "source", "lock_sha256": "lock", "runtime_os_version": "27",
                   "runtime_os_build": "build"}
            receipt_path.write_text(json.dumps({"platforms": {"macos": row}}), encoding="utf-8")
            before = promotion.sha(receipt_path)
            guard = {"receipt": row, "receipt_sha256": before, "binary_sha256": "binary", "engine_sha256": "engine"}
            rows = [{"aircraft": "jensen-das-ugly-stik-60", "battery": "ideal", "start": "runway",
                     "weather": "calm", "soft_hull": True}]
            marker, evidence = install_fixture_marker(project, guard, rows, {}, "token")
            self.assertNotEqual(evidence["fixture_receipt_sha256"], before)
            self.assertEqual(marker["receipt_sha256"], promotion.sha(receipt_path))
            with self.assertRaises(ValueError):
                install_fixture_marker(project, guard, rows, {}, "token2")

    def test_unsupported_host_never_creates_a_success_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "out"
            argv = ["test"]
            for option in ("godot", "project", "tool-root", "qualification-root", "preflight", "campaign"):
                argv.extend(["--" + option, str(Path(directory) / option)])
            argv.extend(["--out", str(out)])
            with patch.object(sys, "argv", argv), patch.object(sys, "platform", "linux"), redirect_stderr(io.StringIO()):
                self.assertEqual(main(), 1)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    raise SystemExit(main())
