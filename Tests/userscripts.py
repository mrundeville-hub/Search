#!/usr/bin/env python3
"""A userscript runs on the pages its own header asks for, and nowhere else,
and the page that lists them opens from the menu.

Build first (`./build.sh`), then `python3 Tests/userscripts.py`. It uses the
split suite's harness: started hidden in a world of its own.

The two scripts are written into the world's `userscripts.json` before the app
starts, which is the same file the panel's Add writes: what is being tested is
the chain from that file, through the header, to the page.
"""
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("userscripts")

EVERYWHERE = """// ==UserScript==
// @name Bench: every page
// @namespace bench.search
// @match *://*/*
// ==/UserScript==
document.title = 'the first ran';
"""

ONE_SITE = """// ==UserScript==
// @name Bench: one site
// @namespace bench.search
// @match https://example.invalid/*
// ==/UserScript==
document.title = 'the second ran';
"""


def keep(scripts):
    folder = Path(sv.SUPPORT)
    folder.mkdir(parents=True, exist_ok=True)
    added = "2026-11-20T00:00:00Z"
    (folder / "userscripts.json").write_text(json.dumps([
        {"source": source, "enabled": True, "added": added} for source in scripts
    ]))


def main():
    t = sv.T()
    try:
        sv.setup()
        keep([EVERYWHERE, ONE_SITE])
        sv.launch()

        page = sv.page("plain")
        title = sv.ev(page, "document.title")
        t.ok("the script whose @match takes this address runs", title == "the first ran", title)

        sv.cmd({"do": "ui", "lead": "userscripts"})
        time.sleep(0.8)
        shown = [tab["internal"] for tab in sv.cmd({"do": "tabs"})["tabs"]]
        t.ok("View › Userscripts… opens search://userscripts", "search://userscripts" in shown, shown)
    finally:
        t.done()
        sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
