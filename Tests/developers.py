#!/usr/bin/env python3
"""Setting a coding agent up from Settings › About › Developer: the entry it
needs, written into a home folder, pointing at the MCP server inside the app.

Build first (`./build.sh`), then `python3 Tests/developers.py`. It uses the split
suite's harness and a temporary home, so nothing of anyone's own is touched.
"""
import json
import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("developers")


def set_up(client, home):
    return sv.cmd({"do": "developers", "client": client, "home": home})


def main():
    t = sv.T()
    home = Path(tempfile.mkdtemp(prefix="developers-home-"))
    try:
        sv.setup()
        sv.launch()

        first = set_up("claude_code", str(home))
        command = first.get("command", "")
        t.ok("the app carries its own MCP server", command.startswith(str(sv.APP)) and os.access(command, os.X_OK),
             command)
        t.ok("it says it wrote the config and the skill", len(first.get("written", [])) == 2, first)

        config = home / ".claude.json"
        t.ok("Claude Code's config is there", config.exists(), str(home))
        entry = json.loads(config.read_text())["mcpServers"]["search"]
        t.ok("with the entry pointing at the app's own server", entry["command"] == command, entry)
        t.ok("and nothing else claimed", entry["args"] == [], entry)

        skill = home / ".claude" / "skills" / "search" / "SKILL.md"
        t.ok("the skill is beside it", skill.exists() and "read_page" in skill.read_text())

        again = set_up("claude_code", str(home))
        t.ok("a second run writes nothing", again.get("written") == [], again)

        codex = set_up("codex", str(home))
        toml = (home / ".codex" / "config.toml").read_text()
        t.ok("Codex gets its own table", "[mcp_servers.search]" in toml and command in toml, toml[:200])
        t.ok("and its skill where it reads them", (home / ".agents" / "skills" / "search" / "SKILL.md").exists(),
             codex)
        t.ok("Codex's config was backed up before the first write",
             (home / ".codex" / "config.toml.search.backup").exists() is False,
             "no backup when there was nothing there")

        # Taking it back: only what the setup wrote.
        removed = sv.cmd({"do": "developers", "client": "claude_code", "action": "remove", "home": str(home)})
        t.ok("removing takes the entry and the skill out", len(removed.get("removed", [])) == 2, removed)
        t.ok("Claude Code's config no longer lists it",
             "search" not in json.loads(config.read_text()).get("mcpServers", {}), config.read_text())
        t.ok("and the skill is gone", not skill.exists())

        gone = sv.cmd({"do": "developers", "client": "codex", "action": "remove", "home": str(home)})
        toml_after = (home / ".codex" / "config.toml").read_text()
        t.ok("Codex's table is gone, its file left empty and clean",
             "[mcp_servers.search]" not in toml_after and toml_after.strip() == "", repr(toml_after))
        t.ok("the skill beside it too",
             not (home / ".agents" / "skills" / "search" / "SKILL.md").exists(), gone)

        again = sv.cmd({"do": "developers", "client": "codex", "action": "remove", "home": str(home)})
        t.ok("removing again finds nothing to remove",
             again.get("removed") == [] and again.get("kept") == [], again)

        # What Copy Config would put on the clipboard.
        copied = json.loads(first["json"])["mcpServers"]["search"]
        t.ok("the copied config is the same entry", copied["command"] == command, copied)
        time.sleep(0.2)
    finally:
        t.done()
        sv.finish()
        subprocess_remove(home)
    return 1 if t.failed else 0


def subprocess_remove(home):
    import shutil
    shutil.rmtree(home, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
