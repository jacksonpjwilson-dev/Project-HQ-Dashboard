#!/usr/bin/env python3
"""Optional single-user Head Quarter monitoring relay. Python 3.11+, stdlib only.

Run behind a TLS reverse proxy. Nothing is deployed or scheduled by the iOS app.
"""
from __future__ import annotations
import argparse
import hashlib
import hmac
import json
import logging
import os
import re
import signal
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from contextlib import closing
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from workspace import WorkspaceStore, RevisionConflict, MAX_WORKSPACE
from push import PushStore, APNsSender

MAX_BODY = 65536
STATES = {"healthy", "needsHelp", "error", "down", "unknown"}
KINDS = {"taskStarted", "taskCompleted", "taskFailed", "buildSucceeded", "buildFailed", "deploymentCompleted", "integrationDisconnected", "healthCheckFailed", "serviceRecovered", "approvalRequired", "manualReport", "milestoneCompleted"}
LOG = logging.getLogger("headquarter.relay")

class ValidationError(ValueError): pass

def canonical_uuid(value):
    if not isinstance(value, str): raise ValidationError("Identifier must be a UUID")
    try: return str(uuid.UUID(value))
    except (ValueError, AttributeError): raise ValidationError("Identifier must be a UUID") from None

def timestamp(value):
    if not isinstance(value, str): raise ValidationError("Timestamp must be ISO 8601")
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if result.tzinfo is None: raise ValueError()
        return result.timestamp()
    except (ValueError, OverflowError): raise ValidationError("Timestamp must include a timezone") from None

