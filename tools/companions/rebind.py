#!/usr/bin/env python3
"""AFC-02-R3: re-bind the AI companion solver qualification after a physics/sim/failures edit.

The companion profile pins a normalized identity of app/physics, app/sim and app/failures. This tool replays
the retained companion tapes (tools/companions/qualification.json) in candidate mode on two disposable
project copies that differ only in those directories: the accepted revision and the current tree. Identical
CSVs show that the edit leaves the qualified aircraft's behaviour unchanged on these tapes; --accept then
re-pins the profile and writes a receipt. Any difference stops: that is a behaviour change and needs a new
qualification, not a re-bind. Parity on these tapes is not exact replay or physical validation.

    python3 tools/companions/rebind.py             # report only
    python3 tools/companions/rebind.py --accept    # re-pin when every tape is identical

Exit codes: 0 qualified (already current, or identical), 1 behaviour changed, 2 setup or replay error.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import contextlib
import csv
from dataclasses import dataclass
import datetime
import gzip
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.graphics.prepare_research import _macos_clonefile, PreparationError  # noqa: E402

QUALIFICATION = ROOT / "tools" / "companions" / "qualification.json"
IDENTITY_SCRIPT = ROOT / "tools" / "companions" / "solver_identity.gd"
RECEIPT_FORMAT = "openrc-ai-solver-rebind v1"
COPY_IGNORE = shutil.ignore_patterns("captures")
DIFF_COLUMNS_REPORTED = 5
# FlightLogCli.inspect admits the recorder's 512 MiB plus two 16 MiB packets.
MAX_MATERIALIZED_BYTES = (512 + 2 * 16) * 1024 * 1024
COPY_BLOCK_BYTES = 1024 * 1024
GZIP_MAGIC = b"\x1f\x8b"
ORFL_MAGIC = b"ORFL0001"


class SetupError(RuntimeError):
    """The comparison could not run; nothing about behaviour is known."""


@dataclass(frozen=True)
class PreparedTape:
    source: Path
    path: Path
    logical_name: str
    orfl_sha256: str = ""
    stored_sha256: str = ""

    @property
    def compressed(self) -> bool:
        return bool(self.stored_sha256)


def run(command: list[str], cwd: Path = ROOT, timeout: int = 600) -> subprocess.CompletedProcess:
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=timeout, env=env)


def git(*args: str) -> str:
    result = run(["git", *args])
    if result.returncode:
        raise SetupError(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def default_godot() -> str:
    result = run([str(ROOT / "app" / "get-godot.sh")])
    if result.returncode or not result.stdout.strip():
        raise SetupError("app/get-godot.sh did not return the pinned Godot binary")
    return result.stdout.strip().splitlines()[-1]


def solver_identity(godot: str, app: Path, tapes: tuple[Path, ...] = (),
                    expected_tape_sha256: dict[str, str] | None = None) -> str:
    if expected_tape_sha256 and not set(expected_tape_sha256).issubset({str(tape) for tape in tapes}):
        raise SetupError("expected inspected tape identity is not among requested tapes")
    if expected_tape_sha256 and any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value)
                                    for value in expected_tape_sha256.values()):
        raise SetupError("expected inspected tape SHA-256 is malformed")
    command = [godot, "--headless", "--path", str(app), "--audio-driver", "Dummy", "--script", str(IDENTITY_SCRIPT)]
    if tapes:
        command += ["--", *(f"--tape={tape}" for tape in tapes)]
    result = run(command)
    for line in result.stdout.splitlines():
        if line.startswith("SOLVER_IDENTITY "):
            identity = json.loads(line.removeprefix("SOLVER_IDENTITY "))
            if result.returncode == 0 and identity.get("ok") and identity.get("inspected_tapes", 0) == len(tapes):
                if expected_tape_sha256:
                    inspected = identity.get("inspected_tape_sha256")
                    if not isinstance(inspected, dict):
                        raise SetupError("solver inspection did not report per-tape SHA-256 identities")
                    for path, expected in expected_tape_sha256.items():
                        actual = inspected.get(path)
                        if not isinstance(actual, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", actual) \
                                or actual.lower() != expected.lower():
                            raise SetupError(f"solver inspection tape SHA-256 missing or differs: {path}")
                return str(identity["sha256"])
            raise SetupError(f"solver identity unavailable in {app}: {identity.get('errors')}")
    raise SetupError(f"no solver identity from {app}:\n{result.stdout[-2000:]}{result.stderr[-2000:]}")


def pinned_identity(profile: Path) -> str:
    return str(json.loads(profile.read_text(encoding="utf-8"))["solver"]["sha256"])


def validate_engine(godot: str, profile: Path) -> None:
    expected = json.loads(profile.read_text(encoding="utf-8")).get("engine_version")
    if not isinstance(expected, str) or not expected:
        raise SetupError("profile has no exact qualified engine identity")
    result = run([godot, "--version"], timeout=30)
    actual = result.stdout.strip()
    if result.returncode or actual != expected:
        raise SetupError(f"engine build differs: profile requires {expected}, got {actual or 'no version'}")


def qualified_tapes(qualification: dict) -> tuple[Path, ...]:
    entries = qualification.get("tapes")
    if not isinstance(entries, list) or not entries or any(not isinstance(item, str) or not item for item in entries):
        raise SetupError("qualification must list its retained tapes")
    tapes = tuple((ROOT / item).resolve() for item in entries)
    if len(set(tapes)) != len(tapes):
        raise SetupError("qualification contains duplicate tapes")
    missing = [str(tape) for tape in tapes if not tape.is_file()]
    if missing:
        raise SetupError(f"missing tapes: {missing}")
    identities = qualification.get("tape_identities", {})
    if not isinstance(identities, dict):
        raise SetupError("tape_identities must be an object")
    compressed = {name for name in entries if name.lower().endswith(".orfl.gz")}
    if set(identities) != compressed:
        raise SetupError("tape_identities must name exactly the compressed tapes")
    for name, identity in identities.items():
        if not isinstance(identity, dict) or set(identity) != {"orfl_sha256", "stored_sha256"} \
                or any(not isinstance(identity[key], str) or not re.fullmatch(r"[0-9a-fA-F]{64}", identity[key])
                       for key in ("orfl_sha256", "stored_sha256")):
            raise SetupError(f"invalid raw or stored tape identity: {name}")
    names: dict[str, bool] = {}
    for name, tape in zip(entries, tapes):
        declared_name = Path(name).name
        lower = declared_name.lower()
        is_gzip = name in compressed
        if lower.endswith(".gz") and not is_gzip:
            raise SetupError(f"compressed tape must use .orfl.gz: {name}")
        with tape.open("rb") as source:
            magic = source.read(2)
        if (magic == GZIP_MAGIC) != is_gzip:
            raise SetupError(f"tape suffix and gzip content disagree: {name}")
        # Both forms produce the same .orfl basename and comparison directory.
        logical = Path(declared_name[:-3]).stem if is_gzip else Path(declared_name).stem
        folded = logical.casefold()
        if not logical or (folded in names and (is_gzip or names[folded])):
            raise SetupError(f"duplicate tape output name: {logical}")
        names[folded] = names.get(folded, False) or is_gzip
    return tapes


def _materialize_gzip(source: Path, destination: Path, identity: dict) -> PreparedTape:
    stored_expected = identity["stored_sha256"].lower()
    raw_expected = identity["orfl_sha256"].lower()
    if sha256_file(source) != stored_expected:
        raise SetupError(f"stored tape SHA-256 differs: {source}")
    digest = hashlib.sha256()
    size = 0
    try:
        with source.open("rb") as stored, gzip.GzipFile(fileobj=stored, mode="rb") as packed, \
                destination.open("xb") as output:
            while True:
                block = packed.read(min(COPY_BLOCK_BYTES, MAX_MATERIALIZED_BYTES - size + 1))
                if not block:
                    break  # Reading through EOF verifies the gzip trailer and CRC.
                size += len(block)
                if size > MAX_MATERIALIZED_BYTES:
                    raise SetupError(f"decompressed tape exceeds {MAX_MATERIALIZED_BYTES} bytes: {source}")
                digest.update(block)
                output.write(block)
    except (OSError, EOFError, zlib.error) as error:
        raise SetupError(f"invalid or incomplete gzip tape {source}: {error}") from error
    if sha256_file(source) != stored_expected:
        raise SetupError(f"stored tape changed while materializing: {source}")
    if digest.hexdigest() != raw_expected or sha256_file(destination) != raw_expected:
        raise SetupError(f"materialized ORFL SHA-256 differs: {source}")
    with destination.open("rb") as raw:
        if raw.read(len(ORFL_MAGIC)) != ORFL_MAGIC:
            raise SetupError(f"materialized tape has invalid ORFL magic: {source}")
    return PreparedTape(source, destination, destination.stem, raw_expected, stored_expected)


@contextlib.contextmanager
def materialized_tapes(qualification: dict, workspace_root: Path | None = None):
    """Keep gzip expansions private and alive through inspection and both replays."""
    sources = qualified_tapes(qualification)
    entries = qualification["tapes"]
    if not any(name.lower().endswith(".orfl.gz") for name in entries):
        yield tuple(PreparedTape(ROOT / name, source, Path(name).stem) for name, source in zip(entries, sources))
        return
    parent = (workspace_root if workspace_root is not None else ROOT / "tmp").resolve()
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="companion-rebind-tapes-", dir=parent) as temporary:
        directory = Path(temporary)
        prepared = []
        for name, resolved in zip(entries, sources):
            source = ROOT / name
            if name.lower().endswith(".orfl.gz"):
                prepared.append(_materialize_gzip(source, directory / Path(name).name[:-3],
                                                  qualification["tape_identities"][name]))
            else:
                prepared.append(PreparedTape(source, resolved, Path(name).stem))
        yield tuple(prepared)


def _check_materialized_tapes(tapes: tuple[PreparedTape, ...]) -> None:
    for tape in tapes:
        if tape.compressed and (sha256_file(tape.path) != tape.orfl_sha256
                                or sha256_file(tape.source) != tape.stored_sha256):
            raise SetupError(f"compressed tape or materialized ORFL changed: {tape.source}")


## "full" also takes every other tracked app file and the replay tooling from the accepted revision.
## Use it when current non-solver code calls solver API newer than the accepted revision, which stops
## the default hybrid baseline compiling. It compares more than the solver, so identical tapes are
## a stricter result; a difference may come from non-solver code and still needs requalification.
FULL_BASELINE_PATHS = ("app", "tools/flight_log", "tools/release/macos_reference_receipt.py")


def _copy_function(mode: str):
    if mode == "copy":
        return shutil.copy2
    if mode != "clone":
        raise SetupError(f"unsupported copy mode: {mode}")
    try:
        clone = _macos_clonefile()
    except PreparationError as error:
        raise SetupError(str(error)) from error

    def clone_copy(source, destination):
        clone(Path(source), Path(destination))
        original = os.stat(source, follow_symlinks=False)
        copied = os.stat(destination, follow_symlinks=False)
        if (not stat.S_ISREG(original.st_mode) or not stat.S_ISREG(copied.st_mode)
                or copied.st_nlink != 1 or (original.st_dev, original.st_ino) == (copied.st_dev, copied.st_ino)):
            raise SetupError("clone copy must create an independent regular file")
        shutil.copystat(source, destination, follow_symlinks=False)
        return destination

    return clone_copy


def _extract_archive_stream(base: Path, rev: str, paths: list[str], *, prefix: str = "",
                            env: dict | None = None) -> None:
    """Extract the trusted Git archive without a second full-sized tar on disk."""
    with tempfile.TemporaryFile() as errors:
        command = ["git", "archive", *([f"--prefix={prefix}"] if prefix else []), rev, *paths]
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=errors)
        try:
            assert process.stdout is not None
            with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
                archive.extractall(base, filter="data")
        except (OSError, tarfile.TarError) as error:
            if process.stdout is not None:
                process.stdout.close()
            if process.poll() is None:
                process.kill()
            process.wait()
            errors.seek(0)
            detail = errors.read().decode(errors="replace").strip() or str(error)
            raise SetupError(f"git archive {rev} or extraction failed: {detail}") from error
        process.stdout.close()
        code = process.wait()
        if code:
            errors.seek(0)
            raise SetupError(f"git archive {rev}: {errors.read().decode(errors='replace').strip()}")


def _scoped_solver_archive(base: Path, rev: str, directories: list[str]) -> None:
    """Archive only requested trees; reject attributes lost by changing the tree root."""
    for path in directories:
        if not re.fullmatch(r"[A-Za-z0-9_./-]+", path) or path.startswith("/") \
                or any(part in ("", ".", "..") for part in path.split("/")):
            raise SetupError(f"invalid solver directory: {path}")
        tree = f"{rev}:{path}"
        listing = subprocess.run(["git", "ls-tree", "-r", "--name-only", "-z", tree], cwd=ROOT,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if listing.returncode:
            raise SetupError(f"cannot inspect accepted solver tree {tree}: {listing.stderr.decode(errors='replace').strip()}")
        names = [name for name in listing.stdout.split(b"\0") if name]
        if not names:
            raise SetupError(f"accepted solver tree is empty: {tree}")
        inputs = b"\0".join(path.encode("utf-8") + b"/" + name for name in names) + b"\0"
        attributes = subprocess.run(["git", "check-attr", f"--source={rev}", "--all", "-z", "--stdin"],
                                    cwd=ROOT, input=inputs, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if attributes.returncode:
            raise SetupError(f"cannot inspect accepted solver attributes: {attributes.stderr.decode(errors='replace').strip()}")
        if attributes.stdout:
            raise SetupError(f"accepted solver tree has attributes requiring a full-root archive: {path}")
        _extract_archive_stream(base, tree, [], prefix=path + "/")


def build_baseline(workspace: Path, rev: str, directories: list[str], scope: str = "solver",
                   copy_mode: str = "copy") -> Path:
    """Build the accepted solver hybrid or an exact tracked historical app and replay tree."""
    base = workspace / "base"
    copy = _copy_function(copy_mode)
    if scope not in ("solver", "full"):
        raise SetupError(f"unsupported baseline scope: {scope}")
    if scope == "full":
        paths = [path for path in FULL_BASELINE_PATHS
                 if subprocess.run(["git", "cat-file", "-e", f"{rev}:{path}"], cwd=ROOT,
                                   stderr=subprocess.DEVNULL).returncode == 0]
        if "app" not in paths or "tools/flight_log" not in paths:
            raise SetupError("accepted revision lacks the tracked app or replay tooling")
        base.mkdir()
        # Only imported assets may come from the current tree. In particular,
        # do not retain current extension lists, class caches or native binaries.
        imported = ROOT / "app" / ".godot" / "imported"
        if os.path.lexists(imported):
            if imported.is_symlink() or not imported.is_dir():
                raise SetupError("import cache must be a regular directory")

            def no_cache_links(parent, names):
                for name in names:
                    item = Path(parent) / name
                    if item.is_symlink() or (hasattr(item, "is_junction") and item.is_junction()):
                        raise SetupError(f"import cache link is not supported: {item}")
                return ()

            destination = base / "app" / ".godot" / "imported"
            destination.parent.mkdir(parents=True)
            shutil.copytree(imported, destination, symlinks=True, ignore=no_cache_links, copy_function=copy)
        _extract_archive_stream(base, rev, paths)
        return base

    shutil.copytree(ROOT / "app", base / "app", symlinks=True, ignore=COPY_IGNORE, copy_function=copy)
    shutil.copytree(ROOT / "tools" / "flight_log", base / "tools" / "flight_log", symlinks=True, copy_function=copy)
    # tools/flight_log/flight_log.py loads the Mac receipt helper by path at import time.
    (base / "tools" / "release").mkdir(parents=True, exist_ok=True)
    copy(ROOT / "tools" / "release" / "macos_reference_receipt.py",
         base / "tools" / "release" / "macos_reference_receipt.py")
    for directory in directories:
        shutil.rmtree(base / directory)
    paths = list(directories)
    if copy_mode == "clone":
        _scoped_solver_archive(base, rev, paths)
    else:
        archive = workspace / "base-solver.tar"
        with archive.open("wb") as handle:
            result = subprocess.run(["git", "archive", rev, *paths], cwd=ROOT, stdout=handle, stderr=subprocess.PIPE)
        if result.returncode:
            raise SetupError(f"git archive {rev}: {result.stderr.decode(errors='replace').strip()}")
        with tarfile.open(archive) as tar:
            tar.extractall(base, filter="data")
        archive.unlink()
    return base


def replay(godot: str, project: Path, tape: Path, candidate: str, out: Path) -> dict:
    command = [sys.executable, str(project / "tools" / "flight_log" / "flight_log.py"), "replay", str(tape),
               "--godot", godot, "--candidate", str(project / candidate), "--out", str(out)]
    result = run(command, timeout=900)
    report_path, csv_path = out / "replay.json", out / "flight.csv"
    report = json.loads(report_path.read_text()) if report_path.is_file() else {}
    if result.returncode or not report.get("complete") or not csv_path.is_file():
        log = (out / "godot.log").read_text(errors="replace") if (out / "godot.log").is_file() else ""
        detail = (result.stdout + result.stderr + log).strip().splitlines()
        raise SetupError(f"replay of {tape.name} in {project.name} failed: {' | '.join(detail[-4:])}")
    with csv_path.open() as csv_file:
        rows = sum(1 for _ in csv_file) - 1
    return {"csv": csv_path, "csv_sha256": sha256_file(csv_path), "rows": rows,
            "source_sha256": report.get("source_sha256")}


def csv_difference(base_csv: Path, head_csv: Path) -> dict:
    """First differing row and the columns with the largest absolute differences."""
    with base_csv.open(newline="") as a, head_csv.open(newline="") as b:
        base_rows, head_rows = list(csv.reader(a)), list(csv.reader(b))
    if not base_rows or not head_rows or base_rows[0] != head_rows[0]:
        return {"header_changed": True, "base_columns": len(base_rows[0]) if base_rows else 0,
                "head_columns": len(head_rows[0]) if head_rows else 0}
    header = base_rows[0]
    first_row, worst = None, {}
    for index, (left, right) in enumerate(zip(base_rows[1:], head_rows[1:]), start=1):
        if left == right:
            continue
        first_row = index if first_row is None else first_row
        for column, (x, y) in enumerate(zip(left, right)):
            if x == y:
                continue
            try:
                delta = abs(float(x) - float(y))
            except ValueError:
                delta = math.inf
            name = header[column] if column < len(header) else str(column)
            worst[name] = max(worst.get(name, 0.0), delta)
    largest = sorted(worst.items(), key=lambda item: -item[1])[:DIFF_COLUMNS_REPORTED]
    return {"header_changed": False, "rows_base": len(base_rows) - 1, "rows_head": len(head_rows) - 1,
            "first_differing_row": first_row, "columns_changed": len(worst),
            "largest_abs_differences": {name: (None if math.isinf(value) else value) for name, value in largest}}


def solver_tree_is_committed(directories: list[str]) -> bool:
    tracked = run(["git", "diff", "--quiet", "HEAD", "--", *directories]).returncode == 0
    untracked = git("ls-files", "--others", "--exclude-standard", "--", *directories)
    return tracked and not untracked


def repin_profile(profile: Path, old: str, new: str) -> None:
    text = profile.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SetupError(f"{profile} must contain the pinned identity exactly once")
    data = json.loads(text.replace(old, new))
    if data["solver"]["sha256"] != new:
        raise SetupError(f"{profile}: the replaced identity is not the solver pin")
    profile.write_text(text.replace(old, new), encoding="utf-8")


def compare(godot: str, qualification: dict, jobs: int, keep: bool,
            workspace_root: Path | None = None, scope: str = "solver",
            prepared_tapes: tuple[PreparedTape, ...] | None = None,
            copy_mode: str = "copy") -> tuple[list[dict], str]:
    accepted = qualification["accepted"]
    directories = qualification["solver_directories"]
    parent = (workspace_root if workspace_root is not None else ROOT / "tmp").resolve()
    parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="companion-rebind-", dir=parent))
    try:
        base = build_baseline(workspace, accepted["rev"], directories, scope, copy_mode)
        base_identity = solver_identity(godot, base / "app")
        if base_identity != accepted["solver_sha256"]:
            raise SetupError(f"accepted rev {accepted['rev'][:8]} reproduces {base_identity[:8]}, "
                             f"not the accepted {accepted['solver_sha256'][:8]}; fix qualification.json")
        with contextlib.ExitStack() as stack:
            tapes = prepared_tapes if prepared_tapes is not None else stack.enter_context(
                materialized_tapes(qualification, workspace_root))
            _check_materialized_tapes(tapes)
            work = {(side, tape): (project, workspace / side / tape.logical_name)
                    for tape in tapes for side, project in (("base", base), ("head", ROOT))}
            with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
                futures = {key: pool.submit(replay, godot, project, key[1].path,
                                            qualification["candidate_aircraft"], out)
                           for key, (project, out) in work.items()}
                outputs = {key: future.result() for key, future in futures.items()}
            _check_materialized_tapes(tapes)
            results = []
            for tape in tapes:
                base_out, head_out = outputs[("base", tape)], outputs[("head", tape)]
                if tape.compressed:
                    for side, child in (("base", base_out), ("head", head_out)):
                        reported = child.get("source_sha256")
                        if not isinstance(reported, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", reported) \
                                or reported.lower() != tape.orfl_sha256:
                            raise SetupError(f"{side} replay source SHA-256 missing or differs: {tape.source}")
                identical = base_out["csv_sha256"] == head_out["csv_sha256"]
                raw_sha256 = sha256_file(tape.path)
                if tape.compressed and raw_sha256 != tape.orfl_sha256:
                    raise SetupError(f"materialized ORFL changed: {tape.source}")
                entry = {"tape": str(tape.source.relative_to(ROOT)), "orfl_sha256": raw_sha256,
                         "rows": head_out["rows"], "base_csv_sha256": base_out["csv_sha256"],
                         "head_csv_sha256": head_out["csv_sha256"], "identical": identical}
                if tape.compressed:
                    entry.update(tape_encoding="gzip", stored_sha256=tape.stored_sha256,
                                 base_replay_source_sha256=base_out["source_sha256"],
                                 head_replay_source_sha256=head_out["source_sha256"])
                if not identical:
                    entry["difference"] = csv_difference(base_out["csv"], head_out["csv"])
                results.append(entry)
            return results, str(workspace)
    finally:
        if not keep:
            shutil.rmtree(workspace, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--accept", action="store_true", help="re-pin the profile when every tape is identical")
    parser.add_argument("--godot", help="Godot executable (default: app/get-godot.sh)")
    parser.add_argument("--jobs", type=int, default=max(1, min(6, (os.cpu_count() or 2) // 2)))
    parser.add_argument("--report", type=Path, help="also write the full JSON report to this new file")
    parser.add_argument("--keep", action="store_true", help="keep the disposable project copies")
    parser.add_argument("--baseline", choices=("solver", "full"), default="solver",
                        help="accepted-revision content in the base copy: solver directories (default) or "
                             "every tracked app file and the replay tooling")
    parser.add_argument("--copy-mode", choices=("copy", "clone"), default="copy",
                        help="clone uses exclusive macOS clonefile without copy fallback (default: copy)")
    parser.add_argument("--workspace-root", type=Path,
                        help="parent for disposable project copies (default: repository tmp/)")
    args = parser.parse_args()
    try:
        if args.copy_mode == "clone":
            _copy_function(args.copy_mode)  # Refuse unsupported hosts even if no rebind is needed.
        qualification = json.loads(QUALIFICATION.read_text(encoding="utf-8"))
        profile = ROOT / qualification["profile"]
        godot = args.godot or default_godot()
        pinned = pinned_identity(profile)
        if pinned != qualification["accepted"]["solver_sha256"]:
            raise SetupError(f"profile pins {pinned[:8]} but qualification.json accepts "
                             f"{qualification['accepted']['solver_sha256'][:8]}; they must agree")
        validate_engine(godot, profile)
        with materialized_tapes(qualification, args.workspace_root) as tapes:
            paths = tuple(tape.path for tape in tapes)
            expected = {str(tape.path): tape.orfl_sha256 for tape in tapes if tape.compressed}
            current = solver_identity(godot, ROOT / "app", paths, expected) if expected else \
                solver_identity(godot, ROOT / "app", paths)
            _check_materialized_tapes(tapes)
            for tape in tapes:
                if tape.compressed:
                    print(f"  inspected {tape.source.relative_to(ROOT)}: stored_sha256={tape.stored_sha256} "
                          f"orfl_sha256={tape.orfl_sha256}")
            if current == pinned:
                print(f"Companion qualification is current ({current[:8]}); nothing to re-bind.")
                return 0
            print(f"Solver identity changed: accepted {pinned[:8]} -> current {current[:8]}. "
                  f"Replaying {len(qualification['tapes'])} tapes on both sides...", flush=True)
            results, workspace = compare(godot, qualification, args.jobs, args.keep, args.workspace_root,
                                         args.baseline, tapes, args.copy_mode)
            _check_materialized_tapes(tapes)
    except (SetupError, OSError, KeyError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"rebind: setup error: {error}", file=sys.stderr)
        return 2

    identical = all(entry["identical"] for entry in results)
    for entry in results:
        status = "identical" if entry["identical"] else "CHANGED"
        print(f"  {status:9} {Path(entry['tape']).stem} ({entry['rows']} rows)")
        if not entry["identical"]:
            print(f"            {json.dumps(entry['difference'])}")
    changed_sources = git("diff", "--name-only", qualification["accepted"]["rev"], "--",
                          *qualification["solver_directories"]).splitlines()
    report = {"format": RECEIPT_FORMAT, "date": datetime.date.today().isoformat(),
              "accepted_before": qualification["accepted"], "current_solver_sha256": current,
              "head": git("rev-parse", "HEAD"), "solver_tree_committed": solver_tree_is_committed(
                  qualification["solver_directories"]), "changed_sources": changed_sources,
              "candidate_aircraft": qualification["candidate_aircraft"], "identical": identical, "tapes": results,
              "baseline": args.baseline, "copy_mode": args.copy_mode,
              "method": ("Candidate replays of the retained tapes on two disposable copies differing only in the "
                         "solver directories (accepted rev vs current tree); CSV bytes compared."
                         if args.baseline == "solver" else
                         "Candidate replays of the retained tapes on the accepted revision's tracked app and replay "
                         "tooling vs the current tree; CSV bytes compared."),
              "limits": "Parity on these tapes only; not exact replay, not a new qualification, not physical "
                        "validation."}
    if args.keep:
        report["workspace"] = workspace
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not identical:
        print("Behaviour changed on the tapes above: this needs a new companion qualification, not a re-bind.")
        return 1
    if not args.accept:
        print("All tapes identical. Commit the physics change, then re-run with --accept to re-pin.")
        return 0
    if not report["solver_tree_committed"]:
        print("rebind: commit app/physics, app/sim and app/failures first; the accepted rev must hold them.",
              file=sys.stderr)
        return 2
    try:
        repin_profile(profile, pinned, current)
    except SetupError as error:
        print(f"rebind: {error}", file=sys.stderr)
        return 2
    qualification["accepted"] = {"solver_sha256": current, "rev": report["head"]}
    QUALIFICATION.write_text(json.dumps(qualification, indent=2) + "\n", encoding="utf-8")
    receipts = ROOT / qualification["receipts"]
    receipts.mkdir(parents=True, exist_ok=True)
    receipt = receipts / f"{report['date']}-{pinned[:8]}-to-{current[:8]}.json"
    receipt.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Re-pinned {profile.relative_to(ROOT)} to {current[:8]}; receipt {receipt.relative_to(ROOT)}.")
    print("Commit the profile, tools/companions/qualification.json and the receipt together.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
