import Foundation
import AppKit
import SwiftData
import SwiftUI

enum SessionEngineState: String, Codable {
    case idle
    case studying
    case paused
}

struct LiveActivitySegment: Codable, Identifiable, Equatable {
    var id: UUID
    var activityName: String?
    var startTime: Date
    var durationSeconds: Int

    init(id: UUID = UUID(), activityName: String?, startTime: Date, durationSeconds: Int = 0) {
        self.id = id
        self.activityName = activityName
        self.startTime = startTime
        self.durationSeconds = durationSeconds
    }
}

struct SessionSnapshot: Codable {
    var termID: String
    var courseID: String
    var courseName: String
    var courseColorHex: String
    var activityName: String?
    var state: SessionEngineState
    var sessionStartTime: Date
    var accumulatedStudySeconds: Int
    var segments: [LiveActivitySegment]
    var focusedMode: Bool
    var lastStudyEndTime: Date?
    /// Start of the in-progress study stint. Nil while paused.
    var openSegmentStart: Date?
    /// When this snapshot was written. Used so time after the app quits is not counted as study.
    var savedAt: Date?

    enum CodingKeys: String, CodingKey {
        case termID, courseID, courseName, courseColorHex, activityName, state
        case sessionStartTime, accumulatedStudySeconds, segments, focusedMode, lastStudyEndTime
        case openSegmentStart, savedAt
    }

    init(
        termID: String,
        courseID: String,
        courseName: String,
        courseColorHex: String,
        activityName: String?,
        state: SessionEngineState,
        sessionStartTime: Date,
        accumulatedStudySeconds: Int,
        segments: [LiveActivitySegment],
        focusedMode: Bool,
        lastStudyEndTime: Date?,
        openSegmentStart: Date? = nil,
        savedAt: Date? = nil
    ) {
        self.termID = termID
        self.courseID = courseID
        self.courseName = courseName
        self.courseColorHex = courseColorHex
        self.activityName = activityName
        self.state = state
        self.sessionStartTime = sessionStartTime
        self.accumulatedStudySeconds = accumulatedStudySeconds
        self.segments = segments
        self.focusedMode = focusedMode
        self.lastStudyEndTime = lastStudyEndTime
        self.openSegmentStart = openSegmentStart
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termID = try container.decode(String.self, forKey: .termID)
        courseID = try container.decode(String.self, forKey: .courseID)
        courseName = try container.decode(String.self, forKey: .courseName)
        courseColorHex = try container.decode(String.self, forKey: .courseColorHex)
        activityName = try container.decodeIfPresent(String.self, forKey: .activityName)
        state = try container.decode(SessionEngineState.self, forKey: .state)
        sessionStartTime = try container.decode(Date.self, forKey: .sessionStartTime)
        accumulatedStudySeconds = try container.decode(Int.self, forKey: .accumulatedStudySeconds)
        segments = try container.decode([LiveActivitySegment].self, forKey: .segments)
        focusedMode = try container.decode(Bool.self, forKey: .focusedMode)
        lastStudyEndTime = try container.decodeIfPresent(Date.self, forKey: .lastStudyEndTime)
        openSegmentStart = try container.decodeIfPresent(Date.self, forKey: .openSegmentStart)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(termID, forKey: .termID)
        try container.encode(courseID, forKey: .courseID)
        try container.encode(courseName, forKey: .courseName)
        try container.encode(courseColorHex, forKey: .courseColorHex)
        try container.encodeIfPresent(activityName, forKey: .activityName)
        try container.encode(state, forKey: .state)
        try container.encode(sessionStartTime, forKey: .sessionStartTime)
        try container.encode(accumulatedStudySeconds, forKey: .accumulatedStudySeconds)
        try container.encode(segments, forKey: .segments)
        try container.encode(focusedMode, forKey: .focusedMode)
        try container.encodeIfPresent(lastStudyEndTime, forKey: .lastStudyEndTime)
        try container.encodeIfPresent(openSegmentStart, forKey: .openSegmentStart)
        try container.encodeIfPresent(savedAt, forKey: .savedAt)
    }
}

@Observable
@MainActor
final class SessionEngine {
    static let shared = SessionEngine()

