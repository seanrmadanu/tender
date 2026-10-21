import XCTest
@testable import TenderCore

final class LedgerTests: XCTestCase {
    func testMoneyParsingNeverUsesFloatingPoint() {
        XCTAssertEqual(Money.cents("0.29"), 29)
        XCTAssertEqual(Money.cents("12.3"), 1230)
        XCTAssertEqual(Money.cents("999999999.99"), 99_999_999_999)
        for invalid in ["-1", "1.234", "nan", "1e9", "1,000", "1000000000", "", "1.", "€5"] { XCTAssertNil(Money.cents(invalid), invalid) }
    }
    func testExpenseDeductsExactlyAndRejectsInvalidReferences() throws {
        var ledger = Ledger.empty()
        let account = Account(name: "Cash", available: 10000)
        ledger.accounts = [account]
        try ledger.record(Expense(merchant: "Shop", amount: 29, categoryID: ledger.categories[0].id, accountID: account.id))
        XCTAssertEqual(ledger.available, 9971)
        XCTAssertEqual(ledger.spent(in: ledger.month()), 29)
        XCTAssertThrowsError(try ledger.record(Expense(merchant: "Shop", amount: 500, categoryID: UUID(), accountID: account.id)))
        XCTAssertEqual(ledger.available, 9971)
        XCTAssertThrowsError(try ledger.record(Expense(merchant: "Tomorrow", amount: 500, categoryID: ledger.categories[0].id, accountID: account.id, date: Date().addingTimeInterval(86400))))
    }
    func testShoppingRequiresCashAndCategoryAndReservesBills() throws {
        var ledger = Ledger.empty()
        ledger.accounts = [Account(name: "Checking", available: 10000)]
        let category = BudgetCategory(name: "Food", symbol: "carrot", limit: 5000)
        ledger.categories = [category]
        ledger.recurring = [RecurringBill(name: "Bill", amount: 8000, categoryID: category.id, nextDue: Date().addingTimeInterval(86400))]
        XCTAssertFalse(ledger.shopping(amount: 2500, category: category).fits)
        XCTAssertTrue(ledger.shopping(amount: 2000, category: category).fits)
        ledger.accounts = []
        XCTAssertFalse(ledger.shopping(amount: 1, category: category).fits)
        XCTAssertFalse(ledger.shopping(amount: 0, category: category).fits)
    }
    func testMonthBoundaryIsExclusive() {
        var ledger = Ledger.empty()
        let end = ledger.month().end
        let a = Account(name: "Account", available: 1000); ledger.accounts = [a]
        ledger.expenses = [Expense(merchant: "At boundary", amount: 300, categoryID: ledger.categories[0].id, accountID: a.id, date: end)]
        XCTAssertEqual(ledger.spent(in: ledger.month()), 0)
    }
    func testDeletingOldExpenseDoesNotInflateNewBalanceSnapshot() throws {
        var ledger = Ledger.empty()
        let account = Account(name: "Cash", available: 10000)
        ledger.accounts = [account]
        let expense = Expense(merchant: "Shop", amount: 2000, categoryID: ledger.categories[0].id, accountID: account.id)
        try ledger.record(expense)
        ledger.setBalance(accountID: account.id, available: 5000)
        ledger.removeExpense(id: expense.id)
        XCTAssertEqual(ledger.available, 5000)
        try ledger.record(expense)
        XCTAssertEqual(ledger.available, 3000)
        ledger.removeExpense(id: expense.id)
        XCTAssertEqual(ledger.available, 5000)
    }
    func testHistoricalExpenseCanLeaveCashUnchanged() throws {
        var ledger = Ledger.empty()
        let account = Account(name: "Cash", available: 10000)
        ledger.accounts = [account]
        let expense = Expense(merchant: "History", amount: 2000, categoryID: ledger.categories[0].id, accountID: account.id)
        try ledger.record(expense, deductFromBalance: false)
        XCTAssertEqual(ledger.available, 10000)
        XCTAssertEqual(ledger.spent(in: ledger.month()), 2000)
        ledger.removeExpense(id: expense.id)
        XCTAssertEqual(ledger.available, 10000)
    }
    func testReserveIncludesWeeklyOccurrencesAndSingleOverdue() {
        var ledger = Ledger.empty()
        let today = Calendar.current.startOfDay(for: Date())
        ledger.recurring = [RecurringBill(name: "Weekly", amount: 100, categoryID: ledger.categories[0].id, nextDue: today, cycle: .weekly)]
        XCTAssertEqual(ledger.upcomingReserve(at: today), 500)
        ledger.recurring[0].nextDue = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        XCTAssertEqual(ledger.upcomingReserve(at: today), 500)
    }
    func testGroceryEstimateUsesFiveNewestPricesAndQuantity() {
        let now = Date()
        let item = GroceryItem(name: "Milk", quantity: 2, observations: (0..<6).map { PriceObservation(price: Int64(($0 + 1) * 100), store: "Shop", date: now.addingTimeInterval(Double($0))) })
        XCTAssertEqual(item.estimatedUnitPrice, 400)
    }
    func testBackupValidationRejectsUnsafeFilesAndBrokenReferences() throws {
        var ledger = Ledger.sample()
        _ = try ledger.validated()
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: data), ledger)
        ledger.expenses[0].attachment = "../secret"
        XCTAssertThrowsError(try ledger.validated())
        ledger.expenses[0].attachment = nil
        ledger.expenses[0].categoryID = UUID()
        XCTAssertThrowsError(try ledger.validated())
    }

    func testMonthlyRenewalKeepsOriginalDayAcrossFebruary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 31))!
        var bill = RecurringBill(name: "Renewal", amount: 100, categoryID: UUID(), nextDue: january, recurrenceAnchor: january)
        bill.nextDue = bill.advanced(calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: bill.nextDue), 28)
        bill.nextDue = bill.advanced(calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: bill.nextDue), 3)
        XCTAssertEqual(calendar.component(.day, from: bill.nextDue), 31)
    }

    func testYearlyRenewalReturnsToLeapDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let leapDay = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29))!
        var bill = RecurringBill(name: "Annual", amount: 100, categoryID: UUID(), nextDue: leapDay, cycle: .yearly, recurrenceAnchor: leapDay)
        for _ in 0..<4 { bill.nextDue = bill.advanced(calendar: calendar) }
        XCTAssertEqual(calendar.component(.year, from: bill.nextDue), 2028)
        XCTAssertEqual(calendar.component(.day, from: bill.nextDue), 29)
    }

    func testDuplicateBankBalancesAreRejected() throws {
        var ledger = Ledger.empty()
        ledger.accounts = [Account(name: "Checking", available: 1000, bankAccountKey: "production:one")]
        _ = try ledger.validated()
        ledger.accounts.append(Account(name: "Same bank again", available: 1000, bankAccountKey: "production:one"))
        XCTAssertThrowsError(try ledger.validated())
    }

    func testCompleteBackupRoundTripsPhotosAndRejectsMissingOrExtraFiles() throws {
        var ledger = Ledger.sample()
        ledger.expenses[0].attachment = "receipt.jpg"
        ledger.groceries[0].observations[0].photo = "price.jpg"
        let images = ["receipt.jpg": Data([1, 2, 3]), "price.jpg": Data([4, 5, 6])]
        let archive = try LedgerArchive(ledger: ledger, attachments: images).validated()
        let restored = try JSONDecoder().decode(LedgerArchive.self, from: JSONEncoder().encode(archive)).validated()
        XCTAssertEqual(restored.ledger, ledger)
        XCTAssertEqual(restored.attachments, images)
        XCTAssertThrowsError(try LedgerArchive(ledger: ledger, attachments: ["receipt.jpg": Data([1])]).validated())
        var extra = images; extra["../outside.jpg"] = Data([1])
        XCTAssertThrowsError(try LedgerArchive(ledger: ledger, attachments: extra).validated())
        var renamed = restored.ledger
        renamed.renameAttachments(["receipt.jpg": "fresh-receipt.jpg", "price.jpg": "fresh-price.jpg"])
        XCTAssertEqual(renamed.attachmentNames, Set(["fresh-receipt.jpg", "fresh-price.jpg"]))
        _ = try renamed.validated()
    }

    func testOldLedgerWithoutNewOptionalFieldsStillDecodes() throws {
        let original = Ledger.sample()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var accounts = try XCTUnwrap(object["accounts"] as? [[String: Any]])
        for i in accounts.indices { accounts[i].removeValue(forKey: "bankAccountKey") }
        object["accounts"] = accounts
        var bills = try XCTUnwrap(object["recurring"] as? [[String: Any]])
        for i in bills.indices { bills[i].removeValue(forKey: "recurrenceAnchor") }
        object["recurring"] = bills
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        XCTAssertEqual(restored, original)
    }
}
