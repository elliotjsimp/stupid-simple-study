import SwiftUI
import SwiftData

struct SessionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings
    @Environment(TermContext.self) private var termContext
    @Environment(StudyDayClock.self) private var dayClock

    @Query(sort: \StudySession.startTime, order: .reverse) private var allSessions: [StudySession]

    @State private var selectedCourseID: PersistentIdentifier?
    @State private var selectedActivityID: PersistentIdentifier?
    @State private var showAddSheet = false
    @State private var editingSession: StudySession?
    @State private var sessionToDelete: StudySession?

    private var sessions: [StudySession] {
        guard let termID = termContext.displayedTerm?.persistentModelID else { return [] }
        return allSessions.filter { session in
            SessionFilter.matches(session, termID: termID, courseID: selectedCourseID, activityID: selectedActivityID)
        }
    }

    var body: some View {
        let _ = dayClock.startOfToday
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CourseActivityFilterBar(
                    selectedCourseID: $selectedCourseID,
                    selectedActivityID: $selectedActivityID
                )
                Spacer()
                Button("+") { showAddSheet = true }
                    .font(.title2)
                    .disabled(termContext.displayedTerm == nil)
                    .help(termContext.displayedTerm == nil ? "Create a term first" : "Add past session")
            }

            if sessions.isEmpty {
                Text("No sessions yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sessions, id: \.persistentModelID) { session in
                            SessionRowView(session: session, showFocus: settings.focusRatingsEnabled)
                                .onTapGesture { editingSession = session }
                                .contextMenu {
                                    Button("Delete", role: .destructive) { sessionToDelete = session }
                                }
                        }
                    }
                }
                .hiddenVerticalScrollIndicators()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPastSessionSheet(isPresented: $showAddSheet)
        }
        .sheet(isPresented: Binding(
            get: { editingSession != nil },
            set: { if !$0 { editingSession = nil } }
        )) {
            if let editingSession {
                EditSessionSheet(session: editingSession)
            }
        }
        .confirmationDialog("Delete this session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let sessionToDelete { modelContext.delete(sessionToDelete) }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        }
    }
}

struct SessionRowView: View {
    let session: StudySession
    let showFocus: Bool

    private let dateWidth: CGFloat = 110
    private let courseWidth: CGFloat = 188
    private let activityWidth: CGFloat = 168
    private let durationWidth: CGFloat = 48

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                Text(DurationFormatters.sessionListDate(session.startTime))
                    .font(.subheadline.weight(.semibold))
                    .frame(width: dateWidth, alignment: .leading)

                Group {
                    if let course = session.course {
                        CoursePill(course: course)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: courseWidth, alignment: .leading)
                .clipped()

                Text(session.activityNames.isEmpty ? "—" : session.activityNames)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: activityWidth, alignment: .leading)

                Text(session.note.isEmpty ? " " : session.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showFocus {
                    StaticStarRatingView(rating: session.focusRating)
                }

                DurationLabel(seconds: session.studyTimeSeconds)
                    .frame(width: durationWidth, alignment: .trailing)
            }
        }
    }
}


