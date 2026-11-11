# Optional Head Quarter monitoring relay

This is an independent, single-user service for HTTPS checks and authenticated structured events. It does not depend on continuous iPhone execution. Nothing is deployed, enabled, or connected to `jackson-ops` automatically. Python 3.11+ and the standard library are sufficient; there are no paid dependencies.

## Setup

1. Add a relay service in the iPhone app, save it, then reopen service settings to copy its project and service UUIDs. Use those IDs in a private copy of `config.example.json` named `config.local.json`.
2. Omit `endpoint` for a webhook-only service. For a scheduled check, supply an HTTPS endpoint, `intervalSeconds` (60–86400), `timeoutSeconds` (5–60), and optional `critical`. Targets are trusted administrator configuration; there is no remote endpoint-configuration API. An optional `tokenEnv` names an environment variable containing the target's bearer credential; never put it in the endpoint URL.
3. Generate **distinct** read and write credentials of at least 32 characters. Supply `HQ_READ_TOKEN` and `HQ_WRITE_SECRET` from your host's secret manager/environment, never from committed files or command arguments. For local development, `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'` can generate each value; do not share it in chat.
4. Run `python3 relay.py --config config.local.json --database relay.sqlite3`. Default binding is `127.0.0.1:8787`. Give the process a private writable data directory. Use a process supervisor for restart/reboot persistence and back up the SQLite database using SQLite's backup API (it uses WAL).
5. Place it behind an HTTPS reverse proxy. Restrict network access, apply request/connection limits, set a 64 KiB body limit, and forward only the required routes. The built-in server is a small reference integration layer, not an internet-facing TLS server. The iPhone refuses plaintext relay URLs.
6. Configure the phone's service endpoint as `https://YOUR_HOST/v1/projects/PROJECT_UUID/services/SERVICE_UUID/evidence`; put `HQ_READ_TOKEN` in the secure token field. Configure evidence expiry longer than the external check interval plus expected scheduling/network delay.

The scheduler checks configured targets sequentially and stores evidence even when no phone is connected. A verified expected 2xx response passes. HTTP 5xx on a critical target reports down; authentication needs help; transport errors and rate limits are unknown. Phone-side per-service criticality still determines aggregation. For many or slow targets, use a worker queue or your existing monitoring system instead of this small sequential scheduler. External deployment and process supervision are required for 24/7 service.

## Authenticated events

Send `POST /v1/events` with `Content-Type: application/json`, a `Content-Length` no greater than 65536 bytes, and these headers:

- `X-HQ-Timestamp`: current Unix epoch seconds as ten decimal digits.
- `X-HQ-Signature`: `sha256=` plus lowercase hex HMAC-SHA256 of the exact bytes `timestamp + "." + body`, keyed by `HQ_WRITE_SECRET`.

Payload:

```json
{
  "version": 1,
  "eventID": "00000000-0000-0000-0000-000000000003",
  "projectID": "00000000-0000-0000-0000-000000000001",
  "serviceID": "00000000-0000-0000-0000-000000000002",
  "kind": "healthCheckFailed",
  "evidence": {
    "state": "down",
    "explanation": "Health endpoint returned HTTP 503",
    "observedAt": "2026-11-11T12:00:00Z",
    "source": "My CI monitor"
  }
}
```

Use real current timestamps and new UUIDs; the example is not a live event. Signatures expire after five minutes. Evidence can be at most one day old and at most sixty seconds in the future. The project/service pair must be configured. Duplicate event IDs return 200 with `duplicate: true` and do not create another event; accepted new events return 202. Older observed evidence cannot replace newer evidence. Events are retained for 30 days; latest evidence keeps its original timestamp so the phone can mark it stale. Secrets, headers, bodies, and endpoint URLs are not logged.

Supported kinds: taskStarted, taskCompleted, taskFailed, buildSucceeded, buildFailed, deploymentCompleted, integrationDisconnected, healthCheckFailed, serviceRecovered, approvalRequired, manualReport, milestoneCompleted. Evidence states: healthy, needsHelp, error, down, unknown. The caller explicitly supplies evidence; a task-start event is not inferred to mean the project's services are healthy. Contradictory failure/recovery/approval evidence is rejected.

Read latest evidence with `Authorization: Bearer HQ_READ_TOKEN`. Reads never change observation time. Unknown services, or configured services with no evidence, return 404. The iPhone provider validates response version, service ID, timestamp, and text limits before persisting a report. It currently pulls latest evidence; it does not import every server event or mutate development tasks.

## Push delivery boundary and future jackson-ops integration

APNs delivery is **not implemented**. An external monitor running continuously does not, by itself, deliver alerts to a suspended phone. To add it, implement authenticated device registration with Keychain-backed user identity, store device tokens encrypted at rest, associate them with the owner's projects, and send APNs provider requests from the server using an Apple team/key/topic configured in a secret manager. Persist an incident key and per-device delivery state to deduplicate failure/escalation/recovery pushes. Apply the user's quiet hours and severity preferences on the server. Add retry/backoff and APNs token-invalid handling; revoke registration on sign-out. Never ship an APNs provider signing key inside the app.

ActivityKit push needs a separate registered per-activity push token and operation lifecycle. Remote completion must end the specific activity; do not create permanent health-monitor activities. These boundaries are documented rather than represented by a fake push sender.

`jackson-ops` may later post signed health results or expose a compatible evidence adapter. Its existing workflow activation rules, credentials, scheduling, and notification channels must be assessed independently. No workflow, routine, secret, or bot in that repository is changed here.

## Tests

From the repository root: `python3 -m unittest discover -s monitoring-relay/tests -v`. Tests cover real loopback HTTP ingestion/read flows, invalid signatures, request limits, timestamp validation, configured scope, durable deduplication, recovery, and out-of-order events. They do not deploy a server or call external targets.
