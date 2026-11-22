import Combine
import Foundation

enum RepositoryLoadState: Equatable {
    case loading
    case content
    case empty
    case failure(RepositoryFailure)
}

enum RepositoryMutationState: Equatable {
    case idle
    case submitting
    case succeeded
    case failure(RepositoryFailure)
}

enum RepositoryMutationContext: Equatable {
    case general
    case mediaUpload
    case profileUpdate
    case avatarUpload
    case avatarRemove
}

struct RepositoryFailure: Equatable {
    enum Kind: Equatable {
        case network
        case permission
        case unavailable
    }

    let kind: Kind
    let debugDescription: String

    init(error: Error) {
        let nsError = error as NSError
        let searchableText = [
            nsError.domain,
            nsError.localizedDescription,
            String(describing: error)
        ]
        .joined(separator: " ")
        .lowercased()

        if nsError.domain == NSURLErrorDomain {
            kind = .network
        } else if searchableText.contains("401")
                    || searchableText.contains("403")
                    || searchableText.contains("42501")
                    || searchableText.contains("permission")
                    || searchableText.contains("not authorized")
                    || searchableText.contains("row-level security") {
            kind = .permission
        } else {
            kind = .unavailable
        }
        debugDescription = nsError.localizedDescription
    }
}

struct OwnershipPolicy {
    static func canMutate(ownerID: UUID, requesterID: UUID) -> Bool {
        ownerID == requesterID
    }

    static func canRead(
        visibility: ContentVisibility,
        ownerID: UUID,
        viewerID: UUID
    ) -> Bool {
        visibility == .publicContent || ownerID == viewerID
    }
}

// MAINTENANCE-POINT: BACKEND-001
// Shared data and ownership contract for the community stores.
@MainActor
protocol AppDataRepository: AnyObject {
    func changes() -> AsyncStream<Void>
    var loadState: RepositoryLoadState { get }
    var mutationState: RepositoryMutationState { get }
    var mutationContext: RepositoryMutationContext { get }
    var canRetryLastMutation: Bool { get }
    func synchronize() async throws
    // CLUB-ANNOUNCEMENT-001: permissions and announcement data share the existing repository.
    var clubAnnouncement: ClubAnnouncement? { get }
    var canManageClubAnnouncement: Bool { get }
    var announcementLoadState: RepositoryLoadState { get }
    func refreshClubAnnouncement() async throws
    func saveClubAnnouncement(_ draft: ClubAnnouncementDraft, expectedRevision: Int) async throws
    func refreshProfiles() async throws
    func refreshMatchMoments(ownerID: UUID) async throws
    func reportContent(kind: String, id: UUID, reason: String) async throws
    func setUserBlocked(_ id: UUID, blocked: Bool) async throws
    func blockedUsers() async throws -> [UUID]
    var hasMorePosts: Bool { get }
    var hasMoreGameRequests: Bool { get }
    func loadMorePosts() async throws
    func loadMoreGameRequests() async throws
    func loadComments(postID: UUID) async throws
    func loadPersonalRecords() async throws
    func personalPosts(viewerID: UUID) -> [FeedPost]
    func personalGameRequests(viewerID: UUID) -> [GameRequest]
    func profileCounts(viewerID: UUID) -> [Int]
    func commentCount(postID: UUID, viewerID: UUID) -> Int
    func clearMutationState()
    func retryLastMutation()

    func user(id: UUID) -> CommunityUser?
    func profile(userID: UUID, viewerID: UUID) -> CommunityProfile?
    func canModify(ownerID: UUID, requesterID: UUID) -> Bool
    @discardableResult func createProfile(_ profile: CommunityProfile, requesterID: UUID) -> Bool
    @discardableResult func deleteProfile(userID: UUID, requesterID: UUID) -> Bool

