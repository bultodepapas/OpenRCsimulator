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


if __name__ == "__main__":
    unittest.main()
