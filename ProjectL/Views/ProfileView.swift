import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    let profileStore: ProfileStore
    let clubFeedStore: ClubFeedStore
    let gameRequestStore: GameRequestStore
    @ObservedObject var session: AppSession
    @ObservedObject var sessionReminderStore: SessionReminderStore

    @Environment(\.openURL) private var openURL
    @State private var isShowingEditor = false
    @State private var isShowingAvatarEditor = false
    @State private var isManagingMatchMoments = false
    @State private var viewedMatchMoment: MatchMoment?
    @State private var selectedMatchMomentItems: [PhotosPickerItem] = []
    @State private var isShowingMailUnavailable = false

    private var copy: AppCopy { AppCopy() }
    private var matchMomentVisibilitySelection: Binding<Bool> {
        Binding(
            get: { profileStore.areMatchMomentsPublic },
            set: { profileStore.setMatchMomentsPublic($0, for: profileStore.currentUserID) }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    PageHeader(
                        eyebrow: copy.profileEyebrow,
                        title: copy.profileTab,
                        subtitle: String(localized: "Your club activity and match photos.")
                    )

                    profileSection
                    matchMomentSection
                    interactionSection
                    accountSection
                    if session.state != .demo { contactSection }

                    Text(copy.appVersionLabel)
                        .font(.caption)
                        .foregroundStyle(Color.olive.opacity(0.8))
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background { CommunityBackdrop() }
            .navigationBarHidden(true)
            .sheet(isPresented: $isShowingEditor) {
                EditMyProfileView(store: profileStore)
            }
            .sheet(isPresented: $isShowingAvatarEditor) {
                EditMyAvatarView(store: profileStore)
            }
            .sheet(isPresented: $isManagingMatchMoments) {
                ManageMatchMomentsView(store: profileStore)
            }
            .fullScreenCover(item: $viewedMatchMoment) { photo in
                MatchMomentViewer(
                    photos: profileStore.matchMoments,
                    initialPhotoID: photo.id
                )
            }
            .alert(
                String(localized: "Mail is unavailable"),
                isPresented: $isShowingMailUnavailable
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(localized: "Please set up a mail app on this device first."))
            }
        }
    }

    private var profileSection: some View {
        VStack(spacing: 12) {
            HStack {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                Spacer(minLength: 0)
                Button {
                    isShowingAvatarEditor = true
                } label: {
                    ProfileAvatarView(store: profileStore, size: 88)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "View or change avatar"))
                .accessibilityIdentifier("edit-avatar-button")

                Spacer(minLength: 0)
                Button {
                    isShowingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .frame(width: 44, height: 44)
                        .background(Color.oliveSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.olive)
                .accessibilityLabel(String(localized: "Edit profile"))
                .accessibilityIdentifier("edit-profile-button")
            }

                NavigationLink {
                    MyProfileDetailView(store: profileStore)
                } label: {
                    VStack(spacing: 5) {
                        Text(profileStore.nickname)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.inkBrown)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(profileStore.signature)
                            .font(.subheadline)
                            .foregroundStyle(Color.mutedBrown)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "View profile"))
                .accessibilityIdentifier("my-profile-link")

            HStack(spacing: 0) {
                profileMetric(clubFeedStore.postCount, title: String(localized: "Posts"))
                    .accessibilityIdentifier("profile-post-count")
                profileMetric(gameRequestStore.requestCount, title: String(localized: "Game requests"))
                profileMetric(gameRequestStore.responseCount, title: String(localized: "Joined"))
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    private func profileMetric(_ count: Int, title: String) -> some View {
        VStack(spacing: 4) {
            Text(count.formatted()).font(.headline).foregroundStyle(Color.inkBrown)
            Text(title).font(.caption).foregroundStyle(Color.mutedBrown)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var matchMomentSection: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label {
                        Text(String(localized: "Match moments"))
                    } icon: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(Color.inkBrown)
                    }
                        .font(.headline)
                        .foregroundStyle(Color.inkBrown)
                    Spacer()
                    Text("\(profileStore.matchMoments.count)/\(ProfileStore.maximumMatchMoments)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.mutedBrown)
                }

                Picker(
                    String(localized: "Match moment visibility"),
                    selection: matchMomentVisibilitySelection
                ) {
                    Text(String(localized: "Public")).tag(true)
                    Text(String(localized: "Hidden")).tag(false)
                }
                .pickerStyle(.segmented)
                .warmSegmentedCanvas()
                .accessibilityIdentifier("matchMoments-visibility-picker")

                if profileStore.matchMoments.isEmpty {
                    Text(String(localized: "Add photos from your matches and practice sessions."))
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedBrown)
                } else {
                    MatchMomentGrid(
                        photos: profileStore.matchMoments,
                        accessibilityIdentifierPrefix: "view-match-moment-photo",
                        onSelect: { viewedMatchMoment = $0 }
                    )
                }

                HStack(spacing: 10) {
                    PhotosPicker(
                        selection: $selectedMatchMomentItems,
                        maxSelectionCount: max(1, profileStore.remainingPhotoSlots),
                        matching: .images
                    ) {
                        Label(String(localized: "Add photos"), systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppActionButtonStyle(isPrimary: false))
                    .disabled(profileStore.remainingPhotoSlots == 0)
                    .accessibilityIdentifier("add-match-moment-photos-button")
                    .onChange(of: selectedMatchMomentItems) { _, items in
                        Task { await loadMatchMoments(from: items) }
                    }

                    Button {
                        isManagingMatchMoments = true
                    } label: {
                        Label(String(localized: "Arrange"), systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppActionButtonStyle(isPrimary: false))
                    .disabled(profileStore.matchMoments.isEmpty)
                    .accessibilityIdentifier("manage-match-moments-button")
                }
            }
        }
    }

    private var interactionSection: some View {
        WarmCard {
            VStack(spacing: 0) {
                ProfileNavigationRow(
                    title: String(localized: "My posts"),
                    subtitle: String(localized: "Posts you shared"),
                    systemImage: "text.bubble"
                ) {
                    MyPostRecordsView(store: clubFeedStore)
                }
                .accessibilityIdentifier("my-posts-link")

                Divider().overlay(Color.olive.opacity(0.12))

                ProfileNavigationRow(
                    title: String(localized: "My game requests"),
                    subtitle: String(localized: "Requests you posted"),
                    systemImage: "tennis.racket"
                ) {
                    MyGameRequestRecordsView(store: gameRequestStore, mode: .started)
                }
                .accessibilityIdentifier("my-game-requests-link")

                Divider().overlay(Color.olive.opacity(0.12))

                ProfileNavigationRow(
                    title: String(localized: "Joined games"),
                    subtitle: String(localized: "Game requests you joined"),
                    systemImage: "tennisball.fill"
                ) {
                    MyGameRequestRecordsView(store: gameRequestStore, mode: .responded)
                }
                .accessibilityIdentifier("my-responses-link")

                Divider().overlay(Color.olive.opacity(0.12))

                ProfileNavigationRow(
                    title: String(localized: "Session reminders"),
                    subtitle: String(localized: "Set a weekly session reminder"),
                    systemImage: "bell.badge"
                ) {
                    SessionReminderView(store: sessionReminderStore)
                }
                .accessibilityIdentifier("session-reminders-link")
            }
        }
    }

    private var accountSection: some View {
        WarmCard {
            VStack(spacing: 0) {
                ProfileNavigationRow(
                    title: String(localized: "Account settings"),
                    subtitle: String(localized: "Manage your account"),
                    systemImage: "gearshape"
                ) {
                    AccountActionsView(session: session)
                }
                .accessibilityIdentifier("account-settings-link")

                Divider().overlay(Color.olive.opacity(0.12))

                ProfileNavigationRow(
                    title: String(localized: "Safety & privacy"),
                    subtitle: String(localized: "Community rules, blocks, and privacy policy"),
                    systemImage: "hand.raised"
                ) {
                    SafetyPrivacyView(store: profileStore)
                }
            }
        }
    }

    private var contactSection: some View {
        EditorialSection {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    guard let url = DeveloperContact.mailURL(for: .english) else {
                        isShowingMailUnavailable = true
                        return
                    }
                    openURL(url) { accepted in
                        if !accepted { isShowingMailUnavailable = true }
                    }
                } label: {
                    HStack {
                        Label(String(localized: "Contact the developer"), systemImage: "envelope")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.olive)
                    }
                    .foregroundStyle(Color.olive)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("contact-developer-button")

                Text(String(localized: "If you have ideas, suggestions, or a community concern, please be sure to get in touch."))
                .font(.caption)
                .foregroundStyle(Color.mutedBrown)
                .lineSpacing(3)
            }
        }
    }

    private func loadMatchMoments(from items: [PhotosPickerItem]) async {
        var loadedData: [Data] = []
        for item in items.prefix(profileStore.remainingPhotoSlots) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loadedData.append(data)
            }
        }
        profileStore.addMatchMoments(for: profileStore.currentUserID, loadedData)
        selectedMatchMomentItems = []
    }
}

