import Foundation

public enum AssistantProvider: String, Codable, Sendable {
    case chatgpt, claude, assistant
    public var name: String { switch self { case .chatgpt: "ChatGPT"; case .claude: "Claude"; case .assistant: "AI assistant" } }
}
/// Written by Tender's authenticated connector, never inferred from a merchant,
/// note or a model-supplied source label. Normal edits preserve this attribution.
public struct AssistantOrigin: Codable, Equatable, Sendable {
    public var provider: AssistantProvider
    public var actionID: String
    public var createdAt: Date
    public init(provider: AssistantProvider, actionID: String, createdAt: Date) { self.provider = provider; self.actionID = actionID; self.createdAt = createdAt }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var remindersEnabled: Bool = true
    public var assistantLastEdit: AssistantOrigin? = nil
    public init(remindersEnabled: Bool = true) { self.remindersEnabled = remindersEnabled }
}
public enum AssistantScreen: String, Codable, Sendable {
    case home, budgets, groceries, activity, profile, accounts, updates, archive, backup, privacy
    case aiConnections = "ai_connections"
    case shopping
    case addPurchase = "add_purchase"
}
public struct AssistantScreenRequest: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var screen: AssistantScreen
    public var createdAt: Date? = nil
    public init(id: UUID = UUID(), screen: AssistantScreen, createdAt: Date = Date()) { self.id = id; self.screen = screen; self.createdAt = createdAt }
}
