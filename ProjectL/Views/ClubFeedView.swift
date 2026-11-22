import SwiftUI
import UIKit

struct ClubFeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    let store: ClubFeedStore
    let gameRequestStore: GameRequestStore
    let profileStore: ProfileStore
    @State private var selectedSection = ClubFeedSection.sharing
    @State private var composer: ClubFeedSection?
    @State private var isShowingAnnouncement = false

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        PageHeader(
                            eyebrow: copy.clubFeedEyebrow,
                            title: copy.clubFeedTab,
                            subtitle: String(localized: "Talk about your games, drills, and favorite courts.")
                        )
                        Button {
                            // Capture the selected section now; the sheet never reads a later selection.
                            composer = selectedSection
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(AppIconButtonStyle())
                        .padding(.top, 2)
                        .accessibilityLabel(selectedSection == .sharing
                            ? String(localized: "Create post")
                            : String(localized: "New game request"))
                        .accessibilityIdentifier(selectedSection == .sharing ? "create-post-button" : "create-game-request-button")
                    }
                    sectionPicker

                    if selectedSection == .sharing {
                        sharingContent
                    } else {
                        GameRequestFeedContent(store: gameRequestStore)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background { CommunityBackdrop() }
            .navigationDestination(for: UUID.self) { postID in
                FeedPostDetailView(postID: postID, store: store)
            }
            .navigationDestination(for: CommunityUser.self) { user in
                UserProfileView(user: user, profileStore: profileStore)
            }
            .navigationDestination(isPresented: $isShowingAnnouncement) {
                ClubAnnouncementDetailView(store: store)
            }
            .navigationBarHidden(true)
            .sheet(item: $composer) { section in
                switch section {
                case .sharing: CreatePostView(store: store)
                case .gameRequests: CreateGameRequestView(store: gameRequestStore)
                }
            }
            .task { try? await store.refreshAnnouncement() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { try? await store.refreshAnnouncement() }
            }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 2) {
            ForEach(ClubFeedSection.allCases) { section in
                Button { selectedSection = section } label: {
                    Text(section.title(for: .english))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppReactionButtonStyle(isActive: selectedSection == section))
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .accessibilityIdentifier("club-feed-section-\(section.rawValue)")
            }
        }
        .padding(4)
        .warmCanvas()
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Color.appSeparator, lineWidth: 0.5) }
    }

    @ViewBuilder
    private var sharingContent: some View {
        // CLUB-ANNOUNCEMENT-001 — Permanent announcement surface.
        ClubAnnouncementBar(store: store) { isShowingAnnouncement = true }

        let posts = store.visiblePosts
        if posts.isEmpty {
            WarmCard {
                ContentUnavailableView(
                    store.hasMore
                        ? String(localized: "No matches in loaded posts")
                        : String(localized: "No posts yet"),
                    systemImage: "text.bubble",
                    description: Text(store.hasMore ? String(localized: "Load more posts to see earlier updates.") : String(localized: "You can be the first to share here."))
                )
            }
        } else {
            ForEach(posts) { post in
                FeedPostCard(postID: post.id, store: store)
            }
        }
        if store.hasMore {
            FeedMoreButton { try await store.loadMore() }
        }
    }
}

private enum ClubFeedSection: String, CaseIterable, Identifiable {
    case sharing, gameRequests
    var id: String { rawValue }
    func title(for language: AppLanguage) -> String {

        switch self {
        case .sharing: return String(localized: "Sharing")
        case .gameRequests: return String(localized: "Game requests")
        }
    }
}

private struct AnnouncementWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ClubAnnouncementBar: View {
    let store: ClubFeedStore
    @ScaledMetric(relativeTo: .subheadline) private var previewFontSize: CGFloat = 15
    @State private var textWidth: CGFloat = 0
    let open: () -> Void
    private var copy: AppCopy { AppCopy() }
    private var message: String { store.announcement?.bodyEN ?? "" }
    private var failed: Bool {
        if case .failure = store.announcementLoadState { return true }
        return false
    }
    private var isTruncated: Bool {
        // Match the two-line SwiftUI preview, including explicit paragraph breaks.
        guard textWidth > 0, !message.isEmpty else { return false }
        let font = UIFont.systemFont(ofSize: previewFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let height = (message as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph], context: nil).height
        return height > font.lineHeight * 2 + 4 + 1
    }

