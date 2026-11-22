import Foundation

enum AnonymousGameRequestIdentity: String, Hashable {
    case playerA = "player_a"
    case playerB = "player_b"

    func nickname(for language: AppLanguage) -> String {

        switch self {
        case .playerA:
            return String(localized: "Anonymous player A")
        case .playerB:
            return String(localized: "Anonymous player B")
        }
    }
}

enum GameRequestIdentity: Hashable {
    case publicUser(CommunityUser)
    case anonymous(AnonymousGameRequestIdentity)

    var publicUser: CommunityUser? {
        guard case let .publicUser(user) = self else { return nil }
        return user
    }

    var isAnonymous: Bool {
        if case .anonymous = self { return true }
        return false
    }

    func nickname(for language: AppLanguage) -> String {
        switch self {
        case let .publicUser(user): return user.nickname
        case let .anonymous(identity): return identity.nickname(for: language)
        }
    }

    var avatar: String {
        switch self {
        case let .publicUser(user): user.avatar
        case .anonymous: "RallyAvatar"
        }
    }
}

struct GameRequest: Identifiable, Hashable {
    let id: UUID
    let ownerID: UUID
    var isAnonymous: Bool
    var anonymousIdentity: AnonymousGameRequestIdentity
    var title: String
    var body: String
    let createdAt: Date
    var updatedAt: Date
    var visibility: ContentVisibility
    var languageCode: AppLanguage
    var responseCount: Int

    func timeLabel(interfaceLanguage: AppLanguage, relativeTo now: Date = Date()) -> String {
        if abs(now.timeIntervalSince(createdAt)) < 60 {
            return String(localized: "Just now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: createdAt, relativeTo: now)
    }
}

enum GameRequestPublishIdentity: String, CaseIterable, Identifiable {
    case publicIdentity
    case anonymous

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {

        switch self {
        case .publicIdentity: return String(localized: "Post publicly")
        case .anonymous: return String(localized: "Post anonymously")
        }
    }
}
