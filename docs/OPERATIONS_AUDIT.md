# Operations dashboard implementation and integration audit

The approved reference and complete implementation brief are preserved under `assets/operations-reference`. The native implementation uses the existing application, signing identity, SwiftData workspace, settings, task workflows, launch animation, widgets and Watch target.

## Interface and graph implementation

The compact Overview summarizes registered systems, tracked workspace work, recorded incidents and public-feed coverage. Systems uses the approved navy glass list with exact square icons from the current native repositories. The mountain image comes from the existing Logbook arctic-mountain asset and is subdued under the HQ navy background. The app icon and opening video are unchanged.

The seven systems open a shared operations layout with distinct backgrounds, surfaces, text contrast and accents. Daily Briefing uses blue/white glass and waves. Logbook uses graphite and silver, Stack champagne/gold, Crew cream and restrained colour, Stocked cool steel, and YKF navy/radar-blue. Systems and operations support Dynamic Type through native typography and scrolling. Graph labels have accessibility descriptions and an expanded scrollable map; Reduce Motion disables transition/pulse effects.

`Shared/ecosystem.json` describes the inspected nodes, directed connections, owners, source files, setup requirements and downstream impact. Runtime/data and development flows are separate. A tap on a node or connection opens its inspector. The Map section also lists connections with readable direction and responsibility. The ecosystem map browser switches between the same registry-backed app maps.

Health observations are independent of the expected graph. Missing means an HQ evidence binding is unconfigured, rather than a claim that another app lacks permission or is offline. Unknown covers absent, failed-to-fetch, stale or future-dated evidence. Healthy, degraded, failed, missing, unknown and disabled have distinct labels and symbols. An active check indicator is shown only for an actual in-progress refresh.

An inspector can bind an existing workspace monitor or add a monitor through the existing service editor. Existing HTTPS criteria, GitHub repository activity and relay evidence providers remain in use, with credentials in Keychain. A bound monitor must measure the exact node or operation. Pausing a dashboard binding excludes it from this dashboard's refreshes; independent workspace monitoring remains separately configured.

Original project names and UUIDs are preserved. Aliases map Pantry to Stocked, YKF Arrivals to YKF Tracker, and Head Quarter to Headquarters. Deleting a workspace does not silently recreate it. Existing project/task/service management remains available through Manage and Config, with settings and history retained.

## Verified source inspection

These are source revisions inspected locally. Repository presence establishes source availability, rather than deployment or runtime health.

| Native repository | Revision | Inspected implementation |
| --- | --- | --- |
| logbook-v2 | `b1cca5e` | `native-ios/Sources/Logbook/LogbookStore.swift`, food catalogue, reminders, WatchBridge, SharedStateFile, workout activity and native README |
| daily-briefing-launch | `a45b68e` | CalendarService, DataProviders, DeliveryServices, RefreshCoordinator, preferences and shared snapshots |
| stack-launch | `9d83d39` | Native CSV/ledger/sync interfaces and optional backend job documentation |
| pantry | `5f50871` | PantryStore, FirebaseSetup, legacy Logbook adapter, TelemetryAdapter, widget snapshots |
| crew-map | `d76a40d` | PublicGitHubSource, StaticFlow, AuthorizedOperations, HeadquartersAdapter and roster/activity schemas |
| ykf-tracker | `eeea992` | BackendClient, snapshot freshness, Python feed/tracker modules, notification implementation and build report |

## Genuinely collected information

| Source | What HQ reads | Boundary |
| --- | --- | --- |
| Crew public roster | Version-2 schema, declared agent identities, roles and reporting hierarchy | Reachability is measurable. There is no roster generation timestamp or authorized agent execution stream. |
| Crew public activity | Original Toronto publication time and dated reported interactions | These are published reports with unverified execution outcomes. Publication age is not a heartbeat. |
| YKF public live.json | Original publication time, active/off-shift flag, provider status and snapshot schema | A stale publication stays unknown even after a new HTTP 200. HQ does not infer aircraft positions or scheduled-job liveness. |
| Current HQ process | Refresh execution in this running process | This does not establish another app's runtime or a continuous background service. |
| HQ SwiftData | A real project query against the existing local container | Readability does not establish cloud sync or successful future writes. |
| HQ shared snapshot | Presence, decoding and freshness of the real App Group snapshot | A shared read does not establish extension rendering or Watch delivery. |
| HQ notification setup | Existing alert preference and read-only iOS authorization state | Disabled preferences, denied permission and unrequested permission are distinguished. Delivery is unverified. |
| HQ Watch setup | Read-only pairing state through the existing WatchConnectivity session | Pairing alone does not verify snapshots or acknowledgements. |
| Existing configured workspace services | HTTPS, manual, GitHub or relay evidence explicitly bound to a graph item | Source, age and expiry remain visible. Development evidence cannot certify runtime availability. |

