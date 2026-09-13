import Foundation
import SwiftData

enum AppModelContainer {
    static let schema = Schema([
        Term.self,
        Course.self,
        Activity.self,
        StudySession.self,
        ActivitySegment.self,
    ])

    private static let wipeMarkerName = "pending-store-wipe"

    private static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private static var wipeMarkerURL: URL {
        applicationSupportURL.appendingPathComponent(wipeMarkerName)
    }

    static func make(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            if inMemory {
                fatalError("Could not create ModelContainer: \(error)")
            }
            deletePersistentStoreFiles()
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    static func requestStoreWipeOnNextLaunch() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        fileManager.createFile(atPath: wipeMarkerURL.path, contents: Data())
    }

    static func removeStoreIfRequested() {
        guard FileManager.default.fileExists(atPath: wipeMarkerURL.path) else { return }
        deletePersistentStoreFiles()
        try? FileManager.default.removeItem(at: wipeMarkerURL)
    }

    private static func deletePersistentStoreFiles() {
        let configuration = ModelConfiguration(schema: schema)
        let storeURL = configuration.url
        let fileManager = FileManager.default
        let relatedURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]
        for url in relatedURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
