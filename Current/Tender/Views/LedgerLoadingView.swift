import SwiftUI

/// Visible while local data opens and the launch balance refresh completes.
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
                Text("Loading balances").font(.footnote)
                    .accessibilityIdentifier("loading-balances")
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

struct BankDateSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    var body: some View {
        Text(Date().formatted(date: .abbreviated, time: .shortened)).font(.caption).hidden()
            .overlay {
                RoundedRectangle(cornerRadius: 4).fill(Ink.muted.opacity(pulsing ? 0.3 : 0.13))
                    .frame(height: 13)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulsing = true }
            }.accessibilityHidden(true)
    }
}
