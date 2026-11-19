#!/usr/bin/env python3
"""Snippets: a name typed in a page's box, taken in as the text it stands for —
with a space or with Tab — and nothing typed into a box for a password.

Build first (`./build.sh`), then `python3 Tests/snippets.py`. It uses the split
suite's harness, and its own server for a page with boxes in it.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("snippets")

PAGE = """<!doctype html><html><head><title>boxes</title></head><body>
<input id="box" type="text">
<textarea id="area"></textarea>
<input id="pw" type="password">
</body></html>"""


class Boxes(BaseHTTPRequestHandler):
    def do_GET(self):
        body = PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Boxes)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"

SIGNATURE = "Best,\nMussa"
QUICK = "On my way!"


def keep():
    folder = Path(sv.SUPPORT)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "snippets.json").write_text(json.dumps([
        {"name": "sig", "text": SIGNATURE},
        {"name": "omw", "text": QUICK},
    ]))


def typed(page, selector, text):
    sv.cmd({"do": "type", "id": page, "selector": selector, "text": text})
    time.sleep(0.2)


def value(page, selector):
    return sv.ev(page, f"document.querySelector('{selector}').value")


def clear(page, selector):
    sv.ev(page, f"""(() => {{
        var el = document.querySelector('{selector}');
        el.focus();
        el.value = '';
        el.dispatchEvent(new Event('input', {{ bubbles: true }}));
    }})()""")


def main():
    t = sv.T()
    try:
        sv.setup(**{"pages.snippets": True})
        keep()
        sv.launch()
        page = sv.cmd({"do": "open", "url": f"{BASE}/boxes"})["id"]
        time.sleep(0.8)

        typed(page, "#box", ";omw ")
        t.ok("a name and a space is taken in as its text", value(page, "#box") == QUICK,
             repr(value(page, "#box")))

        typed(page, "#area", ";sig ")
        t.ok("a snippet's own line breaks arrive in a box with room for them",
             value(page, "#area") == SIGNATURE, repr(value(page, "#area")))

        clear(page, "#box")
        typed(page, "#box", ";omw")
        ended = sv.ev(page, """(() => {
            var el = document.querySelector('#box');
            el.focus();
            el.setSelectionRange(el.value.length, el.value.length);
            var event = new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
            el.dispatchEvent(event);
            return { prevented: event.defaultPrevented, value: el.value };
        })()""")
        t.ok("a name and Tab is taken in as well", ended["value"] == QUICK, ended)
        t.ok("and the Tab does not also leave the box", ended["prevented"] is True, ended)

        clear(page, "#box")
        typed(page, "#box", ";nothing ")
        t.ok("a name that isn't there is left as typed", value(page, "#box") == ";nothing ",
             repr(value(page, "#box")))

        clear(page, "#pw")
        typed(page, "#pw", ";omw ")
        t.ok("a box for a password is never touched", value(page, "#pw") == ";omw ",
             repr(value(page, "#pw")))

        # Off, the list is kept and nothing is typed for you.
        sv.setup()
        keep()
        sv.launch()
        page = sv.cmd({"do": "open", "url": f"{BASE}/boxes"})["id"]
        time.sleep(0.8)
        typed(page, "#box", ";omw ")
        t.ok("off, a box is left exactly as typed", value(page, "#box") == ";omw ",
             repr(value(page, "#box")))
    finally:
        t.done()
        sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
