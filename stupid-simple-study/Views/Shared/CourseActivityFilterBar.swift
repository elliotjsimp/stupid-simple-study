import SwiftUI
import SwiftData

struct FilterPickerMenu<ID: Hashable>: View {
    let defaultTitle: String
    let items: [(ID, String)]
    @Binding var selection: ID?

    private var menuTitle: String {
        guard let selection,
              let name = items.first(where: { $0.0 == selection })?.1
        else { return defaultTitle }
        return name
    }

    var body: some View {
        Menu {
            ForEach(items, id: \.0) { id, name in
                Button {
                    selection = id
                } label: {
                    if selection == id {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            Text(menuTitle)
        }
        .menuStyle(.button)
        .fixedSize()
    }
}

struct CourseActivityFilterBar: View {
    @Environment(TermContext.self) private var termContext

    @Query(sort: \Activity.name) private var allActivities: [Activity]

    @Binding var selectedCourseID: PersistentIdentifier?
    @Binding var selectedActivityID: PersistentIdentifier?
    var showsActivityFilter: Bool = true

    private var termCourses: [Course] {
        guard let term = termContext.displayedTerm else { return [] }
        return term.courses.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var hasSelection: Bool {
        selectedCourseID != nil || (showsActivityFilter && selectedActivityID != nil)
    }

    var body: some View {
        HStack(spacing: 8) {
            FilterPickerMenu(
                defaultTitle: "Course",
                items: termCourses.map { ($0.persistentModelID, $0.name) },
                selection: $selectedCourseID
            )
            if showsActivityFilter {
                FilterPickerMenu(
                    defaultTitle: "Activity",
                    items: allActivities.map { ($0.persistentModelID, $0.name) },
                    selection: $selectedActivityID
                )
            }
            if hasSelection {
                Button("Clear") {
                    selectedCourseID = nil
                    if showsActivityFilter {
                        selectedActivityID = nil
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

enum SessionFilter {
    static func matches(
        _ session: StudySession,
        termID: PersistentIdentifier?,
        courseID: PersistentIdentifier?,
        activityID: PersistentIdentifier?
    ) -> Bool {
        guard let termID, session.term?.persistentModelID == termID else { return false }
        if let courseID, session.course?.persistentModelID != courseID { return false }
        if let activityID {
            let activityIDs = Set(session.sortedSegments.compactMap { $0.activity?.persistentModelID })
            if !activityIDs.contains(activityID) { return false }
        }
        return true
    }
}
