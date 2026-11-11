// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "HeadQuarterCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HeadQuarterCore", targets: ["HeadQuarterCore"])],
    targets: [
        .target(name: "HeadQuarterCore", path: ".", exclude: ["HeadQuarterTests", "HeadQuarterWidgets", "HeadQuarter.xcodeproj", "tools", "HeadQuarter/Assets.xcassets", "HeadQuarter/Views", "HeadQuarter/Intents", "HeadQuarter/Models", "HeadQuarter/HeadQuarterApp.swift", "HeadQuarter/Info.plist", "HeadQuarter/HeadQuarter.entitlements", "HeadQuarter/PrivacyInfo.xcprivacy", "HeadQuarter/Services", "Shared/OperationAttributes.swift"], sources: ["Shared/Domain.swift", "Shared/Backup.swift", "Shared/Monitoring.swift"]),
        .testTarget(name: "HeadQuarterCoreTests", dependencies: ["HeadQuarterCore"], path: "HeadQuarterTests")
    ]
)