Public endpoints are taken directly from the sibling source code.

- `https://raw.githubusercontent.com/jacksonpjwilson-dev/crew-map/data/roster.json`
- `https://raw.githubusercontent.com/jacksonpjwilson-dev/crew-map/data/activity.json`
- `https://raw.githubusercontent.com/jacksonpjwilson-dev/ykf-tracker/data/live.json`

Read-only checks on 2026-11-26 returned HTTP 200 for all three. Crew activity was dated 2026-11-19 and the YKF snapshot was dated 2026-11-12. Both are stale under their configured freshness windows. No healthy runtime claim follows.

The local evidence cache uses atomic protected storage, retains original observation and activity times, limits history, and deduplicates published activities and equivalent check outcomes. Failed reads preserve history and report unknown connection evidence. Refreshes run on launch, by explicit request, and on the existing foreground-check cadence. There is no new always-on background polling service.

## Remaining setup and changes in sibling repositories

No sibling application or production service was modified.

| System | Existing capability | Required for operational confirmation in HQ |
| --- | --- | --- |
| Daily Briefing | EventKit calendar/reminders, gated WeatherKit/location, aviationweather.gov METAR/TAF, email provider boundary (currently disconnected), configurable AI summary backend, local snapshots/delivery | Publish health-only per-stage results with original timestamps, stable IDs, permission/configuration outcomes and sanitized failures. Calendar authorization must be granted inside Daily Briefing. Direct Gmail OAuth and consumer Grok execution logs were not established. FlightBridge and native Logbook habit reporting need an actual supported adapter before adding live flows. |
| Logbook | Manual training/nutrition/recovery, food catalogue, local persistence, widgets, Watch and Live Activities | Add an explicitly authorized health-only report path for persistence, catalogue, snapshots and delivery. HealthKit is intentionally disabled under the owner's current policy and is not offered as an enable action. A native cross-app habit contract is not established. |
| Stack | Manual/CSV accounting, provider protocol and optional read-only Plaid ingestion foundation | Deploy and authorize the actual account bridge, then report import/sync cursor outcomes without financial records. BMO automation and provider production readiness are unverified. No bank access was configured. |
| Stocked | Local inventory, optional Firebase/authenticated sync, legacy Logbook v2 import, widgets and TelemetryAdapter | Configure the authorized registered Firebase client/account in Stocked if desired. Authorize/version the native Logbook import contract. Adapt the health-only report to the existing HQ relay ingestion contract, provision the private endpoint and keep the device token local. |
| Crew | Public roster/activity, declared static flow metadata, outbound HeadquartersAdapter and AuthorizedOperations protocol | Provide authorized task, approval, failure and automation event APIs. Static bot relationships are declarations. The public roster cannot establish running jobs. Adapt the existing health-only report to the relay contract and configure its approved host/token in Crew. |
| YKF Tracker | Real feed/tracker code, publication, snapshot/cache, alert and companion code | Emit tracker-job heartbeat, attempts, last successes, upstream provider failures and delivery results through a private health-only adapter. The public publication omits richer operational host state and does not verify current cron or alert delivery. |
| Headquarters | Existing relay, workspace sync, CloudKit transport, notification preferences, APNs and Watch support | Provision and authorize the private relay/CloudKit/APNs connections only when desired. Bind graph items to exact service UUIDs. GitHub Connect creates a development monitor; private repositories need user-provided read-only credentials through the existing editor. |

The existing relay uses signed event ingestion and authenticated evidence reads, documented in `monitoring-relay/README.md`. Crew and Stocked report bodies/authentication are not automatically equivalent to that contract. A server adapter or an explicitly versioned client mapping must validate scope, map each connection ID to the exported project/service UUIDs, retain producer times, deduplicate event IDs and sanitize failures. No credentials or private application records should be put into the registry or public GitHub feeds.

