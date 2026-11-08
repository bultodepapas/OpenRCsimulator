#!/usr/bin/env python3
"""GDScript compiler diagnostics for every script, from Godot's own language server (PT1h-R8). Standard library only.

Starts the pinned editor headless with --lsp-port on a snapshot of app/ (the shared tree is never opened by an
editor), opens each script and collects the errors and warnings the engine's compiler reports, with the project's
own warning settings. Without --baseline it prints a summary; with --baseline FILE it fails only on findings not in
the baseline, keyed by file, warning code and message without line numbers (edits elsewhere in a file keep matching).

  gdscript_warnings.py [--files 'debug/*.gd' ...] [--out report.json] [--baseline FILE] [--write-baseline FILE]
                       [--in-place] [--keep-snapshot] [--port N] [--timeout S]

Exit status: 0 no errors and nothing new, 1 compiler errors or new warnings, 2 tool failure. Guide: tools/debug/README.md.
"""
from __future__ import annotations

import fnmatch
import json
import math
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote, urlsplit

import debugctl

REPO = Path(__file__).resolve().parents[2]
EXCLUDE = ("captures/", ".godot/")
SEVERITY = {1: "error", 2: "warning", 3: "information", 4: "hint"}


def connection_owned(sock: socket.socket, pid: int, timeout: float = 2) -> bool:
    """Prove ownership of the connected server endpoint, not just a shared LISTEN port.

    Use native OS inventories; unavailable evidence fails the scan closed. No LSP
    request (including source text) is sent until this exact connection is owned.
    """
    server, client = sock.getpeername(), sock.getsockname()
    local, remote = f"{server[0]}:{server[1]}", f"{client[0]}:{client[1]}"
    if sys.platform == "win32":
        result = subprocess.run(["netstat.exe", "-ano", "-p", "tcp"], capture_output=True,
                                text=True, check=True, timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)
        return any(len(row) == 5 and row[0] == "TCP" and row[1:3] == [local, remote] and row[3] == "ESTABLISHED"
                   and row[-1] == str(pid) for row in map(str.split, result.stdout.splitlines()))
    if sys.platform == "darwin":
        result = subprocess.run(["/usr/sbin/lsof", "-nP", "-a", "-p", str(pid), "-iTCP",
                                 "-sTCP:ESTABLISHED", "-Fpn"], capture_output=True, text=True, timeout=timeout)
        if result.returncode not in (0, 1) or result.stderr:
            raise RuntimeError("cannot verify editor TCP ownership with lsof: " + result.stderr.strip())
        return f"p{pid}" in result.stdout.splitlines() and f"n{local}->{remote}" in result.stdout.splitlines()
    if sys.platform.startswith("linux"):
        owned = set()
        for path in (Path("/proc") / str(pid) / "fd").iterdir():
            try:
                owned.add(os.readlink(path))
            except FileNotFoundError:  # an unrelated editor descriptor closed during enumeration
                continue
        for table in ("tcp", "tcp6"):
            def address(endpoint):
                packed = (socket.inet_aton(endpoint[0]) if table == "tcp" else
                          socket.inet_pton(socket.AF_INET6, "::ffff:" + endpoint[0]))
                host = "".join(f"{int.from_bytes(packed[i:i + 4], sys.byteorder):08X}"
                               for i in range(0, len(packed), 4))
                return f"{host}:{endpoint[1]:04X}"
            path = Path("/proc") / str(pid) / "net" / table
            if table == "tcp6" and not path.exists():
                continue
            for line in path.read_text(encoding="ascii").splitlines()[1:]:
                row = line.split()
                if (row[1:3] == [address(server), address(client)] and row[3] == "01"
                        and f"socket:[{row[9]}]" in owned):
                    return True
        return False
    raise RuntimeError(f"editor TCP ownership is unsupported on {sys.platform}")


def same_document_uri(first: str, second: str) -> bool:
    def local_path(uri):
        parts = urlsplit(uri)
        if parts.scheme != "file" or parts.netloc not in ("", "localhost") or parts.query or parts.fragment:
            return None
        return os.path.normcase(unquote(parts.path))
    left, right = local_path(first), local_path(second)
    return left is not None and left == right


