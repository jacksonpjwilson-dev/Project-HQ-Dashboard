import hashlib
import hmac
import http.client
import json
import sys
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from relay import EventStore, RelayServer, ValidationError, authenticate_event, iso8601, load_configuration, validate_event

class RelayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.project, self.service = str(uuid.uuid4()), str(uuid.uuid4())
        self.allowed = {(self.project, self.service)}; self.now = time.time()
        self.store = EventStore(Path(self.tmp.name) / 'test.sqlite3')
    def payload(self, state='down', observed=None):
        return {'version': 1, 'eventID': str(uuid.uuid4()), 'projectID': self.project, 'serviceID': self.service, 'kind': 'healthCheckFailed' if state != 'healthy' else 'serviceRecovered', 'evidence': {'state': state, 'explanation': 'Observed HTTP response', 'observedAt': iso8601(observed or self.now), 'source': 'Test monitor'}}
    def test_signature_valid_and_tamper_rejected(self):
        body = json.dumps(self.payload()).encode(); sent = str(int(self.now)); secret = 'a' * 32
        signature = 'sha256=' + hmac.new(secret.encode(), sent.encode() + b'.' + body, hashlib.sha256).hexdigest()
        self.assertTrue(authenticate_event(secret, sent, signature, body, self.now))
        self.assertFalse(authenticate_event(secret, sent, signature, body + b' ', self.now))
    def test_replay_window_rejected(self):
        self.assertFalse(authenticate_event('a' * 32, str(int(self.now - 301)), 'sha256=x', b'{}', self.now))
    def test_wrong_service_scope_rejected(self):
        payload = self.payload(); payload['serviceID'] = str(uuid.uuid4())
        with self.assertRaises(ValidationError): validate_event(payload, self.allowed, self.now)
    def test_future_evidence_rejected(self):
        with self.assertRaises(ValidationError): validate_event(self.payload(observed=self.now + 120), self.allowed, self.now)
    def test_contradictory_recovery_rejected(self):
        payload = self.payload(); payload['kind'] = 'serviceRecovered'
        with self.assertRaises(ValidationError): validate_event(payload, self.allowed, self.now)
    def test_event_deduplication_is_persistent(self):
        event = validate_event(self.payload(), self.allowed, self.now)
        self.assertTrue(self.store.ingest(event, self.now))
        reopened = EventStore(self.store.path)
        self.assertFalse(reopened.ingest(event, self.now))
    def test_out_of_order_event_cannot_replace_new_evidence(self):
        self.store.ingest(validate_event(self.payload('healthy'), self.allowed, self.now), self.now)
        self.store.ingest(validate_event(self.payload('down', self.now - 60), self.allowed, self.now), self.now)
        self.assertEqual(self.store.evidence(self.project, self.service)['evidence']['state'], 'healthy')
    def test_recovery_and_evidence_response_format(self):
        self.store.ingest(validate_event(self.payload(), self.allowed, self.now), self.now)
        self.store.ingest(validate_event(self.payload('healthy', self.now + 1), self.allowed, self.now), self.now)
        result = self.store.evidence(self.project, self.service)
        self.assertEqual(result['version'], 1); self.assertEqual(result['serviceID'], self.service)
        self.assertEqual(result['evidence']['state'], 'healthy'); self.assertTrue(result['evidence']['observedAt'].endswith('Z'))
    def test_configuration_rejects_insecure_endpoint(self):
        config = Path(self.tmp.name) / 'config.json'
        config.write_text(json.dumps({'version': 1, 'services': [{'projectID': self.project, 'serviceID': self.service, 'endpoint': 'http://example.com'}]}))
        with self.assertRaises(ValidationError): load_configuration(config)
    def start_server(self):
        server = RelayServer(('127.0.0.1', 0), self.store, self.allowed, 'r' * 32, 'w' * 32)
        worker = threading.Thread(target=server.serve_forever, daemon=True); worker.start()
        self.addCleanup(server.server_close); self.addCleanup(server.shutdown)
        return server.server_address
    def test_http_read_requires_token(self):
        address = self.start_server(); client = http.client.HTTPConnection(*address); self.addCleanup(client.close)
        client.request('GET', f'/v1/projects/{self.project}/services/{self.service}/evidence')
        self.assertEqual(client.getresponse().status, 401)
    def test_http_signed_event_then_authenticated_read(self):
        address = self.start_server(); client = http.client.HTTPConnection(*address); self.addCleanup(client.close)
        body = json.dumps(self.payload()).encode(); sent = str(int(time.time()))
        signature = 'sha256=' + hmac.new(b'w' * 32, sent.encode() + b'.' + body, hashlib.sha256).hexdigest()
        headers = {'Content-Type': 'application/json', 'X-HQ-Timestamp': sent, 'X-HQ-Signature': signature}
        client.request('POST', '/v1/events', body, headers)
        response = client.getresponse(); self.assertEqual(response.status, 202); response.read()
        client.request('POST', '/v1/events', body, headers)
        response = client.getresponse(); self.assertEqual(response.status, 200); self.assertTrue(json.loads(response.read())['duplicate'])
        client.request('GET', f'/v1/projects/{self.project}/services/{self.service}/evidence', headers={'Authorization': 'Bearer ' + 'r' * 32})
        response = client.getresponse(); self.assertEqual(response.status, 200); self.assertEqual(json.loads(response.read())['evidence']['state'], 'down')
    def test_http_invalid_signature_does_not_persist(self):
        address = self.start_server(); client = http.client.HTTPConnection(*address); self.addCleanup(client.close)
        client.request('POST', '/v1/events', json.dumps(self.payload()), {'Content-Type': 'application/json', 'X-HQ-Timestamp': str(int(time.time())), 'X-HQ-Signature': 'sha256=wrong'})
        response = client.getresponse(); self.assertEqual(response.status, 401); response.read()
        self.assertIsNone(self.store.evidence(self.project, self.service))
    def test_http_oversized_body_rejected(self):
        address = self.start_server(); client = http.client.HTTPConnection(*address); self.addCleanup(client.close)
        client.request('POST', '/v1/events', b'x' * 65537, {'Content-Type': 'application/json'})
        self.assertEqual(client.getresponse().status, 413)

if __name__ == '__main__': unittest.main()
