import Foundation

enum ActiveSessionLifecycle: String, Codable, Sendable, Equatable {
    case active
    case paused
    case timerCompleted
    case readyForPhoto
    case abandoned
}

struct ActiveSessionSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var serverSessionId: UUID?
    let promptId: UUID
    let promptWords: [String]
    let promptAccessibilityLabel: String
    let timerMode: String
    let selectedTimerSeconds: Int?
    let startedAt: Date
    var pausedAt: Date?
    var pausedTotalSeconds: Int
    var lifecycle: ActiveSessionLifecycle
    var syncPending: Bool
    var isGuest: Bool

    var isRecoverable: Bool {
        switch lifecycle {
        case .active, .paused, .timerCompleted, .readyForPhoto:
            return true
        case .abandoned:
            return false
        }
    }
}

protocol ActiveSessionStoring: Sendable {
    func load() throws -> ActiveSessionSnapshot?
    func save(_ snapshot: ActiveSessionSnapshot) throws
    func clear() throws
}

struct ActiveSessionStore: ActiveSessionStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent("DailySketch", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.fileURL = directory.appendingPathComponent("active_sketch_session.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> ActiveSessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ActiveSessionSnapshot.self, from: data)
    }

    func save(_ snapshot: ActiveSessionSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

final class InMemoryActiveSessionStore: ActiveSessionStoring, @unchecked Sendable {
    private var snapshot: ActiveSessionSnapshot?

    func load() throws -> ActiveSessionSnapshot? {
        snapshot
    }

    func save(_ snapshot: ActiveSessionSnapshot) throws {
        self.snapshot = snapshot
    }

    func clear() throws {
        snapshot = nil
    }
}
