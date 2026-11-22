import Combine
import CryptoKit
import Foundation
import GRDB
import OSLog
import Supabase

// MAINTENANCE-POINT: SUPABASE-REPOSITORY-001
// Configured repository for data synchronization, permission checks, and Storage.
@MainActor
final class SupabaseAppDataRepository: ObservableObject, AppDataRepository {
    private struct ResponseKey: Hashable {
        let userID: UUID
        let contentID: UUID
    }

    private let client: SupabaseClient
    private let currentUserID: UUID
    private let changeBroadcaster = RepositoryChangeBroadcaster()

    private var profilesByID: [UUID: CommunityProfile] = [:]
    private var storedPosts: [FeedPost] = []
    private var storedComments: [PostComment] = []
    private var storedGameRequests: [GameRequest] = []
    private var storedMatchMoments: [MatchMoment] = []
    private var postResponses: Set<ResponseKey> = []
    private var gameRequestResponses: Set<ResponseKey> = []
    private var pendingMutationCount = 0
    private var profileRevision = 0
    private var isSynchronizing = false
    private var isRefreshingProfiles = false
    private var mutationTask: Task<Void, Never>?
    private var mediaURLCache: [String: (url: URL, expiresAt: Date)] = [:]
    private var pendingMatchMoments: [UUID: PendingMatchMoment] = [:]
    private let pendingStorage: Result<MatchMomentPendingStorage.Queue, Error>
    private var resumedMatchMoments = false
    private var postCursor: FeedCursor?
    private var gameRequestCursor: FeedCursor?
    private var isLoadingPage = false
    private(set) var hasMorePosts = false
    private(set) var hasMoreGameRequests = false
    private var personalPostRecords: [FeedPost] = []
    private var personalGameRequestRecords: [GameRequest] = []
    private var ownCounts = [0, 0, 0]
    private var commentTotals: [UUID: Int] = [:]
    private var recentlyViewedUsers: [UUID: Date] = [:]
    private var avatarURLCache: [String: (url: URL, expiresAt: Date)] = [:]
    private var pendingMutationFailure: RepositoryFailure?
    private var lastFailedOperation: (@MainActor () async throws -> Void)?
    private var lastFailedMutationContext: RepositoryMutationContext?
    private(set) var clubAnnouncement: ClubAnnouncement?
    private(set) var canManageClubAnnouncement = false
    private(set) var announcementLoadState: RepositoryLoadState = .loading
    private var isRefreshingAnnouncement = false
    private var isSavingAnnouncement = false

    @Published private(set) var loadState: RepositoryLoadState = .loading
    @Published private(set) var mutationState: RepositoryMutationState = .idle
    @Published private(set) var mutationContext: RepositoryMutationContext = .general

    var canRetryLastMutation: Bool {
        lastFailedOperation != nil
    }

    func changes() -> AsyncStream<Void> {
        changeBroadcaster.subscribe()
    }

    init(client: SupabaseClient, currentUserID: UUID) {
        self.client = client
        self.currentUserID = currentUserID
        let loaded = MatchMomentPendingStorage.load(ownerID: currentUserID)
        pendingMatchMoments = loaded.pending
        pendingStorage = loaded.storage
        let now = Date()
        profilesByID[currentUserID] = CommunityProfile(
            id: currentUserID,
            userID: currentUserID,
            nickname: String(localized: "Club member"),
            avatar: "RallyAvatar",
            avatarData: nil,
            avatarRemoteURL: nil,
            avatarStoragePath: nil,
            signature: "",
            languageCode: .english,
            visibility: .publicContent,
            areMatchMomentsPublic: false,
            displayIdentity: .publicIdentity,
            createdAt: now,
            updatedAt: now
        )
    }

    // CLUB-ANNOUNCEMENT-001
    // Only the server decides publisher access. Announcement failures do not block the feed.
    func refreshClubAnnouncement() async throws {
        guard !isRefreshingAnnouncement, !isSavingAnnouncement else { return }
        isRefreshingAnnouncement = true
        defer { isRefreshingAnnouncement = false }
        announcementLoadState = .loading
        notifyChange()
        do {
            async let rows: BackendBatch<ClubAnnouncementRow> = client.from("club_announcements")
                .select("id,body_zh_hant,body_en,body_ja,revision,updated_at").eq("id", value: 1).limit(1).execute().value
            async let access: BackendAccess = client.rpc("club_announcement_access").execute().value
            let (announcements, allowed) = try await (rows, access)
            if let latest = announcements.rows.first?.value {
                if latest.revision >= (clubAnnouncement?.revision ?? 0) { clubAnnouncement = latest }
            }
            canManageClubAnnouncement = allowed.isAllowed
            announcementLoadState = clubAnnouncement == nil ? .empty : .content
            notifyChange()
        } catch {
            canManageClubAnnouncement = false
            announcementLoadState = .failure(RepositoryFailure(error: error))
            notifyChange()
            throw error
        }
    }

    func saveClubAnnouncement(_ draft: ClubAnnouncementDraft, expectedRevision: Int) async throws {
        guard !isSavingAnnouncement else { throw ClubAnnouncementError.conflict }
        guard canManageClubAnnouncement else { throw ClubAnnouncementError.forbidden }
        guard draft.isValid else { throw ClubAnnouncementError.invalid }
        isSavingAnnouncement = true
        defer { isSavingAnnouncement = false }
        struct Parameters: Encodable {
            let body_zh_hant: String
            let body_en: String
            let body_ja: String
            let expected_revision: Int
        }
        let normalized = draft.normalized
        do {
            let saved: ClubAnnouncement = try await client.rpc("save_club_announcement",
                params: Parameters(body_zh_hant: normalized.bodyZH, body_en: normalized.bodyEN,
                    body_ja: normalized.bodyJA, expected_revision: expectedRevision)).execute().value
            clubAnnouncement = saved
            announcementLoadState = .content
            notifyChange()
        } catch {
            let description = String(describing: error)
            if description.contains("40001") { throw ClubAnnouncementError.conflict }
            if RepositoryFailure(error: error).kind == .permission {
                canManageClubAnnouncement = false
                notifyChange()
                throw ClubAnnouncementError.forbidden
            }
            throw error
        }
    }

    func synchronize() async throws {
        guard !isSynchronizing, pendingMutationCount == 0 else { return }
        isSynchronizing = true
        profileRevision += 1
        let revision = profileRevision
        defer { isSynchronizing = false }
        loadState = .loading
        notifyChange()
        do {
            async let posts = fetchPostPage(after: nil)
            async let gameRequests = fetchGameRequestPage(after: nil)
            async let responsePosts: [PostResponseRow] = allRows {
                self.client.from("post_reaction_responses").select("post_id,user_id")
                    .eq("user_id", value: self.currentUserID.uuidString).order("post_id").range(from: $0, to: $0 + 99)
            }
            async let responseGameRequests: [GameRequestResponseRow] = allRows {
                self.client.from("game_request_responses").select("game_request_id,user_id")
                    .eq("user_id", value: self.currentUserID.uuidString).order("game_request_id").range(from: $0, to: $0 + 99)
            }
            let (postPage, gameRequestPage, postResponseRows, gameRequestResponseRows) = try await (posts, gameRequests, responsePosts, responseGameRequests)
            let postRows = postPage.rows
            let gameRequestRows = gameRequestPage.rows
            let media = try await mediaForPosts(postRows.map(\.id))
            let ids = Set(postRows.map(\.owner_id) + gameRequestRows.compactMap(\.owner_id) + [currentUserID])
            let profiles = await hydratedProfiles(from: try await fetchProfiles(ids))
            try await refreshCounts()
            try Task.checkCancellation()
            guard revision == profileRevision, pendingMutationCount == 0 else {
                loadState = .content
                return
            }
            profilesByID = Dictionary(profiles.map { ($0.userID, $0) }, uniquingKeysWith: { _, new in new })
            storedPosts = postRows.map { $0.model(media: media[$0.id] ?? PostMediaCollection()) }
            storedGameRequests = gameRequestRows.map(\.model)
            storedComments = []
            personalPostRecords = []
            personalGameRequestRecords = []
            commentTotals = Dictionary(postRows.map { ($0.id, $0.comment_count ?? 0) }, uniquingKeysWith: { _, new in new })
            postCursor = postPage.nextCursor
            gameRequestCursor = gameRequestPage.nextCursor
            hasMorePosts = postPage.hasMore
            hasMoreGameRequests = gameRequestPage.hasMore
            postResponses = Set(postResponseRows.map { ResponseKey(userID: $0.user_id, contentID: $0.post_id) })
            gameRequestResponses = Set(gameRequestResponseRows.map { ResponseKey(userID: $0.user_id, contentID: $0.game_request_id) })
            try await refreshMatchMoments(ownerID: currentUserID)
            loadState = storedPosts.isEmpty && storedGameRequests.isEmpty ? .empty : .content
            notifyChange()
            if !resumedMatchMoments, case .success = pendingStorage {
                resumedMatchMoments = true
                for pending in pendingMatchMoments.values.sorted(by: { $0.row.sort_order < $1.row.sort_order }) {
                    enqueue { [weak self] in try await self?.persistMatchMoment(pending) }
                }
            }
        } catch {
            loadState = .failure(RepositoryFailure(error: error))
            notifyChange()
            throw error
        }
    }

    private struct FeedCursor {
        let position: BackendFeedPosition?
        let offset: Int
        var filter: String? { position?.filter }
    }

    private struct FeedPage<Row: Decodable> {
        let rows: [Row]
        let nextCursor: FeedCursor
        var hasMore: Bool

        init(batch: BackendBatch<Row>, after cursor: FeedCursor?) {
            rows = batch.rows
            hasMore = batch.rawCount == 40
            // Advance from the LAST RAW row, even when its content was discarded.
            // If its ordering keys are unusable, scan past the raw page under the same anchor.
            if let position = batch.lastPosition {
                nextCursor = FeedCursor(position: position, offset: 0)
            } else {
                nextCursor = FeedCursor(position: cursor?.position,
                    offset: (cursor?.offset ?? 0) + batch.rawCount)
            }
        }
    }

    private func allRows<Row: Decodable>(_ query: (Int) throws -> PostgrestTransformBuilder) async throws -> [Row] {
        try await BackendDecoding.allRows { offset in
            let page: BackendBatch<Row> = try await query(offset).execute().value
            return page
        }
    }

    private static let maximumConsecutiveUnreadableFeedPages = 3

    private static func readableFeedPage<Row: Decodable>(after cursor: FeedCursor?,
        fetch: (FeedCursor?) async throws -> BackendBatch<Row>) async throws -> FeedPage<Row> {
        var cursor = cursor
        var consecutiveUnreadablePages = 0
        while true {
            try Task.checkCancellation()
            var page = FeedPage(batch: try await fetch(cursor), after: cursor)
            // A fully discarded page must not strand the UI on an empty feed with more data.
            if !page.rows.isEmpty || !page.hasMore { return page }
            consecutiveUnreadablePages += 1
            if consecutiveUnreadablePages >= maximumConsecutiveUnreadableFeedPages {
                // Bound old clients' requests after a breaking server change. Keep the
                // continuation AFTER the final scanned raw page, but stop this feed load.
                page.hasMore = false
                return page
            }
            cursor = page.nextCursor
        }
    }

