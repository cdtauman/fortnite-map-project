"""Push local uefn/Verse sources into the open UEFN project and compile.

Usage: python tools/sync_verse.py coach_model.verse [more.verse ...] [--check-only]

For each file: reads the native copy through MCP, verifies it matches the committed
(HEAD) version (ignoring line endings / trailing newline) so no unseen editor-side change is
overwritten, writes the local version, then runs one BuildAll and prints diagnostics.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = os.path.join(ROOT, ".venv-uefn", "Scripts", "python.exe")
VERSE_ROOT = "/eda26a53-42c0-4b9e-8f62-31719aef6889/"


def call(toolset, tool, args, timeout="300"):
    payload = {"toolset_name": toolset, "tool_name": tool, "arguments": args}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(payload, f)
    p = subprocess.run([PY, os.path.join(ROOT, "tools", "uefn_mcp.py"), "--url", "http://127.0.0.1:8000/mcp",
                        "--timeout", timeout, "call", "call_tool", "--arguments-file", f.name],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env={**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1"})
    os.unlink(f.name)
    if p.returncode != 0:
        raise RuntimeError(f"{tool} failed: {p.stdout[-1500:]} {p.stderr[-1500:]}")
    d = json.loads(p.stdout)
    text = d["result"]["content"][0]["text"]
    return json.loads(text).get("returnValue")


def norm(s):
    return s.replace("\r\n", "\n").rstrip("\n")


def head_text(name):
    p = subprocess.run(["git", "show", f"HEAD:uefn/Verse/{name}"], cwd=ROOT, capture_output=True)
    return p.stdout.decode("utf-8") if p.returncode == 0 else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check-only" in sys.argv
    for name in args:
        local = open(os.path.join(ROOT, "uefn", "Verse", name), encoding="utf-8").read()
        try:
            native = call("VerseToolset.VerseToolset", "ReadFile", {"path": VERSE_ROOT + name})
        except RuntimeError:
            native = None
        base = head_text(name)
        cache = os.path.join(ROOT, ".local", "sync_cache", name)
        last = open(cache, encoding="utf-8").read() if os.path.exists(cache) else None
        if (native is not None and base is not None and norm(native) != norm(base) and norm(native) != norm(local)
                and (last is None or norm(native) != norm(last))):
            print(f"STOP {name}: native copy differs from HEAD and from local; not overwriting")
            sys.exit(2)
        if check_only:
            print(f"{name}: native {'missing' if native is None else 'ok'}")
            continue
        call("VerseToolset.VerseToolset", "WriteFile", {"path": VERSE_ROOT + name, "content": local, "bCreateIfMissing": True})
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        open(cache, "w", encoding="utf-8").write(local)
        print(f"wrote {name}")
    if check_only:
        return
    diags = call("VerseToolset.VerseToolset", "BuildAll", {})
    errors = [d for d in diags or [] if d.get("severity") == "Error"]
    for d in diags or []:
        sp = d.get("span", {})
        print(f"{d.get('severity')} {d.get('filePath')}:{sp.get('startLine')}: {d.get('message')}")
    print(f"BUILD {'FAILED' if errors else 'OK'} ({len(diags or [])} diagnostics)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
