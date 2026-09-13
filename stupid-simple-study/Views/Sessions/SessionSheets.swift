import SwiftUI
import SwiftData

struct StartSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TermContext.self) private var termContext
    @Environment(SessionEngine.self) private var sessionEngine

    @Binding var isPresented: Bool

    @Query(sort: \Activity.name) private var activities: [Activity]

    @State private var selectedCourse: Course?
    @State private var selectedActivity: Activity?
    @State private var showCreateCourse = false
    @State private var isCreatingActivity = false
    @State private var newActivityName = ""
    @State private var errorMessage: String?

    private var courses: [Course] {
        guard let term = termContext.displayedTerm else { return [] }
        return term.courses.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ZStack {
            startSessionForm
                .opacity(showCreateCourse ? 0 : 1)
                .allowsHitTesting(!showCreateCourse)

            if showCreateCourse {
                CourseEditorSheet(mode: .create, isPresented: $showCreateCourse) { course in
                    selectedCourse = course
                }
            }
        }
        .frame(width: 520)
        .onAppear {
            if courses.isEmpty {
                showCreateCourse = true
            }
        }
    }

    private var startSessionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start Session")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 16) {
                coursePicker
                activityPicker
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Start") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
            }
        }
        .padding(24)
    }

    private var canStart: Bool {
        selectedCourse != nil
    }

    @ViewBuilder
    private var coursePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Course").font(.caption).foregroundStyle(.secondary)
            Menu {
                ForEach(courses, id: \.persistentModelID) { course in
                    Button(course.name) { selectedCourse = course }
                }
                Divider()
                Button("Create new course…") {
                    showCreateCourse = true
                }
            } label: {
                pickerLabel(selectedCourse?.name ?? "Select course")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity (optional)").font(.caption).foregroundStyle(.secondary)
            if isCreatingActivity {
                TextField("New activity name", text: $newActivityName)
                if !activities.isEmpty {
                    Button("Choose existing") {
                        isCreatingActivity = false
                        newActivityName = ""
                    }
                    .font(.caption)
                }
            } else {
                Menu {
                    if selectedActivity != nil {
                        Button("None") {
                            selectedActivity = nil
                            newActivityName = ""
                        }
                    }
                    ForEach(activities, id: \.persistentModelID) { activity in
                        Button(activity.name) {
                            selectedActivity = activity
                            newActivityName = ""
                        }
                    }
                    if selectedActivity != nil || !activities.isEmpty {
                        Divider()
                    }
                    Button("Create new activity…") {
                        isCreatingActivity = true
                        selectedActivity = nil
                    }
                } label: {
                    pickerLabel(selectedActivity?.name ?? "Select activity")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pickerLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(title.hasPrefix("Select") ? .secondary : .primary)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func start() {
        guard let term = termContext.activeTerm else { return }
        guard let course = selectedCourse else { return }

        let activity: String?
        if isCreatingActivity {
            let trimmed = newActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
            activity = trimmed.isEmpty ? nil : trimmed
            if let activity, !activities.contains(where: { $0.name.caseInsensitiveCompare(activity) == .orderedSame }) {
                modelContext.insert(Activity(name: activity))
            }
        } else if let selectedActivity {
            activity = selectedActivity.name
        } else {
            activity = nil
        }

        sessionEngine.start(term: term, course: course, activityName: activity)
        isPresented = false
    }
}

struct EndSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings
    @Environment(SessionEngine.self) private var sessionEngine

    @Binding var isPresented: Bool

    @State private var studySeconds: Int = 0
    @State private var note = ""
    @State private var focusRating: Int?
    @State private var showShortPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("End Session")
                .font(.title2.bold())

            Stepper(
                "Study time: \(DurationFormatters.clock(seconds: studySeconds))",
                value: $studySeconds,
                in: 0...24 * 3600,
                step: 60
            )

            TextField("Add a quick note?", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: note) { _, newValue in
                    if newValue.count > 500 { note = String(newValue.prefix(500)) }
                }

            if settings.focusRatingsEnabled {
                StarRatingView(rating: $focusRating)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Continue") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420, height: 320)
        .onAppear {
            studySeconds = sessionEngine.completedStudySecondsForSave()
            if studySeconds < 60 { showShortPrompt = true }
        }
        .confirmationDialog("Study time is under 1 minute.", isPresented: $showShortPrompt) {
            Button("Log anyway") { showShortPrompt = false }
            Button("Discard", role: .destructive) {
                sessionEngine.discard()
                isPresented = false
            }
        }
    }

    private func save() {
        if studySeconds < 60 && !showShortPrompt {
            showShortPrompt = true
            return
        }
        guard let term = sessionEngine.term, let course = sessionEngine.course,
              let start = sessionEngine.sessionStartTime else {
            sessionEngine.discard()
            isPresented = false
            return
        }

        let end = Date()
        let clipped = StudyTimeAttribution.clipToTermLastDay(
            startTime: start,
            endTime: end,
            totalStudySeconds: studySeconds,
            termLastDay: term.lastDay
        )

        let session = StudySession(
            startTime: start,
            endTime: end,
            studyTimeSeconds: clipped,
            note: note,
            focusRating: settings.focusRatingsEnabled ? focusRating : nil
        )
        session.term = term
        session.course = course
        modelContext.insert(session)

        for live in SessionEngine.normalizedSegments(sessionEngine.segments) where live.durationSeconds > 0 {
            guard let name = live.activityName else { continue }
            let descriptor = FetchDescriptor<Activity>()
            let activities = (try? modelContext.fetch(descriptor)) ?? []
            let activity: Activity
            if let existing = activities.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                activity = existing
            } else {
                activity = Activity(name: name)
                modelContext.insert(activity)
            }
            let segment = ActivitySegment(startTime: live.startTime, durationSeconds: live.durationSeconds)
            segment.activity = activity
            segment.session = session
            modelContext.insert(segment)
        }

        try? modelContext.save()
        sessionEngine.discard()
        isPresented = false
    }
}
