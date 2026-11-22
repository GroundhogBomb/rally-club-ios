import Foundation

// PROFILE-001
// Public member profile and its fallback.
enum ProfileAvatarStorage {
    static let bucket = "profile-avatars"
    static let maximumFileSize = 5 * 1_024 * 1_024
    static let signedURLLifetime = 3_600

    static func path(ownerID: UUID, avatarID: UUID) -> String {
        "\(ownerID.uuidString.lowercased())/avatars/\(avatarID.uuidString.lowercased()).jpg"
    }
}

enum ContentVisibility: String, Hashable {
    case publicContent
    case privateContent
}

struct CommunityProfile: Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    var nickname: String
    var avatar: String
    var avatarData: Data?
    var avatarRemoteURL: URL?
    var avatarStoragePath: String?
    var signature: String
    var languageCode: AppLanguage
    var visibility: ContentVisibility
    var areMatchMomentsPublic: Bool
    var displayIdentity: ProfileDisplayIdentity
    let createdAt: Date
    var updatedAt: Date
}

extension CommunityProfile {
    var showsPublicAvatar: Bool {
        visibility == .publicContent && displayIdentity == .publicIdentity
    }

    var publicAvatarData: Data? { showsPublicAvatar ? avatarData : nil }
    var publicAvatarURL: URL? { showsPublicAvatar ? avatarRemoteURL : nil }
    var publicAvatarFallback: String { showsPublicAvatar ? avatar : "RallyAvatar" }
}

struct UserAccount: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
}

struct CommunityUser: Identifiable, Hashable {
    let account: UserAccount
    var profile: CommunityProfile

    var id: UUID { account.id }
    var createdAt: Date { account.createdAt }
    var updatedAt: Date { account.updatedAt }

    var nickname: String { profile.nickname }
    var displayName: String { profile.nickname }
    var avatar: String { profile.avatar }
    var signature: String { profile.signature }
    var language: AppLanguage { profile.languageCode }

    init(
        id: UUID,
        profileID: UUID,
        nickname: String,
        avatar: String,
        signature: String,
        language: AppLanguage,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) {
        self.account = UserAccount(id: id, createdAt: createdAt, updatedAt: updatedAt)
        self.profile = CommunityProfile(
            id: profileID,
            userID: id,
            nickname: nickname,
            avatar: avatar,
            avatarData: nil,
            avatarRemoteURL: nil,
            avatarStoragePath: nil,
            signature: signature,
            languageCode: language,
            visibility: .publicContent,
            areMatchMomentsPublic: true,
            displayIdentity: .publicIdentity,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    init(account: UserAccount, profile: CommunityProfile) {
        self.account = account
        self.profile = profile
    }

    static func placeholder(id: UUID, language: AppLanguage) -> CommunityUser {

        let now = Date()
        return CommunityUser(
            id: id,
            profileID: id,
            nickname: String(localized: "Club member"),
            avatar: "RallyAvatar",
            signature: "",
            language: language,
            createdAt: now,
            updatedAt: now
        )
    }
}

enum CommunityDirectory {
    static let demoMember = CommunityUser(
        id: UUID(uuid: (0xbf, 0x47, 0x65, 0xe1, 0x9e, 0x8d, 0x51, 0xc3, 0x94, 0xfb, 0xba, 0x9d, 0x86, 0x32, 0x16, 0x7c)),
        profileID: UUID(uuid: (0xdb, 0xc8, 0x53, 0xff, 0xb8, 0x1b, 0x5b, 0x95, 0xba, 0x81, 0x78, 0x5e, 0xf8, 0xd5, 0x09, 0x6c)),
        nickname: "Mina Park",
        avatar: "RallyAvatar",
        signature: "Working on a steadier backhand.",
        language: .english
    )

    static let riley = CommunityUser(
        id: UUID(uuid: (0x52, 0x11, 0xf1, 0x4f, 0x72, 0x46, 0x50, 0x13, 0x8d, 0xc6, 0x15, 0x2f, 0x88, 0xfb, 0x7d, 0x27)),
        profileID: UUID(uuid: (0x0d, 0x9c, 0xe3, 0xd8, 0x79, 0xda, 0x54, 0x8b, 0xa5, 0x1a, 0xa3, 0x50, 0xc0, 0x89, 0xa7, 0x2f)),
        nickname: "Riley Moss",
        avatar: "RallyAvatar",
        signature: "Saturday doubles regular.",
        language: .english
    )

    static let aki = CommunityUser(
        id: UUID(uuid: (0x25, 0xb1, 0x40, 0xb8, 0xb1, 0xba, 0x55, 0x38, 0xa5, 0xcd, 0xef, 0x99, 0x44, 0x89, 0xa6, 0x5c)),
        profileID: UUID(uuid: (0x73, 0xbf, 0xc6, 0x84, 0x73, 0xb8, 0x5c, 0x7c, 0xa2, 0x80, 0xc6, 0x62, 0x4f, 0x94, 0x1d, 0x40)),
        nickname: "Aki Wren",
        avatar: "RallyAvatar",
        signature: "Here for long rallies and good practice partners.",
        language: .english
    )
}
