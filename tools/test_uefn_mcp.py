"""SDK integration checks with an in-memory server; these do not test UEFN."""

import argparse
import json
from pathlib import Path
import tempfile
import unittest

from mcp.server import MCPServer

from uefn_mcp import local_endpoint, run


class ConnectionChecks(unittest.IsolatedAsyncioTestCase):
    async def test_sdk_discovery_call_and_server_error(self):
        server = MCPServer("Connection check")

        @server.tool()
        def echo(marker: str) -> str:
            return marker

        listing = await run(argparse.Namespace(url=server, operation="discover"))
        names = [tool["name"] for tool in listing["tool_listing"]["tools"]]
        self.assertIn("echo", names)

        with tempfile.TemporaryDirectory(prefix="fortnite-mcp-check-") as directory:
            arguments = Path(directory) / "arguments.json"
            arguments.write_text(json.dumps({"marker": "בדיקת חיבור"}), encoding="utf-8")
            call = argparse.Namespace(url=server, operation="call", tool="echo",
                                      arguments_file=arguments)
            result = await run(call)
            self.assertEqual(result["result"]["content"][0]["text"], "בדיקת חיבור")
            call.tool = "missing_tool"
            with self.assertRaises(Exception):
                await run(call)

    def test_endpoint_is_explicitly_local(self):
        for value in ("http://127.0.0.1:8000/mcp", "http://[::1]:8000/mcp"):
            self.assertEqual(local_endpoint(value), value)
        for value in ("https://example.com/mcp", "http://localhost.example.com/mcp",
                      "http://user:secret@localhost/mcp", "http://localhost/mcp?key=secret"):
            with self.assertRaises(ValueError):
                local_endpoint(value)


if __name__ == "__main__":
    unittest.main()
