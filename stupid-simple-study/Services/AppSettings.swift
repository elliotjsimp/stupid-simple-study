import SwiftUI
import AppKit

enum AccentColorPreset: String, CaseIterable, Identifiable {
    case system
    case purple
    case blue
    case green
    case orange
    case pink
    case teal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .purple: "Purple"
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        case .pink: "Pink"
        case .teal: "Teal"
        }
    }

    /// `nil` means use the system accent color.
    var color: Color? {
        switch self {
        case .system: nil
        case .purple: Color(red: 0.55, green: 0.35, blue: 0.85)
        case .blue: Color(red: 0.25, green: 0.45, blue: 0.95)
        case .green: Color(red: 0.20, green: 0.70, blue: 0.45)
        case .orange: Color(red: 0.95, green: 0.55, blue: 0.20)
        case .pink: Color(red: 0.90, green: 0.35, blue: 0.55)
        case .teal: Color(red: 0.20, green: 0.65, blue: 0.70)
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// Last-seen macOS light/dark setting. Used when `appearance == .system`.
    private(set) var systemColorScheme: ColorScheme

    private var themeObserver: NSObjectProtocol?

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var accentColor: AccentColorPreset {
        didSet { defaults.set(accentColor.rawValue, forKey: Keys.accentColor) }
    }

    var showMenuBarItem: Bool {
        didSet { defaults.set(showMenuBarItem, forKey: Keys.showMenuBarItem) }
    }

    var showMenuBarTimer: Bool {
        didSet { defaults.set(showMenuBarTimer, forKey: Keys.showMenuBarTimer) }
    }

    var focusRatingsEnabled: Bool {
        didSet { defaults.set(focusRatingsEnabled, forKey: Keys.focusRatingsEnabled) }
    }

    var streaksEnabled: Bool {
        didSet { defaults.set(streaksEnabled, forKey: Keys.streaksEnabled) }
    }

    var showGoalSummary: Bool {
        didSet { defaults.set(showGoalSummary, forKey: Keys.showGoalSummary) }
    }

    var dailyGoalHours: Double {
        didSet { defaults.set(dailyGoalHours, forKey: Keys.dailyGoalHours) }
    }

    var useWeekdayDailyGoals: Bool {
        didSet { defaults.set(useWeekdayDailyGoals, forKey: Keys.useWeekdayDailyGoals) }
    }

    /// Monday-first study-time goals in hours when `useWeekdayDailyGoals` is on.
    var weekdayGoalHours: [Double] {
        didSet { defaults.set(weekdayGoalHours, forKey: Keys.weekdayGoalHours) }
    }

    /// Study hours that map to full heatmap intensity.
    var heatmapFullHours: Double {
        didSet { defaults.set(heatmapFullHours, forKey: Keys.heatmapFullHours) }
    }

    var sidebarShowsLabels: Bool {
        didSet { defaults.set(sidebarShowsLabels, forKey: Keys.sidebarShowsLabels) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    private enum Keys {
        static let appearance = "appearance"
        static let accentColor = "accentColor"
        static let themeColor = "themeColor"
        static let showMenuBarItem = "showMenuBarItem"
        static let showMenuBarTimer = "showMenuBarTimer"
        static let focusRatingsEnabled = "focusRatingsEnabled"
        static let streaksEnabled = "streaksEnabled"
        static let showGoalSummary = "showGoalSummary"
        static let dailyGoalHours = "dailyGoalHours"
        static let useWeekdayDailyGoals = "useWeekdayDailyGoals"
        static let weekdayGoalHours = "weekdayGoalHours"
        static let heatmapFullHours = "heatmapFullHours"
        static let sidebarShowsLabels = "sidebarShowsLabels"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private init() {
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        if let saved = defaults.string(forKey: Keys.accentColor),
           let preset = AccentColorPreset(rawValue: saved) {
            accentColor = preset
        } else if let legacy = defaults.string(forKey: Keys.themeColor),
                  let preset = AccentColorPreset(rawValue: legacy) {
            accentColor = preset
        } else {
            accentColor = .system
        }
        showMenuBarItem = defaults.object(forKey: Keys.showMenuBarItem) as? Bool ?? true
        showMenuBarTimer = defaults.object(forKey: Keys.showMenuBarTimer) as? Bool ?? true
        focusRatingsEnabled = defaults.object(forKey: Keys.focusRatingsEnabled) as? Bool ?? true
        streaksEnabled = defaults.object(forKey: Keys.streaksEnabled) as? Bool ?? true
        showGoalSummary = defaults.object(forKey: Keys.showGoalSummary) as? Bool ?? true
        let loadedDailyGoalHours = defaults.object(forKey: Keys.dailyGoalHours) as? Double ?? 2.0
        dailyGoalHours = loadedDailyGoalHours
        useWeekdayDailyGoals = defaults.object(forKey: Keys.useWeekdayDailyGoals) as? Bool ?? false
        if let stored = defaults.array(forKey: Keys.weekdayGoalHours) as? [Double], stored.count == 7 {
            weekdayGoalHours = stored
        } else {
            weekdayGoalHours = Array(repeating: loadedDailyGoalHours, count: 7)
        }
        heatmapFullHours = defaults.object(forKey: Keys.heatmapFullHours) as? Double ?? 2.0
        sidebarShowsLabels = defaults.object(forKey: Keys.sidebarShowsLabels) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        systemColorScheme = Self.detectSystemColorScheme()
        themeObserver = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppSettings.shared.refreshSystemColorScheme()
            }
        }
    }

    /// Always a concrete scheme. Passing `nil` to `preferredColorScheme` after an
    /// explicit light/dark override fails to reset AppKit window appearance.
    var preferredColorScheme: ColorScheme {
        switch appearance {
        case .system: systemColorScheme
        case .light: .light
        case .dark: .dark
        }
    }

    private func refreshSystemColorScheme() {
        let next = Self.detectSystemColorScheme()
        if next != systemColorScheme {
            systemColorScheme = next
        }
    }

    private static func detectSystemColorScheme() -> ColorScheme {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return .dark
        }
        if let app = NSApp {
            let match = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return .dark
            }
        }
        return .light
    }

    var resolvedAccentColor: Color {
        accentColor.color ?? Color(nsColor: .controlAccentColor)
    }

    static let weekdayGoalLabels = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let weekdayGoalShortLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    func goalHours(for date: Date) -> Double {
        guard useWeekdayDailyGoals, weekdayGoalHours.count == 7 else {
            return dailyGoalHours
        }
        let index = (Calendar.app.component(.weekday, from: date) + 5) % 7
        return weekdayGoalHours[index]
    }

    func goalSeconds(for date: Date) -> Int {
        Int(goalHours(for: date) * 3600)
    }

    var heatmapFullSeconds: Int {
        Int(heatmapFullHours * 3600)
    }

    var chartScaleGoalSeconds: Int {
        if useWeekdayDailyGoals, let maxHours = weekdayGoalHours.max() {
            return Int(maxHours * 3600)
        }
        return Int(dailyGoalHours * 3600)
    }

    func resetAllPreferences() {
        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }
        appearance = .system
        accentColor = .system
        showMenuBarItem = true
        showMenuBarTimer = true
        focusRatingsEnabled = true
        streaksEnabled = true
        showGoalSummary = true
        dailyGoalHours = 2.0
        useWeekdayDailyGoals = false
        weekdayGoalHours = Array(repeating: 2.0, count: 7)
        heatmapFullHours = 2.0
        sidebarShowsLabels = true
        hasCompletedOnboarding = false
    }
}

private struct AppSettingsKey: EnvironmentKey {
    static let defaultValue = AppSettings.shared
}

extension EnvironmentValues {
    var appSettings: AppSettings {
        get { self[AppSettingsKey.self] }
        set { self[AppSettingsKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func appAccentColor(_ settings: AppSettings) -> some View {
        if settings.accentColor == .system {
            self
        } else {
            self.tint(settings.resolvedAccentColor)
        }
    }
}
