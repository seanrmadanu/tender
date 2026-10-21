import XCTest

final class TenderUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Add expense"].waitForExistence(timeout: 15))
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNavigationShoppingAndReports() {
        capture("Overview")
        app.buttons["Open shopping mode"].tap()
        XCTAssertTrue(app.navigationBars["Shopping Mode"].waitForExistence(timeout: 5))
        app.textFields["Purchase amount in US dollars"].tap()
        app.textFields["Purchase amount in US dollars"].typeText("25.00")
        app.buttons["Category, Choose an envelope"].tap()
        app.collectionViews.buttons["Groceries"].tap()
        XCTAssertTrue(app.staticTexts["Within your recorded budget"].waitForExistence(timeout: 5))
        capture("Shopping Mode")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].exists)
        capture("Budgets")
        app.tabBars.buttons["Reports"].tap()
        XCTAssertTrue(app.staticTexts["TOTAL SPENT"].waitForExistence(timeout: 5))
        capture("Reports")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Where it went"].waitForExistence(timeout: 5))
        capture("Heatmap")
    }
    func testExpensePersistsAfterRelaunch() {
        app.buttons["Add expense"].tap()
        app.textFields["Merchant or description"].tap()
        app.textFields["Merchant or description"].typeText("QA Coffee")
        app.textFields["Amount (USD)"].tap()
        app.textFields["Amount (USD)"].typeText("12.34")
        app.buttons["Category, Choose"].tap()
        app.buttons["Food & coffee"].tap()
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Add expense"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--preserve-test-ledger"]
        app.launch()
        XCTAssertTrue(app.staticTexts["$2,950.16"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "QA Coffee").firstMatch.waitForExistence(timeout: 5))
        capture("Saved Expense")
    }
    func testGroceryObservation() {
        app.tabBars.buttons["Groceries"].tap()
        capture("Groceries")
        app.buttons["Add grocery item"].tap()
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText("QA Apples")
        app.navigationBars.buttons["Add"].tap()
        app.swipeUp()
        app.buttons.containing(.staticText, identifier: "QA Apples").firstMatch.tap()
        XCTAssertTrue(app.textFields["Store"].waitForExistence(timeout: 5))
        app.textFields["Store"].tap()
        app.textFields["Store"].typeText("Test Market")
        app.textFields["Price per each (USD)"].tap()
        app.textFields["Price per each (USD)"].typeText("1.49")
        app.buttons["Save Price Observation"].tap()
        XCTAssertTrue(app.staticTexts["Test Market"].waitForExistence(timeout: 5))
        capture("Price History")
    }
}
