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
    private var screenSleepObserver: NSObjectProtocol?
    private let snapshotKey = "sessionSnapshot"

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
            Task { @MainActor in SessionEngine.shared.pause() }
        }
        screenSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in SessionEngine.shared.pause() }
        }
    }

    func start(term: Term, course: Course, activityName: String?) {
        reset()
        self.term = term
        self.course = course
        self.currentActivityName = activityName
        self.sessionStartTime = Date()
        self.state = .studying
        self.studySegmentStart = Date()
        self.lastStudyEndTime = nil
        if let activityName {
            segments.append(LiveActivitySegment(activityName: activityName, startTime: Date()))
        }
        startTicking()
        persistSnapshot()
    }

    func pause() {
        guard state == .studying else { return }
        let now = Date()
        let delta = currentStudyingDelta(at: now)
        finalizeOpenSegment(at: now)
        accumulatedStudySeconds += delta
        studySegmentStart = nil
        lastStudyEndTime = now
        state = .paused
        stopTicking()
        persistSnapshot()
    }

    func resume() {
        guard state == .paused else { return }
        state = .studying
        studySegmentStart = Date()
        if let currentActivityName, segments.last?.activityName != currentActivityName {
            segments.append(LiveActivitySegment(activityName: currentActivityName, startTime: Date()))
        }
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
        if let name, segments.last?.activityName != name {
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

    func restore(from snapshot: SessionSnapshot, context: ModelContext) {
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

        if state == .studying {
            startTicking()
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

        for live in Self.normalizedSegments(segments) {
            guard let name = live.activityName, live.durationSeconds > 0 else { continue }
            let activity = fetchOrCreateActivity(named: name, context: context)
            let segment = ActivitySegment(startTime: live.startTime, durationSeconds: live.durationSeconds)
            segment.activity = activity
            segment.session = session
            context.insert(segment)
        }

        reset()
        clearSnapshot()
        return session
    }

    private func reset() {
        stopTicking()
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
            lastStudyEndTime: lastStudyEndTime
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

    static func normalizedSegments(_ segments: [LiveActivitySegment]) -> [LiveActivitySegment] {
        var merged: [LiveActivitySegment] = []
        for segment in segments {
            guard segment.durationSeconds > 0, let name = segment.activityName else { continue }
            if var last = merged.last, last.activityName == name {
                last.durationSeconds += segment.durationSeconds
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
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
