import XCTest
@testable import TenderCore
final class AssistantAppAccessTests: XCTestCase {
    private func withMetadata(_ extra: [String: Any]) throws -> Ledger {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder.tender.encode(Ledger.empty())) as! [String: Any]
        for (key, value) in extra { json[key] = value }
        return try JSONDecoder.tender.decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func json(_ ledger: Ledger) throws -> [String: Any] { try JSONSerialization.jsonObject(with: JSONEncoder.tender.encode(ledger)) as! [String: Any] }
    func testAssistantSettingsAndScreenRequestSurvivePhoneSave() throws {
        let requestID = UUID().uuidString
        let ledger = try withMetadata(["appPreferences": ["remindersEnabled": false], "assistantScreenRequest": ["id": requestID, "screen": "profile"]]).validated()
        let saved = try json(ledger)
        XCTAssertEqual((saved["appPreferences"] as? [String: Any])?["remindersEnabled"] as? Bool, false)
        XCTAssertEqual((saved["assistantScreenRequest"] as? [String: Any])?["id"] as? String, requestID)
    }
    func testRemoteNavigationCannotRequestResetOrExecuteDeletion() throws {
        for screen in ["reset_app", "delete_all", "bank_login", "run_command"] { XCTAssertThrowsError(try withMetadata(["assistantScreenRequest": ["id": UUID().uuidString, "screen": screen]]).validated()) }
    }
    func testCloudSettingsMergeKeepsIndependentPhoneProfileEdit() throws {
        let base = Ledger.empty(); var phone = base; phone.profileName = "Phone name"
        let remote = try withMetadata(["appPreferences": ["remindersEnabled": false]])
        let merged = try CloudLedgerMerge.merge(base: base, local: phone, remote: remote)
        XCTAssertEqual(merged.profileName, "Phone name")
        XCTAssertEqual((try json(merged)["appPreferences"] as? [String: Any])?["remindersEnabled"] as? Bool, false)
    }
    func testGroceryRecurringAndAccountSourcesSurviveArchiveAndBackup() throws {
        var ledger = Ledger.empty(); ledger.accounts = [Account(name: "Cash", available: 50000, isCash: true)]
        ledger.groceries = [GroceryItem(name: "Milk")]
        ledger.recurring = [RecurringBill(name: "Music", amount: 1200, categoryID: ledger.categories[0].id, nextDue: Date())]
        var root = try json(ledger)
        let origin: [String: Any] = ["provider": "chatgpt", "actionID": UUID().uuidString, "createdAt": "2026-11-01T19:00:00Z"]
        for key in ["accounts", "groceries", "recurring"] { var rows = root[key] as! [[String: Any]]; rows[0]["assistantOrigin"] = origin; root[key] = rows }
        ledger = try JSONDecoder.tender.decode(Ledger.self, from: JSONSerialization.data(withJSONObject: root))
        let id = ledger.groceries[0].id; ledger.archiveGrocery(id); ledger.restoreGrocery(id)
        let restored = try LedgerArchive(ledger: ledger, attachments: [:]).validated().ledger
        for key in ["accounts", "groceries", "recurring"] { let rows = try json(restored)[key] as! [[String: Any]]; XCTAssertEqual((rows[0]["assistantOrigin"] as? [String: Any])?["provider"] as? String, "chatgpt", key) }
    }
}
