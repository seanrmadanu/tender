import Foundation

/// Old ledgers did not track which records were entered by the user.
/// Cleanup therefore requires an explicit selection and never guesses from amounts.
struct PersonalLedgerSelection {
    var accounts: Set<UUID> = []
    var expenses: Set<UUID> = []
    var recurring: Set<UUID> = []
    var groceries: Set<UUID> = []
    var keepBudgets = false
}

extension Ledger {
    func personalLedger(keeping selection: PersonalLedgerSelection) throws -> Ledger {
        guard isDemo else { throw LedgerError.invalidBackup }
        var next = self
        next.isDemo = false
        if !selection.keepBudgets {
            next.monthlyAllocation = 0
            next.fixedExpenses = nil
            for i in next.categories.indices { next.categories[i].limit = 0 }
        } else { next.initializeMonthlyAllocationIfNeeded() }
        next.expenses.removeAll { !selection.expenses.contains($0.id) }
        next.recurring.removeAll { !selection.recurring.contains($0.id) }
        next.groceries.removeAll { !selection.groceries.contains($0.id) }
        let requiredAccounts = Set(next.expenses.map(\.accountID))
        next.accounts.removeAll { !selection.accounts.contains($0.id) && !requiredAccounts.contains($0.id) }
        for i in next.accounts.indices {
            // An expense can retain its account reference without retaining a fake balance.
            if !selection.accounts.contains(next.accounts[i].id) { next.accounts[i].available = 0 }
            next.accounts[i].source = "Manual"
            next.accounts[i].bankAccountKey = nil
            next.accounts[i].balanceRevision = UUID()
            next.accounts[i].snapshotAt = Date()
            next.accounts[i].updated = Date()
        }
        return try next.validated()
    }
}
