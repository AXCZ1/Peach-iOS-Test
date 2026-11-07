import json
import re
import sys
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from urllib.parse import parse_qs, urlsplit


FIXTURES = Path(__file__).parent
AVC = (FIXTURES / "avc-tail.mp4").read_bytes()
HEVC = (FIXTURES / "hev1-tail.mp4").read_bytes()
AUDIO = (FIXTURES / "audio-only.m4a").read_bytes()
COUNTS = Counter()
LOCK = Lock()
UPSTREAM_ORIGIN = sys.argv[1] if len(sys.argv) > 1 else None


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def count(self, key):
        with LOCK:
            COUNTS[key] += 1

    def json(self, payload, status=200):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        route = urlsplit(self.path)
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if route.path == "/api/external-playback":
            self.count("tickets")
            origin = self.headers.get("Origin", "").rstrip("/")
            upstream = UPSTREAM_ORIGIN or "http://" + self.headers["Host"]
            if origin and origin != upstream:
                return self.json({"error": "请从 Peach 配置页提交"}, 403)
            asset = parse_qs(route.query).get("id", [""])[0]
            if asset == "42003":
                return self.json({"url": "https://example.invalid/external-stream/42003?ticket=fixture"})
            if asset == "42004":
                return self.json({}, 404)
            return self.json({"url": f"/external-stream/{asset}?ticket=fixture", "expires_in": 21600})
        if route.path == "/api/play":
            self.count("play_marks")
        self.json({"ok": True, "play_count": 1})

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        route = urlsplit(self.path)
        if route.path == "/counts":
            with LOCK:
                return self.json(dict(COUNTS))
        if route.path == "/api/stream-plan":
            self.count("plans")
            return self.json({"id": 42002, "protocol": "range", "src": "/compatible.mp4"})
        original = route.path.startswith("/external-stream/")
        if original and parse_qs(route.query).get("ticket") != ["fixture"]:
            return self.json({}, 401)
        if not original and route.path != "/compatible.mp4":
            return self.json({}, 404)
        if route.path == "/external-stream/42005":
            video = HEVC
        elif route.path == "/external-stream/42006":
            video = AUDIO
        else:
            video = AVC
        end = len(video) - 1
        start = 0
        match = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
        if match:
            start = int(match[1])
            end = min(end, int(match[2])) if match[2] else end
            if start > end:
                return self.json({}, 416)
            if original:
                self.count("original_ranges")
        self.send_response(206 if match else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if match:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(video)}")
        self.end_headers()
        if self.command != "HEAD":
            try:
                self.wfile.write(video[start:end + 1])
            except (BrokenPipeError, ConnectionResetError):
                pass


with ThreadingHTTPServer(("127.0.0.1", 0), Fixture) as server:
    print(f"{server.server_port:05d}", flush=True)
    server.serve_forever()
