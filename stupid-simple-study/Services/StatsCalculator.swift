import Foundation
import SwiftData

struct ProvisionalSegment {
    var startTime: Date
    var durationSeconds: Int
    var activityName: String?
}

/// An in-progress session, attributed separately from saved sessions so a live
/// session that crosses midnight can land on both days before it is saved.
struct ProvisionalStudy {
    var startTime: Date
    var endTime: Date
    var studyTimeSeconds: Int
    var courseName: String
    var courseColorHex: String
    var segments: [ProvisionalSegment]
}

struct DailyStudyTotal: Identifiable {
    let date: Date
    let seconds: Int
    var id: Date { date }
}

struct CourseStudyTotal: Identifiable {
    let courseID: PersistentIdentifier?
    let name: String
    let colorHex: String
    let seconds: Int
    var id: String { name }
}

struct ActivityStudyTotal: Identifiable {
    let name: String
    let seconds: Int
    var id: String { name }
}

struct FocusTrendPoint: Identifiable {
    let id: PersistentIdentifier
    let date: Date
    let rating: Double
    let courseName: String
    let activityNames: String
    let studySeconds: Int
}

struct TermStats {
    let totalStudySeconds: Int
    let averagePerStudyDaySeconds: Int
    let currentStreak: Int
    let longestStreak: Int
    let studyDayCount: Int
    /// Study days across the whole term, used to unlock focus/radar charts.
    let termStudyDayCount: Int
    let dailyTotals: [DailyStudyTotal]
    let termDailyTotals: [DailyStudyTotal]
    let courseTotals: [CourseStudyTotal]
    let activityTotals: [ActivityStudyTotal]
    let secondsWithoutActivity: Int
    let focusTrend: [FocusTrendPoint]
    let weekdayAverages: [Int]
    let todayStudySeconds: Int
    let dailyGoalProgressDays: Int
    let dailyGoalTargetDays: Int
}

enum StatsCalculator {
    static let chartUnlockStudyDays = 7

