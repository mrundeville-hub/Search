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

GM_STORE = """// ==UserScript==
// @name Bench: GM store
// @namespace bench.search
// @match *://*/gm*
// @grant GM_setValue
// @grant GM_getValue
// ==/UserScript==
if (!GM_getValue('step', '')) {
  GM_setValue('step', 'kept');
  document.title = 'wrote';
} else {
  document.title = 'read:' + GM_getValue('step', 'missing');
}
"""

REQUIRED = """// ==UserScript==
// @name Bench: brings a file
// @namespace bench.search
// @match *://*/req*
// @require http://bench.invalid/helper.js
// ==/UserScript==
document.title = window.__helper || 'missing';
"""

ONE_SITE = """// ==UserScript==
// @name Bench: one site
// @namespace bench.search
// @match https://example.invalid/*
// ==/UserScript==
document.title = 'the second ran';
"""


def keep(scripts, requires=None):
    """The world's list, as the panel's Add would have written it."""
    folder = Path(sv.SUPPORT)
    folder.mkdir(parents=True, exist_ok=True)
    added = "2026-11-20T00:00:00Z"
    lines = []
    for source in scripts:
        line = {"source": source, "enabled": True, "added": added}
        if requires and "@require" in source:
            line["requires"] = requires
        lines.append(line)
    (folder / "userscripts.json").write_text(json.dumps(lines))


def main():
    t = sv.T()
    try:
        sv.setup()
        keep([EVERYWHERE, ONE_SITE, GM_STORE, REQUIRED],
             requires=[{"url": "http://bench.invalid/helper.js",
                        "sha256": "0" * 64,
                        "text": "window.__helper = 'loaded';"}])
        sv.launch()

        page = sv.page("plain")
        title = sv.ev(page, "document.title")
        t.ok("the script whose @match takes this address runs", title == "the first ran", title)

        # GM_setValue reaches Search, is kept, and is there for the page after.
        first = sv.page("gm")
        wrote = sv.ev(first, "document.title")
        t.ok("GM_setValue answers at once in the page", wrote == "wrote", wrote)
        time.sleep(0.8)
        kept = json.loads((Path(sv.SUPPORT) / "userscript-values.json").read_text())
        t.ok("the value reached Search's file", any("kept" in str(v) for v in kept.values()), kept)

        second = sv.page("gm?again")
        read = sv.ev(second, "document.title")
        t.ok("a page opened after it reads the kept value", read == "read:kept", read)

        # A file the script required goes in ahead of it.
        brought = sv.page("req")
        t.ok("a @require file runs before the script that asked for it",
             sv.ev(brought, "document.title") == "loaded", sv.ev(brought, "document.title"))

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
