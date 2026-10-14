import AppKit
import Foundation

/// Publishes the start of the current local day and advances it at midnight,
/// after wake, and when the system clock or time zone changes.
@Observable
@MainActor
final class StudyDayClock {
    static let shared = StudyDayClock()

    private(set) var startOfToday: Date

    private var rolloverTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        startOfToday = Date().startOfDay
        scheduleRollover()

        let names: [(NotificationCenter, Notification.Name)] = [
            (.default, .NSCalendarDayChanged),
            (.default, .NSSystemClockDidChange),
            (.default, .NSSystemTimeZoneDidChange),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        for (center, name) in names {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            )
        }
    }

    func refresh() {
        let today = Date().startOfDay
        if today != startOfToday {
            startOfToday = today
        }
        scheduleRollover()
    }

    private func scheduleRollover() {
        rolloverTimer?.invalidate()
        guard let nextMidnight = Calendar.app.date(byAdding: .day, value: 1, to: Date().startOfDay) else { return }
        let timer = Timer(fire: nextMidnight.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
    }
}
