import Foundation
import Combine

struct JournalEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    var modifiedAt = Date()
}

// Notes and their draft are independent from todos and WidgetKit.
@MainActor final class JournalStore: ObservableObject {
    @Published var draft = "" { didSet { scheduleSave() } }
    @Published private(set) var entries: [JournalEntry] = []
    @Published var error: String?
    private let url: URL?
    private var pending: DispatchWorkItem?
    private var unreadable = false
    private var saved = Document()

    private struct Document: Codable, Equatable {
        var draft = ""
        var entries: [JournalEntry] = []
    }

    init(url: URL? = nil) {
        self.url = url ?? (try? DailyShared.dataURL().deletingLastPathComponent().appendingPathComponent("journal.json"))
        do {
            guard let url = self.url else { throw CocoaError(.fileNoSuchFile) }
            if FileManager.default.fileExists(atPath: url.path) {
                let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
                guard Set(document.entries.map(\.id)).count == document.entries.count else { throw CocoaError(.fileReadCorruptFile) }
                saved = document
                draft = document.draft
                entries = document.entries
            }
        } catch {
            unreadable = true
            self.error = "无法读取速记，原文件不会被覆盖。\n\(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @discardableResult func flush() -> Bool {
        pending?.cancel(); pending = nil
        return persist(Document(draft: draft, entries: entries))
    }

    @discardableResult func archive() -> Bool {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        let document = Document(draft: "", entries: [JournalEntry(text: clean)] + entries)
        guard persist(document) else { return false }
        entries = document.entries
        draft = ""
        pending?.cancel(); pending = nil
        return true
    }

    @discardableResult func edit(_ id: UUID, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        var updated = entries
        updated[index].text = clean
        updated[index].modifiedAt = Date()
        guard persist(Document(draft: draft, entries: updated)) else { return false }
        entries = updated
        return true
    }

    @discardableResult func delete(_ id: UUID) -> Bool {
        let updated = entries.filter { $0.id != id }
        guard persist(Document(draft: draft, entries: updated)) else { return false }
        entries = updated
        return true
    }

    private func persist(_ document: Document) -> Bool {
        guard !unreadable else { return false }
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            if document != saved {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(document).write(to: url, options: .atomic)
                saved = document
            }
            error = nil
            return true
        } catch {
            self.error = "速记保存失败，内容已保留在当前窗口，请重试。\n\(error.localizedDescription)"
            return false
        }
    }

    deinit { pending?.cancel() }
}
