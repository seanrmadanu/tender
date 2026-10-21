import Foundation

/// A portable, explicitly exported snapshot. No bank credentials are included.
public struct LedgerArchive: Codable, Sendable {
    public static let maximumEncodedBytes = 120_000_000
    public static let maximumAttachmentBytes = 60_000_000
    public var format = "TenderBackup"
    public var version = 1
    public var createdAt = Date()
    public var ledger: Ledger
    public var attachments: [String: Data]

    public init(ledger: Ledger, attachments: [String: Data]) {
        self.ledger = ledger
        self.attachments = attachments
    }

    public func validated() throws -> LedgerArchive {
        _ = try ledger.validated()
        guard format == "TenderBackup", version == 1,
              Set(attachments.keys) == ledger.attachmentNames,
              attachments.values.allSatisfy({ !$0.isEmpty && $0.count <= 20_000_000 }),
              attachments.values.reduce(0, { $0 + $1.count }) <= Self.maximumAttachmentBytes else {
            throw LedgerError.invalidBackup
        }
        return self
    }
}

extension Ledger {
    public var attachmentNames: Set<String> {
        Set(expenses.compactMap(\.attachment) + groceries.flatMap { $0.observations.compactMap(\.photo) })
    }

    public mutating func renameAttachments(_ mapping: [String: String]) {
        for i in expenses.indices {
            if let name = expenses[i].attachment, let newName = mapping[name] { expenses[i].attachment = newName }
        }
        for i in groceries.indices {
            for j in groceries[i].observations.indices {
                if let name = groceries[i].observations[j].photo, let newName = mapping[name] { groceries[i].observations[j].photo = newName }
            }
        }
    }
}
