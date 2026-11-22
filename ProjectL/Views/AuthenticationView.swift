import AuthenticationServices
import SwiftUI

// AUTH-001
// Email and Apple sign-in forms.
struct SignInView: View {
    @ObservedObject var session: AppSession
    @State private var isShowingPrivacy = false
    @Environment(\.colorScheme) private var colorScheme

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("RallyAvatar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Welcome to Rally Club"))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.inkBrown)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(String(localized: "Rally Club"))
                            .font(.subheadline)
                            .foregroundStyle(Color.mutedBrown)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if session.configurationStatus == .missing {
                    Text(String(localized: "Explore a fictional club. Posts and game requests stay in this demo session, and reminders stay on this device."))
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedBrown)
                    Button {
                        session.continueInDemo()
                    } label: {
                        Label(String(localized: "Continue in demo mode"), systemImage: "tennis.racket")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .accessibilityIdentifier("continue-demo")
                } else {
                    EmailAuthForm(session: session)

                    Button(String(localized: "Privacy policy")) {
                        isShowingPrivacy = true
                    }
                    .font(.footnote)
                    .frame(minHeight: 44)

                    VStack(spacing: 18) {
                        HStack(spacing: 14) {
                            Rectangle().fill(Color.appSeparator).frame(height: 1)
                            Text(String(localized: "Or use Apple"))
                                .font(.footnote)
                                .foregroundStyle(Color.mutedBrown)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Rectangle().fill(Color.appSeparator).frame(height: 1)
                        }

                        SignInWithAppleButton(
                            .signIn,
                            onRequest: session.prepareAppleSignIn,
                            onCompletion: session.completeAppleSignIn
                        )
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("sign-in-with-apple-button")

                        Text(String(localized: "Your Apple email is never shown publicly."))
                        .font(.caption)
                        .foregroundStyle(Color.mutedBrown)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }

#if DEBUG
                    Divider()
                        .overlay(Color.appSeparator)

                    TestIdentitySignInView(session: session)
#endif
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { CommunityBackdrop() }
        .sheet(isPresented: $isShowingPrivacy) {
            NavigationStack {
                Form { PrivacyPolicyContent() }
                    .navigationTitle(String(localized: "Privacy policy"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button(copy.dismissTitle) { isShowingPrivacy = false } }
            }
        }
    }
}

private struct EmailAuthForm: View {
    @ObservedObject var session: AppSession
    @State private var email = ""
    @State private var password = ""
    @State private var createsAccount = false
    @State private var localFailure: SessionFailureKind?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
    }

    private var copy: AppCopy { AppCopy() }
    private var isSubmitting: Bool {
        session.state == .signingIn || session.state == .creatingProfile
    }
    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker(
                String(localized: "Account action"),
                selection: $createsAccount
            ) {
                Text(String(localized: "Sign in")).tag(false)
                Text(String(localized: "Create account")).tag(true)
            }
            .pickerStyle(.segmented)
            .warmSegmentedCanvas()
            .accessibilityIdentifier("email-auth-mode")

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Email"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.inkBrown)

                TextField("name@example.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .padding(15)
                    .frame(minHeight: 52)
                    .warmCanvas()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(focusedField == .email ? Color.olive : Color.appSeparator, lineWidth: 1)
                    }
                    .accessibilityLabel(String(localized: "Email"))
                    .accessibilityIdentifier("email-auth-email")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Password"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.inkBrown)

                SecureField(
                    String(localized: "At least 6 characters"),
                    text: $password
                )
                .textContentType(createsAccount ? .newPassword : .password)
                .focused($focusedField, equals: .password)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .padding(15)
                .frame(minHeight: 52)
                .warmCanvas()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focusedField == .password ? Color.olive : Color.appSeparator, lineWidth: 1)
                }
                .accessibilityLabel(String(localized: "Password"))
                .accessibilityIdentifier("email-auth-password")
            }

            if let localFailure {
                Text(copy.sessionErrorMessage(localFailure))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(
                createsAccount
                    ? String(localized: "Create and sign in")
                    : String(localized: "Sign in with email")
            ) {
                focusedField = nil
                submit()
            }
            .buttonStyle(AppActionButtonStyle())
            .tint(Color.olive)
            .frame(maxWidth: .infinity)
            .disabled(!canSubmit || isSubmitting)
            .accessibilityIdentifier("email-auth-submit")
        }
    }

    private func submit() {
        let normalizedEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard Self.isValidEmail(normalizedEmail) else {
            localFailure = .invalidEmail
            return
        }
        guard password.count >= 6 else {
            localFailure = .invalidPassword
            return
        }
        localFailure = nil
        session.authenticateEmail(
            email: normalizedEmail,
            password: password,
            createAccount: createsAccount
        )
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return false }
        return parts[0].isEmpty == false
            && parts[1].contains(".")
            && parts[1].first != "."
            && parts[1].last != "."
    }
}

struct SessionProgressView: View {
    let state: AppSessionState


    private var statusText: String {
        switch state {
        case .signingIn:
            String(localized: "Signing in…")
        case .creatingProfile:
            String(localized: "Creating your profile…")
        default:
            String(localized: "Checking your session…")
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.olive)
            Text(statusText)
            .foregroundStyle(Color.mutedBrown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { CommunityBackdrop() }
    }
}

#if DEBUG
private struct TestIdentitySignInView: View {
    @ObservedObject var session: AppSession
    @State private var email = ""
    @State private var password = ""
    @State private var createsAccount = false

