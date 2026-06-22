"""A minimal mock Unimus REST API v2 server, driven by `dataset.py`.

Language-agnostic: it serves canned responses over HTTP so ANY implementation
of the exporter (this Bash script today, the PowerShell port later) can be run
black-box against it. Nothing here knows or cares which port is under test.

Endpoints implemented (base path /api/v2, Bearer auth). Shapes verified against
the Unimus API v2 wiki; results are wrapped in a `paginator` object that the
script ignores (it terminates on an empty `data` array):
  GET /health                       -> {"data": {"status": "OK"}}
  GET /devices?page=N               -> {"data": [{id, address, ...}, ...], paginator}
  GET /devices/{id}/backups?page=N  -> {"data": [{id, validSince, validUntil, type, bytes}, ...], paginator}
  GET /devices/backups/latest?page=N-> {"data": [{deviceId, address, backup:{...}}, ...], paginator}

Run standalone (handy for manually testing the PowerShell port):
    python3 tests/mock_server.py --port 8085
then point unimus_server_address at http://127.0.0.1:8085 and
unimus_api_key at the value of dataset.API_KEY.
"""

import argparse
import base64
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

import dataset

_DEVICE_BACKUPS_RE = re.compile(r"^/api/v2/devices/(\d+)/backups$")


def _page(items, page):
    chunk = items[page * dataset.PAGE_SIZE:(page + 1) * dataset.PAGE_SIZE]
    total = len(items)
    return {
        "data": chunk,
        "paginator": {
            "totalCount": total,
            "totalPages": (total + dataset.PAGE_SIZE - 1) // dataset.PAGE_SIZE,
            "page": page,
            "size": dataset.PAGE_SIZE,
        },
    }


def _encode(backup, backup_id=1):
    # The script reads only validSince/type/bytes; id and validUntil are
    # included to mirror the real API v2 backup object.
    return {
        "id": backup_id,
        "validSince": backup["validSince"],
        "validUntil": None,
        "type": backup["type"],
        "bytes": base64.b64encode(backup["content"]).decode("ascii"),
    }


class Handler(BaseHTTPRequestHandler):
    # Silence the default per-request stderr logging.
    def log_message(self, *args):
        pass

    def _send(self, status, payload):
        blob = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)

    def do_GET(self):
        if self.headers.get("Authorization") != f"Bearer {dataset.API_KEY}":
            self._send(401, {"error": "unauthorized"})
            return

        parts = urlsplit(self.path)
        path = parts.path.rstrip("/")
        page = int(parse_qs(parts.query).get("page", ["0"])[0])

        if path == "/api/v2/health":
            self._send(200, {"data": {"status": "OK"}})
            return

        if path == "/api/v2/devices":
            self._send(200, _page(dataset.DEVICES, page))
            return

        if path == "/api/v2/devices/backups/latest":
            items = [
                {
                    "deviceId": dev_id,
                    "address": dataset.address_of(dev_id),
                    "backup": _encode(bk, i + 1),
                }
                for i, (dev_id, bk) in enumerate(dataset.latest_per_device())
            ]
            self._send(200, _page(items, page))
            return

        m = _DEVICE_BACKUPS_RE.match(path)
        if m:
            dev_id = int(m.group(1))
            items = [_encode(bk, i + 1) for i, bk in enumerate(dataset.BACKUPS.get(dev_id, []))]
            self._send(200, _page(items, page))
            return

        self._send(404, {"error": "not found"})


def make_server(port=0):
    """Return (httpd, port). port=0 picks a free ephemeral port."""
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    return httpd, httpd.server_address[1]


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Mock Unimus API v2 server")
    ap.add_argument("--port", type=int, default=8085)
    args = ap.parse_args()
    httpd, port = make_server(args.port)
    print(f"mock Unimus API on http://127.0.0.1:{port}  (api key: {dataset.API_KEY})")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.shutdown()
