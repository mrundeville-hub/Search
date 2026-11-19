#!/usr/bin/env python3
"""A card about the link under the pointer: what the page says about itself,
read once and kept.

Build first (`./build.sh`), then `python3 Tests/link_cards.py`. It uses the split
suite's harness for the app and its own small server for a page with a head worth
reading, so the card is asked for over the network the way a resting pointer asks.

The card itself is drawn by SwiftUI over the page, which a bench run can't read;
what is checked here is the part behind it: the request, the reading of the head,
and that an address is only asked for once.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("link-cards")

HEAD = """<!doctype html><html><head>
<title>Plain title, not this one</title>
<meta property="og:title" content="The page's own title">
<meta property="og:description" content="What the page says it is">
<meta property="og:image" content="/icon.png">
</head><body><p>body</p></body></html>"""


class Heads(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/meta":
            body = HEAD.encode()
            self.send_response(200)
        else:
            body = b"<title>another page</title>"
            self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Heads)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"


def card(url, on=None):
    ask = {"do": "linkcard", "url": url}
    if on is not None:
        ask["on"] = on
    return sv.cmd(ask)


def main():
    t = sv.T()
    try:
        sv.setup()
        sv.launch()

        first = card(f"{BASE}/meta", on=True)
        t.ok("the card takes Open Graph's title over the plain one",
             first["title"] == "The page's own title", first)
        t.ok("and its description", first["summary"] == "What the page says it is", first)
        t.ok("and the icon it names, made absolute",
             first["icon"] == f"{BASE}/icon.png", first)
        t.ok("and the page's host", first["host"] == f"127.0.0.1:{srv.server_port}", first)

        again = card(f"{BASE}/meta")
        t.ok("a second look at the same address says the same thing",
             again["title"] == first["title"], again)

        plain = card(f"{BASE}/other")
        t.ok("a page with only a <title> still gets a card", plain["title"] == "another page", plain)

        nothing = card("search://history")
        t.ok("Search's own pages are never asked for", nothing["title"] == "", nothing)

        time.sleep(0.3)
    finally:
        t.done()
        sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
