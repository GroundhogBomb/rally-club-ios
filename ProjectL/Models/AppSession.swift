import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import Supabase

enum AppSessionState: Equatable {
    case launching
    case signedOut
    case signingIn
    case creatingProfile
    case signedIn
    case demo
    case failed
}

enum SessionFailureKind: Equatable {
    case configurationMissing
    case invalidAppleCredential
    case invalidEmail
    case invalidPassword
    case invalidCredentials
    case emailConfirmationRequired
    case emailAlreadyRegistered
    case emailProviderDisabled
    case weakPassword
    case emailRateLimited
    case emailLinkExpired
    case network
    case unavailable
}

enum ConfirmationResendState: Equatable {
    case idle
    case sending
    case sent
}

enum BackendConfigurationStatus: Equatable {
    case configured
    case missing
}

enum AppAuthenticationProvider: Equatable {
    case email
    case apple
    case unknown
}

struct BackendConfiguration {
    let url: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) -> BackendConfiguration? {
        let rawURL = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let rawKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        guard
            let rawURL,
            let rawKey,
            !rawURL.isEmpty,
            !rawKey.isEmpty,
            !rawURL.contains("$("),
            !rawKey.contains("$("),
            !rawKey.contains("YOUR_"),
            let url = URL(string: rawURL),
            url.scheme == "https"
        else {
            return nil
        }
        return BackendConfiguration(url: url, publishableKey: rawKey)
    }
}

private actor SessionAccessTokenProvider {
    private var token: String?

    func update(_ token: String?) {
        self.token = token
    }

    func currentToken() -> String? {
        token
    }
}

// MAINTENANCE-POINT: AUTH-001
// Authentication, session restoration, and member setup.
@MainActor
final class AppSession: ObservableObject {
    static let authRedirectURL = URL(string: "projectl://auth/callback")

    @Published private(set) var state: AppSessionState = .launching
    @Published private(set) var failureKind: SessionFailureKind?
    @Published private(set) var authenticatedUserID: UUID?
    @Published private(set) var authenticationProvider: AppAuthenticationProvider = .unknown
    @Published private(set) var accountDeletionPending = false
    @Published private(set) var pendingConfirmationEmail: String?
    @Published private(set) var confirmationResendState: ConfirmationResendState = .idle

    let configurationStatus: BackendConfigurationStatus
    let client: SupabaseClient?
    let dataClient: SupabaseClient?

    private var rawNonce: String?
    private var authStateTask: Task<Void, Never>?
    private let accessTokenProvider: SessionAccessTokenProvider

    var canDeleteAccount: Bool {
        authenticationProvider == .apple || authenticationProvider == .email
    }

    func deleteEmailAccount(password: String) async throws {
        guard let client, authenticatedUserID != nil, authenticationProvider == .email else {
            throw SessionError.configurationMissing
        }
        do {
            try await client.functions.invoke("delete-account",
                options: FunctionInvokeOptions(body: ["password": password]))
        } catch {
            accountDeletionPending = (try? await client.rpc("account_deletion_pending").execute().value) ?? false
            throw error
        }
        await finishAccountDeletion()
    }

    private func finishAccountDeletion() async {
        ThumbnailLoader.clear()
        if let id = authenticatedUserID {
            SessionReminderStorage.clear(ownerID: id)
            MatchMomentPendingStorage.clear(ownerID: id)
        }
        try? await client?.auth.signOut(scope: .local)
        await accessTokenProvider.update(nil)
        authenticatedUserID = nil
        authenticationProvider = .unknown
        accountDeletionPending = false
        failureKind = nil
        pendingConfirmationEmail = nil
        confirmationResendState = .idle
        state = .signedOut
    }

    init(configuration: BackendConfiguration? = BackendConfiguration.load()) {
        let accessTokenProvider = SessionAccessTokenProvider()
        self.accessTokenProvider = accessTokenProvider
        if let configuration {
            configurationStatus = .configured
            let authClient = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.publishableKey,
                options: SupabaseClientOptions(
                    auth: .init(redirectToURL: Self.authRedirectURL)
                )
            )
            client = authClient
            dataClient = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.publishableKey,
                options: SupabaseClientOptions(
                    auth: .init(
                        redirectToURL: Self.authRedirectURL,
                        accessToken: {
                            await accessTokenProvider.currentToken()
                        }
                    )
                )
            )
        } else {
            configurationStatus = .missing
            client = nil
            dataClient = nil
            state = .signedOut
        }

        if client != nil {
            Task { await restoreSession() }
            observeAuthChanges()
        }
    }