    func posts(viewerID: UUID) -> [FeedPost]
    func post(id: UUID, viewerID: UUID) -> FeedPost?
    @discardableResult func createPost(_ post: FeedPost, requesterID: UUID) -> Bool
    @discardableResult func updatePost(_ post: FeedPost, requesterID: UUID) -> Bool
    @discardableResult func deletePost(id: UUID, requesterID: UUID) -> Bool

    func comments(postID: UUID, viewerID: UUID) -> [PostComment]
    @discardableResult func createComment(_ comment: PostComment, requesterID: UUID) -> Bool
    @discardableResult func updateComment(_ comment: PostComment, requesterID: UUID) -> Bool
    @discardableResult func deleteComment(id: UUID, requesterID: UUID) -> Bool

    func gameRequests(viewerID: UUID) -> [GameRequest]
    func gameRequest(id: UUID, viewerID: UUID) -> GameRequest?
    @discardableResult func createGameRequest(_ gameRequest: GameRequest, requesterID: UUID) -> Bool
    @discardableResult func updateGameRequest(_ gameRequest: GameRequest, requesterID: UUID) -> Bool
    @discardableResult func deleteGameRequest(id: UUID, requesterID: UUID) -> Bool

    func hasReactedForPost(postID: UUID, userID: UUID) -> Bool
    func togglePostReaction(postID: UUID, userID: UUID)
    func hasRespondedToGameRequest(gameRequestID: UUID, userID: UUID) -> Bool
    func respondToGameRequest(gameRequestID: UUID, userID: UUID)

    @discardableResult
    func updateProfile(
        userID: UUID,
        requesterID: UUID,
        nickname: String?,
        signature: String?,
        avatarData: Data?,
        matchMomentsPublic: Bool?,
        displayIdentity: ProfileDisplayIdentity?
    ) -> Bool
    @discardableResult
    func updateAvatar(userID: UUID, requesterID: UUID, data: Data) -> Bool
    @discardableResult
    func removeAvatar(userID: UUID, requesterID: UUID) -> Bool

    func matchMoments(ownerID: UUID, viewerID: UUID) -> [MatchMoment]
    @discardableResult func createMatchMoment(_ photo: MatchMoment, requesterID: UUID) -> Bool
    @discardableResult func updateMatchMoment(_ photo: MatchMoment, requesterID: UUID) -> Bool
    @discardableResult func deleteMatchMoment(id: UUID, requesterID: UUID) -> Bool
    @discardableResult func moveMatchMoment(ownerID: UUID, id: UUID, offset: Int, requesterID: UUID) -> Bool
}

extension AppDataRepository {
    var hasMorePosts: Bool { false }
    var hasMoreGameRequests: Bool { false }
    func loadMorePosts() async throws {}
    func loadMoreGameRequests() async throws {}
    func loadComments(postID: UUID) async throws {}
    func loadPersonalRecords() async throws {}
    func personalPosts(viewerID: UUID) -> [FeedPost] { posts(viewerID: viewerID).filter { $0.ownerID == viewerID } }
    func personalGameRequests(viewerID: UUID) -> [GameRequest] { gameRequests(viewerID: viewerID) }
    func profileCounts(viewerID: UUID) -> [Int] {
        [personalPosts(viewerID: viewerID).count,
         gameRequests(viewerID: viewerID).filter { $0.ownerID == viewerID }.count,
         gameRequests(viewerID: viewerID).filter { hasRespondedToGameRequest(gameRequestID: $0.id, userID: viewerID) }.count]
    }
    func commentCount(postID: UUID, viewerID: UUID) -> Int { comments(postID: postID, viewerID: viewerID).count }
}

// Each caller gets its own stream. A pending signal covers every change up to the next read.
@MainActor
final class RepositoryChangeBroadcaster {
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

#if DEBUG
    var subscriberCount: Int { continuations.count }
#endif

    func subscribe() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.continuations.removeValue(forKey: id)
            }
        }
        continuations[id] = continuation
        return stream
    }

    func send() {
        for continuation in continuations.values {
            continuation.yield()
        }
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
    }
}

