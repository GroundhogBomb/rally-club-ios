import Foundation

struct PostComment: Identifiable, Hashable {
    let id: UUID
    let postID: UUID
    let ownerID: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date
    var visibility: ContentVisibility
    var languageCode: AppLanguage
}