    private func fetchPostPage(after cursor: FeedCursor?) async throws -> FeedPage<PostRow> {
        try await Self.readableFeedPage(after: cursor) { cursor in
            let query = self.client.from("post_feed").select()
            if let filter = cursor?.filter { _ = query.or(filter) }
            let offset = cursor?.offset ?? 0
            let page: BackendFeedBatch<PostRow> = try await query.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: offset, to: offset + 39).execute().value
            return page.batch
        }
    }

    private func fetchGameRequestPage(after cursor: FeedCursor?) async throws -> FeedPage<GameRequestRow> {
        try await Self.readableFeedPage(after: cursor) { cursor in
            let query = try self.client.rpc("list_visible_game_requests")
            if let filter = cursor?.filter { _ = query.or(filter) }
            let offset = cursor?.offset ?? 0
            let page: BackendFeedBatch<GameRequestRow> = try await query.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: offset, to: offset + 39).execute().value
            return page.batch
        }
    }

    private func fetchProfiles(_ ids: Set<UUID>) async throws -> [ProfileRow] {
        var rows: [ProfileRow] = []
        let ids = ids.sorted { $0.uuidString < $1.uuidString }
        for start in stride(from: 0, to: ids.count, by: 100) {
            let page: BackendBatch<ProfileRow> = try await client.from("profiles").select()
                .in("user_id", values: ids[start..<min(start + 100, ids.count)].map(\.uuidString)).execute().value
            rows.append(contentsOf: page.rows)
        }
        return rows
    }

    private func mediaForPosts(_ ids: [UUID]) async throws -> [UUID: PostMediaCollection] {
        guard !ids.isEmpty else { return [:] }
        let rows: [PostMediaRow] = try await allRows {
            self.client.from("post_media").select().in("post_id", values: ids.map(\.uuidString))
                .order("post_id").order("sort_order").order("id").range(from: $0, to: $0 + 99)
        }
        return try await hydratedMedia(from: rows)
    }

    private func mergeProfiles(_ ids: Set<UUID>) async throws {
        let revision = profileRevision
        let profiles = await hydratedProfiles(from: try await fetchProfiles(ids))
        guard revision == profileRevision, pendingMutationCount == 0 else { return }
        for profile in profiles { profilesByID[profile.userID] = profile }
    }

    func loadMorePosts() async throws {
        guard hasMorePosts, !isLoadingPage, !isSynchronizing, pendingMutationCount == 0 else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        let revision = profileRevision
        let page = try await fetchPostPage(after: postCursor)
        let rows = page.rows
        let media = try await mediaForPosts(rows.map(\.id))
        try await mergeProfiles(Set(rows.map(\.owner_id)))
        guard revision == profileRevision, pendingMutationCount == 0 else { return }
        let existing = Set(storedPosts.map(\.id))
        storedPosts.append(contentsOf: rows.filter { !existing.contains($0.id) }.map { $0.model(media: media[$0.id] ?? PostMediaCollection()) })
        for row in rows { commentTotals[row.id] = row.comment_count ?? 0 }
        postCursor = page.nextCursor
        hasMorePosts = page.hasMore
        notifyChange()
    }

    func loadMoreGameRequests() async throws {
        guard hasMoreGameRequests, !isLoadingPage, !isSynchronizing, pendingMutationCount == 0 else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        let revision = profileRevision
        let page = try await fetchGameRequestPage(after: gameRequestCursor)
        let rows = page.rows
        try await mergeProfiles(Set(rows.compactMap(\.owner_id)))
        guard revision == profileRevision, pendingMutationCount == 0 else { return }
        let existing = Set(storedGameRequests.map(\.id))
        storedGameRequests.append(contentsOf: rows.filter { !existing.contains($0.id) }.map(\.model))
        gameRequestCursor = page.nextCursor
        hasMoreGameRequests = page.hasMore
        notifyChange()
    }

    func loadComments(postID: UUID) async throws {
        let revision = profileRevision
        let rows: [CommentRow] = try await allRows {
            self.client.from("comments").select().eq("post_id", value: postID.uuidString)
                .order("created_at").order("id").range(from: $0, to: $0 + 99)
        }
        try await mergeProfiles(Set(rows.map(\.owner_id)))
        guard revision == profileRevision, pendingMutationCount == 0 else { return }
        storedComments.removeAll { $0.postID == postID }
        storedComments.append(contentsOf: rows.map(\.model))
        commentTotals[postID] = rows.count
        notifyChange()
    }

    func loadPersonalRecords() async throws {
        let revision = profileRevision
        let postRows: [PostRow] = try await allRows {
            self.client.from("post_feed").select().eq("owner_id", value: self.currentUserID.uuidString)
                .order("created_at", ascending: false).order("id", ascending: false).range(from: $0, to: $0 + 99)
        }
        let gameRequestRows: [GameRequestRow] = try await allRows {
            try self.client.rpc("list_personal_game_requests")
                .order("created_at", ascending: false).order("id", ascending: false).range(from: $0, to: $0 + 99)
        }
        guard revision == profileRevision, pendingMutationCount == 0 else { return }
        personalPostRecords = postRows.map { $0.model(media: PostMediaCollection()) }
        personalGameRequestRecords = gameRequestRows.map(\.model)
        try await refreshCounts()
        notifyChange()
    }

    func personalPosts(viewerID: UUID) -> [FeedPost] {
        let rows = personalPostRecords + storedPosts.filter { $0.ownerID == viewerID }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            .values.sorted { $0.createdAt > $1.createdAt }
    }
    func personalGameRequests(viewerID: UUID) -> [GameRequest] {
        Dictionary((personalGameRequestRecords + storedGameRequests).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            .values.sorted { $0.createdAt > $1.createdAt }
    }
    func profileCounts(viewerID: UUID) -> [Int] { ownCounts }
    func commentCount(postID: UUID, viewerID: UUID) -> Int { commentTotals[postID] ?? 0 }
    private func refreshCounts() async throws {
        let revision = profileRevision
        let counts: BackendCounts = try await client.rpc("community_counts").execute().value
        guard revision == profileRevision, pendingMutationCount == 0 else { return }
        ownCounts = [counts.posts, counts.gameRequests, counts.responses]
    }

    // Refresh the shared identity cache without replacing the visible page with loading UI.
    func refreshProfiles() async throws {
        guard !isSynchronizing, !isRefreshingProfiles, pendingMutationCount == 0 else { return }
        isRefreshingProfiles = true
        let revision = profileRevision
        defer { isRefreshingProfiles = false }
        recentlyViewedUsers = recentlyViewedUsers.filter { $0.value > Date().addingTimeInterval(-120) }
        let requestedIDs = Set(recentlyViewedUsers.keys).union([currentUserID])
        let rows = try await fetchProfiles(requestedIDs)
        let profiles = await hydratedProfiles(from: rows)
        try Task.checkCancellation()
        guard revision == profileRevision, pendingMutationCount == 0 else { return }
        for id in requestedIDs { profilesByID.removeValue(forKey: id) }
        for profile in profiles { profilesByID[profile.userID] = profile }
        storedMatchMoments.removeAll { photo in
            photo.ownerID != currentUserID && !(profilesByID[photo.ownerID]?.areMatchMomentsPublic ?? false)
        }
        notifyChange()
    }

    func reportContent(kind: String, id: UUID, reason: String) async throws {
        try await client.rpc("report_content", params: [
            "report_id": UUID().uuidString, "kind": kind,
            "target": id.uuidString, "report_reason": reason
        ]).execute()
    }

    func blockedUsers() async throws -> [UUID] {
        let rows: BackendBatch<BlockRow> = try await client.from("user_blocks")
            .select("blocked_user_id").eq("user_id", value: currentUserID.uuidString)
            .execute().value
        return rows.rows.map(\.blocked_user_id)
    }

    func setUserBlocked(_ id: UUID, blocked: Bool) async throws {
        guard id != currentUserID else { throw URLError(.badURL) }
        if blocked {
            try await client.from("user_blocks").upsert([
                "user_id": currentUserID.uuidString, "blocked_user_id": id.uuidString
            ], onConflict: "user_id,blocked_user_id", ignoreDuplicates: true).execute()
            profileRevision += 1
            // Remove locally immediately, even if the following refresh fails.
            storedPosts.removeAll { $0.ownerID == id }
            storedComments.removeAll { $0.ownerID == id }
            // Anonymous author IDs are masked by the server; discard these cached
            // rows until the next authorized read rather than guess their owners.
            storedGameRequests.removeAll { $0.ownerID == id || $0.isAnonymous }
            personalPostRecords.removeAll { $0.ownerID == id }
            personalGameRequestRecords.removeAll { $0.ownerID == id || $0.isAnonymous }
            notifyChange()
        } else {
            try await client.from("user_blocks").delete()
                .eq("user_id", value: currentUserID.uuidString)
                .eq("blocked_user_id", value: id.uuidString).execute()
        }
        try await synchronize()
    }

    func refreshMatchMoments(ownerID: UUID) async throws {
        let batch: BackendBatch<MatchMomentReadRow> = try await client.from("match_moments").select()
            .eq("owner_id", value: ownerID.uuidString)
            .order("sort_order").order("id").limit(9).execute().value
        var photos: [MatchMoment] = []
        do {
            for record in batch.rows {
                let row = record.value
                guard ownerID == currentUserID || row.visibility == "public" else { continue }
                try Task.checkCancellation()
                // Authenticated download, not a transferable signed URL.
                let data = try await client.storage.from("match-moments").download(path: row.storage_path)
                photos.append(row.model(data: data))
            }
        } catch {
            storedMatchMoments.removeAll { $0.ownerID == ownerID }
            notifyChange()
            throw error
        }
        storedMatchMoments.removeAll { $0.ownerID == ownerID }
        if ownerID == currentUserID {
            let remoteIDs = Set(photos.map(\.id))
            photos.append(contentsOf: pendingMatchMoments.values
                .filter { !remoteIDs.contains($0.row.id) }
                .sorted { $0.row.sort_order < $1.row.sort_order }
                .map { $0.row.model(data: $0.data) })
        }
        storedMatchMoments.append(contentsOf: photos)
        notifyChange()
    }

    private func persistMatchMoment(_ pending: PendingMatchMoment) async throws {
        let storage = client.storage.from("match-moments")
        try await storage.upload(pending.row.storage_path, data: pending.data,
            options: FileOptions(contentType: "image/jpeg", upsert: true))
        try await client.from("match_moments").upsert(pending.row, onConflict: "id").execute()
        pendingMatchMoments.removeValue(forKey: pending.row.id)
        do { try pendingStorage.get().remove(id: pending.row.id) }
        catch { pendingMatchMoments[pending.row.id] = pending; throw error }
    }

    func clearMutationState() {
        guard pendingMutationCount == 0 else { return }
        mutationState = .idle
        mutationContext = .general
        lastFailedOperation = nil
        lastFailedMutationContext = nil
        notifyChange()
    }

    func retryLastMutation() {
        guard
            pendingMutationCount == 0,
            let operation = lastFailedOperation
        else { return }
        let context = lastFailedMutationContext ?? mutationContext
        lastFailedOperation = nil
        lastFailedMutationContext = nil
        enqueue(context: context, operation)
    }

    func user(id: UUID) -> CommunityUser? {
        recentlyViewedUsers[id] = Date()
        guard let profile = profilesByID[id] else { return nil }
        return CommunityUser(
            account: UserAccount(
                id: id,
                createdAt: profile.createdAt,
                updatedAt: profile.updatedAt
            ),
            profile: profile
        )
    }

    func profile(userID: UUID, viewerID: UUID) -> CommunityProfile? {
        recentlyViewedUsers[userID] = Date()
        guard let profile = profilesByID[userID] else { return nil }
        guard OwnershipPolicy.canRead(
            visibility: profile.visibility,
            ownerID: profile.userID,
            viewerID: viewerID
        ) else { return nil }
        return profile
    }

    func canModify(ownerID: UUID, requesterID: UUID) -> Bool {
        ownerID == requesterID && requesterID == currentUserID
    }

    func createProfile(_ profile: CommunityProfile, requesterID: UUID) -> Bool {
        guard canModify(ownerID: profile.userID, requesterID: requesterID),
              profilesByID[profile.userID] == nil else { return false }
        profilesByID[profile.userID] = profile
        let row = ProfileWrite(profile)
        enqueue { [client] in
            try await client.from("profiles").insert(row).execute()
        }
        notifyChange()
        return true
    }

    func deleteProfile(userID: UUID, requesterID: UUID) -> Bool {
        // Profile-only deletion is intentionally unavailable. Full account deletion
        // must go through the authenticated delete-account Edge Function.
        false
    }

    func posts(viewerID: UUID) -> [FeedPost] {
        storedPosts.filter {
            OwnershipPolicy.canRead(
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
        guard canModify(ownerID: post.ownerID, requesterID: requesterID),
              !storedPosts.contains(where: { $0.id == post.id }) else { return false }
        storedPosts.insert(post, at: 0)
        let row = PostWrite(post)
        let hasMedia = !post.images.isEmpty || post.gif != nil
        enqueue(context: hasMedia ? .mediaUpload : .general) { [self, client] in
            if hasMedia {
                try await persistPostWithMedia(post)
            } else {
                try await client.from("posts").insert(row).execute()
            }
        }
        notifyChange()
        return true
    }

    func updatePost(_ post: FeedPost, requesterID: UUID) -> Bool {
        guard let index = storedPosts.firstIndex(where: { $0.id == post.id }),
              canModify(ownerID: storedPosts[index].ownerID, requesterID: requesterID)
        else { return false }
        storedPosts[index] = post
        let row = PostWrite(post)
        enqueue { [client] in
            try await client
                .from("posts")
                .update(row)
                .eq("id", value: post.id.uuidString)
                .execute()
        }
        notifyChange()
        return true
    }

    func deletePost(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedPosts.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedPosts[index].ownerID, requesterID: requesterID)
        else { return false }
        let mediaPaths = (
            storedPosts[index].images + [storedPosts[index].gif].compactMap { $0 }
        )
        .compactMap(\.storagePath)
        storedPosts.remove(at: index)
        personalPostRecords.removeAll { $0.id == id }
        commentTotals.removeValue(forKey: id)
        storedComments.removeAll { $0.postID == id }
        postResponses = postResponses.filter { $0.contentID != id }
        enqueue { [client] in
            try await client.from("posts").delete().eq("id", value: id.uuidString).execute()
            if !mediaPaths.isEmpty {
                try await client.storage
                    .from(CommunityMediaStorage.bucket)
                    .remove(paths: mediaPaths)
            }
        }
        notifyChange()
        return true
    }

    func comments(postID: UUID, viewerID: UUID) -> [PostComment] {
        guard post(id: postID, viewerID: viewerID) != nil else { return [] }
        return storedComments.filter {
            $0.postID == postID && OwnershipPolicy.canRead(visibility: $0.visibility,
                ownerID: $0.ownerID, viewerID: viewerID)
        }
    }

    func createComment(_ comment: PostComment, requesterID: UUID) -> Bool {
        guard canModify(ownerID: comment.ownerID, requesterID: requesterID),
              post(id: comment.postID, viewerID: requesterID) != nil,
              !storedComments.contains(where: { $0.id == comment.id })
        else { return false }
        storedComments.append(comment)
        commentTotals[comment.postID, default: 0] += 1
        let row = CommentWrite(comment)
        enqueue { [client] in
            try await client.from("comments").insert(row).execute()
        }
        notifyChange()
        return true
    }

    func updateComment(_ comment: PostComment, requesterID: UUID) -> Bool {
        guard let index = storedComments.firstIndex(where: { $0.id == comment.id }),
              canModify(ownerID: storedComments[index].ownerID, requesterID: requesterID)
        else { return false }
        storedComments[index] = comment
        let row = CommentWrite(comment)
        enqueue { [client] in
            try await client
                .from("comments")
                .update(row)
                .eq("id", value: comment.id.uuidString)
                .execute()
        }
        notifyChange()
        return true
    }

    func deleteComment(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedComments.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedComments[index].ownerID, requesterID: requesterID)
        else { return false }
        let postID = storedComments[index].postID
        storedComments.remove(at: index)
        commentTotals[postID] = max(0, (commentTotals[postID] ?? 1) - 1)
        enqueue { [client] in
            try await client.from("comments").delete().eq("id", value: id.uuidString).execute()
        }
        notifyChange()
        return true
    }

    func gameRequests(viewerID: UUID) -> [GameRequest] {
        storedGameRequests.filter {
            OwnershipPolicy.canRead(
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
        guard canModify(ownerID: gameRequest.ownerID, requesterID: requesterID),
              !storedGameRequests.contains(where: { $0.id == gameRequest.id }) else { return false }
        storedGameRequests.insert(gameRequest, at: 0)
        let row = GameRequestWrite(gameRequest)
        enqueue { [client] in
            try await client.from("game_requests").insert(row).execute()
        }
        notifyChange()
        return true
    }

    func updateGameRequest(_ gameRequest: GameRequest, requesterID: UUID) -> Bool {
        guard let index = storedGameRequests.firstIndex(where: { $0.id == gameRequest.id }),
              canModify(ownerID: storedGameRequests[index].ownerID, requesterID: requesterID)
        else { return false }
        storedGameRequests[index] = gameRequest
        let row = GameRequestWrite(gameRequest)
        enqueue { [client] in
            try await client
                .from("game_requests")
                .update(row)
                .eq("id", value: gameRequest.id.uuidString)
                .execute()
        }
        notifyChange()
        return true
    }

    func deleteGameRequest(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedGameRequests.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedGameRequests[index].ownerID, requesterID: requesterID)
        else { return false }
        storedGameRequests.remove(at: index)
        gameRequestResponses = gameRequestResponses.filter { $0.contentID != id }
        enqueue { [client] in
            try await client.from("game_requests").delete().eq("id", value: id.uuidString).execute()
        }
        notifyChange()
        return true
    }

    func hasReactedForPost(postID: UUID, userID: UUID) -> Bool {
        postResponses.contains(ResponseKey(userID: userID, contentID: postID))
    }

    func togglePostReaction(postID: UUID, userID: UUID) {
        guard userID == currentUserID,
              let index = storedPosts.firstIndex(where: { $0.id == postID })
        else { return }
        let key = ResponseKey(userID: userID, contentID: postID)
        if postResponses.remove(key) != nil {
            storedPosts[index].responseCount = max(0, storedPosts[index].responseCount - 1)
            enqueue { [client] in
                try await client
                    .from("post_reaction_responses")
                    .delete()
                    .eq("post_id", value: postID.uuidString)
                    .eq("user_id", value: userID.uuidString)
                    .execute()
            }
        } else {
            postResponses.insert(key)
            storedPosts[index].responseCount += 1
            enqueue { [client] in
                try await client
                    .from("post_reaction_responses")
                    .insert(PostResponseWrite(post_id: postID, user_id: userID))
                    .execute()
            }
        }
        notifyChange()
    }

    func hasRespondedToGameRequest(gameRequestID: UUID, userID: UUID) -> Bool {
        gameRequestResponses.contains(ResponseKey(userID: userID, contentID: gameRequestID))
    }

    func respondToGameRequest(gameRequestID: UUID, userID: UUID) {
        guard userID == currentUserID,
              let index = storedGameRequests.firstIndex(where: { $0.id == gameRequestID })
        else { return }
        let key = ResponseKey(userID: userID, contentID: gameRequestID)
        guard gameRequestResponses.insert(key).inserted else { return }
        storedGameRequests[index].responseCount += 1
        enqueue { [client] in
            try await client
                .from("game_request_responses")
                .insert(GameRequestResponseWrite(game_request_id: gameRequestID, user_id: userID))
                .execute()
        }
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
              var profile = profilesByID[userID] else { return false }
        if let nickname { profile.nickname = nickname }
        if let signature { profile.signature = signature }
        if let matchMomentsPublic { profile.areMatchMomentsPublic = matchMomentsPublic }
        if let displayIdentity { profile.displayIdentity = displayIdentity }
        profile.updatedAt = Date()
        profilesByID[userID] = profile

        let row = ProfileWrite(profile)
        enqueue(context: .profileUpdate) { [client] in
            try await client
                .from("profiles")
                .update(row)
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
        notifyChange()
        return true
    }

    func updateAvatar(userID: UUID, requesterID: UUID, data: Data) -> Bool {
        guard canModify(ownerID: userID, requesterID: requesterID),
              data.count <= ProfileAvatarStorage.maximumFileSize,
              var profile = profilesByID[userID] else { return false }
        let oldPath = profile.avatarStoragePath
        let newPath = ProfileAvatarStorage.path(ownerID: userID, avatarID: UUID())
        profile.avatarData = data
        profile.avatarRemoteURL = nil
        profile.avatarStoragePath = newPath
        profile.updatedAt = Date()
        profilesByID[userID] = profile

        enqueue(context: .avatarUpload) { [self] in
            try await persistAvatar(
                userID: userID,
                data: data,
                newPath: newPath,
                oldPath: oldPath
            )
        }
        notifyChange()
        return true
    }

    func removeAvatar(userID: UUID, requesterID: UUID) -> Bool {
        guard canModify(ownerID: userID, requesterID: requesterID),
              var profile = profilesByID[userID] else { return false }
        let oldPath = profile.avatarStoragePath
        profile.avatarData = nil
        profile.avatarRemoteURL = nil
        profile.avatarStoragePath = nil
        profile.updatedAt = Date()
        profilesByID[userID] = profile

        enqueue(context: .avatarRemove) { [client] in
            try await client
                .from("profiles")
                .update(AvatarPathClear(updatedAt: Date()))
                .eq("user_id", value: userID.uuidString)
                .execute()
            if let oldPath {
                _ = try? await client.storage
                    .from(ProfileAvatarStorage.bucket)
                    .remove(paths: [oldPath])
            }
        }
        notifyChange()
        return true
    }

    func matchMoments(ownerID: UUID, viewerID: UUID) -> [MatchMoment] {
        guard let profile = profile(userID: ownerID, viewerID: viewerID),
              ownerID == viewerID || profile.areMatchMomentsPublic else { return [] }
        return storedMatchMoments.filter {
            $0.ownerID == ownerID && OwnershipPolicy.canRead(visibility: $0.visibility,
                ownerID: $0.ownerID, viewerID: viewerID)
        }
    }

    func createMatchMoment(_ photo: MatchMoment, requesterID: UUID) -> Bool {
        guard canModify(ownerID: photo.ownerID, requesterID: requesterID),
              !storedMatchMoments.contains(where: { $0.id == photo.id }),
              storedMatchMoments.filter({ $0.ownerID == photo.ownerID }).count < 9,
              photo.data.count <= ProfileAvatarStorage.maximumFileSize else { return false }
        let order = storedMatchMoments.filter { $0.ownerID == photo.ownerID }.count
        let row = MatchMomentRow(photo, sortOrder: order)
        let pending = PendingMatchMoment(row: row, data: photo.data)
        pendingMatchMoments[photo.id] = pending
        do { try pendingStorage.get().save(pending) }
        catch {
            pendingMatchMoments.removeValue(forKey: photo.id)
            mutationState = .failure(RepositoryFailure(error: error))
            notifyChange()
            return false
        }
        storedMatchMoments.append(photo)
        enqueue { [weak self] in try await self?.persistMatchMoment(pending) }
        notifyChange()
        return true
    }

    func updateMatchMoment(_ photo: MatchMoment, requesterID: UUID) -> Bool {
        guard let index = storedMatchMoments.firstIndex(where: { $0.id == photo.id }),
              canModify(ownerID: storedMatchMoments[index].ownerID, requesterID: requesterID)
        else { return false }
        storedMatchMoments[index] = photo
        let order = storedMatchMoments.filter { $0.ownerID == photo.ownerID }.firstIndex { $0.id == photo.id } ?? 0
        enqueue { [client] in
            try await client.from("match_moments").upsert(MatchMomentRow(photo, sortOrder: order), onConflict: "id").execute()
        }
        notifyChange()
        return true
    }

    func deleteMatchMoment(id: UUID, requesterID: UUID) -> Bool {
        guard let index = storedMatchMoments.firstIndex(where: { $0.id == id }),
              canModify(ownerID: storedMatchMoments[index].ownerID, requesterID: requesterID)
        else { return false }
        if pendingMatchMoments[id] != nil {
            do { try pendingStorage.get().remove(id: id) }
            catch {
                mutationState = .failure(RepositoryFailure(error: error))
                notifyChange()
                return false
            }
            pendingMatchMoments.removeValue(forKey: id)
        }
        let photo = storedMatchMoments.remove(at: index)
        enqueue { [client] in
            _ = try await client.storage.from("match-moments").remove(paths: [MatchMomentRow.path(photo)])
            try await client.from("match_moments").delete().eq("id", value: id.uuidString).execute()
        }
        notifyChange()
        return true
    }

    func moveMatchMoment(ownerID: UUID, id: UUID, offset: Int, requesterID: UUID) -> Bool {
        guard canModify(ownerID: ownerID, requesterID: requesterID) else { return false }
        let indices = storedMatchMoments.indices.filter { storedMatchMoments[$0].ownerID == ownerID }
        guard let position = indices.firstIndex(where: { storedMatchMoments[$0].id == id }),
              indices.indices.contains(position + offset) else { return false }
        storedMatchMoments.swapAt(indices[position], indices[position + offset])
        let ids = storedMatchMoments.filter { $0.ownerID == ownerID }.map { $0.id.uuidString }
        enqueue { [client] in
            try await client.rpc("reorder_match_moments", params: ["photo_ids": ids]).execute()
        }
        notifyChange()
        return true
    }

    private func hydratedMedia(
        from rows: [PostMediaRow]
    ) async throws -> [UUID: PostMediaCollection] {
        var mediaByPostID: [UUID: PostMediaCollection] = [:]
        let storage = client.storage.from(CommunityMediaStorage.bucket)
        let missingPaths = rows.map(\.storage_path).filter {
            (mediaURLCache[$0]?.expiresAt ?? .distantPast) <= Date()
        }
        for start in stride(from: 0, to: missingPaths.count, by: 50) {
            try Task.checkCancellation()
            let results = try await storage.createSignedURLs(
                paths: Array(missingPaths[start..<min(start + 50, missingPaths.count)]),
                expiresIn: CommunityMediaStorage.signedURLLifetime)
            for result in results {
                switch result {
                case let .success(path, signedURL):
                    mediaURLCache[path] = (signedURL, Date().addingTimeInterval(
                        TimeInterval(CommunityMediaStorage.signedURLLifetime - 300)))
                case .failure:
                    throw URLError(.resourceUnavailable)
                }
            }
        }

        for row in rows {
            try Task.checkCancellation()
            let signedURL: URL
            if let cached = mediaURLCache[row.storage_path], cached.expiresAt > Date() {
                signedURL = cached.url
            } else {
                signedURL = try await storage.createSignedURL(
                    path: row.storage_path, expiresIn: CommunityMediaStorage.signedURLLifetime)
                mediaURLCache[row.storage_path] = (signedURL, Date().addingTimeInterval(
                    TimeInterval(CommunityMediaStorage.signedURLLifetime - 300)))
            }
            let media = PostMedia(
                id: row.id,
                remoteURL: signedURL,
                storagePath: row.storage_path,
                mimeType: row.mime_type
            )
            var collection = mediaByPostID[row.post_id] ?? PostMediaCollection()
            if row.media_type == "gif" {
                collection.gif = media
            } else {
                collection.images.append(media)
            }
            mediaByPostID[row.post_id] = collection
        }
        let activePaths = Set(rows.map(\.storage_path))
        mediaURLCache = mediaURLCache.filter { activePaths.contains($0.key) }
        return mediaByPostID
    }

    private func hydratedProfiles(from rows: [ProfileRow]) async -> [CommunityProfile] {
        let storage = client.storage.from(ProfileAvatarStorage.bucket)
        var profiles: [CommunityProfile] = []
        profiles.reserveCapacity(rows.count)
        for row in rows {
            let signedURL: URL?
            if let path = row.avatar_path {
                if let cached = avatarURLCache[path], cached.expiresAt > Date() {
                    signedURL = cached.url
                } else {
                    signedURL = try? await storage.createSignedURL(
                        path: path,
                        expiresIn: ProfileAvatarStorage.signedURLLifetime
                    )
                    if let signedURL {
                        avatarURLCache[path] = (signedURL, Date().addingTimeInterval(
                            TimeInterval(ProfileAvatarStorage.signedURLLifetime - 300)
                        ))
                    }
                }
            } else {
                signedURL = nil
            }
            var profile = row.model(avatarRemoteURL: signedURL)
            if let path = profile.avatarStoragePath,
               let existing = profilesByID[profile.userID],
               existing.avatarStoragePath == path {
                profile.avatarData = existing.avatarData
            }
            profiles.append(profile)
        }
        let activePaths = Set(rows.compactMap(\.avatar_path))
        avatarURLCache = avatarURLCache.filter { activePaths.contains($0.key) }
        return profiles
    }

    private func persistAvatar(
        userID: UUID,
        data: Data,
        newPath: String,
        oldPath: String?
    ) async throws {
        guard data.count <= ProfileAvatarStorage.maximumFileSize else {
            throw AvatarStorageError.invalidImage
        }
        let storage = client.storage.from(ProfileAvatarStorage.bucket)
        do {
            _ = try? await storage.remove(paths: [newPath])
            try await storage.upload(
                newPath,
                data: data,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: false
                )
            )
            try await client
                .from("profiles")
                .update(AvatarPathUpdate(path: newPath, updatedAt: Date()))
                .eq("user_id", value: userID.uuidString)
                .execute()
            if let oldPath, oldPath != newPath {
                _ = try? await storage.remove(paths: [oldPath])
            }
        } catch {
            _ = try? await storage.remove(paths: [newPath])
            throw error
        }
    }

    private func persistPostWithMedia(_ post: FeedPost) async throws {
        let storage = client.storage.from(CommunityMediaStorage.bucket)
        var uploadedPaths: [String] = []
        var mediaRows: [PostMediaWrite] = []
        let orderedMedia = post.images.map { ($0, "image", "jpg") }
            + [post.gif].compactMap { media in
                media.map { ($0, "gif", "gif") }
            }
        guard orderedMedia.count <= CommunityMediaStorage.maximumItemCount else {
            throw MediaStorageError.invalidMedia
        }
        let plannedPaths = orderedMedia.map { item in
            CommunityMediaStorage.path(
                ownerID: post.ownerID,
                postID: post.id,
                mediaID: item.0.id,
                fileExtension: item.2
            )
        }

        do {
            // A retry may follow a network interruption after an object reached Storage.
            // These paths are unique to this unsaved post, so remove only those exact
            // owner-scoped objects before attempting fresh inserts.
            _ = try? await storage.remove(paths: plannedPaths)

            for (sortOrder, item) in orderedMedia.enumerated() {
                let (media, mediaType, _) = item
                guard
                    let data = media.data,
                    data.count <= CommunityMediaStorage.maximumFileSize,
                    media.mimeType == "image/jpeg" || media.mimeType == "image/gif"
                else {
                    throw MediaStorageError.invalidMedia
                }
                let path = plannedPaths[sortOrder]
                try await storage.upload(
                    path,
                    data: data,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: media.mimeType,
                        upsert: false
                    )
                )
                uploadedPaths.append(path)
                mediaRows.append(
                    PostMediaWrite(
                        id: media.id,
                        post_id: post.id,
                        owner_id: post.ownerID,
                        storage_path: path,
                        media_type: mediaType,
                        mime_type: media.mimeType,
                        byte_size: data.count,
                        sort_order: sortOrder
                    )
                )
            }

            try await client
                .from("posts")
                .upsert(PostWrite(post), onConflict: "id")
                .execute()
            try await client
                .from("post_media")
                .delete()
                .eq("post_id", value: post.id.uuidString)
                .execute()
            try await client
                .from("post_media")
                .insert(mediaRows)
                .execute()
        } catch {
            _ = try? await client
                .from("post_media")
                .delete()
                .eq("post_id", value: post.id.uuidString)
                .execute()
            _ = try? await client
                .from("posts")
                .delete()
                .eq("id", value: post.id.uuidString)
                .execute()
            if !uploadedPaths.isEmpty {
                _ = try? await storage.remove(paths: uploadedPaths)
            }
            throw error
        }
    }

    private func enqueue(
        context: RepositoryMutationContext = .general,
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        // An older in-flight read must never overwrite a locally updated avatar.
        profileRevision += 1
        if pendingMutationCount == 0 || context != .general {
            mutationContext = context
        }
        pendingMutationCount += 1
        mutationState = .submitting
        notifyChange()

        let previousMutation = mutationTask
        mutationTask = Task {
            await previousMutation?.value
            do {
                try await operation()
                finishMutation()
            } catch {
                lastFailedOperation = operation
                lastFailedMutationContext = context
                finishMutation(with: RepositoryFailure(error: error))
                try? await synchronize()
            }
        }
    }

    private func finishMutation(with failure: RepositoryFailure? = nil) {
        if let failure {
            pendingMutationFailure = failure
        }
        pendingMutationCount = max(0, pendingMutationCount - 1)
        guard pendingMutationCount == 0 else { return }

        if let pendingMutationFailure {
            mutationState = .failure(pendingMutationFailure)
            self.pendingMutationFailure = nil
        } else {
            mutationState = .succeeded
            lastFailedOperation = nil
            lastFailedMutationContext = nil
        }
        notifyChange()
        if pendingMutationCount == 0 {
            Task { try? await refreshCounts(); notifyChange() }
        }
    }

    private func notifyChange() {
        objectWillChange.send()
        changeBroadcaster.send()
    }
}