def iso8601(value): return datetime.fromtimestamp(value, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

def validate_event(payload, allowed, now):
    if not isinstance(payload, dict) or payload.get("version") != 1: raise ValidationError("Unsupported event version")
    event_id = canonical_uuid(payload.get("eventID")); project = canonical_uuid(payload.get("projectID")); service = canonical_uuid(payload.get("serviceID"))
    if (project, service) not in allowed: raise ValidationError("Service is not configured")
    if payload.get("kind") not in KINDS: raise ValidationError("Unsupported event kind")
    evidence = payload.get("evidence")
    if not isinstance(evidence, dict) or evidence.get("state") not in STATES: raise ValidationError("Invalid evidence state")
    for key, limit in [("explanation", 4096), ("source", 256)]:
        if not isinstance(evidence.get(key), str) or not evidence[key].strip() or len(evidence[key]) > limit: raise ValidationError("Invalid evidence text")
    observed = timestamp(evidence.get("observedAt"))
    if observed > now + 60 or observed < now - 86400: raise ValidationError("Evidence timestamp is outside the allowed window")
    if payload["kind"] in {"taskFailed", "buildFailed", "healthCheckFailed"} and evidence["state"] not in {"error", "down", "unknown"}: raise ValidationError("Failure event contradicts its evidence")
    if payload["kind"] == "serviceRecovered" and evidence["state"] != "healthy": raise ValidationError("Recovery requires passing evidence")
    if payload["kind"] == "approvalRequired" and evidence["state"] != "needsHelp": raise ValidationError("Approval requires needsHelp evidence")
    return (event_id, project, service, payload["kind"], evidence["state"], evidence["explanation"], observed, evidence["source"])

def authenticate_event(secret, sent_at, signature, body, now):
    if not isinstance(sent_at, str) or not re.fullmatch(r"\d{10}", sent_at): return False
    if abs(now - int(sent_at)) > 300: return False
    expected = "sha256=" + hmac.new(secret.encode(), sent_at.encode() + b"." + body, hashlib.sha256).hexdigest()
    return isinstance(signature, str) and hmac.compare_digest(expected, signature)

class EventStore:
    def __init__(self, path):
        self.path = str(path)
        self.push = None
        self.service_expiries = {}
        with closing(self.connect()) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS events (
                    event_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, service_id TEXT NOT NULL,
                    kind TEXT NOT NULL, state TEXT NOT NULL, explanation TEXT NOT NULL,
                    observed_at REAL NOT NULL, source TEXT NOT NULL, received_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS evidence (
                    project_id TEXT NOT NULL, service_id TEXT NOT NULL, state TEXT NOT NULL,
                    explanation TEXT NOT NULL, observed_at REAL NOT NULL, source TEXT NOT NULL,
                    PRIMARY KEY (project_id, service_id)
                );
                CREATE INDEX IF NOT EXISTS events_received ON events(received_at);
            """)
    def connect(self): return sqlite3.connect(self.path, timeout=10)
    def ingest(self, event, now):
        event_id, project, service, kind, state, explanation, observed, source = event
        with closing(self.connect()) as db, db:
            result = db.execute("INSERT OR IGNORE INTO events VALUES (?,?,?,?,?,?,?,?,?)", (*event, now))
            created = result.rowcount != 0
            previous = db.execute("SELECT state,observed_at FROM evidence WHERE project_id=? AND service_id=?", (project,service)).fetchone()
            updated = db.execute("""INSERT INTO evidence VALUES (?,?,?,?,?,?)
                ON CONFLICT(project_id, service_id) DO UPDATE SET state=excluded.state,
                explanation=excluded.explanation, observed_at=excluded.observed_at, source=excluded.source
                WHERE excluded.observed_at >= evidence.observed_at AND ?""", (project, service, state, explanation, observed, source, 1 if created else 0))
            db.execute("DELETE FROM events WHERE received_at < ?", (now - 30 * 86400,))
        eligible = (created and updated.rowcount > 0) or (not created and previous == (state, observed))
        if self.push is not None and eligible:
            self.push.observe(event, self.service_expiries.get((project,service),600), now)
        return created
    def evidence(self, project, service):
        with closing(self.connect()) as db:
            row = db.execute("SELECT state,explanation,observed_at,source FROM evidence WHERE project_id=? AND service_id=?", (project, service)).fetchone()
        if row is None: return None
        return {"version": 1, "serviceID": service, "evidence": {"state": row[0], "explanation": row[1], "observedAt": iso8601(row[2]), "source": row[3]}}

class RelayServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, store, allowed, read_token, write_secret, sync_token=None, device_token=None, push_sender=None):
        self.workspace = WorkspaceStore(store.path); self.sync_token = sync_token
        self.device_token = device_token; self.push_sender = push_sender; self.push = PushStore(store.path)
        store.push = self.push
        self.store = store; self.allowed = allowed; self.read_token = read_token; self.write_secret = write_secret
        super().__init__(address, RelayHandler)

class RelayHandler(BaseHTTPRequestHandler):
    server_version = "HeadQuarterRelay/1"
    def setup(self):
        super().setup(); self.connection.settimeout(10)
    def log_message(self, format, *args):
        # Never log request paths, headers, payloads, or configured endpoint URLs.
        LOG.info("request completed")
    def reply(self, status, payload):
        data = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff"); self.end_headers(); self.wfile.write(data)
    def sync_authorized(self):
        if not self.server.sync_token:
            self.reply(503, {"error": "workspace synchronization is not configured"}); return False
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), ("Bearer " + self.server.sync_token).encode()):
            self.reply(401, {"error": "unauthorized"}); return False
        return True
    def do_PUT(self):
        if self.path != "/v1/workspace": self.close_connection = True; return self.reply(404, {"error": "not found"})
        if not self.sync_authorized(): self.close_connection = True; return
        try:
            if self.headers.get("Transfer-Encoding") is not None or self.headers.get_content_type() != "application/json": raise ValueError()
            length = int(self.headers.get("Content-Length", "-1"))
            if not 0 < length <= MAX_WORKSPACE: self.close_connection = True; return self.reply(413, {"error": "workspace too large"})
            match = re.fullmatch(r'"(\d+)"', self.headers.get("If-Match", ""))
            if not match: self.close_connection = True; return self.reply(428, {"error": "If-Match revision required"})
            payload = json.loads(self.rfile.read(length))
            result = self.server.workspace.save(payload, int(match.group(1)))
        except RevisionConflict: return self.reply(409, {"error": "revision conflict"})
        except (ValueError, KeyError, TypeError, RecursionError): return self.reply(400, {"error": "invalid workspace"})
        except sqlite3.Error: return self.reply(503, {"error": "storage unavailable"})
        return self.reply(200, result)
    def do_GET(self):
        if self.path == "/v1/workspace":
            if not self.sync_authorized(): return
            try: return self.reply(200, self.server.workspace.fetch())
            except sqlite3.Error: return self.reply(503, {"error": "storage unavailable"})
        authorization = self.headers.get("Authorization", "")
        if not hmac.compare_digest(authorization.encode(), ("Bearer " + self.server.read_token).encode()): return self.reply(401, {"error": "unauthorized"})
        match = re.fullmatch(r"/v1/projects/([0-9a-fA-F-]+)/services/([0-9a-fA-F-]+)/evidence", self.path)
        if not match: return self.reply(404, {"error": "not found"})
        try: key = tuple(canonical_uuid(item) for item in match.groups())
        except ValidationError: return self.reply(400, {"error": "invalid identifiers"})
        if key not in self.server.allowed: return self.reply(404, {"error": "not found"})
        result = self.server.store.evidence(*key)
        if result is None: return self.reply(404, {"error": "no monitoring evidence"})
        return self.reply(200, result)
    def do_DELETE(self):
        if not self.path.startswith("/v1/devices/"): return self.reply(404,{"error":"not found"})
        if not self.device_authorized(): return
        try: self.server.push.unregister(self.path.rsplit("/",1)[1])
        except ValueError: return self.reply(400,{"error":"invalid device"})
        return self.reply(200,{"removed":True})
    def device_authorized(self):
        if not self.server.device_token or self.server.push_sender is None: self.reply(503,{"error":"APNs is not configured"}); return False
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(),("Bearer "+self.server.device_token).encode()): self.reply(401,{"error":"unauthorized"}); return False
        return True
    def do_POST(self):
        if self.path == "/v1/devices":
            if not self.device_authorized(): self.close_connection=True; return
            try:
                length=int(self.headers.get("Content-Length","-1"))
                if self.headers.get("Transfer-Encoding") is not None or not 0<length<=8192 or self.headers.get_content_type()!="application/json": raise ValueError()
                self.server.push.register(json.loads(self.rfile.read(length)))
            except (ValueError,KeyError,TypeError): self.close_connection=True; return self.reply(400,{"error":"invalid registration"})
            return self.reply(200,{"registered":True})
        if self.path != "/v1/events": self.close_connection = True; return self.reply(404, {"error": "not found"})
        if self.headers.get("Transfer-Encoding") is not None: self.close_connection = True; return self.reply(400, {"error": "chunked bodies are not accepted"})
        try: length = int(self.headers.get("Content-Length", "-1"))
        except ValueError: length = -1
        if not 0 < length <= MAX_BODY: self.close_connection = True; return self.reply(413, {"error": "invalid body size"})
        if self.headers.get_content_type() != "application/json": self.close_connection = True; return self.reply(415, {"error": "JSON required"})
        body = self.rfile.read(length)
        if len(body) != length: self.close_connection = True; return self.reply(400, {"error": "incomplete body"})
        now = time.time()
        if not authenticate_event(self.server.write_secret, self.headers.get("X-HQ-Timestamp"), self.headers.get("X-HQ-Signature"), body, now): return self.reply(401, {"error": "unauthorized"})
        try:
            payload = json.loads(body)
            event = validate_event(payload, self.server.allowed, now)
        except (ValueError, TypeError, RecursionError): return self.reply(400, {"error": "invalid event"})
        try: created = self.server.store.ingest(event, now)
        except sqlite3.Error: LOG.exception("storage failure"); return self.reply(503, {"error": "storage unavailable"})
        return self.reply(202 if created else 200, {"accepted": True, "duplicate": not created})

class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl): return None

def check_target(target, now):
    parsed = urllib.parse.urlsplit(target["endpoint"])
    headers = {"User-Agent": "HeadQuarterRelay/1"}
    if target.get("tokenEnv"):
        token = os.environ.get(target["tokenEnv"])
        if not token: return "needsHelp", "Configured endpoint credential is missing"
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(target["endpoint"], headers=headers)
    opener = urllib.request.build_opener(NoRedirects())
    try:
        with opener.open(request, timeout=target.get("timeoutSeconds", 15)) as response:
            status = response.status
            marker = target.get("requiredBodyText", "")
            if marker:
                data = response.read(1024 * 1024 + 1)
                if len(data)>1024*1024 or marker not in data.decode("utf-8", errors="replace"): return "error", "Required response text was missing"
    except urllib.error.HTTPError as error: status = error.code
    except (urllib.error.URLError, OSError, ValueError): return "unknown", "Monitor could not establish a verified connection"
    if status == target.get("expectedHTTPStatus", 200): return "healthy", f"HTTPS health criteria passed (HTTP {status})"
    if status in {401, 403}: return "needsHelp", "Endpoint authentication requires attention"
    if status == 429: return "unknown", "Endpoint rate limited the monitor"
    return ("down" if target.get("critical", True) and status >= 500 else "error"), f"HTTPS health check returned HTTP {status}"

def scheduler(store, targets, stop, push=None, sender=None):
    due = {}
    while not stop.is_set():
        for target in targets:
            key = (target["projectID"], target["serviceID"])
            if time.monotonic() < due.get(key, 0): continue
            state, message = check_target(target, time.time())
            now = time.time(); due[key] = time.monotonic() + target.get("intervalSeconds", 300)
            kind = "serviceRecovered" if state == "healthy" else "approvalRequired" if state == "needsHelp" else "healthCheckFailed"
            event = (str(uuid.uuid4()), *key, kind, state, message, now, "Head Quarter relay HTTPS check")
            try: store.ingest(event, now)
            except sqlite3.Error: LOG.exception("scheduled check storage failure")
        stop.wait(1)

def load_configuration(path):
    data = json.loads(Path(path).read_text())
    if not isinstance(data, dict) or data.get("version") != 1: raise ValidationError("Unsupported configuration")
    services = data.get("services", [])
    if not isinstance(services, list) or len(services) > 1000: raise ValidationError("Invalid service list")
    allowed = set(); targets = []
    for service in services:
        key = (canonical_uuid(service.get("projectID")), canonical_uuid(service.get("serviceID")))
        if key in allowed: raise ValidationError("Duplicate configured service")
        allowed.add(key)
        if service.get("endpoint"):
            url = urllib.parse.urlsplit(service["endpoint"])
            if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment: raise ValidationError("Checks require HTTPS endpoints without embedded credentials")
            expected=service.get("expectedHTTPStatus",200)
            if isinstance(expected,bool) or not isinstance(expected,int) or not 200<=expected<=299:raise ValidationError("Invalid expected HTTP status")
            if not isinstance(service.get("requiredBodyText",""),str):raise ValidationError("Invalid response criterion")
            expiry=service.get("evidenceExpirySeconds",600)
            if isinstance(expiry,bool) or not isinstance(expiry,int) or not 60<=expiry<=604800:raise ValidationError("Invalid evidence expiry")
            interval = service.get("intervalSeconds", 300); timeout = service.get("timeoutSeconds", 15)
            if isinstance(interval, bool) or not isinstance(interval, int) or not 60 <= interval <= 86400: raise ValidationError("Invalid check interval")
            if isinstance(timeout, bool) or not isinstance(timeout, int) or not 5 <= timeout <= 60: raise ValidationError("Invalid timeout")
            targets.append(dict(service, projectID=key[0], serviceID=key[1]))
    return allowed, targets

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True); parser.add_argument("--database", default="relay.sqlite3")
    parser.add_argument("--host", default="127.0.0.1"); parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    read_token = os.environ.get("HQ_READ_TOKEN", ""); write_secret = os.environ.get("HQ_WRITE_SECRET", "")
    if min(len(read_token), len(write_secret)) < 32 or hmac.compare_digest(read_token, write_secret): parser.error("Set distinct HQ_READ_TOKEN and HQ_WRITE_SECRET values, each at least 32 characters")
    allowed, targets = load_configuration(args.config)
    store = EventStore(args.database); stop = threading.Event()
    sync_token = os.environ.get("HQ_SYNC_TOKEN")
    if sync_token and (len(sync_token) < 32 or sync_token in {read_token, write_secret}): parser.error("HQ_SYNC_TOKEN must be distinct and at least 32 characters")
    device_token=os.environ.get("HQ_DEVICE_TOKEN")
    if device_token and (len(device_token)<32 or device_token in {read_token,write_secret,sync_token}): parser.error("HQ_DEVICE_TOKEN must be distinct and at least 32 characters")
    sender=APNsSender.configured()
    server = RelayServer((args.host, args.port), store, allowed, read_token, write_secret, sync_token=sync_token,device_token=device_token,push_sender=sender)
    for item in json.loads(Path(args.config).read_text()).get("services",[]):
        store.service_expiries[(canonical_uuid(item["projectID"]),canonical_uuid(item["serviceID"]))] = max(60,min(604800,int(item.get("evidenceExpirySeconds",600))))
    def deliver_pushes():
        while not stop.is_set():
            try: server.push.deliver(sender,time.time())
            except sqlite3.Error: LOG.error("push storage unavailable")
            stop.wait(1)
    threading.Thread(target=deliver_pushes,daemon=True).start()
    worker = threading.Thread(target=scheduler, args=(store, targets, stop, server.push, sender), daemon=True); worker.start()
    def shutdown(signum, frame): stop.set(); threading.Thread(target=server.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, shutdown); signal.signal(signal.SIGINT, shutdown)
    logging.basicConfig(level=logging.INFO)
    try: server.serve_forever(poll_interval=0.5)
    finally: stop.set(); server.server_close(); worker.join(timeout=65)

if __name__ == "__main__": main()