// MAINTENANCE-POINT: DEMO-DATA-001
// The demo uses the same ownership rules and stores as the configured club.
@MainActor
final class InMemoryAppDataRepository: ObservableObject, AppDataRepository {
    private struct UserContentKey: Hashable {
        let userID: UUID
        let contentID: UUID
    }

    private let changeBroadcaster = RepositoryChangeBroadcaster()
    private var usersByID: [UUID: UserAccount]
    private var profilesByUserID: [UUID: CommunityProfile]
    private var storedPosts: [FeedPost]
    private var storedComments: [PostComment]
    private var storedGameRequests: [GameRequest]
    private var storedMatchMoments: [MatchMoment]
    private var postReactions: Set<UserContentKey> = []
    private var gameRequestResponses: Set<UserContentKey> = []
    private var blockedUserIDs: Set<UUID> = []
    private var reports: [(kind: String, id: UUID, reason: String)] = []
#if DEBUG
    // Hooks for deterministic Store identity checks across an await.
    var onRefreshProfiles: (@MainActor () async -> Void)?
    private(set) var refreshedMatchMomentOwnerIDs: [UUID] = []
#endif
    private let announcementPublisherIDs: Set<UUID>
    private(set) var clubAnnouncement: ClubAnnouncement?
    var canManageClubAnnouncement: Bool { announcementPublisherIDs.contains(CommunityDirectory.demoMember.id) }
    var announcementLoadState: RepositoryLoadState { clubAnnouncement == nil ? .empty : .content }

    func changes() -> AsyncStream<Void> {
        changeBroadcaster.subscribe()
    }
    var loadState: RepositoryLoadState { .content }
    var mutationState: RepositoryMutationState { .idle }
    var mutationContext: RepositoryMutationContext { .general }
    var canRetryLastMutation: Bool { false }

    init(now: Date = Date(), announcementPublisherIDs: Set<UUID> = [], announcement: ClubAnnouncement? = nil) {
        self.announcementPublisherIDs = announcementPublisherIDs
        clubAnnouncement = announcement
        let currentUser = CommunityDirectory.demoMember
        let riley = CommunityDirectory.riley
        let aki = CommunityDirectory.aki
        let seedUsers = [currentUser, riley, aki]
        usersByID = Dictionary(uniqueKeysWithValues: seedUsers.map { ($0.id, $0.account) })
        profilesByUserID = Dictionary(uniqueKeysWithValues: seedUsers.map { ($0.id, $0.profile) })

        let servingPostID = UUID(uuid: (0x26, 0xf8, 0x6c, 0xe8, 0x08, 0x53, 0x5e, 0x49, 0x92, 0x6b, 0xfd, 0x74, 0x95, 0x99, 0x6b, 0x41))
        let tiebreakPostID = UUID(uuid: (0x3d, 0xe5, 0xf0, 0x0c, 0x68, 0xca, 0x59, 0xf9, 0xac, 0x4b, 0xec, 0xde, 0xe8, 0xbc, 0x15, 0xaf))
        let backhandPostID = UUID(uuid: (0xac, 0x50, 0x94, 0x90, 0x8a, 0x33, 0x53, 0xb8, 0xa8, 0xc2, 0xd6, 0x9d, 0xe3, 0xb0, 0x7f, 0x88))

        storedPosts = [
            FeedPost(
                id: servingPostID,
                ownerID: currentUser.id,
                text: "I landed five serves in a row at Northbank this weekend. Anyone up for a serving session next time?",
                images: [PostMedia(assetName: "RallyAvatar")],
                gif: nil,
                languageCode: .english,
                createdAt: now.addingTimeInterval(-1_500),
                updatedAt: now.addingTimeInterval(-1_500),
                visibility: .publicContent,
                responseCount: 12
            ),
            FeedPost(
                id: tiebreakPostID,
                ownerID: riley.id,
                text: "We played our first tiebreak under the lights at Cedar Lane. My best point was a backhand down the line.",
                images: [],
                gif: FeedSeedMedia.rallyGIF().map { PostMedia(data: $0) },
                languageCode: .english,
                createdAt: now.addingTimeInterval(-7_200),
                updatedAt: now.addingTimeInterval(-7_200),
                visibility: .publicContent,
                responseCount: 8
            ),
            FeedPost(
                id: backhandPostID,
                ownerID: aki.id,
                text: "Worked on my backhand today and kept a long crosscourt rally going.",
                images: [],
                gif: nil,
                languageCode: .english,
                createdAt: now.addingTimeInterval(-18_000),
                updatedAt: now.addingTimeInterval(-18_000),
                visibility: .publicContent,
                responseCount: 17
            )
        ]

        storedComments = [
            PostComment(
                id: UUID(uuid: (0x52, 0xee, 0xca, 0xcd, 0x59, 0xad, 0x5e, 0x42, 0xb2, 0xe8, 0x0f, 0xa2, 0xbd, 0x48, 0xc6, 0xd2)),
                postID: servingPostID,
                ownerID: aki.id,
                text: "I'll bring the balls next time. See you this weekend!",
                createdAt: now.addingTimeInterval(-900),
                updatedAt: now.addingTimeInterval(-900),
                visibility: .publicContent,
                languageCode: .english
            ),
            PostComment(
                id: UUID(uuid: (0x62, 0x69, 0x2b, 0xb2, 0x5e, 0xe5, 0x5b, 0x76, 0x92, 0x98, 0xb7, 0x74, 0xc6, 0x8b, 0xc9, 0xb9)),
                postID: tiebreakPostID,
                ownerID: currentUser.id,
                text: "That backhand was a great shot. See you at the next session!",
                createdAt: now.addingTimeInterval(-4_800),
                updatedAt: now.addingTimeInterval(-4_800),
                visibility: .publicContent,
                languageCode: .english
            )
        ]
        storedGameRequests = SampleData.gameRequests(now: now)
        storedMatchMoments = []
    }

