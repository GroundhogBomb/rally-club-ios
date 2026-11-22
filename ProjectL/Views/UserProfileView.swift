import SwiftUI
import UIKit

struct UserProfileView: View {
    let user: CommunityUser
    let profileStore: ProfileStore
    @State private var viewedMatchMoment: MatchMoment?

    private var displayedNickname: String {
        profileStore.profile(for: user.id)?.nickname ?? user.nickname
    }
    private var displayedSignature: String {
        profileStore.profile(for: user.id)?.signature ?? user.signature
    }
    private var visibleMatchMoments: [MatchMoment] {
        profileStore.visibleMatchMoments(for: user.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                profileAvatar

                Text(displayedNickname)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.inkBrown)
                    .accessibilityIdentifier("profile-nickname")

                Text("“\(displayedSignature)”")
                    .font(.body)
                    .foregroundStyle(Color.mutedBrown)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("profile-signature")

                if !visibleMatchMoments.isEmpty {
                    publicMatchMomentsSection
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 48)
            .padding(.bottom, 28)
        }
        .background { CommunityBackdrop().overlay { Color.softCream.opacity(CommunityCanvasStyle.detailVeilOpacity) } }
        .navigationTitle(String(localized: "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .localizedBackButton()
        .task(id: user.id) { await profileStore.refreshProfiles(ownerID: user.id) }
        .fullScreenCover(item: $viewedMatchMoment) { photo in
            MatchMomentViewer(
                photos: visibleMatchMoments,
                initialPhotoID: photo.id
            )
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        let profile = profileStore.profile(for: user.id)
        CommunityAvatarImage(
            avatarData: profile?.publicAvatarData,
            remoteURL: profile?.publicAvatarURL,
            fallbackAsset: profile?.publicAvatarFallback ?? "RallyAvatar",
            size: 112
        )
        .accessibilityLabel(String(localized: "User avatar"))
        .accessibilityIdentifier("profile-avatar")
    }

    private var publicMatchMomentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(String(localized: "Match moments"))
            } icon: {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(Color.inkBrown)
            }
            .font(.headline)
            .foregroundStyle(Color.inkBrown)

            MatchMomentGrid(
                photos: visibleMatchMoments,
                accessibilityIdentifierPrefix: "public-match-moment-photo",
                onSelect: { viewedMatchMoment = $0 }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("public-match-moments-section")
    }
}
