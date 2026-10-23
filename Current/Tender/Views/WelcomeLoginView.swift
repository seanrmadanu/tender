import SwiftUI
import AuthenticationServices

/// Account entry point. Never unlock a personal ledger from a provider button.
/// Authentication and per-user storage must be configured before enabling these actions.
struct WelcomeLoginView: View {
    @Environment(AccountAuth.self) private var auth
    @State private var emailForm = false
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
                        Button { emailForm = true } label: {
                            Label("Continue with email", systemImage: "envelope")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(PrimaryButton())
                        Button { Task { await auth.googleLogin() } } label: {
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
                    if auth.busy { ProgressView("Signing in…") }
                    if let message = auth.message { Text(message).font(.footnote).foregroundStyle(Ink.warning) }
                    Text("Apple and phone sign-in require additional setup.").font(.footnote).foregroundStyle(Ink.muted)
                    Text("Connecting Gmail for subscription notices is a separate, optional step.")
                        .font(.footnote).foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 8)
            }
            .padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background { Ink.paper.ignoresSafeArea(); Engraving().frame(height: 350).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea() }
        .foregroundStyle(Ink.green)
        .disabled(auth.busy)
        .sheet(isPresented: $emailForm) { NavigationStack { EmailAccountView() } }
        .accessibilityIdentifier("welcome-login")
        .alert("Sign-in isn't available yet", isPresented: Binding(get: { selectedMethod != nil }, set: { if !$0 { selectedMethod = nil } })) {
            Button("OK") { selectedMethod = nil }
        } message: {
            Text("\(selectedMethod ?? "Account") sign-in still needs account-service configuration. No account has been created and your saved financial data has not been opened.")
        }
    }
}

struct EmailAccountView: View {
    @Environment(AccountAuth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var create = false
    var body: some View {
        Form {
            Picker("Account", selection: $create) { Text("Sign In").tag(false); Text("Create Account").tag(true) }.pickerStyle(.segmented)
            TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password", text: $password).textContentType(create ? .newPassword : .password)
            if create { Text("Use at least 6 characters, or the stronger password required by this app’s account policy.").font(.caption) }
            Button(create ? "Create Account" : "Sign In") { Task { await auth.emailLogin(email, password: password, create: create) } }
                .disabled(!email.contains("@") || password.isEmpty || (create && password.count < 6) || auth.busy)
            Button("Forgot Password?") { Task { await auth.resetPassword(email) } }.disabled(!email.contains("@") || auth.busy)
            if auth.busy { ProgressView("Connecting…") }
            if let message = auth.message { Text(message).font(.footnote).foregroundStyle(Ink.warning) }
        }.paperForm().navigationTitle(create ? "Create Account" : "Sign In")
            .toolbar { Button("Close") { dismiss() }.disabled(auth.busy) }
            .interactiveDismissDisabled(auth.busy)
            .onDisappear { password = "" }
    }
}