struct SafetyPrivacyView: View {
    let store: ProfileStore
    @State private var blockedIDs: [UUID] = []
    @State private var hasError = false
    private var copy: AppCopy { AppCopy() }

    var body: some View {
        Form {
            Section(String(localized: "Community rules")) {
                Text(String(localized: "Respect one another. Harassment, hate, threats, sexual, fraudulent, and illegal content are prohibited. Basic harmful-text filtering is applied; report images or other concerns from the content menu for administrator review. Removed content is hidden. Contact local emergency services for immediate danger."))
                Text(String(localized: "Reporting an anonymous game request does not reveal its author to other users."))
                SafetyContactButton()
            }
            .listRowBackground(WarmCanvas())
            Section(String(localized: "Blocked users")) {
                if blockedIDs.isEmpty {
                    Text(String(localized: "No blocked users."))
                }
                ForEach(blockedIDs, id: \.self) { id in
                    HStack {
                        Text(store.profile(for: id)?.nickname ?? String(localized: "User"))
                        Spacer()
                        Button(String(localized: "Unblock")) {
                            Task {
                                do { try await store.unblock(id); try await load() }
                                catch { hasError = true }
                            }
                        }
                    }
                }
            }
            .listRowBackground(WarmCanvas())
            PrivacyPolicyContent()
        }
        .navigationTitle(String(localized: "Safety & privacy"))
        .localizedBackButton()
        .scrollContentBackground(.hidden)
        .background { CommunityBackdrop() }
        .task { do { try await load() } catch { hasError = true } }
        .alert(String(localized: "Could not complete. Please retry."), isPresented: $hasError) {
            Button(copy.dismissTitle, role: .cancel) {}
            Button(String(localized: "Retry")) { Task { do { try await load() } catch { hasError = true } } }
        }
    }

