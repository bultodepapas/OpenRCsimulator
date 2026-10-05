#!/usr/bin/env python3
"""Reproducibly check the livery SVG source, import, and stale-source guard."""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


class CheckFailure(RuntimeError):
    pass


def find_repo_root(start):
    for candidate in (start, *start.parents):
        compiler = candidate / "assets/aircraft/ugly-stik-60/compile_appearance.py"
        project = candidate / "app/project.godot"
        source = candidate / "app/aircraft/livery.svg"
        if compiler.is_file() and project.is_file() and source.is_file():
            return candidate
    raise CheckFailure("Could not find repo root while ascending from " + str(start))


def command_text(command):
    return " ".join(str(part) for part in command)


def output_text(result):
    return result.stdout or ""


def run_command(log, label, command, cwd, timeout, expected_returncode=0):
    log.append("== " + label + " ==")
    log.append("$ " + command_text(command))
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        log.append("TIMEOUT after {} seconds".format(timeout))
        if partial:
            log.append(partial.rstrip())
        raise CheckFailure(label + " timed out after {} seconds".format(timeout))

    output = output_text(result)
    if output:
        log.append(output.rstrip())
    log.append("exit code: {}".format(result.returncode))
    if re.search(r"\bERROR\b", output, flags=re.IGNORECASE):
        raise CheckFailure(label + " emitted ERROR")
    if expected_returncode is not None and result.returncode != expected_returncode:
        raise CheckFailure("{} exited with {}".format(label, result.returncode))
    return result


def copy_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(str(source), str(destination))


def run_checks(root, log, godot_override=None):
    python = sys.executable
    compiler = root / "assets/aircraft/ugly-stik-60/compile_appearance.py"
    run_command(
        log,
        "Generated appearance is current",
        [python, str(compiler), "--check"],
        root,
        timeout=30,
    )

    godot = Path(godot_override).resolve() if godot_override else root / ".tools/Godot_v4.7.2-stable_linux.x86_64"
    if not godot.is_file() or not godot.stat().st_mode & 0o111:
        raise CheckFailure(
            "Pinned Godot 4.7.2 is missing at {}; run app/get-godot.sh first".format(godot)
        )

    fixture = Path(__file__).resolve().with_name("atlas-fixture")
    with tempfile.TemporaryDirectory(prefix="openrc-atlas-godot-") as temporary:
        project = Path(temporary) / "godot-project"
        project.mkdir()
        copy_file(fixture / "project.godot", project / "project.godot")
        copy_file(fixture / "compare_import.gd", project / "compare_import.gd")
        copy_file(fixture / "livery.svg.import", project / "livery.svg.import")
        copy_file(root / "app/aircraft/livery.svg", project / "livery.svg")
        copy_file(
            root / "app/aircraft/ugly_stik_appearance.gd",
            project / "appearance.gd",
        )

        run_command(
            log,
            "Import SVG in a clean temporary Godot project",
            [str(godot), "--headless", "--editor", "--path", str(project), "--import"],
            project,
            timeout=60,
        )
        imported_files = list((project / ".godot/imported").glob("livery.svg-*.ctex"))
        if len(imported_files) != 1:
            raise CheckFailure(
                "Expected one imported SVG texture, found {}".format(len(imported_files))
            )
        log.append("imported texture: {} bytes".format(imported_files[0].stat().st_size))

        comparison = run_command(
            log,
            "Compare imported texture bytes with Image.load_svg_from_string",
            [str(godot), "--headless", "--path", str(project), "--script", "res://compare_import.gd"],
            project,
            timeout=60,
        )
        if "SVG editor/runtime raster match: true size=(1024, 1024)" not in output_text(comparison):
            raise CheckFailure("SVG editor/runtime byte comparison did not report a match")

    # Recreate only the compiler's input/output topology in a disposable copy.
    # Mutating that copy proves --check rejects stale checked-in generated SVG.
    with tempfile.TemporaryDirectory(prefix="openrc-atlas-mutation-") as temporary:
        mutation_root = Path(temporary)
        copy_file(
            root / "assets/aircraft/ugly-stik-60/appearance.json",
            mutation_root / "assets/aircraft/ugly-stik-60/appearance.json",
        )
        copy_file(
            compiler,
            mutation_root / "assets/aircraft/ugly-stik-60/compile_appearance.py",
        )
        copy_file(
            root / "app/aircraft/livery.svg",
            mutation_root / "app/aircraft/livery.svg",
        )
        copy_file(
            root / "app/aircraft/ugly_stik_appearance.gd",
            mutation_root / "app/aircraft/ugly_stik_appearance.gd",
        )
        mutated_svg = mutation_root / "app/aircraft/livery.svg"
        mutated_svg.write_text(
            mutated_svg.read_text(encoding="utf-8") + "<!-- stale-source mutation -->\n",
            encoding="utf-8",
        )
        mutation = run_command(
            log,
            "Mutation check rejects a changed SVG in the disposable source tree",
            [python, str(mutation_root / "assets/aircraft/ugly-stik-60/compile_appearance.py"), "--check"],
            mutation_root,
            timeout=30,
            expected_returncode=None,
        )
        if mutation.returncode == 0 or "Stale livery.svg" not in output_text(mutation):
            raise CheckFailure("Mutation did not fail specifically on stale livery.svg")
        log.append("mutation rejected as expected")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--log",
        type=Path,
        default=Path(__file__).with_name("atlas-check.log"),
        help="write the concise run log here (default: evidence/atlas-check.log)",
    )
    parser.add_argument(
        "--godot",
        type=Path,
        help="explicit Godot 4.7.2 binary; defaults to .tools/Godot_v4.7.2-stable_linux.x86_64",
    )
    args = parser.parse_args()
    log = ["Atlas verification: compile, clean import byte match, stale-source mutation"]
    try:
        root = find_repo_root(Path(__file__).resolve().parent)
        log.append("repository root: {}".format(root))
        run_checks(root, log, args.godot)
        log.append("RESULT: PASS — source current; imported/runtime bytes match; stale SVG rejected")
        return_code = 0
    except CheckFailure as error:
        log.append("RESULT: FAIL — {}".format(error))
        return_code = 1
    except Exception as error:  # Keep an actionable log for unexpected failures too.
        log.append("RESULT: FAIL — {}: {}".format(type(error).__name__, error))
        return_code = 1

    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.log.write_text("\n".join(log) + "\n", encoding="utf-8")
    print("\n".join(log))
    print("log: {}".format(args.log))
    return return_code


if __name__ == "__main__":
    sys.exit(main())
