"""MCP server protocol and tool mapping, against a stubbed bridge (no simulator needed)."""
from __future__ import annotations

import io
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import debugctl  # noqa: E402
import mcp_server  # noqa: E402

LOOK = {"route": "home", "screens": ["home", "settings"], "scope": "AppRoot/Settings", "focus": "e2",
        "controls": [{"ref": "e9", "role": "option", "name": "Window resolution", "value": "Automatic",
                      "options": ["Automatic", "1920 × 1080"]}],
        "next": ["close  (Esc/Back on the top dialog or menu)"]}


def fake_bridge(calls: list):
    def result_of(command, args=None, **_):
        calls.append((command, args or {}))
        if command == "look":
            return LOOK
        if command == "choose" and args.get("value") == "8K":
            raise debugctl.Refused("item '8K' not unique or not found")
        return {"done": command}
    return result_of


class McpServerTests(unittest.TestCase):
    def rpc(self, method, params=None, id_=1):
        return mcp_server.handle({"jsonrpc": "2.0", "id": id_, "method": method, "params": params or {}})

    def test_initialize_negotiates_and_lists_tools_with_schemas(self) -> None:
        reply = self.rpc("initialize", {"protocolVersion": "2025-06-18"})
        self.assertEqual(reply["result"]["protocolVersion"], "2025-06-18")
        self.assertIn("tools", reply["result"]["capabilities"])
        self.assertEqual(self.rpc("initialize", {"protocolVersion": "1999-01-01"})["result"]["protocolVersion"],
                         mcp_server.PROTOCOLS[0])
        tools = self.rpc("tools/list")["result"]["tools"]
        names = {tool["name"] for tool in tools}
        self.assertTrue({"sim_look", "sim_choose", "sim_fly", "sim_screenshot", "sim_command"} <= names)
        for tool in tools:
            self.assertEqual(tool["inputSchema"]["type"], "object", tool["name"])

    def test_notifications_get_no_reply_and_unknown_methods_an_error(self) -> None:
        self.assertIsNone(mcp_server.handle({"jsonrpc": "2.0", "method": "notifications/initialized"}))
        self.assertEqual(self.rpc("resources/list")["error"]["code"], -32601)
        self.assertEqual(self.rpc("tools/call", {"name": "sim_nope"})["error"]["code"], -32602)

    def test_choose_maps_to_the_bridge_and_answers_with_the_new_snapshot(self) -> None:
        calls: list = []
        with patch.object(debugctl, "result_of", fake_bridge(calls)):
            reply = self.rpc("tools/call", {"name": "sim_choose", "arguments": {"field": "Window resolution", "value": "1920 × 1080"}})
        result = reply["result"]
        self.assertFalse(result["isError"])
        self.assertEqual(calls[0], ("choose", {"field": "Window resolution", "value": "1920 × 1080"}))
        self.assertIn('e9            option   "Window resolution" = "Automatic"', result["content"][0]["text"])

    def test_refusals_and_missing_targets_are_tool_errors_not_protocol_errors(self) -> None:
        with patch.object(debugctl, "result_of", fake_bridge([])):
            refused = self.rpc("tools/call", {"name": "sim_choose", "arguments": {"ref": "e9", "value": "8K"}})
            unnamed = self.rpc("tools/call", {"name": "sim_press", "arguments": {}})
        self.assertTrue(refused["result"]["isError"])
        self.assertIn("8K", refused["result"]["content"][0]["text"])
        self.assertTrue(unnamed["result"]["isError"])
        self.assertIn("ref", unnamed["result"]["content"][0]["text"])

    def test_serve_speaks_newline_delimited_json_and_survives_garbage(self) -> None:
        stdin = io.StringIO('not json\n{"jsonrpc":"2.0","id":7,"method":"ping"}\n'
                            '{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        stdout = io.StringIO()
        mcp_server.serve(stdin, stdout)
        lines = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertEqual(lines[0]["error"]["code"], -32700)
        self.assertEqual(lines[1], {"jsonrpc": "2.0", "id": 7, "result": {}})
        self.assertEqual(len(lines), 2)

    def test_malformed_params_do_not_end_the_stream_or_invoke_tools(self) -> None:
        invalid = [
            {"method": "initialize", "params": value}
            for value in (True, 1, "params", [], [1], None)
        ] + [
            {"method": "tools/call", "params": value}
            for value in (True, [], [1], None)
        ] + [
            {"method": "tools/call", "params": {"name": value}}
            for value in ([], {}, True, 1, None)
        ] + [
            {"method": "tools/call", "params": {"name": "sim_stop", "arguments": value}}
            for value in (True, [], [1], "arguments", None)
        ]
        for request in invalid:
            with self.subTest(request=request), patch.object(mcp_server, "call_tool") as call:
                request = {"jsonrpc": "2.0", "id": 1, **request}
                ping = {"jsonrpc": "2.0", "id": "after", "method": "ping"}
                stdout = io.StringIO()
                mcp_server.serve(io.StringIO(json.dumps(request) + "\n" + json.dumps(ping) + "\n"), stdout)
                replies = [json.loads(line) for line in stdout.getvalue().splitlines()]
                self.assertEqual(replies[0]["id"], 1)
                self.assertEqual(replies[0]["error"]["code"], -32602)
                self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": "after", "result": {}})
                call.assert_not_called()

    def test_invalid_envelopes_are_reported_and_following_ping_is_served(self) -> None:
        invalid = [None, True, [], 7, "request", {},
                   {"jsonrpc": "1.0", "id": 1, "method": "ping"},
                   {"jsonrpc": "2.0", "id": 1, "method": []}]
        invalid += [{"jsonrpc": "2.0", "id": value, "method": "ping"}
                    for value in (None, True, [], {}, 1.5)]
        for request in invalid:
            with self.subTest(request=request):
                stdout = io.StringIO()
                mcp_server.serve(io.StringIO(json.dumps(request) + '\n{"jsonrpc":"2.0","id":2,"method":"ping"}\n'), stdout)
                replies = [json.loads(line) for line in stdout.getvalue().splitlines()]
                self.assertEqual(replies[0]["error"]["code"], -32600)
                self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": 2, "result": {}})

    def test_notifications_remain_silent_even_with_invalid_params(self) -> None:
        with patch.object(mcp_server, "call_tool") as call:
            self.assertIsNone(mcp_server.handle({"jsonrpc": "2.0", "method": "tools/call", "params": True}))
            self.assertIsNone(mcp_server.handle({"jsonrpc": "2.0", "method": "tools/call",
                                               "params": {"name": "sim_stop"}}))
            call.assert_not_called()

    def test_stop_failure_is_a_tool_error_with_its_diagnostic(self) -> None:
        for status in (1, 2):
            def stop(_argv):
                print("simulator is still running", file=sys.stderr)
                return status
            with self.subTest(status=status), patch.object(debugctl, "stop", stop):
                result = self.rpc("tools/call", {"name": "sim_stop"})["result"]
                self.assertTrue(result["isError"])
                self.assertIn("simulator is still running", result["content"][0]["text"])

    def test_stop_success_and_empty_failure_output(self) -> None:
        with patch.object(debugctl, "stop", return_value=0):
            self.assertFalse(self.rpc("tools/call", {"name": "sim_stop"})["result"]["isError"])
        with patch.object(debugctl, "stop", return_value=2):
            result = self.rpc("tools/call", {"name": "sim_stop"})["result"]
            self.assertTrue(result["isError"])
            self.assertIn("2", result["content"][0]["text"])

    def test_declared_argument_contracts_are_checked_before_actions(self) -> None:
        cases = [
            ("sim_launch", {"headless": "false"}, "headless"),
            ("sim_stop", {"unexpected": True}, "unexpected"),
            ("sim_choose", {"ref": "e9"}, "value"),
            ("sim_sticks", {"throttle": True}, "throttle"),
            ("sim_sticks", {"roll": float("inf")}, "roll"),
            ("sim_screenshot", {"max_width": 3.5}, "max_width"),
            ("sim_setup", {"start": "unknown"}, "start"),
            ("sim_command", {"command": "look", "args": []}, "args"),
        ]
        for name, arguments, diagnostic in cases:
            with self.subTest(name=name, arguments=arguments), patch.object(mcp_server, "call_tool") as call:
                result = self.rpc("tools/call", {"name": name, "arguments": arguments})["result"]
                self.assertTrue(result["isError"])
                self.assertIn(diagnostic, result["content"][0]["text"])
                call.assert_not_called()

    def test_valid_argument_types_and_aliases_reach_the_tool_unchanged(self) -> None:
        cases = [
            ("sim_launch", {"headless": False}),
            ("sim_choose", {"ref": "e9", "value": False}),
            ("sim_choose", {"ref": "e9", "value": 0.25}),
            ("sim_choose", {"ref": "e9", "value": "1920 × 1080"}),
            ("sim_screenshot", {"max_width": 1280.0}),
            ("sim_setup", {"start": "hand_launch"}),
            ("sim_command", {"command": "look", "args": {"all": True}}),
        ]
        for name, arguments in cases:
            with self.subTest(name=name, arguments=arguments), patch.object(mcp_server, "call_tool", return_value=[]) as call:
                result = self.rpc("tools/call", {"name": name, "arguments": arguments})["result"]
                self.assertFalse(result["isError"])
                call.assert_called_once_with(name, arguments)

    def test_decoder_limits_do_not_end_the_stream(self) -> None:
        saved_limit = sys.get_int_max_str_digits()
        try:
            sys.set_int_max_str_digits(4300)
            invalid = ['{"jsonrpc":"2.0","id":' + "9" * 5000 + ',"method":"ping"}',
                       "[" * 10000 + "0" + "]" * 10000]
            for request in invalid:
                with self.subTest(prefix=request[:30]):
                    stdout = io.StringIO()
                    mcp_server.serve(io.StringIO(request + '\n{"jsonrpc":"2.0","id":2,"method":"ping"}\n'), stdout)
                    replies = [json.loads(line) for line in stdout.getvalue().splitlines()]
                    self.assertEqual(replies[0]["error"]["code"], -32700)
                    self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": 2, "result": {}})
        finally:
            sys.set_int_max_str_digits(saved_limit)

    def test_utf8_stdio_preserves_unicode_and_survives_escaped_surrogates(self) -> None:
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "\ud800"}}
        ping = {"jsonrpc": "2.0", "id": "Español × 日本語", "method": "ping"}
        stream = io.BytesIO()
        stdout = io.TextIOWrapper(stream, encoding="utf-8", errors="strict")
        mcp_server.serve(io.StringIO(json.dumps(request) + "\n" + json.dumps(ping) + "\n"), stdout)
        replies = [json.loads(line) for line in stream.getvalue().decode("utf-8").splitlines()]
        self.assertEqual(replies[0]["error"]["code"], -32602)
        self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": ping["id"], "result": {}})


if __name__ == "__main__":
    unittest.main()