struct AddPastSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TermContext.self) private var termContext
    @Environment(\.appSettings) private var settings

    @Binding var isPresented: Bool

    @State private var date = Date()
    @State private var startTime = Date()
    @State private var useEndTime = true
    @State private var endTime = Date()
    @State private var durationMinutes = 60
    @State private var breakMinutes = 0
    @State private var selectedCourse: Course?
    @State private var activityName = ""
    @State private var note = ""
    @State private var focusRating: Int?

    private var courses: [Course] {
        termContext.displayedTerm?.courses.filter { !$0.isArchived } ?? []
    }

    var body: some View {
        Form {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
            Toggle("Use end time", isOn: $useEndTime)
            if useEndTime {
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                if endsNextDay {
                    Text("Ends the next day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 1...720)
                Stepper("Break: \(breakMinutes) min", value: $breakMinutes, in: 0...180)
            }
            Picker("Course", selection: $selectedCourse) {
                ForEach(courses, id: \.persistentModelID) { course in
                    Text(course.name).tag(Optional(course))
                }
            }
            TextField("Activity (optional)", text: $activityName)
            TextField("Note", text: $note, axis: .vertical)
            if settings.focusRatingsEnabled {
                StarRatingView(rating: $focusRating)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { selectedCourse = courses.first }
    }

    private var endsNextDay: Bool {
        guard useEndTime else { return false }
        return clockMinutes(endTime) < clockMinutes(startTime)
    }

    private func clockMinutes(_ date: Date) -> Int {
        let parts = Calendar.app.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func save() {
        guard let term = termContext.displayedTerm, let course = selectedCourse else { return }
        let calendar = Calendar.app
        let day = calendar.startOfDay(for: date)
        guard day >= term.firstDay && day <= term.lastDay else { return }

        var startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        startComponents.year = calendar.component(.year, from: date)
        startComponents.month = calendar.component(.month, from: date)
        startComponents.day = calendar.component(.day, from: date)
        guard let start = calendar.date(from: startComponents) else { return }

        var studySeconds: Int
        var end: Date
        if useEndTime {
            var endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            endComponents.year = startComponents.year
            endComponents.month = startComponents.month
            endComponents.day = startComponents.day
            guard let endOnStartDay = calendar.date(from: endComponents) else { return }
            if endOnStartDay > start {
                end = endOnStartDay
            } else if endsNextDay, let nextDay = calendar.date(byAdding: .day, value: 1, to: endOnStartDay) {
                end = nextDay
            } else {
                return
            }
            studySeconds = Int(end.timeIntervalSince(start))
            let clipped = StudyTimeAttribution.clipToTermLastDay(
                startTime: start,
                endTime: end,
                totalStudySeconds: studySeconds,
                termLastDay: term.lastDay
            )
            if clipped <= 0 { return }
            if clipped < studySeconds {
                let lastDayEnd = calendar.date(byAdding: .day, value: 1, to: term.lastDay.startOfDay) ?? end
                end = min(end, lastDayEnd)
                studySeconds = clipped
            }
        } else {
            studySeconds = max(0, durationMinutes * 60 - breakMinutes * 60)
            end = start.addingTimeInterval(TimeInterval(studySeconds))
        }

        let session = StudySession(
            startTime: start,
            endTime: end,
            studyTimeSeconds: studySeconds,
            note: note,
            focusRating: settings.focusRatingsEnabled ? focusRating : nil
        )
        session.term = term
        session.course = course
        modelContext.insert(session)

        let trimmed = activityName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let descriptor = FetchDescriptor<Activity>()
            let activities = (try? modelContext.fetch(descriptor)) ?? []
            let activity: Activity
            if let existing = activities.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                activity = existing
            } else {
                activity = Activity(name: trimmed)
                modelContext.insert(activity)
            }
            let segment = ActivitySegment(startTime: start, durationSeconds: studySeconds)
            segment.activity = activity
            segment.session = session
            modelContext.insert(segment)
        }

        try? modelContext.save()
        isPresented = false
    }
}

struct EditSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings
    @Bindable var session: StudySession

    @Environment(\.dismiss) private var dismiss
    @State private var studyMinutes: Int = 0
    @State private var note: String = ""
    @State private var focusRating: Int?

    var body: some View {
        Form {
            if let course = session.course {
                CoursePill(course: course)
            }
            Text(session.startTime, style: .date)
                .foregroundStyle(.secondary)
            Stepper("Study time: \(studyMinutes) min", value: $studyMinutes, in: 1...720)
            TextField("Note", text: $note, axis: .vertical)
            if settings.focusRatingsEnabled {
                StarRatingView(rating: $focusRating)
            }
            HStack {
                Spacer()
                Button("Done") {
                    session.studyTimeSeconds = studyMinutes * 60
                    session.endTime = session.startTime.addingTimeInterval(TimeInterval(session.studyTimeSeconds))
                    session.note = note
                    session.focusRating = settings.focusRatingsEnabled ? focusRating : nil
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            studyMinutes = max(1, session.studyTimeSeconds / 60)
            note = session.note
            focusRating = session.focusRating
        }
    }
}