# Supported Codex monitoring bridge

This adapter observes **real notifications from a user-configured Codex CLI app-server connection**, or the CLI's legacy `agent-turn-complete` notify hook. It never reads undocumented session SQLite files, scrapes the Codex desktop UI, or pretends to monitor unrelated cloud/desktop chats.

References checked for this implementation:

- [Official Codex app-server protocol](https://developers.openai.com/codex/app-server/)
- [Official configuration reference](https://developers.openai.com/codex/config-reference/)

The notification protocol is versioned with the installed CLI. Before integrating a new CLI version, run `codex app-server generate-json-schema --out ./schemas` and compare `turn/started`, `turn/completed`, and `thread/status/changed` against this adapter. Unsupported messages are ignored rather than guessed.

## Authentication and scope

1. Authenticate the **workstation's** Codex CLI through its supported `codex login` flow or the official CLI API-key configuration. This adapter does not collect, forward, or embed Codex/OpenAI credentials in the phone app or relay.
2. Add a relay service to the intended Head Quarter project. Export Ecosystem connections from the phone and configure that exact project/service pair in the relay allowlist.
3. Configure these variables in the bridge process's secret manager/environment:
   - `HQ_RELAY_URL`: HTTPS base URL of your private Head Quarter relay.
   - `HQ_PROJECT_ID`, `HQ_SERVICE_ID`: UUIDs from the configured phone project/service.
   - `HQ_CODEX_THREAD_ID`: the **exact thread ID** from your controlling app-server client. Events for other threads are discarded.
   - `HQ_WRITE_SECRET`: relay event-signing secret; distinct from the phone's read token.
4. Optional development task synchronization additionally requires `HQ_TASK_ID` and `HQ_SYNC_TOKEN`. First synchronize that project/task from the phone to the relay. The bridge refuses to create an assumed task or match one by name.

The app-server stdin/stdout client remains responsible for initialization, subscriptions, approval policy, and starting or resuming a thread. This bridge does not approve commands or run a turn automatically. A general public API for arbitrarily reading the current Codex desktop account's or cloud account's sessions is not provided by this integration; those sessions are **not connected** unless their owning client forwards supported notifications.

## Ways to connect

- Use `python3 bridge.py --proxy --outbox /PRIVATE/PATH/codex-outbox.sqlite3` as the app-server executable for a controlling client that normally launches `codex app-server`. The proxy forwards JSON-RPC requests and responses unchanged; a separate worker sends selected monitoring metadata to the relay. No model prompt or response text is retained or forwarded.
- If your existing client already owns the app-server process, copy its notification stream into `python3 bridge.py --stream --outbox /PRIVATE/PATH/codex-outbox.sqlite3`, or call the `Bridge.observe` adapter from that client.
- For a CLI version supporting the legacy notify hook, set the **user-level** Codex `notify` command to `['python3', '/ABSOLUTE/PATH/bridge.py', '--notify']`. Codex supplies the notification JSON as the final argument. This mode reports **completion only**, not reliable starts, approvals, failures, or continuous liveness. It cannot provide unrestricted live task monitoring.
- Supervise the bridge, and retry retained events with `python3 bridge.py --flush --outbox /PRIVATE/PATH/codex-outbox.sqlite3` after connectivity returns. Keep that outbox private. Observations older than one day are marked expired rather than re-timestamped as current evidence.

## Meaning of events

| Supported observation | Development task update (only if explicitly configured) | Monitoring evidence |
| --- | --- | --- |
| `turn/started` for the configured thread | In Progress, subject to dependencies | Fresh evidence that this Codex runner emitted a turn event |
| `turn/completed` with `completed` | **Testing**, never automatically Completed | Turn receipt is passing connection evidence; work still needs verification |
| `turn/completed` with `failed` | Failed | Error; no raw model/API error text is leaked |
| `turn/completed` with `interrupted` | Blocked | Needs Help |
| `thread/status/changed` with `waitingOnApproval` after a known turn start | Blocked | Needs Help |

Turn completion is not proof of a successful build, deployment, app uptime, or acceptance of all task requirements. The integration service name should identify the Codex runner, not a production uptime endpoint. Missing/stale observations expire through the service's configured freshness threshold; silence is never promoted to success. Successful development completion still requires a manual or independently verified task update.

Event UUIDs are deterministic per thread/turn/transition. The local outbox and relay deduplicate retries. Remote task writes use revision compare-and-swap; newer timestamped user edits are preserved. Task titles, notes, dependencies, priorities, and weights are retained. The phone receives remote task updates through configured foreground synchronization or a manual sync, not an unsupported always-running background process.

## Verification limits

The adapter's protocol mapping, wrong-thread rejection, deduplication, dependency handling, outbox persistence, and relay transport are covered by automated fixtures and loopback tests. No user's authenticated live Codex thread is configured in this build environment. **An end-to-end live Codex account/session connection has not been verified**, and the native UI must not show one as connected solely because the adapter is installed.
