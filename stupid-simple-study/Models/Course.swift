import Foundation
import SwiftData

@Model
final class Course {
    var name: String
    var colorHex: String
    var isArchived: Bool
    var sortOrder: Int

    var term: Term?

    @Relationship(deleteRule: .nullify, inverse: \StudySession.course)
    var sessions: [StudySession]

    init(name: String, colorHex: String, sortOrder: Int = 0, isArchived: Bool = false) {
        self.name = name
        self.colorHex = colorHex
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.sessions = []
    }
}
