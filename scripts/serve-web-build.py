#!/usr/bin/env python3
"""Serve a Godot web export locally with the MIME table it actually needs.

    python3 serve-web-build.py <proj>/build/web [--port 8080] [--host 127.0.0.1]

`python3 -m http.server` is not enough: it serves `.wasm` as octet-stream on some
installs (the engine refuses to instantiate it) and it dies with "Address already
in use" instead of finding a port that works. This walks forward from --port, prints
the port it actually bound, and mirrors what nginx must do in production:

    .html  text/html          .wasm  application/wasm
    .js    text/javascript    .pck   application/octet-stream

Run it with the terminal tool's background=true, then curl the four files before
opening a browser — /, /index.wasm, /index.pck, /index.js must all be 200 with the
types above. If the bytes served differ from the files on disk you are talking to a
DIFFERENT process on that port: `ss -ltnp | grep <port>` names it.
"""
import argparse
import functools
import http.server
import os
import socketserver
import sys

TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".ogg": "audio/ogg",
    ".json": "application/json",
    ".css": "text/css",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        return TYPES.get(os.path.splitext(str(path))[1].lower(), "application/octet-stream")

    def end_headers(self):
        # filenames are fixed across builds; never let the browser pin them
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        if args and str(args[1])[:1] in ("4", "5"):
            super().log_message(fmt, *args)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default="build/web")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--host", default="127.0.0.1")
    a = ap.parse_args()

    root = os.path.abspath(a.root)
    if not os.path.isfile(os.path.join(root, "index.html")):
        print(f"no index.html in {root} — export first", file=sys.stderr)
        return 1

    handler = functools.partial(Handler, directory=root)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = None
    for port in range(a.port, a.port + 40):
        try:
            httpd = socketserver.ThreadingTCPServer((a.host, port), handler)
            a.port = port
            break
        except OSError:
            continue
    if httpd is None:
        print(f"no free port in {a.port}..{a.port + 39}", file=sys.stderr)
        return 1

    with httpd:
        print(f"serving {root}\n  -> http://{a.host}:{a.port}/")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
