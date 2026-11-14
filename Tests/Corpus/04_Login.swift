import SwiftUI

// MARK: - Styling

struct LoginFieldStyle: ViewModifier {
    var isInvalid = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isInvalid ? Color.red : Color.clear, lineWidth: 1.5)
            }
    }
}

extension View {
    func loginField(isInvalid: Bool = false) -> some View {
        modifier(LoginFieldStyle(isInvalid: isInvalid))
    }
}

// MARK: - Subviews

struct LoginLogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 84, height: 84)
                .shadow(color: .purple.opacity(0.35), radius: 12, y: 6)
            Image(systemName: "leaf.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Sprout logo")
    }
}

struct LoginDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.quaternary).frame(height: 1)
            Text("or").font(.footnote).foregroundStyle(.secondary)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
    }
}

// MARK: - Screen

struct LoginScreen: View {
    enum Field { case email, password }

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isSubmitting = false
    @State private var didAttempt = false
    @FocusState private var focus: Field?

    private var emailValid: Bool { email.contains("@") && email.contains(".") }
    private var passwordValid: Bool { password.count >= 8 }
    private var showEmailError: Bool { didAttempt && !emailValid }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                LoginLogoMark().padding(.top, 40)
                VStack(spacing: 6) {
                    Text("Welcome back").font(.largeTitle.bold())
                    Text("Sign in to continue to Sprout")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .loginField(isInvalid: showEmailError)

                    HStack {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    }
                    .loginField(isInvalid: didAttempt && !passwordValid)

                    if showEmailError || (didAttempt && !passwordValid) {
                        Label(showEmailError ? "Enter a valid email address." : "Password must be at least 8 characters.",
                              systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button("Forgot password?") {}
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { didAttempt = true }
                    if emailValid && passwordValid { isSubmitting = true }
                } label: {
                    HStack {
                        if isSubmitting { ProgressView().tint(.white) }
                        Text(isSubmitting ? "Signing in" : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting)

                LoginDivider()

                VStack(spacing: 12) {
                    Button { } label: {
                        Label("Continue with Apple", systemImage: "apple.logo").frame(maxWidth: .infinity)
                    }
                    Button { } label: {
                        Label("Continue with Google", systemImage: "globe").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.primary)

                Text("By continuing you agree to our [Terms of Service](https://example.com/terms) and [Privacy Policy](https://example.com/privacy).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview {
    LoginScreen()
}

#Preview("Dark") {
    LoginScreen().preferredColorScheme(.dark)
}
