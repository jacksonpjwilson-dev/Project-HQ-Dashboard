# Optional Head Quarter relay

A private single-user service for continuous HTTPS checks, signed structured events, workspace synchronization, and optional APNs delivery. The phone is not required to run continuously. No deployment, external account, `jackson-ops` workflow, or scheduled routine is activated by adding this code.

The core uses Python 3.11+ standard library. Optional APNs HTTP/2/ES256 requires `pip install -r requirements-push.txt` in a private virtual environment. Test signing uses a generated test key and a mocked Apple transport; no test is sent to a real device.

## Configure and run

1. Add actual service connections in the phone's projects. Settings → Ecosystem monitoring connections exports their exact UUIDs, HTTPS endpoints, HTTP/body/timestamp criteria, timeout, criticality, and evidence expiry. The export contains environment-variable names for credentials, never secret values.
2. Save a private configuration as `config.local.json`, based on `config.example.json` or the phone export. Omit `endpoint` for webhook-only/Codex services. Scheduled targets require HTTPS without embedded credentials, interval 60–86400 seconds, timeout 5–60 seconds, expected 2xx status (default 200), optional `requiredBodyText`, optional dot-separated `timestampPath`, and `evidenceExpirySeconds` (60–604800).
3. Set distinct secret-manager/environment values of at least 32 characters: `HQ_READ_TOKEN` for evidence reads, `HQ_WRITE_SECRET` for signed event ingestion, optional `HQ_SYNC_TOKEN` for the private workspace, and optional `HQ_DEVICE_TOKEN` for APNs device registration. Generate high-entropy ASCII values; never commit them or pass them in command arguments.
4. If a target names `tokenEnv`, configure that environment variable with its bearer credential. Missing credentials return Needs Help, not a successful check. Set evidence expiry longer than the check interval plus expected scheduling/network delay.
5. Run `python3 relay.py --config config.local.json --database /PRIVATE/DATA/relay.sqlite3`. Default binding is `127.0.0.1:8787`. Use private filesystem permissions, encrypted host storage, SQLite-aware backups, and a process supervisor for restart/reboot persistence.
6. Put the service behind a TLS reverse proxy with connection/rate/body limits. The built-in server is a reference integration layer, not an internet-facing TLS server. The iPhone refuses plaintext URLs. Permit the monitoring routes plus any explicitly enabled sync/device routes.

Scheduled checks are sequential and intended for a small personal ecosystem; APNs delivery has a separate worker so provider failures do not block health checks. Scale to a worker queue or an established monitoring service for many slow targets. HTTPS status/body criteria must actually pass. A verified critical HTTP availability failure can be down; transport/rate-limit failures are unknown. For data feeds, a configured producer timestamp can be stale even if HTTP returns 200. JSON timestamps must be ISO 8601 or Unix epoch seconds; invalid/missing values require help, future or stale data is unknown. A healthy availability check alone does not prove fresh business data.

## Evidence and structured events

`GET /v1/projects/PROJECT_UUID/services/SERVICE_UUID/evidence` requires `Authorization: Bearer HQ_READ_TOKEN`. It returns version 1, the service UUID, and original evidence (`state`, `explanation`, `observedAt`, `source`). It never re-timestamps old evidence. No configured evidence returns 404; the phone does not infer health from that absence.

Send `POST /v1/events` with JSON, an exact Content-Length of at most 65536 bytes, and:

- `X-HQ-Timestamp`: current Unix epoch seconds.
- `X-HQ-Signature`: `sha256=` plus lowercase hex HMAC-SHA256 of the exact bytes `timestamp + "." + body`, keyed by `HQ_WRITE_SECRET`.

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
    "observedAt": "2026-11-12T12:00:00Z",
    "source": "Configured CI monitor"
  }
}
```

Use actual configured IDs, new event UUIDs, and real current observation timestamps; the example is documentation, not a live report. The signature window is five minutes. Evidence may be at most one day old and sixty seconds in the future. The project/service pair must be allowlisted. New events return 202; duplicates return 200 without another stored event. Older evidence cannot replace newer evidence. Contradictory failure/recovery/approval states are rejected. Events retain 30 days of history; latest evidence keeps its original timestamp. Credentials, headers, bodies, and endpoint URLs are not logged.

Supported kinds: taskStarted, taskCompleted, taskFailed, buildSucceeded, buildFailed, deploymentCompleted, integrationDisconnected, healthCheckFailed, serviceRecovered, approvalRequired, manualReport, milestoneCompleted. States: healthy, needsHelp, error, down, unknown. The sender must supply genuine evidence; a started/completed task is not automatically proof that the app's other services are healthy.

## Workspace synchronization

`GET /v1/workspace` and `PUT /v1/workspace` use **HQ_SYNC_TOKEN**, never the evidence-read token. PUT requires `If-Match: "REVISION"` and a validated native workspace backup, at most 20 MB. SQLite atomically advances the revision; stale writers receive 409 and cannot overwrite newer work. Missing revision receives 428. No workspace initially returns revision zero with null backup.

The native app performs a three-way merge and in-place reconciliation with safety backups, while the relay enforces atomic compare-and-swap. See [remote synchronization](../docs/REMOTE_SYNCHRONIZATION.md) for conflict handling, first-device/new-device behavior, privacy, and supported limits. The service is single-user; add proper user authentication/tenant isolation before offering it to anyone else.

The [Codex adapter](../integrations/codex/README.md) can observe a real owning app-server client's notifications, post signed evidence, and update an exact configured remote task via this endpoint. It does not expose arbitrary Codex desktop/cloud sessions or approve commands. It preserves newer user edits and never automatically marks development work Completed.

## Optional Apple push delivery

Configure `APNS_TEAM_ID`, `APNS_KEY_ID`, owner-only `APNS_KEY_PATH`, and `APNS_TOPIC` with your Apple credentials, plus `HQ_DEVICE_TOKEN`. Only then can `POST /v1/devices` register a device or `DELETE /v1/devices/DEVICE_UUID` remove it, using the separate device-registration bearer token. The phone supplies the actual Apple token, sandbox/production environment, timezone, and notification preferences after explicit permission/configuration.

The provider signs ES256 JWTs with the server-held key, uses HTTP/2 to Apple's fixed provider endpoints, deduplicates per-device incident transitions, applies quiet hours and severity/category preferences, expires stale queued alerts, retries transient failures, and removes tokens rejected with HTTP 410. Unknown evidence never resolves an incident or creates a passing recovery. Repeated equivalent incidents do not create another delivery. Delivery state remains pending if no provider is configured; installation does not simulate success.

**Actual APNs delivery is unverified until configured and tested on the owner's signed physical device.** Relay registration is not proof of Apple delivery. See [Apple setup](../docs/APPLE_CONFIGURATION.md) for exact entitlements, environment matching, container/account gates, and device test cases. ActivityKit push and silent/background workspace sync remain incomplete.

## Verification

From repository root: `python3 -m unittest discover -s monitoring-relay/tests -v`. Tests cover SQLite/CAS/restarts, real loopback HTTPS signed ingestion and Codex task transitions, wrong-thread and duplicate filtering, newer-human/Completed-task protection, producer-data freshness, push incident deduplication/quiet hours/stale expiry/token invalidation, and real ES256 signing against a mocked HTTP/2 transport. These are not live Apple or live authenticated Codex account tests.

Existing `jackson-ops` routines, bot credentials, notification channels, and activation rules remain unchanged. Connect it only by configuring an explicit compatible endpoint/event adapter after independently checking its current deployment.
