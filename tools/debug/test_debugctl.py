"""PT1h-R7: debugctl.py against a fake loopback bridge (no Godot): argument parsing, token, exit codes, output."""
from __future__ import annotations

import contextlib
import csv
import random
import io
import tempfile
import time
import json
import os
import socket
import sys
import threading
import unittest
from unittest.mock import patch
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
import debugctl  # noqa: E402


class FakeBridge:
    """Answers each connection's single JSON line like the Godot bridge and records the requests."""

    def __init__(self) -> None:
        self.server = socket.create_server(("127.0.0.1", 0))
        self.port = self.server.getsockname()[1]
        self.requests: list[dict] = []
        self.screens = ["home"]
        self.stuck = False
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                with conn.makefile() as stream:
                    line = stream.readline()
                if not line:
                    continue # Port-reservation probes connect without sending a bridge request.
                request = json.loads(line)
                self.requests.append(request)
                if request["cmd"] == "ui":
                    result = {"scope": "AppRoot/Home", "focus": "AppRoot/Home/Fly", "controls": [
                        {"path": "AppRoot/Home/Fly", "type": "Button", "text": "Fly", "focused": True, "disabled": False},
                        {"path": "AppRoot/Home/Wind", "type": "HSlider", "text": "Wind", "focused": False,
                         "value": 2.5, "min": 0, "max": 10}]}
                    reply = {"id": request["id"], "ok": True, "result": result}
                elif request["cmd"] == "nope":
                    reply = {"id": request["id"], "ok": False, "error": "unknown command 'nope'; try help"}
                elif request["cmd"] in ("open", "close", "state", "logs"):
                    reply = self._screens(request)
                elif request["cmd"] == "assert":
                    reply = {"id": request["id"], "ok": str(request["expr"]).lower() == "true", "error": "assertion failed: x"}
                elif request["cmd"] == "sample":
                    start = 24 * len([r for r in self.requests if r["cmd"] == "sample"])
                    rows = [[start + i * request["every_ticks"], 0.1 * i, i] for i in range(request["count"])]
                    reply = {"id": request["id"], "ok": True,
                             "result": {"columns": ["tick", "time_s"] + list(request["exprs"]), "rows": rows}}
                else:
                    reply = {"id": request["id"], "ok": True, "result": {"echo": request}}
                conn.sendall((json.dumps(reply) + "\n").encode())

    def _screens(self, request: dict) -> dict:
        command, ok, result = request["cmd"], True, None
        if command == "open" and "screen" not in request:
            result = ["pause", "settings", "help"]
        elif command == "open":
            ok = request["screen"] != "pause"
            if ok:
                self.screens.append(request["screen"])
                result = {"opened": request["screen"]}
        elif command == "close":
            if not self.stuck or self.screens[-1] != "help":
                self.screens.pop()
            result = {"closed": True}
        elif command == "state":
            result = {"route": "home", "screens": list(self.screens)}
        else:
            records = [{"seq": 6, "level": "script_error", "text": "boom"}] if request.get("since") else []
            result = {"last_seq": 5, "dropped": 0, "records": records if self.stuck else []}
        return {"id": request["id"], "ok": ok, "result": result, "error": "did not open here"}

    def close(self) -> None:
        with contextlib.suppress(OSError):
            self.server.shutdown(socket.SHUT_RDWR)  # wakes the blocked accept()
        self.server.close()


class DebugctlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bridge = FakeBridge()
        self.env = dict(os.environ)
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(self.bridge.port)
        os.environ.pop("OPENRC_DEBUG_TOKEN", None)
        self.tmp = tempfile.TemporaryDirectory()
        self.saved_current = debugctl.CURRENT
        self.saved_sessions = debugctl.SESSIONS
        debugctl.CURRENT = Path(self.tmp.name) / "current.json"
        debugctl.SESSIONS = Path(self.tmp.name) / "sessions"

    def tearDown(self) -> None:
        debugctl.CURRENT = self.saved_current
        debugctl.SESSIONS = self.saved_sessions
        self.tmp.cleanup()
        self.bridge.close()
        os.environ.clear()
        os.environ.update(self.env)

    def run_cli(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = debugctl.main(list(argv))
        return status, out.getvalue(), err.getvalue()

    def test_exported_launch_uses_packaged_executable_without_project_path(self) -> None:
        exe = Path(self.tmp.name) / "packaged app.exe"
        exe.touch()
        out = Path(self.tmp.name) / "exported-run"
        os.environ["OPENRC_GODOT"] = str(exe)
        process = SimpleNamespace(pid=12345)
        with patch.object(debugctl, "reserve_port", return_value=43210) as reserve, \
                patch.object(debugctl.subprocess, "run") as run, \
                patch.object(debugctl.subprocess, "Popen", return_value=process) as popen, \
                patch.object(debugctl, "wait_ready", return_value={"result": {"pid": 12346}}) as ready, \
                patch.object(debugctl.secrets, "token_hex", return_value="session-secret"):
            status, output, err = self.run_cli("launch", "--exported", "--headless", "--port", "43210",
                                                "--out", str(out), "--", "--quick-flight", "--app")
        self.assertEqual((status, err), (0, ""))
        reserve.assert_called_once_with(43210)
        run.assert_not_called()
        command = popen.call_args.args[0]
        self.assertEqual(command, [str(exe.resolve()), "--headless", "--audio-driver", "Dummy",
                                   "--", "--quick-flight", "--app"])
        self.assertNotIn("--path", command[:command.index("--")])
        kwargs = popen.call_args.kwargs
        self.assertEqual(kwargs["cwd"], debugctl.REPO)
        self.assertTrue(kwargs["start_new_session"])
        env = kwargs["env"]
        self.assertEqual((env["OPENRC_DEBUG_BRIDGE"], env["OPENRC_DEBUG_TOKEN"]), ("43210", "session-secret"))
        self.assertEqual(env["OPENRC_DEBUG_LOG"], str(out / "log.jsonl"))
        self.assertEqual(env["OPENRC_DEBUG_OUT"], str(out))
        self.assertEqual(env["APPDATA"], str(out / "profile"))
        self.assertEqual(env["XDG_DATA_HOME"], str(out / "profile"))
        ready.assert_called_once_with(180.0, process, 43210, out / "engine.log")
        self.assertEqual(json.loads(output)["pid"], 12346)
        self.assertEqual(json.loads((out / "launch.json").read_text())["command"], command)
        self.assertEqual(debugctl.session_for(43210)["token"], "session-secret")

    def test_source_launch_keeps_project_path_and_import(self) -> None:
        os.environ["OPENRC_GODOT"] = "source-godot"
        process = SimpleNamespace(pid=12345)
        source_copy = Path(self.tmp.name) / "source copy"
        for extra, expected_project, imported in (
                ([], debugctl.REPO / "app", False),
                (["--app", str(source_copy), "--import"], source_copy, True)):
            with self.subTest(imported=imported):
                out = Path(self.tmp.name) / f"source-run-{imported}"
                with patch.object(debugctl, "reserve_port", return_value=43210), \
                        patch.object(debugctl.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, \
                        patch.object(debugctl.subprocess, "Popen", return_value=process) as popen, \
                        patch.object(debugctl, "wait_ready", return_value={"result": {"pid": 12346}}):
                    status, _, err = self.run_cli("launch", "--headless", "--out", str(out), *extra,
                                                  "--", "--quick-flight")
                self.assertEqual((status, err), (0, ""))
                project = str(expected_project.resolve())
                self.assertEqual(popen.call_args.args[0], ["source-godot", "--path", project, "--headless",
                                                          "--audio-driver", "Dummy", "--", "--quick-flight"])
                if imported:
                    self.assertEqual(run.call_args.args[0], ["source-godot", "--headless", "--path", project,
                                                             "--audio-driver", "Dummy", "--import"])
                else:
                    run.assert_not_called()

    def test_exported_launch_rejects_invalid_options_before_claiming_port(self) -> None:
        exe = Path(self.tmp.name) / "packaged.exe"
        exe.touch()
        for override, args, message in (
                (None, [], "requires OPENRC_GODOT"),
                ("  ", [], "requires OPENRC_GODOT"),
                (str(exe.parent / "missing.exe"), [], "does not exist"),
                (str(exe.parent), [], "does not exist"),
                (str(exe), ["--import"], "--import cannot be used"),
                (str(exe), ["--app", "app"], "--app cannot be used")):
            with self.subTest(override=override, args=args):
                if override is None:
                    os.environ.pop("OPENRC_GODOT", None)
                else:
                    os.environ["OPENRC_GODOT"] = override
                with patch.object(debugctl, "reserve_port") as reserve, \
                        patch.object(debugctl.subprocess, "run") as run, \
                        patch.object(debugctl.subprocess, "Popen") as popen:
                    status, _, err = self.run_cli("launch", "--exported", "--headless", *args)
                self.assertEqual(status, 2)
                self.assertIn(message, err)
                reserve.assert_not_called()
                run.assert_not_called()
                popen.assert_not_called()
                self.assertFalse(debugctl.SESSIONS.exists())

    def test_failed_exported_launch_stops_only_its_own_process(self) -> None:
        exe = Path(self.tmp.name) / "packaged.exe"
        exe.touch()
        os.environ["OPENRC_GODOT"] = str(exe)
        out = Path(self.tmp.name) / "failed-run"
        process = SimpleNamespace(pid=12345)
        with patch.object(debugctl, "reserve_port", return_value=43210), \
                patch.object(debugctl.subprocess, "Popen", return_value=process), \
                patch.object(debugctl, "wait_ready", side_effect=RuntimeError("bridge unavailable")), \
                patch.object(debugctl, "kill_group") as kill:
            status, _, err = self.run_cli("launch", "--exported", "--headless", "--out", str(out))
        self.assertEqual(status, 2)
        self.assertIn("bridge unavailable", err)
        self.assertIn("require a debug template", err)
        kill.assert_called_once_with(12345)
        self.assertFalse((debugctl.SESSIONS / "43210.json").exists())
        self.assertFalse(debugctl.CURRENT.exists())

    def test_key_values_are_json_when_possible(self) -> None:
        status, out, _ = self.run_cli("sticks", "roll=0.4", "release=true", "text=Fly", 'expr=flight.session.sim.tick > 3')
        self.assertEqual(status, 0)
        sent = self.bridge.requests[-1]
        self.assertEqual((sent["cmd"], sent["roll"], sent["release"], sent["text"]), ("sticks", 0.4, True, "Fly"))
        self.assertEqual(sent["expr"], "flight.session.sim.tick > 3")
        self.assertEqual(json.loads(out)["echo"]["cmd"], "sticks")

    def test_token_is_sent_from_the_environment(self) -> None:
        os.environ["OPENRC_DEBUG_TOKEN"] = "s3cret"
        self.run_cli("ping")
        self.assertEqual(self.bridge.requests[-1]["token"], "s3cret")

    def test_bridge_errors_exit_one(self) -> None:
        status, out, err = self.run_cli("nope")
        self.assertEqual((status, out), (1, ""))
        self.assertIn("unknown command", err)

    def test_usage_and_connection_errors_exit_two(self) -> None:
        self.assertEqual(self.run_cli("press", "Fly")[0], 2)
        with socket.create_server(("127.0.0.1", 0)) as unused:
            free_port = unused.getsockname()[1]
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(free_port)  # nothing listens there now
        status, _, err = self.run_cli("ping")
        self.assertEqual(status, 2)
        self.assertIn("debugctl:", err)

    def test_ui_prints_a_table_and_json_on_request(self) -> None:
        status, out, _ = self.run_cli("ui")
        lines = out.splitlines()
        self.assertEqual(status, 0)
        self.assertTrue(lines[0].startswith("# scope AppRoot/Home"))
        self.assertTrue(lines[1].startswith("* Button") and lines[1].endswith(" Fly"), lines[1])
        self.assertTrue(self.run_cli("ui", "--paths")[1].splitlines()[1].endswith("AppRoot/Home/Fly"))
        self.assertIn("value=2.5 [0..10]", lines[2])
        self.assertEqual(json.loads(self.run_cli("ui", "--json")[1])["focus"], "AppRoot/Home/Fly")

    def test_last_launch_supplies_the_port(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        self.assertEqual(debugctl.port(), debugctl.DEFAULT_PORT)
        debugctl.CURRENT.write_text(json.dumps({"port": self.bridge.port, "pid": os.getpid()}))
        status, out, _ = self.run_cli("status")
        report = json.loads(out)
        self.assertEqual((status, report["port"], report["alive"], report["bridge"]), (0, self.bridge.port, True, True))

    def test_run_script_stops_at_the_first_failure(self) -> None:
        script = Path(self.tmp.name) / "repro.txt"
        script.write_text("# comment\nping\nassert expr=true\n\nassert expr=false\nping note='after failure'\n")
        status, out, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("line 5: assertion failed", err)
        self.assertNotIn("after failure", out)
        self.assertEqual([r["cmd"] for r in self.bridge.requests], ["ping", "assert", "assert"])
        status, out, _ = self.run_cli("run", str(script), "--keep-going")
        self.assertEqual(status, 1)
        self.assertEqual(self.bridge.requests[-1]["note"], "after failure")

    def test_run_executes_sibling_cleanup_after_success(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("ping note=main\n")
        script.with_suffix(".cleanup").write_text("ping note=cleanup\n")
        status, _, err = self.run_cli("run", str(script))
        self.assertEqual((status, err), (0, ""))
        self.assertEqual([r.get("note") for r in self.bridge.requests], ["main", "cleanup"])

    def test_run_executes_cleanup_after_assertion_and_keeps_original_failure(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("assert expr=false\nping note=unreached\n")
        script.with_suffix(".cleanup").write_text("ping note=cleanup\n")
        status, out, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("line 1: assertion failed", err)
        self.assertNotIn("unreached", out)
        self.assertEqual([r["cmd"] for r in self.bridge.requests], ["assert", "ping"])
        self.assertEqual(self.bridge.requests[-1]["note"], "cleanup")

    def test_cleanup_attempts_remaining_commands_and_reports_both_failures(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("assert expr=false\n")
        script.with_suffix(".cleanup").write_text("nope\nping note=after_cleanup_error\n")
        status, _, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("line 1: assertion failed", err)
        self.assertIn("cleanup line 1:", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "after_cleanup_error")
        script.write_text("ping note=main\n")
        status, _, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("cleanup line 1:", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "after_cleanup_error")

    def test_cleanup_attempts_commands_after_connection_failure_and_keeps_main_status(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("assert expr=false\n")
        script.with_suffix(".cleanup").write_text("ping note=connection_error\nping note=after_connection_error\n")
        original = debugctl.execute_line
        def execute(line):
            if "connection_error" in line and "after_connection_error" not in line:
                raise OSError("simulated connection failure")
            return original(line)
        with patch.object(debugctl, "execute_line", side_effect=execute):
            status, _, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)  # Original assertion failure remains the result.
        self.assertIn("line 1: assertion failed", err)
        self.assertIn("cleanup line 1: simulated connection failure", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "after_connection_error")

    def test_cleanup_file_is_not_recursively_executed(self) -> None:
        script = Path(self.tmp.name) / "scenario.cleanup"
        script.write_text("ping note=once\n")
        status, _, _ = self.run_cli("run", str(script))
        self.assertEqual(status, 0)
        self.assertEqual([r.get("note") for r in self.bridge.requests], ["once"])

    def test_cleanup_reports_engine_errors_when_requested(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("ping note=main\n")
        script.with_suffix(".cleanup").write_text("state note=cleanup1\nstate note=cleanup2\n")
        original_result = debugctl.result_of
        def result(command, *args, **kwargs):
            if command == "ping":
                return {"log_seq": 1}
            return original_result(command, *args, **kwargs)
        with patch.object(debugctl, "result_of", side_effect=result), \
                patch.object(debugctl, "new_errors", side_effect=[[], [{"level": "script_error", "text": "cleanup failure"}], []]), \
                patch.object(debugctl, "format_record", return_value="cleanup engine failure"):
            status, _, err = self.run_cli("run", str(script), "--fail-on-error")
        self.assertEqual(status, 1)
        self.assertIn("cleanup line 1: new engine errors: cleanup engine failure", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "cleanup2")

    def test_run_stdin_has_no_sibling_cleanup(self) -> None:
        (Path(self.tmp.name) / "-.cleanup").write_text("nope\n")
        with patch.object(sys, "stdin", io.StringIO("ping note=stdin\n")):
            status, _, err = self.run_cli("run", "-")
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(self.bridge.requests[-1]["note"], "stdin")

    def test_watch_streams_csv_in_chunks(self) -> None:
        target = Path(self.tmp.name) / "watch.csv"
        status, out, _ = self.run_cli("watch", "--every", "6", "--count", "13", "--csv", str(target), "height=-s[2]")
        self.assertEqual(status, 0)
        rows = list(csv.reader(io.StringIO(out)))
        self.assertEqual(rows[0], ["tick", "time_s", "height"])
        self.assertEqual(len(rows), 14)
        with target.open() as stream:
            self.assertEqual(rows, list(csv.reader(stream)))
        samples = [r for r in self.bridge.requests if r["cmd"] == "sample"]
        self.assertEqual([r["count"] for r in samples], [10, 3])
        self.assertEqual(samples[0]["exprs"], {"height": "-s[2]"})

    def test_crawl_opens_lists_and_closes_every_screen(self) -> None:
        status, out, _ = self.run_cli("crawl")
        self.assertEqual(status, 0, out)
        self.assertIn("pause           unavailable here", out)
        self.assertRegex(out, r"settings\s+ok\s+2 controls")
        self.assertTrue(out.rstrip().endswith("# 0 screen failures, 0 errors, 0 warnings"))

    def test_crawl_fails_on_a_screen_that_stays_open_or_new_errors(self) -> None:
        self.bridge.stuck = True
        status, out, _ = self.run_cli("crawl")
        self.assertEqual(status, 1)
        self.assertIn("help            did not return", out)
        self.assertIn("script_error", out)

    def test_clean_keeps_recent_runs_and_foreign_folders(self) -> None:
        saved = debugctl.RUNS
        debugctl.RUNS = Path(self.tmp.name) / "runs"
        try:
            for i in range(4):
                run = debugctl.RUNS / f"run-{i}"
                run.mkdir(parents=True)
                (run / "launch.json").write_text("{}")
                os.utime(run, (1000 + i, 1000 + i))
            (debugctl.RUNS / "notes").mkdir()
            os.utime(debugctl.RUNS / "notes", (1, 1))
            status, out, _ = self.run_cli("clean", "--keep", "2")
            self.assertEqual((status, json.loads(out)["removed"]), (0, 2))
            self.assertEqual(sorted(p.name for p in debugctl.RUNS.iterdir()), ["notes", "run-2", "run-3"])
        finally:
            debugctl.RUNS = saved

    def test_short_paths_drop_the_scope_and_generated_segments(self) -> None:
        path = "AppRoot/Settings/@Control@91/@CenterContainer@93/@VBoxContainer@95/@GridContainer@98/DisplayCategory"
        self.assertEqual(debugctl.short_path(path, "AppRoot/Settings"), "DisplayCategory")
        self.assertEqual(debugctl.short_path("AppRoot/Main/A/B/C/D", "AppRoot"), "B/C/D")

    def test_the_launch_token_is_sent_for_its_port_only(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        debugctl.CURRENT.write_text(json.dumps({"port": self.bridge.port, "token": "abc123"}))
        self.run_cli("ping")
        self.assertEqual(self.bridge.requests[-1]["token"], "abc123")
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(self.bridge.port + 1)  # another session's port: no stray token
        self.assertEqual(debugctl.token(), "")

    def test_enable_value_one_is_not_a_port(self) -> None:
        os.environ["OPENRC_DEBUG_BRIDGE"] = "1"
        self.assertIsNone(debugctl.env_port())
        self.assertEqual(debugctl.port(), debugctl.DEFAULT_PORT)

    def test_stop_without_a_session_says_so(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        status, _, err = self.run_cli("stop")
        self.assertEqual(status, 1)
        self.assertIn("no launched session", err)

    def test_quoted_values_stay_strings_in_scripts(self) -> None:
        words = debugctl.split_line('key name="2" note=\'a b\' count=3 exprs={"h":"-s[2]"}')
        values = [debugctl.parse_value(w.split("=", 1)[1]) for w in words[1:]]
        self.assertEqual(values, ["2", "a b", 3, {"h": "-s[2]"}])

    def test_exit_report_reads_crashes_and_leaks(self) -> None:
        log = Path(self.tmp.name) / "engine.log"
        log.write_text(
            "ERROR: probe crash\n   at: crash (core/core_bind.cpp:349)\n\n"
            "================================================================\n"
            "handle_crash: Program crashed with signal 4\nEngine version: Godot Engine v4.7.2\n"
            "Dumping the backtrace.\n[1] 788d6aa45330 (libc.so.6+45330)\n-- END OF C++ BACKTRACE --\n"
            "================================================================\nGDScript backtrace (most recent call first):\n"
            "    [0] deep (res://crash.gd:3)\n    [1] _init (res://crash.gd:5)\n-- END OF GDSCRIPT BACKTRACE --\n"
            "WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
            "Leaked instance: Node:123\n")
        report = debugctl.exit_report(log)
        self.assertEqual(report["leaked_objects"], 2)
        self.assertEqual(report["leaked_instances"], ["Node:123"])
        self.assertEqual(report["crash"]["reason"], "Program crashed with signal 4")
        self.assertEqual(report["crash"]["gdscript_backtrace"], ["[0] deep (res://crash.gd:3)", "[1] _init (res://crash.gd:5)"])
        log.write_text("clean exit\n")
        self.assertEqual(debugctl.exit_report(log), {"crash": None, "leaked_objects": 0})  # explicit, not silent

    def test_hitches_are_attributed_to_the_last_action_before_them(self) -> None:
        saved = debugctl.result_of
        debugctl.result_of = lambda cmd, args=None, **kw: {"hitches": [{"frame": 15, "ms": 80.0}, {"frame": 31, "ms": 60.0},
                                                                        {"frame": 2, "ms": 900.0}]}
        try:
            slow = debugctl.slow_actions([(10, "key name=\"F5\""), (30, "press text=\"Fly\""), (40, "close")])
        finally:
            debugctl.result_of = saved
        self.assertEqual(slow, {'key name="F5"': [80.0], 'press text="Fly"': [60.0]})

    def test_monkey_actions_are_reproducible_from_the_seed(self) -> None:
        controls = [{"text": "Fly", "path": "A/Fly", "type": "Button"},
                    {"text": "×", "path": "A/X1", "type": "Button"}, {"text": "×", "path": "A/X2", "type": "Button"},
                    {"text": "Wind", "path": "A/Wind", "type": "HSlider", "value": 1, "min": 0, "max": 10}]
        first = [debugctl.monkey_action(random.Random(5), controls, ["Kp Enter"]) for _ in range(1)]
        runs = [[debugctl.monkey_action(rng, controls, ["Kp Enter"]) for _ in range(40)] for rng in (random.Random(5), random.Random(5))]
        self.assertEqual(runs[0], runs[1])
        self.assertTrue(first)
        joined = "\n".join(runs[0])
        self.assertNotIn("\\u", joined)  # labels stay literal UTF-8
        self.assertIn('key name="Kp Enter"', joined)
        self.assertIn('path="A/X', joined)  # ambiguous labels are addressed by path
        for line in runs[0]:
            debugctl.split_line(line)  # every generated line reads back

    def test_port_claims_are_exclusive_and_stale_claims_are_taken_over(self) -> None:
        with socket.create_server(("127.0.0.1", 0)) as unused:
            free = unused.getsockname()[1]
        self.assertEqual(debugctl.reserve_port(free), free)  # claimed by this live process
        self.assertIsNone(debugctl.reserve_port(free))  # a second agent cannot take it
        claim = debugctl.SESSIONS / f"{free}.json"
        claim.write_text(json.dumps({"port": free, "launcher_pid": 999999999, "pid": 999999998}))
        self.assertEqual(debugctl.reserve_port(free), free)  # its processes are gone: taken over
        self.assertIsNone(debugctl.reserve_port(self.bridge.port))  # something already listens there

    def test_commands_follow_the_session_of_their_port(self) -> None:
        debugctl.SESSIONS.mkdir(parents=True)
        (debugctl.SESSIONS / f"{self.bridge.port}.json").write_text(json.dumps({"port": self.bridge.port, "token": "mine"}))
        debugctl.CURRENT.write_text(json.dumps({"port": self.bridge.port + 7, "token": "someone-else"}))  # another agent's launch
        self.run_cli("ping")
        self.assertEqual(self.bridge.requests[-1]["token"], "mine")

    def test_stop_refuses_to_guess_between_live_sessions(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        debugctl.SESSIONS.mkdir(parents=True)
        for number in (40001, 40002):
            (debugctl.SESSIONS / f"{number}.json").write_text(json.dumps({"port": number, "pid": os.getpid()}))
        debugctl.CURRENT.write_text(json.dumps({"port": 40002}))
        status, _, err = self.run_cli("stop")
        self.assertEqual(status, 2)
        self.assertIn("OPENRC_DEBUG_BRIDGE", err)

    def test_smoke_recovers_after_failed_scenario_and_skips_when_home_is_unavailable(self) -> None:
        scenarios = Path(self.tmp.name) / "scenarios"
        scenarios.mkdir()
        for name in ("a_broken", "b_next"):
            (scenarios / f"{name}.txt").write_text("# fixture\n")
        for recovery_available in (True, False):
            with self.subTest(recovery_available=recovery_available):
                state = {"home": True, "ran": []}

                def fake_launch(_args):
                    print(json.dumps({"port": self.bridge.port, "out": self.tmp.name}))
                    return 0

                def fake_stop(_args):
                    print(json.dumps({"crash": None, "leaked_objects": 0}))
                    return 0

                def reset(_args=None):
                    if not state["home"] and not recovery_available:
                        return 1
                    state["home"] = True
                    return 0

                def scenario(args):
                    self.assertTrue(state["home"], "scenario inherited a failed flight")
                    name = Path(args[0]).stem
                    state["ran"].append(name)
                    if name == "a_broken":
                        state["home"] = False
                        raise debugctl.Refused("intentional failed flight")
                    return 0

                output = io.StringIO()
                with patch.multiple(debugctl, SCENARIOS=scenarios, launch=fake_launch, stop=fake_stop,
                                    home_reset=reset, run_script=scenario, crawl=lambda _: 0,
                                    run_lines=lambda _: 0, monkey=lambda _: 0, soak=lambda _: 0,
                                    result_of=lambda _: {"hitch_total": 0}), contextlib.redirect_stdout(output):
                    status = debugctl.smoke([])
                report = json.loads(output.getvalue().strip().splitlines()[-1])
                self.assertEqual(status, 1)  # Recovery must never hide the original failure.
                self.assertFalse(report["ok"])
                self.assertIn("scenario a_broken", report["failed"])
                if recovery_available:
                    self.assertEqual(state["ran"], ["a_broken", "b_next"])
                    self.assertEqual(report["failed"], ["scenario a_broken"])
                else:
                    self.assertEqual(state["ran"], ["a_broken"])
                    self.assertIn("Home before scenario b_next", report["failed"])

    def test_home_reset_discards_only_workshop_guard_in_current_language(self) -> None:
        for guard in ("UnsavedBuildDialog", "StatisticsResetDialog"):
            with self.subTest(guard=guard):
                state = {"route": "home", "screens": ["home", "workshop"]}
                calls = []
                window = {"scope": f"AppRoot/Workshop/{guard}", "window": {"type": "ConfirmationDialog"}}

                def result(command, args=None):
                    calls.append((command, args))
                    if command == "state": return state
                    if command == "ui": return window
                    if command == "eval": return "Descartar cambios"
                    if command in ("press", "close"):
                        state["screens"] = ["home"]
                        window.clear()
                    return {}

                with patch.object(debugctl, "result_of", side_effect=result):
                    self.assertEqual(debugctl.home_reset(), 0)
                if guard == "UnsavedBuildDialog":
                    self.assertIn(("press", {"text": "Descartar cambios"}), calls)
                    self.assertFalse(any(command == "close" for command, _ in calls))
                else:
                    self.assertFalse(any(command == "press" for command, _ in calls))
                    self.assertIn(("close", {}), calls)

    def test_an_unreaped_exited_child_is_not_alive(self) -> None:
        if not Path("/proc/self/stat").exists():
            self.skipTest("needs /proc")
        import subprocess
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        deadline = time.monotonic() + 10
        while debugctl.alive(child.pid) and time.monotonic() < deadline:
            time.sleep(0.05)  # never reaped by wait() here: it stays a zombie
        self.assertFalse(debugctl.alive(child.pid))
        child.wait()


if __name__ == "__main__":
    unittest.main()
