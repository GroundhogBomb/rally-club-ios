import Supabase
import SwiftUI

// AUTH-001
// Compose the authenticated community tabs and route authentication callbacks.
struct RootTabView: View {
    @ObservedObject var versionGate: VersionGate
    let welcomeFinished: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var mainReady = false
    @StateObject private var session = AppSession()

    private var canPresentVersionNotice: Bool {
        scenePhase == .active && welcomeFinished && mainReady && session.state == .signedIn
            && !session.accountDeletionPending && session.authenticatedUserID != nil
    }

    var body: some View {
        Group {
            switch session.state {
            case .launching, .signingIn, .creatingProfile:
                SessionProgressView(state: session.state)
            case .signedOut:
                SignInView(session: session)
            case .signedIn:
                if session.accountDeletionPending {
                    NavigationStack { AccountActionsView(session: session) }
                } else if let client = session.dataClient, let userID = session.authenticatedUserID {
                    SignedInTabView(
                        session: session,
                        stores: SignedInStores(
                            repository: SupabaseAppDataRepository(client: client, currentUserID: userID),
                            userID: userID
                        )
                    )
                    .id(userID)
                } else {
                    SignInView(session: session)
                }
            case .demo:
                SignedInTabView(
                    session: session,
                    stores: SignedInStores(
                        repository: InMemoryAppDataRepository(announcement: SampleData.clubAnnouncement),
                        userID: CommunityDirectory.demoMember.id
                    )
                )
                .environment(\.isDemoMode, true)
            case .failed:
                SessionErrorView(session: session)
            }
        }
        .onPreferenceChange(VersionGateReadyKey.self) { mainReady = $0 }
        .onChange(of: canPresentVersionNotice, initial: true) { _, value in
            versionGate.setReady(value)
        }
        .task(id: scenePhase) { versionGate.setActive(scenePhase == .active && session.configurationStatus == .configured) }
        .onDisappear { versionGate.setActive(false) }
        .modifier(VersionGatePresentation(gate: versionGate))

        .onOpenURL { url in
            session.handleAuthRedirect(url)
        }
    }
}

private struct DemoModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDemoMode: Bool {
        get { self[DemoModeKey.self] }
        set { self[DemoModeKey.self] = newValue }
    }
}

// StateObject evaluates the owning view's factory once for its mounted identity.
@MainActor
final class SignedInStores<Repository: AppDataRepository & ObservableObject>: ObservableObject {
    let repository: Repository
    let clubFeed: ClubFeedStore
    let gameRequests: GameRequestStore
    let profile: ProfileStore

    init(repository: Repository, userID: UUID) {
#if DEBUG
        RepositoryContractChecks.run()
#endif
        self.repository = repository
        clubFeed = ClubFeedStore(repository: repository, userID: userID)
        gameRequests = GameRequestStore(repository: repository, userID: userID)
        profile = ProfileStore(repository: repository, userID: userID)
    }
}

struct SignedInTabView<Repository: AppDataRepository & ObservableObject>: View {
    let session: AppSession
    @StateObject private var stores: SignedInStores<Repository>

    init(session: AppSession, stores: @autoclosure @escaping () -> SignedInStores<Repository>) {
        self.session = session
        _stores = StateObject(wrappedValue: stores())
    }

    var body: some View {
        SignedInTabContent(session: session, stores: stores)
    }
}

private struct SignedInTabContent<Repository: AppDataRepository & ObservableObject>: View {
    @ObservedObject var session: AppSession
    @ObservedObject private var repository: Repository
    @StateObject private var sessionReminderStore: SessionReminderStore
    @Environment(\.scenePhase) private var scenePhase
    private let stores: SignedInStores<Repository>

    init(session: AppSession, stores: SignedInStores<Repository>) {
        self.session = session
        self.stores = stores
        repository = stores.repository
        _sessionReminderStore = StateObject(wrappedValue: SessionReminderStore(ownerID: stores.profile.currentUserID))
    }

    private var copy: AppCopy { AppCopy() }

    private var versionGateReady: Bool {
        switch repository.loadState {
        case .loading, .failure: return false
        case .content, .empty:
            switch repository.mutationState {
            case .submitting, .failure: return false
            case .idle, .succeeded: return true
            }
        }
    }

