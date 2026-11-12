# Remote workspace and ecosystem setup

## Private relay synchronization

The native app and relay implement a single-user workspace endpoint:

- `GET /v1/workspace` → `{ "version": 1, "revision": N, "backup": nativeBackupOrNull }`.
- `PUT /v1/workspace`, native backup body, `If-Match: "N"` → new revision and saved backup.
- Both require `Authorization: Bearer HQ_SYNC_TOKEN`, distinct from event-ingestion, evidence-read, and device-registration credentials.
- Missing revision is rejected; stale revisions return 409; invalid payloads are rejected before mutation. SQLite commits revision and payload atomically and survives process restarts.

Enable `HQ_SYNC_TOKEN` on the deployed HTTPS relay. In the app, enter its full HTTPS `/v1/workspace` URL and token in Project & task synchronization. Tokens stay in Keychain and are not synchronized. The workspace contains project/task/milestone/service/history/incident data, including user-entered notes and endpoint URLs; deploy the relay in private protected storage and use encryption-at-rest provided by your host. The deployment is not a multi-tenant account service.

Normal synchronization uses the last successful per-backend local base to merge independent field edits and additions. Collections merge by UUID; unrelated object ordering does not cause false conflicts. Deletions are preserved when the other side is unchanged. Same-field and delete/edit races stop and preserve both sides. The user can explicitly choose the device or remote side after review. A protected local `before-last-sync.json` safety copy is written to the app's Application Support/Synchronization directory before applying changes. Existing persistent objects are reconciled by ID so open tasks and projects keep their identities. Local edits received during a network request are detected before reconciliation.

First sync never assumes that same-named projects on two devices are identical. Independently seeded projects have distinct UUIDs; to adopt an existing remote workspace on a new device, explicitly choose Use remote workspace after reviewing the preserved safety copy. Do not silently match Logbook or any other project by name. Offline edits stay local; foreground automatic synchronization is opt-in. Server or device unavailability is reported as a sync error and never as successful delivery.

## GitHub repository activity

Add a GitHub service under the intended project's Connected services using `owner/repository`. Refreshing fetches:

- Latest 30 commits, preserving author and original commit date.
- Latest 30 updated pull requests, including draft/open/closed/merged states.
- Latest workflow-run state and actual observation timestamp.

Public repositories can use GitHub's unauthenticated API quota; private repositories need a fine-grained token with Metadata, Contents, Pull requests, and Actions **read** permissions for that repository. The GitHub connection used by this development chat is not automatically transferred to the phone. Authentication/rate-limit failures remain visible; rate-limit cooldowns are persisted. Cached activity shows its last successful fetch and stale status. The page links only to validated HTTPS github.com URLs.

Repository development activity is distinct from task-weighted completion and app operational availability. A merged PR does not automatically complete a manually tracked task. Workflow results expire and do not establish that a production service is up. GitHub mutations, issue-to-task synchronization, OAuth login UI, and direct GitHub webhook signature handling are not implemented. CI systems may post authenticated structured relay events using the documented Head Quarter signing protocol.

## Other ecosystem applications

Settings → Ecosystem monitoring connections lists every actual configured service and its current evidence-based health. Configure each app's real health endpoint or GitHub repository from its project detail screen. No URL or successful heartbeat is invented for Logbook, Daily Briefing, Stack, Crew, YKF Arrivals, Pantry, or Head Quarter.

Export configured relay checks from that screen. The file contains actual project/service IDs, criticality, timeout, expected HTTP status, optional response substring, optional JSON timestamp path, and evidence-expiry interval. HTTPS checks get periodic schedules; Codex/relay/GitHub services get allowlisted webhook IDs without guessed polling endpoints. Secret values are never exported. If a phone-side bearer token exists, the export names a server environment variable such as `HQ_TARGET_TOKEN_<SERVICE_UUID>` that the owner must populate privately.

Use the file as a private relay configuration. Missing server credentials produce Needs Help. HTTPS criteria must actually pass before green; transport errors, rate limits, stale evidence, and missing configuration are unknown. Confirmed critical failures are down; noncritical failures aggregate as errors. Set check intervals shorter than evidence expiry and allow time for expected delays. The phone, Watch, and widgets recompute expiry independently. A scheduled app or automation should emit genuine heartbeat/completion evidence with a threshold matching its expected schedule, not an assumed continuous heartbeat.

Existing `jackson-ops` workflows and credentials remain untouched. Connecting them requires an explicit signed event adapter or a compatible HTTPS health/evidence endpoint; installing Head Quarter does not activate routines or obtain private service access.


For feeds or scheduled jobs, set a dot-separated JSON timestamp path such as `meta.updatedAt`. Values must be ISO 8601 strings or Unix epoch **seconds**, not milliseconds or booleans. The phone ages evidence from that producer timestamp; the relay checks it against `evidenceExpirySeconds`. A new HTTP 200 cannot make old producer data fresh. Missing/invalid timestamps require help, future timestamps are unknown, and stale data is unknown. Leave this field empty for a pure availability endpoint; do not interpret an availability-only check as proof of fresh application data.

Synchronization and push credentials are bound to their configured endpoints. Changing an endpoint requires re-entering its token instead of forwarding an old secret to a new host. CloudKit account authorization is also explicit and account-scoped.