#if DEBUG
    init(previewUserID: UUID) {
        accessTokenProvider = SessionAccessTokenProvider()
        configurationStatus = .missing
        client = nil
        dataClient = nil
        authenticatedUserID = previewUserID
        state = .signedIn
    }

    // AUTH-001: local regression only; the clientless session never touches real Auth or data.
    static func runStoreIdentityContractChecks() async {
        RepositoryContractChecks.run()
        let ownerID = CommunityDirectory.demoMember.id
        let nextUserID = CommunityDirectory.riley.id
        let session = AppSession(previewUserID: ownerID)
        let repository = InMemoryAppDataRepository(now: Date(timeIntervalSince1970: 1_750_000_000))
        let clubFeed = ClubFeedStore(repository: repository, userID: ownerID)
        let gameRequest = GameRequestStore(repository: repository, userID: ownerID)
        let profile = ProfileStore(repository: repository, userID: ownerID)
        let nickname = profile.nickname

        var privatePost = clubFeed.currentUserPosts[0]
        privatePost.visibility = .privateContent
        assert(clubFeed.updatePost(privatePost))
        clubFeed.addComment("identity-check", to: privatePost.id)
        var privateGameRequest = gameRequest.myRequests()[0]
        privateGameRequest.visibility = .privateContent
        assert(gameRequest.update(privateGameRequest))
        gameRequest.respond(to: privateGameRequest.id)
        let photo = MatchMoment(ownerID: ownerID, data: Data([0x01]),
            visibility: .privateContent, languageCode: .english)
        assert(repository.createMatchMoment(photo, requesterID: ownerID))

        // Suspend refreshProfiles before ProfileStore reads its default matchMoment owner.
        func suspendedRefresh() async -> (Task<Void, Never>, CheckedContinuation<Void, Never>) {
            var resumeRefresh: CheckedContinuation<Void, Never>?
            var refreshTask: Task<Void, Never>?
            await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
                repository.onRefreshProfiles = {
                    await withCheckedContinuation { resume in
                        resumeRefresh = resume
                        started.resume()
                    }
                }
                refreshTask = Task { await profile.refreshProfiles() }
            }
            repository.onRefreshProfiles = nil
            return (refreshTask!, resumeRefresh!)
        }
        let (signedOutRefresh, resumeSignedOutRefresh) = await suspendedRefresh()
        assert(session.authenticatedUserID == ownerID)
        session.authenticatedUserID = nil
        session.state = .signedOut
        assert(session.authenticatedUserID == nil)

        // Retained screens/tasks must still use A while the Auth session has no identity.
        assert(clubFeed.currentUser.id == ownerID)
        assert(clubFeed.post(id: privatePost.id)?.ownerID == ownerID)
        assert(clubFeed.currentUserPosts.contains { $0.id == privatePost.id })
        assert(clubFeed.comments(for: privatePost.id).contains { $0.text == "identity-check" })
        assert(gameRequest.currentUser.id == ownerID)
        assert(gameRequest.myRequests().contains { $0.id == privateGameRequest.id })
        assert(gameRequest.myResponses().contains { $0.id == privateGameRequest.id })
        assert(profile.nickname == nickname)
        assert(profile.matchMoments.contains { $0.id == photo.id })
        assert(profile.access(for: ownerID) == .ownerReadWrite)
        resumeSignedOutRefresh.resume()
        await signedOutRefresh.value
        assert(session.authenticatedUserID == nil)
        assert(repository.refreshedMatchMomentOwnerIDs == [ownerID])

        // A later login creates B's Stores; the retained A Stores never inherit B's UUID.
        let (switchedRefresh, resumeSwitchedRefresh) = await suspendedRefresh()
        session.authenticatedUserID = nextUserID
        session.state = .signedIn
        let nextClubFeed = ClubFeedStore(repository: repository, userID: nextUserID)
        let nextGameRequest = GameRequestStore(repository: repository, userID: nextUserID)
        let nextProfile = ProfileStore(repository: repository, userID: nextUserID)
        assert(nextClubFeed.currentUser.id == nextUserID)
        assert(!nextClubFeed.currentUserPosts.isEmpty)
        assert(nextClubFeed.currentUserPosts.allSatisfy { $0.ownerID == nextUserID })
        assert(nextClubFeed.post(id: privatePost.id) == nil)
        assert(!nextClubFeed.deletePost(id: privatePost.id))
        assert(!nextGameRequest.myRequests().isEmpty)
        assert(nextGameRequest.myRequests().allSatisfy { $0.ownerID == nextUserID })
        assert(!nextGameRequest.requests().contains { $0.id == privateGameRequest.id })
        assert(!nextGameRequest.delete(id: privateGameRequest.id))
        assert(nextProfile.access(for: ownerID) == .visitorReadOnly)
        assert(nextProfile.profile(for: nextUserID)?.nickname == nextProfile.nickname)
        assert(nextProfile.access(for: nextUserID) == .ownerReadWrite)
        assert(!nextProfile.updateProfile(for: ownerID, nickname: "wrong-user", signature: ""))
        assert(nextProfile.visibleMatchMoments(for: ownerID).isEmpty)
        for language in AppLanguage.allCases {
            assert(gameRequest.currentUser(for: language).id == ownerID)
            assert(nextGameRequest.currentUser(for: language).id == nextUserID)
        }

        resumeSwitchedRefresh.resume()
        await switchedRefresh.value
        assert(repository.refreshedMatchMomentOwnerIDs == [ownerID, ownerID])
        await profile.refreshProfiles(ownerID: nextUserID)
        await nextProfile.refreshProfiles()
        assert(repository.refreshedMatchMomentOwnerIDs == [ownerID, ownerID, nextUserID, nextUserID])
        assert(clubFeed.post(id: privatePost.id)?.ownerID == ownerID)
        assert(gameRequest.myRequests().contains { $0.id == privateGameRequest.id })
        assert(profile.nickname == nickname)
        print("STORE-IDENTITY-001 passed: cleared session, suspended refresh, account isolation")
    }
