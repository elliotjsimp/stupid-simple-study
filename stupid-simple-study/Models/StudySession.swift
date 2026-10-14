import Foundation
import SwiftData

@Model
final class StudySession {
    var startTime: Date
    var endTime: Date
    var studyTimeSeconds: Int
    var note: String
    var focusRating: Int?

    var term: Term?
    var course: Course?

    @Relationship(deleteRule: .cascade, inverse: \ActivitySegment.session)
    var activitySegments: [ActivitySegment]

    init(
        startTime: Date,
        endTime: Date,
        studyTimeSeconds: Int,
        note: String = "",
        focusRating: Int? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.studyTimeSeconds = studyTimeSeconds
        self.note = note
        self.focusRating = focusRating
        self.activitySegments = []
    }

    var sortedSegments: [ActivitySegment] {
        activitySegments.sorted { $0.startTime < $1.startTime }
    }

    var activityNames: String {
        var names: [String] = []
        for segment in sortedSegments {
            guard let name = segment.activity?.name else { continue }
            if names.last?.caseInsensitiveCompare(name) != .orderedSame {
                names.append(name)
            }
        }
        return names.joined(separator: ", ")
    }
}
