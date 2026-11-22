import SwiftUI
import UIKit

struct CreateGameRequestView: View {
    let store: GameRequestStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var identity = GameRequestPublishIdentity.publicIdentity

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Request title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.inkBrown)
                        TextField(
                            String(localized: "Write a request title"),
                            text: $title
                        )
                        .padding(14)
                        .warmCanvas()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("game-request-title-field")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Game request"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.inkBrown)
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 150)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .warmCanvas()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                if bodyText.isEmpty {
                                    Text(String(localized: "Tell players where and when you want to play, plus the skill level or format."))
                                    .foregroundStyle(Color.mutedBrown.opacity(0.7))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                                }
                            }
                            .accessibilityIdentifier("game-request-body-field")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Posting identity"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.inkBrown)

                        Picker(String(localized: "Posting identity"), selection: $identity) {
                            ForEach(GameRequestPublishIdentity.allCases) { option in
                                Text(option.title(for: .english)).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .warmSegmentedCanvas()
                        .accessibilityIdentifier("game-request-identity-picker")

                        identityPreview
                    }

                    Text(String(localized: "An anonymous request hides your profile from other players. You can still manage it."))
                    .font(.caption)
                    .foregroundStyle(Color.mutedBrown)
                    .lineSpacing(3)
                }
                .padding(20)
            }
            .background { CommunityBackdrop() }
            .navigationTitle(String(localized: "New game request"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Publish")) {
                        store.publish(
                            title: title,
                            body: bodyText,
                            identity: identity
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canPublish || store.isSubmitting)
                    .accessibilityIdentifier("publish-game-request-button")
                }
            }
        }
    }

    private var identityPreview: some View {
        HStack(spacing: 11) {
            identityAvatar
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(identity == .anonymous
                     ? AnonymousGameRequestIdentity.playerA.nickname(for: .english)
                     : store.currentUser.nickname)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkBrown)
                Text(identity == .anonymous
                     ? String(localized: "Your player profile stays hidden")
                     : String(localized: "Shows avatar and nickname"))
                    .font(.caption)
                    .foregroundStyle(Color.mutedBrown)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.oliveSoft.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier(identity == .anonymous ? "anonymous-identity-preview" : "public-identity-preview")
    }

    @ViewBuilder
    private var identityAvatar: some View {
        if identity != .anonymous,
           let data = store.currentUser.profile.avatarData,
           let image = UIImage(data: data) {
            Image(uiImage: image).resizable()
        } else {
            Image(
                identity == .anonymous
                    ? "RallyAvatar"
                    : store.currentUser.avatar
            ).resizable()
        }
    }
}