    var body: some View {
        Button {
            if failed && message.isEmpty {
                Task { try? await store.refreshAnnouncement() }
            } else { open() }
        } label: {
            WarmCard {
                VStack(alignment: .leading, spacing: 7) {
                    if !message.isEmpty {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkBrown)
                            .lineSpacing(4)
                            .lineLimit(2, reservesSpace: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: AnnouncementWidthKey.self, value: geometry.size.width)
                                }
                            }
                        if isTruncated {
                            Text(String(localized: "… Read full announcement"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.mutedBrown)
                        }
                    } else if failed {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.mutedBrown)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .disabled(message.isEmpty && !store.canManageAnnouncement && !failed)
        .accessibilityHidden(message.isEmpty && !store.canManageAnnouncement && !failed)
        .accessibilityLabel(failed && message.isEmpty ? copy.retryTitle
            : String(localized: "Administrator announcement"))
        .accessibilityValue(message)
        .accessibilityIdentifier("clubFeed-announcement-bar")
        .onPreferenceChange(AnnouncementWidthKey.self) { textWidth = $0 }
    }
}

private struct ClubAnnouncementDetailView: View {
    let store: ClubFeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            WarmCard {
                Text(store.announcement?.bodyEN ?? "")
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                    .foregroundStyle(Color.inkBrown)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("clubFeed-announcement-full-text")
            }
            .padding(16)
        }
        .background { CommunityBackdrop() }
        .refreshable { try? await store.refreshAnnouncement() }
        .navigationBarHidden(false)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(String(localized: "Administrator announcement"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(String(localized: "Back"))
            }
            if store.canManageAnnouncement {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isEditing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel(String(localized: "Edit announcement"))
                        .accessibilityIdentifier("edit-announcement-button")
                }
            }
        }
        .sheet(isPresented: $isEditing) { ClubAnnouncementEditor(store: store) }
        .onChange(of: isEditing) { _, editing in
            if !editing { Task { try? await store.refreshAnnouncement() } }
        }
    }
}

private struct ClubAnnouncementEditor: View {
    let store: ClubFeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText: String
    @State private var isSaving = false
    @State private var isShowingError = false
    @State private var saveError: Error?
    private let revision: Int
    private var copy: AppCopy { AppCopy() }
    private var characterCount: Int {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    init(store: ClubFeedStore) {
        self.store = store
        revision = store.announcement?.revision ?? 0
        _bodyText = State(initialValue: store.announcement?.bodyEN ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextEditor(text: $bodyText)
                        .font(.body).scrollContentBackground(.hidden)
                        .padding(10).frame(minHeight: 200)
                        .warmCanvas().clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel(String(localized: "Announcement content"))
                        .accessibilityIdentifier("announcement-body-editor")
                    Text("\(characterCount) / \(ClubAnnouncementDraft.maximumLength)")
                        .font(.caption).foregroundStyle(Color.mutedBrown)
                }
                .padding(16)
                .disabled(isSaving)
            }
            .background { CommunityBackdrop() }
            .navigationTitle(String(localized: "Edit announcement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSaving = true
                        Task {
                            do {
                                try await store.saveAnnouncement(bodyText, expectedRevision: revision)
                                dismiss()
                            } catch {
                                saveError = error
                                isShowingError = true
                            }
                            isSaving = false
                        }
                    } label: {
                        if isSaving { ProgressView() }
                        else { Text(String(localized: "Save")) }
                    }
                    .disabled(isSaving || characterCount > ClubAnnouncementDraft.maximumLength
                        || !store.canManageAnnouncement)
                    .accessibilityIdentifier("save-announcement-button")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert(String(localized: "Announcement not saved"), isPresented: $isShowingError) {
                Button(copy.dismissTitle) {}
            } message: { Text(errorMessage) }
        }
    }

    private var errorMessage: String {
        if let error = saveError as? ClubAnnouncementError, case .conflict = error {
            return String(localized: "The announcement changed elsewhere. Your text is retained. Go back and reload the announcement before editing again.")
        }
        if let error = saveError as? ClubAnnouncementError, case .forbidden = error {
            return String(localized: "This account cannot edit announcements. Your text is retained.")
        }
        return String(localized: "Unable to save right now. Your text is retained; please try again.")
    }
}

private struct FeedPostCard: View {
    let postID: UUID
    let store: ClubFeedStore

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        if let post = store.post(id: postID), let author = store.user(id: post.ownerID) {
            WarmCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 11) {
                        NavigationLink(value: author) {
                            HStack(spacing: 11) {
                                MemberAvatar(user: author, size: 36)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(author.nickname)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.inkBrown)
                                    Text(post.timeLabel(interfaceLanguage: .english))
                                        .font(.caption)
                                        .foregroundStyle(Color.mutedBrown)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "View \(author.nickname)'s profile"))
                        .accessibilityIdentifier("post-author-link-\(post.id.uuidString)")

                        Spacer()

                        CommunitySafetyMenu(
                            canBlock: post.ownerID != store.currentUserID,
                            onReport: { try await store.report(kind: "post", id: post.id, reason: $0) },
                            onBlock: { try await store.block(post.ownerID) }
                        )

