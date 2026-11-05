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
            // Start inside the content. The navigation edge can swallow drags
            // that begin outside a Form's inset rows.
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: above ? 0.62 : 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
            drags += 1
        }
        XCTAssertTrue(element.isHittable, "Could not scroll to \(element)", file: file, line: line)
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        reveal(element, file: file, line: line); element.tap()
    }
    private func openMonthlyAllocations() {
        let button = app.buttons["edit-monthly-allocations"]
        // The selection bar overlays content that XCTest sometimes calls hittable.
        // Bring the row fully above it before tapping its center.
        for _ in 0..<8 {
            if button.exists && button.frame.midY < app.frame.height * 0.72 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        tap(button)
        XCTAssertTrue(app.navigationBars["Monthly allocations"].waitForExistence(timeout: 5))
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
        tap(app.buttons["add-info-manually"])
        tap(app.buttons["continue-manual-account"])
        enter("Account name", name); enter("Available balance (USD)", balance)
        // The Accounts screen behind the sheet has its own "Add Account" button.
        tap(app.buttons["save-manual-account"])
        XCTAssertTrue(app.navigationBars["Offline Account"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account-\(name)"].waitForExistence(timeout: 5))
    }
    private func saveScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func restart() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-test-ledger"]; app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 10))
    }
    private func openProfilePhotoFromHome() {
        tap(app.buttons["profile-photo-button"])
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        tap(app.buttons["change-profile-photo"])
    }
    func testMonthlyEnvelopeAllocationsEditSaveCancelAndPersist() {
        accounts(); addAccount("Budget funding", "2500")
        app.tabBars.buttons["Budgets"].tap()
        let total = app.buttons["edit-monthly-allocations"]
        XCTAssertFalse(total.isEnabled)
        app.navigationBars.buttons["Edit"].tap()
        openMonthlyAllocations()
        XCTAssertTrue(app.navigationBars["Monthly allocations"].waitForExistence(timeout: 5))
        enter("monthly-budget-input", "1000")
        enter("Groceries monthly allocation in US dollars", "250")
        enter("Food & coffee monthly allocation in US dollars", "75.50")
        let draftTotal = app.descendants(matching: .any).matching(identifier: "allocation-draft-total").firstMatch
        XCTAssertTrue(draftTotal.label.contains("$1,000.00"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "allocation-draft-assigned").firstMatch.label.contains("$325.50"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "allocation-draft-unallocated").firstMatch.label.contains("$674.50"))
        saveScreen("Separate monthly budget and envelope allocations")
        tap(app.buttons["save-monthly-allocations"])
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("$1,000.00"))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].isHittable)
        tap(app.buttons["Add category"])
        enter("Category name", "Extra budget")
        enter("Monthly allocation (USD)", "100")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(total.label.contains("$1,000.00"))
        restart(); app.tabBars.buttons["Budgets"].tap()
        XCTAssertTrue(total.label.contains("$1,000.00"))
        app.navigationBars.buttons["Edit"].tap(); openMonthlyAllocations()
        enter("Shopping monthly allocation in US dollars", "1")
        XCTAssertTrue(draftTotal.label.contains("$1,000.00"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "allocation-draft-assigned").firstMatch.label.contains("$426.50"))
        tap(app.navigationBars.buttons["Cancel"])
        XCTAssertTrue(total.label.contains("$1,000.00"))
        openMonthlyAllocations()
        let budget = app.textFields["monthly-budget-input"]
        tap(budget)
        let value = budget.value as? String ?? ""
        budget.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + "1200")
        tap(app.buttons["save-monthly-allocations"])
        XCTAssertTrue(total.label.contains("$1,200.00"))
        app.navigationBars.buttons["Done"].tap()
        restart(); app.tabBars.buttons["Budgets"].tap()
        XCTAssertTrue(total.label.contains("$1,200.00"))
        saveScreen("Monthly budget stays independent of added envelopes and can be changed")
    }
    func testBudgetEditingReplacesNavigationAndDoneRestoresIt() {
        app.tabBars.buttons["Budgets"].tap()
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Home"].isHittable)
        let category = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "budget-select-")).firstMatch
        tap(category)
        XCTAssertTrue(app.buttons["Delete"].isEnabled)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isHittable)
        XCTAssertFalse(app.buttons["Delete"].exists)
        saveScreen("Budgets review cards")
    }
    func testFixedExpensesCapAllocationsAndImportedSpendingAppearsInActivity() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--budget-funding-test"]; app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Activity"].tap()
        let spent = app.descendants(matching: .any).matching(identifier: "activity-total-spent").firstMatch
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertTrue(spent.label.contains("$10.00"), spent.label)
        app.tabBars.buttons["Budgets"].tap()
        tap(app.buttons["add-fixed-expense"])
        enter("fixed-expense-name", "Rent"); enter("fixed-expense-amount", "200")
        tap(app.buttons["save-fixed-expense"])
        let capacity = app.descendants(matching: .any).matching(identifier: "budget-capacity").firstMatch
        reveal(capacity); XCTAssertTrue(capacity.label.contains("$300.00"), capacity.label)
        saveScreen("Five hundred balance less two hundred reserved leaves three hundred")
        app.navigationBars.buttons["Edit"].tap(); openMonthlyAllocations()
        enter("monthly-budget-input", "301")
        XCTAssertFalse(app.buttons["save-monthly-allocations"].isEnabled)
        reveal(app.staticTexts["allocation-cap-warning"])
        let total = app.textFields["monthly-budget-input"]
        tap(total); total.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (total.value as? String ?? "").count) + "300")
        enter("Groceries monthly allocation in US dollars", "150")
        enter("Food & coffee monthly allocation in US dollars", "100")
        XCTAssertTrue(app.buttons["save-monthly-allocations"].isEnabled)
        saveScreen("Allocation capped at available funds with envelope amounts")
        tap(app.buttons["save-monthly-allocations"])
        app.navigationBars.buttons["Done"].tap()
        tap(app.buttons["review-monthly-payments"])
        XCTAssertTrue(app.navigationBars["Monthly Payments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["apply-monthly-suggestions"].label.contains("1"))
        tap(app.buttons["apply-monthly-suggestions"])
        XCTAssertTrue(app.staticTexts["1 purchases categorized. Balances are unchanged."].waitForExistence(timeout: 5))
        saveScreen("Monthly bank spending categorized without another deduction")
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(spent.label.contains("$10.00"), spent.label)
        XCTAssertFalse(app.buttons["activity-unassigned"].exists)
        app.tabBars.buttons["Budgets"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        reveal(capacity); XCTAssertTrue(capacity.label.contains("$300.00"), capacity.label)
    }
    func testEmailSignupUsesNameForProfileWithoutSeparateNamingStep() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--signup-ui-test"]; app.launch()
        tap(app.buttons["Continue with email"])
        tap(app.segmentedControls.buttons["Create Account"])
        enter("Email", "signup-fixture@example.invalid")
        tap(app.secureTextFields["Password"]); app.secureTextFields["Password"].typeText("test-password-only")
        XCTAssertFalse(app.buttons["email-auth-submit"].isEnabled)
        enter("signup-full-name", "Taylor Example")
        XCTAssertTrue(app.buttons["email-auth-submit"].isEnabled)
        tap(app.buttons["email-auth-submit"])
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["profile-display-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profile-display-name"].label, "Taylor Example")
        saveScreen("Signup name supplies profile identity")
    }
    func testAIConnectionsAreOptInAndSourcesSurviveNormalEditingAndDeletion() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ai-connections-test"]; app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 10))
        accounts(); addAccount("AI test checking", "500")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["ai-connections-settings"])
        XCTAssertTrue(app.staticTexts["Stored on this phone"].waitForExistence(timeout: 5))
        tap(app.buttons["ai-enable"]); tap(app.buttons.matching(identifier: "ai-confirm-enable").firstMatch)
        XCTAssertTrue(app.buttons["ai-sync-now"].waitForExistence(timeout: 5))
        tap(app.buttons["ai-fixture-purchase"])
        tap(app.buttons["ai-fixture-fixed"])
        app.tabBars.buttons["Budgets"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "assistant-source-claude").firstMatch.waitForExistence(timeout: 5))
        saveScreen("Claude fixed expense source badge")
        app.tabBars.buttons["Home"].tap()
        tap(app.buttons["show-all-bank-transactions"])
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "assistant-source-chatgpt").firstMatch.waitForExistence(timeout: 5))
        saveScreen("ChatGPT purchase source badge")
        tap(app.buttons.containing(.staticText, identifier: "AI fixture lunch").firstMatch)
        tap(app.buttons["edit-manual-purchase"])
        let merchant = app.textFields["edit-expense-merchant"]
        tap(merchant); merchant.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100) + "Corrected AI lunch")
        let amount = app.textFields["edit-expense-amount"]
        tap(amount); amount.typeText("15")
        tap(app.buttons["save-edited-purchase"])
        XCTAssertTrue(app.staticTexts["Corrected AI lunch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "assistant-source-chatgpt").firstMatch.exists)
        saveScreen("AI purchase uses normal editing controls and retains attribution")
        tap(app.buttons["Delete Expense"])
        tap(app.buttons.matching(identifier: "confirm-archive-expense").firstMatch)
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Corrected AI lunch"].exists)
    }
    func testAIChangesProfileRemindersAndGroceriesAndOpensSettingsOnce() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ai-connections-test"]; app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 10))
        accounts(); addAccount("AI test checking", "500")
        app.navigationBars.buttons.firstMatch.tap(); tap(app.buttons["ai-connections-settings"])
        tap(app.buttons["ai-enable"]); tap(app.buttons.matching(identifier: "ai-confirm-enable").firstMatch)
        tap(app.buttons["ai-fixture-app-settings"])
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Taylor AI"].exists)
        app.tabBars.buttons["Groceries"].tap()
        XCTAssertTrue(app.staticTexts["AI fixture milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "assistant-source-chatgpt").firstMatch.exists)
        saveScreen("AI grocery source and synced profile settings")
        app.tabBars.buttons["Settings"].tap(); app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["Bank Updates & Reminders"])
        XCTAssertEqual(app.switches["app-reminders-enabled"].value as? String, "0")
        saveScreen("AI reminder setting uses normal Settings control")
    }
    func testCloudConflictTurningOffRemindersClearsScheduledNotifications() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ai-connections-test", "--ai-reminder-test"]; app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 10))
        accounts(); addAccount("AI checking", "500")
        app.navigationBars.buttons.firstMatch.tap(); tap(app.buttons["ai-connections-settings"])
        tap(app.buttons["ai-enable"]); tap(app.buttons.matching(identifier: "ai-confirm-enable").firstMatch)
        tap(app.buttons["ai-fixture-reminder-conflict"])
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.buttons["ai-fixture-resolve-cloud"].waitForExistence(timeout: 5))
        tap(app.buttons["ai-check-pending-reminders"])
        XCTAssertTrue(app.staticTexts["1 scheduled test reminders"].waitForExistence(timeout: 5))
        tap(app.buttons["ai-fixture-resolve-cloud"])
        tap(app.buttons["ai-check-pending-reminders"])
        XCTAssertTrue(app.staticTexts["0 scheduled test reminders"].waitForExistence(timeout: 5))
    }
    func testExpensePaidFromOpensOfflineAccountNotice() {
        tap(app.buttons["Record Purchase"])
        XCTAssertFalse(app.switches["Paid with cash"].exists)
        tap(app.buttons["expense-paid-from"])
        tap(app.buttons["Add account…"])
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
        tap(app.buttons["add-info-manually"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "does not connect to a bank or sync balances or transactions")).firstMatch.waitForExistence(timeout: 5))
        saveScreen("Offline account notice from Paid from")
    }
    func testArchiveEnvelopeAndRestoreFromSettings() {
        app.tabBars.buttons["Budgets"].tap()
        app.navigationBars.buttons["Edit"].tap()
        let category = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "budget-select-")).firstMatch
        tap(category)
        tap(app.buttons["Delete"])
        XCTAssertTrue(app.buttons["confirm-delete-envelopes"].waitForExistence(timeout: 5))
        saveScreen("Envelope anchored archive confirmation")
        tap(app.buttons["confirm-delete-envelopes"])
        app.tabBars.buttons["Settings"].tap()
        tap(app.buttons["Archive"])
        XCTAssertTrue(app.navigationBars["Archive"].waitForExistence(timeout: 5))
        tap(app.buttons["Restore"].firstMatch)
        XCTAssertTrue(app.staticTexts["No archived envelopes"].waitForExistence(timeout: 5))
    }
    func testHomeSubscriptionsAndTransactionDateMenu() {
        saveScreen("Home transactions and subscriptions switch")
        tap(app.segmentedControls.buttons["Subscriptions"])
        tap(app.buttons["Show all possible subscriptions"])
        XCTAssertTrue(app.navigationBars["Possible subscriptions"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.segmentedControls.buttons["Transactions"])
        XCTAssertFalse(app.staticTexts["This month"].exists)
        tap(app.buttons["show-all-bank-transactions"])
        tap(app.buttons["Date range"])
        tap(app.buttons["Custom dates"])
        XCTAssertTrue(app.navigationBars["Transaction dates"].waitForExistence(timeout: 5))
        tap(app.buttons["Apply"])
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 5))
        saveScreen("Transactions date range")
    }
    func testHomeBankActivityOpensFullHistory() {
        XCTAssertFalse(app.staticTexts["YOUR EVERYDAY LEDGER"].exists)
        XCTAssertFalse(app.staticTexts["A little more intentional."].exists)
        tap(app.buttons["show-all-bank-transactions"])
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 5))
        saveScreen("Bank activity history")
    }
    func testSlowStorageShowsLoadingScreenBeforeLedgerIsReady() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--slow-ledger-load"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Loading balances"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Last updated"].exists)
        XCTAssertFalse(app.buttons["Record Purchase"].exists, "Editing must wait for the saved ledger.")
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Loading balances"].exists)
    }
    func testManualExplanationCanGoBackOrContinueAndCashPersists() {
        accounts()
        XCTAssertFalse(app.staticTexts["No bank connection needed"].exists)
        XCTAssertTrue(app.buttons["import-bank-plaid"].exists)
        saveScreen("Accounts options")
        tap(app.buttons["add-info-manually"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "You’re responsible for updating purchases and balances")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["explanation-connect-plaid"].exists)
        saveScreen("Manual account explanation")
        tap(app.buttons["Go Back"])
        XCTAssertFalse(app.buttons["continue-manual-account"].exists)
        addAccount("Manual Checking", "123.45")
        let field = app.textFields["cash-on-hand"]
        tap(field); field.typeText("42.50")
        tap(app.buttons["save-cash"])
        reveal(app.buttons["account-Cash"])
        restart(); accounts()
        XCTAssertEqual(app.textFields["cash-on-hand"].value as? String, "42.50")
        tap(app.textFields["cash-on-hand"])
        app.textFields["cash-on-hand"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "30.00")
        tap(app.buttons["save-cash"])
        reveal(app.buttons["account-Cash"])
        XCTAssertEqual(app.buttons.matching(identifier: "account-Cash").count, 1)
        reveal(app.staticTexts["Total available, $153.45"])
        saveScreen("Cash saved without duplicate account")
    }
    func testManualExplanationCanSwitchToPlaid() {
        accounts(); tap(app.buttons["add-info-manually"])
        tap(app.buttons["explanation-connect-plaid"])
        XCTAssertTrue(app.navigationBars["Import Bank Account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["continue-manual-account"].exists)
    }
    func testBankTransactionNotePersistsWithoutExpense() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--bank-import-test"]; app.launch()
        accounts(); tap(app.buttons["import-bank-plaid"])
        XCTAssertTrue(app.buttons["account-Test Bank · Checking · ··1234"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Home"].tap()
        tap(app.buttons["show-all-bank-transactions"])
        let purchase = app.buttons["bank-transaction-production:fixture-item:purchase"]
        tap(purchase)
        let note = app.descendants(matching: .any).matching(identifier: "bank-transaction-note").firstMatch
        tap(note); note.typeText("Lunch with Alex")
        tap(app.buttons["Save Note"])
        XCTAssertTrue(app.staticTexts["Note saved."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Attach Receipt PDF or Image"].exists)
        app.navigationBars.buttons["Done"].tap()
        tap(purchase)
        XCTAssertEqual(note.value as? String, "Lunch with Alex")
        XCTAssertFalse(app.staticTexts["This bank purchase is already matched to your recorded expenses."].exists)
        saveScreen("Bank transaction receipts and notes")
    }
    func testPlaidAutomaticallyImportsAndSavedBalanceSurvivesOfflineRelaunch() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--bank-import-test"]; app.launch()
        accounts()
        tap(app.buttons["import-bank-plaid"])
        let imported = app.buttons["account-Test Bank · Checking · ··1234"]
        XCTAssertTrue(imported.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Check Connection"].exists)
        XCTAssertFalse(app.buttons["Load Cached Balances"].exists)
        XCTAssertFalse(app.navigationBars["Import Bank Account"].exists)
        reveal(imported); saveScreen("Automatically imported bank account")
        tap(imported)
        XCTAssertTrue(app.staticTexts["Available balance, $123.45"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Update Balance"].exists)
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-test-ledger", "--offline-bank"]; app.launch()
        XCTAssertTrue(app.staticTexts["bank-offline-warning"].waitForExistence(timeout: 10))
        saveScreen("Offline Home with saved bank balance")
        accounts(); reveal(imported)
        XCTAssertEqual(app.buttons.matching(identifier: "account-Test Bank · Checking · ··1234").count, 1)
        XCTAssertTrue(app.staticTexts["bank-offline-warning"].exists)
        saveScreen("Offline Accounts retains last bank update")
        tap(imported)
        XCTAssertTrue(app.staticTexts["Available balance, $123.45"].waitForExistence(timeout: 5))
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
    func testReportsAreTheActivityScreen() {
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls.buttons["Expenses"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Recurring"].exists)
        XCTAssertTrue(app.staticTexts["TOTAL SPENT"].exists)
        saveScreen("Activity monthly statistics")
        tap(app.segmentedControls.buttons["Last 7 days"])
        XCTAssertTrue(app.staticTexts["Daily spending · USD"].exists)
        saveScreen("Activity weekly statistics")
    }
    func testSettingsProfileIdentityNameAndPhotoRoute() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--profile-settings-test"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertEqual(app.staticTexts["profile-display-name"].label, "Test Member")
        XCTAssertEqual(app.staticTexts["profile-member-since"].label, "Member since 2021")
        XCTAssertFalse(app.staticTexts["Personal edition · USD"].exists)
        tap(app.buttons["profile-settings-header"])
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        tap(app.buttons["edit-profile-name"])
        enter("Your name", " Updated")
        tap(app.buttons["save-profile-name"])
        XCTAssertEqual(app.staticTexts["profile-display-name"].label, "Test Member Updated")
        tap(app.buttons["change-profile-photo"])
        XCTAssertTrue(app.buttons["profile-choose-photo"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        let profileButton = app.buttons["profile-photo-button"].frame
        XCTAssertEqual(profileButton.width, 60.8, accuracy: 1)
        XCTAssertEqual(profileButton.height, 60.8, accuracy: 1)
        XCTAssertEqual(profileButton.width, profileButton.height, accuracy: 1)
        saveScreen("Smaller circular Home profile button")
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-test-ledger", "--profile-settings-test"]; app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertEqual(app.staticTexts["profile-display-name"].label, "Test Member Updated")
        XCTAssertEqual(app.staticTexts["profile-member-since"].label, "Member since 2021")
        saveScreen("Settings profile photo name and member year")
        tap(app.buttons["profile-settings"])
        XCTAssertTrue(app.buttons["change-profile-photo"].exists)
        XCTAssertFalse(app.sliders["profile-frame-size"].exists)
        XCTAssertFalse(app.buttons["reset-profile-frame-size"].exists)
        saveScreen("Fixed larger Settings profile photo without size controls")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["profile-settings"])
        XCTAssertFalse(app.sliders["profile-frame-size"].exists)
        saveScreen("Profile settings photo and name controls")
    }
    func testProfilePhotoCropSaveReeditCancelAndRemove() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--profile-photo-test"]; app.launch()
        openProfilePhotoFromHome()
        XCTAssertTrue(app.buttons["profile-choose-photo"].exists)
        XCTAssertFalse(app.buttons["profile-adjust-photo"].exists)
        tap(app.buttons["profile-test-photo"])
        XCTAssertTrue(app.navigationBars["Adjust photo"].waitForExistence(timeout: 5))
        tap(app.buttons["profile-zoom-in"]); tap(app.buttons["profile-zoom-in"])
        XCTAssertEqual(app.staticTexts["profile-zoom-value"].label, "150% zoom")
        let preview = app.descendants(matching: .any).matching(identifier: "profile-crop-preview").firstMatch
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)))
        saveScreen("Logo shaped profile photo crop and zoom")
        tap(app.buttons["profile-rotate"])
        XCTAssertEqual(app.staticTexts["profile-zoom-value"].label, "100% zoom")
        tap(app.buttons["profile-zoom-in"])
        tap(app.buttons["profile-save-crop"])
        XCTAssertTrue(app.buttons["profile-adjust-photo"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        XCTAssertEqual(app.buttons["profile-photo-button"].value as? String, "Photo set")
        saveScreen("Home profile photo in tender logo")
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-test-ledger", "--profile-photo-test"]; app.launch()
        openProfilePhotoFromHome(); tap(app.buttons["profile-adjust-photo"])
        XCTAssertEqual(app.staticTexts["profile-zoom-value"].label, "125% zoom")
        tap(app.buttons["profile-reset-crop"])
        XCTAssertEqual(app.staticTexts["profile-zoom-value"].label, "100% zoom")
        tap(app.navigationBars.buttons["Cancel"])
        tap(app.buttons["profile-adjust-photo"])
        XCTAssertEqual(app.staticTexts["profile-zoom-value"].label, "125% zoom")
        tap(app.navigationBars.buttons["Cancel"])
        tap(app.buttons["profile-remove-photo"])
        tap(app.buttons.matching(identifier: "confirm-remove-profile-photo").firstMatch)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["profile-adjust-photo"])
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["Home"].tap()
        XCTAssertEqual(app.buttons["profile-photo-button"].value as? String, "Default logo")
    }
    func testCardArtworkSelectionPersistsAndStandardDisplayRemainsAvailable() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--bank-import-test", "--card-artwork-test"]; app.launch()
        accounts(); tap(app.buttons["import-bank-plaid"])
        let account = app.buttons["account-Test Bank · Checking · ··1234"]
        XCTAssertTrue(account.waitForExistence(timeout: 15)); tap(account)
        tap(app.buttons["choose-card-design"])
        XCTAssertTrue(app.buttons["card-artwork-automatic"].label.contains("selected"))
        tap(app.buttons["card-artwork-fixture-premium"])
        XCTAssertTrue(app.buttons["card-artwork-fixture-premium"].label.contains("selected"))
        saveScreen("Synthetic card artwork selection")
        app.tabBars.buttons["Home"].tap()
        tap(app.buttons["wallet-reveal"])
        let front = app.buttons["wallet-front-card"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        XCTAssertTrue(front.label.contains("$123.45"))
        saveScreen("Synthetic original artwork in revealed wallet")
        tap(front)
        XCTAssertTrue(app.buttons["choose-card-design"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-test-ledger", "--bank-import-test", "--card-artwork-test"]; app.launch()
        accounts(); tap(app.buttons["account-Test Bank · Checking · ··1234"])
        tap(app.buttons["choose-card-design"])
        XCTAssertTrue(app.buttons["card-artwork-fixture-premium"].label.contains("selected"))
        tap(app.buttons["card-artwork-standard"])
        XCTAssertTrue(app.buttons["card-artwork-standard"].label.contains("selected"))
    }
    func testCardArtworkUnavailableKeepsStandardDisplay() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--bank-import-test"]; app.launch()
        accounts(); tap(app.buttons["import-bank-plaid"])
        XCTAssertTrue(app.buttons["account-Test Bank · Checking · ··1234"].waitForExistence(timeout: 15))
        tap(app.buttons["account-Test Bank · Checking · ··1234"]); tap(app.buttons["choose-card-design"])
        XCTAssertTrue(app.staticTexts["Original artwork isn’t available for this bank yet."].exists)
        XCTAssertFalse(app.buttons["card-artwork-fixture-premium"].exists)
        tap(app.buttons["card-artwork-standard"])
        XCTAssertTrue(app.buttons["card-artwork-standard"].label.contains("selected"))
    }
    func testWalletHideDoesNotOpenCardDetails() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--bank-import-test", "--wallet-test"]; app.launch()
        accounts(); tap(app.buttons["import-bank-plaid"])
        XCTAssertTrue(app.buttons["account-Test Bank · Checking · ··1234"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Home"].tap()
        let control = app.buttons["wallet-reveal"]
        let card = app.buttons["wallet-front-card"]
        let width = control.frame.width
        for _ in 0..<2 {
            tap(control)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertEqual(control.label, "Hide card")
            XCTAssertEqual(control.frame.width, width, accuracy: 0.5)
            // Use a physical touch at the button center to catch overlapping card hit targets.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            expectation(for: NSPredicate(format: "label == %@", "Reveal card"), evaluatedWith: control)
            waitForExpectations(timeout: 5)
            XCTAssertFalse(card.exists)
            XCTAssertFalse(app.buttons["delete-card"].exists)
        }
        tap(control)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        tap(card)
        XCTAssertTrue(app.navigationBars["Test Bank · Checking · ··1234"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["delete-card"].exists)
    }
    func testWalletSwipeDetailsDeleteAndRestore() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--bank-import-test", "--wallet-test"]; app.launch()
        accounts(); tap(app.buttons["import-bank-plaid"])
        XCTAssertTrue(app.buttons["account-Test Bank · Checking · ··1234"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Home"].tap()
        XCTAssertFalse(app.buttons["Edit"].exists)
        XCTAssertFalse(app.buttons["primary-account-menu"].exists)
        let control = app.buttons["wallet-reveal"]
        let width = control.frame.width
        tap(control)
        let card = app.buttons["wallet-front-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("$123.45"))
        XCTAssertEqual(control.frame.width, width, accuracy: 0.5)
        saveScreen("Revealed tilted stack and rolling balance")
        card.swipeLeft()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Savings"), evaluatedWith: card)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(card.label.contains("$200.00"))
        tap(app.segmentedControls.buttons["Subscriptions"])
        XCTAssertTrue(app.staticTexts["Other Account Service"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fixture Cafe"].exists)
        saveScreen("Next card and matching subscriptions")
        tap(card)
        XCTAssertTrue(app.navigationBars["Other Bank · Savings · ··9876"].waitForExistence(timeout: 5))
        tap(app.buttons["delete-card"])
        let confirm = app.buttons.matching(identifier: "confirm-delete-card").firstMatch
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        else {
            let buttons = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Card"))
            buttons.element(boundBy: buttons.count - 1).tap()
        }
        XCTAssertTrue(app.buttons["wallet-reveal"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        if app.navigationBars["Accounts"].exists { app.navigationBars.buttons.firstMatch.tap() }
        tap(app.buttons["Archive"])
        tap(app.buttons["Other Bank · Savings · ··9876"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Other Account Service")).firstMatch.waitForExistence(timeout: 5))
        saveScreen("Archived card with transaction history")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["Restore"].firstMatch)
        XCTAssertTrue(app.staticTexts["No archived accounts"].waitForExistence(timeout: 5))
    }
    func testQuickStartupRefreshFinishesBeforeHome() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--bank-import-test", "--wallet-startup-test"]
        app.launch()
        XCTAssertTrue(app.buttons["wallet-reveal"].waitForExistence(timeout: 4))
        let total = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "wallet-total-balance", "$123.45")).firstMatch
        XCTAssertTrue(total.exists)
        saveScreen("First Home frame has refreshed balance")
    }
    func testStartupWaitsForBalanceRefreshBeforeShowingHome() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--bank-import-test", "--wallet-startup-test", "--wallet-startup-timeout-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Loading balances"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Last updated"].exists)
        XCTAssertFalse(app.buttons["wallet-reveal"].exists, "Home must stay closed while its balance is still being refreshed.")
        let savedTotal = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "wallet-total-balance", "$9.99")).firstMatch
        XCTAssertFalse(savedTotal.exists)
        saveScreen("Loading balances without date or time while bank refresh runs")
        let updatedTotal = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "wallet-total-balance", "$123.45")).firstMatch
        XCTAssertTrue(updatedTotal.waitForExistence(timeout: 15), "The first Home frame must show the completed balance refresh.")
        XCTAssertFalse(app.staticTexts["Loading balances"].exists)
        XCTAssertFalse(savedTotal.exists)
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Fixture Cafe").firstMatch.exists)
        saveScreen("First Home after loading shows refreshed balances and activity")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--preserve-test-ledger", "--bank-import-test", "--wallet-startup-test", "--offline-bank"]
        app.launch()
        XCTAssertTrue(updatedTotal.waitForExistence(timeout: 4), "The completed refresh must survive the next offline launch.")
    }
    func testStartupRefreshFailureOpensSavedBalancesWithWarning() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--bank-import-test", "--wallet-startup-test", "--wallet-startup-failure-test"]
        app.launch()
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "wallet-total-balance", "$9.99")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bank update failed. Showing saved balances."].exists)
        XCTAssertFalse(app.staticTexts["Loading balances"].exists)
        saveScreen("Failed launch refresh keeps saved balances and shows warning")
    }
    func testOfflineStartupKeepsSavedBalancesWithoutHanging() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--bank-import-test", "--wallet-startup-test", "--offline-bank"]
        app.launch()
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "wallet-total-balance", "$9.99")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["bank-offline-warning"].exists)
        XCTAssertFalse(app.staticTexts["Loading balances"].exists)
    }
    func testRememberedSignInDoesNotWaitForAccountService() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--auth-startup-test"]
        let started = Date()
        app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 3))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(app.staticTexts["Opening your ledger…"].exists)
    }
    func testFirstOpenShowsCurrentBuildAndMenu() {
        let names = app.tabBars.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(names, ["Home", "Budgets", "Groceries", "Activity", "Settings"])
        app.tabBars.buttons["Settings"].tap()
        let version = app.descendants(matching: .any).matching(identifier: "installed-app-version").firstMatch
        reveal(version)
        XCTAssertTrue(version.label.contains("0.1.0 (10)"))
        saveScreen("First open shows installed build 7")
    }
    func testPersonalizedCashNoteRevealsAndUpdatesCashBalance() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--profile-photo-test"]; app.launch()
        openProfilePhotoFromHome()
        tap(app.buttons["profile-test-photo"])
        tap(app.buttons["profile-save-crop"])
        app.tabBars.buttons["Home"].tap()
        accounts()
        let cash = app.textFields["cash-on-hand"]
        tap(cash); cash.typeText("42.50")
        tap(app.buttons["save-cash"])
        app.tabBars.buttons["Home"].tap()
        tap(app.buttons["wallet-reveal"])
        let front = app.buttons["wallet-front-card"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        XCTAssertTrue(front.label.contains("$42.50"))
        saveScreen("Reference green guilloche cash note without profile photo")
        tap(app.buttons["wallet-reveal"])
        XCTAssertTrue(app.buttons["wallet-reveal"].label.contains("Reveal"))
        accounts()
        tap(cash); cash.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "60.00")
        tap(app.buttons["save-cash"])
        app.tabBars.buttons["Home"].tap()
        tap(app.buttons["wallet-reveal"])
        XCTAssertTrue(front.label.contains("$60.00"))
        tap(front)
        XCTAssertTrue(app.buttons["delete-card"].waitForExistence(timeout: 5))
    }
    func testZeroBalanceCanBeReplacedByTypingWithDecimalKeyboard() {
        accounts(); addAccount("Zero checking", "0.00")
        tap(app.buttons["account-Zero checking"])
        tap(app.buttons["Update Balance"])
        let amount = app.textFields["Available balance (USD)"]
        tap(amount); amount.typeText("50")
        XCTAssertEqual(amount.value as? String, "50")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.keyboards.keys["q"].exists)
        XCTAssertTrue(app.keyboards.keys["5"].exists || app.keyboards.buttons["5"].exists)
        saveScreen("Zero balance replaced without clearing and decimal keyboard")
        tap(app.buttons["save-manual-account"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "$50.00")).firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["Update Balance"])
        tap(amount); amount.typeText("75")
        XCTAssertEqual(amount.value as? String, "75", "A prefilled amount should be selected for replacement.")
        tap(app.buttons["save-manual-account"])
    }
    func testHomeProfileOpensSettingsProfileAndCanGoBackToSettings() {
        tap(app.buttons["profile-photo-button"])
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        XCTAssertTrue(app.buttons["change-profile-photo"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        saveScreen("Home avatar route leads through the Settings tab")
    }
    func testCameraDeniedIsHandledOnlyWhenCameraIsUsed() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--camera-denied-test"]; app.launch()
        XCTAssertFalse(app.buttons["camera-open-settings"].exists)
        tap(app.buttons["open-shopping"])
        tap(app.buttons["shopping-scan-label"])
        XCTAssertTrue(app.buttons["camera-open-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Camera access needed"].exists)
        saveScreen("Camera denied after scan action with recovery route")
        tap(app.buttons["Close"])
        XCTAssertTrue(app.buttons["shopping-scan-label"].waitForExistence(timeout: 5))
    }
    func testExpiredRememberedSignInStillOpensSavedLedgerPromptly() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--auth-startup-test", "--expired-auth-test"]
        let started = Date()
        app.launch()
        XCTAssertTrue(app.buttons["Record Purchase"].waitForExistence(timeout: 3))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
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
    func testShoppingModeAddsDirectlyWithoutCategoryOrAccount() {
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        tap(app.buttons["open-shopping"])
        XCTAssertTrue(app.buttons["shopping-scan-label"].exists)
        XCTAssertFalse(app.buttons["shopping-add-cart"].isEnabled)
        XCTAssertTrue(app.pickerWheels.firstMatch.exists)
        XCTAssertFalse(app.buttons["Increase quantity"].exists)
        enter("Item or purchase name", "Donut")
        enter("shopping-unit-price", "2.50")
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "2")
        XCTAssertTrue((app.pickerWheels.firstMatch.value as? String ?? "").hasPrefix("2"))
        tap(app.buttons["shopping-add-cart"])
        XCTAssertTrue(app.staticTexts["shopping-cart-confirmation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Shopping Mode"].exists)
        XCTAssertFalse(app.navigationBars["Shopping Item"].exists)
        XCTAssertFalse(app.buttons["shopping-add-cart"].isEnabled)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        reveal(app.textFields["Item or purchase name"])
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shopping Mode direct cart"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap(app.buttons["Done"])
        app.tabBars.buttons["Activity"].tap()
        XCTAssertFalse(app.buttons.containing(.staticText, identifier: "Donut").firstMatch.exists)
        restart()
        app.tabBars.buttons["Groceries"].tap()
        let donut = app.buttons.containing(.staticText, identifier: "Donut").firstMatch
        XCTAssertTrue(donut.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.containing(.staticText, identifier: "Donut").count, 1)
        XCTAssertTrue(donut.staticTexts["2 × each · Planned"].exists)
        XCTAssertTrue(donut.staticTexts["$5.00"].exists)
    }
    func testShoppingModeNameOnlyCart() {
        tap(app.buttons["open-shopping"])
        enter("Item or purchase name", "Ice cream")
        tap(app.buttons["shopping-add-cart"])
        XCTAssertTrue(app.staticTexts["shopping-cart-confirmation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shopping Mode name-only cart"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap(app.buttons["Done"])
        app.tabBars.buttons["Groceries"].tap()
        XCTAssertTrue(app.staticTexts["Ice cream"].waitForExistence(timeout: 5))
    }
    func testShoppingModeQuantityFlowsIntoPurchaseAndLinksCart() {
        accounts(); addAccount("Checking", "100.00")
        app.tabBars.buttons["Home"].tap(); tap(app.buttons["open-shopping"])
        enter("Item or purchase name", "Donut")
        enter("shopping-unit-price", "2.50")
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "2")
        tap(app.buttons["Category, Choose an envelope"])
        tap(app.collectionViews.buttons["Food & coffee"])
        XCTAssertTrue(app.staticTexts["Cash after purchase & bills, $95.00"].exists)
        tap(app.buttons["shopping-add-cart"])
        tap(app.buttons["shopping-record-purchase"])
        XCTAssertEqual(app.textFields["Amount (USD)"].value as? String, "5.00")
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.navigationBars["Add manual expense"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved in today’s purchases."].exists)
        XCTAssertFalse(app.buttons["shopping-record-purchase"].isEnabled)
        tap(app.buttons["Done"])
        app.tabBars.buttons["Groceries"].tap()
        let donut = app.buttons.containing(.staticText, identifier: "Donut").firstMatch
        XCTAssertTrue(donut.staticTexts["2 × each · Purchased"].exists)
        accounts(); tap(app.buttons["account-Checking"])
        XCTAssertTrue(app.staticTexts["Available balance, $95.00"].exists)
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
        tap(app.buttons["expense-paid-from"])
        tap(app.buttons["Cash wallet"])
        tap(app.navigationBars.buttons["Save"])
        XCTAssertTrue(app.navigationBars["Add manual expense"].waitForNonExistence(timeout: 5))
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
        let shop = app.textFields["plan-store"]
        tap(shop); shop.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Target")
        tap(app.navigationBars["Edit Shopping Plan"].buttons["Save"])
        XCTAssertTrue(app.staticTexts["Store, Target"].waitForExistence(timeout: 5))
        restart(); app.tabBars.buttons["Groceries"].tap(); tap(app.buttons["Next day"])
        XCTAssertTrue(app.staticTexts["apples"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Target"].exists)
    }
}
