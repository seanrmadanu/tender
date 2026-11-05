import Foundation

enum LedgerPersistence {
    /// Call off the main actor. A normal launch only reads the saved ledger;
    /// writing is reserved for an actual schema migration or isolated test seed.
    static func load(root: URL, initial: Ledger? = nil, now: Date = Date()) throws -> Ledger {
        try FileManager.default.createDirectory(at: root.appending(path: "Attachments"), withIntermediateDirectories: true)
        let file = root.appending(path: "ledger.json")
        if let initial {
            try JSONEncoder.tender.encode(initial).write(to: file, options: [.atomic, .completeFileProtection])
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty() }
        var ledger = try JSONDecoder.tender.decode(Ledger.self, from: Data(contentsOf: file)).validated()
        var migrated = ledger.initializeMonthlyAllocationIfNeeded()
        if ledger.freshStartVersion == nil {
            ledger.freshStartVersion = 1
            migrated = true
        }
        let day = Calendar.current.startOfDay(for: now)
        for i in ledger.groceries.indices where ledger.groceries[i].plannedAt == nil {
            ledger.groceries[i].plannedAt = day
            migrated = true
        }
        if migrated {
            try JSONEncoder.tender.encode(ledger).write(to: file, options: [.atomic, .completeFileProtection])
        }
        return ledger
    }
}

extension JSONEncoder {
    static var tender: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
extension JSONDecoder {
    static var tender: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
