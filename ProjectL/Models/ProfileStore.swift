import Observation
import Foundation
import SwiftUI
import UIKit
import ImageIO

struct MatchMoment: Identifiable, Equatable {
    let id: UUID
    let ownerID: UUID
    let data: Data
    let createdAt: Date
    var updatedAt: Date
    var visibility: ContentVisibility
    var languageCode: AppLanguage

    init(
        id: UUID = UUID(),
        ownerID: UUID,
        data: Data,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        visibility: ContentVisibility = .publicContent,
        languageCode: AppLanguage
    ) {
        self.id = id
        self.ownerID = ownerID
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.visibility = visibility
        self.languageCode = languageCode
    }
}

enum ProfileDisplayIdentity: String, CaseIterable, Identifiable {
    case publicIdentity
    case anonymous

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {

        switch self {
        case .publicIdentity: return String(localized: "Public identity")
        case .anonymous: return String(localized: "Anonymous identity")
        }
    }
}

enum ProfileDataAccess: Equatable {
    case ownerReadWrite
    case visitorReadOnly

    var canEdit: Bool {
        self == .ownerReadWrite
    }
}

// MAINTENANCE-POINT: PROFILE-001
// Store for profiles, avatars, and match moments.
@MainActor
@Observable
final class ProfileStore {
    static let maximumMatchMoments = 9

    private let dataRepository: any AppDataRepository
    @ObservationIgnored private var repositoryChanges: Task<Void, Never>?

    // Track reads from the repository, which has its own storage.
    private var repository: any AppDataRepository {
        access(keyPath: \.repository)
        return dataRepository
    }

    let currentUserID: UUID
    private var currentProfile: CommunityProfile {
        repository.profile(userID: currentUserID, viewerID: currentUserID)
            ?? CommunityUser.placeholder(id: currentUserID, language: .english).profile
    }


    var nickname: String { currentProfile.nickname }
    var signature: String { currentProfile.signature }
    var avatarData: Data? { currentProfile.avatarData }
    var avatarRemoteURL: URL? { currentProfile.avatarRemoteURL }
    var hasCustomAvatar: Bool {
        avatarData != nil || avatarRemoteURL != nil || currentProfile.avatarStoragePath != nil
    }
    var isUpdatingIdentity: Bool {
        guard repository.mutationState == .submitting else { return false }
        return repository.mutationContext == .profileUpdate
            || repository.mutationContext == .avatarUpload
            || repository.mutationContext == .avatarRemove
    }
    var matchMoments: [MatchMoment] {
        repository.matchMoments(ownerID: currentUserID, viewerID: currentUserID)
    }
    var areMatchMomentsPublic: Bool { currentProfile.areMatchMomentsPublic }
    var displayIdentity: ProfileDisplayIdentity { currentProfile.displayIdentity }

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

    var remainingPhotoSlots: Int {
        max(0, Self.maximumMatchMoments - matchMoments.count)
    }

    func access(for userID: UUID) -> ProfileDataAccess {
        repository.canModify(ownerID: userID, requesterID: currentUserID)
            ? .ownerReadWrite
            : .visitorReadOnly
    }

    func profile(for userID: UUID) -> CommunityProfile? {
        repository.profile(userID: userID, viewerID: currentUserID)
    }

    func refreshProfiles(ownerID: UUID? = nil) async {
        try? await repository.refreshProfiles()
        try? await repository.refreshMatchMoments(ownerID: ownerID ?? currentUserID)
    }

    func blockedUsers() async throws -> [UUID] { try await repository.blockedUsers() }
    func unblock(_ id: UUID) async throws { try await repository.setUserBlocked(id, blocked: false) }

    func visibleMatchMoments(for userID: UUID) -> [MatchMoment] {
        Array(
            repository
                .matchMoments(ownerID: userID, viewerID: currentUserID)
                .prefix(Self.maximumMatchMoments)
        )
    }

    func avatarData(for userID: UUID) -> Data? {
        profile(for: userID)?.avatarData
    }

