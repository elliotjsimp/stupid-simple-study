import Foundation

/// Pure functions for attributing study time across calendar days and term boundaries.
enum StudyTimeAttribution {
    /// Splits known study intervals across the calendar days they occupy.
    /// Time before midnight stays on the start day; time after midnight counts
    /// toward the new day. Gaps between intervals (pauses) are not study time.
    static func dailySeconds(intervals: [(start: Date, end: Date)]) -> [Date: Int] {
        let calendar = Calendar.app
        var result: [Date: Int] = [:]
        var expected = 0

        for (start, end) in intervals where end > start {
            expected += max(0, Int(end.timeIntervalSince(start).rounded()))
            var cursor = start
            while cursor < end {
                let dayStart = calendar.startOfDay(for: cursor)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let segmentEnd = min(end, nextDay)
                let seconds = max(0, Int(segmentEnd.timeIntervalSince(cursor).rounded()))
                if seconds > 0 {
                    result[dayStart, default: 0] += seconds
                }
                cursor = segmentEnd
            }
        }

        let sum = result.values.reduce(0, +)
        if sum != expected, let lastDay = result.keys.sorted().last {
            result[lastDay, default: 0] += expected - sum
        }
        return result
    }

    /// Splits session study time across calendar days. When wall-clock time is
    /// longer than study time (for example after a forgotten overnight session),
    /// the study duration is treated as contiguous from the recorded start.
    /// Used when a session has no per-interval record.
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
