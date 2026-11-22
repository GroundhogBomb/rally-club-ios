import Observation
import Foundation
import SwiftUI

// MAINTENANCE-POINT: GAME-REQUEST-001
// Store for arranging games, responding to requests, and anonymous display.
@MainActor
@Observable
final class GameRequestStore {
    private let dataRepository: any AppDataRepository
    @ObservationIgnored private var repositoryChanges: Task<Void, Never>?

    // Track reads from the repository, which has its own storage.
    private var repository: any AppDataRepository {
        access(keyPath: \.repository)
        return dataRepository
    }

    let currentUserID: UUID
    var isSubmitting: Bool { repository.mutationState == .submitting }

    func report(id: UUID, reason: String) async throws {
        try await repository.reportContent(kind: "game_request", id: id, reason: reason)
    }

    func block(_ userID: UUID) async throws {
        try await repository.setUserBlocked(userID, blocked: true)
    }
    var currentUser: CommunityUser {
        repository.user(id: currentUserID)
            ?? CommunityUser.placeholder(id: currentUserID, language: .english)
    }


    func currentUser(for language: AppLanguage) -> CommunityUser {
        repository.user(id: currentUserID)
            ?? CommunityUser.placeholder(id: currentUserID, language: language)
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

    func requests(now _: Date = Date()) -> [GameRequest] {
        repository.gameRequests(viewerID: currentUserID)
    }

    func myRequests(now: Date = Date()) -> [GameRequest] {
        repository.personalGameRequests(viewerID: currentUserID).filter { $0.ownerID == currentUserID }
    }

    func myResponses(now: Date = Date()) -> [GameRequest] {
        repository.personalGameRequests(viewerID: currentUserID).filter { hasResponded(for: $0.id) }
    }
    var requestCount: Int { repository.profileCounts(viewerID: currentUserID)[1] }
    var responseCount: Int { repository.profileCounts(viewerID: currentUserID)[2] }
    var hasMore: Bool { repository.hasMoreGameRequests }
    func loadMore() async throws { try await repository.loadMoreGameRequests() }
    func loadPersonalRecords() async throws { try await repository.loadPersonalRecords() }

    func hasResponded(for gameRequestID: UUID) -> Bool {
        repository.hasRespondedToGameRequest(gameRequestID: gameRequestID, userID: currentUserID)
    }

    func responseCount(for gameRequest: GameRequest) -> Int {
        repository.gameRequest(id: gameRequest.id, viewerID: currentUserID)?.responseCount ?? gameRequest.responseCount
    }

    func respond(to gameRequestID: UUID) {
        repository.respondToGameRequest(gameRequestID: gameRequestID, userID: currentUserID)
    }

    func displayIdentity(for gameRequest: GameRequest) -> GameRequestIdentity {
        if gameRequest.isAnonymous {
            return .anonymous(gameRequest.anonymousIdentity)
        }
        guard let user = repository.user(id: gameRequest.ownerID) else {
            return .anonymous(.playerA)
        }
        return .publicUser(user)
    }

    func publish(
        title: String,
        body: String,
        identity: GameRequestPublishIdentity
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return }

        let now = Date()
        repository.createGameRequest(
            GameRequest(
                id: UUID(),
                ownerID: currentUserID,
                isAnonymous: identity == .anonymous,
                anonymousIdentity: .playerA,
                title: trimmedTitle,
                body: trimmedBody,
                createdAt: now,
                updatedAt: now,
                visibility: .publicContent,
                languageCode: .english,
                responseCount: 0
            ),
            requesterID: currentUserID
        )
    }

    @discardableResult
    func update(_ gameRequest: GameRequest) -> Bool {
        repository.updateGameRequest(gameRequest, requesterID: currentUserID)
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        repository.deleteGameRequest(id: id, requesterID: currentUserID)
    }
}
