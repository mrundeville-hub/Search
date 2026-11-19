#!/usr/bin/env python3
"""A site's own CSS and its own script: both halves of a boost, put on every
page of that site, and both off when the setting is off.

Build first (`./build.sh`), then `python3 Tests/boosts.py`. It uses the split
suite's harness: the booth's page is the stand-in server's, so the host a boost
is kept by is 127.0.0.1.
"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("boosts")

CSS = "body { background: rgb(1, 2, 3); }"
SCRIPT = "document.body.dataset.boost = 'ran';"


def keep():
    """What the editor writes: two halves under one host, as styles.json keeps them."""
    folder = Path(sv.SUPPORT)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "styles.json").write_text(json.dumps({
        "version": 2,
        "css": {"127.0.0.1": CSS},
        "script": {"127.0.0.1": SCRIPT},
    }))


def look(page, js):
    return sv.ev(page, js)


def main():
    t = sv.T()
    try:
        # On: the style is on the page, and the script has run.
        sv.setup(**{"sites.styles": True})
        keep()
        sv.launch()
        page = sv.page("boosted")
        background = look(page, "getComputedStyle(document.body).backgroundColor")
        t.ok("a site's own CSS is on its page", background == "rgb(1, 2, 3)", background)
        ran = look(page, "document.body.dataset.boost || ''")
        t.ok("a site's own script has run on its page", ran == "ran", ran)
        other = sv.page("plain")
        t.ok("and on the next page of that site too",
             look(other, "document.body.dataset.boost || ''") == "ran")

        # Sharing it: out to a file, and back in as another site's boost.
        folder = Path(tempfile.mkdtemp(prefix="boost-share-"))
        shared = folder / "127.0.0.1.boost"
        wrote = sv.cmd({"do": "boost", "action": "export", "site": "127.0.0.1", "path": str(shared)})
        t.ok("a boost can be written to a file", wrote.get("written") == str(shared) and shared.exists(), wrote)
        kept = json.loads(shared.read_text())
        t.ok("the file carries both halves and its site",
             kept.get("format") == "search-boost" and kept.get("css") == CSS and kept.get("script") == SCRIPT, kept)

        elsewhere = json.dumps({"format": "search-boost", "version": 1,
                                "site": "other.example", "css": "h1 { color: teal }",
                                "script": "window.__shared = 1;"})
        theirs = folder / "other.boost"
        theirs.write_text(elsewhere)
        brought = sv.cmd({"do": "boost", "action": "import", "path": str(theirs)})
        t.ok("a boost brought in lands on its own site", brought.get("site") == "other.example", brought)
        back = sv.cmd({"do": "boost", "action": "export", "site": "other.example", "path": str(folder / "x.boost")})
        round_trip = json.loads(back["text"])
        t.ok("and is there afterwards, both halves",
             round_trip["css"] == "h1 { color: teal }" and round_trip["script"] == "window.__shared = 1;", round_trip)

        bad = folder / "bad.boost"
        bad.write_text('{"format": "search-boost", "site": "a.com", "css": "  "}')
        try:
            sv.cmd({"do": "boost", "action": "import", "path": str(bad)})
            t.ok("a file with nothing in it is refused, with a reason", False, "it was accepted")
        except RuntimeError as refusal:
            t.ok("a file with nothing in it is refused, with a reason",
                 "nothing in it" in str(refusal), str(refusal))

        # Off: kept, but neither worn nor run.
        sv.setup()
        keep()
        sv.launch()
        off = sv.page("off")
        background = look(off, "getComputedStyle(document.body).backgroundColor")
        t.ok("off, the style stays off the page", background != "rgb(1, 2, 3)", background)
        ran = look(off, "document.body.dataset.boost || ''")
        t.ok("off, the script does not run", ran == "", ran)
    finally:
        t.done()
        sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
