import XCTest
@testable import TenderCore

final class MonthlyAllocationTests: XCTestCase {
    func testChangingAllocationsRecalculatesTotalsWithoutMovingMoneyOrPurchases() throws {
        var ledger = Ledger.empty()
        let account = Account(name: "Checking", available: 100_000)
        ledger.accounts = [account]
        try ledger.record(Expense(merchant: "Market", amount: 1_000, categoryID: ledger.categories[0].id, accountID: account.id))
        let before = ledger
        var amounts = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, $0.limit) })
        amounts[ledger.categories[0].id] = 25_000
        amounts[ledger.categories[1].id] = 7_550
        try ledger.setMonthlyAllocations(amounts, total: 99_000)
        XCTAssertEqual(ledger.monthlyBudget, 99_000)
        XCTAssertEqual(ledger.allocatedToEnvelopes, 32_550)
        XCTAssertEqual(ledger.unallocatedBudget, 66_450)
        XCTAssertEqual(ledger.remaining(ledger.categories[0]), 24_000)
        XCTAssertEqual(ledger.monthlyBudget - ledger.spent(in: ledger.month()), 98_000)
        XCTAssertEqual(ledger.accounts, before.accounts)
        XCTAssertEqual(ledger.expenses, before.expenses)
        XCTAssertEqual(ledger.recurring, before.recurring)
        XCTAssertEqual(ledger.groceries, before.groceries)
    }
    func testInvalidOrStaleAllocationSetsNeverPartiallyChangeBudgets() throws {
        var ledger = Ledger.empty()
        let before = ledger
        let valid = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, Int64(100)) })
        var invalid = valid; invalid[ledger.categories[1].id] = -1
        XCTAssertThrowsError(try ledger.setMonthlyAllocations(invalid)); XCTAssertEqual(ledger, before)
        invalid = valid; invalid[ledger.categories[1].id] = 100_000_000_000
        XCTAssertThrowsError(try ledger.setMonthlyAllocations(invalid)); XCTAssertEqual(ledger, before)
        invalid = valid; invalid.removeValue(forKey: ledger.categories[0].id)
        XCTAssertThrowsError(try ledger.setMonthlyAllocations(invalid)); XCTAssertEqual(ledger, before)
        invalid = valid; invalid[UUID()] = 100
        XCTAssertThrowsError(try ledger.setMonthlyAllocations(invalid)); XCTAssertEqual(ledger, before)
        try ledger.setMonthlyAllocations(Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, Int64(0)) }))
        XCTAssertEqual(ledger.monthlyBudget, 0)
    }
    func testSavedAllocationsRoundTripThroughCompleteBackup() throws {
        var ledger = Ledger.empty(); ledger.accounts = [Account(name: "Funding", available: 100_000)]
        let amounts = Dictionary(uniqueKeysWithValues: ledger.categories.enumerated().map { ($0.element.id, Int64($0.offset + 1) * 100) })
        try ledger.setMonthlyAllocations(amounts, total: 5_000)
        let archive = try LedgerArchive(ledger: ledger, attachments: [:]).validated()
        let restored = try JSONDecoder.tender.decode(LedgerArchive.self, from: JSONEncoder.tender.encode(archive))
        XCTAssertEqual(restored.ledger.categories, ledger.categories)
        XCTAssertEqual(restored.ledger.monthlyBudget, 5_000)
        XCTAssertEqual(restored.ledger.allocatedToEnvelopes, 2_100)
        XCTAssertEqual(restored.ledger.unallocatedBudget, 2_900)
    }
    func testAddingEditingArchivingAndRestoringEnvelopesKeepsTheOverallBudget() throws {
        var ledger = Ledger.empty(); ledger.accounts = [Account(name: "Funding", available: 100_000)]
        let initial = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, Int64(0)) })
        try ledger.setMonthlyAllocations(initial, total: 100_000)
        let added = BudgetCategory(name: "Extra envelope", symbol: "tag", limit: 10_000)
        ledger.categories.append(added)
        XCTAssertEqual(ledger.monthlyBudget, 100_000); XCTAssertEqual(ledger.unallocatedBudget, 90_000)
        var changed = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, $0.limit) })
        changed[added.id] = 20_000
        try ledger.setMonthlyAllocations(changed)
        XCTAssertEqual(ledger.monthlyBudget, 100_000); XCTAssertEqual(ledger.unallocatedBudget, 80_000)
        ledger.archiveCategories([added.id])
        XCTAssertEqual(ledger.monthlyBudget, 100_000); XCTAssertEqual(ledger.unallocatedBudget, 100_000)
        ledger.restoreCategory(added.id)
        XCTAssertEqual(ledger.monthlyBudget, 100_000); XCTAssertEqual(ledger.unallocatedBudget, 80_000)
    }
    func testLegacyBudgetFreezesAtItsOldSumOnceAndThenStaysIndependent() throws {
        var ledger = Ledger.empty(); ledger.monthlyAllocation = nil
        ledger.categories[0].limit = 25_000; ledger.categories[1].limit = 7_550
        let oldData = try JSONEncoder.tender.encode(ledger)
        ledger = try JSONDecoder.tender.decode(Ledger.self, from: oldData)
        XCTAssertEqual(ledger.monthlyBudget, 32_550)
        XCTAssertTrue(ledger.initializeMonthlyAllocationIfNeeded())
        ledger.categories.append(BudgetCategory(name: "New envelope", symbol: "tag", limit: 500))
        XCTAssertFalse(ledger.initializeMonthlyAllocationIfNeeded())
        XCTAssertEqual(ledger.monthlyBudget, 32_550)
        XCTAssertEqual(ledger.unallocatedBudget, -500)
    }
    func testTotalCanBeChangedWithoutEnvelopesOrAnyRedistribution() throws {
        var ledger = Ledger.empty(); ledger.accounts = [Account(name: "Funding", available: 100_000)]; ledger.categories = []
        try ledger.setMonthlyAllocations([:], total: 100_000)
        XCTAssertEqual(ledger.monthlyBudget, 100_000); XCTAssertEqual(ledger.unallocatedBudget, 100_000)
        try ledger.setMonthlyAllocations([:], total: 75_000)
        XCTAssertEqual(ledger.monthlyBudget, 75_000)
        let before = ledger
        XCTAssertThrowsError(try ledger.setMonthlyAllocations([:], total: -1))
        XCTAssertEqual(ledger, before)
    }
}
