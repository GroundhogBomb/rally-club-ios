import Observation
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MAINTENANCE-POINT: CLUB-ANNOUNCEMENT-001
// The backend keeps all three body fields. The app displays and edits the English body.
struct ClubAnnouncement: Codable, Equatable, Identifiable {
    let id: Int
    let bodyZH: String
    let bodyEN: String
    let bodyJA: String
    let revision: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, revision
        case bodyZH = "body_zh_hant", bodyEN = "body_en", bodyJA = "body_ja", updatedAt = "updated_at"
    }
}

struct ClubAnnouncementDraft: Equatable {
    static let maximumLength = 8_000
    var bodyZH = ""
    var bodyEN = ""
    var bodyJA = ""
    var normalized: Self {
        Self(bodyZH: bodyZH.trimmingCharacters(in: .whitespacesAndNewlines),
             bodyEN: bodyEN.trimmingCharacters(in: .whitespacesAndNewlines),
             bodyJA: bodyJA.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var isValid: Bool {
        let bodies = [normalized.bodyZH, normalized.bodyEN, normalized.bodyJA]
        return bodies.allSatisfy { $0.unicodeScalars.count <= Self.maximumLength }
            && (bodies.allSatisfy(\.isEmpty) || bodies.allSatisfy { !$0.isEmpty })
    }
}

enum ClubAnnouncementError: Error {
    case forbidden, invalid, conflict
}

// MAINTENANCE-POINT: CLUB-FEED-001
// Store for club posts, comments, media, and reactions.
@MainActor
@Observable
final class ClubFeedStore {
    private let dataRepository: any AppDataRepository
    @ObservationIgnored private var repositoryChanges: Task<Void, Never>?

    // Track reads from the repository, which has its own storage.
    private var repository: any AppDataRepository {
        access(keyPath: \.repository)
        return dataRepository
    }

    let currentUserID: UUID
    var isSubmitting: Bool { repository.mutationState == .submitting }

    var announcement: ClubAnnouncement? { repository.clubAnnouncement }
    var canManageAnnouncement: Bool { repository.canManageClubAnnouncement }
    var announcementLoadState: RepositoryLoadState { repository.announcementLoadState }
    func refreshAnnouncement() async throws { try await repository.refreshClubAnnouncement() }
    func saveAnnouncement(_ text: String, expectedRevision: Int) async throws {
        let english = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft: ClubAnnouncementDraft
        if english.isEmpty {
            draft = ClubAnnouncementDraft()
        } else {
            // Keep existing versions and satisfy the backend's nonempty body fields for a new announcement.
            let previousZH = announcement?.bodyZH.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let previousJA = announcement?.bodyJA.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            draft = ClubAnnouncementDraft(bodyZH: previousZH.isEmpty ? english : previousZH,
                                          bodyEN: english,
                                          bodyJA: previousJA.isEmpty ? english : previousJA)
        }
        try await repository.saveClubAnnouncement(draft, expectedRevision: expectedRevision)
    }

    func report(kind: String, id: UUID, reason: String) async throws {
        try await repository.reportContent(kind: kind, id: id, reason: reason)
    }

    func block(_ userID: UUID) async throws {
        try await repository.setUserBlocked(userID, blocked: true)
    }

    init(repository: any AppDataRepository, userID: UUID) {
        dataRepository = repository
        currentUserID = userID
        let changes = repository.changes()
        repositoryChanges = Task { [weak self] in
            for await _ in changes {
                self?.withMutation(keyPath: \.repository) {}
            }
        }
    }

    deinit {
        repositoryChanges?.cancel()
    }

    var currentUser: CommunityUser {
        repository.user(id: currentUserID)
            ?? CommunityUser.placeholder(id: currentUserID, language: .english)
    }


    func user(id: UUID) -> CommunityUser? {
        repository.user(id: id)
    }

    func post(id: UUID) -> FeedPost? {
        repository.post(id: id, viewerID: currentUserID)
    }

    var visiblePosts: [FeedPost] {
        repository.posts(viewerID: currentUserID)
    }

    var currentUserPosts: [FeedPost] {
        repository.personalPosts(viewerID: currentUserID)
    }
    var postCount: Int { repository.profileCounts(viewerID: currentUserID)[0] }
    var hasMore: Bool { repository.hasMorePosts }
    func loadMore() async throws { try await repository.loadMorePosts() }
    func loadPersonalRecords() async throws { try await repository.loadPersonalRecords() }
    func loadComments(postID: UUID) async throws { try await repository.loadComments(postID: postID) }
    func commentCount(for postID: UUID) -> Int { repository.commentCount(postID: postID, viewerID: currentUserID) }

    func comments(for postID: UUID) -> [PostComment] {
        repository.comments(postID: postID, viewerID: currentUserID)
    }

    func hasReacted(for postID: UUID) -> Bool {
        repository.hasReactedForPost(postID: postID, userID: currentUserID)
    }

    func publish(text: String, images: [PostMedia], gif: PostMedia?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty || gif != nil else { return }

        let now = Date()
        repository.createPost(
            FeedPost(
                id: UUID(),
                ownerID: currentUserID,
                text: trimmed,
                images: images,
                gif: gif,
                languageCode: .english,
                createdAt: now,
                updatedAt: now,
                visibility: .publicContent,
                responseCount: 0
            ),
            requesterID: currentUserID
        )
    }

    func toggleReaction(for postID: UUID) {
        repository.togglePostReaction(postID: postID, userID: currentUserID)
    }

    func addComment(_ text: String, to postID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, post(id: postID) != nil else { return }
        let now = Date()
        repository.createComment(
            PostComment(
                id: UUID(),
                postID: postID,
                ownerID: currentUserID,
                text: trimmed,
                createdAt: now,
                updatedAt: now,
                visibility: .publicContent,
                languageCode: .english
            ),
            requesterID: currentUserID
        )
    }

    @discardableResult
    func updatePost(_ post: FeedPost) -> Bool {
        repository.updatePost(post, requesterID: currentUserID)
    }

    @discardableResult
    func deletePost(id: UUID) -> Bool {
        repository.deletePost(id: id, requesterID: currentUserID)
    }

    @discardableResult
    func updateComment(_ comment: PostComment) -> Bool {
        repository.updateComment(comment, requesterID: currentUserID)
    }

    @discardableResult
    func deleteComment(id: UUID) -> Bool {
        repository.deleteComment(id: id, requesterID: currentUserID)
    }
}

enum FeedSeedMedia {
    static func rallyGIF() -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.gif.identifier as CFString,
            3,
            nil
        ) else { return nil }

        let fileProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)

        let colors: [UIColor] = [
            UIColor(red: 0.74, green: 0.57, blue: 0.25, alpha: 1),
            UIColor(red: 0.42, green: 0.49, blue: 0.30, alpha: 1),
            UIColor(red: 0.84, green: 0.69, blue: 0.38, alpha: 1)
        ]

        for (index, color) in colors.enumerated() {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360))
            let image = renderer.image { context in
                UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))

                let pulse = CGFloat(76 + index * 10)
                color.withAlphaComponent(0.18).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 320 - pulse, y: 180 - pulse, width: pulse * 2, height: pulse * 2))

                let configuration = UIImage.SymbolConfiguration(pointSize: 88, weight: .medium)
                let symbol = UIImage(systemName: "tennisball.fill", withConfiguration: configuration)
                color.set()
                symbol?.withTintColor(color, renderingMode: .alwaysOriginal).draw(
                    in: CGRect(x: 276, y: 136, width: 88, height: 88)
                )
            }
            guard let cgImage = image.cgImage else { continue }
            let frameProperties = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.45]
            ] as CFDictionary
            CGImageDestinationAddImage(destination, cgImage, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