private enum SupabaseDate {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let standard = ISO8601DateFormatter()
    // Shared formatters are configured once; serialize reads as well as output.
    private static let formatterLock = NSLock()

    static func parse(_ value: String) -> Date {
        parseIfValid(value) ?? Date()
    }

    static func parseIfValid(_ value: String) -> Date? {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return fractional.date(from: value) ?? standard.date(from: value)
    }

    static func string(_ value: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return fractional.string(from: value)
    }
}

struct MatchMomentRow: Codable {
    let id: UUID
    let owner_id: UUID
    let storage_path: String
    let sort_order: Int
    let visibility: String
    let language_code: String
    let created_at: String
    let updated_at: String

    private enum CodingKeys: String, CodingKey {
        case id, owner_id, storage_path, sort_order, visibility, language_code, created_at, updated_at
    }

    static func path(_ photo: MatchMoment) -> String {
        "\(photo.ownerID.uuidString.lowercased())/match-moments/\(photo.id.uuidString.lowercased()).jpg"
    }

    init(_ photo: MatchMoment, sortOrder: Int) {
        id = photo.id
        owner_id = photo.ownerID
        storage_path = Self.path(photo)
        sort_order = sortOrder
        visibility = photo.visibility == .publicContent ? "public" : "private"
        language_code = AppLanguage.english.localeIdentifier
        created_at = SupabaseDate.string(photo.createdAt)
        updated_at = SupabaseDate.string(photo.updatedAt)
    }

