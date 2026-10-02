import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard
    case sessions
    case term
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .sessions: "Sessions"
        case .term: "Term"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "house"
        case .sessions: "list.bullet"
        case .term: "calendar"
        case .settings: "gearshape"
        }
    }
}

enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case all = "All"

    var id: String { rawValue }

    /// Trailing window for the quality-trend line, in calendar days.
    var qualityTrendWindowDays: Int {
        switch self {
        case .day: 1
        case .week: 2
        case .month: 7
        case .all: 14
        }
    }

    var goalCaptionSuffix: String {
        switch self {
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        case .all: "this term"
        }
    }

    /// Inclusive start/end for stats, clipped to the term and an as-of day.
    func bounds(asOf: Date, term: Term) -> (start: Date, end: Date) {
        let termStart = term.firstDay.startOfDay
        let termEnd = min(asOf.startOfDay, term.lastDay.startOfDay)
        let calendar = Calendar.app
        switch self {
        case .day:
            return (max(termStart, termEnd), termEnd)
        case .week:
            let raw = calendar.date(byAdding: .day, value: -6, to: termEnd) ?? termEnd
            return (max(termStart, raw.startOfDay), termEnd)
        case .month:
            let raw = calendar.date(byAdding: .day, value: -29, to: termEnd) ?? termEnd
            return (max(termStart, raw.startOfDay), termEnd)
        case .all:
            return (termStart, termEnd)
        }
    }
}