    private func load() async throws { blockedIDs = try await store.blockedUsers() }
}

private struct SafetyContactButton: View {
    @Environment(\.isDemoMode) private var isDemoMode
    @Environment(\.openURL) private var openURL
    @State private var unavailable = false
    private var copy: AppCopy { AppCopy() }

    var body: some View {
        if !isDemoMode {
            contactButton
        }
    }

    private var contactButton: some View {
        Button(String(localized: "Contact administrator / appeal")) {
            guard let url = DeveloperContact.mailURL(for: .english) else { unavailable = true; return }
            openURL(url) { if !$0 { unavailable = true } }
        }
        .alert(String(localized: "Mail is unavailable"), isPresented: $unavailable) {
            Button(copy.dismissTitle, role: .cancel) {}
        } message: {
            Text(String(localized: "Set up a mail app on your device, then try this contact option again. Content reports remain available in the report menu."))
        }
    }
}

struct PrivacyPolicyContent: View {
    @Environment(\.isDemoMode) private var isDemoMode

    var body: some View {
    Section(String(localized: "Privacy policy")) {
        if isDemoMode {
            Text(String(localized: "Demo activity stays in memory until you leave the session. Weekly reminders are saved on this device. The demo uses fictional court locations and member profiles."))
        } else {
        Text(String(localized: "A configured club uses your email and account identifier for sign-in, and stores the profile and community activity you share. Your email stays out of public profiles."))
        Text(String(localized: "In a configured club, signed-in members can see public posts and match moments. Private match moments are visible to their owner. Media links expire. Reports are available to their submitter and authorized administrators."))
        Text(String(localized: "In a configured club, nearby court search uses Apple Maps after you grant location access. You choose which photos to share, and session reminders stay on your device."))
        Text(String(localized: "Account settings lets you request permanent deletion of your account, related content, and media. If processing fails, verify again and retry; deletion may be partially complete until it succeeds. Device backups and provider security records retained under their policies may not disappear immediately. For access, correction, privacy rights, or questions, contact the developer."))
            SafetyContactButton()
        }
    }
    .listRowBackground(WarmCanvas())
    }
}


