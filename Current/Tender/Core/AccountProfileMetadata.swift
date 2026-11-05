import Foundation

struct AccountProfileMetadata: Codable, Equatable, Sendable {
    var displayName: String?
    var memberSince: Date?
    init(displayName: String? = nil, memberSince: Date? = nil) {
        self.displayName = displayName; self.memberSince = memberSince
    }
    init(firebaseUser: [String: Any], now: Date = Date()) {
        let name = (firebaseUser["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = name.flatMap { !$0.isEmpty && $0.count <= 80 && $0.rangeOfCharacter(from: .controlCharacters) == nil ? $0 : nil }
        // Firebase createdAt is milliseconds since the Unix epoch, not the current login date.
        if let raw = firebaseUser["createdAt"] as? String, let milliseconds = Double(raw), milliseconds.isFinite,
           milliseconds > 0, milliseconds / 1000 <= now.timeIntervalSince1970 + 300 {
            memberSince = Date(timeIntervalSince1970: milliseconds / 1000)
        } else { memberSince = nil }
    }
}
