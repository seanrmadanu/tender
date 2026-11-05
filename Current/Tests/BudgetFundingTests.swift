import XCTest
@testable import TenderCore

final class BudgetFundingTests: XCTestCase {
    private func funded() -> Ledger {
        var ledger = Ledger.empty()
        ledger.accounts = [Account(name: "Checking", available: 50_000, bankAccountKey: "production:checking")]
        return ledger
    }
    private func transaction(_ id: String = "coffee", amount: Int64 = 1000, pending: Bool = false, transfer: Bool = false, currency: String = "USD", day: Date = Date()) -> BankTransaction {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        return BankTransaction(id: "production:bank:" + id, accountKey: "production:checking", merchant: "Coffee", amountCents: amount, currency: currency, date: formatter.string(from: day), pending: pending, category: "FOOD_AND_DRINK", isTransfer: transfer)
    }
    func testFiveHundredMinusTwoHundredFixedCapsBudgetAtThreeHundredAtomically() throws {
        var ledger = funded()
        let rent = FixedExpense(name: "Rent", amount: 20_000)
        try ledger.saveFixedExpense(rent)
        XCTAssertEqual(ledger.available, 50_000); XCTAssertEqual(ledger.fixedReserve(), 20_000); XCTAssertEqual(ledger.budgetCapacity(), 30_000)
        var amounts = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, Int64(0)) })
        amounts[ledger.categories[0].id] = 15_000
        try ledger.setMonthlyAllocations(amounts, total: 30_000)
        let before = ledger
        XCTAssertThrowsError(try ledger.setMonthlyAllocations(amounts, total: 30_001)); XCTAssertEqual(ledger, before)
        amounts[ledger.categories[0].id] = 30_001
        XCTAssertThrowsError(try ledger.setMonthlyAllocations(amounts, total: 30_000)); XCTAssertEqual(ledger, before)
        var category = ledger.categories[0]; category.limit = 30_001
        XCTAssertThrowsError(try ledger.setCategoryAllocation(category)); XCTAssertEqual(ledger, before)
    }
    func testPaidFixedExpenseIsNotReservedOrChargedTwiceAndResetsNextMonth() throws {
        var ledger = funded(); ledger.accounts[0].bankAccountKey = nil
        let rent = FixedExpense(name: "Rent", amount: 20_000); try ledger.saveFixedExpense(rent)
        try ledger.record(Expense(merchant: "Rent", amount: 5000, categoryID: ledger.categories[4].id, accountID: ledger.accounts[0].id, fixedExpenseID: rent.id))
        XCTAssertEqual(ledger.fixedReserve(), 15_000); XCTAssertEqual(ledger.budgetCapacity(), 30_000)
        try ledger.record(Expense(merchant: "Rent balance", amount: 15_000, categoryID: ledger.categories[4].id, accountID: ledger.accounts[0].id, fixedExpenseID: rent.id))
        XCTAssertEqual(ledger.available, 30_000); XCTAssertEqual(ledger.fixedReserve(), 0); XCTAssertEqual(ledger.budgetCapacity(), 30_000)
        XCTAssertEqual(ledger.spent(in: ledger.month()), 20_000); XCTAssertEqual(ledger.envelopeSpent(in: ledger.month()), 0)
        let next = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        XCTAssertEqual(ledger.fixedReserve(at: next), 20_000)
    }
    func testActivityIncludesUnassignedPostedBankPurchasesAndExcludesPendingCreditsAndTransfers() throws {
        var ledger = funded()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [transaction(), transaction("pending", pending: true), transaction("transfer", transfer: true), transaction("credit", amount: -2000), transaction("foreign", currency: "CAD")])])
        let report = SpendingSummary(entries: ledger.spendingEntries(in: ledger.month()))
        XCTAssertEqual(report.total, 1000); XCTAssertEqual(report.unassigned, 1000); XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(ledger.expenses.count, 0)
    }
    func testApplyingSuggestionsIsIdempotentAndDoesNotDeductBankBalance() throws {
        var ledger = funded(); let purchase = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [purchase])])
        let balances = ledger.accounts
        XCTAssertEqual(try ledger.categorizeSuggestedPurchases(in: ledger.month()), 1)
        XCTAssertEqual(try ledger.categorizeSuggestedPurchases(in: ledger.month()), 0)
        XCTAssertEqual(ledger.accounts, balances); XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.expenses[0].categoryID, ledger.categories[1].id)
        XCTAssertEqual(ledger.spent(in: ledger.month()), 1000)
        XCTAssertEqual(SpendingSummary(entries: ledger.spendingEntries(in: ledger.month())).unassigned, 0)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [transaction(amount: 1200)])])
        XCTAssertEqual(ledger.spent(in: ledger.month()), 1200)
    }
    func testExactManualReceiptIsCountedOnceBeforeAndAfterConfirmedBankMatch() throws {
        var ledger = funded(); let purchase = transaction()
        let receipt = Expense(merchant: "COFFEE", amount: 1000, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id, date: Date())
        try ledger.record(receipt, deductFromBalance: false)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [purchase])])
        XCTAssertEqual(ledger.spent(in: ledger.month()), 1000)
        XCTAssertEqual(try ledger.categorizeSuggestedPurchases(in: ledger.month()), 1)
        XCTAssertEqual(ledger.expenses.count, 1); XCTAssertEqual(ledger.expenses[0].id, receipt.id)
        XCTAssertEqual(ledger.expenses[0].bankTransactionID, purchase.id)
        XCTAssertEqual(ledger.spent(in: ledger.month()), 1000)
    }
    func testUncertainReceiptMatchRequiresReviewAndDoesNotCreateAnotherExpense() throws {
        var ledger = funded(); let purchase = transaction()
        try ledger.record(Expense(merchant: "Different purchase", amount: 1000, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id), deductFromBalance: false)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [purchase])])
        XCTAssertEqual(try ledger.categorizeSuggestedPurchases(in: ledger.month()), 0)
        XCTAssertEqual(ledger.expenses.count, 1); XCTAssertNil(ledger.expenses[0].bankTransactionID)
    }
    func testFixedReservesRoundTripAndArchivedReservesCanBeRestored() throws {
        var ledger = funded(); let rent = FixedExpense(name: "Rent", amount: 20_000); try ledger.saveFixedExpense(rent)
        let data = try JSONEncoder.tender.encode(LedgerArchive(ledger: ledger, attachments: [:]).validated())
        var restored = try JSONDecoder.tender.decode(LedgerArchive.self, from: data).validated().ledger
        XCTAssertEqual(restored.budgetCapacity(), 30_000)
        restored.fixedExpenses?[0].archivedAt = Date(); XCTAssertEqual(restored.budgetCapacity(), 50_000)
        restored.fixedExpenses?[0].archivedAt = nil; XCTAssertEqual(restored.budgetCapacity(), 30_000)
        var invalid = rent; invalid.amount = -1
        XCTAssertThrowsError(try restored.saveFixedExpense(invalid)); XCTAssertEqual(restored.fixedExpenses?[0].amount, 20_000)
    }
    func testLegacyOverfundedPlanStillLoadsButCannotBeIncreased() throws {
        var ledger = funded(); ledger.monthlyAllocation = 100_000
        let restored = try JSONDecoder.tender.decode(Ledger.self, from: JSONEncoder.tender.encode(ledger)).validated()
        XCTAssertEqual(restored.monthlyBudget, 100_000)
        XCTAssertThrowsError(try ledger.setMonthlyAllocations(Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, $0.limit) }), total: 100_001))
    }
    func testArchivedBankExpenseDoesNotReappearInActivityUntilRestored() throws {
        var ledger = funded(); let purchase = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [purchase])])
        try ledger.recordBankPurchase(purchase, categoryID: ledger.categories[1].id)
        let id = ledger.expenses[0].id; ledger.archiveExpense(id)
        XCTAssertEqual(ledger.spent(in: ledger.month()), 0)
        try ledger.restoreExpense(id); XCTAssertEqual(ledger.spent(in: ledger.month()), 1000)
    }
    func testPostedFixedPaymentReleasesReserveWithoutDeductingImportedBalance() throws {
        var ledger = funded()
        // Current bank balance already reflects the rent payment.
        ledger.accounts[0].available = 30_000
        let rent = FixedExpense(name: "Rent", amount: 20_000); try ledger.saveFixedExpense(rent)
        let payment = transaction("rent", amount: 20_000)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [payment])])
        try ledger.recordBankPurchase(payment, categoryID: ledger.categories[4].id)
        ledger.expenses[0].fixedExpenseID = rent.id
        XCTAssertEqual(ledger.available, 30_000)
        XCTAssertEqual(ledger.fixedPaid(rent), 20_000); XCTAssertEqual(ledger.fixedReserve(), 0)
        XCTAssertEqual(ledger.budgetCapacity(), 30_000)
        XCTAssertEqual(ledger.spent(in: ledger.month()), 20_000)
        XCTAssertEqual(ledger.envelopeSpent(in: ledger.month()), 0)
    }
    func testGroceriesSuggestionTakesPriorityOverFoodAndDrinkPrimaryCategory() {
        let ledger = funded()
        var groceries = transaction(); groceries.category = "FOOD_AND_DRINK_GROCERIES"
        XCTAssertEqual(ledger.suggestedCategory(for: groceries)?.symbol, "carrot")
    }
}
