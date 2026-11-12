# Project HQ / Head Quarter

The existing Project HQ web app remains at the repository root. Head Quarter adds a **native SwiftUI iPhone app** alongside it in `ios/HeadQuarter`, with SwiftData persistence, WidgetKit, ActivityKit, App Intents, and an optional independent monitoring relay. There is no web view in the iPhone app.

## Existing foundation and preservation

Repository discovery found `jacksonpjwilson-dev/Project-HQ-Dashboard` at `659b57aecd80a02c3b61bc38632c663079d21325`. It contained `index.html`, `manifest.webmanifest`, `icon.svg`, static smoke tests, and CI. There were no Swift files, Xcode projects, package dependencies, or AGENTS.md files on its only branch, `main`. Existing features were editable projects and tasks, manually entered percentages, device-local browser storage, and JSON import/export. The original nine web projects include Games, Jarvis, and Automation Infrastructure; none were removed or rewritten.

The owner selected this repository as Head Quarter's home. The separate `jackson-ops` repository remains unchanged and is a future monitoring integration, not a dependency. Its documentation alone does not establish that its services are currently configured or healthy.

All native additions are on `codex/native-head-quarter`. Existing web source, assets, data format, and CI are preserved. The native app accepts the web app's exported `projectHQv1` JSON and retains imported manual percentages as history instead of treating them as calculated completion. Browser localStorage is not automatically accessible from a native app.

## Run the iPhone app

1. On a Mac, install Xcode 16.2 or newer and an iOS Simulator runtime. The deployment target remains **iOS 17.0**.
2. Open `ios/HeadQuarter/HeadQuarter.xcodeproj`. Choose the **HeadQuarter** scheme and an iPhone Simulator; Run.
3. For a physical iPhone, set your signing team on **both** the app and widget targets. Change the sample bundle IDs `com.headquarter.app` and `com.headquarter.app.widgets` to identifiers you own.
4. Register an App Group you own. Replace `group.com.headquarter.app` in both entitlements and `Shared/Domain.swift`; enable that group for both targets. The group shares widget snapshots, not credentials.
5. The first launch registers Logbook, Daily Briefing, Stack, Crew, YKF Arrivals, Pantry, and Head Quarter. They begin with zero tracked completion and **Unknown / Not Configured** health. No external connection or progress is invented.
6. Create tasks and services from Projects. Configure a manual report, HTTPS endpoint, GitHub Actions repository, or monitoring relay. Add notification permission only when you want alerts. Temporary demonstration data is available in Settings and is isolated from the real workspace, exports, integrations, and widget snapshots.

A missing or unreadable local database presents an error and retry; the app never deletes it to recover. Deleting all projects intentionally does not reseed them on the next launch. Local writes explicitly save and roll back on failure. No CloudKit container or paid dependency is required.

## Implemented behavior