#endif

    deinit {
        authStateTask?.cancel()
    }

    func restoreSession() async {
        guard let client else {
            failureKind = .configurationMissing
            state = .failed
            return
        }

        state = .launching
        do {
            let session = try await client.auth.session
            try await finishAuthentication(
                userID: session.user.id,
                suggestedName: session.user.userMetadata["full_name"]?.stringValue,
                provider: Self.authenticationProvider(for: session.user),
                accessToken: session.accessToken
            )
        } catch let authError as AuthError where authError == .sessionMissing {
            authenticatedUserID = nil
            failureKind = nil
            state = .signedOut
        } catch {
            handleFailure(error)
        }
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        // A missing nonce makes completeAppleSignIn fail with invalidAppleCredential, never crash.
        rawNonce = Self.randomNonce()
        request.requestedScopes = [.fullName, .email]
        if let rawNonce { request.nonce = Self.sha256(rawNonce) }
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task {
            do {
                guard
                    let client,
                    let nonce = rawNonce,
                    case let .success(authorization) = result,
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    if case let .failure(error) = result {
                        throw error
                    }
                    throw SessionError.invalidAppleCredential
                }

                state = .signingIn
                let session = try await client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .apple,
                        idToken: idToken,
                        nonce: nonce
                    )
                )
                rawNonce = nil
                let name = credential.fullName.map {
                    PersonNameComponentsFormatter().string(from: $0)
                }
                if let name = name?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !name.isEmpty
                {
                    _ = try? await client.auth.update(
                        user: UserAttributes(data: ["full_name": .string(name)])
                    )
                }
                try await finishAuthentication(
                    userID: session.user.id,
                    suggestedName: name,
                    provider: .apple,
                    accessToken: session.accessToken
                )
            } catch {
                rawNonce = nil
                if Self.isCancellation(error) {
                    failureKind = nil
                    state = .signedOut
                    return
                }
                handleFailure(error)
            }
        }
    }

    func authenticateEmail(
        email: String,
        password: String,
        createAccount: Bool
    ) {
        guard state != .signingIn, state != .creatingProfile else { return }

        Task {
            do {
                guard let client else {
                    throw SessionError.configurationMissing
                }

                let normalizedEmail = email
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard Self.isValidEmail(normalizedEmail) else {
                    throw SessionError.invalidEmail
                }
                guard password.count >= 6 else {
                    throw SessionError.invalidPassword
                }

                state = .signingIn
                let session: Session
                if createAccount {
                    let response = try await client.auth.signUp(
                        email: normalizedEmail,
                        password: password,
                        redirectTo: Self.authRedirectURL
                    )
                    guard let createdSession = response.session else {
                        pendingConfirmationEmail = normalizedEmail
                        confirmationResendState = .idle
                        throw SessionError.emailConfirmationRequired
                    }
                    session = createdSession
                } else {
                    session = try await client.auth.signIn(
                        email: normalizedEmail,
                        password: password
                    )
                }

                try await finishAuthentication(
                    userID: session.user.id,
                    suggestedName: nil,
                    provider: .email,
                    accessToken: session.accessToken
                )
            } catch {
                handleFailure(error)
            }
        }
    }

