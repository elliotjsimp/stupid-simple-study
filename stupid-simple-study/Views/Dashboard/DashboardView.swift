import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.appSettings) private var settings
    @Environment(TermContext.self) private var termContext
    @Environment(StudyDayClock.self) private var dayClock
    @Environment(SessionEngine.self) private var sessionEngine

    @Query private var allSessions: [StudySession]
    @State private var selectedRange: DashboardTimeRange = .all

    var onStartSession: () -> Void
    var onGoToTerm: () -> Void

    private var termSessions: [StudySession] {
        guard let termID = termContext.displayedTerm?.persistentModelID else { return [] }
        return allSessions.filter { $0.term?.persistentModelID == termID }
    }

    private var asOfDay: Date {
        guard let term = termContext.displayedTerm else { return dayClock.startOfToday }
        let today = dayClock.startOfToday
        if today < term.firstDay { return term.firstDay }
        if today > term.lastDay { return term.lastDay }
        return today
    }

    private var statsRange: (start: Date, end: Date)? {
        guard let term = termContext.displayedTerm else { return nil }
        return selectedRange.bounds(asOf: asOfDay, term: term)
    }

    private var stats: TermStats? {
        let _ = sessionEngine.tickCount
        guard let term = termContext.displayedTerm else { return nil }
        let range = statsRange
        let provisional = sessionEngine.term?.persistentModelID == term.persistentModelID
            ? sessionEngine.provisionalStudy()
            : nil
        return StatsCalculator.compute(
            term: term,
            sessions: termSessions,
            streaksEnabled: settings.streaksEnabled,
            focusRatingsEnabled: settings.focusRatingsEnabled,
            rangeStart: range?.start,
            rangeEnd: range?.end,
            asOf: dayClock.startOfToday,
            provisional: provisional,
            goalHoursForDay: { settings.goalHours(for: $0) }
        )
    }

    private var remainingUnlockDays: Int {
        guard let stats else { return StatsCalculator.chartUnlockStudyDays }
        return max(0, StatsCalculator.chartUnlockStudyDays - stats.termStudyDayCount)
    }

    var body: some View {
        Group {
            if termContext.displayedTerm == nil {
                EmptyStateView(
                    title: "Welcome to Stupid Simple Study",
                    message: "Track your study sessions by course and activity, set goals, and view your progress all in one place.",
                    actionTitle: "Get Started",
                    action: onGoToTerm
                )
            } else if stats?.totalStudySeconds == 0 && termSessions.isEmpty {
                EmptyStateView(
                    title: "Start your first session",
                    message: "It's time to get studying!",
                    actionTitle: "Start Session",
                    action: onStartSession
                )
            } else if let stats, let term = termContext.displayedTerm {
                VStack(alignment: .leading, spacing: 12) {
                    rangePicker

                    ScrollView {
                        VStack(spacing: DashboardLayout.gridSpacing) {
                            Grid(
                                horizontalSpacing: DashboardLayout.gridSpacing,
                                verticalSpacing: DashboardLayout.gridSpacing
                            ) {
                                GridRow {
                                    gridCell(statsStrip(stats, term: term), height: DashboardLayout.overviewRowHeight)
                                    gridCell(heatmapCard(stats, term: term), height: DashboardLayout.overviewRowHeight)
                                }
                                GridRow {
                                    gridCell(coursesBarChart(stats), height: DashboardLayout.chartRowHeight)
                                    gridCell(activitiesBarChart(stats), height: DashboardLayout.chartRowHeight)
                                }
                                if settings.focusRatingsEnabled {
                                    GridRow {
                                        gridCell(weekdayRadar(stats), height: DashboardLayout.wideRowHeight)
                                        gridCell(focusTrend(stats), height: DashboardLayout.wideRowHeight)
                                    }
                                } else {
                                    GridRow {
                                        gridCell(weekdayRadar(stats), height: DashboardLayout.wideRowHeight)
                                        Color.clear.frame(height: DashboardLayout.wideRowHeight)
                                    }
                                }
                            }
                        }
                    }
                    .hiddenVerticalScrollIndicators()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rangePicker: some View {
        HStack(spacing: 14) {
            ForEach(DashboardTimeRange.allCases) { range in
                Button(range.rawValue) {
                    selectedRange = range
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(selectedRange == range ? .semibold : .regular))
                .foregroundStyle(selectedRange == range ? Color.primary : Color.secondary)
            }
            Spacer()
        }
    }

    private func gridCell<Content: View>(_ content: Content, height: CGFloat) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statsStrip(_ stats: TermStats, term: Term) -> some View {
        let goalSeconds = settings.goalSeconds(for: dayClock.startOfToday)
        let showsToday = term.contains(date: dayClock.startOfToday)
        return Card {
            Text("Overview").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                if showsToday {
                    let progress = goalSeconds > 0 ? Double(stats.todayStudySeconds) / Double(goalSeconds) : 0
                    let pct = String(format: "%.1f", round(progress * 10000) / 100)
                    let pastGoal = goalSeconds > 0 && stats.todayStudySeconds >= goalSeconds

                    HStack {
                        Text(
                            "Today: \(DurationFormatters.compactHours(stats.todayStudySeconds, style: settings.durationDisplayStyle)) / "
                            + DurationFormatters.compactHours(goalSeconds, style: settings.durationDisplayStyle)
                        )
                        Spacer()
                        if pastGoal {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(settings.resolvedAccentColor)
                                .accessibilityLabel("Daily goal met")
                        }
                        Text("\(pct)%")
                            .foregroundStyle(pastGoal ? settings.resolvedAccentColor : .secondary)
                            .font(.subheadline)
                    }
                    .font(.title3.bold())
                    if goalSeconds > 0 {
                        ProgressView(value: min(progress, 1))
                    }
                }
                if settings.showGoalSummary {
                    Text("\(stats.dailyGoalProgressDays) of \(stats.dailyGoalTargetDays) study days met goal \(selectedRange.goalCaptionSuffix)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                statItem(
                    "Total",
                    DurationFormatters.compactHours(stats.totalStudySeconds, style: settings.durationDisplayStyle)
                )
                statItem(
                    "Avg/day",
                    DurationFormatters.compactHours(stats.averagePerStudyDaySeconds, style: settings.durationDisplayStyle)
                )
                if settings.streaksEnabled {
                    statItem("Streak", "\(stats.currentStreak)d")
                    statItem("Longest", "\(stats.longestStreak)d")
                }
            }
        }
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
    }

    private func heatmapCard(_ stats: TermStats, term: Term) -> some View {
        Card {
            Text("Heatmap").font(.headline)
            HeatmapView(
                dailyTotals: stats.termDailyTotals,
                trackingStart: term.trackingStartDate,
                termFirstDay: term.firstDay,
                termLastDay: term.lastDay,
                fullColorSeconds: settings.heatmapFullSeconds,
                themeColor: settings.resolvedAccentColor
            )
        }
    }

    private func coursesBarChart(_ stats: TermStats) -> some View {
        Card {
            Text("Courses").font(.headline)
            if stats.courseTotals.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudyTimeBarChart(
                    bars: stats.courseTotals.map {
                        StudyTimeBar(id: $0.name, name: $0.name, seconds: $0.seconds, color: Color(hex: $0.colorHex))
                    },
                    minXScaleSeconds: settings.chartScaleGoalSeconds
                )
            }
        }
    }

    private func activitiesBarChart(_ stats: TermStats) -> some View {
        Card {
            Text("Activities").font(.headline)
            if stats.activityTotals.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudyTimeBarChart(
                    bars: stats.activityTotals.map { item in
                        StudyTimeBar(
                            id: item.name,
                            name: item.name,
                            seconds: item.seconds,
                            color: settings.resolvedAccentColor
                        )
                    },
                    footnote: settings.showTimeWithoutActivity && stats.secondsWithoutActivity > 0
                        ? "\(DurationFormatters.compactHours(stats.secondsWithoutActivity, style: settings.durationDisplayStyle)) without activity"
                        : nil,
                    minXScaleSeconds: settings.chartScaleGoalSeconds
                )
            }
        }
    }

    private func weekdayRadar(_ stats: TermStats) -> some View {
        Card {
            Text("Study by Weekday").font(.headline)
            if selectedRange == .day {
                ChartOneDayPlaceholder()
            } else if remainingUnlockDays > 0 {
                ChartUnlockPlaceholder(remainingDays: remainingUnlockDays, chartName: "weekday pattern")
            } else {
                RadarChartView(weekdayAverages: stats.weekdayAverages, themeColor: settings.resolvedAccentColor)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func focusTrend(_ stats: TermStats) -> some View {
        Card {
            Text("Quality Trend").font(.headline)
            if selectedRange == .day {
                if stats.studyDayCount > 0 {
                    qualityTrendChart(stats)
                } else {
                    ChartOneDayPlaceholder()
                }
            } else if remainingUnlockDays > 0 {
                ChartUnlockPlaceholder(remainingDays: remainingUnlockDays, chartName: "quality trend")
            } else {
                qualityTrendChart(stats)
            }
        }
    }

    private func qualityTrendChart(_ stats: TermStats) -> some View {
        FocusTrendChart(
            points: stats.focusTrend,
            range: selectedRange,
            themeColor: settings.resolvedAccentColor
        )
        .frame(maxHeight: .infinity)
    }
}
