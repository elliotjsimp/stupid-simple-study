import Foundation
import SwiftData

@Model
final class Activity {
    var name: String

    @Relationship(deleteRule: .nullify, inverse: \ActivitySegment.activity)
    var segments: [ActivitySegment]

    init(name: String) {
        self.name = name
        self.segments = []
    }
}