## Verification record

Verified locally on 2026-11-28 with Xcode 27.2 (27B52):

- Portable Swift suite: 89 executed, 88 passed, one opt-in live GitHub test skipped, zero failures.
- App-hosted unit suite: 104 executed, 103 passed, one opt-in live GitHub test skipped, zero failures. Includes persistence, binding, alias/deep-link and runtime/development separation checks.
- Unsigned arm64 Simulator compilation: iPhone app, embedded widgets/Live Activities/App Intents, and Watch target succeeded. Subsequent UI runs rebuilt the final app successfully.
- UI suite: all three tests have passing results. The initial run passed legacy Settings/Activity and exposed a navigation test issue and inadequate connection hit targets. The targeted retry passed all seven app themes, back-navigation restoration, node/connection inspection and Config. A final affected-screen run passed after correcting light-theme control contrast, and captured the compact Overview.
- Simulator used: existing iPhone 18 Pro, 402 × 874 points. Standard iPhone 16 and accessibility-size visual acceptance remain additional coverage, rather than claimed passes. No simulator was erased or reset.
- Final signed Debug deployment via `python3 ci/deploy-iphone.py`: iPhone application plus embedded widget and Watch products built, installed in place on the owner's iPhone 16 Plus over the paired local-network transport, and launched. The final PID survived the required 15-second process check. Deep signature verification passed. No uninstall, bundle-identifier change or user-data reset occurred.
- Physical iPhone deep-link check: `headquarter://system/briefing` reached the visible blue/white Daily Briefing operations screen; `device-briefing.png` captured the installed build. The Systems route also succeeded and `device-systems.png` captured the visible navy Systems screen.
- Existing app icon, offline opening video and native launch-screen sources are unchanged. User workspace migrations and private integrations were not rewritten.

Evidence is local under `ios/HeadQuarter/DerivedData/operations-validation`: `final-checks.log`, `ui-tests.xcresult`, `ui-retry.xcresult`, `ui-final.xcresult`, `screenshots/`, `final-screenshots/`, and `device-deploy-final.log`. Final signing/installation/process records are under `DerivedData/physical-deployment`. Screenshots and logs are excluded from Git because existing workspace content or device details may be visible.

Screen review identified and corrected overlapping graph cards, small connection targets and inherited dark styling on light-theme controls. The compact Overview fits the tested default screen. Detail maps scroll and expand; the ecosystem browser filters app maps rather than displaying an unrestricted global graph. VoiceOver walkthrough, large accessibility sizes, offline-on-device behaviour, notification delivery, widget rendering, Live Activity delivery, paired Watch exchange and authenticated private integrations still need dedicated acceptance testing. Process survival does not establish functional or external-integration acceptance.

## Repeatable checks

Run jobs sequentially from the repository root. Use an available simulator UUID from `xcrun simctl list devices available`; preserve existing simulator data.

```sh
(cd ios/HeadQuarter && swift test)
python3 ios/HeadQuarter/tools/generate_project.py
xcodebuild -project ios/HeadQuarter/HeadQuarter.xcodeproj -scheme HeadQuarter \
  -destination "platform=iOS Simulator,id=$HQ_SIMULATOR_UDID" \
  -derivedDataPath ios/HeadQuarter/DerivedData -parallel-testing-enabled NO \
  -only-testing:HeadQuarterTests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ios/HeadQuarter/HeadQuarter.xcodeproj -scheme HeadQuarter \
  -destination "platform=iOS Simulator,id=$HQ_SIMULATOR_UDID" \
  -derivedDataPath ios/HeadQuarter/DerivedData -parallel-testing-enabled NO \
  -only-testing:HeadQuarterUITests -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 360 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test
python3 ci/deploy-iphone.py
```

The UI tests launch the real app without replacing workspace data, exercise the seven themed dashboards, node/connection inspectors, existing settings and activity, and retain screenshot attachments. The deployment script builds the phone app and embedded widget/Watch targets with the existing automatic signing setup, installs in place and checks process survival after 15 seconds. Screenshots establish visual evidence only for the captured state; they do not establish remote integrations or delivery acceptance.