    @discardableResult
    func updateProfile(for userID: UUID, nickname: String, signature: String) -> Bool {
        guard access(for: userID).canEdit else { return false }
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty,
              trimmedNickname.count <= 80,
              trimmedSignature.count <= 240 else { return false }
        return repository.updateProfile(
            userID: userID,
            requesterID: currentUserID,
            nickname: trimmedNickname,
            signature: trimmedSignature,
            avatarData: nil,
            matchMomentsPublic: nil,
            displayIdentity: nil
        )
    }

    @discardableResult
    func updateAvatar(for userID: UUID, with data: Data) -> Bool {
        repository.updateAvatar(userID: userID, requesterID: currentUserID, data: data)
    }

    @discardableResult
    func removeAvatar(for userID: UUID) -> Bool {
        repository.removeAvatar(userID: userID, requesterID: currentUserID)
    }

    static func preparedAvatarJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { return nil }
        let sourceImage = UIImage(cgImage: thumbnail)
        let maximumDimension: CGFloat = 1_600
        let sourceSize = sourceImage.size
        let scale = min(
            1,
            maximumDimension / max(sourceSize.width, sourceSize.height)
        )
        let targetSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalizedImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpeg = normalizedImage.jpegData(compressionQuality: 0.82),
              jpeg.count <= ProfileAvatarStorage.maximumFileSize else { return nil }
        return jpeg
    }

    @discardableResult
    func addMatchMoments(for userID: UUID, _ dataItems: [Data]) -> Bool {
        guard access(for: userID).canEdit else { return false }
        let availableItems = dataItems.prefix(remainingPhotoSlots)
        guard !availableItems.isEmpty else { return false }
        var didCreateAll = true
        for data in availableItems {
            guard let prepared = Self.preparedAvatarJPEG(from: data),
                  prepared.count <= ProfileAvatarStorage.maximumFileSize else {
                didCreateAll = false
                continue
            }
            let photo = MatchMoment(
                ownerID: userID,
                data: prepared,
                languageCode: .english
            )
            didCreateAll = repository.createMatchMoment(photo, requesterID: currentUserID) && didCreateAll
        }
        return didCreateAll
    }

    @discardableResult
    func removeMatchMoment(for userID: UUID, id: UUID) -> Bool {
        guard matchMoments.contains(where: { $0.id == id && $0.ownerID == userID }) else { return false }
        return repository.deleteMatchMoment(id: id, requesterID: currentUserID)
    }

    @discardableResult
    func moveMatchMoment(for userID: UUID, id: UUID, offset: Int) -> Bool {
        repository.moveMatchMoment(
            ownerID: userID,
            id: id,
            offset: offset,
            requesterID: currentUserID
        )
    }

    @discardableResult
    func setMatchMomentsPublic(_ isPublic: Bool, for userID: UUID) -> Bool {
        repository.updateProfile(
            userID: userID,
            requesterID: currentUserID,
            nickname: nil,
            signature: nil,
            avatarData: nil,
            matchMomentsPublic: isPublic,
            displayIdentity: nil
        )
    }

    @discardableResult
    func setDisplayIdentity(_ identity: ProfileDisplayIdentity, for userID: UUID) -> Bool {
        repository.updateProfile(
            userID: userID,
            requesterID: currentUserID,
            nickname: nil,
            signature: nil,
            avatarData: nil,
            matchMomentsPublic: nil,
            displayIdentity: identity
        )
    }

    @discardableResult
    func updateMatchMoment(_ photo: MatchMoment) -> Bool {
        repository.updateMatchMoment(photo, requesterID: currentUserID)
    }
}

// MAINTENANCE-POINT: SUPPORT-001
// Open an email draft for optional feedback.
enum DeveloperContact {
    static let email = "feedback@example.com"
    static let subject = "Rally Club Feedback"

    static func mailURL(for language: AppLanguage) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]
        return components.url
    }
}
