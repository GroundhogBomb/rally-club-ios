import SwiftUI

// MAINTENANCE-POINT: I18N-001
// English interface copy and the language code used by the app.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "English"

    var id: String { rawValue }

    var localeIdentifier: String { "en" }
}

struct AppCopy {
    var courtTab: String { String(localized: "Courts") }
    var clubFeedTab: String { String(localized: "Feed") }
    var gameRequestTab: String { String(localized: "Game requests") }
    var trainingLoungeTab: String { String(localized: "Training lounge") }
    var profileTab: String { String(localized: "Me") }
    var courtEyebrow: String { String(localized: "Court finder") }
    var clubFeedEyebrow: String { String(localized: "Club feed") }
    var gameRequestEyebrow: String { String(localized: "Join game") }
    var profileEyebrow: String { String(localized: "Player profile") }
    var appVersionLabel: String { String(localized: "Rally Club · V1") }
    var loadingTitle: String { String(localized: "Loading") }
    var noDataTitle: String { String(localized: "No data") }
    var noDataMessage: String {
        String(localized: "Be the first to share an update or start a game request.")
    }
    var homeStartTitle: String { String(localized: "Start here") }
    var homeStartMessage: String {
        String(localized: "Find a court, share a highlight in the club feed, or post a request to get a game going.")
    }
    var errorTitle: String { String(localized: "Unable to load") }
    var retryTitle: String { String(localized: "Retry") }
    var submittingTitle: String { String(localized: "Submitting…") }
    var submittedTitle: String { String(localized: "Submitted") }
    var submissionFailedTitle: String { String(localized: "Submission failed") }
    var dismissTitle: String { String(localized: "OK") }
    var retryUploadTitle: String { String(localized: "Retry") }
    var resendConfirmationTitle: String {
        String(localized: "Resend confirmation email")
    }
    var confirmationResentMessage: String {
        String(localized: "The confirmation email was sent again. Check your inbox, then return to sign in.")
    }

    var accountDeletionUnavailableTitle: String {
        String(localized: "Account deletion is not available yet")
    }

    var accountDeletionUnavailableMessage: String {
        String(localized: "The current deletion flow requires Apple reauthentication. This account is not linked to Apple, so it cannot be deleted in the app yet.")
    }

    func sessionErrorTitle(_ failure: SessionFailureKind) -> String {
        switch failure {
        case .emailConfirmationRequired:
            String(localized: "Confirm your email first")
        case .emailLinkExpired:
            String(localized: "Confirmation link expired")
        case .configurationMissing:
            String(localized: "Sign-in service is not configured")
        default:
            String(localized: "Unable to sign in")
        }
    }

    func sessionErrorMessage(_ failure: SessionFailureKind) -> String {
        switch failure {
        case .configurationMissing:
            String(localized: "Supabase is not configured in this build. Ask the developer to finish backend setup.")
        case .invalidEmail:
            String(localized: "Enter a valid email address.")
        case .invalidPassword:
            String(localized: "Your password must be at least 6 characters.")
        case .invalidCredentials:
            String(localized: "The email or password is incorrect. Check it and try again.")
        case .emailConfirmationRequired:
            String(localized: "Your account was created. Confirm your email, then return to sign in.")
        case .emailAlreadyRegistered:
            String(localized: "This email is already registered. Sign in or use another address.")
        case .emailProviderDisabled:
            String(localized: "Email sign-in is unavailable right now. Please try again later.")
        case .weakPassword:
            String(localized: "This password is too weak. Choose a stronger password.")
        case .emailRateLimited:
            String(localized: "There have been too many attempts. Please try again later.")
        case .emailLinkExpired:
            String(localized: "This confirmation link has expired or was already used. Resend the email and try again.")
        case .network:
            String(localized: "Check your network connection and try again.")
        case .invalidAppleCredential:
            String(localized: "The Apple sign-in credential could not be used. Please try again.")
        case .unavailable:
            String(localized: "Your profile could not be prepared after sign-in. Please try again later.")
        }
    }

    func mutationSubmittingTitle(_ context: RepositoryMutationContext) -> String {
        switch context {
        case .general:
            submittingTitle
        case .mediaUpload:
            String(localized: "Uploading media…")
        case .profileUpdate:
            String(localized: "Updating profile…")
        case .avatarUpload:
            String(localized: "Uploading avatar…")
        case .avatarRemove:
            String(localized: "Removing avatar…")
        }
    }

    func mutationSucceededTitle(_ context: RepositoryMutationContext) -> String {
        switch context {
        case .general:
            submittedTitle
        case .mediaUpload:
            String(localized: "Media uploaded and posted")
        case .profileUpdate:
            String(localized: "Profile updated")
        case .avatarUpload:
            String(localized: "Avatar updated")
        case .avatarRemove:
            String(localized: "Default avatar restored")
        }
    }

    func mutationFailedTitle(_ context: RepositoryMutationContext) -> String {
        switch context {
        case .general:
            submissionFailedTitle
        case .mediaUpload:
            String(localized: "Media upload failed")
        case .profileUpdate:
            String(localized: "Profile update failed")
        case .avatarUpload:
            String(localized: "Avatar upload failed")
        case .avatarRemove:
            String(localized: "Unable to remove avatar")
        }
    }

    func loadFailureMessage(_ failure: RepositoryFailure) -> String {
        switch failure.kind {
        case .network:
            String(localized: "Check your network connection and try again.")
        case .permission:
            String(localized: "You do not have permission to load this data. Sign in again and retry.")
        case .unavailable:
            String(localized: "The data could not be loaded. Please try again.")
        }
    }

    func mutationFailureMessage(_ failure: RepositoryFailure) -> String {
        switch failure.kind {
        case .network:
            String(localized: "The network is unavailable, so this change may not have been saved.")
        case .permission:
            String(localized: "You do not have permission to make this change.")
        case .unavailable:
            String(localized: "This change could not be saved. Please try again.")
        }
    }

    func feedReactionAction(isActive: Bool) -> String {
        isActive ? String(localized: "Liked") : String(localized: "Like")
    }

    func feedReactionCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 like") : String(localized: "\(count) likes")
    }

    func requestResponseAction(isActive: Bool) -> String {
        if isActive {
            return String(localized: "Joined")
        }
        return String(localized: "Join game")
    }

    func requestResponseCount(_ count: Int) -> String {
        return count == 1
            ? String(localized: "1 player joined")
            : String(localized: "\(count) players joined")
    }
}

private struct LocalizedBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss


    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel(String(localized: "Back"))
                    .accessibilityIdentifier("localized-back-button")
                }
            }
    }
}

extension View {
    func localizedBackButton() -> some View {
        modifier(LocalizedBackButtonModifier())
    }
}
