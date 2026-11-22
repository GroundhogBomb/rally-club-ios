import SwiftUI
import UIKit

@main
struct ProjectL: App {
    @State private var isShowingWelcome = true
    @StateObject private var versionGate = VersionGate()

#if DEBUG
    private static let showsCourtMapFixture = ProcessInfo.processInfo.arguments.contains("--court-map-ui-test")
    private static let showsGIFPostFixture = ProcessInfo.processInfo.arguments.contains("--feed-gif-ui-test")
#endif

    init() {
#if DEBUG
        if Self.showsCourtMapFixture || Self.showsGIFPostFixture {
            _isShowingWelcome = State(initialValue: false)
        }
        if ProcessInfo.processInfo.arguments.contains("--backend-decode-checks") {
            Task { await SupabaseAppDataRepository.runBackendDecodeContractChecks() }
        }
        if ProcessInfo.processInfo.arguments.contains("--reminder-persistence-checks") {
            Task { await SessionReminderStore.runPersistenceContractChecks() }
        }
        if ProcessInfo.processInfo.arguments.contains("--match-moment-pending-checks") {
            Task { MatchMomentPendingStorage.runContractChecks() }
        }
        if ProcessInfo.processInfo.arguments.contains("--version-gate-checks") {
            Task { VersionGate.runContractChecks() }
        }
#endif
        // Native segmented controls keep their behavior and labels; soften only the plates.
        let segments = UISegmentedControl.appearance()
        segments.backgroundColor = UIColor(Color.oliveSoft).withAlphaComponent(
            UIAccessibility.isReduceTransparencyEnabled ? 1 : CommunityCanvasStyle.segmentedTrackOpacity
        )
        segments.selectedSegmentTintColor = UIColor(Color.softCream).withAlphaComponent(
            UIAccessibility.isReduceTransparencyEnabled ? 1 : CommunityCanvasStyle.segmentedSelectionOpacity
        )
    }

    var body: some Scene {
        WindowGroup {
            appContent
                .foregroundStyle(AnyShapeStyle(.primary))
                .allowsHitTesting(!isShowingWelcome)
                .overlay {
                    if isShowingWelcome {
                        WelcomeView { isShowingWelcome = false }
                    }
                }
                .environment(\.locale, Locale(identifier: "en"))
                .tint(.olive)
                // Keep the release appearance stable until native dark tab contrast is verified.
                .preferredColorScheme(.light)
        }
    }

    @ViewBuilder private var appContent: some View {
#if DEBUG
        if Self.showsCourtMapFixture {
            let courts = SampleData.nearbyCourts
            CourtMapView(courts: courts, userLocation: nil, highlightedCourt: courts.first)
        } else if Self.showsGIFPostFixture {
            GIFPostFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--match-moment-pending-checks")
            || ProcessInfo.processInfo.arguments.contains("--version-gate-checks") {
            // Isolated contracts: do not create a session or resume real uploads.
            Color.clear
        } else {
#if DESIGN_REVIEW
            DesignReviewHost()
#else
            RootTabView(versionGate: versionGate, welcomeFinished: !isShowingWelcome)
#endif
        }
#else
        RootTabView(versionGate: versionGate, welcomeFinished: !isShowingWelcome)
#endif
    }
}

#if DEBUG
private struct GIFPostFixture: View {
    @State private var store = ClubFeedStore(
        repository: InMemoryAppDataRepository(),
        userID: CommunityDirectory.demoMember.id
    )

    var body: some View {
        NavigationStack {
            if let post = store.visiblePosts.first(where: { $0.gif != nil }) {
                FeedPostDetailView(postID: post.id, store: store)
            }
        }
    }
}
#endif

#if DEBUG && DESIGN_REVIEW
// Explicit build-only fixture. No production login bypass or remote writes.
private struct DesignReviewHost: View {
    @StateObject private var session: AppSession
    @State private var clubFeed: ClubFeedStore
    @State private var gameRequest: GameRequestStore
    @State private var profile: ProfileStore
    @StateObject private var reminders: SessionReminderStore
    private let arguments = ProcessInfo.processInfo.arguments

    init() {
        let userID = CommunityDirectory.demoMember.id
        let session = AppSession(previewUserID: userID)
        let arguments = ProcessInfo.processInfo.arguments
        let previewAnnouncement = arguments.contains("--announcement-long") ? ClubAnnouncement(
            id: 1,
            bodyZH: "",
            bodyEN: "The Northbank beginner session starts Saturday at 9 AM.\nBring a racket and water, and check in at the welcome table.",
            bodyJA: "",
            revision: 1, updatedAt: "2026-10-02T00:00:00Z") : nil
        let repository = InMemoryAppDataRepository(now: Date(timeIntervalSince1970: 1789200000),
            announcementPublisherIDs: arguments.contains("--announcement-admin") ? [userID] : [],
            announcement: previewAnnouncement)
        _session = StateObject(wrappedValue: session)
        _clubFeed = State(initialValue: ClubFeedStore(repository: repository, userID: userID))
        _gameRequest = State(initialValue: GameRequestStore(repository: repository, userID: userID))
        _profile = State(initialValue: ProfileStore(repository: repository, userID: userID))
        _reminders = StateObject(wrappedValue: SessionReminderStore(ownerID: userID))
    }

    var body: some View {
        Group {
            if arguments.contains("--sign-in") {
                SignInView(session: session)
            } else {
                CommunityTabView(session: session, clubFeedStore: clubFeed, gameRequestStore: gameRequest,
                    profileStore: profile, sessionReminderStore: reminders)
            }
        }

        .environment(\.dynamicTypeSize, arguments.contains("--large-text") ? .accessibility1 : .large)
        .task {
            if arguments.contains("--store-identity-checks") {
                await AppSession.runStoreIdentityContractChecks()
            }
        }
    }
}
#endif
