#!/usr/bin/env python3
"""Reproduce checkpoint short-write and UTF-8 accounting with a disposable Godot project."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
ORIGINAL = '{"old":"previous checkpoint"}'
MARKER = "OPENRC_CHECKPOINT_OBSERVATION="


def limit_child() -> None:
    # The limit must apply to Godot, not the checked runner or its report files.
    import resource
    import signal

    resource.setrlimit(resource.RLIMIT_FSIZE, (64, 64))
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    os.execv(sys.argv[2], sys.argv[2:])


def digest(path: Path, algorithm: str) -> str:
    hashed = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hashed.update(block)
    return hashed.hexdigest()


def make_project(project: Path) -> None:
    source = REPO / "app"
    for pattern in ("*.gd", "*.gdshader"):
        for path in source.rglob(pattern):
            relative = path.relative_to(source)
            if any(part.startswith(".") for part in relative.parts):
                continue
            destination = project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Checkpoint review fixture"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8"
    )
    # These unrelated preloads otherwise require image assets and editor imports.
    (project / "landscapes/catalog.gd").write_text(
        'extends RefCounted\nconst DEFAULT_ID = "club_field"\n'
        'static func ids() -> Array[String]: return ["club_field"]\n'
        'static func has(id: String) -> bool: return id == DEFAULT_ID\n', encoding="utf-8"
    )
    (project / "app_state/preferences.gd").write_text(
        'extends RefCounted\nconst LANGUAGES = {"en": "English"}\n', encoding="utf-8"
    )
    shutil.copyfile(HERE / "checkpoint_probe.gd", project / "checkpoint_probe.gd")


def matches(observation: dict, filesystem: dict, expected: str) -> bool:
    if (not observation.get("original_setup_ok") or observation.get("other_files") != []
            or filesystem.get("target_temporaries", []) != []):
        return False
    if observation.get("scenario") == "limited":
        if expected == "fixed":
            return not observation.get("save_ok") and observation.get("original_preserved")
        return (observation.get("save_ok") and not observation.get("original_preserved")
                and observation.get("actual_bytes") == 64
                and observation.get("reported_bytes", 0) > 64)
    if observation.get("scenario") == "cycle":
        return (not observation.get("save_ok") and filesystem.get("is_symlink")
                and filesystem.get("second_link_is_symlink"))
    if observation.get("scenario") == "missing-intermediate":
        return (not observation.get("save_ok") and filesystem.get("is_symlink")
                and filesystem.get("link_target_is_original"))
    common = (observation.get("save_ok") and observation.get("exact_new_content")
              and observation.get("reload_ok")
              and observation.get("actual_bytes") == observation.get("expected_utf8_bytes"))
    if observation.get("scenario") in ("mode", "symlink", "relative-chain", "directory-link-parent"):
        common = common and filesystem.get("mode") == "0600"
    if observation.get("scenario") in ("symlink", "relative-chain", "directory-link-parent", "dangling"):
        common = common and filesystem.get("is_symlink") and not filesystem.get("link_target_is_original")
    if observation.get("scenario") in ("relative-chain", "directory-link-parent"):
        common = common and filesystem.get("second_link_is_symlink")
    if expected == "fixed":
        return common and observation.get("reported_bytes") == observation.get("expected_utf8_bytes")
    return (common and observation.get("reported_bytes") == observation.get("expected_characters")
            and observation.get("expected_characters") < observation.get("expected_utf8_bytes"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="path to the verified Godot executable")
    parser.add_argument("--out-dir", required=True, help="directory for checked reports and the compact receipt")
    parser.add_argument("--expect", choices=("fixed", "vulnerable"), default="fixed")
    args = parser.parse_args()
    if os.name != "posix":
        parser.error("the limited-write case requires POSIX RLIMIT_FSIZE and SIGXFSZ")
    godot = Path(args.godot).resolve(strict=True)
    out = Path(args.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    checked = out / "checked"
    checked.mkdir(exist_ok=True)
    version = subprocess.run([str(godot), "--version"], capture_output=True, text=True,
                             check=True, timeout=15).stdout.strip()
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True,
                            text=True, check=True, timeout=15).stdout.strip()
    receipt = {
        "format": "openrc-checkpoint-repro-v1",
        "expected_behavior": args.expect,
        "checkout_head": commit,
        "bridge_sha256": digest(REPO / "app/debug/debug_bridge.gd", "sha256"),
        "godot_version": version,
        "godot_sha512": digest(godot, "sha512"),
        "platform": platform.platform(),
        "limitations": ["fake session; source-only isolated project", "no native Windows runtime"],
        "scenarios": {},
    }
    with tempfile.TemporaryDirectory(prefix="checkpoint-project-", dir=out) as temporary:
        work = Path(temporary)
        project = work / "project"
        project.mkdir()
        make_project(project)
        for scenario in ("limited", "normal", "long", "mode", "symlink", "relative-chain", "directory-link-parent", "dangling", "cycle", "missing-intermediate"):
            case_dir = work / scenario
            case_dir.mkdir()
            name = "a" * 235 + ".json" if scenario == "long" else "checkpoint.json"
            target = case_dir / name
            link_target = None
            second_link = None
            if scenario in ("symlink", "relative-chain", "dangling"):
                link_target = work / (scenario + "-target.json")
                if scenario != "dangling":
                    link_target.write_text(ORIGINAL, encoding="utf-8")
                    link_target.chmod(0o600)
                if scenario == "relative-chain":
                    second_link = work / "relative-chain-next"
                    second_link.symlink_to(link_target.name)
                    target.symlink_to("../" + second_link.name)
                else:
                    target.symlink_to(link_target if scenario == "symlink" else "../" + link_target.name)
            elif scenario == "directory-link-parent":
                nested = work / "directory-link-real/nested"
                nested.mkdir(parents=True)
                link_target = nested.parent / "state.json"
                link_target.write_text(ORIGINAL, encoding="utf-8")
                link_target.chmod(0o600)
                second_link = work / "directory-link"
                second_link.symlink_to("directory-link-real/nested", target_is_directory=True)
                target.symlink_to("../directory-link/../state.json")
            elif scenario == "missing-intermediate":
                link_target = work / "state.json"
                link_target.write_text(ORIGINAL, encoding="utf-8")
                link_target.chmod(0o600)
                target.symlink_to("../missing-component/../state.json")
            elif scenario == "cycle":
                second_link = work / "cycle-next"
                target.symlink_to("../" + second_link.name)
                second_link.symlink_to("cycle/checkpoint.json")
            else:
                target.write_text(ORIGINAL, encoding="utf-8")
                if scenario == "mode":
                    target.chmod(0o600)
            env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1", PYTHONDONTWRITEBYTECODE="1",
                       XDG_DATA_HOME=str(work / "user"), XDG_CONFIG_HOME=str(work / "config"),
                       XDG_CACHE_HOME=str(work / "cache"), OPENRC_CHECKPOINT_REPRO_PATH=str(target),
                       OPENRC_CHECKPOINT_REPRO_SCENARIO=scenario)
            label = "checkpoint-repro-" + scenario + "-" + uuid.uuid4().hex[:8]
            command = [sys.executable, "-B", str(REPO / "tools/godot/run_checked.py"),
                       "--out-dir", str(checked), "--label", label, "--timeout", "30",
                       "--require-text", MARKER, "--"]
            if scenario == "limited":
                command += [sys.executable, "-B", str(HERE / "run.py"), "--limit-child"]
            command += [str(godot), "--headless", "--path", str(project), "--audio-driver", "Dummy",
                        "--script", "res://checkpoint_probe.gd"]
            run = subprocess.run(command, cwd=REPO, env=env, capture_output=True, text=True, timeout=45)
            reports = list(checked.glob(label + "-*/report.json"))
            if len(reports) != 1:
                raise RuntimeError(f"expected one checked report for {scenario}, found {len(reports)}")
            report = json.loads(reports[0].read_text(encoding="utf-8"))
            log = reports[0].with_name("engine.log").read_text(encoding="utf-8")
            observations = [json.loads(line.split(MARKER, 1)[1]) for line in log.splitlines() if MARKER in line]
            observation = observations[0] if len(observations) == 1 else {}
            filesystem = {"is_symlink": target.is_symlink(),
                          "mode": format(stat.S_IMODE(target.stat().st_mode), "04o") if target.exists() else None}
            if link_target is not None:
                filesystem["link_target_is_original"] = (link_target.exists()
                                                         and link_target.read_text(encoding="utf-8") == ORIGINAL)
                filesystem["target_temporaries"] = sorted(
                    item.name for item in link_target.parent.iterdir() if item.name.startswith(".checkpoint-")
                )
            if second_link is not None:
                filesystem["second_link_is_symlink"] = second_link.is_symlink()
            passed = (run.returncode == 0 and report.get("ok") and report.get("counts") == {"error": 0, "warning": 0}
                      and len(observations) == 1 and matches(observation, filesystem, args.expect))
            receipt["scenarios"][scenario] = {
                "passed": bool(passed), "observation": observation, "filesystem": filesystem,
                "checked_report": str(reports[0].relative_to(out)),
                "checked_ok": report.get("ok"), "diagnostic_counts": report.get("counts"),
            }
            print(f"{scenario}: {'PASS' if passed else 'FAIL'} ({reports[0]})", flush=True)
            if not passed:
                print(run.stdout + run.stderr, file=sys.stderr)
    receipt["passed"] = all(result["passed"] for result in receipt["scenarios"].values())
    destination = out / "receipt.json"
    destination.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"receipt: {destination}")
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--limit-child":
        limit_child()
    raise SystemExit(main())
