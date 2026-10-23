import SwiftUI
import AuthenticationServices

/// Account entry point. Never unlock a personal ledger from a provider button.
/// Authentication and per-user storage must be configured before enabling these actions.
struct WelcomeLoginView: View {
    @State private var selectedMethod: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Image(systemName: "leaf.circle").font(.title)
                    Text("tender").font(.system(.title, design: .serif).weight(.medium))
                }.padding(.top, 30).accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 12) {
                    Text("A little clarity.\nA fresh start.")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Sign in or create an account to start your ledger.")
                        .font(.body).foregroundStyle(Ink.muted)
                }
                PaperCard {
                    VStack(spacing: 14) {
                        Button { selectedMethod = "Email" } label: {
                            Label("Continue with email", systemImage: "envelope")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(PrimaryButton())
                        Button { selectedMethod = "Google" } label: {
                            Text("Continue with Google").font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(Ink.paper, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
                        }.buttonStyle(.plain)
                        // Native Apple styling; no authorization request until account setup is complete.
                        SignInWithAppleButton(.continue) { _ in } onCompletion: { _ in }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 14))
                            .allowsHitTesting(false).accessibilityHidden(true)
                            .overlay {
                                Button { selectedMethod = "Apple" } label: { Color.clear.contentShape(Rectangle()) }
                                    .accessibilityLabel("Continue with Apple")
                            }
                        Button { selectedMethod = "Phone" } label: {
                            Label("Continue with phone", systemImage: "iphone")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                                .background(Ink.paper, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Sign-in setup required", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                    Text("Account sign-in is not enabled in this build yet. These options will be available after setup.")
                        .font(.footnote).foregroundStyle(Ink.muted)
                    Text("Connecting Gmail for subscription notices is a separate, optional step.")
                        .font(.footnote).foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 8)
            }
            .padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background { Ink.paper.ignoresSafeArea(); Engraving().frame(height: 350).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea() }
        .foregroundStyle(Ink.green)
        .accessibilityIdentifier("welcome-login")
        .alert("Sign-in isn't available yet", isPresented: Binding(get: { selectedMethod != nil }, set: { if !$0 { selectedMethod = nil } })) {
            Button("OK") { selectedMethod = nil }
        } message: {
            Text("\(selectedMethod ?? "Account") sign-in still needs account-service configuration. No account has been created and your saved financial data has not been opened.")
        }
    }
}