    // Pending uploads keep the same archive fields and accept older language metadata.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        owner_id = try values.decode(UUID.self, forKey: .owner_id)
        storage_path = try values.decode(String.self, forKey: .storage_path)
        sort_order = try values.decode(Int.self, forKey: .sort_order)
        visibility = try values.decode(String.self, forKey: .visibility)
        language_code = AppLanguage.english.localeIdentifier
        created_at = try values.decode(String.self, forKey: .created_at)
        updated_at = try values.decode(String.self, forKey: .updated_at)
    }

    fileprivate init(server values: KeyedDecodingContainer<BackendKey>) throws {
        id = try values.required(UUID.self, "id")
        owner_id = try values.required(UUID.self, "owner_id")
        storage_path = try values.requiredPath("storage_path")
        sort_order = values.fallback(Int.self, "sort_order", 0)
        visibility = values.fallback(String.self, "visibility", "private")
        language_code = AppLanguage.english.localeIdentifier
        created_at = values.fallback(String.self, "created_at", BackendDecoding.epoch)
        updated_at = values.fallback(String.self, "updated_at", BackendDecoding.epoch)
    }

    func model(data: Data) -> MatchMoment {
        MatchMoment(id: id, ownerID: owner_id, data: data,
            createdAt: SupabaseDate.parse(created_at), updatedAt: SupabaseDate.parse(updated_at),
            visibility: visibility == "public" ? .publicContent : .privateContent,
            languageCode: .english)
    }
}

struct PendingMatchMoment: Codable {
    let row: MatchMomentRow
    let data: Data
}

// MAINTENANCE-POINT: MATCH-MOMENT-PENDING-001
// SQLite owns the pending queue. Legacy archives are kept for recovery.
@MainActor
enum MatchMomentPendingStorage {
    private static let files = FileManager.default
    private static let logger = Logger(subsystem: "com.example.projectl", category: "MatchMomentQueue")

    fileprivate struct LegacyArchive {
        let digest: Data
        let pending: [UUID: PendingMatchMoment]
        let isComplete: Bool

        init(data: Data, ownerID: UUID) {
            digest = Data(SHA256.hash(data: data))
            let batch = try? JSONDecoder().decode(BackendBatch<PendingMatchMoment>.self, from: data)
            let ownedRows = batch?.rows.filter { $0.row.owner_id == ownerID } ?? []
            pending = Dictionary(ownedRows.map { ($0.row.id, $0) }, uniquingKeysWith: { _, latest in latest })
            isComplete = batch != nil && batch?.discardedCount == 0 && ownedRows.count == batch?.rows.count
        }
    }

