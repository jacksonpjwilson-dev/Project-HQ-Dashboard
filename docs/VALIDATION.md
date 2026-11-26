# Head Quarter validation

This is a chronological validation record. The **Continued development** section supersedes the earlier startup-stall and pending-test notes. Earlier counts describe earlier commits, not the current suite.

## Approved icon and opening animation installed on 2026-11-25

The supplied portrait artwork is preserved byte-for-byte at `assets/approved/HeadQuarter-original.png`. Its opaque 1024 × 1024 app icon preserves the full composition and aspect ratio, with the dark edge background extended to the square corners. The supplied MP4 is bundled unchanged at `HeadQuarter/Resources/Opening.mp4`, with a 720 × 1280 video track and a 3.041667-second duration. Its SHA-256 is `265a7fb1785b972a25379c5bb2ce1d056742bf35e4f1281c44b76f520c42ec7a`.

A first-frame native launch storyboard matches the playback poster. An aspect-fit player preserves the entire video over a matching background derived from its first frame. The opening overlay runs once per app process, fades out at playback completion, and falls through on missing media, decoder failure, or a first-frame startup timeout. Background returns retain the dismissed state. Existing interface, navigation, widgets, persistence, and integrations are preserved.

Validation completed on 2026-11-25 and 2026-11-26.

- Signed Debug compilation and the existing `python3 ci/deploy-iphone.py` installation workflow passed on the iPhone 16 Plus with `com.headquarter.app` and the existing signing team. The final deployment's launched process remained alive after 15 seconds.
- The final signed bundle contains the exact MP4, compiled launch storyboard, and new AppIcon metadata. The decoded compiled icon was visually inspected. Icon dimensions, opacity, asset JSON, property list, resource membership, and deterministic project regeneration checks passed.
- Physical screenshots show the supplied opening animation and the subsequent existing Overview interface. A background/foreground check on 2026-11-26 retained process 33948 and opened the Tasks deep link without replaying the opening animation.
- Physical screen recording is unsupported on this device. CoreDevice returned error 1001 for `com.apple.coredevice.feature.screenrecording`. Screenshots provide visual evidence, while frame-perfect timing and flash-free transitions require direct visual acceptance.
- The Simulator app and test bundle compiled, but Simulator data migration failed and XCTest stalled before reporting any cases. That invocation was interrupted. No Simulator test pass is claimed for this revision.
- AGENTS.md already requires validation, automatic physical deployment after application changes, launch verification, commit, push, and explicit pending-deployment reporting.

Local screenshots and logs are under `ios/HeadQuarter/DerivedData/artwork-validation` and remain excluded from Git.

## Physical development installation on 2026-11-25

Local process execution recovered. Xcode 27.2 built the signed Debug iPhone app, embedded widget extension, and Watch companion using existing Apple Developer team `7HL7Y5SP24`. Initial app and widget profiles had empty App Group lists. Selecting the existing team in each target's Signing & Capabilities editor refreshed provisioning for `group.com.headquarter.app`. Application source and entitlements were preserved.

The USB-connected iPhone 16 Plus, “Bluetoof Device (2)”, paired successfully. Head Quarter `com.headquarter.app` installed and launched in the foreground. The reusable `python3 ci/deploy-iphone.py` command then passed the same build/install/launch workflow end to end. Its launched process, PID 27150, remained present after 15 seconds. This establishes successful installation and an initial process survival check. Visual UI acceptance, sustained runtime behavior, and integration acceptance remain for evaluation on the phone.

Logs and device command JSON results are under `ios/HeadQuarter/DerivedData/physical-deployment`. No simulator QA was required for this development installation.

Implementation branch: `codex/native-head-quarter`.
Existing base: `659b57aecd80a02c3b61bc38632c663079d21325`.

This workspace is Debian Linux. Xcode, the iOS SDK, Simulator, and watchOS are not installed. A Swift 6.0.3 Linux toolchain was installed temporarily outside the repository to compile and execute the exact portable production sources, not a translated test model. The native app and core relay use no third-party runtime packages; optional APNs provider delivery requires the documented HTTP/2 and JWT packages.

