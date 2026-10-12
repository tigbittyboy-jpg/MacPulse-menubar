#if os(macOS)
import XCTest

final class MacPulseUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
    override func tearDownWithError() throws { app?.terminate() }
    func testDashboardNavigationAndScreenshots() {
        for page in ["Overview", "Screen Time", "Codex", "Applications", "System", "Sessions", "Insights", "Settings"] {
            let button = app.buttons["nav-" + page]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing navigation: " + page)
            button.click()
            let heading = app.staticTexts["page-heading"]
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", page), object: heading)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed, "Missing page heading: " + page)
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.name = "Dashboard-" + page; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testDemoAndMonitoringSettingsAreInteractive() {
        app.buttons["nav-Settings"].click()
        let demo = app.checkBoxes["setting-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        let tracking = app.checkBoxes["setting-recording"]
        XCTAssertTrue(tracking.waitForExistence(timeout: 5))
        XCTAssertFalse(tracking.isEnabled)
        demo.click()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: tracking)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        tracking.click()
        app.buttons["nav-Overview"].click()
        XCTAssertTrue(app.staticTexts["Right now"].waitForExistence(timeout: 5))
        app.buttons["nav-Settings"].click(); demo.click()
        XCTAssertFalse(tracking.isEnabled)
    }
}
#endif
