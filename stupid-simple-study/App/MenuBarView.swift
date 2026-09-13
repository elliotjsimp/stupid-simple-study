import SwiftData
import SwiftUI

struct MenuBarView: View {
    @Environment(SessionEngine.self) private var sessionEngine
    @Environment(TermContext.self) private var termContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = sessionEngine.tickCount

        VStack(alignment: .leading, spacing: 12) {
            if sessionEngine.isActive {
                activeSessionItems
            } else if termContext.canStartLiveSession {
                MenuBarStartSessionMenu()
            } else {
                Text("Switch to the active term to start")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Open Stupid Simple Study") {
                AppRelauncher.activateMainApp()
                dismiss()
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder
    private var activeSessionItems: some View {
        Text(DurationFormatters.clock(seconds: sessionEngine.displayStudySeconds))
            .font(.title2.monospacedDigit().weight(.semibold))

        if let course = sessionEngine.course {
            Text(course.name)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
            if sessionEngine.state == .studying {
                Button("Pause") { sessionEngine.pause() }
            } else if sessionEngine.state == .paused {
                Button("Resume") { sessionEngine.resume() }
            }

            Button("End Session…") {
                sessionEngine.requestEndSheetPresentation()
                AppRelauncher.activateMainApp()
                dismiss()
            }
        }
    }
}

private struct MenuBarStartSessionMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TermContext.self) private var termContext
    @Environment(SessionEngine.self) private var sessionEngine

    @Query(sort: \Activity.name) private var activities: [Activity]

    @State private var selectedCourseID: PersistentIdentifier?
    @State private var activitySelection: ActivitySelection = .none
    @State private var showNewCourseAlert = false
    @State private var newCourseName = ""

    private enum ActivitySelection: Hashable {
        case none
        case named(String)
    }

    private var courses: [Course] {
        guard let term = termContext.displayedTerm else { return [] }
        return term.courses.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedCourse: Course? {
        guard let selectedCourseID else { return nil }
        return courses.first { $0.persistentModelID == selectedCourseID }
    }

    private var courseMenuTitle: String {
        selectedCourse?.name ?? "Select course"
    }

    private var activityMenuTitle: String {
        switch activitySelection {
        case .none: "Select activity"
        case .named(let name): name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start Session")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Course").font(.caption).foregroundStyle(.secondary)
                Menu {
                    ForEach(courses, id: \.persistentModelID) { course in
                        Button {
                            selectedCourseID = course.persistentModelID
                        } label: {
                            if selectedCourseID == course.persistentModelID {
                                Label(course.name, systemImage: "checkmark")
                            } else {
                                Text(course.name)
                            }
                        }
                    }
                    Divider()
                    Button("New Course…") { showNewCourseAlert = true }
                } label: {
                    pickerLabel(courseMenuTitle, placeholder: selectedCourse == nil)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Activity").font(.caption).foregroundStyle(.secondary)
                Menu {
                    if activitySelection != .none {
                        Button("None") { activitySelection = .none }
                    }
                    ForEach(activities, id: \.persistentModelID) { activity in
                        Button {
                            activitySelection = .named(activity.name)
                        } label: {
                            if activitySelection == .named(activity.name) {
                                Label(activity.name, systemImage: "checkmark")
                            } else {
                                Text(activity.name)
                            }
                        }
                    }
                } label: {
                    pickerLabel(activityMenuTitle, placeholder: activitySelection == .none)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            HStack {
                Spacer()
                Button("Start") { startSession() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCourse == nil)
            }
        }
        .onAppear {
            if selectedCourseID == nil, let only = courses.only {
                selectedCourseID = only.persistentModelID
            }
        }
        .alert("New Course", isPresented: $showNewCourseAlert) {
            TextField("Course name", text: $newCourseName)
            Button("Create") { createCourse() }
            Button("Cancel", role: .cancel) { newCourseName = "" }
        } message: {
            Text("Add a course to the active term.")
        }
    }

    private func pickerLabel(_ title: String, placeholder: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(placeholder ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func createCourse() {
        guard let term = termContext.displayedTerm else { return }
        let name = newCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if termContext.courseNameExistsInHistory(name, in: modelContext) &&
            !term.courses.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return
        }
        let used = Set(term.courses.map { $0.colorHex.uppercased() })
        let course = Course(
            name: name,
            colorHex: CourseColorPalette.nextColor(usedHexes: used),
            sortOrder: term.courses.count
        )
        course.term = term
        modelContext.insert(course)
        selectedCourseID = course.persistentModelID
        newCourseName = ""
    }

    private func startSession() {
        guard let term = termContext.activeTerm, let course = selectedCourse else { return }

        let activityName: String?
        switch activitySelection {
        case .none:
            activityName = nil
        case .named(let name):
            activityName = name
            if !activities.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                modelContext.insert(Activity(name: name))
            }
        }

        sessionEngine.start(
            term: term,
            course: course,
            activityName: activityName
        )
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}

struct MenuBarLabel: View {
    @Environment(SessionEngine.self) private var sessionEngine
    @Environment(\.appSettings) private var settings

    var body: some View {
        let _ = sessionEngine.tickCount
        return HStack(spacing: 4) {
            Image("MenuBarIcon")
            if settings.showMenuBarTimer && sessionEngine.isActive {
                Text(DurationFormatters.clock(seconds: sessionEngine.displayStudySeconds))
                    .monospacedDigit()
            }
        }
    }
}
