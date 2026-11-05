import Foundation

public struct FixedExpense: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var amount: Int64
    public var archivedAt: Date? = nil
    public var assistantOrigin: AssistantOrigin? = nil
    public var assistantLastEdit: AssistantOrigin? = nil
    public init(id: UUID = UUID(), name: String, amount: Int64) { self.id = id; self.name = name; self.amount = amount }
}

public struct SpendingEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var merchant: String
    public var amount: Int64
    public var date: Date
    public var accountID: UUID
    public var categoryID: UUID?
    public var fixedExpenseID: UUID?
    public var expenseID: UUID?
    public var bankTransactionID: String?
    public var assistantOrigin: AssistantOrigin? = nil
    public var assistantLastEdit: AssistantOrigin? = nil
}

public struct SpendingSummary: Sendable {
    public var entries: [SpendingEntry]
    public var total: Int64 = 0
    public var unassigned: Int64 = 0
    public var categories: [UUID: Int64] = [:]
    public var days: [Date: Int64] = [:]
    public init(entries: [SpendingEntry], calendar: Calendar = .current) {
        self.entries = entries
        for entry in entries {
            total += entry.amount
            if let category = entry.categoryID { categories[category, default: 0] += entry.amount }
            else { unassigned += entry.amount }
            days[calendar.startOfDay(for: entry.date), default: 0] += entry.amount
        }
    }
}

extension Ledger {
    public var activeFixedExpenses: [FixedExpense] { (fixedExpenses ?? []).filter { $0.archivedAt == nil } }
    public func fixedPaid(_ fixed: FixedExpense, at date: Date = Date()) -> Int64 {
        let interval = month(at: date)
        return expenses.filter { $0.fixedExpenseID == fixed.id && $0.date >= interval.start && $0.date < interval.end }.reduce(0) { $0 + $1.amount }
    }
    public func fixedOutstanding(_ fixed: FixedExpense, at date: Date = Date()) -> Int64 { max(0, fixed.amount - fixedPaid(fixed, at: date)) }
    public func fixedReserve(at date: Date = Date()) -> Int64 {
        let interval = month(at: date)
        var paid: [UUID: Int64] = [:]
        for expense in expenses where expense.date >= interval.start && expense.date < interval.end {
            if let id = expense.fixedExpenseID { paid[id, default: 0] += expense.amount }
        }
        return activeFixedExpenses.reduce(0) { $0 + max(0, $1.amount - (paid[$1.id] ?? 0)) }
    }
    public func budgetCapacity(at date: Date = Date()) -> Int64 { max(0, available - fixedReserve(at: date)) }
    public mutating func saveFixedExpense(_ fixed: FixedExpense) throws {
        var next = self
        if next.fixedExpenses == nil { next.fixedExpenses = [] }
        if let i = next.fixedExpenses?.firstIndex(where: { $0.id == fixed.id }) { next.fixedExpenses?[i] = fixed }
        else { next.fixedExpenses?.append(fixed) }
        self = try next.validated()
    }
    public mutating func setCategoryAllocation(_ category: BudgetCategory) throws {
        guard category.limit >= 0, category.limit <= 99_999_999_999 else { throw LedgerError.invalidBackup }
        let assigned = allocatedToEnvelopes - (categories.first { $0.id == category.id }?.limit ?? 0) + category.limit
        guard assigned <= min(monthlyBudget, budgetCapacity()) else { throw LedgerError.budgetUnavailable }
        if let index = categories.firstIndex(where: { $0.id == category.id }) { categories[index] = category }
        else { categories.append(category) }
    }

