#!/usr/bin/env python3
"""An agent's reach beyond the page: the bookmarks, the places been, the spaces.

Build first (`./build.sh`), then `python3 Tests/agent_wide.py`. It uses the
split suite's harness and speaks to ./search-mcp over stdio exactly as Claude
Code does, as Tests/agent_control.py does.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("agent-wide")
ROOT = Path(__file__).resolve().parents[1]


class Client:
    def __init__(self, name="claude-code"):
        self.p = subprocess.Popen([str(ROOT / "search-mcp"), "--world", sv.W],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, start_new_session=True)
        self.n = 0
        init = self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                       "clientInfo": {"name": name}})
        assert init["serverInfo"]["name"] == "search", init

    def rpc(self, method, params=None):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n,
                                       "method": method, "params": params or {}}) + "\n")
        self.p.stdin.flush()
        out = json.loads(self.p.stdout.readline())
        return out["result"]

    def tool(self, which, /, **args):
        out = self.rpc("tools/call", {"name": which, "arguments": args})
        text = out["content"][0]["text"]
        return json.loads(text), bool(out.get("isError"))

    def send_tool(self, which, /, **args):
        """A tool call sent and not waited for: the question it raises has to be
        answered in Search first, as a person's click does."""
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": "tools/call",
                                       "params": {"name": which, "arguments": args}}) + "\n")
        self.p.stdin.flush()
        return self.n

    def answer_tool(self, n):
        out = self.p.stdout.readline()
        result = json.loads(out)["result"]
        return json.loads(result["content"][0]["text"]), bool(result.get("isError"))

    def names(self):
        return [tool["name"] for tool in self.rpc("tools/list")["tools"]]

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(5)
        except Exception:
            self.p.kill()


def agents(action="state", **f):
    return sv.cmd({"do": "agents", "action": action, **f})


def main():
    t = sv.T()
    client = None
    try:
        sv.setup(agents=True)
        sv.launch()
        time.sleep(1)
        client = Client()
        # The first call raises the question; the person's Allow answers it, as
        # the pill's button does.
        asked = client.send_tool("spaces")
        waited = time.time() + 10
        while agents().get("state") != "asking" and time.time() < waited:
            time.sleep(0.1)
        agents("allow")
        first, bad = client.answer_tool(asked)
        t.ok("the spaces answer comes back once allowed",
             not bad and len(first["spaces"]) >= 1, first)

        named = client.names()
        wanted = ["bookmarks", "bookmark_add", "history", "spaces", "space_switch"]
        t.ok("the wider tools are offered", all(name in named for name in wanted),
             [name for name in wanted if name not in named])

        spaces, bad = client.tool("spaces")
        t.ok("the spaces come back, numbered, with one of them in front",
             not bad and any(space["current"] for space in spaces["spaces"]), spaces)

        again, bad = client.tool("space_switch", index=0)
        t.ok("going to the space already in front is fine", not bad and again["current"] is True, again)
        out_of_range, bad = client.tool("space_switch", index=99)
        t.ok("a space that isn't there is refused, not crashed on", bad and out_of_range["error"]["code"] == "no_space",
             out_of_range)

        kept, bad = client.tool("bookmarks")
        t.ok("the bookmarks list starts empty in a fresh world", not bad and kept["bookmarks"] == [], kept)

        added, bad = client.tool("bookmark_add", url="https://example.com/wide", title="Wide")
        t.ok("a bookmark can be added", not bad and added["added"] is True, added)

        listed, bad = client.tool("bookmarks")
        t.ok("and is in the list after", not bad and any(b["url"] == "https://example.com/wide" for b in listed["bookmarks"]),
             listed)

        twice, bad = client.tool("bookmark_add", url="https://example.com/wide")
        t.ok("adding the same address twice says it is already kept",
             not bad and twice["added"] is False and twice["already"] is True, twice)

        refused, bad = client.tool("bookmark_add", url="search://history")
        t.ok("Search's own addresses are not bookmarks", bad, refused)

        places, bad = client.tool("history", limit=5)
        t.ok("the recent places come back as a list", not bad and isinstance(places["places"], list), places)

        narrowed, bad = client.tool("history", query="nothing-matches-this-at-all")
        t.ok("words that match nothing narrow it away", not bad and narrowed["places"] == [], narrowed)

        # ---- the notebook
        kept_note, bad = client.tool("memory_write", text="This Mac runs the dev server on :3000",
                                     key="dev-server")
        t.ok("an agent can keep a note", not bad and kept_note["kept"] == "dev-server", kept_note)

        read_back, bad = client.tool("memory_read", key="dev-server")
        t.ok("and read it back", not bad and read_back["notes"][0]["text"].endswith(":3000"), read_back)

        found, bad = client.tool("memory_search", query="dev server")
        t.ok("and find it by a word", not bad and len(found["notes"]) == 1, found)

        # A second session finds what the first wrote.
        client.close()
        client = Client()
        # A new session asks again: the call is sent, the question appears, and
        # the person's Allow answers it, as the first time.
        again = client.send_tool("memory_read", key="dev-server")
        waited = time.time() + 10
        while agents().get("state") != "asking" and time.time() < waited:
            time.sleep(0.1)
        agents("allow")
        second, bad = client.answer_tool(again)
        t.ok("the next session finds it", not bad and second["notes"][0]["key"] == "dev-server", second)

        gone, bad = client.tool("memory_forget", key="dev-server")
        t.ok("and it can be thrown away", not bad and gone["forgotten"] is True, gone)
        empty, bad = client.tool("memory_read")
        t.ok("the notebook is empty after", not bad and empty["notes"] == [], empty)
    finally:
        if client:
            client.close()
        t.done()
        sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
