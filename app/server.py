"""Small dependency-free API; never returns the mounted secret value."""
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SECRET_PATH = Path(os.getenv("SECRET_PATH", "/mnt/secrets-store/demo-message"))
_counter = 0
_lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global _counter
        with _lock:
            _counter += 1
            count = _counter
        ready = SECRET_PATH.is_file()
        if self.path == "/healthz":
            status, body, content_type = 200, b"ok", "text/plain"
        elif self.path == "/readyz":
            status, body, content_type = (200 if ready else 503), (b"ready" if ready else b"secret unavailable"), "text/plain"
        elif self.path == "/metrics":
            status, body, content_type = 200, f"# TYPE http_requests_total counter\nhttp_requests_total {count}\n".encode(), "text/plain; version=0.0.4"
        elif self.path == "/":
            status, body, content_type = 200, json.dumps({
                "service": "portfolio-api", "version": os.getenv("APP_VERSION", "local"),
                "environment": os.getenv("ENVIRONMENT", "local"), "secret_mounted": ready
            }).encode(), "application/json"
        else:
            status, body, content_type = 404, b"not found", "text/plain"
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.getenv("PORT", "8080"))), Handler).serve_forever()
