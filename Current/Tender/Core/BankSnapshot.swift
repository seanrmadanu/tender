import Foundation

struct BankSnapshot: Decodable, Identifiable, Sendable {
    var id: String
    var name: String
    var institutionName: String? = nil
    var mask: String?
    var currency: String?
    var availableCents: Int64?
    var currentCents: Int64?
    var retrievedAt: Date
    var itemID: String? = nil
    var officialName: String? = nil
    var accountType: String? = nil
    var accountSubtype: String? = nil
}

extension BankSnapshot {
    var displayName: String {
        [institutionName, name, mask.map { "··" + $0 }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension Ledger {
    /// Each provider account has one stable ledger identity, across refreshes.
    mutating func applyBankSnapshot(_ snapshot: BankSnapshot, environment: String, matching manualID: UUID? = nil) throws {
        guard environment == "production", !isDemo, snapshot.currency == "USD",
              let amount = snapshot.availableCents, amount.magnitude <= 99_999_999_999,
              !snapshot.id.isEmpty else { throw LedgerError.invalidBackup }
        let key = environment + ":" + snapshot.id
        let linked = accounts.first { $0.bankAccountKey == key }
        if let id = linked?.id ?? manualID {
            guard let index = accounts.firstIndex(where: { $0.id == id }),
                  (accounts[index].bankAccountKey == nil || accounts[index].bankAccountKey == key || accounts[index].needsReconnection == true), accounts[index].isCash != true else { throw LedgerError.invalidBackup }
            setBalance(accountID: id, available: amount)
            accounts[index].bankAccountKey = key
            accounts[index].needsReconnection = false
            accounts[index].isArchived = false
            accounts[index].snapshotAt = snapshot.retrievedAt
            accounts[index].source = "Plaid snapshot"
            accounts[index].bankDetails = snapshot.details
        } else {
            accounts.append(Account(name: snapshot.displayName, available: amount, source: "Plaid snapshot", snapshotAt: snapshot.retrievedAt, balanceRevision: UUID(), bankAccountKey: key, bankDetails: snapshot.details))
        }
    }
}

extension BankSnapshot {
    var details: BankAccountDetails {
        BankAccountDetails(itemID: itemID, institutionName: institutionName, bankName: name, mask: mask,
            currentBalance: currentCents, currency: currency ?? "USD", officialName: officialName,
            accountType: accountType, accountSubtype: accountSubtype)
    }
}
