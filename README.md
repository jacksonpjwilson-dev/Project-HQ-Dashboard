# Project HQ / Head Quarter

Head Quarter is a native **iOS 17+ SwiftUI application** added inside the existing Project HQ repository. The original `index.html`, web manifest, icon, legacy JSON format, smoke test, and web CI are preserved unchanged. The native app uses SwiftData, WidgetKit, ActivityKit, App Intents, CloudKit, and WatchConnectivity. No web view or paid runtime dependency is used.

Development continues in [Draft PR #1](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/pull/1) on `codex/native-head-quarter`. Existing base: `659b57aecd80a02c3b61bc38632c663079d21325`. Initial repository discovery found a functional web app and no Swift/Xcode foundation or AGENTS.md. The owner selected this repository; `jackson-ops` remains unchanged and is not connected automatically.

## Run in Xcode

1. Open `ios/HeadQuarter/HeadQuarter.xcodeproj` on a Mac with Xcode 16.4 or newer. Select **HeadQuarter** and an iPhone Simulator. Deployment target remains iOS 17.
2. For devices, select your signing team on the app, widgets, and Watch targets; replace the sample `com.headquarter.app` identifiers with owned identifiers. Update the Watch companion bundle reference to match.
3. Register an App Group and replace `group.com.headquarter.app` in the app/widget entitlements and `Shared/Domain.swift`. Snapshots, not secrets, use this group.
4. The first launch registers Logbook, Daily Briefing, Stack, Crew, YKF Arrivals, Pantry, and Head Quarter. They begin with no assumed progress and **Unknown / Not Configured** health. Add actual tasks and services from Projects.
5. Optional remote sync, Codex, iCloud, and push require explicit setup. Default `HQCloudKitEnabled` and `HQPushEnabled` are false. They do not represent successful connections simply because code is installed.

The checked-in Xcode project opens directly. Regenerate after adding source files with `python3 ios/HeadQuarter/tools/generate_project.py`. The generator uses only Python's standard library. Keep owned signing settings in your local build configuration when regenerating the sample project.

## Implemented functionality

| Area | Behavior |
| --- | --- |
| Local workspace | SwiftData projects, tasks, milestones, services, events, incidents, repository cache, and one-time seeding. Offline editing, explicit saves, rollback errors, and cascade deletion. Empty workspaces stay empty after intentional deletion. |
| Dashboard and work | Seven seed projects; progress calculated from positive task weights; health separate from development progress. Project CRUD, sorting/filtering/order, editable priorities/phases, Kanban/list tasks, assignees, blockers, planned/actual dates, dependencies/subtasks with cycle validation, milestones and history. |
| Evidence-based monitoring | Manual reports, HTTPS status/body criteria, optional producer JSON timestamps, GitHub Actions, authenticated relay evidence. Criticality, timeout, expiry, project coverage rules, rate-limit cooldowns, stale/future-data detection. HTTP 200 with stale feed data does not become green. |
| GitHub activity | Actual latest-30 commits and pull requests plus latest workflow; original dates, draft/open/closed/merged states, cached fetch/error state, source links, stale labels. No inferred task completion or production uptime from commits/PRs. |
| Codex bridge | Supported app-server notification observer/proxy and legacy CLI completion hook; exact thread/project/service/task mapping, durable outbox, HMAC events, idempotent remote task updates, approval/failure handling, newer-human-edit protection. A finished turn maps to **Testing**, never automatic verified completion. |
| Remote project/task sync | Authenticated HTTPS workspace endpoint; revision compare-and-swap, durable SQLite state, three-way field/object merge, independent additions/deletions, visible conflicts, explicit resolution, safety backups, in-place SwiftData reconciliation, opt-in foreground sync. Credentials stay device-local. |
| CloudKit transport | Optional private CKAsset workspace backend using the same merge engine and conditional saves. Explicit Apple configuration and current-account authorization; account-specific sync bases. No direct migration of the existing SwiftData graph to CloudKit is performed. |
| Incidents/alerts | Open → acknowledged → resolved, repeated-incident deduplication, evidence-backed recovery, local notification preferences/quiet hours/severity/category controls and actions. Optional remote device registration and APNs relay with per-device deduplication, stale-push expiry, quiet hours, retries, and invalid-token removal. |
| Widgets/Live Activities | Home Screen small/medium/large and Lock Screen accessories, project selection/deep links, component-level expiry timelines; bounded local task Live Activities and Dynamic Island layouts with lifecycle/end handling. OS refresh/background limits apply. |
| Apple Watch | Real watchOS 10+ companion target; paired-phone snapshots, system/project health and progress, outstanding tasks/incidents, queued acknowledgement. Local expiry recomputation, payload-size budget, explicit limited-snapshot labels, and unknown status when evidence cannot fit. |
| Backups/settings | Native JSON and legacy web imports, ID-collision rejection, relationship/history preservation, appearance/order/integration/alert/sync settings, temporary isolated demonstration workspace. Tokens are never exported. |
| Ecosystem setup | Actual configured services listed per project; export of real relay IDs/endpoints/criteria/timing. No guessed endpoints or automatic claims that the other apps are connected. |

These are source implementations with distinct verification levels, not a claim of App Store readiness. [Validation results](docs/VALIDATION.md) distinguish actual builds/tests from Apple-account or physical-device gates.

## Integration setup and limits

- [Remote synchronization, GitHub, and ecosystem checks](docs/REMOTE_SYNCHRONIZATION.md): API authentication, merge/conflict behavior, real connection configuration, data freshness, and secret handling.
- [Supported Codex integration](integrations/codex/README.md): controlling-client setup, official protocol references, authentication, exact supported events, outbox recovery, and unsupported desktop/cloud-session access.
- [Apple configuration](docs/APPLE_CONFIGURATION.md): signing, CloudKit schema/container/account authorization, Watch pairing, APNs provider/device registration and production/sandbox setup.
- [Relay deployment](monitoring-relay/README.md): independent continuous checks, signed events, TLS/private storage, service supervision, optional APNs dependencies, and routes.

Public GitHub repositories can be fetched without a token within public API limits. Private repositories require user-supplied fine-grained Metadata/Contents/Pull requests/Actions **read** access. The chat's GitHub connection is not embedded in the phone app. The Codex adapter uses the owning CLI client's supported authentication; no OpenAI token is copied to the app or relay. There is no general supported API here to monitor arbitrary existing Codex desktop/cloud sessions.

Remote workspace and APNs routes require distinct private owner credentials. Deploy the relay behind HTTPS and protect its database/storage. The Python core uses the standard library; optional APNs sends require the free packages in `monitoring-relay/requirements-push.txt`. No backend is deployed by this change. Continuous monitoring runs outside the phone, and foreground sync is not a promise of reliable unrestricted background execution.

## Data preservation

The web app still reads `projectHQv1` and retains its original nine starter projects, including Games, Jarvis, and Automation Infrastructure. Native import accepts its JSON export. Previous manual percentages are retained as history; weighted completion comes from imported tasks, with no invented historical completion dates.

Native imports are additive and reject project or child-record ID collisions. Synchronization is a separate, explicit workflow: it merges by UUID, preserves conflicts, detects local edits during network requests, and writes a protected local safety backup before reconciliation. Same-named projects on different devices are not silently merged. A database-open failure shows retry/error rather than deleting stored data. Preserve/export a backup and validate upgrades on signed devices before distributing to real users.

## Structure

```text
index.html, manifest.webmanifest, icon.svg   Original web app, unchanged
ci/smoke.mjs                                Original smoke test, unchanged
ci/verify-ios.sh                            Watch/iPhone/widgets builds + Simulator tests
ci/capture-ios-previews.sh                  Optional bounded actual-app screenshots
ios/HeadQuarter/
  HeadQuarter.xcodeproj/                    Shared iPhone/widget/Watch/test schemes
  HeadQuarter/Models/                      SwiftData graph and shared local container
  HeadQuarter/Services/                    Store, GitHub cache, sync, CloudKit, Watch, push, alerts, backups
  HeadQuarter/Views/                       Native app navigation and settings
  HeadQuarter/Intents/                     Siri/Shortcuts actions
  HeadQuarterWidgets/                     WidgetKit and Live Activity layouts
  HeadQuarterWatch/                       watchOS companion
  Shared/                                 Domain, providers, merge/backup codecs, Watch payload
  HeadQuarterTests/                        Portable and Apple-only tests
  Package.swift                           Same production core sources, no Swift package dependencies
  tools/generate_project.py               Reproducible Xcode project generator
monitoring-relay/                          Optional private monitoring/sync/APNs service
integrations/codex/                        Supported Codex protocol adapter and configuration guide
```

## Automated checks

```sh
node ci/smoke.mjs
swift test --package-path ios/HeadQuarter
python3 -m unittest discover -s monitoring-relay/tests -v
# Explicit live public GitHub read (three API calls):
HQ_RUN_GITHUB_LIVE=1 swift test --package-path ios/HeadQuarter --filter GitHubRepositoryTests.testLivePublicRepositoryWhenExplicitlyEnabled
# On a Mac with iOS/watchOS SDKs:
bash ci/verify-ios.sh
bash ci/capture-ios-previews.sh
```

APNs signing tests use optional installed dependencies and a mocked HTTP/2 Apple transport; they never send a test fixture to a real device. Codex wire tests use real loopback TLS/HMAC/CAS against the relay with explicitly labeled notification fixtures; they are not an authenticated live Codex session. Set `HQ_SIMULATOR_UDID` to select a device and `HQ_RESULTS_DIR` for DerivedData. CI explicitly boots Simulator, disables parallel test clones, and bounds boot/test/preview timeouts. Watch builds do not prove physical pairing.

## Remaining release gates

- Configure and verify an actual Codex client/thread → deployed relay → signed iPhone connection. Unsupported arbitrary desktop/cloud-session monitoring remains unavailable.
- Configure private relay credentials, endpoints, supervision, and storage; verify signed multi-device remote sync against that deployment. Loopback and in-memory tests are not a production deployment.
- Verify CloudKit two-device/account-change/offline/conflict behavior with the owner's provisioned container and iCloud account.
- Verify Watch pairing, delivery/reconnects, queued acknowledgements, and accessibility on signed paired devices. Watch complications/Smart Stack widgets are not implemented.
- Verify APNs registration and actual Apple delivery using the owner's team/key/topic and a physical device. ActivityKit push updates and silent/background workspace sync are not implemented.
- Validate Siri/Shortcuts/Spotlight and notifications/widget/Live Activity UI on devices. Xcode 16.4 emitted a nonfatal `Unable to parse extract.actionsdata` training diagnostic in the first expanded run while also generating all six app shortcut phrase archives; this is recorded for acceptance rather than hidden.
- GitHub OAuth/write operations, issue-to-task or PR-to-task automation, direct GitHub webhook verification, CloudKit sharing/subscriptions, record-level large-workspace sync, and multi-tenant relay accounts remain incomplete.
