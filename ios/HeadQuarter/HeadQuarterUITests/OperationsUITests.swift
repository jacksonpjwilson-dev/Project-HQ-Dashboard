import XCTest

final class OperationsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Systems"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Systems"].tap()
        XCTAssertTrue(app.buttons["system-briefing"].waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        app.activate()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func open(_ id: String) {
        let row = app.buttons["system-" + id]
        app.activate()
        if row.frame.maxY > app.tabBars.firstMatch.frame.minY - 12 { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Map"].waitForExistence(timeout: 15))
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["system-briefing"].waitForExistence(timeout: 5))
    }

    func testAllSevenAppThemesAndRestoration() {
        capture("HQ-Systems")
        for id in ["briefing", "logbook", "stack", "crew", "stocked", "ykf", "hq"] {
            open(id)
            capture("Operations-" + id)
            if id == "logbook" {
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HealthKit, Disabled")).firstMatch.exists)
            }
            back()
        }
        capture("HQ-Systems-Restored")
    }

    func testNodeAndConnectionInspectors() {
        open("briefing")
        capture("Operations-briefing-final")
        let calendar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Apple Calendar,")).firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        calendar.tap()
        XCTAssertTrue(app.navigationBars["Apple Calendar"].waitForExistence(timeout: 5))
        capture("Calendar-Node-Inspector")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Daily Briefing Connections")).firstMatch.exists)
        app.buttons["Done"].tap()

        let connection = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Apple Calendar to Daily Briefing,")).firstMatch
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        connection.tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))
        capture("Calendar-Connection-Inspector")
        app.buttons["Done"].tap()
        app.segmentedControls.buttons["Config"].tap()
        XCTAssertTrue(app.buttons["Connect repository checks"].waitForExistence(timeout: 5))
        capture("Operations-Config")
        back()
        open("stack")
        capture("Operations-stack-final")
        app.tabBars.buttons["Overview"].tap()
        XCTAssertTrue(app.staticTexts["Mission control"].waitForExistence(timeout: 5))
        capture("HQ-Overview")
    }

    func testLegacySettingsAndActivityRemainReachable() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Manage projects and services"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Alerts & setup"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Alerts & setup"].tap()
        capture("HQ-Alerts")
    }
}