    static func compute(
        term: Term,
        sessions: [StudySession],
        courseFilter: Course? = nil,
        activityFilter: Activity? = nil,
        streaksEnabled: Bool = true,
        focusRatingsEnabled: Bool = true,
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil,
        asOf: Date = Date(),
        provisional: ProvisionalStudy? = nil,
        goalHoursForDay: (Date) -> Double = { _ in 2.0 }
    ) -> TermStats {
        let filtered = sessions.filter { session in
            guard session.term?.persistentModelID == term.persistentModelID else { return false }
            if let courseFilter, session.course?.persistentModelID != courseFilter.persistentModelID { return false }
            if let activityFilter {
                let activityIDs = Set(session.sortedSegments.compactMap { $0.activity?.persistentModelID })
                if !activityIDs.contains(activityFilter.persistentModelID) { return false }
            }
            return true
        }

        var termDailyMap: [Date: Int] = [:]
        var dailyMap: [Date: Int] = [:]
        var courseMap: [String: (seconds: Int, color: String)] = [:]
        var activityMap: [String: Int] = [:]
        var secondsWithoutActivity = 0
        var focusPoints: [FocusTrendPoint] = []

        let rangeStartDay = rangeStart?.startOfDay
        let rangeEndDay = rangeEnd?.startOfDay

        func isInRange(_ day: Date) -> Bool {
            let start = day.startOfDay
            if let rangeStartDay, start < rangeStartDay { return false }
            if let rangeEndDay, start > rangeEndDay { return false }
            return true
        }

        func accumulate(
            startTime: Date,
            endTime: Date,
            studyTimeSeconds: Int,
            courseName: String?,
            courseColorHex: String?,
            segments: [(start: Date, duration: Int, activityName: String?)],
            focus: (id: PersistentIdentifier, rating: Int, activityNames: String, studySeconds: Int)?
        ) {
            let daily = Self.dailyBreakdown(
                startTime: startTime,
                endTime: endTime,
                totalStudySeconds: studyTimeSeconds,
                segments: segments.map { (start: $0.start, duration: $0.duration) }
            )
            var sessionInRangeSeconds = 0
            for (day, seconds) in daily {
                guard !StudyTimeAttribution.isUntrackedDay(day, trackingStart: term.trackingStartDate) else { continue }
                guard day >= term.firstDay && day <= term.lastDay else { continue }
                termDailyMap[day, default: 0] += seconds
                if isInRange(day) {
                    dailyMap[day, default: 0] += seconds
                    sessionInRangeSeconds += seconds
                }
            }

            if sessionInRangeSeconds > 0, let courseName, let courseColorHex {
                let existing = courseMap[courseName]?.seconds ?? 0
                courseMap[courseName] = (existing + sessionInRangeSeconds, courseColorHex)
            }

            let fraction = studyTimeSeconds > 0
                ? Double(sessionInRangeSeconds) / Double(studyTimeSeconds)
                : 0
            var namedTotal = 0
            for segment in segments {
                guard let name = segment.activityName else { continue }
                namedTotal += segment.duration
                activityMap[name, default: 0] += Int((Double(segment.duration) * fraction).rounded())
            }
            let unattributed = max(0, studyTimeSeconds - namedTotal)
            secondsWithoutActivity += Int((Double(unattributed) * fraction).rounded())

            if let focus, focusRatingsEnabled, sessionInRangeSeconds > 0 {
                focusPoints.append(
                    FocusTrendPoint(
                        id: focus.id,
                        date: startTime,
                        rating: Double(focus.rating),
                        courseName: courseName ?? "Unknown",
                        activityNames: focus.activityNames,
                        studySeconds: focus.studySeconds
                    )
                )
            }
        }

        for session in filtered {
            let focus: (id: PersistentIdentifier, rating: Int, activityNames: String, studySeconds: Int)?
            if let rating = session.focusRating {
                focus = (session.persistentModelID, rating, session.activityNames, session.studyTimeSeconds)
            } else {
                focus = nil
            }
            accumulate(
                startTime: session.startTime,
                endTime: session.endTime,
                studyTimeSeconds: session.studyTimeSeconds,
                courseName: session.course?.name,
                courseColorHex: session.course?.colorHex,
                segments: session.sortedSegments.map {
                    (start: $0.startTime, duration: $0.durationSeconds, activityName: $0.activity?.name)
                },
                focus: focus
            )
        }

        if let provisional, provisional.studyTimeSeconds > 0 {
            accumulate(
                startTime: provisional.startTime,
                endTime: provisional.endTime,
                studyTimeSeconds: provisional.studyTimeSeconds,
                courseName: provisional.courseName,
                courseColorHex: provisional.courseColorHex,
                segments: provisional.segments.map {
                    (start: $0.startTime, duration: $0.durationSeconds, activityName: $0.activityName)
                },
                focus: nil
            )
        }

        let statsStart = rangeStartDay ?? term.firstDay
        let statsEnd = rangeEndDay ?? term.lastDay
        let rangeDays = Calendar.app.days(from: max(statsStart, term.firstDay), through: min(statsEnd, term.lastDay))
        let dailyTotals = rangeDays.map { day in
            DailyStudyTotal(date: day, seconds: dailyMap[day.startOfDay] ?? 0)
        }

        let termDays = Calendar.app.days(from: term.firstDay, through: term.lastDay)
        let termDailyTotals = termDays.map { day in
            DailyStudyTotal(date: day, seconds: termDailyMap[day.startOfDay] ?? 0)
        }

        var weekdayTotals = Array(repeating: 0, count: 7)
        var weekdayCounts = Array(repeating: 0, count: 7)
        for (day, seconds) in dailyMap {
            guard seconds >= 60 else { continue }
            let weekday = (Calendar.app.component(.weekday, from: day) + 5) % 7 // Mon=0
            weekdayTotals[weekday] += seconds
            weekdayCounts[weekday] += 1
        }

        let weekdayAverages = zip(weekdayTotals, weekdayCounts).map { total, count in
            count > 0 ? total / count : 0
        }

        let studyDays = dailyMap.filter { $0.value >= 60 && !StudyTimeAttribution.isUntrackedDay($0.key, trackingStart: term.trackingStartDate) }
        let totalStudySeconds = studyDays.values.reduce(0, +)
        let studyDayCount = studyDays.count
        let averagePerStudyDay = studyDayCount > 0 ? totalStudySeconds / studyDayCount : 0

        let termStudyDays = termDailyMap.filter { $0.value >= 60 && !StudyTimeAttribution.isUntrackedDay($0.key, trackingStart: term.trackingStartDate) }
        let termStudyDayCount = termStudyDays.count

        let asOfDay = min(asOf.startOfDay, term.lastDay.startOfDay)

        let (current, longest) = streaksEnabled
            ? computeStreaks(dailyMap: termDailyMap, trackingStart: term.trackingStartDate, termLastDay: term.lastDay, asOfDay: asOfDay)
            : (0, 0)

        let focusTrend: [FocusTrendPoint] = focusRatingsEnabled
            ? focusPoints.sorted { $0.date < $1.date }
            : []

        let todayStudySeconds = term.contains(date: asOfDay) ? (termDailyMap[asOfDay] ?? 0) : 0

        let goalDays = studyDays.filter { $0.value >= Int(goalHoursForDay($0.key) * 3600) }.count
        let goalTargetDays = studyDayCount

        return TermStats(
            totalStudySeconds: totalStudySeconds,
            averagePerStudyDaySeconds: averagePerStudyDay,
            currentStreak: current,
            longestStreak: longest,
            studyDayCount: studyDayCount,
            termStudyDayCount: termStudyDayCount,
            dailyTotals: dailyTotals,
            termDailyTotals: termDailyTotals,
            courseTotals: courseMap.map { CourseStudyTotal(courseID: nil, name: $0.key, colorHex: $0.value.color, seconds: $0.value.seconds) }
                .sorted { $0.seconds > $1.seconds },
            activityTotals: activityMap.map { ActivityStudyTotal(name: $0.key, seconds: $0.value) }
                .filter { $0.seconds > 0 }
                .sorted { $0.seconds > $1.seconds },
            secondsWithoutActivity: secondsWithoutActivity,
            focusTrend: focusTrend,
            weekdayAverages: weekdayAverages,
            todayStudySeconds: todayStudySeconds,
            dailyGoalProgressDays: goalDays,
            dailyGoalTargetDays: goalTargetDays
        )
    }

