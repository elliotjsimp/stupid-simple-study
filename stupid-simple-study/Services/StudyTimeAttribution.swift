import Foundation

/// Pure functions for attributing study time across calendar days and term boundaries.
enum StudyTimeAttribution {
    /// Splits session study time proportionally across calendar days when a session spans midnight.
    /// Used for heatmap cells and streak calculations.
    static func dailySeconds(
        startTime: Date,
        endTime: Date,
        totalStudySeconds: Int
    ) -> [Date: Int] {
        guard totalStudySeconds > 0, endTime > startTime else { return [:] }

        let calendar = Calendar.app
        var result: [Date: Int] = [:]
        var segmentStart = startTime
        let sessionDuration = endTime.timeIntervalSince(startTime)

        while segmentStart < endTime {
            let dayStart = calendar.startOfDay(for: segmentStart)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentEnd = min(endTime, nextDay)
            let wallSeconds = segmentEnd.timeIntervalSince(segmentStart)
            let proportion = wallSeconds / sessionDuration
            let attributed = Int((Double(totalStudySeconds) * proportion).rounded())
            result[dayStart, default: 0] += attributed
            segmentStart = segmentEnd
        }

        // Fix rounding drift
        let sum = result.values.reduce(0, +)
        if sum != totalStudySeconds, let lastDay = result.keys.sorted().last {
            result[lastDay, default: 0] += totalStudySeconds - sum
        }

        return result
    }

    /// Credits only study time on or before the term's last day when a live session runs past term end.
    static func clipToTermLastDay(
        startTime: Date,
        endTime: Date,
        totalStudySeconds: Int,
        termLastDay: Date
    ) -> Int {
        let calendar = Calendar.app
        let lastDayEnd = calendar.date(byAdding: .day, value: 1, to: termLastDay) ?? termLastDay
        if endTime <= lastDayEnd { return totalStudySeconds }
        if startTime >= lastDayEnd { return 0 }

        let clippedEnd = min(endTime, lastDayEnd)
        let fullDuration = endTime.timeIntervalSince(startTime)
        guard fullDuration > 0 else { return 0 }
        let clippedDuration = clippedEnd.timeIntervalSince(startTime)
        return Int((Double(totalStudySeconds) * (clippedDuration / fullDuration)).rounded())
    }

    static func isUntrackedDay(_ day: Date, trackingStart: Date) -> Bool {
        day < trackingStart.startOfDay
    }
}
