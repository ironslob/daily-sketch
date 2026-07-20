import Foundation

/// Local unpublished sketch metadata. Image bytes live in `DraftImageStoring`, never UserDefaults.
struct LocalDraft: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let localSessionId: UUID
    var serverSessionId: UUID?
    let promptId: UUID
    let promptWords: [String]
    let promptAccessibilityLabel: String
    let promptDate: Date
    let timerMode: String
    let selectedTimerSeconds: Int?
    let sessionStartedAt: Date
    var imageFileName: String
    var caption: String?
    let createdAt: Date
    var updatedAt: Date
    var pendingAuthentication: Bool
    var pendingPublication: Bool
    /// Stable Idempotency-Key for duplicate-safe Submission create retries.
    var publicationIdempotencyKey: String? = nil
    var uploadId: UUID? = nil
    /// True after a successful signed upload and completeUpload call.
    var uploadCompleted: Bool = false

    var isRecoverable: Bool {
        !imageFileName.isEmpty
    }

    var timerDisplayLabel: String {
        if timerMode == "no_timer" {
            return "No timer"
        }
        if let seconds = selectedTimerSeconds {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return "No timer"
    }
}

protocol DraftStoring: Sendable {
    func list() throws -> [LocalDraft]
    func save(_ draft: LocalDraft) throws
    func delete(id: UUID) throws
    func mostRecentRecoverable() throws -> LocalDraft?
    func purgeExpired(retentionDays: Int, now: Date) throws -> [LocalDraft]
}

struct DraftStore: DraftStoring {
    static let defaultRetentionDays = 30

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent("DailySketch", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.fileURL = directory.appendingPathComponent("local_drafts.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func list() throws -> [LocalDraft] {
        try loadAll().sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ draft: LocalDraft) throws {
        var drafts = try loadAll()
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        try writeAll(drafts)
    }

    func delete(id: UUID) throws {
        var drafts = try loadAll()
        drafts.removeAll { $0.id == id }
        try writeAll(drafts)
    }

    func mostRecentRecoverable() throws -> LocalDraft? {
        try list().first { $0.isRecoverable }
    }

    func purgeExpired(retentionDays: Int, now: Date) throws -> [LocalDraft] {
        let cutoff = now.addingTimeInterval(-TimeInterval(retentionDays * 24 * 60 * 60))
        var drafts = try loadAll()
        let expired = drafts.filter { $0.updatedAt < cutoff }
        guard !expired.isEmpty else { return [] }
        let expiredIDs = Set(expired.map(\.id))
        drafts.removeAll { expiredIDs.contains($0.id) }
        try writeAll(drafts)
        return expired
    }

    private func loadAll() throws -> [LocalDraft] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }
        return try decoder.decode([LocalDraft].self, from: data)
    }

    private func writeAll(_ drafts: [LocalDraft]) throws {
        let data = try encoder.encode(drafts)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }
}

final class InMemoryDraftStore: DraftStoring, @unchecked Sendable {
    private var drafts: [UUID: LocalDraft] = [:]

    func list() throws -> [LocalDraft] {
        Array(drafts.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ draft: LocalDraft) throws {
        drafts[draft.id] = draft
    }

    func delete(id: UUID) throws {
        drafts.removeValue(forKey: id)
    }

    func mostRecentRecoverable() throws -> LocalDraft? {
        try list().first { $0.isRecoverable }
    }

    func purgeExpired(retentionDays: Int, now: Date) throws -> [LocalDraft] {
        let cutoff = now.addingTimeInterval(-TimeInterval(retentionDays * 24 * 60 * 60))
        let expired = drafts.values.filter { $0.updatedAt < cutoff }
        for draft in expired {
            drafts.removeValue(forKey: draft.id)
        }
        return expired
    }
}