Local results on 2026-11-11:

| Check | Actual result |
| --- | --- |
| Swift package build + XCTest on Linux, Swift 6.0.3 | PASS: 53 tests, 0 failures |
| Relay Python unittest suite, including real loopback HTTP | PASS: 13 tests, 0 failures |
| Existing web smoke plus new JSON assets | PASS: 7 checks, 0 failures |
| All native Swift source syntax (`swiftc -frontend -parse`) | PASS |
| Independent OpenStep project parser | PASS: 100 objects, valid object references and existing file references |
| Plist/entitlement/privacy manifest/scheme/JSON/icon validation | PASS |
| Deterministic project regeneration | PASS: byte-identical project.pbxproj |
| Original web app/assets/smoke-test CI vs existing base | PASS: unchanged |
| Local Apple build and iOS Simulator tests | UNAVAILABLE: Linux host has no Xcode |

The eight SwiftData/integration tests are intentionally conditional and were not counted as executed in the Linux suite. They run through the Xcode app test target, alongside the same 53 shared tests. Interactive device and Simulator UI checks have not been performed. The Mac verification script exits 127 here with: `xcodebuild is unavailable. Install Xcode on macOS and select it with xcode-select.` Consequently no local Apple build or Simulator execution is claimed. Draft PR #1 starts the native workflow on a GitHub macOS runner; its result is recorded below when available.


## First native validation

[GitHub Actions run 43065555537](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/actions/runs/43065555537), commit `48a72e91104b667e21cb36a1338d853ff39924aa`, used Xcode **16.4 (16F6)** on macOS 15, with an **iPhone 16 Pro / iOS 18.5** Simulator:

- HeadQuarter iPhone Simulator build: **BUILD SUCCEEDED**.
- HeadQuarterWidgets separate Simulator build: **BUILD SUCCEEDED**.
- HeadQuarter Simulator XCTest: **59 tests, 0 failures; TEST SUCCEEDED** (53 shared tests plus six persistence/integration tests).
- Portable Swift suite on macOS: **53 tests, 0 failures**.
- Python relay suite on macOS: **13 tests, 0 failures**.

The final source revision adds child-record collision and attention-filter persistence tests, per-component widget expiry tests, and real light/dark Simulator screenshot capture. Those results are recorded below when available. Warnings in the initial test build concern Xcode's pre-signed XCTest binaries being left unstripped; no source compilation errors occurred.


## Final source revision

Source commit: `9cf6a9b0ad423c8b18bb006bcb9af1f22c8d0bb8`.

- Linux Swift 6.0.3: **57 shared tests, 0 failures** on 2026-11-12.
- Existing web CI: **PASS**, run `43196364770`; the original web source, icon, manifest, smoke test, and CI workflow remain byte-for-byte unchanged.
- Final-source native compilation: run [43196364843](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/actions/runs/43196364843) passed both app and widget builds. It was superseded after Simulator test startup stalled before any test output; it does **not** establish a completed final Simulator suite.
- Bounded-startup verification: see the [latest native workflow run for this branch](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/actions/workflows/native-ios.yml?query=branch%3Acodex%2Fnative-head-quarter). The app source is unchanged from `9cf6a9b`; verification now explicitly boots Simulator, disables parallel clones, and bounds startup/test timeouts. Screenshot capture is a separate optional step with a three-minute timeout. PR updates can supersede pending runs; use the workflow page rather than an old queued run ID.

The final Xcode test target contains those 57 shared tests plus eight Apple-only persistence/integration tests (65 total). At the last verification check, the bounded-startup retry was queued without an assigned runner. The final source's **app and widget builds have passed**, but a complete run of all 65 Simulator tests has **not** been observed. Earlier intermediate runs superseded by source fixes do not establish that final runtime result. The workflow page is the source of truth for any result posted after handoff.

