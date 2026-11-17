"""Loopback-only synthetic ERP responses for the mobile UI smoke tests."""
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

COMPANY = "Mobile Test Mill"
COOKIE = "sid=mobile-smoke-fixture"


class FixtureRequest(BaseHTTPRequestHandler):
    def respond(self, status, value, *, cookie=False):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if cookie:
            self.send_header("Set-Cookie", COOKIE + "; Path=/; HttpOnly")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self.respond(HTTPStatus.OK, {"ready": True})
        else:
            self.respond(HTTPStatus.NOT_FOUND, {})

    def do_POST(self):
        if not self.path.startswith("/api/method/"):
            self.respond(HTTPStatus.NOT_FOUND, {})
            return
        method = self.path.removeprefix("/api/method/")
        fields = parse_qs(self.rfile.read(int(self.headers["Content-Length"])).decode())
        if method == "login":
            if fields == {"usr": ["smoke"], "pwd": ["fixture"]}:
                self.respond(HTTPStatus.OK, {"message": "Logged In"}, cookie=True)
            else:
                self.respond(HTTPStatus.UNAUTHORIZED, {})
            return
        if self.headers.get("Cookie") != COOKIE:
            self.respond(HTTPStatus.UNAUTHORIZED, {})
            return
        if method == "erp_extensions.workspace.context":
            result = {
                "company": COMPANY, "companies": [{"name": COMPANY}],
                "knitting_enabled": True, "knitting_only": True, "setup_state": "Active",
                "capabilities": ["overview", "materials"],
                "readable_records": ["Sales Invoice"], "creatable_records": ["Sales Invoice"],
            }
        elif fields.get("company") != [COMPANY]:
            self.respond(HTTPStatus.FORBIDDEN, {})
            return
        elif method == "erp_extensions.knitting.api.snapshot":
            result = {"version": 1, "company": COMPANY}
        elif method == "erp_extensions.invoices.register":
            result = {"rows": [], "statuses": ["All", "Draft"], "can_create": True, "has_more": False}
        elif method == "erp_extensions.invoice_compose.defaults":
            result = {"posting_date": "2026-11-18", "currency": "INR", "template_id": "ledger"}
        else:
            self.respond(HTTPStatus.NOT_FOUND, {})
            return
        self.respond(HTTPStatus.OK, {"message": result})


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 8081), FixtureRequest) as server:
        server.serve_forever()