    public var reviewableBankPurchases: [BankTransaction] {
        let keys = Set(activeAccounts.compactMap(\.bankAccountKey))
        let archived = Set((archivedItems?.expenses ?? []).compactMap { $0.expense.bankTransactionID })
        return (bankActivity ?? []).flatMap(\.transactions).filter { $0.canRecord && keys.contains($0.accountKey) && !archived.contains($0.id) }
    }
    public func manualCandidates(for transaction: BankTransaction) -> [Expense] {
        guard let account = accounts.first(where: { $0.bankAccountKey == transaction.accountKey }), let date = transaction.purchaseDate else { return [] }
        return expenses.filter { $0.accountID == account.id && $0.bankTransactionID == nil && $0.amount == transaction.amountCents && abs($0.date.timeIntervalSince(date)) < 4 * 86400 }
    }
    public func exactManualMatch(for transaction: BankTransaction) -> Expense? {
        guard transaction.canRecord, let date = transaction.purchaseDate else { return nil }
        let candidates = manualCandidates(for: transaction).filter {
            Calendar.current.isDate($0.date, inSameDayAs: date) && budgetMerchantKey($0.merchant) == budgetMerchantKey(transaction.merchant)
        }
        let identicalBank = reviewableBankPurchases.filter {
            $0.accountKey == transaction.accountKey && $0.amountCents == transaction.amountCents && $0.date == transaction.date && budgetMerchantKey($0.merchant) == budgetMerchantKey(transaction.merchant)
        }
        return candidates.count == 1 && identicalBank.count == 1 ? candidates[0] : nil
    }
    /// One spend fact per posted debit. Exact, unambiguous same-day manual
    /// receipts stand in for the bank debit until the match is reviewed.
    public func spendingEntries(in interval: DateInterval) -> [SpendingEntry] {
        let bank = reviewableBankPurchases.filter { $0.purchaseDate! >= interval.start && $0.purchaseDate! < interval.end }
        let accountsByKey = Dictionary(uniqueKeysWithValues: accounts.compactMap { account in account.bankAccountKey.map { ($0, account.id) } })
        let linked = Set(expenses.compactMap(\.bankTransactionID))
        func key(_ account: UUID, _ amount: Int64, _ date: Date, _ merchant: String) -> String {
            account.uuidString + ":" + String(amount) + ":" + String(Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate) + ":" + budgetMerchantKey(merchant)
        }
        let manual = Dictionary(grouping: expenses.filter { $0.bankTransactionID == nil && $0.date >= interval.start && $0.date < interval.end }) { key($0.accountID, $0.amount, $0.date, $0.merchant) }
        let unlinked = bank.filter { !linked.contains($0.id) }
        let bankGroups = Dictionary(grouping: unlinked) { key(accountsByKey[$0.accountKey]!, $0.amountCents, $0.purchaseDate!, $0.merchant) }
        var inferred: [UUID: String] = [:]
        for (group, transactions) in bankGroups where transactions.count == 1 {
            if let candidates = manual[group], candidates.count == 1 { inferred[candidates[0].id] = transactions[0].id }
        }
        let covered = linked.union(inferred.values)
        var result = expenses.filter { $0.date >= interval.start && $0.date < interval.end }.map {
            SpendingEntry(id: "expense:" + $0.id.uuidString, merchant: $0.merchant, amount: $0.amount, date: $0.date, accountID: $0.accountID,
                categoryID: $0.categoryID, fixedExpenseID: $0.fixedExpenseID, expenseID: $0.id, bankTransactionID: $0.bankTransactionID ?? inferred[$0.id], assistantOrigin: $0.assistantOrigin, assistantLastEdit: $0.assistantLastEdit)
        }
        result += bank.filter { !covered.contains($0.id) }.map {
            SpendingEntry(id: "bank:" + $0.id, merchant: $0.merchant, amount: $0.amountCents, date: $0.purchaseDate!, accountID: accountsByKey[$0.accountKey]!,
                categoryID: nil, fixedExpenseID: nil, expenseID: nil, bankTransactionID: $0.id, assistantLastEdit: bankTransactionDetails?[$0.id]?.assistantLastEdit)
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    public func envelopeSpent(category: UUID? = nil, in interval: DateInterval) -> Int64 {
        spendingEntries(in: interval).filter { $0.fixedExpenseID == nil && (category == nil || $0.categoryID == category) }.reduce(0) { $0 + $1.amount }
    }
    public func suggestedCategory(for transaction: BankTransaction) -> BudgetCategory? {
        let source = transaction.category.uppercased()
        let symbol: String?
        if source.contains("GROCERIES") { symbol = "carrot" }
        else if source.hasPrefix("FOOD_AND_DRINK") { symbol = "cup.and.saucer" }
        else if source.hasPrefix("TRANSPORTATION") || source.hasPrefix("TRAVEL") { symbol = "tram" }
        else if source.hasPrefix("RENT_AND_UTILITIES") { symbol = "house" }
        else if source.hasPrefix("MEDICAL") || source.hasPrefix("PERSONAL_CARE") { symbol = "heart" }
        else if source.hasPrefix("GENERAL_MERCHANDISE") { symbol = "bag" }
        else { symbol = nil }
        return symbol.flatMap { symbol in categories.first { $0.symbol == symbol } }
    }
    public func suggestedPurchases(in interval: DateInterval) -> [BankTransaction] {
        let linked = Set(expenses.compactMap(\.bankTransactionID))
        return reviewableBankPurchases.filter {
            $0.purchaseDate! >= interval.start && $0.purchaseDate! < interval.end && !linked.contains($0.id) && suggestedCategory(for: $0) != nil && (manualCandidates(for: $0).isEmpty || exactManualMatch(for: $0) != nil)
        }
    }
    @discardableResult public mutating func categorizeSuggestedPurchases(in interval: DateInterval) throws -> Int {
        let suggestions = suggestedPurchases(in: interval)
        var next = self
        for transaction in suggestions {
            guard let category = next.suggestedCategory(for: transaction) else { continue }
            try next.recordBankPurchase(transaction, categoryID: category.id, matching: next.exactManualMatch(for: transaction)?.id)
        }
        self = try next.validated()
        return suggestions.count
    }
}

private func budgetMerchantKey(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
}
