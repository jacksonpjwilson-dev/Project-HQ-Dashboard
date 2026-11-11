# Head Quarter validation

Implementation branch: `codex/native-head-quarter`.
Existing base: `659b57aecd80a02c3b61bc38632c663079d21325`.

This workspace is Debian Linux. Xcode, the iOS SDK, Simulator, and watchOS are not installed. A Swift 6.0.3 Linux toolchain was installed temporarily outside the repository to compile and execute the exact portable production sources, not a translated test model. No third-party runtime package is required by the app or relay.

Local validation is in progress; this file is updated with final counts before completion. The Mac verification script exits 127 here with: `xcodebuild is unavailable. Install Xcode on macOS and select it with xcode-select.` Consequently no local Apple build or Simulator execution is claimed. The native workflow can run those checks on a GitHub macOS runner when a pull request is opened.
