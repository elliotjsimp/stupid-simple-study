import SwiftUI
import SwiftData

struct TermView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TermContext.self) private var termContext

    @State private var showCreateTerm = false
    @State private var showEditTerm = false
    @State private var monthOffset = 0

    var body: some View {
        Group {
            if termContext.displayedTerm == nil {
                EmptyStateView(
                    title: "Create your first term",
                    message: "A term marks the first and last day of your study period,\nwith an option to set the last day of lectures within that range.",
                    actionTitle: "New Term",
                    action: { showCreateTerm = true }
                )
            } else if let term = termContext.displayedTerm {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 16) {
                            Text("\(term.firstDay.formatted(date: .abbreviated, time: .omitted)) – \(term.lastDay.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)

                            Spacer()
                            HStack(spacing: 8) {
                                Button("Edit") { showEditTerm = true }
                                Button("New Term") { showCreateTerm = true }
                            }
                        }

                        TermCalendarView(
                            term: term,
                            monthOffset: $monthOffset
                        )
                    }
                }
                .hiddenVerticalScrollIndicators()
            }
        }
        .sheet(isPresented: $showCreateTerm) {
            TermFormSheet(mode: .create, isPresented: $showCreateTerm)
        }
        .sheet(isPresented: $showEditTerm) {
            if let term = termContext.displayedTerm {
                TermFormSheet(mode: .edit(term), isPresented: $showEditTerm)
            }
        }
    }
}

struct TermCalendarView: View {
    @Environment(\.appSettings) private var settings

    let term: Term
    @Binding var monthOffset: Int

    private let gridSpacing: CGFloat = 4
    private let cellAspectRatio: CGFloat = 1.15

    private var displayedMonth: Date {
        let base = term.firstDay
        return Calendar.app.date(byAdding: .month, value: monthOffset, to: base) ?? base
    }

    var body: some View {
        Card {
            HStack {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Spacer()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 7),
                spacing: gridSpacing
            ) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(daysInMonth().enumerated()), id: \.offset) { _, day in
                    if let day {
                        CalendarDayCell(
                            day: day,
                            term: term,
                            accentColor: settings.resolvedAccentColor
                        )
                        .aspectRatio(cellAspectRatio, contentMode: .fit)
                    } else {
                        Color.clear
                            .aspectRatio(cellAspectRatio, contentMode: .fit)
                    }
                }
            }
            .containerRelativeFrame(.horizontal) { width, _ in width * 0.85 }
            .frame(maxWidth: .infinity)
        }
    }

    private func daysInMonth() -> [Date?] {
        let calendar = Calendar.app
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let range = calendar.range(of: .day, in: .month, for: monthStart)!
        let firstWeekday = (calendar.component(.weekday, from: monthStart) + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }
        return days
    }
}

struct CalendarDayCell: View {
    let day: Date
    let term: Term
    let accentColor: Color

    private var inTerm: Bool {
        day.startOfDay >= term.firstDay && day.startOfDay <= term.lastDay
    }

    private var isExamPeriod: Bool {
        guard let lastLecture = term.lastLectureDate else { return false }
        let afterLecture = Calendar.app.date(byAdding: .day, value: 1, to: lastLecture) ?? lastLecture
        return day.startOfDay >= afterLecture && day.startOfDay <= term.lastDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Calendar.app.component(.day, from: day))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(inTerm ? .primary : .tertiary)

            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
        }
    }

    private var backgroundFill: Color {
        guard inTerm else { return .clear }
        if isExamPeriod { return Color.orange.opacity(0.12) }
        return accentColor.opacity(0.06)
    }
}

enum TermFormMode {
    case create
    case edit(Term)
}

struct TermFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TermContext.self) private var termContext

    let mode: TermFormMode
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var firstDay = Date()
    @State private var lastDay = Date()
    @State private var trackingStart = Date()
    @State private var lastLecture: Date?
    @State private var hasLastLecture = false
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            DatePicker("First day", selection: $firstDay, displayedComponents: .date)
            DatePicker("Last day", selection: $lastDay, displayedComponents: .date)
            DatePicker("Tracking start", selection: $trackingStart, displayedComponents: .date)
            Toggle("Last lecture date", isOn: $hasLastLecture)
            if hasLastLecture {
                DatePicker("Last lecture", selection: Binding(
                    get: { lastLecture ?? lastDay },
                    set: { lastLecture = $0 }
                ), displayedComponents: .date)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if case .edit(let term) = mode {
                    Button("Delete Term", role: .destructive) {
                        modelContext.delete(term)
                        try? modelContext.save()
                        isPresented = false
                    }
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            if case .edit(let term) = mode {
                name = term.name
                firstDay = term.firstDay
                lastDay = term.lastDay
                trackingStart = term.trackingStartDate
                lastLecture = term.lastLectureDate
                hasLastLecture = term.lastLectureDate != nil
            }
        }
    }

    private func save() {
        let f = firstDay.startOfDay
        let l = lastDay.startOfDay
        guard l >= f else {
            error = "Last day must be on or after first day."
            return
        }
        let draft = Term(name: name, firstDay: f, lastDay: l, trackingStartDate: trackingStart.startOfDay, lastLectureDate: hasLastLecture ? lastLecture?.startOfDay : nil)
        let excluding: Term? = if case .edit(let term) = mode { term } else { nil }
        if !termContext.validateNoOverlap(for: draft, excluding: excluding) {
            error = "Term dates overlap an existing term."
            return
        }

        switch mode {
        case .create:
            modelContext.insert(draft)
        case .edit(let term):
            term.name = name
            term.firstDay = f
            term.lastDay = l
            term.trackingStartDate = trackingStart.startOfDay
            term.lastLectureDate = hasLastLecture ? lastLecture?.startOfDay : nil
        }
        try? modelContext.save()
        isPresented = false
    }
}