private struct ProfileAvatarView: View {
    let store: ProfileStore
    let size: CGFloat


    var body: some View {
        CommunityAvatarImage(
            avatarData: store.displayIdentity == .publicIdentity ? store.avatarData : nil,
            remoteURL: store.displayIdentity == .publicIdentity ? store.avatarRemoteURL : nil,
            fallbackAsset: "RallyAvatar",
            size: size
        )
        .accessibilityLabel(String(localized: "Profile avatar"))
    }
}

struct MatchMomentView: View {
    let photo: MatchMoment

    var body: some View {
        // The grid sets the square size; image dimensions must not affect layout.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    DownsampledPhoto(data: photo.data, url: nil, cacheKey: photo.id.uuidString, maximumPixels: 450)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MatchMomentGrid: View {
    let photos: [MatchMoment]
    let accessibilityIdentifierPrefix: String
    let onSelect: (MatchMoment) -> Void



    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(photos) { photo in
                Button {
                    onSelect(photo)
                } label: {
                    MatchMomentView(photo: photo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Open photo"))
                .accessibilityIdentifier("\(accessibilityIdentifierPrefix)-\(photo.id.uuidString)")
            }
        }
    }
}

struct MatchMomentViewer: View {
    let photos: [MatchMoment]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoID: UUID

    init(photos: [MatchMoment], initialPhotoID: UUID) {
        self.photos = photos
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    private var positionText: String {
        guard let index = photos.firstIndex(where: { $0.id == selectedPhotoID }) else { return "" }
        return "\(index + 1) / \(photos.count)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedPhotoID) {
                ForEach(photos) { photo in
                    Group {
                        if let image = UIImage(data: photo.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(photo.id)
                    .accessibilityIdentifier("match-moment-photo-page-\(photo.id.uuidString)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        }
        .overlay(alignment: .top) {
            HStack {
                Text(positionText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(String(localized: "Close photo"))
                .accessibilityIdentifier("close-match-moment-viewer-button")
            }
            .padding(.horizontal, 18)
            .safeAreaPadding(.top, 8)
        }
    }
}

private struct ProfileNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let destination: Destination

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.olive)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.inkBrown)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.olive.opacity(0.65))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(subtitle)
    }
}

private struct EditMyAvatarView: View {
    let store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var avatarItem: PhotosPickerItem?
    @State private var isShowingInvalidAvatar = false

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Text(String(localized: "Current avatar"))
                    .font(.headline)
                    .foregroundStyle(Color.inkBrown)

                ProfileAvatarView(store: store, size: 180)

                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Label(String(localized: "Change avatar"), systemImage: "photo")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.softCream)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .background(Color.olive)
                        .clipShape(Capsule())
                }
                .accessibilityIdentifier("avatar-editor-change-button")
                .disabled(store.isUpdatingIdentity)

                if store.hasCustomAvatar {
                    Button(role: .destructive) {
                        store.removeAvatar(for: store.currentUserID)
                    } label: {
                        Label(
                            String(localized: "Remove avatar"),
                            systemImage: "trash"
                        )
                    }
                    .disabled(store.isUpdatingIdentity)
                    .accessibilityIdentifier("avatar-editor-remove-button")
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .background { CommunityBackdrop() }
            .navigationTitle(String(localized: "Edit avatar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(String(localized: "Done")) { dismiss() }
            }
            .onChange(of: avatarItem) { _, item in
                Task { await loadAvatar(from: item) }
            }
            .alert(
                String(localized: "Unable to use this image"),
                isPresented: $isShowingInvalidAvatar
            ) {
                Button(copy.dismissTitle, role: .cancel) {}
            } message: {
                Text(String(localized: "Choose a valid image. Avatars are converted to JPEG and must be 5 MB or smaller."))
            }
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let preparedData = ProfileStore.preparedAvatarJPEG(from: rawData),
              store.updateAvatar(for: store.currentUserID, with: preparedData)
        else {
            isShowingInvalidAvatar = true
            return
        }
        avatarItem = nil
    }
}

private struct EditMyProfileView: View {
    let store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var signature: String
    @State private var avatarItem: PhotosPickerItem?
    @State private var isShowingInvalidAvatar = false

