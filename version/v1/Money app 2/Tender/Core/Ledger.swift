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
    public static func input(_ cents: Int64) -> String { String(format: "%.2f", Double(cents) / 100) }
}

public struct BudgetCategory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var limit: Int64
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
    public var estimatedUnitPrice: Int64? {
        guard !observations.isEmpty else { return nil }
        let recent = observations.sorted { $0.date > $1.date }.prefix(5)
        return recent.reduce(0) { $0 + $1.price } / Int64(recent.count)
    }
}
public struct Ledger: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var isDemo: Bool = false
    public var categories: [BudgetCategory] = []
    public var accounts: [Account] = []
    public var expenses: [Expense] = []
    public var recurring: [RecurringBill] = []
    public var groceries: [GroceryItem] = []
    public init() {}
    public var available: Int64 { accounts.reduce(0) { $0 + $1.available } }
    public var monthlyBudget: Int64 { categories.reduce(0) { $0 + $1.limit } }
    public func spent(category: UUID? = nil, in interval: DateInterval) -> Int64 {
        expenses.filter { (category == nil || $0.categoryID == category) && $0.date >= interval.start && $0.date < interval.end }.reduce(0) { $0 + $1.amount }
    }
    public func month(at date: Date = Date(), calendar: Calendar = .current) -> DateInterval { calendar.dateInterval(of: .month, for: date)! }
    public func remaining(_ category: BudgetCategory, at date: Date = Date()) -> Int64 { category.limit - spent(category: category.id, in: month(at: date)) }
    public func upcomingReserve(at date: Date = Date(), calendar: Calendar = .current) -> Int64 {
        let end = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: date))!
        return recurring.reduce(0) { total, bill in
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
        return ShoppingDecision(validAmount: amount > 0, categoryAfter: categoryLeft - amount, cashAfter: cashLeft - amount, hasAccount: !accounts.isEmpty)
    }
    public mutating func record(_ expense: Expense, deductFromBalance: Bool = true) throws {
        guard expense.amount > 0, expense.amount <= 99_999_999_999,
              !expense.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              categories.contains(where: { $0.id == expense.categoryID }),
              let index = accounts.firstIndex(where: { $0.id == expense.accountID }) else { throw LedgerError.invalidExpense }
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
        guard schemaVersion == 1, categories.count <= 100, accounts.count <= 100, expenses.count <= 100_000,
              recurring.count <= 1000, groceries.count <= 10_000,
              Set(categories.map(\.id)).count == categories.count,
              Set(accounts.map(\.id)).count == accounts.count,
              Set(accounts.compactMap(\.bankAccountKey)).count == accounts.compactMap(\.bankAccountKey).count,
              Set(expenses.map(\.id)).count == expenses.count,
              Set(recurring.map(\.id)).count == recurring.count,
              Set(groceries.map(\.id)).count == groceries.count,
              categories.allSatisfy({ $0.limit >= 0 && $0.limit <= 99_999_999_999 }),
              accounts.allSatisfy({ absSafe($0.available) <= 99_999_999_999 }),
              expenses.allSatisfy({ e in e.amount > 0 && e.amount <= 99_999_999_999 && categories.contains(where: { $0.id == e.categoryID }) && accounts.contains(where: { $0.id == e.accountID }) && safeAttachment(e.attachment) }),
              recurring.allSatisfy({ bill in bill.amount > 0 && bill.amount <= 99_999_999_999 && categories.contains(where: { $0.id == bill.categoryID }) }),
              groceries.allSatisfy({ $0.quantity > 0 && $0.quantity <= 999 && $0.observations.count <= 10_000 && $0.observations.allSatisfy({ $0.price > 0 && $0.price <= 99_999_999_999 && safeAttachment($0.photo) }) }) else { throw LedgerError.invalidBackup }
        return self
    }
}
private func absSafe(_ value: Int64) -> UInt64 { value.magnitude }
private func safeAttachment(_ name: String?) -> Bool { guard let name else { return true }; return !name.isEmpty && name == (name as NSString).lastPathComponent && !name.contains("..") }
public enum LedgerError: Error { case invalidExpense, futureExpense, invalidBackup }
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
        ledger.categories = [BudgetCategory(name: "Groceries", symbol: "carrot", limit: 45000), BudgetCategory(name: "Food & coffee", symbol: "cup.and.saucer", limit: 25000), BudgetCategory(name: "Shopping", symbol: "bag", limit: 20000), BudgetCategory(name: "Transport", symbol: "tram", limit: 15000), BudgetCategory(name: "Home & bills", symbol: "house", limit: 140000), BudgetCategory(name: "Wellbeing", symbol: "heart", limit: 10000)]
        return ledger
    }
    public static func sample(at now: Date = Date()) -> Ledger {
        var ledger = Ledger.empty(); ledger.isDemo = true
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
