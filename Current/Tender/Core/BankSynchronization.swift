import Foundation

public struct BankAccountDetails: Codable, Equatable, Sendable {
    public var itemID: String?
    public var institutionName: String?
    public var bankName: String
    public var mask: String?
    public var currentBalance: Int64?
    public var currency: String
    public var officialName: String? = nil
    public var accountType: String? = nil
    public var accountSubtype: String? = nil
}
public struct BankSyncRecord: Codable, Equatable, Sendable {
    public var balancesCheckedAt: Date?
    public var activityCheckedAt: Date?
    public var pendingImport: Bool = false
}
struct BankSyncResult {
    var added = 0
    var updated = 0
    var unavailable = 0
}
extension Ledger {
    /// Bank balances are authoritative for linked accounts. Cash and manual
    /// accounts are never guessed/matched by name or deducted a second time.
    mutating func synchronizeBankAccounts(_ snapshots: [BankSnapshot], environment: String, reauthorized: Bool = false, now: Date = Date()) throws -> BankSyncResult {
        guard environment == "production", !isDemo, snapshots.count <= 10_000,
              Set(snapshots.map(\.id)).count == snapshots.count,
              snapshots.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.retrievedAt <= now.addingTimeInterval(300) &&
                  ($0.availableCents?.magnitude ?? 0) <= 99_999_999_999 && ($0.currentCents?.magnitude ?? 0) <= 99_999_999_999 }) else { throw LedgerError.invalidBackup }
        var result = BankSyncResult()
        for snapshot in snapshots {
            guard snapshot.currency == "USD", let amount = snapshot.availableCents else { result.unavailable += 1; continue }
            let key = environment + ":" + snapshot.id
            let details = snapshot.details
            if let i = accounts.firstIndex(where: { $0.bankAccountKey == key }) {
                if (archivedCards ?? []).contains(where: { $0.id == accounts[i].id }) { continue }
                guard accounts[i].isCash != true else { throw LedgerError.invalidBackup }
                guard accounts[i].needsReconnection != true || reauthorized else { result.unavailable += 1; continue }
                guard snapshot.retrievedAt >= (accounts[i].snapshotAt ?? .distantPast) else { result.unavailable += 1; continue }
                // Preserve wallet removal, user naming, expenses and receipts.
                // Advancing the revision prevents old expense deletion from refunding a bank balance.
                setBalance(accountID: accounts[i].id, available: amount)
                accounts[i].snapshotAt = snapshot.retrievedAt
                accounts[i].updated = snapshot.retrievedAt
                accounts[i].source = "Plaid"
                accounts[i].bankDetails = details
                accounts[i].needsReconnection = false
                result.updated += 1
            } else {
                accounts.append(Account(name: snapshot.displayName, available: amount, updated: snapshot.retrievedAt,
                    source: "Plaid", snapshotAt: snapshot.retrievedAt, balanceRevision: UUID(), bankAccountKey: key,
                    bankDetails: details))
                result.added += 1
            }
        }
        let received = Set(snapshots.map { environment + ":" + $0.id })
        result.unavailable += accounts.filter { $0.isArchived != true && $0.bankAccountKey.map { !received.contains($0) } == true }.count
        return result
    }
}
