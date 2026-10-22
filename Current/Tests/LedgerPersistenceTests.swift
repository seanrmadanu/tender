import XCTest
@testable import TenderCore

final class LedgerPersistenceTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "TenderStartup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testUnchangedLedgerIsNotRewritten() throws {
        let root = try temporaryRoot(), file = root.appending(path: "ledger.json")
        var ledger = Ledger.empty()
        ledger.accounts = [Account(name: "Saved account", available: 12345)]
        let bytes = try JSONEncoder.tender.encode(ledger)
        try bytes.write(to: file)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        let loaded = try LedgerPersistence.load(root: root)
        XCTAssertEqual(loaded.accounts.first?.available, 12345)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, oldDate)
    }

    func testLegacyMigrationPreservesDataAndOnlyRunsOnce() throws {
        let root = try temporaryRoot()
        var ledger = Ledger.sample()
        ledger.freshStartVersion = nil
        let now = Date(timeIntervalSince1970: 1_792_627_200)
        let loaded = try LedgerPersistence.load(root: root, initial: ledger, now: now)
        XCTAssertEqual(loaded.accounts.map(\.id), ledger.accounts.map(\.id))
        XCTAssertEqual(loaded.expenses.map(\.id), ledger.expenses.map(\.id))
        XCTAssertEqual(loaded.freshStartVersion, 1)
        XCTAssertTrue(loaded.groceries.allSatisfy { $0.plannedAt == Calendar.current.startOfDay(for: now) })
        let file = root.appending(path: "ledger.json")
        let before = try Data(contentsOf: file)
        let second = try LedgerPersistence.load(root: root, now: now.addingTimeInterval(86400))
        XCTAssertEqual(second.groceries.map(\.plannedAt), loaded.groceries.map(\.plannedAt))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testUnreadableLedgerIsPreserved() throws {
        let root = try temporaryRoot(), file = root.appending(path: "ledger.json")
        let bytes = Data("not a valid ledger".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try LedgerPersistence.load(root: root))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testLargeBankHistoryLoadsWithoutRewrite() throws {
        let root = try temporaryRoot(), file = root.appending(path: "ledger.json")
        var ledger = Ledger.empty()
        ledger.bankActivity = [BankActivityItem(id: "fixture", checkedAt: Date(), transactions: (0..<10_000).map {
            BankTransaction(id: "fixture-\($0)", accountKey: "fixture-account", merchant: "Fixture store", amountCents: 100,
                            currency: "USD", date: "2026-10-01", pending: false, category: "GENERAL", isTransfer: false)
        })]
        try JSONEncoder.tender.encode(ledger).write(to: file)
        let before = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let started = ContinuousClock.now
        let loaded = try LedgerPersistence.load(root: root)
        print("Startup fixture: 10,000 bank records loaded in \(started.duration(to: .now))")
        XCTAssertEqual(loaded.bankActivity?.first?.transactions.count, 10_000)
        XCTAssertEqual(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, before)
    }
}
