import Foundation

// Keep these identifiers stable so existing installations retain their data and widgets.
enum DailyShared {
    static let appGroup = "group.com.example.Daylight"
    static let widgetKind = "DaylightWidget"

    static func dataURL() throws -> URL {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return directory.appendingPathComponent("todos.json")
    }

    static func nextWidgetRefresh(after date: Date, calendar: Calendar = .current) -> Date {
        let periodic = date.addingTimeInterval(30 * 60)
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? periodic
        return min(periodic, midnight)
    }
}

struct Subtask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
    var createdAt = Date()
    var completedAt: Date?
}

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
    var createdAt: Date?
    var completedAt: Date?
    var archivedAt: Date?
    var subtasks: [Subtask] = []

    init(id: UUID = UUID(), title: String, completed: Bool = false, createdAt: Date? = Date(), completedAt: Date? = nil, archivedAt: Date? = nil, subtasks: [Subtask] = []) {
        self.id = id
        self.title = title
        self.completed = completed
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.subtasks = subtasks
    }

    private enum CodingKeys: String, CodingKey { case id, title, completed, createdAt, completedAt, archivedAt, subtasks }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        completed = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        subtasks = try values.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
    }
}

struct TaskRepository {
    let url: URL

    static func shared() throws -> Self { Self(url: try DailyShared.dataURL()) }

    func read() throws -> [Todo] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let tasks = try JSONDecoder().decode([Todo].self, from: Data(contentsOf: url))
        guard Set(tasks.map(\.id)).count == tasks.count, tasks.allSatisfy({ Set($0.subtasks.map(\.id)).count == $0.subtasks.count }) else { throw CocoaError(.fileReadCorruptFile) }
        return tasks
    }

    // Each edit starts with the current file, not the calling window's old snapshot.
    // File coordination serializes participating writers; atomic replacement also
    // lets the widget read either the old or new complete JSON, never a partial save.
    @discardableResult
    func update(_ change: (inout [Todo]) -> Void) throws -> [Todo] {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var outcome: Result<[Todo], Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                let current = TaskRepository(url: coordinatedURL)
                let original = try current.read()
                var updated = original
                change(&updated)
                if updated != original {
                    if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                        try Data(contentsOf: coordinatedURL).write(to: coordinatedURL.appendingPathExtension("bak"), options: .atomic)
                    }
                    try JSONEncoder().encode(updated).write(to: coordinatedURL, options: .atomic)
                }
                return updated
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        return try outcome.get()
    }
    func backupForUpdate() throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { file in
            result = Result {
                let tasks = try TaskRepository(url: file).read()
                let data = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : try JSONEncoder().encode(tasks)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file.appendingPathExtension("update.bak"), options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

}
