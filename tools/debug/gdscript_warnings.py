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
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EXCLUDE = ("captures/", ".godot/")
SEVERITY = {1: "error", 2: "warning", 3: "information", 4: "hint"}


class Lsp:
    """Content-Length framed JSON-RPC over TCP; only what collecting diagnostics needs."""

    def __init__(self, port: int, deadline: float, process: subprocess.Popen) -> None:
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
                break
            except OSError:
                if time.monotonic() > deadline or process.poll() is not None:
                    raise RuntimeError("the editor's language server did not start (see editor.log)")
                time.sleep(1)
        self.buffer = b""
        self.next_id = 1

    def send(self, message: dict) -> None:
        data = json.dumps({"jsonrpc": "2.0", **message}).encode()
        self.sock.sendall(b"Content-Length: %d\r\n\r\n" % len(data) + data)

    def request(self, method: str, params: dict, timeout: float) -> dict:
        self.next_id += 1
        self.send({"id": self.next_id, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message = self.read(deadline - time.monotonic())
            if message is not None and message.get("id") == self.next_id:
                return message
        raise TimeoutError(f"no reply to {method}")

    def read(self, timeout: float) -> dict | None:
        self.sock.settimeout(max(0.05, timeout))
        while True:
            if b"\r\n\r\n" in self.buffer:
                head, rest = self.buffer.split(b"\r\n\r\n", 1)
                length = next(int(line.split(b":")[1]) for line in head.split(b"\r\n")
                              if line.lower().startswith(b"content-length"))
                if len(rest) >= length:
                    self.buffer = rest[length:]
                    return json.loads(rest[:length])
            try:
                chunk = self.sock.recv(1 << 16)
            except socket.timeout:
                return None
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


def finding(relative: str, item: dict) -> dict:
    """One language-server diagnostic. Godot 4.8 sends the warning code in `code`; 4.7 prefixed the message."""
    text = item.get("message", "")
    prefix = re.match(r"\(([A-Z_]+)\)", text)
    code = item.get("code") if isinstance(item.get("code"), str) and item.get("code") else (prefix.group(1) if prefix else "ERROR")
    return {"file": relative, "line": item["range"]["start"]["line"] + 1,
            "severity": SEVERITY.get(item.get("severity"), str(item.get("severity"))),
            "code": code, "message": text[prefix.end():].lstrip(" :").strip() if prefix else text}


def collect(app: Path, files: list[str], port: int, timeout: float, log: Path) -> list[dict]:
    godot = os.environ.get("OPENRC_GODOT") or subprocess.run([str(REPO / "app" / "get-godot.sh")], check=True,
                                                            capture_output=True, text=True).stdout.strip()
    process = subprocess.Popen([godot, "--editor", "--headless", "--path", str(app), "--lsp-port", str(port)],
                               stdout=open(log, "wb"), stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    findings: list[dict] = []
    try:
        lsp = Lsp(port, time.monotonic() + timeout, process)
        lsp.request("initialize", {"processId": os.getpid(), "rootUri": app.as_uri(), "capabilities": {}}, timeout)
        lsp.send({"method": "initialized", "params": {}})
        for index, relative in enumerate(files, 1):
            uri = (app / relative).as_uri()
            lsp.send({"method": "textDocument/didOpen", "params": {"textDocument": {
                "uri": uri, "languageId": "gdscript", "version": 1, "text": (app / relative).read_text(encoding="utf-8")}}})
            deadline = time.monotonic() + 30
            diagnostics = None
            while time.monotonic() < deadline:
                message = lsp.read(deadline - time.monotonic())
                if message and message.get("method") == "textDocument/publishDiagnostics" and message["params"]["uri"] == uri:
                    diagnostics = message["params"]["diagnostics"]
                    break
            if diagnostics is None:
                findings.append({"file": relative, "line": 0, "severity": "tool", "code": "NO_DIAGNOSTICS",
                                 "message": "the language server sent no diagnostics within 30 s"})
                continue
            lsp.send({"method": "textDocument/didClose", "params": {"textDocument": {"uri": uri}}})
            findings.extend(finding(relative, item) for item in diagnostics)
            if index % 200 == 0:
                print(f"# {index}/{len(files)} scripts", file=sys.stderr, flush=True)
    finally:
        process.terminate()
        try:
            process.wait(20)
        except subprocess.TimeoutExpired:
            process.kill()
    return findings


def main(argv: list[str]) -> int:
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    option = lambda name, default=None: argv[argv.index(name) + 1] if name in argv else default  # noqa: E731
    patterns = [argv[i + 1] for i, arg in enumerate(argv) if arg == "--files"]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out = REPO / "tmp" / "gdscript-warnings" / stamp
    out.mkdir(parents=True, exist_ok=False)
    try:
        app = REPO / "app" if "--in-place" in argv else snapshot(out)
        files = scripts(app, patterns)
        if not files:
            print("no scripts match", file=sys.stderr)
            return 2
        started = time.monotonic()
        findings = collect(app, files, int(option("--port", "6011")), float(option("--timeout", "300")), out / "editor.log")
    except (OSError, RuntimeError, TimeoutError, ConnectionError, subprocess.CalledProcessError) as error:
        print(f"gdscript_warnings: {error}; see {out}", file=sys.stderr)
        return 2
    finally:
        if "--in-place" not in argv and "--keep-snapshot" not in argv:
            shutil.rmtree(out / "snapshot", ignore_errors=True)
    report = {"format": "openrc-gdscript-diagnostics v1", "scripts": len(files), "seconds": round(time.monotonic() - started, 1),
              "findings": findings}
    by_code: dict[str, int] = {}
    for finding in findings:
        by_code[finding["code"]] = by_code.get(finding["code"], 0) + 1
    report["by_code"] = dict(sorted(by_code.items(), key=lambda item: -item[1]))
    (out / "report.json").write_text(json.dumps(report, indent=1) + "\n")
    if option("--out"):
        Path(option("--out")).write_text(json.dumps(report, indent=1) + "\n")
    if option("--write-baseline"):
        keys = sorted({key(f) for f in findings if f["severity"] == "warning"})
        Path(option("--write-baseline")).write_text(json.dumps({"format": "openrc-gdscript-warning-baseline v1",
                                                                "keys": keys}, indent=1, ensure_ascii=False) + "\n")
    errors = [f for f in findings if f["severity"] in ("error", "tool")]
    new = findings if not option("--baseline") else []
    if option("--baseline"):
        known = set(json.loads(Path(option("--baseline")).read_text())["keys"])
        new = [f for f in findings if f["severity"] == "warning" and key(f) not in known]
    for code, count in report["by_code"].items():
        print(f"{count:>6} {code}")
    for finding in (errors + [f for f in new if f not in errors])[:200]:
        print(f"{finding['severity'].upper():<8} app/{finding['file']}:{finding['line']} ({finding['code']}) {finding['message']}")
    label = "new warnings" if option("--baseline") else "warnings"
    print(f"# {len(files)} scripts in {report['seconds']} s: {len(errors)} errors, "
          f"{len(new) if option('--baseline') else sum(f['severity'] == 'warning' for f in findings)} {label}; report {out / 'report.json'}")
    return 1 if errors or (option("--baseline") and new) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