    private enum MigrationError: Error {
        case legacyArchiveChanged
        case competingLegacyArchives
        case invalidStoredOwner
    }

    struct Loaded {
        let pending: [UUID: PendingMatchMoment]
        let storage: Result<Queue, Error>
    }

    struct Queue {
        fileprivate let database: DatabaseQueue
        fileprivate let ownerID: UUID

        fileprivate func pendingPhotos() throws -> [UUID: PendingMatchMoment] {
            try database.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT photoID, metadata, imageData FROM pendingPhoto WHERE ownerID = ?
                    """, arguments: [ownerID.uuidString])
                let decoder = JSONDecoder()
                var photos: [UUID: PendingMatchMoment] = [:]
                for row in rows {
                    let id: String = try row.decode(atIndex: 0)
                    let metadata: Data = try row.decode(atIndex: 1)
                    let data: Data = try row.decode(atIndex: 2)
                    let photo = try decoder.decode(MatchMomentRow.self, from: metadata)
                    guard photo.owner_id == ownerID, photo.id.uuidString == id else {
                        throw MigrationError.invalidStoredOwner
                    }
                    photos[photo.id] = PendingMatchMoment(row: photo, data: data)
                }
                return photos
            }
        }

        fileprivate func importedDigest() throws -> Data? {
            try database.read { db in
                try Data.fetchOne(db, sql: "SELECT digest FROM legacyArchive WHERE ownerID = ?",
                    arguments: [ownerID.uuidString])
            }
        }

        fileprivate func importArchive(_ archive: LegacyArchive) throws {
            try database.write { db in
                for photo in archive.pending.values {
                    try insert(photo, into: db)
                }
                try db.execute(sql: "INSERT INTO legacyArchive (ownerID, digest) VALUES (?, ?)",
                    arguments: [ownerID.uuidString, archive.digest])
            }
        }

        func save(_ photo: PendingMatchMoment) throws {
            try database.write { db in try insert(photo, into: db) }
        }

        func remove(id: UUID) throws {
            try database.write { db in
                try db.execute(sql: "DELETE FROM pendingPhoto WHERE ownerID = ? AND photoID = ?",
                    arguments: [ownerID.uuidString, id.uuidString])
            }
        }

        private func insert(_ photo: PendingMatchMoment, into db: Database) throws {
            guard photo.row.owner_id == ownerID else { throw MigrationError.invalidStoredOwner }
            try db.execute(sql: """
                INSERT INTO pendingPhoto (ownerID, photoID, metadata, imageData) VALUES (?, ?, ?, ?)
                """, arguments: [
                    ownerID.uuidString, photo.row.id.uuidString,
                    try JSONEncoder().encode(photo.row), photo.data
                ])
        }
    }

    private static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("MatchMomentUploads.v1", isDirectory: true)
    }

    static func url(ownerID: UUID, directory: URL? = nil) -> URL {
        (directory ?? defaultDirectory).appendingPathComponent(ownerID.uuidString + ".json")
    }

    private static func databaseDirectory(_ directory: URL?) -> URL {
        (directory ?? defaultDirectory).appendingPathComponent("GRDB.v1", isDirectory: true)
    }

    static func databaseURL(directory: URL? = nil) -> URL {
        databaseDirectory(directory).appendingPathComponent("match-moment-pending.v1.sqlite")
    }

    static func archiveURL(ownerID: UUID, isComplete: Bool, date: Date, directory: URL? = nil) -> URL {
        let kind = isComplete ? "migrated" : "unreadable"
        return databaseDirectory(directory)
            .appendingPathComponent("\(ownerID.uuidString).\(kind)-\(Int(date.timeIntervalSince1970)).json")
    }

    static func openDatabase(directory: URL? = nil) throws -> DatabaseQueue {
        let folder = databaseDirectory(directory)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: attributes)
        try excludeFromBackup(folder)
        let url = databaseURL(directory: directory)
        if !files.fileExists(atPath: url.path) {
            try Data().write(to: url, options: [.withoutOverwriting, .completeFileProtection])
        }
        try excludeFromBackup(url)

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        let database = try DatabaseQueue(path: url.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createPendingPhotoQueue.v1") { db in
            try db.create(table: "pendingPhoto") { table in
                table.column("ownerID", .text).notNull()
                table.column("photoID", .text).notNull()
                table.column("metadata", .blob).notNull()
                table.column("imageData", .blob).notNull()
                table.primaryKey(["ownerID", "photoID"])
            }
            try db.create(table: "legacyArchive") { table in
                table.primaryKey("ownerID", .text)
                table.column("digest", .blob).notNull()
            }
        }
        try migrator.migrate(database)
        return database
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private static func readArchive(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    private static func interruptedArchive(ownerID: UUID, directory: URL?) throws -> URL? {
        let items = try files.contentsOfDirectory(at: databaseDirectory(directory), includingPropertiesForKeys: nil)
        let backups = items.filter {
            $0.lastPathComponent.hasPrefix(ownerID.uuidString + ".unreadable-") && $0.pathExtension == "json"
        }
        guard backups.count <= 1 else { throw MigrationError.competingLegacyArchives }
        return backups.first
    }

    static func load(ownerID: UUID, directory: URL? = nil, backupDate: Date = Date()) -> Loaded {
        let original = url(ownerID: ownerID, directory: directory)
        var pending: [UUID: PendingMatchMoment] = [:]
        do {
            let legacy = try readArchive(original).map { LegacyArchive(data: $0, ownerID: ownerID) }
            // If the database is unavailable, keep any readable original photos visible without writing.
            pending = legacy?.pending ?? [:]
            let queue = Queue(database: try openDatabase(directory: directory), ownerID: ownerID)
            let stored = try queue.pendingPhotos()
            let receipt = try queue.importedDigest()

            if let legacy {
                if let receipt {
                    // A commit can succeed before the original is renamed. Never import that file twice.
                    pending = stored
                    guard receipt == legacy.digest else { throw MigrationError.legacyArchiveChanged }
                } else {
                    pending.merge(stored) { _, stored in stored }
                    guard try interruptedArchive(ownerID: ownerID, directory: directory) == nil else {
                        throw MigrationError.competingLegacyArchives
                    }
                }
                let backup = archiveURL(ownerID: ownerID, isComplete: legacy.isComplete,
                    date: backupDate, directory: directory)
                if receipt == nil {
                    if !legacy.isComplete {
                        try files.moveItem(at: original, to: backup)
                    }
                    try queue.importArchive(legacy)
                }
                if legacy.isComplete || receipt != nil {
                    try files.moveItem(at: original, to: backup)
                }
            } else {
                pending = stored
                if receipt == nil, let backup = try interruptedArchive(ownerID: ownerID, directory: directory),
                   let data = try readArchive(backup) {
                    // Only GRDB-era backups can represent an import interrupted after the rename.
                    let legacy = LegacyArchive(data: data, ownerID: ownerID)
                    pending.merge(legacy.pending) { stored, _ in stored }
                    try queue.importArchive(legacy)
                }
            }
            return Loaded(pending: pending, storage: .success(queue))
        } catch {
            logger.error("Pending match-photo queue is unavailable.")
            return Loaded(pending: pending, storage: .failure(error))
        }
    }

    static func clear(ownerID: UUID, directory: URL? = nil) {
        do {
            if files.fileExists(atPath: databaseURL(directory: directory).path) {
                let database = try openDatabase(directory: directory)
                try database.write { db in
                    try db.execute(sql: "DELETE FROM pendingPhoto WHERE ownerID = ?", arguments: [ownerID.uuidString])
                    try db.execute(sql: "DELETE FROM legacyArchive WHERE ownerID = ?", arguments: [ownerID.uuidString])
                }
            }

            let prefix = ownerID.uuidString + "."
            for folder in [directory ?? defaultDirectory, databaseDirectory(directory)] {
                if !files.fileExists(atPath: folder.path) { continue }
                let items = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                for file in items where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "json" {
                    try files.removeItem(at: file)
                }
            }
        } catch {
            logger.error("Could not clear the pending match-photo queue.")
        }
    }
}

#if DEBUG
@MainActor
struct LegacyPendingPhotoFixture {
    let directory: URL
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MATCH-MOMENT-PENDING-001.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func original(_ ownerID: UUID) -> URL {
        MatchMomentPendingStorage.url(ownerID: ownerID, directory: directory)
    }

    func backup(_ ownerID: UUID, complete: Bool) -> URL {
        MatchMomentPendingStorage.archiveURL(ownerID: ownerID, isComplete: complete,
            date: Self.date, directory: directory)
    }

    func load(_ ownerID: UUID) -> MatchMomentPendingStorage.Loaded {
        MatchMomentPendingStorage.load(ownerID: ownerID, directory: directory, backupDate: Self.date)
    }

    func record(ownerID: UUID, id: UUID, order: Int = 0, payload: String = "AQID") -> String {
        // Literal historical JSON written independently of the current encoder.
        """
        {"row":{"id":"\(id.uuidString)","owner_id":"\(ownerID.uuidString)",\
        "storage_path":"\(ownerID.uuidString.lowercased())/match-moments/\(id.uuidString.lowercased()).jpg",\
        "sort_order":\(order),"visibility":"private","language_code":"ja",\
        "created_at":"2026-10-22T00:00:00Z","updated_at":"2026-10-22T00:00:00Z"},"data":"\(payload)"}
        """
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension MatchMomentPendingStorage {
    static func runContractChecks() {
        enum Failure: Error { case check(String) }
        func check(_ condition: Bool, _ description: String) throws {
            guard condition else { throw Failure.check(description) }
        }

        do {
            let fixture = try LegacyPendingPhotoFixture()
            defer { fixture.cleanup() }

            let ownerID = UUID(), photoID = UUID()
            let record = fixture.record(ownerID: ownerID, id: photoID, order: 2, payload: "BAUG")
            let original = fixture.original(ownerID)
            let bytes = Data("[\(fixture.record(ownerID: ownerID, id: photoID)),\(record)]".utf8)
            try bytes.write(to: original)
            let loaded = fixture.load(ownerID)
            let queue = try loaded.storage.get()
            let retained = try Data(contentsOf: fixture.backup(ownerID, complete: true))
            try check(retained == bytes && !files.fileExists(atPath: original.path), "Complete archive")
            try check(loaded.pending.count == 1 && loaded.pending[photoID]?.data == Data([4, 5, 6])
                && loaded.pending[photoID]?.row.sort_order == 2, "Last duplicate wins")
            try queue.remove(id: photoID)
            try check(fixture.load(ownerID).pending.isEmpty, "A completed migration is not reapplied")

            let partialOwner = UUID(), partialID = UUID()
            let partial = Data("[null,\(fixture.record(ownerID: partialOwner, id: partialID)),\(record)]".utf8)
            try partial.write(to: fixture.original(partialOwner))
            let recovered = fixture.load(partialOwner)
            _ = try recovered.storage.get()
            try check(Set(recovered.pending.keys) == [partialID], "Owner-specific partial recovery")
            let partialRetained = try Data(contentsOf: fixture.backup(partialOwner, complete: false))
            try check(partialRetained == partial, "Partial archive bytes")
            clear(ownerID: partialOwner, directory: fixture.directory)
            try check(!files.fileExists(atPath: fixture.backup(partialOwner, complete: false).path)
                && fixture.load(partialOwner).pending.isEmpty, "Account cleanup")
            try check(files.fileExists(atPath: fixture.backup(ownerID, complete: true).path),
                "Account cleanup must preserve other accounts")
            print("MATCH-MOMENT-PENDING-001 passed")
        } catch {
            preconditionFailure("MATCH-MOMENT-PENDING-001 failed: \(error)")
        }
    }
}
#endif

private enum MediaStorageError: LocalizedError {
    case invalidMedia

    var errorDescription: String? {
        "The selected media is unsupported or exceeds the upload limit."
    }
}

private enum AvatarStorageError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "The selected avatar is unsupported or exceeds the upload limit."
    }
}

private struct PostMediaCollection {
    var images: [PostMedia] = []
    var gif: PostMedia?
}

private extension ContentVisibility {
    init(databaseValue: String) {
        self = databaseValue == "public" ? .publicContent : .privateContent
    }

    var databaseValue: String {
        self == .privateContent ? "private" : "public"
    }
}

private struct ProfileRow: Decodable {
    let user_id: UUID
    let nickname: String
    let signature: String
    let avatar_url: String?
    let avatar_path: String?
    let visibility: String
    let match_moments_public: Bool
    let display_identity: String
    let created_at: String
    let updated_at: String

    // Required: user_id establishes ownership. Display metadata is optional; privacy defaults closed.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: BackendKey.self)
        user_id = try values.required(UUID.self, "user_id")
        nickname = values.fallback(String.self, "nickname", "")
        signature = values.fallback(String.self, "signature", "")
        avatar_url = values.optional(String.self, "avatar_url")
        avatar_path = values.optional(String.self, "avatar_path").flatMap { $0.isEmpty ? nil : $0 }
        visibility = values.fallback(String.self, "visibility", "private")
        match_moments_public = values.fallback(Bool.self, "match_moments_public", false)
        display_identity = values.fallback(String.self, "display_identity", "anonymous")
        created_at = values.fallback(String.self, "created_at", BackendDecoding.epoch)
        updated_at = values.fallback(String.self, "updated_at", BackendDecoding.epoch)
    }

    func model(avatarRemoteURL: URL?) -> CommunityProfile {
        CommunityProfile(
            id: user_id,
            userID: user_id,
            nickname: nickname,
            avatar: "RallyAvatar",
            avatarData: nil,
            avatarRemoteURL: avatarRemoteURL,
            avatarStoragePath: avatar_path,
            signature: signature,
            languageCode: .english,
            visibility: ContentVisibility(databaseValue: visibility),
            areMatchMomentsPublic: match_moments_public,
            displayIdentity: display_identity == "public" ? .publicIdentity : .anonymous,
            createdAt: SupabaseDate.parse(created_at),
            updatedAt: SupabaseDate.parse(updated_at)
        )
    }
}

private struct ProfileWrite: Encodable {
    let user_id: UUID
    let nickname: String
    let signature: String
    let avatar_path: String?
    let language_code: String
    let visibility: String
    let match_moments_public: Bool
    let display_identity: String
    let updated_at: String

    init(_ value: CommunityProfile) {
        user_id = value.userID
        nickname = value.nickname
        signature = value.signature
        avatar_path = value.avatarStoragePath
        language_code = AppLanguage.english.localeIdentifier
        visibility = value.visibility.databaseValue
        match_moments_public = value.areMatchMomentsPublic
        display_identity = value.displayIdentity == .anonymous ? "anonymous" : "public"
        updated_at = SupabaseDate.string(value.updatedAt)
    }
}

private struct AvatarPathUpdate: Encodable {
    let avatar_path: String
    let updated_at: String

    init(path: String, updatedAt: Date) {
        avatar_path = path
        updated_at = SupabaseDate.string(updatedAt)
    }
}

private struct AvatarPathClear: Encodable {
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case avatarPath = "avatar_path"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .avatarPath)
        try container.encode(SupabaseDate.string(updatedAt), forKey: .updatedAt)
    }
}

private struct PostRow: Decodable {
    let id: UUID
    let owner_id: UUID
    let body: String
    let visibility: String
    let created_at: String
    let updated_at: String
    let response_count: Int
    let comment_count: Int?

    // Required: id/owner_id/body identify the item, its owner and content (media-only body may be empty).
    // Counts, timestamps and language are display metadata; visibility fails closed.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: BackendKey.self)
        id = try values.required(UUID.self, "id")
        owner_id = try values.required(UUID.self, "owner_id")
        body = try values.required(String.self, "body")
        visibility = values.fallback(String.self, "visibility", "private")
        created_at = values.fallback(String.self, "created_at", BackendDecoding.epoch)
        updated_at = values.fallback(String.self, "updated_at", BackendDecoding.epoch)
        response_count = max(0, values.fallback(Int.self, "response_count", 0))
        comment_count = max(0, values.fallback(Int.self, "comment_count", 0))
    }

    func model(media: PostMediaCollection) -> FeedPost {
        FeedPost(
            id: id,
            ownerID: owner_id,
            text: body,
            images: media.images,
            gif: media.gif,
            languageCode: .english,
            createdAt: SupabaseDate.parse(created_at),
            updatedAt: SupabaseDate.parse(updated_at),
            visibility: ContentVisibility(databaseValue: visibility),
            responseCount: response_count
        )
    }
}

private struct PostMediaRow: Decodable {
    let id: UUID
    let post_id: UUID
    let owner_id: UUID
    let storage_path: String
    let media_type: String
    let mime_type: String
    let byte_size: Int
    let sort_order: Int

    // Required: IDs establish attachment/ownership; storage_path locates the content.
    // Type/MIME/size/order are display metadata; unknown media types use the existing image path.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: BackendKey.self)
        id = try values.required(UUID.self, "id")
        post_id = try values.required(UUID.self, "post_id")
        owner_id = try values.required(UUID.self, "owner_id")
        storage_path = try values.requiredPath("storage_path")
        media_type = values.fallback(String.self, "media_type", "image")
        mime_type = values.fallback(String.self, "mime_type", "image/jpeg")
        byte_size = max(0, values.fallback(Int.self, "byte_size", 0))
        sort_order = values.fallback(Int.self, "sort_order", 0)
    }
}

private struct PostMediaWrite: Encodable {
    let id: UUID
    let post_id: UUID
    let owner_id: UUID
    let storage_path: String
    let media_type: String
    let mime_type: String
    let byte_size: Int
    let sort_order: Int
}

private struct PostWrite: Encodable {
    let id: UUID
    let owner_id: UUID
    let body: String
    let language_code: String
    let visibility: String
    let updated_at: String

    init(_ value: FeedPost) {
        id = value.id
        owner_id = value.ownerID
        body = value.text
        language_code = AppLanguage.english.localeIdentifier
        visibility = value.visibility.databaseValue
        updated_at = SupabaseDate.string(value.updatedAt)
    }
}

private struct CommentRow: Decodable {
    let id: UUID
    let post_id: UUID
    let owner_id: UUID
    let body: String
    let visibility: String
    let created_at: String
    let updated_at: String

    // Required: IDs establish comment/parent/ownership, body is content. Metadata is optional; visibility closes.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: BackendKey.self)
        id = try values.required(UUID.self, "id")
        post_id = try values.required(UUID.self, "post_id")
        owner_id = try values.required(UUID.self, "owner_id")
        body = try values.required(String.self, "body")
        visibility = values.fallback(String.self, "visibility", "private")
        created_at = values.fallback(String.self, "created_at", BackendDecoding.epoch)
        updated_at = values.fallback(String.self, "updated_at", BackendDecoding.epoch)
    }

    var model: PostComment {
        PostComment(
            id: id,
            postID: post_id,
            ownerID: owner_id,
            text: body,
            createdAt: SupabaseDate.parse(created_at),
            updatedAt: SupabaseDate.parse(updated_at),
            visibility: ContentVisibility(databaseValue: visibility),
            languageCode: .english
        )
    }
}

private struct CommentWrite: Encodable {
    let id: UUID
    let post_id: UUID
    let owner_id: UUID
    let body: String
    let language_code: String
    let visibility: String
    let updated_at: String

    init(_ value: PostComment) {
        id = value.id
        post_id = value.postID
        owner_id = value.ownerID
        body = value.text
        language_code = AppLanguage.english.localeIdentifier
        visibility = value.visibility.databaseValue
        updated_at = SupabaseDate.string(value.updatedAt)
    }
}

private struct GameRequestRow: Decodable {
    let id: UUID
    let owner_id: UUID?
    let is_anonymous: Bool
    let anonymous_identity: String
    let title: String
    let body: String
    let visibility: String
    let created_at: String
    let updated_at: String
    let response_count: Int

    // Required: id/title/body are content. is_anonymous must be a known Bool or the row is dropped.
    // A public identity requires owner_id; a known anonymous RPC row may omit its masked owner.
    // Counts/timestamps/language/anonymous label are metadata; visibility fails closed.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: BackendKey.self)
        id = try values.required(UUID.self, "id")
        is_anonymous = try values.required(Bool.self, "is_anonymous")
        if is_anonymous {
            owner_id = try values.decodeIfPresent(UUID.self, forKey: BackendKey("owner_id"))
        } else {
            owner_id = try values.required(UUID.self, "owner_id")
        }
        anonymous_identity = values.fallback(String.self, "anonymous_identity", "player_a")
        title = try values.required(String.self, "title")
        body = try values.required(String.self, "body")
        visibility = values.fallback(String.self, "visibility", "private")
        created_at = values.fallback(String.self, "created_at", BackendDecoding.epoch)
        updated_at = values.fallback(String.self, "updated_at", BackendDecoding.epoch)
        response_count = max(0, values.fallback(Int.self, "response_count", 0))
    }

    var model: GameRequest {
        GameRequest(
            id: id,
            ownerID: owner_id ?? id,
            isAnonymous: is_anonymous,
            anonymousIdentity: anonymous_identity == "player_b" ? .playerB : .playerA,
            title: title,
            body: body,
            createdAt: SupabaseDate.parse(created_at),
            updatedAt: SupabaseDate.parse(updated_at),
            visibility: ContentVisibility(databaseValue: visibility),
            languageCode: .english,
            responseCount: response_count
        )
    }
}

private struct GameRequestWrite: Encodable {
    let id: UUID
    let owner_id: UUID
    let is_anonymous: Bool
    let anonymous_identity: String
    let title: String
    let body: String
    let language_code: String
    let visibility: String
    let updated_at: String

    init(_ value: GameRequest) {
        id = value.id
        owner_id = value.ownerID
        is_anonymous = value.isAnonymous
        anonymous_identity = value.anonymousIdentity.rawValue
        title = value.title
        body = value.body
        language_code = AppLanguage.english.localeIdentifier
        visibility = value.visibility.databaseValue
        updated_at = SupabaseDate.string(value.updatedAt)
    }
}

// Both IDs are required to safely associate a response with content and a user; no optional fields.
private struct PostResponseRow: Decodable {
    let post_id: UUID
    let user_id: UUID
}

// Both IDs are required to safely associate a response with content and a user; no optional fields.
private struct GameRequestResponseRow: Decodable {
    let game_request_id: UUID
    let user_id: UUID
}

private struct PostResponseWrite: Encodable {
    let post_id: UUID
    let user_id: UUID
}

private struct GameRequestResponseWrite: Encodable {
    let game_request_id: UUID
    let user_id: UUID
}

// MAINTENANCE-POINT: BACKEND-DECODE-001
// Server reads only: unknown keys are ignored, optional metadata defaults locally,
// and a rejected element is never written back, deleted or repaired on the server.
private struct BackendKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where Key == BackendKey {
    func required<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try decode(type, forKey: BackendKey(name))
    }
    func optional<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        try? decode(type, forKey: BackendKey(name))
    }
    func fallback<T: Decodable>(_ type: T.Type, _ name: String, _ defaultValue: T) -> T {
        optional(type, name) ?? defaultValue
    }
    func requiredPath(_ name: String) throws -> String {
        let path = try required(String.self, name)
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: BackendKey(name), in: self,
                debugDescription: "Required storage path is empty")
        }
        return path
    }
}

private enum BackendDecoding {
    static let epoch = "1970-01-01T00:00:00Z"
    static let logger = Logger(subsystem: "com.example.projectl", category: "BackendDecode")

    static func allRows<Row: Decodable>(fetch: (Int) async throws -> BackendBatch<Row>) async throws -> [Row] {
        var rows: [Row] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await fetch(offset)
            rows.append(contentsOf: page.rows)
            // A full raw page with zero retained records STILL has a next page.
            if page.rawCount < 100 { return rows }
            offset += page.rawCount
        }
    }
}

private struct BackendBatch<Row: Decodable>: Decodable {
    var rows: [Row] = []
    var rawCount = 0
    var discardedCount = 0
    let lastPosition: BackendFeedPosition?

    init(from decoder: Decoder) throws {
        try self.init(from: decoder, capturesFeedPosition: false)
    }

    init(from decoder: Decoder, capturesFeedPosition: Bool) throws {
        var records = try decoder.unkeyedContainer()
        var lastRecord: Decoder?
        while !records.isAtEnd {
            // Consumes exactly one element before decoding; malformed/null/scalar records
            // cannot trap the loop or make a later good record disappear.
            let record = try records.superDecoder()
            rawCount += 1
            if capturesFeedPosition { lastRecord = record }
            do { rows.append(try Row(from: record)) }
            catch { discardedCount += 1 }
        }
        // Only feed reads keep the LAST raw decoder. Decode its position once, before the
        // decoding scope ends; normal reads (including allRows<PostRow>) do no cursor work.
        if let lastRecord { lastPosition = try? BackendFeedPosition(from: lastRecord) }
        else { lastPosition = nil }
        if discardedCount > 0 {
            // Only type/count: never log raw data, content, user IDs or decoder error payloads.
            let rowType = String(describing: Row.self)
            let discarded = discardedCount
            let total = rawCount
            BackendDecoding.logger.notice("\(rowType, privacy: .public): discarded \(discarded, privacy: .public)/\(total, privacy: .public)")
        }
    }
}

private struct BackendFeedBatch<Row: Decodable>: Decodable {
    let batch: BackendBatch<Row>
    init(from decoder: Decoder) throws {
        batch = try BackendBatch(from: decoder, capturesFeedPosition: true)
    }
}

private struct BackendFeedPosition: Decodable {
    let time: String
    let id: UUID
    var filter: String { "created_at.lt.\(time),and(created_at.eq.\(time),id.lt.\(id.uuidString))" }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: BackendKey.self)
        id = try values.required(UUID.self, "id")
        let rawTime = try values.required(String.self, "created_at")
        guard rawTime.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#,
            options: .regularExpression) != nil,
            SupabaseDate.parseIfValid(rawTime) != nil else {
            throw DecodingError.dataCorruptedError(forKey: BackendKey("created_at"), in: values,
                debugDescription: "Unusable feed ordering timestamp")
        }
        // Validate before interpolation, but preserve server subsecond precision to avoid skipping
        // rows with the same timestamp. Never use a synthesized display timestamp as a cursor.
        time = rawTime
    }
}

// Server reads allow optional metadata. Pending uploads decode their stored fields separately.
private struct MatchMomentReadRow: Decodable {
    let value: MatchMomentRow
    // Required: id/owner_id/path establish ownership and image content.
    // Order/timestamps/language are display metadata; visibility defaults to private.
    init(from decoder: Decoder) throws {
        value = try MatchMomentRow(server: decoder.container(keyedBy: BackendKey.self))
    }
}

private struct BlockRow: Decodable {
    // Required target ID: no safe substitute for a blocked user; no optional fields.
    let blocked_user_id: UUID
}

private struct BackendCounts: Decodable {
    // All counts are nonessential display metadata; missing/malformed/negative values become zero.
    let posts: Int
    let gameRequests: Int
    let responses: Int
    init(from decoder: Decoder) throws {
        let values = try? decoder.container(keyedBy: BackendKey.self)
        posts = max(0, values?.fallback(Int.self, "posts", 0) ?? 0)
        gameRequests = max(0, values?.fallback(Int.self, "game_requests", 0) ?? 0)
        responses = max(0, values?.fallback(Int.self, "responses", 0) ?? 0)
    }
}

private struct BackendAccess: Decodable {
    let isAllowed: Bool
    // Only a literal true grants access; null, unknown strings/numbers/objects fail closed.
    init(from decoder: Decoder) throws {
        isAllowed = (try? decoder.singleValueContainer().decode(Bool.self)) ?? false
    }
}

private struct ClubAnnouncementRow: Decodable {
    let value: ClubAnnouncement
    // Required: singleton ID, all three bodies, revision (needed for safe optimistic writes).
    // updated_at is optional display metadata. Keep mutation response decoding unchanged.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: BackendKey.self)
        value = ClubAnnouncement(id: try values.required(Int.self, "id"),
            bodyZH: try values.required(String.self, "body_zh_hant"),
            bodyEN: try values.required(String.self, "body_en"),
            bodyJA: try values.required(String.self, "body_ja"),
            revision: try values.required(Int.self, "revision"),
            updatedAt: values.fallback(String.self, "updated_at", BackendDecoding.epoch))
        // Publishing limits are not a read contract: accept future longer/partial versions.
        guard value.id == 1, value.revision >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: BackendKey("id"), in: values,
                debugDescription: "Invalid announcement contract")
        }
    }
}

#if DEBUG
extension SupabaseAppDataRepository {
    // Literal server fixtures, independent of all current Encodable implementations.
    static func runBackendDecodeContractChecks() async {
        do {
            // Regression: 845e31c added parallel feed-position date decoding. Exercise
            // parsing and writing together, using fixed timestamps rather than this helper
            // to compute the expected results. No network or user storage is involved.
            await Task.detached {
                let whole = Date(timeIntervalSince1970: 1_791_936_000)
                let fraction = whole.addingTimeInterval(0.125)
                let timestamps = ["2026-10-14T00:00:00Z",
                    "2026-10-14T00:00:00.125Z", "2026-10-14T00:00:00.125000+00:00"]
                let positions = timestamps.map { time in
                    Data("{\"id\":\"11111111-1111-1111-1111-111111111111\",\"created_at\":\"\(time)\"}".utf8)
                }
                DispatchQueue.concurrentPerform(iterations: 10_000) { iteration in
                    let index = iteration % timestamps.count
                    assert(SupabaseDate.parseIfValid(timestamps[index]) == (index == 0 ? whole : fraction))
                    assert(SupabaseDate.parseIfValid("invalid-date") == nil)
                    assert(SupabaseDate.string(whole) == "2026-10-14T00:00:00.000Z")
                    assert(SupabaseDate.string(fraction) == "2026-10-14T00:00:00.125Z")
                    let position = try? JSONDecoder().decode(BackendFeedPosition.self, from: positions[index])
                    assert(position?.time == timestamps[index], "Concurrent feed position must remain readable")
                }
            }.value
            let post = #"{"id":"11111111-1111-1111-1111-111111111111","owner_id":"22222222-2222-2222-2222-222222222222","body":"hello","language_code":"en","visibility":"public","created_at":"2026-10-14T00:00:00.123456+00:00","updated_at":"2026-10-14T00:00:00Z","response_count":3,"comment_count":2}"#
            let profile = #"{"user_id":"22222222-2222-2222-2222-222222222222","nickname":"name","signature":"signature","avatar_url":"https://example.invalid/avatar","avatar_path":"owner/avatar.jpg","language_code":"en","visibility":"public","match_moments_public":true,"display_identity":"public","created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:00:00Z"}"#
            let media = #"{"id":"11111111-1111-1111-1111-111111111111","post_id":"33333333-3333-3333-3333-333333333333","owner_id":"22222222-2222-2222-2222-222222222222","storage_path":"owner/image.jpg","media_type":"image","mime_type":"image/jpeg","byte_size":100,"sort_order":1}"#
            let comment = #"{"id":"11111111-1111-1111-1111-111111111111","post_id":"33333333-3333-3333-3333-333333333333","owner_id":"22222222-2222-2222-2222-222222222222","body":"comment","language_code":"en","visibility":"public","created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:00:00Z"}"#
            let gameRequest = #"{"id":"11111111-1111-1111-1111-111111111111","owner_id":"22222222-2222-2222-2222-222222222222","is_anonymous":false,"anonymous_identity":"player_b","title":"title","body":"gameRequest","language_code":"en","visibility":"public","created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:00:00Z","response_count":4}"#
            let matchMoment = #"{"id":"11111111-1111-1111-1111-111111111111","owner_id":"22222222-2222-2222-2222-222222222222","storage_path":"owner/match-moments/image.jpg","sort_order":1,"visibility":"public","language_code":"en","created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:00:00Z"}"#
            let postResponse = #"{"post_id":"33333333-3333-3333-3333-333333333333","user_id":"22222222-2222-2222-2222-222222222222"}"#
            let gameRequestResponse = #"{"game_request_id":"33333333-3333-3333-3333-333333333333","user_id":"22222222-2222-2222-2222-222222222222"}"#
            let block = #"{"blocked_user_id":"22222222-2222-2222-2222-222222222222"}"#
            let announcement = #"{"id":1,"body_zh_hant":"Older notice","body_en":"announcement","body_ja":"Older notice","revision":2,"updated_at":"2026-10-14T00:00:00Z"}"#

            func decode<Row: Decodable>(_ type: Row.Type, _ json: String) throws -> Row {
                try JSONDecoder().decode(type, from: Data(json.utf8))
            }
            func batch<Row: Decodable>(_ type: Row.Type, _ literals: [String]) throws -> BackendBatch<Row> {
                try decode(BackendBatch<Row>.self, "[" + literals.joined(separator: ",") + "]")
            }
            func feedBatch<Row: Decodable>(_ type: Row.Type, _ literals: [String]) throws -> BackendBatch<Row> {
                try decode(BackendFeedBatch<Row>.self, "[" + literals.joined(separator: ",") + "]").batch
            }
            // Mutations apply only to literal JSON dictionaries; never use the model encoder.
            func changing(_ json: String, _ key: String, to value: Any?) throws -> String {
                var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
                object[key] = value
                return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            }
            func fieldChecks<Row: Decodable>(_ type: Row.Type, _ json: String,
                required: [String], optional: [String]) throws {
                let current = try batch(type, [json])
                assert(current.rows.count == 1 && current.rawCount == 1, "Current format: \(type)")
                let extra = try batch(type, [changing(json, "future_field", to: ["version": 9])])
                assert(extra.rows.count == 1, "Unknown key: \(type)")
                var minimal = json
                for key in optional {
                    for value in [nil, NSNull(), ["unexpected": true]] as [Any?] {
                        let row = try batch(type, [changing(json, key, to: value)])
                        assert(row.rows.count == 1, "Optional \(type).\(key)")
                    }
                    minimal = try changing(minimal, key, to: nil)
                }
                let minimalRow = try batch(type, [minimal])
                assert(minimalRow.rows.count == 1, "All optional fields absent: \(type)")
                for key in required {
                    for value in [nil, NSNull(), ["unexpected": true]] as [Any?] {
                        let mixed = try batch(type, [json, changing(json, key, to: value), json])
                        assert(mixed.rows.count == 2 && mixed.rawCount == 3 && mixed.discardedCount == 1,
                            "Required \(type).\(key) must isolate the bad row")
                    }
                }
                let bad = try batch(type, ["null", "17", "[]", "{}"])
                assert(bad.rows.isEmpty && bad.rawCount == 4 && bad.discardedCount == 4)
                let empty = try batch(type, [])
                assert(empty.rows.isEmpty && empty.rawCount == 0 && empty.discardedCount == 0)
            }
            let metadata = ["language_code", "visibility", "created_at", "updated_at"]
            try fieldChecks(PostRow.self, post, required: ["id", "owner_id", "body"],
                optional: metadata + ["response_count", "comment_count"])
            try fieldChecks(ProfileRow.self, profile, required: ["user_id"],
                optional: metadata + ["nickname", "signature", "avatar_url", "avatar_path", "match_moments_public", "display_identity"])
            try fieldChecks(PostMediaRow.self, media, required: ["id", "post_id", "owner_id", "storage_path"],
                optional: ["media_type", "mime_type", "byte_size", "sort_order"])
            try fieldChecks(CommentRow.self, comment, required: ["id", "post_id", "owner_id", "body"], optional: metadata)
            try fieldChecks(GameRequestRow.self, gameRequest, required: ["id", "owner_id", "is_anonymous", "title", "body"],
                optional: metadata + ["anonymous_identity", "response_count"])
            try fieldChecks(MatchMomentReadRow.self, matchMoment, required: ["id", "owner_id", "storage_path"], optional: metadata + ["sort_order"])
            try fieldChecks(PostResponseRow.self, postResponse, required: ["post_id", "user_id"], optional: [])
            try fieldChecks(GameRequestResponseRow.self, gameRequestResponse, required: ["game_request_id", "user_id"], optional: [])
            try fieldChecks(BlockRow.self, block, required: ["blocked_user_id"], optional: [])
            try fieldChecks(ClubAnnouncementRow.self, announcement,
                required: ["id", "body_zh_hant", "body_en", "body_ja", "revision"], optional: ["updated_at"])
            // Literal JSON content, independent of the publishing encoder and its current limits.
            let longAnnouncement = #"{"id":1,"body_zh_hant":""# + String(repeating: "a", count: 8_001)
                + #"","body_en":"announcement","body_ja":"Older notice","revision":3}"#
            let longRead = try batch(ClubAnnouncementRow.self, [longAnnouncement])
            assert(longRead.rows.count == 1 && longRead.discardedCount == 0)
            assert(longRead.rows.first?.value.bodyZH.unicodeScalars.count == 8_001)
            let partialRead = try batch(ClubAnnouncementRow.self,
                [#"{"id":1,"body_zh_hant":"Older notice","body_en":"","body_ja":"","revision":3}"#])
            assert(partialRead.rows.count == 1 && partialRead.discardedCount == 0)

            let currentPost = try decode(PostRow.self, post).model(media: PostMediaCollection())
            assert(currentPost.text == "hello" && currentPost.languageCode == .english && currentPost.responseCount == 3)
            for value in [nil, NSNull(), "future", 17, ["new": true]] as [Any?] {
                let p = try decode(PostRow.self, changing(post, "visibility", to: value)).model(media: PostMediaCollection())
                let c = try decode(CommentRow.self, changing(comment, "visibility", to: value)).model
                let r = try decode(GameRequestRow.self, changing(gameRequest, "visibility", to: value)).model
                let f = try decode(MatchMomentReadRow.self, changing(matchMoment, "visibility", to: value)).value.model(data: Data())
                let u = try decode(ProfileRow.self, changing(profile, "visibility", to: value)).model(avatarRemoteURL: nil)
                assert([p.visibility, c.visibility, r.visibility, f.visibility, u.visibility].allSatisfy { $0 == .privateContent })
                let identity = try decode(ProfileRow.self, changing(profile, "display_identity", to: value)).model(avatarRemoteURL: nil)
                let publicMatchMoments = try decode(ProfileRow.self, changing(profile, "match_moments_public", to: value))
                assert(identity.displayIdentity == .anonymous && !identity.showsPublicAvatar && !publicMatchMoments.match_moments_public)
                let anonymity = try batch(GameRequestRow.self, [changing(gameRequest, "is_anonymous", to: value)])
                assert(anonymity.rows.isEmpty, "Unknown anonymity must not disclose an owner")
                let access = try decode(BackendAccess.self, value.map { item in
                    String(decoding: try JSONSerialization.data(withJSONObject: item, options: .fragmentsAllowed), as: UTF8.self)
                } ?? "null")
                assert(!access.isAllowed)
            }
            let allowedAccess = try decode(BackendAccess.self, "true")
            let deniedAccess = try decode(BackendAccess.self, "false")
            assert(allowedAccess.isAllowed && !deniedAccess.isAllowed)
            let anonymous = try decode(GameRequestRow.self, #"{"id":"11111111-1111-1111-1111-111111111111","is_anonymous":true,"anonymous_identity":"future","title":"title","body":"body","visibility":"public"}"#)
            assert(anonymous.owner_id == nil && anonymous.model.isAnonymous && anonymous.model.anonymousIdentity == .playerA)
            let futureMedia = try decode(PostMediaRow.self, changing(media, "media_type", to: "future"))
            assert(futureMedia.media_type != "gif")
            for json in [post, profile, comment, gameRequest, matchMoment] {
                let unknown = try changing(json, "language_code", to: "future-language")
                let language: AppLanguage
                if json == post { language = try decode(PostRow.self, unknown).model(media: PostMediaCollection()).languageCode }
                else if json == profile { language = try decode(ProfileRow.self, unknown).model(avatarRemoteURL: nil).languageCode }
                else if json == comment { language = try decode(CommentRow.self, unknown).model.languageCode }
                else if json == gameRequest { language = try decode(GameRequestRow.self, unknown).model.languageCode }
                else { language = try decode(MatchMomentReadRow.self, unknown).value.model(data: Data()).languageCode }
                assert(language == .english)
            }
            let counts = try decode(BackendCounts.self, #"{"posts":3,"game_requests":4,"responses":5,"future":true}"#)
            assert([counts.posts, counts.gameRequests, counts.responses] == [3, 4, 5])
            for key in ["posts", "game_requests", "responses"] {
                for value in [nil, NSNull(), "bad", -1] as [Any?] {
                    let result = try decode(BackendCounts.self, changing(#"{"posts":0,"game_requests":0,"responses":0}"#, key, to: value))
                    assert([result.posts, result.gameRequests, result.responses] == [0, 0, 0])
                }
            }
            for json in ["{}", "null", "17", "[]"] {
                let result = try decode(BackendCounts.self, json)
                assert([result.posts, result.gameRequests, result.responses] == [0, 0, 0])
            }
            let defaults = try decode(PostRow.self, #"{"id":"11111111-1111-1111-1111-111111111111","owner_id":"22222222-2222-2222-2222-222222222222","body":"hello"}"#)
            assert(defaults.response_count == 0 && defaults.comment_count == 0 && defaults.created_at == BackendDecoding.epoch)
            let privatePost = defaults.model(media: PostMediaCollection())
            let visitorID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
            assert(!OwnershipPolicy.canRead(visibility: privatePost.visibility, ownerID: privatePost.ownerID, viewerID: visitorID))
            assert(OwnershipPolicy.canRead(visibility: privatePost.visibility, ownerID: privatePost.ownerID, viewerID: privatePost.ownerID))
            let invalidUUID = try batch(PostRow.self, [post, changing(post, "id", to: "invalid-uuid"), post])
            assert(invalidUUID.rawCount == 3 && invalidUUID.rows.count == 2 && invalidUUID.discardedCount == 1)
            let emptyPath = try batch(MatchMomentReadRow.self, [changing(matchMoment, "storage_path", to: "")])
            assert(emptyPath.rows.isEmpty && emptyPath.discardedCount == 1)
            // Pending archives keep required fields and normalize optional language metadata on retry.
            assert((try? decode(MatchMomentRow.self, changing(matchMoment, "sort_order", to: nil))) == nil)
            for code in [nil, NSNull(), "future-language"] as [Any?] {
                let queued = try decode(MatchMomentRow.self, changing(matchMoment, "language_code", to: code))
                let encoded = try JSONEncoder().encode(queued)
                let payload = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                assert(queued.storage_path == "owner/match-moments/image.jpg" && queued.sort_order == 1)
                assert(payload?["language_code"] as? String == "en")
            }

            // Exercise the EXACT production pagination loop, including a full all-bad page.
            for first in [Array(repeating: post, count: 99) + ["{}"], Array(repeating: "{}", count: 100)] {
                var offsets: [Int] = []
                let rows: [PostRow] = try await BackendDecoding.allRows { offset in
                    offsets.append(offset)
                    assert(offsets.count <= 2, "Pagination did not advance")
                    return try batch(PostRow.self, offset == 0 ? first : [post])
                }
                assert(offsets == [0, 100] && rows.count == (first[0] == post ? 100 : 1))
            }
            let nonFeedBatch = try batch(PostRow.self, [post])
            assert(nonFeedBatch.lastPosition == nil, "Normal row batches must not decode feed positions")
            let emptyFeed = try feedBatch(PostRow.self, [])
            assert(emptyFeed.lastPosition == nil)
            let rawPosition = try feedBatch(PostRow.self, [post])
            assert(rawPosition.lastPosition?.time == "2026-10-14T00:00:00.123456+00:00")
            let badContent = try changing(post, "body", to: nil)
            let mixed = FeedPage(batch: try feedBatch(PostRow.self, Array(repeating: post, count: 39) + [badContent]), after: nil)
            assert(mixed.hasMore && mixed.rows.count == 39 && mixed.nextCursor.offset == 0 && mixed.nextCursor.position != nil)
            for key in ["id", "created_at"] {
                let brokenTail = try changing(post, key, to: nil)
                let page = FeedPage(batch: try feedBatch(PostRow.self, Array(repeating: post, count: 39) + [brokenTail]), after: nil)
                assert(page.hasMore && page.nextCursor.offset == 40 && page.nextCursor.position == nil)
                let next = FeedPage(batch: try feedBatch(PostRow.self, Array(repeating: "{}", count: 40)), after: page.nextCursor)
                assert(next.hasMore && next.nextCursor.offset == 80)
            }
            let invalidTime = FeedPage(batch: try feedBatch(PostRow.self,
                Array(repeating: post, count: 39) + [changing(post, "created_at", to: "future-timestamp")]), after: nil)
            assert(invalidTime.hasMore && invalidTime.nextCursor.offset == 40 && invalidTime.nextCursor.position == nil)
            let anchor = FeedCursor(position: rawPosition.lastPosition, offset: 0)
            let anchored = FeedPage(batch: try feedBatch(PostRow.self, Array(repeating: "{}", count: 40)), after: anchor)
            assert(anchored.nextCursor.position?.filter == anchor.filter && anchored.nextCursor.offset == 40)
            var feedOffsets: [Int] = []
            let readable: FeedPage<PostRow> = try await readableFeedPage(after: nil) { cursor in
                let offset = cursor?.offset ?? 0
                feedOffsets.append(offset)
                assert(feedOffsets.count <= 2)
                return try feedBatch(PostRow.self, offset == 0 ? Array(repeating: "{}", count: 40) : [post])
            }
            assert(feedOffsets == [0, 40] && readable.rows.count == 1 && !readable.hasMore)
            // The production scan must stop at the cap even if every subsequent page is full
            // and unreadable. Verify raw offsets and preservation of an existing anchor.
            for initial in [nil, anchor] as [FeedCursor?] {
                var requests: [Int] = []
                let capped: FeedPage<PostRow> = try await readableFeedPage(after: initial) { cursor in
                    requests.append(cursor?.offset ?? 0)
                    assert(requests.count <= maximumConsecutiveUnreadableFeedPages,
                        "Unreadable feed exceeded its request cap")
                    return try feedBatch(PostRow.self, Array(repeating: "{}", count: 40))
                }
                assert(requests == [0, 40, 80] && requests.count == maximumConsecutiveUnreadableFeedPages)
                assert(capped.rows.isEmpty && !capped.hasMore && capped.nextCursor.offset == 120)
                assert(capped.nextCursor.filter == initial?.filter)
            }
            // A discarded content body can still supply valid ordering keys. The cap must
            // preserve the last scanned raw position, not the starting cursor.
            let times = ["2026-10-14T00:00:00Z", "2026-10-13T00:00:00Z", "2026-10-12T00:00:00Z"]
            var keyedRequests = 0
            let keyedCap: FeedPage<PostRow> = try await readableFeedPage(after: nil) { cursor in
                keyedRequests += 1
                assert(keyedRequests <= maximumConsecutiveUnreadableFeedPages)
                assert((cursor?.offset ?? 0) == 0)
                if keyedRequests > 1 { assert(cursor?.position?.time == times[keyedRequests - 2]) }
                let bad = try changing(badContent, "created_at", to: times[keyedRequests - 1])
                return try feedBatch(PostRow.self, Array(repeating: bad, count: 40))
            }
            assert(keyedRequests == 3 && keyedCap.rows.isEmpty && !keyedCap.hasMore)
            assert(keyedCap.nextCursor.position?.time == times.last && keyedCap.nextCursor.offset == 0)
            var recoveryRequests = 0
            let recovered: FeedPage<PostRow> = try await readableFeedPage(after: nil) { _ in
                recoveryRequests += 1
                assert(recoveryRequests <= maximumConsecutiveUnreadableFeedPages)
                return try feedBatch(PostRow.self, Array(repeating: recoveryRequests == 3 ? post : "{}", count: 40))
            }
            assert(recoveryRequests == 3 && recovered.rows.count == 40 && recovered.hasMore)
            print("BACKEND-DECODE-001 passed: literal fixtures, field grades, unknown enums, fail-closed privacy, mixed/all-bad batches, raw-count pagination, bounded feed scans, long/partial announcements, feed-only final cursor, 10000 concurrent date parse/write/feed-position checks")
        } catch {
            preconditionFailure("BACKEND-DECODE-001 unexpected contract error: \(error)")
        }
    }
}
#endif
