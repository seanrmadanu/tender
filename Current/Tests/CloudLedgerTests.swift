import XCTest
@testable import TenderCore

final class CloudLedgerTests: XCTestCase {
    private func funded() -> Ledger {
        var l = Ledger.empty(); l.accounts = [Account(name: "Cash", available: 50000, isCash: true)]; return l
    }
    func testDisjointPhoneAndAssistantChangesMergeWithoutOverwritingEither() throws {
        let base = funded(); var local = base, remote = base
        local.categories[0].name = "Food shopping"
        var expense = Expense(merchant: "AI lunch", amount: 1200, categoryID: base.categories[0].id, accountID: base.accounts[0].id)
        expense.assistantOrigin = AssistantOrigin(provider: .chatgpt, actionID: UUID().uuidString, createdAt: Date())
        try remote.record(expense, deductFromBalance: false)
        let merged = try CloudLedgerMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.categories[0].name, "Food shopping"); XCTAssertEqual(merged.expenses.count, 1)
        XCTAssertEqual(merged.expenses[0].assistantOrigin?.provider, .chatgpt)
    }
    func testConcurrentEditsAndDeleteVersusEditRequireReview() throws {
        var base = funded()
        try base.record(Expense(merchant: "Market", amount: 1000, categoryID: base.categories[0].id, accountID: base.accounts[0].id))
        var local = base, remote = base
        local.expenses[0].note = "Phone note"; remote.expenses[0].note = "Cloud note"
        XCTAssertThrowsError(try CloudLedgerMerge.merge(base: base, local: local, remote: remote))
        local = base; local.expenses = []
        XCTAssertThrowsError(try CloudLedgerMerge.merge(base: base, local: local, remote: remote))
        XCTAssertEqual(base.expenses[0].note, "")
    }
    func testConcurrentCashChangesConflictInsteadOfLosingACharge() throws {
        let base = funded(); var local = base, remote = base
        local.accounts[0].available -= 1000; remote.accounts[0].available -= 1200
        XCTAssertThrowsError(try CloudLedgerMerge.merge(base: base, local: local, remote: remote))
    }
    func testOriginSurvivesNormalEditsArchiveRestoreAndCompleteBackup() throws {
        var ledger = funded()
        var e = Expense(merchant: "Lunch", amount: 1200, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        e.assistantOrigin = AssistantOrigin(provider: .claude, actionID: UUID().uuidString, createdAt: Date(timeIntervalSince1970: 1700000000))
        try ledger.record(e); ledger.expenses[0].note = "Edited by the user"
        ledger.archiveExpense(e.id); try ledger.restoreExpense(e.id)
        let restored = try JSONDecoder.tender.decode(LedgerArchive.self, from: JSONEncoder.tender.encode(LedgerArchive(ledger: ledger, attachments: [:]))).validated().ledger
        XCTAssertEqual(restored.expenses[0].assistantOrigin, e.assistantOrigin)
        XCTAssertEqual(restored.expenses[0].note, "Edited by the user")
    }
    func testSharedServerFixtureHasIdenticalFundingAndAllocationLimits() throws {
        struct Fixture: Decodable { var now: Date; var timeZone: String; var expectedAvailableCents: Int64; var ledger: Ledger }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "shared/assistant-funding.json")
        var fixture = try JSONDecoder.tender.decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.ledger.budgetCapacity(at: fixture.now), fixture.expectedAvailableCents)
        let amounts = Dictionary(uniqueKeysWithValues: fixture.ledger.categories.map { ($0.id, Int64(0)) })
        try fixture.ledger.setMonthlyAllocations(amounts, total: fixture.expectedAvailableCents)
        XCTAssertThrowsError(try fixture.ledger.setMonthlyAllocations(amounts, total: fixture.expectedAvailableCents + 1))
    }
    func testFirstConnectionCannotReplaceExistingPhoneRecordsSilently() throws {
        XCTAssertThrowsError(try CloudLedgerMerge.merge(base: nil, local: funded(), remote: funded()))
        let remote = funded(), merged = try CloudLedgerMerge.merge(base: nil, local: .empty(), remote: remote)
        XCTAssertEqual(merged.accounts, remote.accounts)
    }
    func testManualCorrectionsAdjustOnlyTheStillAppliedSnapshotAndKeepOrigin() throws {
        var ledger = funded()
        var e = Expense(merchant: "AI lunch", amount: 1200, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        e.assistantOrigin = AssistantOrigin(provider: .chatgpt, actionID: UUID().uuidString, createdAt: Date())
        try ledger.record(e)
        let original = ledger.expenses[0]
        try ledger.editManualExpense(original: original, merchant: "Corrected lunch", amount: 1500, date: original.date, categoryID: original.categoryID, note: "Correction")
        XCTAssertEqual(ledger.accounts[0].available, 48500)
        XCTAssertEqual(ledger.expenses[0].assistantOrigin, original.assistantOrigin)
        XCTAssertThrowsError(try ledger.editManualExpense(original: original, merchant: "Stale edit", amount: 1000, date: original.date, categoryID: original.categoryID, note: ""))
        ledger.setBalance(accountID: ledger.accounts[0].id, available: 42000)
        try ledger.editManualExpense(original: ledger.expenses[0], merchant: "Corrected lunch", amount: 1600, date: original.date, categoryID: original.categoryID, note: "Historical correction")
        XCTAssertEqual(ledger.accounts[0].available, 42000)
        ledger.archiveExpense(e.id)
        XCTAssertEqual(ledger.accounts[0].available, 42000)
    }
}
