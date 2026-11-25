# Head Quarter development workflow

These instructions apply throughout this repository. The owner authorizes automatic development signing, provisioning, installation, launch verification, commit, and push as part of future application development tasks. Follow any more specific instructions supplied by the owner for the current task.

## Required completion workflow

For tasks that change application source code, UI, assets, or functionality, complete the following sequence autonomously.

1. Implement the requested changes in the existing application. Preserve its functionality, integrations, and user data.
2. Run compilation and validation checks relevant to the changes. Reuse the existing checks documented in README.md, including portable Swift tests, app-hosted tests, and unsigned Simulator builds when applicable. Diagnose and fix application build or test failures before deployment. Record environment failures accurately. Incomplete Simulator QA alone does not prevent a development installation when the signed device build and relevant available checks pass.
3. Execute `python3 ci/deploy-iphone.py` from the repository root. This existing script builds and signs a Debug version with Xcode automatic provisioning, including embedded targets, then installs and launches it. Its build step satisfies the signed build requirement. Use the existing Apple Developer membership and signing setup.
4. Install the update over the existing Head Quarter application on the owner's iPhone, preserving its data. Keep the existing bundle identifier `com.headquarter.app`, widget and Watch identifiers, App Group, and signing identity continuity. Never uninstall the application, reset or delete its data, change its bundle identifier, or revoke signing certificates to make deployment succeed.
5. Verify successful launch using the script's launch result and process survival check after 15 seconds. Review build, installation, and launch evidence under `ios/HeadQuarter/DerivedData/physical-deployment`. Investigate failures and report the scope of verification accurately. Process survival alone does not establish visual or functional acceptance.
6. Review the exact changes and validation results, stage only files belonging to the task, check for credentials and secrets, then commit and push to the existing development branch. Preserve unrelated working changes. The current native development branch is `codex/native-head-quarter`. Confirm the branch before committing. Use the connected GitHub integration if local Git authentication is unavailable, and verify the published files and branch head.
7. Report the commit and branch, relevant checks, deployment outcome, and whether this exact update is installed and launched on the owner's iPhone. Include any remaining gaps.

## Device connection and deployment failures

Prefer the owner's already paired iPhone over an available wireless connection. Use CoreDevice discovery with `xcrun devicectl list devices` and let Xcode/CoreDevice use its available transport. Use USB as the fallback when wireless deployment is unavailable. Do not force the owner to reconnect USB when wireless deployment works. Select the owner's phone with `HQ_DEVICE_UDID` when discovery finds multiple iPhones. Deployment configuration overrides are documented in README.md.

Keep build and deployment jobs on this Mac sequential. Inspect existing jobs before starting another deployment. Do not start duplicate installs or launch jobs while an earlier attempt remains active.

If the iPhone is unavailable, locked, disconnected, or waiting for trust, complete all independent implementation and validation work, preserve the changes in a commit, and push the completed work. Clearly report deployment as pending and identify the required connection or user action. Resume installation when the phone becomes available. A commit or successful build must never be reported as proof that an update is installed.

If compilation or relevant application tests fail, fix the failure before attempting installation. Never install a known broken build. If a failure cannot be resolved within the authorized task, preserve the work, report the failure and pending deployment, and avoid claiming the task is fully verified.

## Scope and publication

Documentation-only changes do not trigger app builds, signing, or deployment. Commit and push documentation updates when requested.

Keep credentials, private keys, certificates, provisioning profiles, device inventories, generated build products, and deployment logs out of commits. Apple team and bundle identifiers are configuration identifiers. Store signing secrets through the existing Xcode and Keychain mechanisms.

This workflow authorizes development updates and branch pushes. Merging into main, TestFlight uploads, releases, and production-service changes require the owner's separate authorization.
