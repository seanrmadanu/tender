import XCTest
@testable import TenderCore

final class PersonalFeatureTests: XCTestCase {
    private func transaction(_ id: String = "one", amount: Int64 = 499, date: String = "2026-01-10", pending: Bool = false, transfer: Bool = false) -> BankTransaction {
        BankTransaction(id: "production:bank:" + id, accountKey: "production:checking", merchant: "Example Shop", amountCents: amount, currency: "USD", date: date, pending: pending, category: "GENERAL_MERCHANDISE", isTransfer: transfer)
    }
    private func ledger() -> Ledger {
        var ledger = Ledger.empty()
        ledger.accounts = [Account(name: "Checking", available: 10000, bankAccountKey: "production:checking")]
        return ledger
    }
    func testBankImportDoesNotDeductAndIsIdempotent() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
        XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id)
        XCTAssertEqual(ledger.accounts[0].available, 10000)
        XCTAssertThrowsError(try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id))
        XCTAssertEqual(ledger.expenses.count, 1)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [transaction(amount: 599)])])
        XCTAssertEqual(ledger.expenses[0].amount, 599)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [])])
        XCTAssertTrue(ledger.expenses.isEmpty); XCTAssertEqual(ledger.available, 10000)
    }
    func testMatchingReceiptDoesNotDoubleCountOrChangeOriginalAmount() throws {
        var ledger = ledger(); let t = transaction()
        let receipt = Expense(merchant: "Receipt", amount: 499, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        try ledger.record(receipt)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id, matching: receipt.id)
        XCTAssertEqual(ledger.expenses.count, 1); XCTAssertEqual(ledger.available, 9501)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [transaction(amount: 699)])])
        XCTAssertEqual(ledger.expenses[0].amount, 499)
    }
    func testPendingCreditsAndTransfersCannotEnterExpenseTotals() throws {
        for t in [transaction(pending: true), transaction(transfer: true), transaction(amount: -100)] {
            var ledger = ledger()
            try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
            XCTAssertThrowsError(try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id))
            XCTAssertEqual(ledger.expenses.count, 0)
        }
    }
    func testDisconnectDoesNotDeleteRecordedHistory() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id)
        try ledger.receiveBankActivity([])
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.bankActivity?.first?.transactions.count, 1)
    }
    func testCashPurchaseChangesOnlyCashWallet() throws {
        var ledger = ledger()
        let wallet = Account(name: "Cash", available: 2000, isCash: true); ledger.accounts.append(wallet)
        try ledger.record(Expense(merchant: "Cash purchase", amount: 500, categoryID: ledger.categories[0].id, accountID: wallet.id))
        XCTAssertEqual(ledger.accounts[0].available, 10000); XCTAssertEqual(ledger.accounts[1].available, 1500)
    }
    func testReceiptExtractsTotalItemsDateAndMaskedPayment() {
        let receipt = ReceiptParser.parse("Corner Market\n10/20/2026\n2 x Ice Cream 8.00\nMilk 3.50\nSubtotal 11.50\nTax 0.90\nTOTAL 12.40\nTotal Savings 1.00\nVISA ********1234")
        XCTAssertEqual(receipt.merchant, "Corner Market"); XCTAssertEqual(receipt.total, 1240)
        XCTAssertEqual(receipt.itemCount, 3); XCTAssertEqual(receipt.items.count, 2)
        XCTAssertNotNil(receipt.date); XCTAssertEqual(receipt.payment, "Visa ··1234")
        let noTotal = ReceiptParser.parse("Shop\nSubtotal 10.00\nTax 1.00\nChange 9.00")
        XCTAssertNil(noTotal.total)
    }
    func testShelfLabelDoesNotGuessAmbiguousOrPromotionalPrice() {
        XCTAssertEqual(ShelfLabelParser.parse("Oat Milk\n32 fl oz\n$3.49\nUnit price $0.11 / oz").price, 349)
        XCTAssertNil(ShelfLabelParser.parse("Ice Cream\n$4.99\nMember $3.99").price)
        XCTAssertNil(ShelfLabelParser.parse("Ice Cream\n2 for $5.00").price)
    }
    func testSpokenPlanFindsTomorrowStoreAndReminderTime() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        let draft = ShoppingPlanParser.parse("I want ice cream tomorrow when I go to Costco at 5 PM", now: now, calendar: calendar)
        XCTAssertEqual(draft.item, "ice cream"); XCTAssertEqual(draft.store, "Costco")
        XCTAssertEqual(calendar.component(.day, from: draft.date), 22)
        XCTAssertEqual(calendar.component(.hour, from: draft.date), 17)
        XCTAssertEqual(calendar.component(.hour, from: draft.date.addingTimeInterval(-3600)), 16)
        XCTAssertTrue(draft.hasExplicitTime)
        XCTAssertFalse(ShoppingPlanParser.parse("I want apples tomorrow", now: now, calendar: calendar).hasExplicitTime)
    }
    func testSubscriptionsRequireThreeRegularSimilarCharges() throws {
        var ledger = ledger()
        let values = [transaction("jan", date: "2026-01-10"), transaction("feb", date: "2026-02-10"), transaction("mar", date: "2026-03-10")]
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: values)])
        XCTAssertEqual(ledger.subscriptionSuggestions.count, 1)
        XCTAssertEqual(ledger.subscriptionSuggestions.first?.cycle, .monthly)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: Array(values.prefix(2)))])
        XCTAssertTrue(ledger.subscriptionSuggestions.isEmpty)
    }
    func testRestoredBankCanBeReauthorizedWithoutDuplicateAccount() throws {
        var ledger = ledger(); let id = ledger.accounts[0].id
        ledger.accounts[0].needsReconnection = true
        let snapshot = BankSnapshot(id: "new-provider-id", name: "Checking", currency: "USD", availableCents: 15000, retrievedAt: Date())
        try ledger.applyBankSnapshot(snapshot, environment: "production", matching: id)
        XCTAssertEqual(ledger.accounts.count, 1); XCTAssertEqual(ledger.accounts[0].id, id)
        XCTAssertEqual(ledger.accounts[0].needsReconnection, false)
    }
    func testLegacyJSONDecodesWithOptionalFeatureFields() throws {
        let original = Ledger.sample()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Ledger.self, from: data).validated()
        XCTAssertEqual(restored, original); XCTAssertNil(restored.bankActivity)
    }
    func testShelfLabelIgnoresNutritionServingFraction() {
        let label = ShelfLabelParser.parse("I 1/3 CUP SERVING\n210 CALORIES\n0g SATURATED FAT\n260mg SODIUM\n8g TOTAL SUGARS\nCHEERIOS\n$4.06")
        XCTAssertEqual(label.name, "CHEERIOS")
        XCTAssertEqual(label.price, 406)
        let missingName = ShelfLabelParser.parse("1/3 CUP SERVING\n210 CALORIES\n$4.06")
        XCTAssertNil(missingName.name)
        XCTAssertEqual(missingName.price, 406)
        XCTAssertNil(ShelfLabelParser.parse("1/3 CUP SERVING\nCereal\n2 for $5.00").price)
        XCTAssertNil(ShelfLabelParser.parse("Cereal\n2/$5.00").price)
    }
    func testShelfLabelWithTwoPricesOnOneLineNeedsReview() {
        XCTAssertNil(ShelfLabelParser.parse("Ice cream\nRegular $4.99 now $3.99").price)
        XCTAssertEqual(ShelfLabelParser.parse("Ice cream\n$3.99 $3.99").price, 399)
    }
    func testInformalShoppingPhraseAndDottedTime() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        let draft = ShoppingPlanParser.parse("i want to get ice cream tomorrow when im going costco at 5:30 p.m.", now: now, calendar: calendar)
        XCTAssertEqual(draft.item, "ice cream"); XCTAssertEqual(draft.store, "costco")
        XCTAssertEqual(calendar.component(.day, from: draft.date), 22)
        XCTAssertEqual(calendar.component(.hour, from: draft.date), 17)
        XCTAssertEqual(calendar.component(.minute, from: draft.date), 30)
        XCTAssertFalse(ShoppingPlanParser.parse("apples tomorrow at 5:99 p.m.", now: now, calendar: calendar).hasExplicitTime)
    }
    func testRemovedBankPurchaseReopensLinkedGroceryPlan() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [t])])
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id)
        ledger.groceries = [GroceryItem(name: "Apples", checked: true, plannedAt: Date(), purchasedAt: t.purchaseDate, expenseID: ledger.expenses[0].id)]
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [])])
        XCTAssertNil(ledger.groceries[0].expenseID)
        XCTAssertNil(ledger.groceries[0].purchasedAt)
        XCTAssertFalse(ledger.groceries[0].checked)
        XCTAssertEqual(ledger.available, 10000)
    }
}
