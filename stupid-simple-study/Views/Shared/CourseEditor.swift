import SwiftUI
import SwiftData

@Observable
@MainActor
final class CourseEditorPresenter {
    var isPresented = false
    var mode: CourseEditorSheet.Mode = .create
    var onCreated: ((Course) -> Void)?

    func presentCreate(onCreated: ((Course) -> Void)? = nil) {
        mode = .create
        self.onCreated = onCreated
        isPresented = true
    }

    func presentEdit(_ course: Course) {
        mode = .edit(course)
        onCreated = nil
        isPresented = true
    }
}

struct CourseEditorSheet: View {
    enum Mode {
        case create
        case edit(Course)
    }

    let mode: Mode
    @Binding var isPresented: Bool
    var onCreated: ((Course) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(TermContext.self) private var termContext
    @Environment(SessionEngine.self) private var sessionEngine

    @State private var name = ""
    @State private var colorHex = CourseColorPalette.hexColors[0]
    @State private var error: String?
    @State private var showDeleteConfirm = false

    private var title: String {
        switch mode {
        case .create: "New Course"
        case .edit: "Edit Course"
        }
    }

    private var editingCourse: Course? {
        if case .edit(let course) = mode { return course }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name)
            CourseColorPicker(colorHex: $colorHex)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if editingCourse != nil {
                    Button("Delete Course", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: true, vertical: true)
        .confirmationDialog(
            "Delete this course?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Course", role: .destructive) { deleteCourse() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteWarningMessage)
        }
        .onAppear {
            if let course = editingCourse {
                name = course.name
                colorHex = course.colorHex
            } else if let term = termContext.displayedTerm {
                let used = Set(term.courses.map { $0.colorHex.uppercased() })
                colorHex = CourseColorPalette.nextColor(usedHexes: used)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let course = editingCourse {
            if trimmed.caseInsensitiveCompare(course.name) != .orderedSame {
                if nameConflicts(trimmed, excluding: course) {
                    error = "A course with this name already exists."
                    return
                }
            }
            course.name = trimmed
            course.colorHex = colorHex
            try? modelContext.save()
            isPresented = false
            return
        }

        guard let term = termContext.displayedTerm else { return }
        if termContext.courseNameExistsInHistory(trimmed, in: modelContext) &&
            !term.courses.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            error = "A course with this name existed in a prior term."
            return
        }
        if term.courses.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            error = "A course with this name already exists."
            return
        }

        let course = Course(name: trimmed, colorHex: colorHex, sortOrder: term.courses.count)
        course.term = term
        modelContext.insert(course)
        try? modelContext.save()
        onCreated?(course)
        isPresented = false
    }

    private var deleteWarningMessage: String {
        let count = editingCourse?.sessions.count ?? 0
        let sessionText = count == 1
            ? "1 study session"
            : "\(count) study sessions"
        return "This permanently deletes this course and \(sessionText). This cannot be undone."
    }

    private func deleteCourse() {
        guard let course = editingCourse else { return }

        if sessionEngine.course?.persistentModelID == course.persistentModelID {
            sessionEngine.discard()
        }

        for session in Array(course.sessions) {
            modelContext.delete(session)
        }
        modelContext.delete(course)
        try? modelContext.save()
        isPresented = false
    }

    private func nameConflicts(_ trimmed: String, excluding course: Course) -> Bool {
        let descriptor = FetchDescriptor<Course>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.contains {
            $0.persistentModelID != course.persistentModelID &&
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}
