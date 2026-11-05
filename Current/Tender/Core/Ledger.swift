import Foundation

public enum Money {
    public static func cents(_ text: String) -> Int64? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.range(of: #"^\d{1,9}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).int64Value
    }
    public static func format(_ cents: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSDecimalNumber(value: cents).dividing(by: 100)) ?? "$0.00"
    }
    public static func input(_ cents: Int64) -> String { (cents < 0 ? "-" : "") + String(cents.magnitude / 100) + "." + String(format: "%02d", Int(cents.magnitude % 100)) }
}

public struct BudgetCategory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var limit: Int64
    public var assistantLastEdit: AssistantOrigin? = nil
    public init(id: UUID = UUID(), name: String, symbol: String, limit: Int64) { self.id = id; self.name = name; self.symbol = symbol; self.limit = limit }
}
public struct Account: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var available: Int64
    public var updated: Date = Date()
    public var source: String = "Manual"
    public var snapshotAt: Date? = nil
    public var balanceRevision: UUID? = nil
    public var bankAccountKey: String? = nil
    public var isCash: Bool? = nil
    public var needsReconnection: Bool? = nil
    public var isArchived: Bool? = nil
    public var bankDetails: BankAccountDetails? = nil
    public var cardArtworkID: String? = nil
    public var usesStandardCardDisplay: Bool? = nil
    public var assistantOrigin: AssistantOrigin? = nil
    public var assistantLastEdit: AssistantOrigin? = nil
}
public struct Expense: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var merchant: String
    public var amount: Int64
    public var categoryID: UUID
    public var accountID: UUID
    public var date: Date = Date()
    public var note: String = ""
    public var attachment: String? = nil
    public var balanceAppliedAt: Date? = nil
    public var balanceRevision: UUID? = nil
    public var receipt: ReceiptDetails? = nil
    public var bankTransactionID: String? = nil
    public var importedFromBank: Bool? = nil
    public var fixedExpenseID: UUID? = nil
    public var assistantOrigin: AssistantOrigin? = nil
    public var assistantLastEdit: AssistantOrigin? = nil
}
public enum BillingCycle: String, Codable, CaseIterable, Sendable { case monthly = "Monthly", yearly = "Yearly", weekly = "Weekly" }
public struct RecurringBill: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var amount: Int64
    public var categoryID: UUID
    public var nextDue: Date
    public var cycle: BillingCycle = .monthly
    public var remind: Bool = false
    public var recurrenceAnchor: Date? = nil
    public var cancelledAt: Date? = nil
    public var trialEndsAt: Date? = nil
    public var renewalAmountUnknown: Bool? = nil
    public var source: String? = nil
    public var sourceMailbox: String? = nil
    public var sourceEvidenceID: String? = nil
    public var bankSuggestionID: String? = nil
    public var assistantOrigin: AssistantOrigin? = nil
    public var assistantLastEdit: AssistantOrigin? = nil
    public var monthlyEquivalent: Int64 {
        switch cycle { case .monthly: amount; case .yearly: (amount + 6) / 12; case .weekly: (amount * 52 + 6) / 12 }
    }
    public func advanced(calendar: Calendar = .current) -> Date {
        if cycle == .weekly { return calendar.date(byAdding: .day, value: 7, to: nextDue) ?? nextDue }
        let component: Calendar.Component = cycle == .monthly ? .month : .year
        guard let target = calendar.date(byAdding: component, value: 1, to: nextDue),
              let days = calendar.range(of: .day, in: .month, for: target) else { return nextDue }
        // A Jan 31 renewal should return to Mar 31 after February's shorter month.
        let anchorDay = calendar.component(.day, from: recurrenceAnchor ?? nextDue)
        var parts = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: target)
        parts.day = min(anchorDay, days.count)
        return calendar.date(from: parts) ?? target
    }
}
public struct PriceObservation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var price: Int64
    public var store: String
    public var date: Date = Date()
    public var photo: String? = nil
}
public struct GroceryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var quantity: Int = 1
    public var unit: String = "each"
    public var checked: Bool = false
    public var observations: [PriceObservation] = []
    public var plannedAt: Date? = nil
    public var storeName: String? = nil
    public var remind: Bool? = nil
    public var purchasedAt: Date? = nil
    public var expenseID: UUID? = nil
    public var assistantOrigin: AssistantOrigin? = nil
    public var assistantLastEdit: AssistantOrigin? = nil
    public var estimatedUnitPrice: Int64? {
        guard !observations.isEmpty else { return nil }
        let recent = observations.sorted { $0.date > $1.date }.prefix(5)
        return recent.reduce(0) { $0 + $1.price } / Int64(recent.count)
    }
}
public struct ArchivedEnvelope: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { category.id }
    public var category: BudgetCategory
    public var expenseIDs: [UUID]
    public var recurringIDs: [UUID]
    public var fallbackID: UUID?
}
public struct ArchivedExpense: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { expense.id }
    public var expense: Expense
    public var reversedBalance: Bool
    public var groceryLinks: [GroceryItem]
}
public struct LedgerArchiveItems: Codable, Equatable, Sendable {
    public var envelopes: [ArchivedEnvelope] = []
    public var expenses: [ArchivedExpense] = []
    public var recurring: [RecurringBill] = []
    public var groceries: [GroceryItem] = []
    public init() {}
}
public struct ArchivedCardHistory: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expenses: [Expense]
    public var bankItems: [BankActivityItem]
    public var details: [String: BankTransactionDetails]
    public var groceries: [GroceryItem]
    public var recurring: [RecurringBill]
}
public enum AccountActivityEntry: Identifiable, Equatable, Sendable {
    case bank(BankTransaction)
    case manual(Expense)
    public var id: String { switch self { case .bank(let t): "bank:" + t.id; case .manual(let e): "manual:" + e.id.uuidString } }
    public var date: Date { switch self { case .bank(let t): t.purchaseDate ?? .distantPast; case .manual(let e): e.date } }
    public var pending: Bool { if case .bank(let t) = self { return t.pending }; return false }
}
public struct Ledger: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var freshStartVersion: Int? = nil
    public var isDemo: Bool = false
    public var categories: [BudgetCategory] = []
    public var accounts: [Account] = []
    public var primaryAccountID: UUID? = nil
    public var monthlyAllocation: Int64? = nil
    public var fixedExpenses: [FixedExpense]? = nil
    public var profilePhoto: ProfilePhoto? = nil
    public var profileName: String? = nil
    public var profileFrameSize: Double? = nil
    public var appPreferences: AppPreferences? = nil
    public var assistantScreenRequest: AssistantScreenRequest? = nil
    public var expenses: [Expense] = []
    public var recurring: [RecurringBill] = []
    public var groceries: [GroceryItem] = []
    public var bankActivity: [BankActivityItem]? = nil
    public var bankTransactionDetails: [String: BankTransactionDetails]? = nil
    public var bankSync: BankSyncRecord? = nil
    public var archivedItems: LedgerArchiveItems? = nil
    public var archivedCards: [ArchivedCardHistory]? = nil
    public var subscriptionMailboxes: [SubscriptionMailbox]? = nil
    public var subscriptionEmails: [SubscriptionEmail]? = nil
    public var ignoredSubscriptionIDs: [String]? = nil
    public var activeRecurring: [RecurringBill] { recurring.filter { $0.cancelledAt == nil } }
    public init() {}
    public var activeAccounts: [Account] { accounts.filter { $0.isArchived != true } }
    public var primaryAccount: Account? {
        let cards = activeAccounts.filter { $0.isCash != true }
        return cards.first { $0.id == primaryAccountID } ?? cards.first ?? activeAccounts.first
    }
    public mutating func setPrimaryAccount(_ id: UUID) throws {
        guard activeAccounts.contains(where: { $0.id == id && $0.isCash != true }) else { throw LedgerError.invalidExpense }
        primaryAccountID = id
    }
    public func bankTransactions(for account: Account?) -> [BankTransaction] {
        guard let account, account.isArchived != true, let key = account.bankAccountKey else { return [] }
        return (bankActivity ?? []).flatMap(\.transactions).filter { $0.accountKey == key }
    }
    public func accountActivity(for account: Account?) -> [AccountActivityEntry] {
        guard let account, account.isArchived != true else { return [] }
        let bank = bankTransactions(for: account)
        let bankIDs = Set(bank.map(\.id))
        let manual = expenses.filter { $0.accountID == account.id && ($0.bankTransactionID.map { !bankIDs.contains($0) } ?? true) }
        return (bank.map(AccountActivityEntry.bank) + manual.map(AccountActivityEntry.manual)).sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.pending != $1.pending { return $0.pending }
            return $0.id < $1.id
        }
    }
    public func possibleSubscriptions(for account: Account?) -> [SubscriptionSuggestion] {
        guard let account, account.isArchived != true else { return [] }
        let prefix = (account.bankAccountKey ?? account.id.uuidString) + ":"
        return subscriptionSuggestions.filter { $0.id.hasPrefix(prefix) }
    }
    public var available: Int64 { activeAccounts.reduce(0) { $0 + $1.available } }
    public mutating func removeCategories(_ ids: Set<UUID>) {
        let needsFallback = expenses.contains { ids.contains($0.categoryID) } || recurring.contains { ids.contains($0.categoryID) }
        categories.removeAll { ids.contains($0.id) }
        if needsFallback {
            let replacement = ensureCategory(named: "Uncategorized")
            for i in expenses.indices where ids.contains(expenses[i].categoryID) { expenses[i].categoryID = replacement }
            for i in recurring.indices where ids.contains(recurring[i].categoryID) { recurring[i].categoryID = replacement }
        }
    }
    public mutating func ensureCategory(named name: String) -> UUID {
        if let category = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return category.id }
        let category = BudgetCategory(name: name, symbol: "tag", limit: 0)
        categories.append(category)
        return category.id
    }
    public mutating func archiveCategories(_ ids: Set<UUID>) {
        if archivedItems == nil { archivedItems = LedgerArchiveItems() }
        let snapshots = categories.filter { ids.contains($0.id) }.map { category in
            ArchivedEnvelope(category: category, expenseIDs: expenses.filter { $0.categoryID == category.id }.map(\.id), recurringIDs: recurring.filter { $0.categoryID == category.id }.map(\.id), fallbackID: nil)
        }
        removeCategories(ids)
        let fallback = categories.first { $0.name == "Uncategorized" }?.id
        for var item in snapshots { item.fallbackID = fallback; archivedItems?.envelopes.append(item) }
    }
    public mutating func restoreCategory(_ id: UUID) {
        guard let item = archivedItems?.envelopes.first(where: { $0.id == id }), !categories.contains(where: { $0.id == id }) else { return }
        categories.append(item.category)
        for i in expenses.indices where item.expenseIDs.contains(expenses[i].id) && expenses[i].categoryID == item.fallbackID { expenses[i].categoryID = id }
        for i in recurring.indices where item.recurringIDs.contains(recurring[i].id) && recurring[i].categoryID == item.fallbackID { recurring[i].categoryID = id }
        archivedItems?.envelopes.removeAll { $0.id == id }
    }
    public mutating func archiveExpense(_ id: UUID) {
        guard let expense = expenses.first(where: { $0.id == id }) else { return }
        if archivedItems == nil { archivedItems = LedgerArchiveItems() }
        let reverses = expense.balanceAppliedAt != nil && accounts.contains { $0.id == expense.accountID && $0.balanceRevision == expense.balanceRevision }
        archivedItems?.expenses.append(ArchivedExpense(expense: expense, reversedBalance: reverses, groceryLinks: groceries.filter { $0.expenseID == id }))
        removeExpense(id: id)
    }
    public mutating func restoreExpense(_ id: UUID) throws {
        guard let saved = archivedItems?.expenses.first(where: { $0.id == id }), !expenses.contains(where: { $0.id == id }),
              let account = accounts.firstIndex(where: { $0.id == saved.expense.accountID && $0.isArchived != true }) else { throw LedgerError.invalidExpense }
        guard saved.expense.bankTransactionID == nil || !expenses.contains(where: { $0.bankTransactionID == saved.expense.bankTransactionID }) else { throw LedgerError.invalidExpense }
        var expense = saved.expense
        if !categories.contains(where: { $0.id == expense.categoryID }) { expense.categoryID = ensureCategory(named: "Uncategorized") }
        if saved.reversedBalance && accounts[account].balanceRevision == expense.balanceRevision { accounts[account].available -= expense.amount }
        else { expense.balanceAppliedAt = nil }
        expenses.append(expense)
        for link in saved.groceryLinks {
            if let i = groceries.firstIndex(where: { $0.id == link.id && $0.expenseID == nil }) {
                groceries[i].expenseID = id; groceries[i].purchasedAt = link.purchasedAt; groceries[i].checked = link.checked
            }
        }
        archivedItems?.expenses.removeAll { $0.id == id }
    }
    public mutating func archiveRecurring(_ id: UUID) {
        guard let bill = recurring.first(where: { $0.id == id }) else { return }
        if archivedItems == nil { archivedItems = LedgerArchiveItems() }; archivedItems?.recurring.append(bill)
        recurring.removeAll { $0.id == id }
    }
    public mutating func restoreRecurring(_ id: UUID) {
        guard var bill = archivedItems?.recurring.first(where: { $0.id == id }), !recurring.contains(where: { $0.id == id }) else { return }
        if !categories.contains(where: { $0.id == bill.categoryID }) { bill.categoryID = ensureCategory(named: "Uncategorized") }
        recurring.append(bill); archivedItems?.recurring.removeAll { $0.id == id }
    }
    public mutating func archiveGrocery(_ id: UUID) {
        guard let item = groceries.first(where: { $0.id == id }) else { return }
        if archivedItems == nil { archivedItems = LedgerArchiveItems() }; archivedItems?.groceries.append(item)
        groceries.removeAll { $0.id == id }
    }
    public mutating func restoreGrocery(_ id: UUID) {
        guard var item = archivedItems?.groceries.first(where: { $0.id == id }), !groceries.contains(where: { $0.id == id }) else { return }
        if let expenseID = item.expenseID, !expenses.contains(where: { $0.id == expenseID }) { item.expenseID = nil; item.purchasedAt = nil; item.checked = false }
        groceries.append(item); archivedItems?.groceries.removeAll { $0.id == id }
    }
    public mutating func archiveCardAndHistory(_ id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id && $0.isArchived != true }) else { return }
        let key = accounts[i].bankAccountKey
        let purchases = expenses.filter { $0.accountID == id }
        let purchaseIDs = Set(purchases.map(\.id))
        let items = (bankActivity ?? []).compactMap { item -> BankActivityItem? in
            let transactions = item.transactions.filter { $0.accountKey == key }
            return transactions.isEmpty ? nil : BankActivityItem(id: item.id, checkedAt: item.checkedAt, transactions: transactions)
        }
        let transactionIDs = Set(items.flatMap(\.transactions).map(\.id) + purchases.compactMap(\.bankTransactionID))
        let bills = recurring.filter { bill in key.map { bill.bankSuggestionID?.hasPrefix($0 + ":") == true } ?? false }
        let billIDs = Set(bills.map(\.id))
        let relatedGroceries = groceries.filter { $0.expenseID.map(purchaseIDs.contains) == true }
        if archivedCards == nil { archivedCards = [] }
        archivedCards?.append(ArchivedCardHistory(id: id, expenses: purchases, bankItems: items,
            details: (bankTransactionDetails ?? [:]).filter { transactionIDs.contains($0.key) }, groceries: relatedGroceries, recurring: bills))
        expenses.removeAll { purchaseIDs.contains($0.id) }
        groceries.removeAll { $0.expenseID.map(purchaseIDs.contains) == true }
        recurring.removeAll { billIDs.contains($0.id) }
        if bankActivity != nil { for j in bankActivity!.indices { bankActivity![j].transactions.removeAll { $0.accountKey == key } } }
        for transactionID in transactionIDs { bankTransactionDetails?.removeValue(forKey: transactionID) }
        accounts[i].isArchived = true
        if primaryAccountID == id { primaryAccountID = primaryAccount?.id }
    }
    public mutating func restoreCardAndHistory(_ id: UUID) throws {
        guard let i = accounts.firstIndex(where: { $0.id == id && $0.isArchived == true }) else { return }
        if let saved = archivedCards?.first(where: { $0.id == id }) {
            let activeExpenseIDs = Set(expenses.map(\.id))
            let activeBankIDs = Set(expenses.compactMap(\.bankTransactionID))
            guard !saved.expenses.contains(where: { activeExpenseIDs.contains($0.id) || $0.bankTransactionID.map(activeBankIDs.contains) == true }) else { throw LedgerError.invalidExpense }
            for var expense in saved.expenses {
                if !categories.contains(where: { $0.id == expense.categoryID }) { expense.categoryID = ensureCategory(named: "Uncategorized") }
                expenses.append(expense)
            }
            for var bill in saved.recurring where !recurring.contains(where: { $0.id == bill.id }) {
                if !categories.contains(where: { $0.id == bill.categoryID }) { bill.categoryID = ensureCategory(named: "Uncategorized") }
                recurring.append(bill)
            }
            groceries += saved.groceries.filter { item in !groceries.contains { $0.id == item.id } }
            if bankActivity == nil { bankActivity = [] }
            for item in saved.bankItems {
                if let index = bankActivity?.firstIndex(where: { $0.id == item.id }) {
                    let existing = Set(bankActivity![index].transactions.map(\.id))
                    bankActivity![index].transactions += item.transactions.filter { !existing.contains($0.id) }
                } else { bankActivity?.append(item) }
            }
            if bankTransactionDetails == nil { bankTransactionDetails = [:] }
            for (key, value) in saved.details { bankTransactionDetails?[key] = value }
            archivedCards?.removeAll { $0.id == id }
        }
        accounts[i].isArchived = false
    }
    public mutating func archiveAccount(_ id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].isArchived = true
        if primaryAccountID == id { primaryAccountID = primaryAccount?.id }
        // Historical deductions must not refund an inactive balance later.
        accounts[i].balanceRevision = UUID()
    }
    public var allocatedToEnvelopes: Int64 { categories.reduce(0) { $0 + $1.limit } }
    public var monthlyBudget: Int64 { monthlyAllocation ?? allocatedToEnvelopes }
    public var unallocatedBudget: Int64 { monthlyBudget - allocatedToEnvelopes }
    @discardableResult public mutating func initializeMonthlyAllocationIfNeeded() -> Bool {
        guard monthlyAllocation == nil else { return false }
        monthlyAllocation = allocatedToEnvelopes
        return true
    }
    public mutating func setMonthlyAllocations(_ amounts: [UUID: Int64], total: Int64? = nil) throws {
        let budget = total ?? monthlyBudget
        guard Set(amounts.keys) == Set(categories.map(\.id)),
              amounts.values.allSatisfy({ $0 >= 0 && $0 <= 99_999_999_999 }),
              budget >= 0 && budget <= 9_999_999_999_900 else { throw LedgerError.invalidBackup }
        guard budget <= budgetCapacity(), amounts.values.reduce(0, +) <= budget else { throw LedgerError.budgetUnavailable }
        monthlyAllocation = budget
        for i in categories.indices { categories[i].limit = amounts[categories[i].id]! }
    }
    public func spent(category: UUID? = nil, in interval: DateInterval) -> Int64 {
        spendingEntries(in: interval).filter { category == nil || $0.categoryID == category }.reduce(0) { $0 + $1.amount }
    }
    public func month(at date: Date = Date(), calendar: Calendar = .current) -> DateInterval { calendar.dateInterval(of: .month, for: date)! }
    public func remaining(_ category: BudgetCategory, at date: Date = Date()) -> Int64 { category.limit - envelopeSpent(category: category.id, in: month(at: date)) }
    public func upcomingReserve(at date: Date = Date(), calendar: Calendar = .current) -> Int64 {
        let end = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: date))!
        return activeRecurring.reduce(0) { total, bill in
            var due = bill.nextDue
            var reserve: Int64 = 0
            // Include overdue bills once, and every occurrence in the next 30 days.
            if due < calendar.startOfDay(for: date) {
                reserve += bill.amount
                // One overdue liability, then advance on its original cadence.
                for _ in 0..<10_000 {
                    var occurrence = bill; occurrence.recurrenceAnchor = bill.recurrenceAnchor ?? bill.nextDue; occurrence.nextDue = due
                    let next = occurrence.advanced(calendar: calendar)
                    guard next > due else { break }; due = next
                    if due >= calendar.startOfDay(for: date) { break }
                }
            }
            for _ in 0..<32 {
                guard due < end else { break }
                if due >= calendar.startOfDay(for: date) { reserve += bill.amount }
                var occurrence = bill; occurrence.recurrenceAnchor = bill.recurrenceAnchor ?? bill.nextDue; occurrence.nextDue = due
                let next = occurrence.advanced(calendar: calendar)
                guard next > due else { break }; due = next
            }
            return total + reserve
        }
    }
    public func shopping(amount: Int64, category: BudgetCategory, at date: Date = Date()) -> ShoppingDecision {
        let categoryLeft = remaining(category, at: date)
        let cashLeft = available - upcomingReserve(at: date)
        return ShoppingDecision(validAmount: amount > 0, categoryAfter: categoryLeft - amount, cashAfter: cashLeft - amount, hasAccount: !activeAccounts.isEmpty)
    }
    public mutating func record(_ expense: Expense, deductFromBalance: Bool = true) throws {
        guard expense.amount > 0, expense.amount <= 99_999_999_999,
              !expense.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              categories.contains(where: { $0.id == expense.categoryID }),
              let index = accounts.firstIndex(where: { $0.id == expense.accountID && $0.isArchived != true }) else { throw LedgerError.invalidExpense }
        // A future expense is a plan, not a posted transaction.
        guard expense.date <= Date() else { throw LedgerError.futureExpense }
        var saved = expense
        saved.balanceAppliedAt = deductFromBalance ? Date() : nil
        saved.balanceRevision = accounts[index].balanceRevision
        expenses.append(saved)
        if deductFromBalance { accounts[index].available -= expense.amount; accounts[index].updated = Date() }
    }
    public mutating func removeExpense(id: UUID) {
        guard let i = expenses.firstIndex(where: { $0.id == id }) else { return }
        let removed = expenses.remove(at: i)
        for j in groceries.indices where groceries[j].expenseID == id { groceries[j].expenseID = nil; groceries[j].purchasedAt = nil; groceries[j].checked = false }
        guard removed.balanceAppliedAt != nil,
              let a = accounts.firstIndex(where: { $0.id == removed.accountID }),
              accounts[a].balanceRevision == removed.balanceRevision else { return }
        accounts[a].available += removed.amount
        accounts[a].updated = Date()
    }
    public mutating func setBalance(accountID: UUID, available: Int64) {
        guard let i = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[i].available = available
        accounts[i].updated = Date()
        accounts[i].snapshotAt = Date()
        accounts[i].balanceRevision = UUID()
    }
    public func validated() throws -> Ledger {
        if let fixedExpenses {
            guard fixedExpenses.count <= 1000, Set(fixedExpenses.map(\.id)).count == fixedExpenses.count,
                  fixedExpenses.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 && $0.name.rangeOfCharacter(from: .controlCharacters) == nil && $0.amount > 0 && $0.amount <= 99_999_999_999 }) else { throw LedgerError.invalidBackup }
        }
        if let budget = monthlyAllocation {
            guard budget >= 0 && budget <= 9_999_999_999_900 else { throw LedgerError.invalidBackup }
        }
        if let size = profileFrameSize {
            guard size.isFinite, (40...160).contains(size) else { throw LedgerError.invalidBackup }
        }
        if let name = profileName {
            guard name.count <= 80, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  name.rangeOfCharacter(from: .controlCharacters) == nil else { throw LedgerError.invalidBackup }
        }
        if let photo = profilePhoto {
            guard safeAttachment(photo.originalImage), safeAttachment(photo.croppedImage),
                  !photo.originalImage.isEmpty, !photo.croppedImage.isEmpty,
                  photo.originalImage.count <= 128, photo.croppedImage.count <= 128,
                  photo.crop.isValid else { throw LedgerError.invalidBackup }
        }
        if let cards = archivedCards {
            guard cards.count <= 100, Set(cards.map(\.id)).count == cards.count,
                  cards.allSatisfy({ card in
                      accounts.contains { $0.id == card.id && $0.isArchived == true } &&
                      card.expenses.count <= 100_000 && card.bankItems.flatMap(\.transactions).count <= 100_000 && card.groceries.count <= 10_000 && card.recurring.count <= 1000 &&
                      card.expenses.allSatisfy { $0.accountID == card.id && $0.amount > 0 && $0.amount <= 99_999_999_999 && safeAttachment($0.attachment) } &&
                      card.details.values.allSatisfy { $0.note.count <= 10_000 && $0.attachments.count <= 20 && $0.attachments.allSatisfy { safeAttachment($0) } } &&
                      card.groceries.allSatisfy { $0.observations.allSatisfy { safeAttachment($0.photo) } }
                  }) else { throw LedgerError.invalidBackup }
        }
        if let archive = archivedItems {
            guard archive.envelopes.count <= 10_000, archive.expenses.count <= 100_000, archive.recurring.count <= 10_000, archive.groceries.count <= 10_000,
                  Set(archive.envelopes.map(\.id)).count == archive.envelopes.count,
                  Set(archive.expenses.map(\.id)).count == archive.expenses.count,
                  Set(archive.recurring.map(\.id)).count == archive.recurring.count,
                  Set(archive.groceries.map(\.id)).count == archive.groceries.count,
                  archive.envelopes.allSatisfy({ $0.category.limit >= 0 && $0.category.limit <= 99_999_999_999 }),
                  archive.expenses.allSatisfy({ $0.expense.amount > 0 && $0.expense.amount <= 99_999_999_999 && safeAttachment($0.expense.attachment) && $0.groceryLinks.count <= 10_000 }),
                  archive.recurring.allSatisfy({ $0.amount >= 0 && $0.amount <= 99_999_999_999 }),
                  archive.groceries.allSatisfy({ $0.quantity > 0 && $0.quantity <= 999 && $0.observations.count <= 10_000 && $0.observations.allSatisfy { $0.price > 0 && $0.price <= 99_999_999_999 && safeAttachment($0.photo) } }) else { throw LedgerError.invalidBackup }
        }
        guard (subscriptionMailboxes ?? []).count <= 20,
              Set((subscriptionMailboxes ?? []).map(\.id)).count == (subscriptionMailboxes ?? []).count,
              (subscriptionEmails ?? []).count <= 5000,
              Set((subscriptionEmails ?? []).map(\.id)).count == (subscriptionEmails ?? []).count,
              (ignoredSubscriptionIDs ?? []).count <= 1000,
              accounts.allSatisfy({ ($0.cardArtworkID?.count ?? 0) <= 128 }),
              schemaVersion == 1, categories.count <= 100, accounts.count <= 100, expenses.count <= 100_000,
              recurring.count <= 1000, groceries.count <= 10_000,
              Set(categories.map(\.id)).count == categories.count,
              Set(accounts.map(\.id)).count == accounts.count,
              Set(accounts.compactMap(\.bankAccountKey)).count == accounts.compactMap(\.bankAccountKey).count,
              Set(expenses.map(\.id)).count == expenses.count,
              Set(expenses.compactMap(\.bankTransactionID)).count == expenses.compactMap(\.bankTransactionID).count,
              (bankTransactionDetails ?? [:]).count <= 100_000,
              (bankTransactionDetails ?? [:]).values.allSatisfy({ $0.note.count <= 10_000 && $0.attachments.count <= 20 && $0.attachments.allSatisfy { safeAttachment($0) } }),
              (bankActivity ?? []).count <= 100,
              Set((bankActivity ?? []).map(\.id)).count == (bankActivity ?? []).count,
              (bankActivity ?? []).flatMap(\.transactions).count <= 100_000,
              Set((bankActivity ?? []).flatMap(\.transactions).map(\.id)).count == (bankActivity ?? []).flatMap(\.transactions).count,
              expenses.allSatisfy({ ($0.receipt?.items ?? []).allSatisfy { $0.quantity > 0 && $0.quantity <= 999 && $0.total > 0 && $0.total <= 99_999_999_999 } }),
              (bankActivity ?? []).flatMap(\.transactions).allSatisfy({ $0.amountCents.magnitude <= 99_999_999_999 && $0.purchaseDate != nil }),
              Set(recurring.map(\.id)).count == recurring.count,
              Set(groceries.map(\.id)).count == groceries.count,
              categories.allSatisfy({ $0.limit >= 0 && $0.limit <= 99_999_999_999 }),
              accounts.allSatisfy({ absSafe($0.available) <= 99_999_999_999 }),
              expenses.allSatisfy({ e in e.amount > 0 && e.amount <= 99_999_999_999 && categories.contains(where: { $0.id == e.categoryID }) && accounts.contains(where: { $0.id == e.accountID }) && safeAttachment(e.attachment) }),
              recurring.allSatisfy({ bill in (bill.amount > 0 || (bill.amount == 0 && bill.renewalAmountUnknown == true && bill.trialEndsAt != nil)) && bill.amount <= 99_999_999_999 && categories.contains(where: { $0.id == bill.categoryID }) }),
              groceries.allSatisfy({ $0.quantity > 0 && $0.quantity <= 999 && $0.observations.count <= 10_000 && $0.observations.allSatisfy({ $0.price > 0 && $0.price <= 99_999_999_999 && safeAttachment($0.photo) }) }) else { throw LedgerError.invalidBackup }
        return self
    }
}
private func absSafe(_ value: Int64) -> UInt64 { value.magnitude }
private func safeAttachment(_ name: String?) -> Bool { guard let name else { return true }; return !name.isEmpty && name == (name as NSString).lastPathComponent && !name.contains("..") }
public enum LedgerError: Error { case invalidExpense, futureExpense, invalidBackup, budgetUnavailable, staleEdit }
public struct ShoppingDecision: Sendable {
    public var validAmount: Bool
    public var categoryAfter: Int64
    public var cashAfter: Int64
    public var hasAccount: Bool
    public var fits: Bool { validAmount && hasAccount && categoryAfter >= 0 && cashAfter >= 0 }
}