#if DEBUG
    func authenticateTestIdentity(
        email: String,
        password: String,
        createAccount: Bool
    ) {
        authenticateEmail(
            email: email,
            password: password,
            createAccount: createAccount
        )
    }
#endif

    func continueInDemo() {
        guard configurationStatus == .missing, state == .signedOut else { return }
        state = .demo
    }

    func signOut() async {
        if state == .demo {
            state = .signedOut
            return
        }
        guard let client else { return }
        do {
            try await client.auth.signOut()
            ThumbnailLoader.clear()
            accountDeletionPending = false
            await accessTokenProvider.update(nil)
            authenticatedUserID = nil
            authenticationProvider = .unknown
            failureKind = nil
            pendingConfirmationEmail = nil
            confirmationResendState = .idle
            state = .signedOut
        } catch {
            handleFailure(error)
        }
    }

    func prepareAccountDeletion(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = []
    }

    func deleteAccount(
        authorization result: Result<ASAuthorization, Error>
    ) {
        Task {
            do {
                guard
                    let client,
                    case let .success(authorization) = result,
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let codeData = credential.authorizationCode,
                    let authorizationCode = String(data: codeData, encoding: .utf8)
                else {
                    if case let .failure(error) = result {
                        throw error
                    }
                    throw SessionError.invalidAppleCredential
                }

                try await client.functions.invoke(
                    "delete-account",
                    options: FunctionInvokeOptions(
                        body: ["authorization_code": authorizationCode]
                    )
                )
                await finishAccountDeletion()
            } catch {
                if Self.isCancellation(error) {
                    failureKind = nil
                    state = .signedIn
                    return
                }
                handleFailure(error)
            }
        }
    }

    func returnToSignIn() {
        guard authenticatedUserID == nil else {
            state = .signedIn
            return
        }
        failureKind = nil
        pendingConfirmationEmail = nil
        confirmationResendState = .idle
        state = configurationStatus == .configured ? .signedOut : .failed
    }

    private func finishAuthentication(
        userID: UUID,
        suggestedName: String?,
        provider: AppAuthenticationProvider,
        accessToken: String
    ) async throws {
        guard let client else { throw SessionError.configurationMissing }
        state = .creatingProfile
        let deleting: Bool = try await client.rpc("account_deletion_pending")
            .setHeader(name: "Authorization", value: "Bearer \(accessToken)").execute().value
        if deleting {
            await accessTokenProvider.update(accessToken)
            authenticatedUserID = userID
            authenticationProvider = provider
            accountDeletionPending = true
            state = .signedIn
            return
        }
        accountDeletionPending = false
        try await ProfileBootstrapper.ensureProfile(
            client: client,
            userID: userID,
            suggestedName: suggestedName,
            language: .english,
            accessToken: accessToken
        )
        await accessTokenProvider.update(accessToken)
        authenticatedUserID = userID
        authenticationProvider = provider
        failureKind = nil
        pendingConfirmationEmail = nil
        confirmationResendState = .idle
        state = .signedIn
    }

    func resendConfirmationEmail() {
        guard
            let client,
            let pendingConfirmationEmail,
            confirmationResendState != .sending
        else { return }

        confirmationResendState = .sending
        Task {
            do {
                try await client.auth.resend(
                    email: pendingConfirmationEmail,
                    type: .signup,
                    emailRedirectTo: Self.authRedirectURL
                )
                confirmationResendState = .sent
            } catch {
                confirmationResendState = .idle
                failureKind = Self.failureKind(for: error)
            }
        }
    }

    func handleAuthRedirect(_ url: URL) {
        guard
            let authRedirectURL = Self.authRedirectURL,
            url.scheme == authRedirectURL.scheme,
            url.host == authRedirectURL.host,
            url.path == authRedirectURL.path,
            let client,
            state != .signingIn,
            state != .creatingProfile
        else { return }

        Task {
            do {
                state = .signingIn
                let session = try await client.auth.session(from: url)
                try await finishAuthentication(
                    userID: session.user.id,
                    suggestedName: session.user.userMetadata["full_name"]?.stringValue,
                    provider: Self.authenticationProvider(for: session.user),
                    accessToken: session.accessToken
                )
            } catch {
                let mappedFailure = Self.failureKind(for: error)
                failureKind = mappedFailure == .unavailable ? .emailLinkExpired : mappedFailure
                state = .failed
            }
        }
    }

    private func observeAuthChanges() {
        guard let client else { return }
        authStateTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                if let session {
                    await self?.accessTokenProvider.update(session.accessToken)
                }
                if event == .signedOut || session == nil {
                    await self?.accessTokenProvider.update(nil)
                    guard self?.state != .launching else { continue }
                    self?.authenticatedUserID = nil
                    self?.authenticationProvider = .unknown
                    self?.state = .signedOut
                }
            }
        }
    }

    private func handleFailure(_ error: Error) {
        authenticatedUserID = nil
        authenticationProvider = .unknown
        failureKind = Self.failureKind(for: error)
        state = .failed
    }

    private static func authenticationProvider(for user: User) -> AppAuthenticationProvider {
        if user.identities?.contains(where: { $0.provider == "apple" }) == true {
            return .apple
        }
        if user.identities?.contains(where: { $0.provider == "email" }) == true || user.email != nil {
            return .email
        }
        return .unknown
    }


    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return false }
        return parts[0].isEmpty == false
            && parts[1].contains(".")
            && parts[1].first != "."
            && parts[1].last != "."
    }

    private static func failureKind(for error: Error) -> SessionFailureKind {
        if let sessionError = error as? SessionError {
            return sessionError.failureKind
        }

        if let authError = error as? AuthError {
            if case let .pkceGrantCodeExchange(message, nestedError, code) = authError {
                let detail = "\(message) \(nestedError ?? "") \(code ?? "")".lowercased()
                if detail.contains("expired")
                    || detail.contains("flow_state")
                    || detail.contains("code")
                {
                    return .emailLinkExpired
                }
            }

            switch authError.errorCode {
            case .flowStateExpired, .flowStateNotFound, .badCodeVerifier, .otpExpired:
                return .emailLinkExpired
            case .emailNotConfirmed:
                return .emailConfirmationRequired
            case .emailExists:
                return .emailAlreadyRegistered
            case .emailProviderDisabled:
                return .emailProviderDisabled
            case .weakPassword:
                return .weakPassword
            case .invalidCredentials:
                return .invalidCredentials
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return .emailRateLimited
            default:
                break
            }

            let message = authError.message.lowercased()
            if message.contains("email") && message.contains("invalid") {
                return .invalidEmail
            }
            if message.contains("network") || message.contains("offline") {
                return .network
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network
        }
        return .unavailable
    }

    private static func randomNonce(length: Int = 32) -> String? {
        guard length > 0 else { return nil }
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { return nil }
            if random < characters.count {
                result.append(characters[Int(random)])
                remaining -= 1
            }
        }
        return result
    }
}

