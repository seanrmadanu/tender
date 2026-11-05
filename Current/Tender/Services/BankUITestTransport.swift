#if DEBUG
import Foundation

/// Synthetic fixtures only: unreachable without both explicit UI-test flags.
/// No Firebase sign-in, Plaid calls, real credentials or personal ledger files.
@MainActor enum BankUITestTransport {
    static var linked = false
    static var pending = false
    static let date = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200))
    static func call<T: Decodable>(_ route: String, method: String) throws -> T {
        if ProcessInfo.processInfo.arguments.contains("--wallet-startup-test") { linked = true }
        var object: [String: Any]
        switch (route, method) {
        case ("v1/hosted-link", "POST"):
            pending = true
            object = ["id": "fixture-session", "url": "https://secure.plaid.com/hl/fixture", "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(1800)), "presentation": "appReturn"]
        case ("v1/hosted-link", "GET"):
            object = ["session": pending ? ["id": "fixture-session", "url": "https://secure.plaid.com/hl/fixture", "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(1800)), "presentation": "appReturn"] : NSNull()]
        case ("v1/hosted-link/finish", "POST"):
            linked = true; pending = false; object = ["status": "connected"]
        case ("v1/connections", "GET"):
            object = ["connections": linked ? [["id": "fixture-item", "name": "Test Bank"]] : []]
        case ("v1/sync", "POST"):
            object = ["environment": "production", "accounts": [["id": "fixture-checking", "name": "Checking", "institutionName": "Test Bank", "mask": "1234", "currency": "USD", "availableCents": 12345, "currentCents": 13000, "retrievedAt": date, "itemID": "fixture-item"]], "items": [["id": "fixture-item", "checkedAt": date, "transactions": [["id": "production:fixture-item:purchase", "accountKey": "production:fixture-checking", "merchant": "Fixture Cafe", "amountCents": 450, "currency": "USD", "date": "2026-10-24", "pending": false, "category": "FOOD_AND_DRINK", "isTransfer": false]]]], "connectionIssues": [], "errors": [], "balancesCheckedAt": date, "activityCheckedAt": date]
        default: throw BankError.message("Unexpected UI-test bank route.")
        }
        if route == "v1/sync", ProcessInfo.processInfo.arguments.contains("--wallet-test") {
            var accounts = object["accounts"] as? [[String: Any]] ?? []
            accounts.append(["id": "fixture-savings", "name": "Savings", "institutionName": "Other Bank", "mask": "9876", "currency": "USD", "availableCents": 20000, "currentCents": 20000, "retrievedAt": date, "itemID": "fixture-item"])
            object["accounts"] = accounts
            func charge(_ id: String, _ account: String, _ merchant: String, _ day: String) -> [String: Any] {
                ["id": "production:fixture-item:" + id, "accountKey": "production:" + account, "merchant": merchant, "amountCents": 450, "currency": "USD", "date": day, "pending": false, "category": "FOOD_AND_DRINK", "isTransfer": false]
            }
            object["items"] = [["id": "fixture-item", "checkedAt": date, "transactions": [
                charge("purchase", "fixture-checking", "Fixture Cafe", "2026-10-24"),
                charge("earlier", "fixture-checking", "Fixture Cafe", "2026-09-24"),
                charge("other", "fixture-savings", "Other Account Service", "2026-10-24"),
                charge("other-earlier", "fixture-savings", "Other Account Service", "2026-09-24")
            ]]]
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
#endif
