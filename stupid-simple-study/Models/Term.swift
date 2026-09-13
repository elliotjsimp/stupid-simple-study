import Foundation
import SwiftData

@Model
final class Term {
    var name: String
    var firstDay: Date
    var lastDay: Date
    var trackingStartDate: Date
    var lastLectureDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \Course.term)
    var courses: [Course]

    @Relationship(deleteRule: .cascade, inverse: \StudySession.term)
    var sessions: [StudySession]

    init(
        name: String,
        firstDay: Date,
        lastDay: Date,
        trackingStartDate: Date? = nil,
        lastLectureDate: Date? = nil
    ) {
        self.name = name
        self.firstDay = Calendar.current.startOfDay(for: firstDay)
        self.lastDay = Calendar.current.startOfDay(for: lastDay)
        self.trackingStartDate = Calendar.current.startOfDay(for: trackingStartDate ?? firstDay)
        self.lastLectureDate = lastLectureDate.map { Calendar.current.startOfDay(for: $0) }
        self.courses = []
        self.sessions = []
    }

    func contains(date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        return day >= firstDay && day <= lastDay
    }

    func overlaps(with other: Term) -> Bool {
        firstDay <= other.lastDay && lastDay >= other.firstDay
    }
}
