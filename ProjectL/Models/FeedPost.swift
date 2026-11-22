import Foundation

enum CommunityMediaStorage {
    static let bucket = "community-media"
    static let maximumItemCount = 4
    static let maximumFileSize = 8 * 1_024 * 1_024
    static let signedURLLifetime = 3_600

    static func path(
        ownerID: UUID,
        postID: UUID,
        mediaID: UUID,
        fileExtension: String
    ) -> String {
        "\(ownerID.uuidString.lowercased())/posts/\(postID.uuidString.lowercased())/\(mediaID.uuidString.lowercased()).\(fileExtension)"
    }
}

struct PostMedia: Identifiable, Hashable {
    let id: UUID
    let data: Data?
    let assetName: String?
    let remoteURL: URL?
    let storagePath: String?
    let mimeType: String

    init(
        id: UUID = UUID(),
        data: Data,
        mimeType: String = "image/gif"
    ) {
        self.id = id
        self.data = data
        self.assetName = nil
        self.remoteURL = nil
        self.storagePath = nil
        self.mimeType = mimeType
    }

    init(id: UUID = UUID(), assetName: String) {
        self.id = id
        self.data = nil
        self.assetName = assetName
        self.remoteURL = nil
        self.storagePath = nil
        self.mimeType = "image/png"
    }

    init(
        id: UUID,
        remoteURL: URL,
        storagePath: String,
        mimeType: String
    ) {
        self.id = id
        self.data = nil
        self.assetName = nil
        self.remoteURL = remoteURL
        self.storagePath = storagePath
        self.mimeType = mimeType
    }
}

struct FeedPost: Identifiable, Hashable {
    let id: UUID
    let ownerID: UUID
    var text: String
    var images: [PostMedia]
    var gif: PostMedia?
    var languageCode: AppLanguage
    let createdAt: Date
    var updatedAt: Date
    var visibility: ContentVisibility
    var responseCount: Int

    func timeLabel(interfaceLanguage: AppLanguage) -> String {
        FeedTimestamp.label(for: createdAt, language: interfaceLanguage)
    }
}

enum FeedTimestamp {
    static func label(for date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
