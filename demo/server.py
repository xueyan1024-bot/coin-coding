#!/usr/bin/env python3
"""Coin Coding 演示版本地服务器：提供游戏页面，并把 Claude 的工作状态转发给页面。"""
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

DEMO_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_FILE = os.path.expanduser("~/.coincoding/state.txt")
PORT = 17777

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/state.txt"):
            state = "idle"
            try:
                with open(STATE_FILE) as f:
                    state = f.read().strip() or "idle"
            except FileNotFoundError:
                pass
            body = state.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Cache-Control", "no-store")
        else:
            with open(os.path.join(DEMO_DIR, "index.html"), "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

if __name__ == "__main__":
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    print(f"Coin Coding 演示版运行中：http://localhost:{PORT}")
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
