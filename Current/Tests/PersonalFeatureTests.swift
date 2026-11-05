import XCTest
@testable import TenderCore

final class PersonalFeatureTests: XCTestCase {
    private func transaction(_ id: String = "one", amount: Int64 = 499, date: String = "2026-01-10", pending: Bool = false, transfer: Bool = false) -> BankTransaction {
        BankTransaction(id: "production:bank:" + id, accountKey: "production:checking", merchant: "Example Shop", amountCents: amount, currency: "USD", date: date, pending: pending, category: "GENERAL_MERCHANDISE", isTransfer: transfer)
    }
    private func ledger() -> Ledger {
        var ledger = Ledger.empty()
        ledger.accounts = [Account(name: "Checking", available: 10000, bankAccountKey: "production:checking")]
        return ledger
    }
    func testBankReceiptsAndNotesSurviveRefreshWithoutCreatingExpense() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [t])])
        let details = BankTransactionDetails(note: "Dinner with friends", attachments: ["receipt.jpg"])
        try ledger.saveBankTransactionDetails(details, for: t.id)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [transaction(amount: 599)])])
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.bankTransactionDetails?[t.id], details)
        XCTAssertTrue(restored.expenses.isEmpty)
        XCTAssertEqual(restored.available, 10000)
        XCTAssertThrowsError(try ledger.saveBankTransactionDetails(details, for: "unknown"))
    }
    func testPendingReceiptMovesToPostedAndStaleEditorCanSave() throws {
        var ledger = ledger(); let pending = transaction("pending", pending: true)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [pending])])
        try ledger.saveBankTransactionDetails(BankTransactionDetails(note: "Tip included", attachments: ["tip.jpg"]), for: pending.id)
        var posted = transaction("posted", amount: 699); posted.pendingID = pending.id
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [posted])])
        XCTAssertNil(ledger.bankTransactionDetails?[pending.id])
        XCTAssertEqual(ledger.bankTransactionDetails?[posted.id]?.attachments, ["tip.jpg"])
        try ledger.saveBankTransactionDetails(BankTransactionDetails(note: "Updated", attachments: ["tip.jpg"]), for: pending.id)
        XCTAssertEqual(ledger.bankTransactionDetails?[posted.id]?.note, "Updated")
        XCTAssertTrue(ledger.expenses.isEmpty)
    }
    func testBankReceiptBackupIncludesFilesAndRejectsUnsafeNames() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [t])])
        try ledger.saveBankTransactionDetails(BankTransactionDetails(note: "Warranty", attachments: ["receipt.pdf"]), for: t.id)
        XCTAssertEqual(ledger.attachmentNames, ["receipt.pdf"])
        _ = try LedgerArchive(ledger: ledger, attachments: ["receipt.pdf": Data("receipt".utf8)]).validated()
        XCTAssertThrowsError(try LedgerArchive(ledger: ledger, attachments: [:]).validated())
        ledger.renameAttachments(["receipt.pdf": "restored.pdf"])
        XCTAssertEqual(ledger.bankTransactionDetails?[t.id]?.attachments, ["restored.pdf"])
        XCTAssertThrowsError(try ledger.saveBankTransactionDetails(BankTransactionDetails(attachments: ["../unsafe"]), for: t.id))
    }
    func testExpenseArchiveRestoresBalanceOnceAndRetainsReceiptBackup() throws {
        var ledger = ledger()
        let expense = Expense(merchant: "Cash purchase", amount: 500, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id, attachment: "receipt.jpg")
        try ledger.record(expense)
        XCTAssertEqual(ledger.available, 9500)
        ledger.archiveExpense(expense.id)
        XCTAssertEqual(ledger.available, 10000)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertEqual(ledger.attachmentNames, ["receipt.jpg"])
        _ = try LedgerArchive(ledger: ledger, attachments: ["receipt.jpg": Data([1])]).validated()
        ledger.renameAttachments(["receipt.jpg": "restored.jpg"])
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        ledger = restored
        try ledger.restoreExpense(expense.id)
        XCTAssertEqual(ledger.available, 9500)
        XCTAssertEqual(ledger.expenses[0].attachment, "restored.jpg")
        XCTAssertThrowsError(try ledger.restoreExpense(expense.id))
        XCTAssertEqual(ledger.expenses.count, 1)
    }
    func testArchiveRestoreAfterNewSnapshotDoesNotDeductAgain() throws {
        var ledger = ledger()
        let expense = Expense(merchant: "Purchase", amount: 500, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        try ledger.record(expense); ledger.archiveExpense(expense.id)
        ledger.setBalance(accountID: ledger.accounts[0].id, available: 9000)
        try ledger.restoreExpense(expense.id)
        XCTAssertEqual(ledger.available, 9000)
        XCTAssertNil(ledger.expenses[0].balanceAppliedAt)
        ledger.removeExpense(id: expense.id)
        XCTAssertEqual(ledger.available, 9000)
    }
    func testEnvelopeArchiveRestoresOriginalExpenseAndRecurringLinks() throws {
        var ledger = ledger(); let category = ledger.categories[0]
        let expense = Expense(merchant: "Purchase", amount: 100, categoryID: category.id, accountID: ledger.accounts[0].id)
        try ledger.record(expense, deductFromBalance: false)
        ledger.recurring = [RecurringBill(name: "Subscription", amount: 100, categoryID: category.id, nextDue: Date())]
        ledger.archiveCategories([category.id])
        XCTAssertNotEqual(ledger.expenses[0].categoryID, category.id)
        _ = try ledger.validated()
        ledger.restoreCategory(category.id)
        XCTAssertEqual(ledger.expenses[0].categoryID, category.id)
        XCTAssertEqual(ledger.recurring[0].categoryID, category.id)
        XCTAssertEqual(ledger.categories.filter { $0.id == category.id }.count, 1)
    }
    func testRecurringAndGroceryArchiveRestoreRetainHistory() throws {
        var ledger = ledger()
        let bill = RecurringBill(name: "Internet", amount: 1000, categoryID: ledger.categories[0].id, nextDue: Date(), remind: true)
        let item = GroceryItem(name: "Milk", observations: [PriceObservation(price: 400, store: "Shop", photo: "milk.jpg")])
        ledger.recurring = [bill]; ledger.groceries = [item]
        ledger.archiveRecurring(bill.id); ledger.archiveGrocery(item.id)
        XCTAssertTrue(ledger.recurring.isEmpty && ledger.groceries.isEmpty)
        XCTAssertEqual(ledger.attachmentNames, ["milk.jpg"])
        ledger.renameAttachments(["milk.jpg": "new.jpg"])
        ledger.restoreRecurring(bill.id); ledger.restoreGrocery(item.id)
        XCTAssertEqual(ledger.recurring[0], bill)
        XCTAssertEqual(ledger.groceries[0].observations[0].photo, "new.jpg")
        _ = try ledger.validated()
    }
    func testPrimaryDefaultsToFirstCardAndSelectionPersists() throws {
        var ledger = ledger()
        let first = ledger.accounts[0]
        ledger.accounts.insert(Account(name: "Cash", available: 500, isCash: true), at: 0)
        let second = Account(name: "Second bank", available: 20000, bankAccountKey: "production:second")
        ledger.accounts.append(second)
        XCTAssertEqual(ledger.primaryAccount?.id, first.id)
        try ledger.setPrimaryAccount(second.id)
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.primaryAccount?.id, second.id)
        XCTAssertEqual(restored.available, 30500)
        ledger.archiveAccount(second.id)
        XCTAssertEqual(ledger.primaryAccount?.id, first.id)
        XCTAssertThrowsError(try ledger.setPrimaryAccount(second.id))
        XCTAssertThrowsError(try ledger.setPrimaryAccount(ledger.accounts[0].id))
    }
    func testPrimaryTransactionsAndSuggestionsExcludeOtherAccounts() throws {
        var ledger = ledger()
        let second = Account(name: "Second bank", available: 20000, bankAccountKey: "production:second")
        ledger.accounts.append(second)
        let primaryCharges = [transaction("one", date: "2026-01-10"), transaction("two", date: "2026-02-10")]
        var other = transaction("other", date: "2026-01-10"); other.accountKey = "production:second"
        var another = transaction("another", date: "2026-02-10"); another.accountKey = "production:second"
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: primaryCharges + [other, another])])
        XCTAssertEqual(Set(ledger.bankTransactions(for: ledger.primaryAccount).map(\.id)), Set(primaryCharges.map(\.id)))
        XCTAssertEqual(ledger.possibleSubscriptions(for: ledger.primaryAccount).count, 1)
        XCTAssertTrue(ledger.possibleSubscriptions(for: ledger.primaryAccount).allSatisfy { $0.id.hasPrefix("production:checking:") })
        try ledger.setPrimaryAccount(second.id)
        XCTAssertEqual(Set(ledger.bankTransactions(for: ledger.primaryAccount).map(\.id)), [other.id, another.id])
        XCTAssertTrue(ledger.possibleSubscriptions(for: ledger.primaryAccount).allSatisfy { $0.id.hasPrefix("production:second:") })
        XCTAssertTrue(ledger.bankTransactions(for: nil).isEmpty)
        XCTAssertTrue(ledger.possibleSubscriptions(for: nil).isEmpty)
    }
    func testWholeCardArchiveRetainsHistoryAndBlocksRefreshUntilRestore() throws {
        var ledger = ledger(); let card = ledger.accounts[0]; let t = transaction()
        ledger.accounts.append(Account(name: "Other", available: 20000, bankAccountKey: "production:other"))
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [t])])
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id)
        let manual = Expense(merchant: "Manual receipt", amount: 300, categoryID: ledger.categories[0].id, accountID: card.id, note: "Keep this", attachment: "manual.jpg")
        try ledger.record(manual, deductFromBalance: false)
        ledger.groceries = [GroceryItem(name: "Linked purchase", purchasedAt: Date(), expenseID: manual.id)]
        var bill = RecurringBill(name: "Linked subscription", amount: 499, categoryID: ledger.categories[0].id, nextDue: Date())
        bill.bankSuggestionID = "production:checking:service"; ledger.recurring = [bill]
        try ledger.saveBankTransactionDetails(BankTransactionDetails(note: "Bank note", attachments: ["bank.pdf"]), for: t.id)
        ledger.archiveCardAndHistory(card.id)
        XCTAssertEqual(ledger.available, 20000)
        XCTAssertTrue(ledger.expenses.isEmpty && ledger.groceries.isEmpty && ledger.recurring.isEmpty)
        XCTAssertNil(ledger.bankTransactionDetails?[t.id])
        XCTAssertEqual(ledger.archivedCards?.first?.details[t.id]?.note, "Bank note")
        XCTAssertEqual(ledger.attachmentNames, ["manual.jpg", "bank.pdf"])
        _ = try LedgerArchive(ledger: ledger, attachments: ["manual.jpg": Data([1]), "bank.pdf": Data([2])]).validated()
        let snapshot = BankSnapshot(id: "checking", name: "Checking", currency: "USD", availableCents: 99999, retrievedAt: Date())
        _ = try ledger.synchronizeBankAccounts([snapshot], environment: "production")
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [t])])
        XCTAssertEqual(ledger.accounts.first { $0.id == card.id }?.available, 10000)
        XCTAssertTrue((ledger.bankActivity ?? []).flatMap(\.transactions).isEmpty)
        ledger.renameAttachments(["manual.jpg": "new.jpg", "bank.pdf": "new.pdf"])
        ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        ledger.removeCategories([manual.categoryID])
        try ledger.restoreCardAndHistory(card.id)
        XCTAssertEqual(ledger.available, 30000)
        XCTAssertEqual(ledger.expenses.count, 2)
        XCTAssertEqual(ledger.bankTransactions(for: ledger.accounts[0]).count, 1)
        XCTAssertEqual(ledger.bankTransactionDetails?[t.id]?.attachments, ["new.pdf"])
        XCTAssertEqual(ledger.expenses.first { $0.id == manual.id }?.attachment, "new.jpg")
        XCTAssertEqual(ledger.groceries.first?.expenseID, manual.id)
        XCTAssertEqual(ledger.recurring.count, 1)
        try ledger.restoreCardAndHistory(card.id)
        XCTAssertEqual(ledger.expenses.count, 2)
        _ = try ledger.validated()
    }
    func testAccountFeedIncludesManualPurchasesWithoutDuplicatingMatchedBankEntries() throws {
        var ledger = ledger(); let t = transaction()
        let manual = Expense(merchant: "Receipt", amount: 499, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        let another = Expense(merchant: "Offline purchase", amount: 300, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        try ledger.record(manual, deductFromBalance: false); try ledger.record(another, deductFromBalance: false)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [t])])
        XCTAssertEqual(ledger.accountActivity(for: ledger.primaryAccount).count, 3)
        try ledger.recordBankPurchase(t, categoryID: manual.categoryID, matching: manual.id)
        XCTAssertEqual(ledger.accountActivity(for: ledger.primaryAccount).count, 2)
        ledger.accounts.append(Account(name: "Other", available: 0))
        XCTAssertTrue(ledger.accountActivity(for: ledger.accounts[1]).isEmpty)
    }
    func testBankImportDoesNotDeductAndIsIdempotent() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
        XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id)
        XCTAssertEqual(ledger.accounts[0].available, 10000)
        XCTAssertThrowsError(try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id))
        XCTAssertEqual(ledger.expenses.count, 1)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [transaction(amount: 599)])])
        XCTAssertEqual(ledger.expenses[0].amount, 599)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [])])
        XCTAssertTrue(ledger.expenses.isEmpty); XCTAssertEqual(ledger.available, 10000)
    }
    func testMatchingReceiptDoesNotDoubleCountOrChangeOriginalAmount() throws {
        var ledger = ledger(); let t = transaction()
        let receipt = Expense(merchant: "Receipt", amount: 499, categoryID: ledger.categories[0].id, accountID: ledger.accounts[0].id)
        try ledger.record(receipt)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id, matching: receipt.id)
        XCTAssertEqual(ledger.expenses.count, 1); XCTAssertEqual(ledger.available, 9501)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [transaction(amount: 699)])])
        XCTAssertEqual(ledger.expenses[0].amount, 499)
    }
    func testPendingCreditsAndTransfersCannotEnterExpenseTotals() throws {
        for t in [transaction(pending: true), transaction(transfer: true), transaction(amount: -100)] {
            var ledger = ledger()
            try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
            XCTAssertThrowsError(try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id))
            XCTAssertEqual(ledger.expenses.count, 0)
        }
    }
    func testDisconnectDoesNotDeleteRecordedHistory() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: [t])])
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id)
        try ledger.receiveBankActivity([])
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.bankActivity?.first?.transactions.count, 1)
    }
    func testCashPurchaseChangesOnlyCashWallet() throws {
        var ledger = ledger()
        let wallet = Account(name: "Cash", available: 2000, isCash: true); ledger.accounts.append(wallet)
        try ledger.record(Expense(merchant: "Cash purchase", amount: 500, categoryID: ledger.categories[0].id, accountID: wallet.id))
        XCTAssertEqual(ledger.accounts[0].available, 10000); XCTAssertEqual(ledger.accounts[1].available, 1500)
    }
    func testReceiptExtractsTotalItemsDateAndMaskedPayment() {
        let receipt = ReceiptParser.parse("Corner Market\n10/20/2026\n2 x Ice Cream 8.00\nMilk 3.50\nSubtotal 11.50\nTax 0.90\nTOTAL 12.40\nTotal Savings 1.00\nVISA ********1234")
        XCTAssertEqual(receipt.merchant, "Corner Market"); XCTAssertEqual(receipt.total, 1240)
        XCTAssertEqual(receipt.itemCount, 3); XCTAssertEqual(receipt.items.count, 2)
        XCTAssertNotNil(receipt.date); XCTAssertEqual(receipt.payment, "Visa ··1234")
        let noTotal = ReceiptParser.parse("Shop\nSubtotal 10.00\nTax 1.00\nChange 9.00")
        XCTAssertNil(noTotal.total)
    }
    func testShelfLabelDoesNotGuessAmbiguousOrPromotionalPrice() {
        XCTAssertEqual(ShelfLabelParser.parse("Oat Milk\n32 fl oz\n$3.49\nUnit price $0.11 / oz").price, 349)
        XCTAssertNil(ShelfLabelParser.parse("Ice Cream\n$4.99\nMember $3.99").price)
        XCTAssertNil(ShelfLabelParser.parse("Ice Cream\n2 for $5.00").price)
    }
    func testSpokenPlanFindsTomorrowStoreAndReminderTime() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        let draft = ShoppingPlanParser.parse("I want ice cream tomorrow when I go to Costco at 5 PM", now: now, calendar: calendar)
        XCTAssertEqual(draft.item, "ice cream"); XCTAssertEqual(draft.store, "Costco")
        XCTAssertEqual(calendar.component(.day, from: draft.date), 22)
        XCTAssertEqual(calendar.component(.hour, from: draft.date), 17)
        XCTAssertEqual(calendar.component(.hour, from: draft.date.addingTimeInterval(-3600)), 16)
        XCTAssertTrue(draft.hasExplicitTime)
        XCTAssertFalse(ShoppingPlanParser.parse("I want apples tomorrow", now: now, calendar: calendar).hasExplicitTime)
    }
    func testSubscriptionsOfferTentativeTwoChargeMatches() throws {
        var ledger = ledger()
        let values = [transaction("jan", date: "2026-01-10"), transaction("feb", date: "2026-02-10"), transaction("mar", date: "2026-03-10")]
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: values)])
        XCTAssertEqual(ledger.subscriptionSuggestions.count, 1)
        XCTAssertEqual(ledger.subscriptionSuggestions.first?.cycle, .monthly)
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", checkedAt: Date(), transactions: Array(values.prefix(2)))])
        XCTAssertEqual(ledger.subscriptionSuggestions.first?.occurrences, 2)
    }
    func testRestoredBankCanBeReauthorizedWithoutDuplicateAccount() throws {
        var ledger = ledger(); let id = ledger.accounts[0].id
        ledger.accounts[0].needsReconnection = true
        let snapshot = BankSnapshot(id: "new-provider-id", name: "Checking", currency: "USD", availableCents: 15000, retrievedAt: Date())
        try ledger.applyBankSnapshot(snapshot, environment: "production", matching: id)
        XCTAssertEqual(ledger.accounts.count, 1); XCTAssertEqual(ledger.accounts[0].id, id)
        XCTAssertEqual(ledger.accounts[0].needsReconnection, false)
    }
    func testLegacyJSONDecodesWithOptionalFeatureFields() throws {
        let original = Ledger.sample()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Ledger.self, from: data).validated()
        XCTAssertEqual(restored, original); XCTAssertNil(restored.bankActivity)
    }
    func testShelfLabelIgnoresNutritionServingFraction() {
        let label = ShelfLabelParser.parse("I 1/3 CUP SERVING\n210 CALORIES\n0g SATURATED FAT\n260mg SODIUM\n8g TOTAL SUGARS\nCHEERIOS\n$4.06")
        XCTAssertEqual(label.name, "CHEERIOS")
        XCTAssertEqual(label.price, 406)
        let missingName = ShelfLabelParser.parse("1/3 CUP SERVING\n210 CALORIES\n$4.06")
        XCTAssertNil(missingName.name)
        XCTAssertEqual(missingName.price, 406)
        XCTAssertNil(ShelfLabelParser.parse("1/3 CUP SERVING\nCereal\n2 for $5.00").price)
        XCTAssertNil(ShelfLabelParser.parse("Cereal\n2/$5.00").price)
    }
    func testShelfNamesIgnoreScreenTextAndIsolatedCharacters() {
        let yogurt = ShelfLabelParser.parse("S finance tracker\n558297\nKIRKLAND SIGNATURE\nNON-FAT GREEK YOGURT\n2 CT 32 OZ\n5.79")
        XCTAssertEqual(yogurt.name, "Yogurt")
        XCTAssertEqual(yogurt.price, 579)
        let wine = ShelfLabelParser.parse("p\n1226845\nKIRKLAND SIGNATURE\nCOLUMBIA VALLEY\nCABERNET SAUVIGNON\n750ML\n9.79")
        XCTAssertEqual(wine.name, "Wine")
        XCTAssertEqual(wine.price, 979)
        let faucet = ShelfLabelParser.parse("N\n1806260\nKOHLER GUILD\nPULLDOWN KITCHEN FAUCET\n99.97")
        XCTAssertEqual(faucet.name, "Faucet")
        XCTAssertEqual(faucet.price, 9997)
        XCTAssertNil(ShelfLabelParser.parse("N\np\nS finance tracker\n750ML\n9.79").name)
    }
    func testShelfCommonProductWordsTakePriorityWithoutGuessing() {
        let yogurt = ShelfLabelParser.parse("TUBES\n558297\nKIRKLAND SIGNATURE\nNON-FAT GREEK YOGURT\n2 CT\n5.79")
        XCTAssertEqual(yogurt.name, "Yogurt")
        XCTAssertEqual(yogurt.price, 579)
        XCTAssertEqual(ShelfLabelParser.parse("TUBES\nyoghurt\n5.79").name, "Yogurt")
        XCTAssertEqual(ShelfLabelParser.parse("ICE\nCREAM\n5.79").name, "Ice cream")
        XCTAssertEqual(ShelfLabelParser.parse("CHICKEN PASTA\n5.79").name, "CHICKEN PASTA")
        XCTAssertEqual(ShelfLabelParser.parse("TEAPOT\n5.79").name, "TEAPOT")
        XCTAssertNil(ShelfLabelParser.parse("5.79").name)
    }
    func testShelfLabelWithTwoPricesOnOneLineNeedsReview() {
        XCTAssertNil(ShelfLabelParser.parse("Ice cream\nRegular $4.99 now $3.99").price)
        XCTAssertEqual(ShelfLabelParser.parse("Ice cream\n$3.99 $3.99").price, 399)
    }
    func testInformalShoppingPhraseAndDottedTime() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        let draft = ShoppingPlanParser.parse("i want to get ice cream tomorrow when im going costco at 5:30 p.m.", now: now, calendar: calendar)
        XCTAssertEqual(draft.item, "ice cream"); XCTAssertEqual(draft.store, "costco")
        XCTAssertEqual(calendar.component(.day, from: draft.date), 22)
        XCTAssertEqual(calendar.component(.hour, from: draft.date), 17)
        XCTAssertEqual(calendar.component(.minute, from: draft.date), 30)
        XCTAssertFalse(ShoppingPlanParser.parse("apples tomorrow at 5:99 p.m.", now: now, calendar: calendar).hasExplicitTime)
    }
    func testRemovedBankPurchaseReopensLinkedGroceryPlan() throws {
        var ledger = ledger(); let t = transaction()
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [t])])
        try ledger.recordBankPurchase(t, categoryID: ledger.categories[0].id)
        ledger.groceries = [GroceryItem(name: "Apples", checked: true, plannedAt: Date(), purchasedAt: t.purchaseDate, expenseID: ledger.expenses[0].id)]
        try ledger.receiveBankActivity([BankActivityItem(id: "bank", transactions: [])])
        XCTAssertNil(ledger.groceries[0].expenseID)
        XCTAssertNil(ledger.groceries[0].purchasedAt)
        XCTAssertFalse(ledger.groceries[0].checked)
        XCTAssertEqual(ledger.available, 10000)
    }
}
