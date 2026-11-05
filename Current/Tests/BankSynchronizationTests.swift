import XCTest
@testable import TenderCore

final class BankSynchronizationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func snapshot(_ amount: Int64? = 10_000) -> BankSnapshot {
        BankSnapshot(id: "checking", name: "Checking", institutionName: "Example Bank", mask: "1234", currency: "USD", availableCents: amount, currentCents: 12_000, retrievedAt: date, itemID: "item")
    }
    func testAutomaticUpdatesPersistAndNeverDuplicateOrTouchManualCash() throws {
        var ledger = Ledger.empty()
        let manual = Account(name: "Checking", available: 900, updated: date), cash = Account(name: "Cash", available: 500, updated: date, isCash: true)
        ledger.accounts = [manual, cash]
        XCTAssertEqual(try ledger.synchronizeBankAccounts([snapshot()], environment: "production", now: date).added, 1)
        let id = ledger.accounts[2].id
        var newer = snapshot(7_500); newer.retrievedAt = date.addingTimeInterval(60); newer.name = "New bank name"
        _ = try ledger.synchronizeBankAccounts([newer], environment: "production", now: newer.retrievedAt)
        XCTAssertEqual(ledger.accounts.count, 3); XCTAssertEqual(ledger.accounts[2].id, id)
        XCTAssertEqual(ledger.accounts[2].available, 7_500)
        XCTAssertEqual(ledger.accounts[2].bankDetails?.bankName, "New bank name")
        XCTAssertEqual(ledger.accounts[0], manual); XCTAssertEqual(ledger.accounts[1], cash)
        ledger.bankSync = BankSyncRecord(balancesCheckedAt: newer.retrievedAt, activityCheckedAt: date)
        let restored = try JSONDecoder.tender.decode(Ledger.self, from: JSONEncoder.tender.encode(ledger))
        XCTAssertEqual(restored, ledger); XCTAssertEqual(restored.accounts[2].bankDetails?.itemID, "item")
    }
    func testMissingUnsupportedAndOlderBalancesKeepLastSavedValueAndDate() throws {
        var ledger = Ledger.empty()
        _ = try ledger.synchronizeBankAccounts([snapshot()], environment: "production", now: date)
        let saved = ledger.accounts[0]
        for value in [snapshot(nil), { var s = snapshot(20_000); s.currency = "EUR"; return s }(), { var s = snapshot(30_000); s.retrievedAt = date.addingTimeInterval(-60); return s }()] {
            XCTAssertEqual(try ledger.synchronizeBankAccounts([value], environment: "production", now: date).unavailable, 1)
            XCTAssertEqual(ledger.accounts[0], saved)
        }
    }
    func testAutomaticRefreshPreservesRemovedCardsAndRequiresReauthorizationAfterRestore() throws {
        var ledger = Ledger.empty()
        _ = try ledger.synchronizeBankAccounts([snapshot()], environment: "production", now: date)
        ledger.accounts[0].isArchived = true; ledger.accounts[0].needsReconnection = true
        XCTAssertEqual(try ledger.synchronizeBankAccounts([snapshot(8_000)], environment: "production", now: date).unavailable, 1)
        XCTAssertEqual(ledger.accounts[0].available, 10_000)
        _ = try ledger.synchronizeBankAccounts([snapshot(8_000)], environment: "production", reauthorized: true, now: date)
        XCTAssertEqual(ledger.accounts[0].available, 8_000); XCTAssertEqual(ledger.accounts[0].isArchived, true)
        XCTAssertEqual(ledger.accounts[0].needsReconnection, false); XCTAssertEqual(ledger.available, 0)
    }
    func testRefreshedBalanceIsNotRefundedWhenDeletingAnOldExpense() throws {
        var ledger = Ledger.empty()
        _ = try ledger.synchronizeBankAccounts([snapshot()], environment: "production", now: date)
        let expense = Expense(merchant: "Store", amount: 1_000, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        try ledger.record(expense, deductFromBalance: true)
        _ = try ledger.synchronizeBankAccounts([snapshot(8_000)], environment: "production", now: date)
        ledger.removeExpense(id: expense.id)
        XCTAssertEqual(ledger.accounts[0].available, 8_000)
    }
    func testInvalidProviderDataIsRejectedBeforeAnyMutation() throws {
        var ledger = Ledger.empty()
        XCTAssertThrowsError(try ledger.synchronizeBankAccounts([snapshot(), snapshot()], environment: "production", now: date))
        XCTAssertThrowsError(try ledger.synchronizeBankAccounts([snapshot()], environment: "sandbox", now: date))
        var invalid = snapshot(); invalid.retrievedAt = date.addingTimeInterval(600)
        XCTAssertThrowsError(try ledger.synchronizeBankAccounts([invalid], environment: "production", now: date))
        XCTAssertTrue(ledger.accounts.isEmpty)
    }
}