private enum SessionError: Error {
    case configurationMissing
    case invalidAppleCredential
    case invalidEmail
    case invalidPassword
    case emailConfirmationRequired

    var failureKind: SessionFailureKind {
        switch self {
        case .configurationMissing:
            .configurationMissing
        case .invalidAppleCredential:
            .invalidAppleCredential
        case .invalidEmail:
            .invalidEmail
        case .invalidPassword:
            .invalidPassword
        case .emailConfirmationRequired:
            .emailConfirmationRequired
        }
    }
}

private enum ProfileBootstrapper {
    private struct ExistingProfile: Decodable {
        let user_id: UUID
    }

    private struct NewProfile: Encodable {
        let user_id: UUID
        let nickname: String
        let signature: String
        let language_code: String
        let visibility: String
        let match_moments_public: Bool
        let display_identity: String
    }

    static func ensureProfile(
        client: SupabaseClient,
        userID: UUID,
        suggestedName: String?,
        language: AppLanguage,
        accessToken: String
    ) async throws {
        let rows: [ExistingProfile] = try await client
            .from("profiles")
            .select("user_id")
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .setHeader(name: "Authorization", value: "Bearer \(accessToken)")
            .execute()
            .value
        guard rows.isEmpty else { return }

        let trimmedName = suggestedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname: String
        if let trimmedName, !trimmedName.isEmpty {
            nickname = trimmedName
        } else {
            nickname = neutralNickname(for: language)
        }

        try await client
            .from("profiles")
            .insert(
                NewProfile(
                    user_id: userID,
                    nickname: nickname,
                    signature: "",
                    language_code: AppLanguage.english.localeIdentifier,
                    visibility: "public",
                    match_moments_public: false,
                    display_identity: "public"
                )
            )
            .setHeader(name: "Authorization", value: "Bearer \(accessToken)")
            .execute()
    }

    private static func neutralNickname(for language: AppLanguage) -> String {
        String(localized: "Club member")
    }
}
