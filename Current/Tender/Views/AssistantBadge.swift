import SwiftUI

struct AssistantMark: View {
    var provider: AssistantProvider
    var size: CGFloat = 18
    var body: some View {
        Group {
            if provider == .assistant { Image(systemName: "sparkles").foregroundStyle(Ink.green) }
            else { Image(provider == .chatgpt ? "AssistantChatGPT" : "AssistantClaude").resizable().renderingMode(.original).scaledToFit() }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct AssistantBadge: View {
    var origin: AssistantOrigin?
    var edited: AssistantOrigin? = nil
    var compact = true
    private var attribution: AssistantOrigin? { origin ?? edited }
    var body: some View {
        if let attribution {
            HStack(spacing: 5) {
                AssistantMark(provider: attribution.provider)
                if !compact { Text((origin == nil ? "Updated with " : "Added with ") + attribution.provider.name).font(.caption).foregroundStyle(Ink.muted) }
            }.padding(compact ? 3 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel((origin == nil ? "Updated with " : "Added with ") + attribution.provider.name)
                .accessibilityIdentifier("assistant-source-" + attribution.provider.rawValue)
        }
    }
}
