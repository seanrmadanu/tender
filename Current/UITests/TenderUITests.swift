import XCTest

final class TenderUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--sample-ledger"]
        app.launch()
        XCTAssertTrue(app.buttons["Add expense"].waitForExistence(timeout: 15))
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func launchEmptyLedger() {
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Add expense"].waitForExistence(timeout: 10))
    }
    func testFreshLedgerAndMultipleManualAccountsPersist() {
        launchEmptyLedger()
        XCTAssertFalse(app.staticTexts["$2,962.50"].exists)
        XCTAssertTrue(app.buttons["Add your first account"].exists)
        app.buttons["Add your first account"].tap()
        for (name, amount) in [("My Checking", "100.00"), ("My Savings", "200.00")] {
            app.buttons["add-manual-account"].tap()
            let field = app.textFields["Account name"]
            if !field.isHittable { app.swipeUp() }
            field.tap(); field.typeText(name)
            app.textFields["Available balance (USD)"].tap()
            app.textFields["Available balance (USD)"].typeText(amount)
            app.buttons["Add Account"].tap()
        }
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Manage 2 accounts"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--preserve-test-ledger"]
        app.launch()
        XCTAssertTrue(app.buttons["Manage 2 accounts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["$300.00"].firstMatch.exists)
        capture("Personal accounts")
    }
    func testApprovedLegacyResetRunsOnceAndManualPurchaseUsesSelectedAccount() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--legacy-reset-test"]
        app.launch()
        XCTAssertTrue(app.buttons["Add your first account"].waitForExistence(timeout: 10))
        app.buttons["Add your first account"].tap()
        for (name, amount) in [("Chase manual", "100.00"), ("Capital One manual", "200.00")] {
            app.buttons["add-manual-account"].tap()
            app.textFields["Account name"].tap(); app.textFields["Account name"].typeText(name)
            app.textFields["Available balance (USD)"].tap(); app.textFields["Available balance (USD)"].typeText(amount)
            app.buttons["Add Account"].tap()
        }
        app.buttons["account-Capital One manual"].tap()
        app.buttons["Add Purchase"].tap()
        app.textFields["Merchant or description"].tap(); app.textFields["Merchant or description"].typeText("My groceries")
        app.textFields["Amount (USD)"].tap(); app.textFields["Amount (USD)"].typeText("25.00")
        app.buttons["Category, Choose"].tap(); app.collectionViews.buttons["Groceries"].tap()
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Available balance, $175.00"].waitForExistence(timeout: 5))
        capture("Manual account purchase")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--preserve-test-ledger"]
        app.launch()
        XCTAssertTrue(app.buttons["Manage 2 accounts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["$275.00"].firstMatch.exists)
        app.buttons["Manage 2 accounts"].tap()
        app.buttons["account-Chase manual"].tap()
        XCTAssertTrue(app.staticTexts["Available balance, $100.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Purchases (0)"].exists)
    }
    func testGroceryPricesSaveWithoutStoreAndPersist() {
        launchEmptyLedger()
        app.tabBars.buttons["Groceries"].tap()
        app.buttons["Add grocery item"].tap()
        app.textFields["Name"].tap(); app.textFields["Name"].typeText("My Apples")
        app.textFields["Price per unit (USD, optional)"].tap()
        app.textFields["Price per unit (USD, optional)"].typeText("1.49")
        app.navigationBars.buttons["Add"].tap()
        app.buttons.containing(.staticText, identifier: "My Apples").firstMatch.tap()
        XCTAssertTrue(app.textFields["Price per each (USD)"].waitForExistence(timeout: 5))
        app.textFields["Price per each (USD)"].tap()
        app.textFields["Price per each (USD)"].typeText("3.49")
        app.navigationBars.buttons["Save Price"].tap()
        XCTAssertTrue(app.staticTexts["Price saved"].waitForExistence(timeout: 5))
        capture("Saved grocery price without store")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--preserve-test-ledger"]
        app.launch()
        app.tabBars.buttons["Groceries"].tap()
        XCTAssertTrue(app.staticTexts["$2.49"].firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "My Apples").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Store not specified, $1.49"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Store not specified, $3.49"].exists)
    }
    func testOldSampleLedgerCanBeClearedFromSettings() {
        app.buttons["Settings and exports"].tap()
        let review = app.buttons["Remove Sample Data…"]
        for _ in 0..<8 { if review.isHittable { break }; app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.navigationBars["Review Sample Ledger"].waitForExistence(timeout: 5))
        let remove = app.buttons["Remove Unselected Sample Data"]
        for _ in 0..<16 { if remove.isHittable { break }; app.swipeUp() }
        remove.tap()
        app.buttons["Create Personal Ledger"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add your first account"].waitForExistence(timeout: 5))
        capture("Clean personal ledger")
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
        XCTAssertTrue(app.textFields["Store (optional)"].waitForExistence(timeout: 5))
        app.textFields["Store (optional)"].tap()
        app.textFields["Store (optional)"].typeText("Test Market")
        app.textFields["Price per each (USD)"].tap()
        app.textFields["Price per each (USD)"].typeText("1.49")
        app.buttons["Save Price Observation"].tap()
        XCTAssertTrue(app.staticTexts["Test Market"].waitForExistence(timeout: 5))
        capture("Price History")
    }
}
