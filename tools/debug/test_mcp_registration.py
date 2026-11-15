"""Check the repository MCP registration without launching a server."""
from __future__ import annotations

import json
from pathlib import Path
import unittest


class McpRegistrationTests(unittest.TestCase):
    def test_openrc_sim_registers_the_stdio_python_server(self):
        root = Path(__file__).resolve().parents[2]
        config = json.loads((root / ".mcp.json").read_text(encoding="utf-8"))
        server = config["mcpServers"]["openrc-sim"]
        self.assertEqual(server["type"], "stdio")
        self.assertIn(server["command"], ("python", "python3", "python.exe", "python3.exe"))
        self.assertEqual(server["args"], ["tools/debug/mcp_server.py"])
        self.assertTrue((root / server["args"][0]).is_file())


if __name__ == "__main__":
    unittest.main()