    var body: some View {
        ZStack {
            switch repository.loadState {
            case .loading, .failure:
                RepositoryStateView(
                    state: repository.loadState,
                    retry: {
                        Task { try? await repository.synchronize() }
                    }
                )
                .background { CommunityBackdrop() }
            case .content, .empty:
                CommunityTabView(session: session, clubFeedStore: stores.clubFeed,
                    gameRequestStore: stores.gameRequests, profileStore: stores.profile,
                    sessionReminderStore: sessionReminderStore)
            }

            mutationStatus
                .zIndex(2)
        }
        .preference(key: VersionGateReadyKey.self, value: versionGateReady)
        .task {
            try? await repository.synchronize()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await repository.refreshProfiles()
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { try? await repository.synchronize() }
        }
        .onChange(of: repository.mutationState) { _, state in
            guard state == .succeeded else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard repository.mutationState == .succeeded else { return }
                repository.clearMutationState()
            }
        }
        .onDisappear {
            // Local reminders belong to this signed-in identity. Stop pending
            // notifications when the signed-in surface leaves after logout;
            // the stored reminders are restored on the next signed-in session.
            sessionReminderStore.cancelAllScheduledNotifications()
        }
        .alert(
            copy.mutationFailedTitle(repository.mutationContext),
            isPresented: Binding(
                get: {
                    if case .failure = repository.mutationState { return true }
                    return false
                },
                set: { isPresented in
                    if !isPresented { repository.clearMutationState() }
                }
            )
        ) {
            if repository.canRetryLastMutation {
                Button(copy.retryUploadTitle) {
                    repository.retryLastMutation()
                }
            }
            Button(copy.dismissTitle) {
                repository.clearMutationState()
            }
        } message: {
            if case let .failure(failure) = repository.mutationState {
                Text(copy.mutationFailureMessage(failure))
            }
        }
    }

    @ViewBuilder
    private var mutationStatus: some View {
        switch repository.mutationState {
        case .submitting:
            statusBanner(
                title: copy.mutationSubmittingTitle(repository.mutationContext),
                systemImage: "arrow.triangle.2.circlepath"
            )
        case .succeeded:
            statusBanner(
                title: copy.mutationSucceededTitle(repository.mutationContext),
                systemImage: "checkmark.circle.fill"
            )
        case .idle, .failure:
            EmptyView()
        }
    }

    private func statusBanner(title: String, systemImage: String) -> some View {
        VStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Color.inkBrown)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.inkBrown)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .warmCanvas()
            .clipShape(Capsule())
            .shadow(color: Color.inkBrown.opacity(0.12), radius: 10, y: 4)
            .padding(.top, 12)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// The same native navigation is used by the app and isolated design previews.
struct CommunityTabView: View {
    @State private var selectedTab = CommunityTabIcon.court
    @Environment(\.isDemoMode) private var isDemoMode
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var session: AppSession
    let clubFeedStore: ClubFeedStore
    let gameRequestStore: GameRequestStore
    let profileStore: ProfileStore
    @ObservedObject var sessionReminderStore: SessionReminderStore
    private var copy: AppCopy { AppCopy() }

    var body: some View {
        VStack(spacing: 0) {
            if isDemoMode {
                Text(String(localized: "Demo mode"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.olive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        Color.oliveSoft.ignoresSafeArea(edges: .top)
                    }
            }
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            CourtView(sessionReminderStore: sessionReminderStore, isDemoMode: isDemoMode)
                .tabItem { tabLabel(copy.courtTab, icon: .court) }
                .tag(CommunityTabIcon.court)
            ClubFeedView(store: clubFeedStore, gameRequestStore: gameRequestStore, profileStore: profileStore)
                .tabItem { tabLabel(copy.clubFeedTab, icon: .clubFeed) }
                .tag(CommunityTabIcon.clubFeed)
            TrainingLoungeView()
                .tabItem { tabLabel(copy.trainingLoungeTab, icon: .gameRequest) }
                .tag(CommunityTabIcon.gameRequest)
            ProfileView(profileStore: profileStore, clubFeedStore: clubFeedStore,
                gameRequestStore: gameRequestStore, session: session, sessionReminderStore: sessionReminderStore)
                .tabItem { tabLabel(copy.profileTab, icon: .profile) }
                .tag(CommunityTabIcon.profile)
        }
        .toolbarBackground(CommunityCanvasStyle.tabBackground(reduceTransparency: reduceTransparency), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        // Keep native navigation, selection, and geometry; only change appearance.
        .tint(.primary)
    }

    private func tabLabel(_ title: String, icon: CommunityTabIcon) -> some View {
        Label(title, systemImage: icon.rawValue)
    }
}
