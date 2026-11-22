import SwiftUI

struct FeedPostDetailView: View {
    let postID: UUID
    let store: ClubFeedStore

    @State private var commentText = ""
    @State private var commentsFailed = false

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        Group {
            if let post = store.post(id: postID), let author = store.user(id: post.ownerID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        authorHeader(author: author, post: post)

                        if !post.text.isEmpty {
                            Text(post.text)
                                .font(.body)
                                .foregroundStyle(Color.inkBrown)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !post.images.isEmpty || post.gif != nil {
                            FeedMediaGallery(images: post.images, gif: post.gif)
                        }

                        gameRequestSection(post: post)
                        commentsSection(post: post)
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    commentComposer(post: post)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "Post not found"),
                    systemImage: "text.bubble"
                )
            }
        }
        .background { CommunityBackdrop().overlay { Color.softCream.opacity(CommunityCanvasStyle.detailVeilOpacity) } }
        .navigationTitle(String(localized: "Post details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .localizedBackButton()
        .task(id: postID) {
            do { try await store.loadComments(postID: postID) } catch { commentsFailed = true }
        }
        .alert(String(localized: "Couldn't load comments"), isPresented: $commentsFailed) {
            Button(copy.dismissTitle, role: .cancel) {}
            Button(String(localized: "Retry")) {
                Task { do { try await store.loadComments(postID: postID) } catch { commentsFailed = true } }
            }
        }
    }

    private func authorHeader(author: CommunityUser, post: FeedPost) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: author) {
                HStack(spacing: 12) {
                    MemberAvatar(user: author, size: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(author.nickname)
                            .font(.headline)
                            .foregroundStyle(Color.inkBrown)
                        Text(post.timeLabel(interfaceLanguage: .english))
                            .font(.caption)
                            .foregroundStyle(Color.mutedBrown)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail-author-link")

            Spacer(minLength: 0)
            CommunitySafetyMenu(
                canBlock: post.ownerID != store.currentUserID,
                onReport: { try await store.report(kind: "post", id: post.id, reason: $0) },
                onBlock: { try await store.block(post.ownerID) }
            )
        }
    }

    private func gameRequestSection(post: FeedPost) -> some View {
        EditorialSection {
            VStack(alignment: .leading, spacing: 12) {
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
                .accessibilityIdentifier("detail-feed-reaction")

                Text(copy.feedReactionCount(post.responseCount))
                .font(.caption)
                .foregroundStyle(Color.mutedBrown)
                .accessibilityIdentifier("detail-game-request-count")
            }
        }
    }

    private func commentsSection(post: FeedPost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Comments"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.inkBrown)

            let postComments = store.comments(for: post.id)
            if postComments.isEmpty {
                Text(String(localized: "No comments yet. Start the conversation."))
                .font(.subheadline)
                .foregroundStyle(Color.mutedBrown)
            } else {
                ForEach(postComments) { comment in
                    if let user = store.user(id: comment.ownerID) {
                        HStack(alignment: .top) {
                            CommentRow(comment: comment, user: user)
                            CommunitySafetyMenu(
                                canBlock: comment.ownerID != store.currentUserID,
                                onReport: { try await store.report(kind: "comment", id: comment.id, reason: $0) },
                                onBlock: { try await store.block(comment.ownerID) }
                            )
                        }
                    }
                }
            }

        }
    }

    private func commentComposer(post: FeedPost) -> some View {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    String(localized: "Write a comment…"),
                    text: $commentText,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(13)
                .warmCanvas()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("comment-field")

                Button {
                    store.addComment(commentText, to: post.id)
                    commentText = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(AppIconButtonStyle())
                .disabled(
                    commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || store.isSubmitting
                )
                .accessibilityLabel(String(localized: "Send comment"))
                .accessibilityIdentifier("send-comment-button")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .warmCanvas()
            .overlay(alignment: .top) { Divider() }
    }
}

private struct CommentRow: View {
    let comment: PostComment
    let user: CommunityUser

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: user) {
                MemberAvatar(user: user, size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("comment-author-avatar-\(comment.id.uuidString)")

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink(value: user) {
                        Text(user.nickname)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.inkBrown)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("comment-author-name-\(comment.id.uuidString)")
                    Text(FeedTimestamp.label(for: comment.createdAt, language: .english))
                        .font(.caption2)
                        .foregroundStyle(Color.mutedBrown)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}
