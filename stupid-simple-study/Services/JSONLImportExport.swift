import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct JSONLActivitySegment: Codable {
    var name: String
    var start_time: String
    var duration_seconds: Int
}

struct JSONLSessionRecord: Codable {
    var term: String
    var course: String
    var start_time: String
    var end_time: String
    var study_time_seconds: Int
    var activities: [JSONLActivitySegment]
    var note: String?
    var focus_rating: Int?
}

enum JSONLCodec {
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func encode(sessions: [StudySession]) throws -> String {
        let lines = try sessions.sorted { $0.startTime < $1.startTime }.map { session -> String in
            let record = JSONLSessionRecord(
                term: session.term?.name ?? "",
                course: session.course?.name ?? "",
                start_time: isoFormatter.string(from: session.startTime),
                end_time: isoFormatter.string(from: session.endTime),
                study_time_seconds: session.studyTimeSeconds,
                activities: session.sortedSegments.compactMap { segment in
                    guard let name = segment.activity?.name else { return nil }
                    return JSONLActivitySegment(
                        name: name,
                        start_time: isoFormatter.string(from: segment.startTime),
                        duration_seconds: segment.durationSeconds
                    )
                },
                note: session.note.isEmpty ? nil : session.note,
                focus_rating: session.focusRating
            )
            let data = try JSONEncoder().encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                throw JSONLError.encodingFailed
            }
            return line
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    static func decode(text: String) throws -> [JSONLSessionRecord] {
        let lines = text.split(whereSeparator: \.isNewline)
        return try lines.filter { !$0.isEmpty }.map { line in
            let data = Data(line.utf8)
            return try JSONDecoder().decode(JSONLSessionRecord.self, from: data)
        }
    }
}

enum JSONLError: LocalizedError {
    case encodingFailed
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Failed to encode export data."
        case .importFailed(let msg): msg
        }
    }
}

@MainActor
enum JSONLImportExport {
    /// Dynamic type so the save panel keeps a `.jsonl` extension instead of appending `.json`.
    private static let jsonLinesType = UTType(filenameExtension: "jsonl", conformingTo: .json) ?? .json

    static func exportAll(context: ModelContext) {
        let descriptor = FetchDescriptor<StudySession>()
        let sessions = (try? context.fetch(descriptor)) ?? []
        guard let text = try? JSONLCodec.encode(sessions: sessions) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.jsonLinesType]
        panel.nameFieldStringValue = "stupid-simple-study-export.jsonl"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func importReplace(context: ModelContext, termContext: TermContext, completion: @escaping (Result<Void, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.jsonLinesType, .json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                try performImport(text: text, context: context, termContext: termContext)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func performImport(text: String, context: ModelContext, termContext: TermContext) throws {
        let records = try JSONLCodec.decode(text: text)

        // Clear existing data
        try deleteAll(context: context)

        var termCache: [String: Term] = [:]
        var courseCache: [String: Course] = [:]
        var activityCache: [String: Activity] = [:]

        for record in records {
            let term = termCache[record.term] ?? {
                // Derive term dates from session dates if term unknown — use session day as both bounds initially
                guard let start = JSONLCodec.isoFormatter.date(from: record.start_time) else { return nil }
                let day = start.startOfDay
                let term = Term(name: record.term, firstDay: day, lastDay: day)
                context.insert(term)
                termCache[record.term] = term
                return term
            }()

            guard let term else { continue }

            if let start = JSONLCodec.isoFormatter.date(from: record.start_time) {
                let day = start.startOfDay
                if day < term.firstDay { term.firstDay = day }
                if day > term.lastDay { term.lastDay = day }
            }

            let courseKey = "\(record.term)|\(record.course)"
            let course = courseCache[courseKey] ?? {
                let used = Set(term.courses.map { $0.colorHex.uppercased() })
                let course = Course(name: record.course, colorHex: CourseColorPalette.nextColor(usedHexes: used), sortOrder: term.courses.count)
                course.term = term
                term.courses.append(course)
                context.insert(course)
                courseCache[courseKey] = course
                return course
            }()

            guard let start = JSONLCodec.isoFormatter.date(from: record.start_time),
                  let end = JSONLCodec.isoFormatter.date(from: record.end_time)
            else { continue }

            let session = StudySession(
                startTime: start,
                endTime: end,
                studyTimeSeconds: record.study_time_seconds,
                note: record.note ?? "",
                focusRating: record.focus_rating
            )
            session.term = term
            session.course = course
            context.insert(session)

            for activityRecord in record.activities {
                let activity = activityCache[activityRecord.name] ?? {
                    let activity = Activity(name: activityRecord.name)
                    context.insert(activity)
                    activityCache[activityRecord.name] = activity
                    return activity
                }()
                guard let segStart = JSONLCodec.isoFormatter.date(from: activityRecord.start_time) else { continue }
                let segment = ActivitySegment(startTime: segStart, durationSeconds: activityRecord.duration_seconds)
                segment.activity = activity
                segment.session = session
                context.insert(segment)
            }
        }

        try context.save()

        let termDescriptor = FetchDescriptor<Term>()
        let terms = (try? context.fetch(termDescriptor)) ?? []
        let today = Date().startOfDay
        let active = terms.first { $0.contains(date: today) }
        termContext.refresh(terms: terms, preferredActive: active)
    }

    private static func deleteAll(context: ModelContext) throws {
        try deleteFetched(ActivitySegment.self, context: context)
        try deleteFetched(StudySession.self, context: context)
        try deleteFetched(Course.self, context: context)
        try deleteFetched(Term.self, context: context)
        try deleteFetched(Activity.self, context: context)
        try context.save()
    }

    private static func deleteFetched<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        for item in items {
            context.delete(item)
        }
    }

    static func hasLocalData(context: ModelContext) -> Bool {
        let termCount = (try? context.fetchCount(FetchDescriptor<Term>())) ?? 0
        let sessionCount = (try? context.fetchCount(FetchDescriptor<StudySession>())) ?? 0
        return termCount > 0 || sessionCount > 0
    }

    static func resetSessionsForTerm(_ term: Term, context: ModelContext) throws {
        for session in term.sessions {
            context.delete(session)
        }
        try context.save()
    }

    static func resetAllAppData(context: ModelContext) throws {
        try deleteAll(context: context)
    }
}
