import Foundation

public struct BankTransaction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var accountKey: String
    public var pendingID: String?
    public var merchant: String
    public var amountCents: Int64
    public var currency: String?
    public var date: String
    public var pending: Bool
    public var category: String
    public var isTransfer: Bool
    public var purchaseDate: Date? {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1900...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard let parsed = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: parsed) == year,
              calendar.component(.month, from: parsed) == month,
              calendar.component(.day, from: parsed) == day else { return nil }
        return parsed
    }
    public var canRecord: Bool { !pending && !isTransfer && currency == "USD" && amountCents > 0 && purchaseDate != nil }
}
public struct BankActivityItem: Codable, Equatable, Sendable {
    public var id: String
    public var checkedAt: Date?
    public var transactions: [BankTransaction]
}
public struct SubscriptionSuggestion: Identifiable, Sendable {
    public var id: String
    public var merchant: String
    public var amount: Int64
    public var cycle: BillingCycle
    public var nextDue: Date
    public var occurrences: Int
}
extension Ledger {
    public mutating func receiveBankActivity(_ items: [BankActivityItem]) throws {
        let incoming = items.flatMap(\.transactions)
        guard incoming.count <= 100_000, Set(incoming.map(\.id)).count == incoming.count,
              incoming.allSatisfy({ $0.amountCents.magnitude <= 99_999_999_999 && $0.purchaseDate != nil }) else { throw LedgerError.invalidBackup }
        let refreshedPrefixes = items.map { "production:" + $0.id + ":" }
        let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        // Only entries explicitly created from bank imports follow bank corrections.
        // User-entered expenses matched to imports retain the user's reviewed values.
        for i in expenses.indices.reversed() where expenses[i].importedFromBank == true {
            guard let id = expenses[i].bankTransactionID, refreshedPrefixes.contains(where: { id.hasPrefix($0) }) else { continue }
            guard let t = byID[id], t.canRecord else {
                expenses.remove(at: i); continue
            }
            expenses[i].amount = t.amountCents
            expenses[i].date = t.purchaseDate!
            expenses[i].merchant = t.merchant
        }
        let incomingIDs = Set(items.map(\.id))
        bankActivity = (bankActivity ?? []).filter { !incomingIDs.contains($0.id) } + items
    }
    public mutating func recordBankPurchase(_ transaction: BankTransaction, categoryID: UUID, matching expenseID: UUID? = nil) throws {
        guard transaction.canRecord,
              !(expenses.contains { $0.bankTransactionID == transaction.id }),
              let account = accounts.first(where: { $0.bankAccountKey == transaction.accountKey }),
              bankActivity?.flatMap(\.transactions).contains(transaction) == true else { throw LedgerError.invalidExpense }
        if let expenseID {
            guard let i = expenses.firstIndex(where: { $0.id == expenseID }), expenses[i].bankTransactionID == nil,
                  expenses[i].accountID == account.id, expenses[i].amount == transaction.amountCents else { throw LedgerError.invalidExpense }
            expenses[i].bankTransactionID = transaction.id
        } else {
            try record(Expense(merchant: transaction.merchant, amount: transaction.amountCents, categoryID: categoryID,
                accountID: account.id, date: transaction.purchaseDate!, bankTransactionID: transaction.id, importedFromBank: true), deductFromBalance: false)
        }
    }
    public var subscriptionSuggestions: [SubscriptionSuggestion] {
        let transactions = (bankActivity ?? []).flatMap(\.transactions).filter(\.canRecord)
        let groups = Dictionary(grouping: transactions) { $0.accountKey + ":" + $0.merchant.lowercased().trimmingCharacters(in: .whitespaces) }
        return groups.compactMap { (key, values) -> SubscriptionSuggestion? in
            let ordered = values.sorted { $0.date < $1.date }
            guard ordered.count >= 3, let last = ordered.last, let lastDate = last.purchaseDate,
                  !recurring.contains(where: { $0.name.caseInsensitiveCompare(last.merchant) == .orderedSame }) else { return nil }
            let recent = Array(ordered.suffix(4))
            let amounts = recent.map(\.amountCents)
            guard let low = amounts.min(), let high = amounts.max(), high - low <= max(100, high / 10) else { return nil }
            let gaps = zip(recent, recent.dropFirst()).map { Calendar.current.dateComponents([.day], from: $0.purchaseDate!, to: $1.purchaseDate!).day ?? 0 }
            let cycle: BillingCycle
            if gaps.allSatisfy({ (6...8).contains($0) }) { cycle = .weekly }
            else if gaps.allSatisfy({ (26...35).contains($0) }) { cycle = .monthly }
            else if gaps.allSatisfy({ (350...380).contains($0) }) { cycle = .yearly }
            else { return nil }
            let bill = RecurringBill(name: last.merchant, amount: last.amountCents, categoryID: UUID(), nextDue: lastDate, cycle: cycle, recurrenceAnchor: lastDate)
            return SubscriptionSuggestion(id: key, merchant: last.merchant, amount: last.amountCents, cycle: cycle, nextDue: bill.advanced(), occurrences: recent.count)
        }.sorted { $0.nextDue < $1.nextDue }
    }
}