    func synchronize() async throws {}
    func refreshClubAnnouncement() async throws {}
    func saveClubAnnouncement(_ draft: ClubAnnouncementDraft, expectedRevision: Int) async throws {
        guard canManageClubAnnouncement else { throw ClubAnnouncementError.forbidden }
        guard draft.isValid else { throw ClubAnnouncementError.invalid }
        guard (clubAnnouncement?.revision ?? 0) == expectedRevision else { throw ClubAnnouncementError.conflict }
        let normalized = draft.normalized
        clubAnnouncement = ClubAnnouncement(id: 1, bodyZH: normalized.bodyZH,
            bodyEN: normalized.bodyEN, bodyJA: normalized.bodyJA, revision: expectedRevision + 1,
            updatedAt: ISO8601DateFormatter().string(from: Date()))
        notifyChange()
    }
    func refreshProfiles() async throws {
#if DEBUG
        await onRefreshProfiles?()
#endif
    }
    func refreshMatchMoments(ownerID: UUID) async throws {
#if DEBUG
        refreshedMatchMomentOwnerIDs.append(ownerID)
#endif
    }
    func reportContent(kind: String, id: UUID, reason: String) async throws {
        let viewerID = CommunityDirectory.demoMember.id
        let visible: Bool
        switch kind {
        case "post": visible = post(id: id, viewerID: viewerID) != nil
        case "comment":
            visible = storedComments.contains { comment in
                comment.id == id && comments(postID: comment.postID, viewerID: viewerID).contains { $0.id == id }
            }
        case "game_request": visible = gameRequest(id: id, viewerID: viewerID) != nil
        default: visible = false
        }
        guard visible, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.badURL)
        }
        reports.append((kind, id, reason))
    }

    func setUserBlocked(_ id: UUID, blocked: Bool) async throws {
        guard id != CommunityDirectory.demoMember.id, usersByID[id] != nil else {
            throw URLError(.resourceUnavailable)
        }
        if blocked { blockedUserIDs.insert(id) }
        else { blockedUserIDs.remove(id) }
        notifyChange()
    }

    func blockedUsers() async throws -> [UUID] {
        blockedUserIDs.sorted { $0.uuidString < $1.uuidString }
    }

    func clearMutationState() {}
    func retryLastMutation() {}

    func user(id: UUID) -> CommunityUser? {
        guard let account = usersByID[id],
              let profile = profilesByUserID[id] else { return nil }
        return CommunityUser(account: account, profile: profile)
    }

    func profile(userID: UUID, viewerID: UUID) -> CommunityProfile? {
        guard let profile = profilesByUserID[userID],
              OwnershipPolicy.canRead(
                visibility: profile.visibility,
                ownerID: profile.userID,
                viewerID: viewerID
              ) else { return nil }
        return profile
    }

    func canModify(ownerID: UUID, requesterID: UUID) -> Bool {
        OwnershipPolicy.canMutate(ownerID: ownerID, requesterID: requesterID)
    }

    func createProfile(_ profile: CommunityProfile, requesterID: UUID) -> Bool {
        guard profile.userID == requesterID,
              usersByID[profile.userID] != nil,
              profilesByUserID[profile.userID] == nil else { return false }
        profilesByUserID[profile.userID] = profile
        notifyChange()
        return true
    }

    func deleteProfile(userID: UUID, requesterID: UUID) -> Bool {
        guard canModify(ownerID: userID, requesterID: requesterID),
              profilesByUserID.removeValue(forKey: userID) != nil else { return false }
        storedMatchMoments.removeAll { $0.ownerID == userID }
        notifyChange()
        return true
    }

    func posts(viewerID: UUID) -> [FeedPost] {
        storedPosts.filter {
            !blockedUserIDs.contains($0.ownerID) && OwnershipPolicy.canRead(
                visibility: $0.visibility,
                ownerID: $0.ownerID,
                viewerID: viewerID
            )
        }
    }

    func post(id: UUID, viewerID: UUID) -> FeedPost? {
        posts(viewerID: viewerID).first { $0.id == id }
    }

    func createPost(_ post: FeedPost, requesterID: UUID) -> Bool {
        guard post.ownerID == requesterID,
              usersByID[requesterID] != nil,
              !storedPosts.contains(where: { $0.id == post.id }) else { return false }
        storedPosts.insert(post, at: 0)
        notifyChange()
        return true
    }

    func updatePost(_ post: FeedPost, requesterID: UUID) -> Bool {
        guard let index = storedPosts.firstIndex(where: { $0.id == post.id }),
              storedPosts[index].ownerID == post.ownerID,
              canModify(ownerID: storedPosts[index].ownerID, requesterID: requesterID) else { return false }
        storedPosts[index] = post
        notifyChange()
        return true
    }

    func deletePost(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedPosts.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedPosts[index].ownerID, requesterID: requesterID) else { return false }
        storedPosts.remove(at: index)
        storedComments.removeAll { $0.postID == id }
        postReactions = postReactions.filter { $0.contentID != id }
        notifyChange()
        return true
    }

    func comments(postID: UUID, viewerID: UUID) -> [PostComment] {
        guard post(id: postID, viewerID: viewerID) != nil else { return [] }
        return storedComments
            .filter {
                $0.postID == postID && !blockedUserIDs.contains($0.ownerID) &&
                OwnershipPolicy.canRead(
                    visibility: $0.visibility,
                    ownerID: $0.ownerID,
                    viewerID: viewerID
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func createComment(_ comment: PostComment, requesterID: UUID) -> Bool {
        guard comment.ownerID == requesterID,
              post(id: comment.postID, viewerID: requesterID) != nil,
              !storedComments.contains(where: { $0.id == comment.id }) else { return false }
        storedComments.append(comment)
        notifyChange()
        return true
    }

    func updateComment(_ comment: PostComment, requesterID: UUID) -> Bool {
        guard let index = storedComments.firstIndex(where: { $0.id == comment.id }),
              storedComments[index].ownerID == comment.ownerID,
              storedComments[index].postID == comment.postID,
              canModify(ownerID: storedComments[index].ownerID, requesterID: requesterID) else { return false }
        storedComments[index] = comment
        notifyChange()
        return true
    }

    func deleteComment(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedComments.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedComments[index].ownerID, requesterID: requesterID) else { return false }
        storedComments.remove(at: index)
        notifyChange()
        return true
    }

    func gameRequests(viewerID: UUID) -> [GameRequest] {
        storedGameRequests.filter {
            !blockedUserIDs.contains($0.ownerID) && OwnershipPolicy.canRead(
                visibility: $0.visibility,
                ownerID: $0.ownerID,
                viewerID: viewerID
            )
        }
    }

    func gameRequest(id: UUID, viewerID: UUID) -> GameRequest? {
        gameRequests(viewerID: viewerID).first { $0.id == id }
    }

    func createGameRequest(_ gameRequest: GameRequest, requesterID: UUID) -> Bool {
        guard gameRequest.ownerID == requesterID,
              usersByID[requesterID] != nil,
              !storedGameRequests.contains(where: { $0.id == gameRequest.id }) else { return false }
        storedGameRequests.insert(gameRequest, at: 0)
        notifyChange()
        return true
    }

    func updateGameRequest(_ gameRequest: GameRequest, requesterID: UUID) -> Bool {
        guard let index = storedGameRequests.firstIndex(where: { $0.id == gameRequest.id }),
              storedGameRequests[index].ownerID == gameRequest.ownerID,
              canModify(ownerID: storedGameRequests[index].ownerID, requesterID: requesterID) else { return false }
        storedGameRequests[index] = gameRequest
        notifyChange()
        return true
    }

    func deleteGameRequest(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedGameRequests.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedGameRequests[index].ownerID, requesterID: requesterID) else { return false }
        storedGameRequests.remove(at: index)
        gameRequestResponses = gameRequestResponses.filter { $0.contentID != id }
        notifyChange()
        return true
    }

    func hasReactedForPost(postID: UUID, userID: UUID) -> Bool {
        postReactions.contains(UserContentKey(userID: userID, contentID: postID))
    }

    func togglePostReaction(postID: UUID, userID: UUID) {
        guard let index = storedPosts.firstIndex(where: { $0.id == postID }),
              post(id: postID, viewerID: userID) != nil else { return }
        let key = UserContentKey(userID: userID, contentID: postID)
        if postReactions.remove(key) != nil {
            storedPosts[index].responseCount = max(0, storedPosts[index].responseCount - 1)
        } else {
            postReactions.insert(key)
            storedPosts[index].responseCount += 1
        }
        storedPosts[index].updatedAt = Date()
        notifyChange()
    }

    func hasRespondedToGameRequest(gameRequestID: UUID, userID: UUID) -> Bool {
        gameRequestResponses.contains(UserContentKey(userID: userID, contentID: gameRequestID))
    }

    func respondToGameRequest(gameRequestID: UUID, userID: UUID) {
        guard let index = storedGameRequests.firstIndex(where: { $0.id == gameRequestID }),
              gameRequest(id: gameRequestID, viewerID: userID) != nil else { return }
        let key = UserContentKey(userID: userID, contentID: gameRequestID)
        guard gameRequestResponses.insert(key).inserted else { return }
        storedGameRequests[index].responseCount += 1
        storedGameRequests[index].updatedAt = Date()
        notifyChange()
    }

    func updateProfile(
        userID: UUID,
        requesterID: UUID,
        nickname: String?,
        signature: String?,
        avatarData: Data?,
        matchMomentsPublic: Bool?,
        displayIdentity: ProfileDisplayIdentity?
    ) -> Bool {
        guard canModify(ownerID: userID, requesterID: requesterID),
              var profile = profilesByUserID[userID],
              var account = usersByID[userID] else { return false }
        if let nickname { profile.nickname = nickname }
        if let signature { profile.signature = signature }
        if let avatarData { profile.avatarData = avatarData }
        if let matchMomentsPublic { profile.areMatchMomentsPublic = matchMomentsPublic }
        if let displayIdentity { profile.displayIdentity = displayIdentity }
        let now = Date()
        profile.updatedAt = now
        account.updatedAt = now
        profilesByUserID[userID] = profile
        usersByID[userID] = account
        notifyChange()
        return true
    }

    func updateAvatar(userID: UUID, requesterID: UUID, data: Data) -> Bool {
        guard data.count <= ProfileAvatarStorage.maximumFileSize else { return false }
        return updateProfile(
            userID: userID,
            requesterID: requesterID,
            nickname: nil,
            signature: nil,
            avatarData: data,
            matchMomentsPublic: nil,
            displayIdentity: nil
        )
    }

    func removeAvatar(userID: UUID, requesterID: UUID) -> Bool {
        guard canModify(ownerID: userID, requesterID: requesterID),
              var profile = profilesByUserID[userID] else { return false }
        profile.avatarData = nil
        profile.avatarRemoteURL = nil
        profile.avatarStoragePath = nil
        profile.updatedAt = Date()
        profilesByUserID[userID] = profile
        notifyChange()
        return true
    }

    func matchMoments(ownerID: UUID, viewerID: UUID) -> [MatchMoment] {
        guard let profile = profile(userID: ownerID, viewerID: viewerID) else { return [] }
        let isOwner = ownerID == viewerID
        guard isOwner || profile.areMatchMomentsPublic else { return [] }
        return storedMatchMoments.filter {
            $0.ownerID == ownerID &&
            OwnershipPolicy.canRead(
                visibility: $0.visibility,
                ownerID: $0.ownerID,
                viewerID: viewerID
            )
        }
    }

    func createMatchMoment(_ photo: MatchMoment, requesterID: UUID) -> Bool {
        guard photo.ownerID == requesterID,
              usersByID[requesterID] != nil,
              !storedMatchMoments.contains(where: { $0.id == photo.id }) else { return false }
        storedMatchMoments.append(photo)
        notifyChange()
        return true
    }

    func updateMatchMoment(_ photo: MatchMoment, requesterID: UUID) -> Bool {
        guard let index = storedMatchMoments.firstIndex(where: { $0.id == photo.id }),
              storedMatchMoments[index].ownerID == photo.ownerID,
              canModify(ownerID: storedMatchMoments[index].ownerID, requesterID: requesterID) else { return false }
        storedMatchMoments[index] = photo
        notifyChange()
        return true
    }

    func deleteMatchMoment(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedMatchMoments.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedMatchMoments[index].ownerID, requesterID: requesterID) else { return false }
        storedMatchMoments.remove(at: index)
        notifyChange()
        return true
    }

    func moveMatchMoment(ownerID: UUID, id: UUID, offset: Int, requesterID: UUID) -> Bool {
        guard canModify(ownerID: ownerID, requesterID: requesterID) else { return false }
        let ownerIndices = storedMatchMoments.indices.filter { storedMatchMoments[$0].ownerID == ownerID }
        guard let ownerPosition = ownerIndices.firstIndex(where: { storedMatchMoments[$0].id == id }) else { return false }
        let destinationPosition = ownerPosition + offset
        guard ownerIndices.indices.contains(destinationPosition) else { return false }
        storedMatchMoments.swapAt(ownerIndices[ownerPosition], ownerIndices[destinationPosition])
        notifyChange()
        return true
    }

    private func notifyChange() {
        objectWillChange.send()
        changeBroadcaster.send()
    }
}