| Area | Implementation |
| --- | --- |
| Persistent workspace | SwiftData models for projects, tasks, milestones, services, activity history, incidents, and a one-time seeding marker. Offline editing, cascade deletion, error presentation, explicit saves. |
| Overview | Project count, task-weighted overall completion, healthy/help/error/down service counts, active/completed tasks, unknown coverage, and project cards. Progress and operational health are independent. |
| Projects | Create/edit/delete, descriptions/icons/phases/priorities, dashboard ordering, search, health filtering, sorting by priority/health/completion. Detail screens show work, milestones, evidence, incidents, build/deployment history, errors, and timeline. |
| Work | Seven task states; editable priority, positive work weight, assignee, blocker, planned/actual completion dates; subtasks, dependency-cycle validation, completion prerequisites; Kanban drag-and-drop and list views. Completion history is retained as events when a task is reopened. |
| Milestones | Create with optional planned completion; assign tasks; completion derives from assigned work and reverses when work is reopened. |
| Monitoring | Provider protocol; functional manual reporting with event types; HTTPS status/body criteria; GitHub Actions latest workflow status; authenticated relay evidence. Configurable request timeout, evidence expiry, criticality, and project coverage rules. |
| Incidents | Persisted open → acknowledged → resolved transitions; repeated evidence is deduplicated; fresh passing evidence resolves an existing incident; renewed failure after resolution can create a new incident. Resolving an incident does not override service health. |
| Alerts | UserNotifications permission workflow, severity/category preferences, quiet hours in device local time, incident deduplication, outage/error/approval/recovery/milestone/task-failure alerts. Notification actions acknowledge/resolve incidents; tapping opens the project. |
| Widgets | Small/medium/large Home Screen layouts; inline/circular/rectangular Lock Screen widgets; project selection, progress, alerts, deep links. App Group snapshots and timeline entries expire old evidence without waiting for the phone app. OS refresh budgets still apply. |
| Live Activities | Start from an active task's editor or context menu; one bounded operation at a time, with a one-hour deadline; local updates and completion/failure/deletion/end actions; Lock Screen and compact/minimal/expanded Dynamic Island layouts. |
| Shortcuts | Overall status, projects requiring help, active tasks, open project, create task, recent errors. Native App Intents and App Shortcuts; no private Codex or G.I.L.E.S. API is assumed. Navigation uses an iOS 17-compatible request rather than iOS 18-only OpenURLIntent. |
| Backups | Native JSON export/import including relationships and monitoring history; validated legacy web imports. Imports are additive, refuse colliding project IDs, and never overwrite an existing project. Legacy projects get new IDs; review duplicates before importing. Tokens are excluded. |
| Appearance | Apple-native tabs/navigation/forms, light/dark/system modes, Dynamic Type, semantic labels and icons as well as color, accessible error banners. |
| Optional relay | Python standard-library service with SQLite history, periodic HTTPS checks, authenticated reads, HMAC event ingestion, replay-window checks, event-ID deduplication, and out-of-order protection. No server is deployed automatically. |

The final iPhone app and widget extension compile on Xcode 16.4. The initial 59-test Simulator suite passed; the expanded 65-test runtime rerun is pending after a Simulator startup stall. This is not a claim of App Store readiness: interactive acceptance, notification delivery, widget rendering, and Live Activity behavior still need device validation. See [validation](docs/VALIDATION.md) for exact results and tested revisions.

### Health rules

- **Green:** fresh, passing evidence for all configured checks by default.
- **Yellow:** explicit approval, configuration, or authentication intervention.
- **Orange:** a failed task/build/integration or noncritical service error.
- **Red:** a critical monitor has observed a failing availability response. A failed network connection on the phone does not establish that a remote service is down.
- **Grey:** no evidence, stale evidence, incomplete evidence, invalid future timestamps, or unavailable monitoring connectivity.

Confirmed failures take precedence over unknown coverage. Otherwise, any missing/stale check prevents green. A project can explicitly allow partial coverage; its explanation states that choice. Noncritical `Down` readings become `Error`. GitHub workflow evidence describes that workflow only, not the availability of the app built by it. A running build remains unknown until it concludes; an explicit approval wait is yellow. Successful old builds retain their original timestamp and expire. The app records last monitoring contact separately from evidence observation time.

Every task, including subtasks, contributes its own positive configured weight. Overall progress uses all tracked work rather than averaging project percentages; projects with no tasks add no assumed progress.

### Live integrations and required configuration

- **Manual:** works immediately and offline. Enter actual observed evidence, its source, health, and event kind. Reports expire.
- **HTTPS:** enter an HTTPS endpoint, expected 2xx status, optional required response substring, timeout, and expiry. Tokens use device-only Keychain storage. Redirects are refused to prevent credentials being forwarded to another host.
- **GitHub Actions:** enter `owner/repository`; public repositories can work without a token. Private repositories need a fine-grained token with repository metadata and Actions read permissions. The GitHub connection used during development is **not** embedded in or automatically granted to the app. Authentication failures require help; rate-limit headers establish a persisted cooldown.
- **Relay:** configure the external service described in [monitoring-relay/README.md](monitoring-relay/README.md), copy the project/service IDs from service settings, and supply its HTTPS evidence URL and read token in Keychain. Local relay development uses loopback HTTP; the iPhone provider intentionally requires an HTTPS reverse proxy.
- **Continuous operation and push:** foreground phone checks are configurable from 1–60 minutes. Reliable continuous checks must run externally. This relay can keep checking while the phone is suspended, but **APNs push delivery is not implemented**. Suspended phones receive no new monitoring notifications from this implementation.
- **CloudKit:** disabled. Enabling it needs a deliberate SwiftData relationship/uniqueness migration and CloudKit-compatible schema, container entitlements, and sync UI. Checking a box alone would not make this schema sync safely.

