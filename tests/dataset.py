"""Single source of truth for the test corpus.

Both the mock Unimus server (`mock_server.py`) and the expected-tree builder
(`build_expected.py`) import this module, so the fixtures served over HTTP and the
expected output on disk can never drift apart.

This file is language-agnostic data + the file-naming contract. Every exporter
implementation must reproduce the same expected trees, so treat `date_str()` /
`rel_path()` below as the spec they match byte-for-byte.
"""

from datetime import datetime, timezone

# Must match the api key written into the generated .env by the test driver.
API_KEY = "test-api-key"

# Deliberately tiny so the small corpus still spans several pages and exercises
# the pagination loops. The real Unimus default is larger; the script never
# sends a size param and relies on an empty `data` page to terminate.
PAGE_SIZE = 2

# Unimus device id -> address. Three devices => 2 data pages + 1 empty page at
# PAGE_SIZE=2, so the device-pagination loop is genuinely exercised.
DEVICES = [
    {"id": 1, "address": "10.0.0.1"},
    {"id": 2, "address": "switch01.lab"},
    {"id": 3, "address": "10.0.0.3"},
]

# device id -> backups, oldest first. The newest entry (last) is what the
# `latest` endpoint returns for that device.
#   validSince : unix epoch (seconds), as Unimus returns it
#   type       : TEXT -> .txt, BINARY -> .bin
#   content    : the DECODED payload; the mock server base64-encodes it on the
#                wire, the expected builder writes it verbatim to disk.
#
# Device 1 has 3 backups (2 data pages + empty) so the per-device backup
# pagination loop in `all` mode is exercised, not just page 0.
BACKUPS = {
    1: [
        {"validSince": 1609459200, "type": "TEXT",   "content": b"hostname router1\ninterface eth0\n"},
        {"validSince": 1612137600, "type": "TEXT",   "content": b"hostname router1\ninterface eth0\nip 10.0.0.1\n"},
        {"validSince": 1614556800, "type": "TEXT",   "content": b"hostname router1\nversion 3\n"},
    ],
    2: [
        {"validSince": 1617235200, "type": "BINARY", "content": bytes(range(16))},
    ],
    3: [
        {"validSince": 1619827200, "type": "TEXT",   "content": b"switch config\n"},
    ],
}


# --- file-naming contract (mirror of saveBackup + the date format in the script) ---

def address_of(device_id):
    for d in DEVICES:
        if d["id"] == device_id:
            return d["address"]
    raise KeyError(device_id)


def date_str(epoch):
    """Reproduce `date "+%F-%T-%Z" -d "@<epoch>"` under TZ=UTC."""
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%d-%H:%M:%S-UTC")


def ext_of(btype):
    return "txt" if btype == "TEXT" else "bin"


def rel_path(device_id, backup):
    """(dir, filename) relative to the backups/ root, matching saveBackup()."""
    address = address_of(device_id)
    folder = f"{address} - {device_id}"
    name = f"Backup {address} {date_str(backup['validSince'])} {device_id}.{ext_of(backup['type'])}"
    return folder, name


def latest_per_device():
    """[(device_id, newest_backup)] in device order - the `latest` corpus."""
    return [(d["id"], BACKUPS[d["id"]][-1]) for d in DEVICES if BACKUPS.get(d["id"])]


def all_backups():
    """[(device_id, backup)] across every device - the `all` corpus."""
    out = []
    for d in DEVICES:
        for b in BACKUPS.get(d["id"], []):
            out.append((d["id"], b))
    return out