    private(set) var state: SessionEngineState = .idle
    private(set) var accumulatedStudySeconds: Int = 0
    private(set) var sessionStartTime: Date?
    private(set) var term: Term?
    private(set) var course: Course?
    private(set) var currentActivityName: String?
    private(set) var segments: [LiveActivitySegment] = []
    private(set) var focusedMode = false
    private(set) var tickCount = 0
    private(set) var shouldPresentEndSheet = false
    private(set) var lastStudyEndTime: Date?

    private var tickTask: Task<Void, Never>?
    private var studySegmentStart: Date?
    private var screenLockObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var lockPauseTask: Task<Void, Never>?
    private var lockStartedAt: Date?
    private let snapshotKey = "sessionSnapshot"
    private let lockPauseDelay: TimeInterval = 15 * 60

    var isActive: Bool { state != .idle }

    var displayStudySeconds: Int {
        if state == .studying {
            return accumulatedStudySeconds + currentStudyingDelta()
        }
        return accumulatedStudySeconds
    }

    private init() {
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in SessionEngine.shared.beginLockGracePeriod() }
        }
        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in SessionEngine.shared.endLockGracePeriod() }
        }
        screenSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in SessionEngine.shared.beginLockGracePeriod() }
        }
        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in SessionEngine.shared.endLockGracePeriod() }
        }
    }

    func start(term: Term, course: Course, activityName: String?) {
        reset()
        self.term = term
        self.course = course
        self.currentActivityName = activityName
        let now = Date()
        self.sessionStartTime = now
        self.state = .studying
        self.studySegmentStart = now
        self.lastStudyEndTime = nil
        segments.append(LiveActivitySegment(activityName: activityName, startTime: now))
        startTicking()
        persistSnapshot()
    }

    func pause() {
        pause(at: Date())
    }

    private func pause(at date: Date) {
        guard state == .studying else { return }
        let delta = currentStudyingDelta(at: date)
        finalizeOpenSegment(at: date)
        accumulatedStudySeconds += delta
        studySegmentStart = nil
        lastStudyEndTime = date
        state = .paused
        stopTicking()
        persistSnapshot()
    }

    private func beginLockGracePeriod() {
        guard lockStartedAt == nil else { return }
        let lockedAt = Date()
        lockStartedAt = lockedAt
        lockPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            self?.pauseForLongLock(startedAt: lockedAt)
        }
    }

    private func endLockGracePeriod() {
        guard let lockedAt = lockStartedAt else { return }
        if Date().timeIntervalSince(lockedAt) >= lockPauseDelay {
            pauseForLongLock(startedAt: lockedAt)
        }
        lockPauseTask?.cancel()
        lockPauseTask = nil
        lockStartedAt = nil
    }

    private func pauseForLongLock(startedAt: Date) {
        let pauseDate = startedAt.addingTimeInterval(lockPauseDelay)
        pause(at: min(Date(), pauseDate))
    }

    func resume() {
        guard state == .paused else { return }
        let now = Date()
        state = .studying
        studySegmentStart = now
        // A new stint, even for the same activity, so a pause that crosses midnight
        // is not treated as continuous study.
        segments.append(LiveActivitySegment(activityName: currentActivityName, startTime: now))
        startTicking()
        persistSnapshot()
    }

    func changeCourse(_ course: Course) {
        self.course = course
        persistSnapshot()
    }

    func changeActivity(_ name: String?) {
        if currentActivityName == name { return }

        guard state == .studying else {
            currentActivityName = name
            persistSnapshot()
            return
        }
        let now = Date()
        let delta = currentStudyingDelta(at: now)
        finalizeOpenSegment(at: now)
        accumulatedStudySeconds += delta
        lastStudyEndTime = now
        currentActivityName = name
        if segments.isEmpty || segments.last?.activityName != name {
            segments.append(LiveActivitySegment(activityName: name, startTime: now))
        }
        studySegmentStart = now
        persistSnapshot()
    }

    func pauseForEnd() {
        if state == .studying {
            let now = Date()
            let delta = currentStudyingDelta(at: now)
            finalizeOpenSegment(at: now)
            accumulatedStudySeconds += delta
            studySegmentStart = nil
            lastStudyEndTime = now
        }
        state = .paused
        stopTicking()
        persistSnapshot()
    }

    func requestEndSheetPresentation() {
        pauseForEnd()
        shouldPresentEndSheet = true
    }

    func clearEndSheetPresentationRequest() {
        shouldPresentEndSheet = false
    }

    func toggleFocusedMode() {
        focusedMode.toggle()
        persistSnapshot()
    }

    func exitFocusedMode() {
        guard focusedMode else { return }
        focusedMode = false
        persistSnapshot()
    }

    func discard() {
        reset()
        clearSnapshot()
    }

    func completedStudySecondsForSave() -> Int {
        displayStudySeconds
    }

    var effectiveStudyEndTime: Date? {
        if state == .studying {
            return Date()
        }
        return lastStudyEndTime
    }

    func loadSnapshotIfNeeded() -> SessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data)
        else { return nil }
        return snapshot.state == .idle ? nil : snapshot
    }

    /// `continuing` keeps the session running from now. Time while the app was
    /// closed is not counted. Pass false to freeze the session at the last
    /// snapshot, which is what "save as-is" uses after an overnight quit.
    func restore(from snapshot: SessionSnapshot, context: ModelContext, continuing: Bool) {
        let termFetch = FetchDescriptor<Term>()
        let courseFetch = FetchDescriptor<Course>()
        let terms = (try? context.fetch(termFetch)) ?? []
        let courses = (try? context.fetch(courseFetch)) ?? []

        guard let term = terms.first(where: { String(describing: $0.persistentModelID) == snapshot.termID }),
              let course = courses.first(where: { String(describing: $0.persistentModelID) == snapshot.courseID })
        else {
            clearSnapshot()
            return
        }

        self.term = term
        self.course = course
        self.currentActivityName = snapshot.activityName
        self.state = snapshot.state
        self.sessionStartTime = snapshot.sessionStartTime
        self.accumulatedStudySeconds = snapshot.accumulatedStudySeconds
        self.segments = snapshot.segments
        self.focusedMode = snapshot.focusedMode
        self.lastStudyEndTime = snapshot.lastStudyEndTime
        creditOpenSegment(from: snapshot)

        guard snapshot.state == .studying else { return }
        if continuing {
            let now = Date()
            studySegmentStart = now
            segments.append(LiveActivitySegment(activityName: currentActivityName, startTime: now))
            startTicking()
        } else {
            state = .paused
            studySegmentStart = nil
            if let savedAt = snapshot.savedAt {
                lastStudyEndTime = min(savedAt, Date())
            }
        }
    }

    func saveAsIs(context: ModelContext) -> StudySession? {
        guard let term, let course, let sessionStartTime else { return nil }
        pauseForEnd()
        let endTime = lastStudyEndTime ?? sessionStartTime.addingTimeInterval(TimeInterval(accumulatedStudySeconds))
        var studySeconds = accumulatedStudySeconds
        studySeconds = StudyTimeAttribution.clipToTermLastDay(
            startTime: sessionStartTime,
            endTime: endTime,
            totalStudySeconds: studySeconds,
            termLastDay: term.lastDay
        )
        let session = StudySession(
            startTime: sessionStartTime,
            endTime: endTime,
            studyTimeSeconds: studySeconds
        )
        session.term = term
        session.course = course
        context.insert(session)
        insertActivitySegments(into: session, context: context)

        reset()
        clearSnapshot()
        return session
    }

    private func reset() {
        stopTicking()
        lockPauseTask?.cancel()
        lockPauseTask = nil
        lockStartedAt = nil
        state = .idle
        accumulatedStudySeconds = 0
        sessionStartTime = nil
        term = nil
        course = nil
        currentActivityName = nil
        segments = []
        focusedMode = false
        studySegmentStart = nil
        lastStudyEndTime = nil
    }

    private func currentStudyingDelta() -> Int {
        currentStudyingDelta(at: Date())
    }

    private func currentStudyingDelta(at date: Date) -> Int {
        guard let studySegmentStart else { return 0 }
        return max(0, Int(date.timeIntervalSince(studySegmentStart)))
    }

    private func finalizeOpenSegment(at date: Date = Date()) {
        guard let studySegmentStart else { return }
        let delta = max(0, Int(date.timeIntervalSince(studySegmentStart)))
        if var last = segments.last, last.activityName == currentActivityName {
            last.durationSeconds += delta
            segments[segments.count - 1] = last
        }
        self.studySegmentStart = nil
    }

    private func startTicking() {
        stopTicking()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        tickCount += 1
        persistSnapshot()
    }

    private func persistSnapshot() {
        guard let term, let course, let sessionStartTime, state != .idle else {
            clearSnapshot()
            return
        }
        let snapshot = SessionSnapshot(
            termID: String(describing: term.persistentModelID),
            courseID: String(describing: course.persistentModelID),
            courseName: course.name,
            courseColorHex: course.colorHex,
            activityName: currentActivityName,
            state: state,
            sessionStartTime: sessionStartTime,
            accumulatedStudySeconds: accumulatedStudySeconds,
            segments: segments,
            focusedMode: focusedMode,
            lastStudyEndTime: lastStudyEndTime,
            openSegmentStart: state == .studying ? studySegmentStart : nil,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    private func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    private func fetchOrCreateActivity(named name: String, context: ModelContext) -> Activity {
        let descriptor = FetchDescriptor<Activity>()
        let activities = (try? context.fetch(descriptor)) ?? []
        if let existing = activities.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let activity = Activity(name: name)
        context.insert(activity)
        return activity
    }

    func provisionalStudy(at date: Date = Date()) -> ProvisionalStudy? {
        guard isActive, let sessionStartTime, let course else { return nil }
        let seconds = displayStudySeconds
        guard seconds > 0 else { return nil }
        let end = effectiveStudyEndTime ?? date
        var recorded: [ProvisionalSegment] = []
        for (index, segment) in segments.enumerated() {
            var duration = segment.durationSeconds
            if state == .studying, index == segments.count - 1 {
                duration += currentStudyingDelta(at: date)
            }
            guard duration > 0 else { continue }
            recorded.append(
                ProvisionalSegment(
                    startTime: segment.startTime,
                    durationSeconds: duration,
                    activityName: segment.activityName
                )
            )
        }
        return ProvisionalStudy(
            startTime: sessionStartTime,
            endTime: end,
            studyTimeSeconds: seconds,
            courseName: course.name,
            courseColorHex: course.colorHex,
            segments: recorded
        )
    }

    func insertActivitySegments(into session: StudySession, context: ModelContext) {
        for live in Self.normalizedSegments(segments) where live.durationSeconds > 0 {
            let segment = ActivitySegment(startTime: live.startTime, durationSeconds: live.durationSeconds)
            if let name = live.activityName {
                segment.activity = fetchOrCreateActivity(named: name, context: context)
            }
            segment.session = session
            context.insert(segment)
        }
    }

    /// Credits the stint that was open when the snapshot was saved, and not the
    /// time after the app quit.
    private func creditOpenSegment(from snapshot: SessionSnapshot) {
        guard snapshot.state == .studying, let openStart = snapshot.openSegmentStart else { return }
        let creditEnd = min(snapshot.savedAt ?? openStart, Date())
        let delta = max(0, Int(creditEnd.timeIntervalSince(openStart)))
        guard delta > 0 else { return }
        accumulatedStudySeconds += delta
        if var last = segments.last,
           last.activityName == currentActivityName,
           abs(last.startTime.timeIntervalSince(openStart)) < 1 {
            last.durationSeconds += delta
            segments[segments.count - 1] = last
        } else {
            segments.append(
                LiveActivitySegment(
                    activityName: currentActivityName,
                    startTime: openStart,
                    durationSeconds: delta
                )
            )
        }
    }

    static func normalizedSegments(_ segments: [LiveActivitySegment]) -> [LiveActivitySegment] {
        var merged: [LiveActivitySegment] = []
        for segment in segments {
            guard segment.durationSeconds > 0 else { continue }
            if var last = merged.last, last.activityName == segment.activityName {
                let lastEnd = last.startTime.addingTimeInterval(TimeInterval(last.durationSeconds))
                if abs(segment.startTime.timeIntervalSince(lastEnd)) < 2 {
                    last.durationSeconds += segment.durationSeconds
                    merged[merged.count - 1] = last
                    continue
                }
            }
            merged.append(segment)
        }
        return merged
    }
}

private struct SessionEngineKey: EnvironmentKey {
    static let defaultValue = SessionEngine.shared
}

extension EnvironmentValues {
    var sessionEngine: SessionEngine {
        get { self[SessionEngineKey.self] }
        set { self[SessionEngineKey.self] = newValue }
    }
}
