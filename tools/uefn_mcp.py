"""Use the official MCP SDK to inspect or call a local editor's advertised tools."""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit


def local_endpoint(value: str) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme not in {"http", "https"}
        or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("Use the editor's loopback HTTP URL, without credentials or query parameters.")
    return value


def json_value(value):
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json", by_alias=True, exclude_none=True)
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}
    return value


async def run(args: argparse.Namespace) -> dict:
    from mcp import Client

    async with Client(args.url, raise_exceptions=True, mode="legacy") as client:
        if args.operation == "discover":
            tools = []
            cursor = None
            seen = set()
            for _ in range(100):
                page = json_value(await client.list_tools(cursor=cursor))
                tools.extend(page.get("tools", []))
                cursor = page.get("nextCursor")
                if not cursor:
                    break
                if cursor in seen:
                    raise RuntimeError("Editor repeated a tool-list cursor.")
                seen.add(cursor)
            else:
                raise RuntimeError("Editor tool listing exceeded the page limit.")
            return {
                "server": json_value(client.server_info),
                "protocol_version": client.protocol_version,
                "capabilities": json_value(client.server_capabilities),
                "tool_listing": {"tools": tools},
            }
        arguments = json.loads(args.arguments_file.read_text(encoding="utf-8-sig"))
        if not isinstance(arguments, dict):
            raise ValueError("Tool arguments must be a JSON object.")
        result = await client.call_tool(args.tool, arguments)
        payload = json_value(result)
        if payload.get("isError") or payload.get("is_error"):
            raise RuntimeError("Editor reported a tool execution error.")
        return {"tool": args.tool, "result": payload}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, type=local_endpoint,
                        help="Copy the exact URL from the editor's generated client configuration.")
    parser.add_argument("--timeout", type=float, default=45.0)
    operations = parser.add_subparsers(dest="operation", required=True)
    operations.add_parser("discover", help="Read server identity, capabilities and tool schemas.")
    call = operations.add_parser("call", help="Call one previously inspected tool by its exact name.")
    call.add_argument("tool")
    call.add_argument("--arguments-file", required=True, type=Path)
    args = parser.parse_args()
    if not 0 < args.timeout <= 300:
        parser.error("timeout must be between 0 and 300 seconds")
    try:
        async def bounded():
            return await asyncio.wait_for(run(args), timeout=args.timeout)
        result = asyncio.run(bounded())
    except ImportError:
        print("Install tools/requirements-uefn.txt into .venv-uefn first.", file=sys.stderr)
        return 2
    except TimeoutError:
        print("Editor request timed out. A tool call may have executed; inspect editor state before retrying.",
              file=sys.stderr)
        return 3
    except Exception as error:
        # Avoid printing server error bodies or configuration that could contain credentials.
        print(f"Editor request failed ({type(error).__name__}). Verify the generated URL and running editor.",
              file=sys.stderr)
        return 4
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
