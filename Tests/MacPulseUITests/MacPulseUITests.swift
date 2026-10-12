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
            XCTAssertTrue(app.staticTexts[page].firstMatch.waitForExistence(timeout: 5), "Missing page heading: " + page)
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.name = "Dashboard-" + page; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testDemoAndMonitoringSettingsAreInteractive() {
        app.buttons["nav-Settings"].click()
        let demo = app.checkBoxes["Demonstration mode"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        let tracking = app.checkBoxes["Record application activity"]
        XCTAssertFalse(tracking.isEnabled)
        demo.click()
        XCTAssertTrue(tracking.isEnabled)
        tracking.click()
        app.buttons["nav-Overview"].click()
        XCTAssertTrue(app.staticTexts["Right now"].waitForExistence(timeout: 5))
        app.buttons["nav-Settings"].click(); demo.click()
        XCTAssertFalse(tracking.isEnabled)
    }
}
#endif