    init(store: ProfileStore) {
        self.store = store
        _nickname = State(initialValue: store.nickname)
        _signature = State(initialValue: store.signature)
    }

    private var copy: AppCopy { AppCopy() }
    private var identitySelection: Binding<ProfileDisplayIdentity> {
        Binding(
            get: { store.displayIdentity },
            set: { store.setDisplayIdentity($0, for: store.currentUserID) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ProfileAvatarView(store: store, size: 92)
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                Text(String(localized: "Change avatar"))
                            }
                            .accessibilityIdentifier("change-avatar-button")
                        }
                        Spacer()
                    }
                }
                .listRowBackground(WarmCanvas())

                Section(String(localized: "Profile")) {
                    TextField(String(localized: "Display name"), text: $nickname)
                        .accessibilityIdentifier("profile-nickname-field")
                    TextField(String(localized: "Player bio"), text: $signature, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("profile-signature-field")
                    Text("\(nickname.count)/80 · \(signature.count)/240")
                        .font(.caption)
                        .foregroundStyle(Color.mutedBrown)
                }
                .listRowBackground(WarmCanvas())

                Section(String(localized: "Display identity")) {
                    Picker(String(localized: "Display identity"), selection: identitySelection) {
                        ForEach(ProfileDisplayIdentity.allCases) { identity in
                            Text(identity.title(for: .english)).tag(identity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("profile-identity-picker")
                    .warmSegmentedCanvas()

                    Text(String(localized: "Post with your profile or use the default avatar to stay anonymous."))
                    .font(.caption)
                    .foregroundStyle(Color.mutedBrown)
                }
                .listRowBackground(WarmCanvas())
            }
            .scrollContentBackground(.hidden)
            .background { CommunityBackdrop() }
            .navigationTitle(String(localized: "Edit profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        store.updateProfile(
                            for: store.currentUserID,
                            nickname: nickname,
                            signature: signature
                        )
                        dismiss()
                    }
                    .disabled(
                        nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        nickname.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 ||
                        signature.trimmingCharacters(in: .whitespacesAndNewlines).count > 240 ||
                        store.isUpdatingIdentity
                    )
                    .accessibilityIdentifier("save-profile-button")
                }
            }
            .onChange(of: avatarItem) { _, item in
                Task { await loadAvatar(from: item) }
            }
            .alert(
                String(localized: "Unable to use this image"),
                isPresented: $isShowingInvalidAvatar
            ) {
                Button(copy.dismissTitle, role: .cancel) {}
            } message: {
                Text(String(localized: "Choose a valid image. Avatars are converted to JPEG and must be 5 MB or smaller."))
            }
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let preparedData = ProfileStore.preparedAvatarJPEG(from: rawData),
              store.updateAvatar(for: store.currentUserID, with: preparedData)
        else {
            isShowingInvalidAvatar = true
            return
        }
        avatarItem = nil
    }
}