## Project structure

```text
index.html, icon.svg, manifest.webmanifest  Existing web app, unchanged
ci/smoke.mjs                               Existing web smoke test, unchanged
ci/verify-ios.sh                           Mac builds + iOS unit tests
.github/workflows/native-ios.yml           Native validation workflow
ios/
  HeadQuarter/
    HeadQuarter.xcodeproj/                 App, widget, unit-test targets + shared schemes
    HeadQuarter/Models/                    SwiftData model graph and container
    HeadQuarter/Services/                  Store, Keychain, alerts, backups, Live Activities
    HeadQuarter/Views/                     Overview, Projects, Tasks, Activity, Settings
    HeadQuarter/Intents/                   Siri / Spotlight / Shortcuts actions
    Shared/                               Domain rules, monitoring providers, backup codec, activity attributes
    HeadQuarterWidgets/                   WidgetKit and Dynamic Island layouts
    HeadQuarterTests/                     Shared core + Apple-only persistence/integration tests
    Package.swift                         Portable core tests using the same source files
    tools/generate_project.py              Deterministic Xcode project generator; stdlib only
monitoring-relay/                          Optional independent monitor and authenticated event relay
```

## Verification

```sh
# Existing web application and all JSON assets
node ci/smoke.mjs

# Exact shared Swift implementations; no package dependencies
swift test --package-path ios/HeadQuarter

# Relay auth, storage, replay protection, HTTP lifecycle
python3 -m unittest discover -s monitoring-relay/tests -v

# On a Mac: app build, separate widget build, then Simulator unit tests
bash ci/verify-ios.sh

# Optional: capture actual app previews on the booted Simulator after tests
bash ci/capture-ios-previews.sh
```

`HQ_SIMULATOR_UDID` optionally selects a specific simulator for the Mac script. `HQ_RESULTS_DIR` selects its DerivedData directory. The script otherwise chooses an available iPhone. It never requires device signing for Simulator checks. The checked-in Xcode project opens directly; regenerate it after adding sources with `python3 ios/HeadQuarter/tools/generate_project.py`.

For device checks: create/edit/relaunch a project and task; verify weighted progress; enter evidence and wait past expiry; test dependency blocking; export/import; acknowledge/recover an incident; select widget projects and open their links; run each Shortcut; start/update/end a Live Activity on an eligible iPhone. Test notification permission, quiet hours, VoiceOver, large text, light/dark appearance, and offline edits.

## Remaining work and release gates

- Complete interactive Simulator/device acceptance and distribution validation. Native compilation and unit/integration tests run in macOS CI. The final 65-test runtime rerun is pending. Optional previews capture actual Simulator output; no final-revision screenshots were produced during this session.
- Apple Watch app/complications are not included because this Linux environment does not support watchOS development or verification.
- CloudKit sync, APNs notification delivery, ActivityKit push updates, and distribution signing/provisioning are not implemented/configured.
- No supported Codex-session integration, remote task synchronization, GitHub commit-history UI, or automatic deployment-to-task matching is implemented. The provider/event boundaries support future additions; current GitHub integration is read-only workflow monitoring.
- Relay ingest accepts the requested structured event kinds, but the iPhone currently pulls latest service evidence, not a full event-stream history. Manual event entry and GitHub workflow checks populate local build/deployment history. Remote tasks are not silently mutated.
- No always-running background phone process is attempted. A stale local Live Activity is explicitly labeled expired; if iOS suspends the app, local ending may wait until the app resumes or the system removes it. Use a properly configured push backend for authoritative remote operation endings.
- Backups are user-selected plain JSON and can contain private project names, notes, and endpoint URLs. Store them appropriately and use the Keychain field for secrets. Settings and tokens are not part of the backup. This is a single-device local schema with no historical migrations yet; add versioned migrations before a future schema release.