#if DEBUG
@MainActor
enum RepositoryContractChecks {
    static func run() {
        let repository = InMemoryAppDataRepository(
            now: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let ownerID = CommunityDirectory.demoMember.id
        let visitorID = CommunityDirectory.riley.id

        assert(repository.user(id: ownerID)?.profile.userID == ownerID)
        assert(repository.profile(userID: ownerID, viewerID: visitorID) != nil)

        let now = Date(timeIntervalSince1970: 1_750_000_100)
        let privatePost = FeedPost(
            id: UUID(uuid: (0x2c, 0x33, 0x2b, 0x8b, 0x48, 0x62, 0x57, 0x40, 0x88, 0x6b, 0x83, 0x5e, 0x15, 0xf0, 0x5c, 0x4e)),
            ownerID: ownerID,
            text: "repository-contract-check",
            images: [],
            gif: nil,
            languageCode: .english,
            createdAt: now,
            updatedAt: now,
            visibility: .privateContent,
            responseCount: 0
        )
        assert(repository.createPost(privatePost, requesterID: ownerID))
        assert(repository.post(id: privatePost.id, viewerID: ownerID) != nil)
        assert(repository.post(id: privatePost.id, viewerID: visitorID) == nil)
        assert(!repository.deletePost(id: privatePost.id, requesterID: visitorID))

        let comment = PostComment(
            id: UUID(uuid: (0xa5, 0x8c, 0x51, 0x3d, 0xae, 0xf8, 0x52, 0x8a, 0x9d, 0x2c, 0xcf, 0xc6, 0x11, 0x06, 0x39, 0x6d)),
            postID: privatePost.id,
            ownerID: ownerID,
            text: "owner-comment",
            createdAt: now,
            updatedAt: now,
            visibility: .privateContent,
            languageCode: .english
        )
        assert(repository.createComment(comment, requesterID: ownerID))
        assert(repository.comments(postID: privatePost.id, viewerID: ownerID).contains { $0.id == comment.id })
        assert(repository.comments(postID: privatePost.id, viewerID: visitorID).isEmpty)
        assert(!repository.deleteComment(id: comment.id, requesterID: visitorID))

        let anonymousGameRequest = GameRequest(
            id: UUID(uuid: (0xd9, 0xeb, 0x52, 0x20, 0x0d, 0xa0, 0x53, 0x64, 0x91, 0x41, 0xc2, 0xb2, 0x33, 0xd7, 0x6d, 0xa5)),
            ownerID: ownerID,
            isAnonymous: true,
            anonymousIdentity: .playerA,
            title: "anonymous-owner-check",
            body: "The owner remains in storage.",
            createdAt: now,
            updatedAt: now,
            visibility: .publicContent,
            languageCode: .english,
            responseCount: 0
        )
        assert(repository.createGameRequest(anonymousGameRequest, requesterID: ownerID))
        assert(repository.gameRequest(id: anonymousGameRequest.id, viewerID: visitorID)?.ownerID == ownerID)
        let visitorGameRequestStore = GameRequestStore(repository: repository, userID: visitorID)
        assert(visitorGameRequestStore.displayIdentity(for: anonymousGameRequest).publicUser == nil)
        assert(!repository.deleteGameRequest(id: anonymousGameRequest.id, requesterID: visitorID))

        let photo = MatchMoment(
            id: UUID(uuid: (0xd8, 0x8e, 0x2a, 0x0f, 0x80, 0x00, 0x59, 0x59, 0x8a, 0xb0, 0x45, 0x22, 0xf2, 0xe3, 0x8d, 0xa9)),
            ownerID: ownerID,
            data: Data([0x01]),
            createdAt: now,
            updatedAt: now,
            visibility: .publicContent,
            languageCode: .english
        )
        assert(repository.createMatchMoment(photo, requesterID: ownerID))
        assert(repository.matchMoments(ownerID: ownerID, viewerID: visitorID).contains { $0.id == photo.id })
        assert(!repository.deleteMatchMoment(id: photo.id, requesterID: visitorID))

        let originalLanguage = repository.post(id: privatePost.id, viewerID: ownerID)?.languageCode
        _ = AppCopy()
        assert(repository.post(id: privatePost.id, viewerID: ownerID)?.languageCode == originalLanguage)
    }
}
#endif
