import Foundation

extension Ledger {
    /// Correct a manual entry without reapplying purchases already reflected in
    /// a newer bank/manual balance snapshot. Imported amounts follow the bank.
    public mutating func editManualExpense(original: Expense, merchant: String, amount: Int64, date: Date, categoryID: UUID, note: String) throws {
        guard let index = expenses.firstIndex(where: { $0.id == original.id }), expenses[index] == original else { throw LedgerError.staleEdit }
        guard original.importedFromBank != true, !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, merchant.count <= 200,
              amount > 0, amount <= 99_999_999_999, date <= Date(), note.count <= 10000,
              categories.contains(where: { $0.id == categoryID }), let a = accounts.firstIndex(where: { $0.id == original.accountID && $0.isArchived != true }) else { throw LedgerError.invalidExpense }
        var next = self
        next.expenses[index].merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        next.expenses[index].amount = amount; next.expenses[index].date = date; next.expenses[index].categoryID = categoryID; next.expenses[index].note = note
        if original.balanceAppliedAt != nil && original.balanceRevision == next.accounts[a].balanceRevision {
            next.accounts[a].available += original.amount - amount; next.accounts[a].updated = Date()
        }
        self = try next.validated()
    }
}