    private var canSubmit: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
        && password.count >= 6
    }
    private var isSubmitting: Bool {
        session.state == .signingIn || session.state == .creatingProfile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Phase 3 test identity"))
                .font(.headline)
                .foregroundStyle(Color.inkBrown)

            Text(String(localized: "Debug-only Supabase verification. This is excluded from release builds."))
            .font(.caption)
            .foregroundStyle(Color.mutedBrown)

            TextField(
                String(localized: "Test email"),
                text: $email
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .textContentType(.username)
            .padding(12)
            .warmCanvas()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("test-identity-email")

            SecureField(
                String(localized: "Test password"),
                text: $password
            )
            .textContentType(.password)
            .padding(12)
            .warmCanvas()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("test-identity-password")

            Toggle(
                String(localized: "Create a new test account"),
                isOn: $createsAccount
            )
            .font(.subheadline)
            .tint(Color.olive)

            Button(
                createsAccount
                    ? String(localized: "Create and sign in")
                    : String(localized: "Sign in with test identity")
            ) {
                session.authenticateTestIdentity(
                    email: email,
                    password: password,
                    createAccount: createsAccount
                )
            }
            .buttonStyle(AppActionButtonStyle())
            .tint(Color.olive)
            .frame(maxWidth: .infinity)
            .disabled(!canSubmit || isSubmitting)
            .accessibilityIdentifier("test-identity-submit")
        }
    }
}
#endif

struct SessionErrorView: View {
    @ObservedObject var session: AppSession

    private var copy: AppCopy { AppCopy() }
    private var failure: SessionFailureKind {
        session.failureKind ?? .unavailable
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 42))
                .foregroundStyle(Color.warmGold)
            Text(copy.sessionErrorTitle(failure))
                .font(.title2.bold())
                .foregroundStyle(Color.inkBrown)
            Text(copy.sessionErrorMessage(failure))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.mutedBrown)

            if failure == .emailConfirmationRequired,
               session.pendingConfirmationEmail != nil
            {
                if session.confirmationResendState == .sent {
                    Text(copy.confirmationResentMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.olive)
                }

                Button(copy.resendConfirmationTitle) {
                    session.resendConfirmationEmail()
                }
                .buttonStyle(AppActionButtonStyle(isPrimary: false))
                .tint(Color.olive)
                .disabled(session.confirmationResendState == .sending)
            }

            if session.configurationStatus == .configured {
                Button(String(localized: "Back to sign in")) {
                    session.returnToSignIn()
                }
                .buttonStyle(AppActionButtonStyle())
                .tint(Color.olive)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { CommunityBackdrop() }
    }
}

struct AccountActionsView: View {
    @ObservedObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false
    @State private var isAuthorizingDeletion = false

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        Form {
            if session.accountDeletionPending {
                Section {
                    Text(String(localized: "Account deletion is incomplete. Run deletion again to finish cleanup; community access is disabled meanwhile."))
                }
            }
            Section {
                Button(session.state == .demo ? String(localized: "Exit demo mode") : String(localized: "Sign out")) {
                    Task { await session.signOut() }
                }
                .foregroundStyle(Color.olive)
            }
            .listRowBackground(WarmCanvas())

            if session.state == .demo {
                Section {
                    Text(String(localized: "The demo uses a fictional member. Posts and game requests reset when you exit."))
                }
                .listRowBackground(WarmCanvas())
            } else if session.canDeleteAccount {
                Section {
                    Button(
                        String(localized: "Delete account"),
                        role: .destructive
                    ) {
                        isConfirmingDeletion = true
                    }
                } footer: {
                    Text(String(localized: "Deletion permanently removes your account, profile, posts, comments, likes, game requests, games joined, and photos. Verify again, and retry if interrupted to finish cleanup."))
                }
                .listRowBackground(WarmCanvas())
            } else {
                Section {
                    Label(
                        copy.accountDeletionUnavailableTitle,
                        systemImage: "lock.trianglebadge.exclamationmark"
                    )
                    .foregroundStyle(Color.mutedBrown)
                } footer: {
                    Text(copy.accountDeletionUnavailableMessage)
                }
                .listRowBackground(WarmCanvas())
            }
        }
        .scrollContentBackground(.hidden)
        .background { CommunityBackdrop() }
        .navigationTitle(String(localized: "Account settings"))
        .localizedBackButton()
        .confirmationDialog(
            String(localized: "Delete account permanently?"),
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Continue"),
                role: .destructive
            ) {
                isAuthorizingDeletion = true
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $isAuthorizingDeletion) {
            DeleteAccountAuthorizationView(session: session)
        }
    }
}

private struct DeleteAccountAuthorizationView: View {
    @ObservedObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isDeleting = false
    @State private var failed = false

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 42))
                .foregroundStyle(.red)
            Text(String(localized: "Verify again to permanently delete the account and its related data."))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.mutedBrown)

            if session.authenticationProvider == .email {
                SecureField(String(localized: "Current password"), text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDeleting)
                Button(String(localized: "Delete permanently"), role: .destructive) {
                    isDeleting = true
                    Task {
                        defer { isDeleting = false; password = "" }
                        do { try await session.deleteEmailAccount(password: password); dismiss() }
                        catch { failed = true }
                    }
                }
                .disabled(password.isEmpty || isDeleting)
                if isDeleting { ProgressView() }
            } else {
                SignInWithAppleButton(
                .continue,
                onRequest: session.prepareAccountDeletion,
                onCompletion: session.deleteAccount
            )
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(String(localized: "Cancel")) {
                dismiss()
            }
        }
        .padding(28)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isDeleting)
        .alert(String(localized: "Deletion not complete"), isPresented: $failed) {
            Button(copy.dismissTitle, role: .cancel) {}
        } message: {
            Text(String(localized: "Check your password and connection, then retry. Contact the developer if it still fails; never send anyone your password."))
        }
    }
}
