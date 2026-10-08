import Foundation

/// Pure functions for attributing study time across calendar days and term boundaries.
enum StudyTimeAttribution {
    /// Splits session study time across calendar days. When wall-clock time is
    /// longer than study time (for example after a forgotten overnight session),
    /// the study duration is treated as contiguous from the recorded start.
    /// Used for heatmap cells and streak calculations.
    static func dailySeconds(
        startTime: Date,
        endTime: Date,
        totalStudySeconds: Int
    ) -> [Date: Int] {
        guard totalStudySeconds > 0, endTime > startTime else { return [:] }

        let calendar = Calendar.app
        let durationEnd = startTime.addingTimeInterval(TimeInterval(totalStudySeconds))
        let attributedEnd = min(endTime, durationEnd)
        var result: [Date: Int] = [:]
        var segmentStart = startTime
        let sessionDuration = attributedEnd.timeIntervalSince(startTime)
        guard sessionDuration > 0 else { return [:] }

        while segmentStart < attributedEnd {
            let dayStart = calendar.startOfDay(for: segmentStart)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentEnd = min(attributedEnd, nextDay)
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
        let durationEnd = startTime.addingTimeInterval(TimeInterval(totalStudySeconds))
        let attributedEnd = min(endTime, durationEnd)
        let lastDayEnd = calendar.date(byAdding: .day, value: 1, to: termLastDay) ?? termLastDay
        if attributedEnd <= lastDayEnd { return totalStudySeconds }
        if startTime >= lastDayEnd { return 0 }

        let clippedEnd = min(attributedEnd, lastDayEnd)
        let fullDuration = attributedEnd.timeIntervalSince(startTime)
        guard fullDuration > 0 else { return 0 }
        let clippedDuration = clippedEnd.timeIntervalSince(startTime)
        return Int((Double(totalStudySeconds) * (clippedDuration / fullDuration)).rounded())
    }

    static func isUntrackedDay(_ day: Date, trackingStart: Date) -> Bool {
        day < trackingStart.startOfDay
    }
}