                        NavigationLink(value: post.id) {
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundStyle(Color.mutedBrown)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "View post details"))
                    }

                    NavigationLink(value: post.id) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !post.text.isEmpty {
                                Text(post.text)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.inkBrown)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !post.images.isEmpty || post.gif != nil {
                                FeedMediaGallery(images: post.images, gif: post.gif)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "View post details"))
                    .accessibilityIdentifier("post-content-link-\(post.id.uuidString)")

                    HStack(spacing: 16) {
                        let hasReacted = store.hasReacted(for: post.id)
                        Button {
                            store.toggleReaction(for: post.id)
                        } label: {
                            Label(
                                copy.feedReactionAction(isActive: hasReacted),
                                systemImage: hasReacted ? "hand.thumbsup.fill" : "hand.thumbsup"
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(AppReactionButtonStyle(isActive: hasReacted))
                        .disabled(store.isSubmitting)
                        .accessibilityIdentifier("feed-reaction-\(post.id.uuidString)")

                        Spacer()

                        NavigationLink(value: post.id) {
                            Label(
                                "\(store.commentCount(for: post.id))",
                                systemImage: "text.bubble"
                            )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.olive)
                        }
                        .accessibilityLabel(String(localized: "View comments"))
                        .buttonStyle(AppReactionButtonStyle())
                        .accessibilityIdentifier("comment-button-\(post.id.uuidString)")
                    }

                    Text(responseCountText(post.responseCount))
                        .font(.caption)
                        .foregroundStyle(Color.mutedBrown)
                        .accessibilityIdentifier("feed-reaction-count-\(post.id.uuidString)")
                }
            }
        }
    }

    private func responseCountText(_ count: Int) -> String {
        copy.feedReactionCount(count)
    }
}

// A shared, localized safety control; reports always use the existing repository.
struct FeedMoreButton: View {
    let load: () async throws -> Void
    @State private var loading = false
    @State private var failed = false
    var body: some View {
        Button {
            loading = true
            Task {
                defer { loading = false }
                do { try await load(); failed = false } catch { failed = true }
            }
        } label: {
            if loading { ProgressView() }
            else { Text(failed ? String(localized: "Couldn't load. Tap to retry") : String(localized: "Load more")) }
        }
        .disabled(loading)
        .frame(minHeight: 44)
    }
}

struct CommunitySafetyMenu: View {
    let canBlock: Bool
    let onReport: (String) async throws -> Void
    let onBlock: () async throws -> Void
    @State private var isWorking = false
    @State private var confirmsBlock = false
    @State private var result: String?
    private var copy: AppCopy { AppCopy() }

    var body: some View {
        Menu {
            Menu(String(localized: "Report content")) {
                ForEach(["abuse", "spam", "unsafe", "other"], id: \.self) { reason in
                    Button(reasonTitle(reason)) {
                        run { try await onReport(reason) }
                    }
                }
            }
            if canBlock {
                Button(String(localized: "Block user"), role: .destructive) {
                    confirmsBlock = true
                }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
        }
        .disabled(isWorking)
        .accessibilityLabel(String(localized: "Content safety options"))
        .confirmationDialog(String(localized: "Blocking hides each other's posts, comments, and game requests."), isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button(String(localized: "Block"), role: .destructive) { run { try await onBlock() } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(String(localized: "Result"), isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button(copy.dismissTitle, role: .cancel) { result = nil }
        } message: { Text(result ?? "") }
    }

    private func reasonTitle(_ reason: String) -> String {
        switch reason {
        case "abuse": return String(localized: "Harassment or hate")
        case "spam": return String(localized: "Spam or scam")
        case "unsafe": return String(localized: "Harmful or inappropriate")
        default: return String(localized: "Other concern")
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await action()
                result = String(localized: "Done. For help, open Safety & privacy in Me.")
            } catch {
                result = String(localized: "Could not complete. Check your connection and try again.")
            }
        }
    }
}

struct MemberAvatar: View {
    let user: CommunityUser
    let size: CGFloat

    var body: some View {
        CommunityAvatarImage(
            avatarData: user.profile.publicAvatarData,
            remoteURL: user.profile.publicAvatarURL,
            fallbackAsset: user.profile.publicAvatarFallback,
            size: size
        )
        .accessibilityHidden(true)
    }
}

struct CommunityAvatarImage: View {
    let avatarData: Data?
    let remoteURL: URL?
    let fallbackAsset: String
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(fallbackAsset)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .id(remoteURL)
            } else {
                Image(fallbackAsset)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(Color.appSeparator, lineWidth: 0.5) }
    }
}