No Simulator screenshots were produced for the final revision during this session. Optional preview capture is bounded separately from required build/test validation and uses real Simulator output only. Widget appearance, Dynamic Island/Live Activities, notification delivery/actions, Shortcuts UI navigation, accessibility, and end-to-end editing still require interactive acceptance on a Simulator or signed device.


## Continued development: integrations and Apple companion

The previously pending baseline is now resolved: [run 43200387985](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/actions/runs/43200387985), commit `00270ea`, passed both builds and **65 iPhone Simulator tests, zero failures**, and produced actual light/dark app screenshots. Explicit Simulator boot and disabled parallel clones addressed the observed launch stall.

The first expanded integration revision, `4143ebf`, passed [run 43293353320](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/actions/runs/43293353320):

- watchOS companion Simulator build: BUILD SUCCEEDED.
- iPhone and WidgetKit builds: BUILD SUCCEEDED.
- iPhone Simulator XCTest: **80 test cases, one explicitly skipped live-network test, zero failures; TEST SUCCEEDED**.
- Portable Swift suite on macOS: **68 test cases, one explicit live-network skip, zero failures**.
- Relay suite on macOS: passed. Later extended TLS/signing/feed tests are recorded separately below.

Local follow-up verification on 2026-11-12:

- Portable Swift suite: **77 test cases, one explicit live-network skip, zero failures**.
- Explicitly opted-in production GitHub client read of `jacksonpjwilson-dev/Project-HQ-Dashboard`: **one test passed**, with actual commits, PR #1, and workflow data. The Linux FoundationNetworking per-request session teardown issue observed in an initial attempt was corrected with a persistent ephemeral session whose headers remain request-scoped; no cookies or stored credentials are shared.
- Python relay/Codex/push/feed suite: **41 tests, zero failures** in the final local rerun. Real loopback TLS/HMAC/CAS is exercised with labeled Codex fixtures. APNs ES256 signing uses a generated test key and a mocked HTTP/2 Apple transport.
- Installed Codex CLI `0.167.0-alpha.4` generated its actual app-server JSON schemas successfully; the required fields for the three supported notification types were checked and captured in `integrations/codex/protocol-contract.json`. No authenticated live Codex thread was connected.

Final source revision `9d25d31db707eada9f352d3ef7e7b9c036dbd1b3` passed [native run 43299073398](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/actions/runs/43299073398) on 2026-11-12:

- Watch, iPhone, and WidgetKit builds: **BUILD SUCCEEDED** for all three.
- iPhone Simulator XCTest: **89 cases, one explicitly skipped live-network test, zero failures; TEST SUCCEEDED**.
- Portable Swift on macOS: **77 cases, one explicit live-network skip, zero failures**.
- Python relay/Codex/push/feed tests with optional APNs signing dependencies installed: **41 tests, zero failures, no skips**.
- Actual Simulator preview capture and upload: succeeded; artifact `head-quarter-simulator-previews`, ID `13979974827` (14-day retention).
- Original web CI: **PASS**, [run 43299073518](https://github.com/jacksonpjwilson-dev/Project-HQ-Dashboard/actions/runs/43299073518). Original web files and workflow remain unchanged against the repository base.
- Final local property-list, entitlement, privacy manifest, scheme, and integration JSON validation: **13 files passed**; original smoke plus integration JSON checks: **eight checks, zero failures**.

This final run includes the account/endpoint guards, Watch payload budget, feed freshness additions, and extra regression tests. The one network test is deliberately opt-in; its real production GitHub read passed separately as recorded above. A real iCloud account, paired Watch, APNs delivery, arbitrary Codex desktop/cloud-session access, and production relay deployment are **not** established by these tests.

### Nonfatal App Intents SDK diagnostic

Xcode 16.4's `appintentsnltrainingprocessor` reported `Unable to parse extract.actionsdata` while processing dependency metadata in both expanded iPhone builds, including the final source validation. It continued to train all six Head Quarter phrases, generated/copied their SSU YAML, archived the en locale, and returned a successful build. This diagnostic is not hidden or treated as successful Siri/Spotlight device acceptance. The owner must verify those interfaces on a signed device; SDK-specific metadata behavior remains an open acceptance item.
