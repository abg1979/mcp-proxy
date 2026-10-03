"""Exercise the real nginx/njs image against a mock upstream using only stdlib.

Build first, then run:
    python3 tests/test_notification_normalization.py --image mcp-nginx-proxy
"""

import argparse
from contextlib import contextmanager
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import subprocess
import threading
import time
import unittest
import uuid


NOTIFICATION = {"jsonrpc": "2.0", "method": "notifications/initialized"}
REQUEST = {"jsonrpc": "2.0", "method": "tools/list", "id": 1}
IMAGE = "mcp-nginx-proxy"


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()


@contextmanager
def gateway(upstream):
    name = "mcp-notification-test-" + uuid.uuid4().hex[:12]
    docker("run", "--detach", "--rm", "--name", name,
           "--add-host", "host.docker.internal:host-gateway",
           "--publish", "127.0.0.1::8080",
           "--env", "MCP_UPSTREAM_URL=" + upstream,
           "--env", "MCP_OAUTH_DISCOVERY=off",
           "--env", "MCP_HEADER_X_TEST_HEADER=forwarded",
           IMAGE)
    try:
        port = int(docker("port", name, "8080/tcp").rsplit(":", 1)[1])
        deadline = time.monotonic() + 15
        while True:
            try:
                exchange(port, NOTIFICATION)
                break
            except (OSError, http.client.HTTPException):
                if time.monotonic() >= deadline:
                    raise RuntimeError("Gateway did not start:\n" + docker("logs", name))
                time.sleep(0.1)
        yield port
    finally:
        docker("stop", "--time", "1", name)


def exchange(port, message, path="/empty", method="POST", chunked=False):
    body = json.dumps(message).encode() if not isinstance(message, bytes) else message
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        connection.request(method, path, [body] if chunked else body,
                           {"Content-Type": "application/json",
                            "Accept": "application/json, text/event-stream"},
                           encode_chunked=chunked)
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()


class Upstream(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            parts = []
            while True:
                size = int(self.rfile.readline().strip(), 16)
                if size == 0:
                    self.rfile.readline()
                    break
                parts.append(self.rfile.read(size))
                self.rfile.read(2)
            body = b"".join(parts)
        else:
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        with self.server.received_lock:
            self.server.received.append((self.path, body, dict(self.headers)))

        status = {"/error": 401, "/accepted": 202, "/nocontent": 204}.get(self.path, 200)
        payload = b'{"result":"unchanged"}' if self.path == "/nonempty" else b""
        if self.path == "/echo":
            payload = body
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Mcp-Session-Id", "test-session")
        if self.path == "/stream":
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for part in [b"data: first\n\n", b"data: second\n\n"]:
                self.wfile.write(f"{len(part):x}\r\n".encode() + part + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
        elif self.path == "/unknown-length":
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
        else:
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    do_GET = do_POST
    do_DELETE = do_POST


class NotificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.upstream = ThreadingHTTPServer(("0.0.0.0", 0), Upstream)
        cls.upstream.received = []
        cls.upstream.received_lock = threading.Lock()
        threading.Thread(target=cls.upstream.serve_forever, daemon=True).start()
        cls.addClassCleanup(cls.upstream.server_close)
        cls.addClassCleanup(cls.upstream.shutdown)
        cls.container = gateway(f"http://host.docker.internal:{cls.upstream.server_port}")
        cls.port = cls.container.__enter__()
        cls.addClassCleanup(cls.container.__exit__, None, None, None)

    def test_initialized_notification_is_forwarded_and_normalized(self):
        status, headers, body = exchange(self.port, NOTIFICATION)
        self.assertEqual((status, body), (202, b""))
        self.assertEqual(headers["Content-Length"], "0")
        self.assertNotIn("Content-Type", headers)
        self.assertEqual(headers["Mcp-Session-Id"], "test-session")
        with self.upstream.received_lock:
            path, forwarded, upstream_headers = self.upstream.received[-1]
        self.assertEqual(path, "/empty")
        self.assertEqual(json.loads(forwarded), NOTIFICATION)
        self.assertEqual(upstream_headers["X-Test-Header"], "forwarded")

    def test_only_valid_notifications_are_normalized(self):
        cases = [REQUEST, {**REQUEST, "id": None}, {**REQUEST, "id": 0},
                 {**REQUEST, "id": ""}, {}, None, [], [NOTIFICATION],
                 {"method": "notifications/initialized"},
                 {**NOTIFICATION, "jsonrpc": "1.0"},
                 {**NOTIFICATION, "method": ""},
                 {**NOTIFICATION, "method": 1}, b"not json"]
        for message in cases:
            with self.subTest(message=message):
                self.assertEqual(exchange(self.port, message)[0], 200)

    def test_errors_and_existing_success_statuses_are_preserved(self):
        for path, expected in [("/error", 401), ("/accepted", 202), ("/nocontent", 204)]:
            with self.subTest(path=path):
                self.assertEqual(exchange(self.port, NOTIFICATION, path)[0], expected)

    def test_nonempty_notification_reply_is_preserved(self):
        status, _, body = exchange(self.port, NOTIFICATION, "/nonempty")
        self.assertEqual((status, body), (200, b'{"result":"unchanged"}'))

    def test_streaming_and_unknown_length_responses_are_preserved(self):
        status, _, body = exchange(self.port, NOTIFICATION, "/stream")
        self.assertEqual((status, body), (200, b"data: first\n\ndata: second\n\n"))
        self.assertEqual(exchange(self.port, NOTIFICATION, "/unknown-length")[0], 200)

    def test_non_post_methods_are_preserved(self):
        for method in ["GET", "DELETE"]:
            with self.subTest(method=method):
                self.assertEqual(exchange(self.port, NOTIFICATION, method=method)[0], 200)

    def test_large_and_chunked_requests(self):
        notification = {**NOTIFICATION, "params": {"text": "x" * 131072}}
        self.assertEqual(exchange(self.port, notification)[0], 202)
        self.assertEqual(exchange(self.port, NOTIFICATION, chunked=True)[0], 202)
        request = {**REQUEST, "params": {"text": "x" * 131072}}
        status, _, body = exchange(self.port, request, "/echo", chunked=True)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), request)


def live_smoke(upstream):
    with gateway(upstream) as port:
        status, _, body = exchange(port, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                       "clientInfo": {"name": "gateway-smoke-test", "version": "1.0"}}}, "/")
        assert status == 200, status
        info = json.loads(body)["result"]["serverInfo"]
        status, _, body = exchange(port, NOTIFICATION, "/")
        assert (status, body) == (202, b""), (status, body)
        status, _, body = exchange(port, REQUEST, "/")
        assert status == 200, status
        tools = json.loads(body)["result"]["tools"]
        assert tools
        print(f"Live MCP handshake passed: {info['name']} {info['version']}, {len(tools)} tools")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default=IMAGE)
    parser.add_argument("--live-upstream", help="Optional upstream for initialize/notification/tools-list smoke test")
    args = parser.parse_args()
    IMAGE = args.image
    if args.live_upstream:
        live_smoke(args.live_upstream)
    else:
        unittest.main(argv=[__file__], verbosity=2)
