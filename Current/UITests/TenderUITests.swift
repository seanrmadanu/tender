import XCTest

// These tests use a separate documents directory and Keychain namespace.
// Automatic bank networking is disabled for --ui-testing.
final class TenderUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 15))
    }
    // Forms load rows lazily and the keyboard covers the lower screen. Scroll in short drags
    // that stop before release: a full swipe flings past a row, and the form then unloads it.
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 2)
        var drags = 0
        while !element.isHittable && drags < 15 {
            let above = element.exists && element.frame.midY < app.frame.height * 0.25
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: above ? 0.62 : 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
            drags += 1
        }
        XCTAssertTrue(element.isHittable, "Could not scroll to \(element)", file: file, line: line)
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        reveal(element, file: file, line: line); element.tap()
    }
    private func enter(_ name: String, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields[name]; tap(field, file: file, line: line); field.typeText(value)
    }
    // Menu items can share a name with a tab bar button, such as Groceries.
    private func chooseCategory(_ name: String) {
        tap(app.buttons["Category, Choose"]); tap(app.collectionViews.buttons[name])
    }
    private func accounts() {
        app.tabBars.buttons["Settings"].tap()
        // The Settings tab keeps its navigation stack, so it may still show Accounts or an account.
        let link = app.buttons["Accounts & Cash Wallet"], list = app.navigationBars["Accounts"]
        for _ in 0..<3 {
            if list.exists { return }
            if link.waitForExistence(timeout: 2) { tap(link); XCTAssertTrue(list.waitForExistence(timeout: 5)); return }
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTFail("Could not open Accounts")
    }
    private func addAccount(_ name: String, _ balance: String) {
        tap(app.buttons["Add Account"])
        enter("Account name", name); enter("Available balance (USD)", balance)
        // The Accounts screen behind the sheet has its own "Add Account" button.
        tap(app.buttons["save-manual-account"])
        XCTAssertTrue(app.navigationBars["Manual Account"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account-\(name)"].waitForExistence(timeout: 5))
    }
    private func restart() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-test-ledger"]; app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 10))
    }
    func testAccountsPersistSeparately() {
        accounts(); addAccount("Checking", "100.00"); addAccount("Savings", "200.00")
        restart(); accounts()
        XCTAssertTrue(app.buttons["account-Checking"].exists)
        XCTAssertTrue(app.buttons["account-Savings"].exists)
        XCTAssertTrue(app.staticTexts["Total available, $300.00"].exists)
    }
    func testPurchaseUsesSelectedAccount() {
        accounts(); addAccount("Checking", "100.00"); addAccount("Savings", "200.00")
        tap(app.buttons["account-Savings"]); tap(app.buttons["Add Purchase"])
        enter("Merchant or description", "Market"); enter("Amount (USD)", "25.00")
        chooseCategory("Groceries")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Available balance, $175.00"].waitForExistence(timeout: 5))
        restart(); accounts(); tap(app.buttons["account-Checking"])
        XCTAssertTrue(app.staticTexts["Available balance, $100.00"].waitForExistence(timeout: 5))
    }
    func testLegacyLedgerIsPreservedInsteadOfReset() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--legacy-reset-test"]; app.launch()
        accounts(); XCTAssertTrue(app.buttons["account-Everyday checking"].waitForExistence(timeout: 10))
        restart(); accounts(); XCTAssertTrue(app.buttons["account-Everyday checking"].exists)
    }
    func testReportsMovedInsideActivity() {
        XCTAssertFalse(app.tabBars.buttons["Reports"].exists)
        app.tabBars.buttons["Activity"].tap(); tap(app.buttons["Reports"])
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Backup & Restore"].exists)
    }
    func testCartDoesNotRecordExpenseAndPricePersists() {
        app.tabBars.buttons["Groceries"].tap(); tap(app.buttons["Add item"])
        enter("Item name", "Apples"); enter("Price per unit (USD, optional)", "1.49")
        tap(app.buttons["Add to Cart"])
        XCTAssertTrue(app.staticTexts["Apples"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.containing(.staticText, identifier: "Apples").firstMatch.exists)
        restart(); app.tabBars.buttons["Groceries"].tap()
        XCTAssertTrue(app.staticTexts["Apples"].waitForExistence(timeout: 5))
        let apples = app.buttons.containing(.staticText, identifier: "Apples").firstMatch
        tap(apples)
        enter("Price per each (USD)", "3.49"); tap(app.navigationBars.buttons["Save Price"])
        XCTAssertTrue(app.staticTexts["Price saved"].waitForExistence(timeout: 5))
        // "Price saved" is screen state only; relaunch to check both prices were stored.
        restart(); app.tabBars.buttons["Groceries"].tap(); tap(apples)
        reveal(app.staticTexts["Store not specified, $1.49"])
        reveal(app.staticTexts["Store not specified, $3.49"])
    }
    func testTypedShoppingPlanPrefillsAndStaysReviewable() {
        app.tabBars.buttons["Groceries"].tap(); tap(app.buttons["Add item"])
        enter("Ice cream tomorrow at Costco at 5 PM", "I want ice cream tomorrow when I go to Costco at 5 PM")
        tap(app.buttons["Fill Details for Review"])
        let item = app.textFields["Item name"], shop = app.textFields["Store (optional)"]
        reveal(item); XCTAssertEqual(item.value as? String, "ice cream")
        reveal(shop); XCTAssertEqual(shop.value as? String, "Costco")
        // Cancel rather than requesting notification or microphone permissions.
        tap(app.buttons["Cancel"])
    }
    func testCashDoesNotDeductChecking() {
        accounts(); addAccount("Checking", "100.00")
        app.tabBars.buttons["Home"].tap(); tap(app.buttons["Record Purchase"])
        enter("Merchant or description", "Cash coffee"); enter("Amount (USD)", "5.00")
        chooseCategory("Food & coffee")
        // Tap the switch itself; the middle of a Toggle row is its label.
        let cash = app.switches["Paid with cash"]; reveal(cash)
        cash.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(cash.value as? String, "1")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.navigationBars["Add Expense"].waitForNonExistence(timeout: 5))
        accounts(); XCTAssertTrue(app.buttons["account-Cash wallet"].waitForExistence(timeout: 5))
        tap(app.buttons["account-Checking"])
        XCTAssertTrue(app.staticTexts["Available balance, $100.00"].waitForExistence(timeout: 5))
    }
    func testWholeFieldTapFocusesInput() {
        tap(app.buttons["Record Purchase"])
        let field = app.textFields["Merchant or description"]
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        field.typeText("Wide tap")
        XCTAssertEqual(field.value as? String, "Wide tap")
    }
    func testFutureCartOpensItsDateAndPlanCanBeEdited() {
        app.tabBars.buttons["Groceries"].tap(); tap(app.buttons["Add item"])
        XCTAssertFalse(app.buttons["Add to Cart"].isEnabled)
        enter("Ice cream tomorrow at Costco at 5 PM", "I want apples tomorrow at Costco")
        tap(app.buttons["Fill Details for Review"])
        tap(app.buttons["Add to Cart"])
        XCTAssertTrue(app.staticTexts["apples"].waitForExistence(timeout: 5))
        tap(app.buttons.containing(.staticText, identifier: "apples").firstMatch)
        tap(app.buttons["Edit Shopping Plan"])
        let shop = app.textFields["Store (optional)"]
        tap(shop); shop.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Target")
        tap(app.navigationBars["Edit Shopping Plan"].buttons["Save"])
        XCTAssertTrue(app.staticTexts["Store, Target"].waitForExistence(timeout: 5))
        restart(); app.tabBars.buttons["Groceries"].tap(); tap(app.buttons["Next day"])
        XCTAssertTrue(app.staticTexts["apples"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Target"].exists)
    }
}