private struct MyPostRecordsView: View {
    let store: ClubFeedStore
    @State private var failed = false

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if store.currentUserPosts.isEmpty {
                    Text(String(localized: "You have not shared any posts yet."))
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedBrown)
                    .padding(.top, 48)
                } else {
                    ForEach(store.currentUserPosts) { post in
                        WarmCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(post.text.isEmpty
                                     ? String(localized: "Media post")
                                     : post.text)
                                    .font(.body)
                                    .foregroundStyle(Color.inkBrown)
                                    .lineLimit(4)
                                Text(post.timeLabel(interfaceLanguage: .english))
                                    .font(.caption)
                                    .foregroundStyle(Color.mutedBrown)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { CommunityBackdrop() }
        .navigationTitle(String(localized: "My posts"))
        .task { do { try await store.loadPersonalRecords() } catch { failed = true } }
        .alert(String(localized: "Couldn't load records"), isPresented: $failed) {
            Button(copy.dismissTitle, role: .cancel) {}
            Button(String(localized: "Retry")) {
                Task { do { try await store.loadPersonalRecords() } catch { failed = true } }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .localizedBackButton()
    }
}

private struct MyProfileDetailView: View {
    let store: ProfileStore
    @State private var isShowingEditor = false


    var body: some View {
        VStack(spacing: 18) {
            ProfileAvatarView(store: store, size: 112)
            Text(store.nickname)
                .font(.title.weight(.bold))
                .foregroundStyle(Color.inkBrown)
                .accessibilityIdentifier("my-profile-nickname")
            Text("“\(store.signature)”")
                .font(.body)
                .foregroundStyle(Color.mutedBrown)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("my-profile-signature")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .background { CommunityBackdrop() }
        .navigationTitle(String(localized: "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .localizedBackButton()
        .toolbar {
            Button(String(localized: "Edit")) { isShowingEditor = true }
        }
        .sheet(isPresented: $isShowingEditor) {
            EditMyProfileView(store: store)
        }
    }
}

private struct ManageMatchMomentsView: View {
    let store: ProfileStore
    @Environment(\.dismiss) private var dismiss


    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(store.matchMoments.enumerated()), id: \.element.id) { index, photo in
                    HStack(spacing: 12) {
                        MatchMomentView(photo: photo)
                            .frame(width: 58, height: 58)
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(Color.inkBrown)
                        Spacer()
                        Button { store.moveMatchMoment(for: store.currentUserID, id: photo.id, offset: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        .accessibilityLabel(String(localized: "Move earlier"))
                        Button { store.moveMatchMoment(for: store.currentUserID, id: photo.id, offset: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == store.matchMoments.count - 1)
                        .accessibilityLabel(String(localized: "Move later"))
                        Button(role: .destructive) { store.removeMatchMoment(for: store.currentUserID, id: photo.id) } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(String(localized: "Delete photo"))
                        .accessibilityIdentifier("delete-match-moment-photo-\(photo.id.uuidString)")
                    }
                    .listRowBackground(WarmCanvas())
                }
            }
            .scrollContentBackground(.hidden)
            .background { CommunityBackdrop() }
            .navigationTitle(String(localized: "Reorder match moments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(String(localized: "Done")) { dismiss() }
            }
        }
    }
}

private enum GameRequestRecordMode {
    case started
    case responded
}

private struct MyGameRequestRecordsView: View {
    let store: GameRequestStore
    let mode: GameRequestRecordMode
    @State private var failed = false

    private var copy: AppCopy { AppCopy() }
    private var gameRequests: [GameRequest] {
        switch mode {
        case .started: store.myRequests()
        case .responded: store.myResponses()
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if gameRequests.isEmpty {
                    ContentUnavailableView(
                        mode == .started
                            ? String(localized: "No game requests yet")
                            : String(localized: "No joined games yet"),
                        systemImage: "tennis.racket"
                    )
                    .padding(.top, 80)
                } else {
                    ForEach(gameRequests) { gameRequest in
                        WarmCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(gameRequest.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.inkBrown)
                                Text(gameRequest.body)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.mutedBrown)
                                    .lineLimit(4)
                                Text(gameRequest.timeLabel(interfaceLanguage: .english))
                                    .font(.caption)
                                    .foregroundStyle(Color.olive)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { CommunityBackdrop() }
        .task { do { try await store.loadPersonalRecords() } catch { failed = true } }
        .alert(String(localized: "Couldn't load records"), isPresented: $failed) {
            Button(copy.dismissTitle, role: .cancel) {}
            Button(String(localized: "Retry")) {
                Task { do { try await store.loadPersonalRecords() } catch { failed = true } }
            }
        }
        .navigationTitle(
            mode == .started
                ? String(localized: "My game requests")
                : String(localized: "Joined games")
        )
        .navigationBarTitleDisplayMode(.inline)
        .localizedBackButton()
    }
}