extension Ledger {
    public static func empty() -> Ledger {
        var ledger = Ledger()
        ledger.freshStartVersion = 1
        ledger.monthlyAllocation = 0
        ledger.categories = [BudgetCategory(name: "Groceries", symbol: "carrot", limit: 0), BudgetCategory(name: "Food & coffee", symbol: "cup.and.saucer", limit: 0), BudgetCategory(name: "Shopping", symbol: "bag", limit: 0), BudgetCategory(name: "Transport", symbol: "tram", limit: 0), BudgetCategory(name: "Home & bills", symbol: "house", limit: 0), BudgetCategory(name: "Wellbeing", symbol: "heart", limit: 0)]
        return ledger
    }
    public static func sample(at now: Date = Date()) -> Ledger {
        var ledger = Ledger.empty(); ledger.isDemo = true
        for (index, amount) in [45000, 25000, 20000, 15000, 140000, 10000].enumerated() { ledger.categories[index].limit = Int64(amount) }
        ledger.monthlyAllocation = ledger.allocatedToEnvelopes
        ledger.accounts = [Account(name: "Everyday checking", available: 284250, source: "Sample"), Account(name: "Cash wallet", available: 12000, source: "Sample")]
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: now)!.start
        let day = calendar.component(.day, from: now)
        let names = ["Whole Foods", "Dayglow Coffee", "Uniqlo", "Metro", "Internet", "Pharmacy"]
        for d in 1...max(1, day) {
            if d % 4 == 0 { continue }
            let c = (d * 7) % 6
            let amount: Int64 = c == 4 ? 6500 : Int64(750 + (d * 173) % 5400)
            ledger.expenses.append(Expense(merchant: names[c], amount: amount, categoryID: ledger.categories[c].id, accountID: ledger.accounts[0].id, date: calendar.date(byAdding: .day, value: d - 1, to: start)!))
        }
        ledger.recurring = [RecurringBill(name: "iCloud+", amount: 299, categoryID: ledger.categories[4].id, nextDue: calendar.date(byAdding: .day, value: 2, to: now)!), RecurringBill(name: "Spotify", amount: 1199, categoryID: ledger.categories[4].id, nextDue: calendar.date(byAdding: .day, value: 5, to: now)!), RecurringBill(name: "Internet", amount: 6500, categoryID: ledger.categories[4].id, nextDue: calendar.date(byAdding: .day, value: 9, to: now)!)]
        ledger.groceries = [GroceryItem(name: "Oat milk", unit: "carton", observations: [PriceObservation(price: 449, store: "Trader Joe’s"), PriceObservation(price: 499, store: "Whole Foods")]), GroceryItem(name: "Avocados", quantity: 3, observations: [PriceObservation(price: 149, store: "Trader Joe’s")]), GroceryItem(name: "Sourdough", unit: "loaf", observations: [PriceObservation(price: 549, store: "Trader Joe’s")])]
        return ledger
    }
}