    private static func computeStreaks(
        dailyMap: [Date: Int],
        trackingStart: Date,
        termLastDay: Date,
        asOfDay: Date
    ) -> (current: Int, longest: Int) {
        let studyDays = Set(dailyMap.filter { $0.value >= 60 && !StudyTimeAttribution.isUntrackedDay($0.key, trackingStart: trackingStart) }.map(\.key))
        guard !studyDays.isEmpty else { return (0, 0) }

        var longest = 0
        var run = 0

        let days = Calendar.app.days(from: trackingStart, through: min(termLastDay, asOfDay))
        for day in days {
            if studyDays.contains(day.startOfDay) {
                run += 1
                longest = max(longest, run)
            } else if !StudyTimeAttribution.isUntrackedDay(day, trackingStart: trackingStart) {
                run = 0
            }
        }

        var streak = 0
        var cursor = asOfDay.startOfDay
        while cursor >= trackingStart.startOfDay {
            if studyDays.contains(cursor) {
                streak += 1
            } else if !StudyTimeAttribution.isUntrackedDay(cursor, trackingStart: trackingStart) {
                break
            }
            guard let prev = Calendar.app.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return (streak, longest)
    }

    /// Prefer real study intervals when they account for the session. That keeps
    /// a late-night pause from sliding study time onto the wrong calendar day.
    /// Otherwise fall back to treating study as contiguous from the start.
    private static func dailyBreakdown(
        startTime: Date,
        endTime: Date,
        totalStudySeconds: Int,
        segments: [(start: Date, duration: Int)]
    ) -> [Date: Int] {
        let covered = segments.reduce(0) { $0 + max(0, $1.duration) }
        guard covered > 0, abs(covered - totalStudySeconds) <= 2 else {
            return StudyTimeAttribution.dailySeconds(
                startTime: startTime,
                endTime: endTime,
                totalStudySeconds: totalStudySeconds
            )
        }
        let intervals = segments.compactMap { segment -> (start: Date, end: Date)? in
            guard segment.duration > 0 else { return nil }
            return (segment.start, segment.start.addingTimeInterval(TimeInterval(segment.duration)))
        }
        var daily = StudyTimeAttribution.dailySeconds(intervals: intervals)
        let sum = daily.values.reduce(0, +)
        if sum != totalStudySeconds, let lastDay = daily.keys.sorted().last {
            daily[lastDay, default: 0] += totalStudySeconds - sum
        }
        return daily
    }
}
