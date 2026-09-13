import Foundation
import SwiftData

@Model
final class ActivitySegment {
    var startTime: Date
    var durationSeconds: Int

    var session: StudySession?
    var activity: Activity?

    init(startTime: Date, durationSeconds: Int) {
        self.startTime = startTime
        self.durationSeconds = durationSeconds
    }
}
