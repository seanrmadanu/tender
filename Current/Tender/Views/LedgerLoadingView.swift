import SwiftUI

/// Local ledger startup only. Network refresh never holds this screen open.
struct LedgerLoadingView: View {
    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            Engraving().ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 22) {
                Image(systemName: "leaf.circle")
                    .font(.system(size: 52, weight: .ultraLight)).accessibilityHidden(true)
                Text("tender").font(.system(size: 48, weight: .medium, design: .serif))
                Rectangle().fill(Ink.line).frame(width: 64, height: 1).accessibilityHidden(true)
                Text("A little clarity for every day.")
                    .font(.system(.body, design: .serif)).multilineTextAlignment(.center)
                ProgressView("Opening your ledger…").font(.footnote).tint(Ink.green)
            }
            .padding(32)
            .background(Ink.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Ink.line, lineWidth: 0.7))
            .padding(24)
        }
        .foregroundStyle(Ink.green)
        .accessibilityIdentifier("ledger-loading")
    }
}
