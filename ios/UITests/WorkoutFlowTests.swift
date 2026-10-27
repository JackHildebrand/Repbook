import XCTest

final class WorkoutFlowTests: XCTestCase {
    func testLoggingPersistsAcrossTabsAndRelaunchAndFinishesIntoHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-repbook-ui-testing", "-repbook-reset-test-data"]
        app.launch()
        for name in ["Home", "Routines", "Progress", "History"] { XCTAssertTrue(app.tabBars.buttons[name].exists) }
        app.tabBars.buttons["Routines"].tap()
        app.buttons["Start workout"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Log set"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Log set"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 /")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Minimize workout"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["Resume Upper at current set"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons["Resume Upper at current set"].exists)
        app.terminate()
        app.launchArguments = ["-repbook-ui-testing"]
        app.launch()
        app.buttons["Resume workout"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 /")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Workout controls"].tap()
        app.buttons["Finish workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["History"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Upper"].firstMatch.waitForExistence(timeout: 5))
    }
}
