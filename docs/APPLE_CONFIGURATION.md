# Apple configuration and verification gates

The default app remains a local SwiftData workspace. Its model graph is **not** switched to a different CloudKit-backed SwiftData schema, and existing local data is preserved. Optional CloudKit synchronization uses a private CKAsset workspace document and the same conflict-aware merge/reconciliation engine as relay sync.

## Signing and App Groups

Use Xcode 16.4 or newer. Set your Apple team and owned identifiers on the iPhone app, its WidgetKit extension, and the Watch app. The Watch identifier must be a child of the iPhone identifier; update `WKCompanionAppBundleIdentifier` in the Watch Info.plist to match the phone. Register an App Group and replace `group.com.headquarter.app` in the app/widget entitlements and SharedStorage. Widgets receive snapshots, never API tokens.

The Watch companion uses authenticated system pairing through WatchConnectivity, not a shared cross-device filesystem. Install both apps on a paired iPhone and Watch. Open the phone once to activate its session. The Watch caches its last delivered snapshot and recomputes health expiry using the same component rules. Acknowledgements are queued and shown as queued until the phone's next confirmed snapshot. Neither device claims that a disconnected Watch is receiving live updates.

The Watch source supports project status/progress, open incidents, outstanding tasks, and acknowledgement. Watch complications/Smart Stack widgets are not included in this revision. Paired-device delivery, reconnects, notifications mirrored by watchOS, and accessibility need physical-device acceptance even when the watchOS Simulator build passes.

## Private CloudKit synchronization

1. Create an owned iCloud container, e.g. `iCloud.YOUR_IDENTIFIER`, in the Apple Developer portal and enable CloudKit on the iPhone target.
2. Copy `HeadQuarter/HeadQuarterConfigured.entitlements`, replace the sample container/App Group, and select it in the iPhone target's `CODE_SIGN_ENTITLEMENTS`. The default entitlements remain unchanged so builds do not pretend to own a container. Remove `aps-environment` from a CloudKit-only configuration unless Push Notifications is also provisioned; similarly, remove unused iCloud keys from a push-only configuration.
3. Set `HQCloudKitEnabled` to true in the iPhone Info.plist only for a correctly provisioned build. Enter the matching container ID in Settings → Project & task synchronization → Private iCloud / CloudKit.
4. Sign into iCloud on the device. Create/deploy record type `HQWorkspace` in the private database with `revision` (Int64) and `payload` (Asset). Record name is `head-quarter-workspace-v1` in the default zone. Deploy its schema to Production before distributing production builds.
5. Authorize the current iCloud account explicitly in sync settings, then run Merge and synchronize. The sync base is scoped to the actual iCloud user record; an account change requires new explicit authorization before automatic uploads. The transport reads the private CKAsset, performs a field-level three-way merge, and saves with `ifServerRecordUnchanged`; concurrent CloudKit changes are rejected rather than overwritten. A local safety copy is written before reconciliation.
6. Verify with two signed devices on the **same** iCloud account: independent edits, conflicting edits, offline edits, deletions, iCloud sign-out, storage limits, and simultaneous writers. Never interpret a successful compile as a successful iCloud connection.

Synchronization is manual or foreground polling when explicitly enabled. It is not continuous background execution. CloudKit subscriptions/background sync and multi-user sharing are not implemented. The workspace is a single document; the app enforces a 20 MB backup limit and uses CKAsset for data beyond CKRecord field limits. Larger workspaces should migrate to record-level sync before exceeding that limit.

## APNs remote alerts

1. Enable Push Notifications on the signed iPhone target. Use the configured entitlements template with the correct `aps-environment` (`development` for sandbox, `production` for distribution). Set Info.plist `HQPushEnabled` to true and `HQAPNSEnvironment` to the same environment.
2. On a private HTTPS relay, install optional `monitoring-relay/requirements-push.txt`. Supply distinct `HQ_DEVICE_TOKEN`, `HQ_SYNC_TOKEN` (if using sync), `HQ_READ_TOKEN`, and `HQ_WRITE_SECRET` from a secret manager. Never put tokens or APNs keys in Git or app source.
3. Create an APNs provider signing key in the Apple Developer portal. Configure `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY_PATH`, and `APNS_TOPIC` (the signed iPhone bundle ID) on the server. The `.p8` file must have owner-only permissions. Only the server loads that key.
4. In Settings → Remote push configuration, enter the relay's HTTPS base URL and its device-registration token. Register the phone, allow notifications, and check the actual registration status. The app does not register merely because code is installed; unconfigured capability gates return explicit setup errors.
5. Save notification preferences to upload severity, category preferences, device timezone, and quiet hours. The relay uses that timezone for quiet hours, deduplicates incidents/recovery per device, queues retries for transient APNs failures, expires stale notifications, and removes tokens rejected with HTTP 410.
6. On a signed physical device, exercise outage → repeated outage → escalation → recovery, quiet hours, revoked tokens, denied permission, sandbox/production mismatch, and tapping an alert. Registration with the relay is **not proof of delivery by Apple**. Server delivery state is recorded separately.

Routes are `POST /v1/devices` and `DELETE /v1/devices/{deviceID}`, authenticated using `HQ_DEVICE_TOKEN`. They return unavailable if APNs is not configured. Deployment is single-user; anyone holding this private registration credential has the owner's registration authority, so do not expose it publicly or share it between users. Configure TLS, private database/storage permissions, rate limits, and backups at the deployment layer.

Remote pushes contain monitoring alerts and the project ID. Tapping requests current service evidence from configured providers. They do not mutate local health from an unverified notification body, and remote alerts do not guarantee background data synchronization. ActivityKit push updates and remote Live Activity token registration remain incomplete; bounded local activities still work as before.

## What has and has not been verified

The Apple-specific transports and targets must be compiled in macOS CI. CloudKit account access, signed APNs registration/delivery, and Watch pairing cannot be verified without your Apple team/container/provider credentials and signed paired devices. No successful live connection to these services is claimed by default. See VALIDATION.md for actual build/test results rather than this setup checklist.