class Lsp:
    """Content-Length framed JSON-RPC over TCP; only what collecting diagnostics needs."""

    def __init__(self, port: int, deadline: float, process: subprocess.Popen) -> None:
        self.process = process
        self.buffer = b""
        self.next_id = 1
        while True:
            self.check_alive()
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("the editor's language server did not start (see editor.log)")
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=min(0.25, remaining))
                break
            except OSError:
                time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        try:
            # The OS can expose the accepted socket a little after connect succeeds.
            ownership_deadline = min(deadline, time.monotonic() + 3)
            while True:
                self.check_alive()
                remaining = ownership_deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError("cannot prove the LSP connection belongs to the launched editor")
                if connection_owned(self.sock, process.pid, min(2, remaining)):
                    self.check_alive()
                    break
                if time.monotonic() >= ownership_deadline:
                    raise RuntimeError("cannot prove the LSP connection belongs to the launched editor")
                time.sleep(0.05)
        except subprocess.SubprocessError as error:
            self.sock.close()
            raise RuntimeError("cannot prove editor connection ownership: OS inventory failed") from error
        except BaseException:
            self.sock.close()
            raise

    def check_alive(self) -> None:
        status = self.process.poll()
        if status is not None:
            raise RuntimeError(f"the launched editor exited during diagnostics (exit {status}; see editor.log)")

    def send(self, message: dict) -> None:
        self.check_alive()
        data = json.dumps({"jsonrpc": "2.0", **message}).encode()
        self.sock.settimeout(2)
        self.sock.sendall(b"Content-Length: %d\r\n\r\n" % len(data) + data)
        self.check_alive()

    def request(self, method: str, params: dict, timeout: float) -> dict:
        self.next_id += 1
        self.send({"id": self.next_id, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message = self.read(deadline - time.monotonic())
            if message is not None and message.get("id") == self.next_id:
                if "error" in message or "result" not in message:
                    raise RuntimeError(f"language server refused {method}: {message}")
                return message
        raise TimeoutError(f"no reply to {method}")

    def read(self, timeout: float) -> dict | None:
        deadline = time.monotonic() + timeout
        while True:
            self.check_alive()
            if b"\r\n\r\n" in self.buffer:
                head, rest = self.buffer.split(b"\r\n\r\n", 1)
                length = next(int(line.split(b":")[1]) for line in head.split(b"\r\n")
                              if line.lower().startswith(b"content-length"))
                if len(rest) >= length:
                    self.buffer = rest[length:]
                    return json.loads(rest[:length])
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            self.sock.settimeout(min(0.25, remaining))
            try:
                chunk = self.sock.recv(1 << 16)
            except socket.timeout:
                continue
            if not chunk:
                raise ConnectionError("the language server closed the connection")
            self.buffer += chunk


def scripts(app: Path, patterns: list[str]) -> list[str]:
    found = []
    for path in sorted(app.rglob("*.gd")):
        relative = path.relative_to(app).as_posix()
        if any(relative.startswith(prefix) for prefix in EXCLUDE):
            continue
        if not patterns or any(fnmatch.fnmatch(relative, pattern) for pattern in patterns):
            found.append(relative)
    return found


def snapshot(out: Path) -> Path:
    """A disposable copy of app/ (with its import cache) beside links to the other top-level folders, which scripts
    reach as res://../assets, res://../tools and so on."""
    target = out / "snapshot"
    shutil.copytree(REPO / "app", target / "app", symlinks=True, ignore=shutil.ignore_patterns("captures"))
    for sibling in REPO.iterdir():
        if sibling.is_dir() and sibling.name not in ("app", "tmp", ".git"):
            (target / sibling.name).symlink_to(sibling, target_is_directory=True)
    return target / "app"


def key(finding: dict) -> str:
    message = re.sub(r"\bline \d+\b", "line #", finding["message"])  # "declared at line 105" moves with edits
    return f"{finding['file']}|{finding['code']}|{message}"


def diagnostic_finding(relative: str, item: dict) -> dict:
    """One language-server diagnostic. Godot 4.8 sends the warning code in `code`; 4.7 prefixed the message."""
    text = item.get("message", "")
    prefix = re.match(r"\(([A-Z_]+)\)", text)
    code = item.get("code")
    if not isinstance(code, str) or not code:
        code = prefix.group(1) if prefix else "ERROR"
    return {"file": relative, "line": item["range"]["start"]["line"] + 1,
            "severity": SEVERITY.get(item.get("severity"), str(item.get("severity"))),
            "code": code, "message": text[prefix.end():].lstrip(" :").strip() if prefix else text}


def aliases(first: Path, second: Path) -> bool:
    return (first.resolve() == second.resolve()
            or (first.exists() and second.exists() and first.samefile(second)))


def validate_outputs(reports: list[Path], baseline: Path | None, baseline_out: Path | None) -> None:
    """Refuse source and baseline aliases, including existing hard links and symlinks."""
    destinations = reports + ([baseline_out] if baseline_out is not None else [])
    for report in reports:
        for protected in (baseline, baseline_out):
            if protected is not None and aliases(report, protected):
                raise ValueError(f"report {report} aliases a baseline")
    repo = REPO.resolve()
    for destination in destinations:
        target = destination.resolve()
        if target.is_relative_to(repo) and target.suffix.lower() == ".gd":
            raise ValueError(f"output {destination} aliases a repository GDScript source")
        for protected in (Path(__file__), REPO / "app" / "project.godot"):
            if aliases(destination, protected):
                raise ValueError(f"output {destination} aliases a source or project file")
    identities = {}
    for destination in destinations:
        try:
            information = destination.stat()
        except FileNotFoundError:
            continue
        identities[(information.st_dev, information.st_ino)] = destination
    if not identities:
        return

    def onerror(error):
        raise error

    # Existing destinations may be hard links with arbitrary names. Inspect all
    # repository scripts, including those outside the selected scan. Scratch and
    # editor caches are not repository sources.
    for root, dirs, names in os.walk(REPO, onerror=onerror):
        dirs[:] = [name for name in dirs if name not in (".git", ".godot")
                   and not (Path(root) == REPO and name == "tmp")]
        for name in names:
            if not name.lower().endswith(".gd"):
                continue
            source = Path(root) / name
            try:
                information = source.stat()
            except FileNotFoundError:  # a dangling source symlink has no hard-link identity
                continue
            destination = identities.get((information.st_dev, information.st_ino))
            if destination is not None:
                raise ValueError(f"output {destination} aliases repository source {source}")


def atomic_write(path: Path, contents: str) -> None:
    """Publish a completed UTF-8 file, following destination symlinks as before."""
    target = path.resolve()
    try:
        mode = stat.S_IMODE(target.stat().st_mode)
    except FileNotFoundError:
        mode = None
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n",
                                         dir=target.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(contents)
            stream.flush()
            if mode is not None:
                os.chmod(temporary, mode)
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def collect(app: Path, files: list[str], port: int, timeout: float, log: Path) -> list[dict]:
    if not 0 <= port <= 65535 or not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("port must be 0..65535 and timeout must be positive and finite")
    app = app.resolve()
    executable = debugctl.godot()
    godot = Path(shutil.which(executable) or executable).resolve()
    # The Windows console wrapper spawns the editor under another PID. Launch the
    # sibling editor directly so Popen and the accepted TCP connection have one owner.
    if sys.platform == "win32" and godot.name.endswith("_console.exe"):
        godot = godot.with_name(godot.name.replace("_console.exe", ".exe"))
        if not godot.is_file():
            raise RuntimeError("cannot find the editor beside its Windows console wrapper")
    with socket.socket() as reservation:
        if os.name == "nt":
            reservation.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        reservation.bind(("127.0.0.1", port))
        port = reservation.getsockname()[1]
    # Binding proves initial availability only. The exact connection check closes
    # the release-to-editor-bind race, including noncooperating listeners.
    with log.open("wb") as output:
        process = subprocess.Popen([str(godot), "--editor", "--headless", "--path", str(app), "--lsp-port", str(port)],
                                   stdout=output, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                   **({"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}))
    findings: list[dict] = []
    lsp = None
    try:
        lsp = Lsp(port, time.monotonic() + timeout, process)
        lsp.request("initialize", {"processId": os.getpid(), "rootUri": app.as_uri(), "capabilities": {}}, timeout)
        lsp.send({"method": "initialized", "params": {}})
        for index, relative in enumerate(files, 1):
            uri = (app / relative).as_uri()
            lsp.send({"method": "textDocument/didOpen", "params": {"textDocument": {
                "uri": uri, "languageId": "gdscript", "version": 1, "text": (app / relative).read_text(encoding="utf-8")}}})
            deadline = time.monotonic() + min(30, timeout)
            diagnostics = None
            while time.monotonic() < deadline:
                message = lsp.read(deadline - time.monotonic())
                if (message and message.get("method") == "textDocument/publishDiagnostics"
                        and same_document_uri(message["params"]["uri"], uri)):
                    diagnostics = message["params"]["diagnostics"]
                    if not isinstance(diagnostics, list):
                        raise RuntimeError("language server diagnostics must be a list")
                    break
            if diagnostics is None:
                raise TimeoutError(f"no diagnostics for {relative}; scan incomplete")
            lsp.send({"method": "textDocument/didClose", "params": {"textDocument": {"uri": uri}}})
            findings.extend(diagnostic_finding(relative, item) for item in diagnostics)
            if index % 200 == 0:
                print(f"# {index}/{len(files)} scripts", file=sys.stderr, flush=True)
        lsp.check_alive()
        atomic_write(log.with_name("lsp-identity.json"), json.dumps({
            "editor_pid": process.pid, "executable": str(godot), "project": str(app),
            "server": lsp.sock.getpeername(), "client": lsp.sock.getsockname(),
            "ownership": "os-established-connection", "scripts": len(files), "complete": True,
        }, indent=2) + "\n")
    finally:
        if lsp is not None:
            lsp.sock.close()
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(20)
    return findings


def baseline_keys(path: Path) -> set[str]:
    prior = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(prior, dict) or not isinstance(prior.get("keys"), list) or not all(
            isinstance(value, str) for value in prior["keys"]):
        raise ValueError("baseline must contain a list of warning keys")
    return set(prior["keys"])


def main(argv: list[str]) -> int:
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    option = lambda name, default=None: argv[argv.index(name) + 1] if name in argv else default  # noqa: E731
    patterns = [argv[i + 1] for i, arg in enumerate(argv) if arg == "--files"]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out = REPO / "tmp" / "gdscript-warnings" / stamp
    baseline = Path(option("--baseline")) if option("--baseline") else None
    baseline_out = Path(option("--write-baseline")) if option("--write-baseline") else None
    report_out = Path(option("--out")) if option("--out") else None
    reports = [out / "report.json"] + ([report_out] if report_out is not None else [])
    owned_out = False
    try:
        known = None
        if baseline is not None:
            known = baseline_keys(baseline)
        validate_outputs(reports, baseline, baseline_out)
        prior_refresh = baseline_keys(baseline_out) if patterns and baseline_out and baseline_out.exists() else set()
        out.mkdir(parents=True, exist_ok=False)
        owned_out = True
        app = REPO / "app" if "--in-place" in argv else snapshot(out)
        files = scripts(app, patterns)
        if not files:
            print("no scripts match", file=sys.stderr)
            return 2
        started = time.monotonic()
        findings = collect(app, files, int(option("--port", "0")), float(option("--timeout", "300")), out / "editor.log")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"gdscript_warnings: {error}; see {out}", file=sys.stderr)
        return 2
    finally:
        if owned_out and "--in-place" not in argv and "--keep-snapshot" not in argv:
            shutil.rmtree(out / "snapshot", ignore_errors=True)
    complete = not any(f["severity"] == "tool" for f in findings)
    report = {"format": "openrc-gdscript-diagnostics v1", "scripts": len(files), "seconds": round(time.monotonic() - started, 1),
              "findings": findings, "complete": complete}
    by_code: dict[str, int] = {}
    for finding in findings:
        by_code[finding["code"]] = by_code.get(finding["code"], 0) + 1
    report["by_code"] = dict(sorted(by_code.items(), key=lambda item: -item[1]))
    errors = [f for f in findings if f["severity"] in ("error", "tool")]
    new = findings if known is None else [f for f in findings if f["severity"] == "warning" and key(f) not in known]
    try:
        report_text = json.dumps(report, indent=1) + "\n"
        selected = set(files)
        keys = sorted({key(f) for f in findings if f["severity"] == "warning"}
                      | {entry for entry in prior_refresh if entry.split("|", 1)[0] not in selected})
        baseline_text = json.dumps({"format": "openrc-gdscript-warning-baseline v1", "keys": keys},
                                   indent=1, ensure_ascii=False) + "\n"
        validate_outputs(reports, baseline, baseline_out)
        for destination in reports:
            atomic_write(destination, report_text)
        if baseline_out is not None and not errors:
            atomic_write(baseline_out, baseline_text)
    except (OSError, ValueError, TypeError, RecursionError) as error:
        print(f"gdscript_warnings: {error}; see {out}", file=sys.stderr)
        return 2
    for code, count in report["by_code"].items():
        print(f"{count:>6} {code}")
    for finding in (errors + [f for f in new if f not in errors])[:200]:
        print(f"{finding['severity'].upper():<8} app/{finding['file']}:{finding['line']} ({finding['code']}) {finding['message']}")
    label = "new warnings" if known is not None else "warnings"
    print(f"# {len(files)} scripts in {report['seconds']} s: {len(errors)} errors, "
          f"{len(new) if known is not None else sum(f['severity'] == 'warning' for f in findings)} {label}; report {out / 'report.json'}")
    return 2 if not complete else (1 if errors or (known is not None and new) else 0)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
