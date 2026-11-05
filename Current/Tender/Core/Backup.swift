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
        let cardFiles = (archivedCards ?? []).flatMap { card in
            card.expenses.compactMap(\.attachment) + card.groceries.flatMap { $0.observations.compactMap(\.photo) } + card.details.values.flatMap(\.attachments)
        }
        let profileFiles = profilePhoto.map { [$0.originalImage, $0.croppedImage] } ?? []
        return Set(expenses.compactMap(\.attachment) + (archivedItems?.expenses ?? []).compactMap { $0.expense.attachment } + (archivedItems?.groceries ?? []).flatMap { $0.observations.compactMap(\.photo) } + groceries.flatMap { $0.observations.compactMap(\.photo) } + (bankTransactionDetails ?? [:]).values.flatMap(\.attachments) + cardFiles + profileFiles)
    }

    public mutating func renameAttachments(_ mapping: [String: String]) {
        if let photo = profilePhoto {
            profilePhoto?.originalImage = mapping[photo.originalImage] ?? photo.originalImage
            profilePhoto?.croppedImage = mapping[photo.croppedImage] ?? photo.croppedImage
        }
        if var cards = archivedCards {
            for i in cards.indices {
                for j in cards[i].expenses.indices { if let name = cards[i].expenses[j].attachment { cards[i].expenses[j].attachment = mapping[name] ?? name } }
                for j in cards[i].groceries.indices { for k in cards[i].groceries[j].observations.indices {
                    if let name = cards[i].groceries[j].observations[k].photo { cards[i].groceries[j].observations[k].photo = mapping[name] ?? name }
                } }
                for key in Array(cards[i].details.keys) {
                    let files = (cards[i].details[key]?.attachments ?? []).map { mapping[$0] ?? $0 }
                    cards[i].details[key]?.attachments = files
                }
            }
            archivedCards = cards
        }
        for id in Array((bankTransactionDetails ?? [:]).keys) {
            let renamed = (bankTransactionDetails?[id]?.attachments ?? []).map { mapping[$0] ?? $0 }
            bankTransactionDetails?[id]?.attachments = renamed
        }
        if archivedItems != nil {
            for i in archivedItems!.expenses.indices {
                if let name = archivedItems!.expenses[i].expense.attachment, let renamed = mapping[name] { archivedItems!.expenses[i].expense.attachment = renamed }
            }
            for i in archivedItems!.groceries.indices {
                for j in archivedItems!.groceries[i].observations.indices {
                    if let name = archivedItems!.groceries[i].observations[j].photo, let renamed = mapping[name] { archivedItems!.groceries[i].observations[j].photo = renamed }
                }
            }
        }
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
