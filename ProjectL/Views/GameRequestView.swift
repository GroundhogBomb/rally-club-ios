import SwiftUI
import UIKit

struct GameRequestView: View {
    let store: GameRequestStore
    let profileStore: ProfileStore
    @State private var isShowingComposer = false

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        PageHeader(
                            eyebrow: copy.gameRequestEyebrow,
                            title: copy.gameRequestTab,
                            subtitle: String(localized: "Find people to play with.")
                        )

                        Button {
                            isShowingComposer = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(AppIconButtonStyle())
                        .padding(.top, 2)
                        .accessibilityLabel(String(localized: "New game request"))
                        .accessibilityIdentifier("create-game-request-button")
                    }
                    .padding(.bottom, 5)

                    GameRequestFeedContent(store: store)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background { CommunityBackdrop() }
            .navigationDestination(for: CommunityUser.self) { user in
                UserProfileView(user: user, profileStore: profileStore)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $isShowingComposer) {
                CreateGameRequestView(store: store)
            }
        }
    }
}

// GAME-REQUEST-001
// List content only: callers own scrolling, navigation and the composer.
struct GameRequestFeedContent: View {
    let store: GameRequestStore
    var body: some View {
        let requests = store.requests()
        if requests.isEmpty {
            RepositoryStateView(state: .empty, retry: nil)
                .padding(.horizontal, -20)
        } else {
            ForEach(requests) { gameRequest in
                GameRequestCard(
                    gameRequest: gameRequest,
                    author: store.displayIdentity(for: gameRequest),
                    hasResponded: store.hasResponded(for: gameRequest.id),
                    responseCount: store.responseCount(for: gameRequest),
                    isSubmitting: store.isSubmitting,
                    onRespond: { store.respond(to: gameRequest.id) },
                    canBlock: !gameRequest.isAnonymous && gameRequest.ownerID != store.currentUserID,
                    onReport: { try await store.report(id: gameRequest.id, reason: $0) },
                    onBlock: { try await store.block(gameRequest.ownerID) }
                )
            }
        }
        if store.hasMore { FeedMoreButton { try await store.loadMore() } }
    }
}

// The fourth tab deliberately has no GameRequestStore or data-loading actions.
struct TrainingLoungeView: View {
    private var copy: AppCopy { AppCopy() }
    private var message: String {
        String(localized: "A space for players to share drills and practice plans is coming soon.")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        PageHeader(eyebrow: "", title: copy.trainingLoungeTab, subtitle: message)
                        WarmCard {
                            VStack(spacing: 22) {
                                Image("TrainingLoungePlaceholder")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 300)
                                    .accessibilityHidden(true)
                                Text(String(localized: "Under construction"))
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(Color.inkBrown)
                                    .accessibilityAddTraits(.isHeader)
                                Text(message)
                                    .font(.body)
                                    .foregroundStyle(Color.inkBrown)
                                    .lineSpacing(6)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 170))
                            .padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background { CommunityBackdrop() }
            .navigationBarHidden(true)
        }
    }
}

private struct GameRequestCard: View {
    let gameRequest: GameRequest
    let author: GameRequestIdentity
    let hasResponded: Bool
    let responseCount: Int
    let isSubmitting: Bool
    let onRespond: () -> Void
    let canBlock: Bool
    let onReport: (String) async throws -> Void
    let onBlock: () async throws -> Void

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    authorHeader
                    CommunitySafetyMenu(canBlock: canBlock, onReport: onReport, onBlock: onBlock)
                }

                Text(gameRequest.title)
                    .font(.headline)
                    .foregroundStyle(Color.inkBrown)

                Text(gameRequest.body)
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedBrown)
                    .lineSpacing(4)

                Button(action: onRespond) {
                    Label(
                        copy.requestResponseAction(isActive: hasResponded),
                        systemImage: hasResponded ? "tennisball.fill" : "tennisball"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.olive)
                }
                .buttonStyle(AppReactionButtonStyle(isActive: hasResponded))
                .disabled(isSubmitting)
                .accessibilityIdentifier("game-request-response-button-\(gameRequest.id.uuidString)")

                Text(copy.requestResponseCount(responseCount))
                .font(.caption)
                .foregroundStyle(Color.mutedBrown)
                .accessibilityIdentifier("game-request-response-count-\(gameRequest.id.uuidString)")
            }
        }
    }

    @ViewBuilder
    private var authorHeader: some View {
        if let user = author.publicUser {
            NavigationLink(value: user) {
                GameRequestAuthorLabel(
                    avatar: user.profile.publicAvatarFallback,
                    avatarData: user.profile.publicAvatarData,
                    avatarRemoteURL: user.profile.publicAvatarURL,
                    nickname: user.nickname,
                    time: gameRequest.timeLabel(interfaceLanguage: .english)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "View \(user.nickname)'s profile"))
            .accessibilityIdentifier("public-game-request-author-\(gameRequest.id.uuidString)")
        } else {
            GameRequestAuthorLabel(
                avatar: author.avatar,
                avatarData: nil,
                avatarRemoteURL: nil,
                nickname: author.nickname(for: .english),
                time: gameRequest.timeLabel(interfaceLanguage: .english)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Anonymous player"))
            .accessibilityIdentifier("anonymous-game-request-author-\(gameRequest.id.uuidString)")
        }
    }
}

private struct GameRequestAuthorLabel: View {
    let avatar: String
    let avatarData: Data?
    let avatarRemoteURL: URL?
    let nickname: String
    let time: String

    var body: some View {
        HStack(spacing: 11) {
            CommunityAvatarImage(
                avatarData: avatarData,
                remoteURL: avatarRemoteURL,
                fallbackAsset: avatar,
                size: 42
            )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(nickname)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkBrown)
                Text(time)
                    .font(.caption)
                    .foregroundStyle(Color.mutedBrown)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
