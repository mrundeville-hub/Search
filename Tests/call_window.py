#!/usr/bin/env python3
"""A call out in a window of its own — Yab's call window.

Build first (`./build.sh`), then `python3 Tests/call_window.py`. It uses the
split suite's harness, with WebKit's pretend camera and microphone (test runs
only, see ExtensionCapture.mockDevices), so a page can be on a call without a
person clicking anything.

Checked: the page is seen to be on a call, floating it takes the very same page
out of its tab (it still answers from inside the window), the tab row says which
tab is out, and landing it puts the page back in its tab.
"""
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("call-window")

START = """
navigator.mediaDevices.getUserMedia({ video: true, audio: true }).then(stream => {
  window.stream = stream;
  window.state = 'live';
}).catch(error => { window.state = 'refused: ' + error.name; });
'started'
"""


def described(tab):
    return next((x for x in sv.cmd({"do": "tabs"})["tabs"] if x["id"] == tab), {})


def calls(action=None, tab=None):
    ask = {"do": "calls"}
    if action:
        ask["action"] = action
    if tab:
        ask["id"] = tab
    return sv.cmd(ask)


def main():
    t = sv.T()
    try:
        sv.setup(splitView=True)
        # The site's camera and microphone answered yes beforehand
        # (Browser.askedForCapture), as Tests/call_background.py does.
        for kind in (0, 1, 2):
            subprocess.run(["defaults", "write", sv.SUITE, f"capture.{sv.BASE}|{kind}", "-bool", "true"])
        sv.launch()
        page = sv.sp("open", url=f"{sv.BASE}/call")["resultID"]
        time.sleep(0.6)
        sv.ev(page, START)
        state = None
        for _ in range(40):
            state = sv.ev(page, "window.state")
            if state in ("live",) or (isinstance(state, str) and state.startswith("refused")):
                break
            time.sleep(0.2)
        t.ok("the page is on a call with WebKit's pretend camera and microphone", state == "live", state)

        told = calls()
        t.ok("the tab is seen to be on a call", len(told["calls"]) == 1, told)
        t.ok("and nothing is out in a window yet", told["showing"] is False and told["floatingCall"] == "", told)

        floated = calls("float", page)
        t.ok("floating it opens the window", floated["showing"] is True, floated)
        t.ok("the tab row knows which tab is out", floated["floatingCall"] != "", floated)
        t.ok("the very same page is in it, still answering", sv.ev(page, "1 + 1") == 2)

        landed = calls("land")
        t.ok("landing it closes the window", landed["showing"] is False, landed)
        t.ok("and the page is back in its tab, still the same page",
             sv.ev(page, "window.state") == "live" and sv.ev(page, "1 + 1") == 2, landed)
    finally:
        t.done()
        sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
