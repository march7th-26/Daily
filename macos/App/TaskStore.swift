import Foundation
import Combine
import WidgetKit
import Darwin

@MainActor final class TaskStore: ObservableObject {
    @Published private(set) var items: [Todo] = []
    @Published var error: String?
    @Published private(set) var hasSaveFailure = false
    private let repository: TaskRepository?
    private let refreshWidget: () -> Void
    private var monitor: TaskFileMonitor?

    init(repository: TaskRepository? = nil,
         refreshWidget: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: DailyShared.widgetKind) }) {
        self.repository = repository ?? (try? TaskRepository.shared())
        self.refreshWidget = refreshWidget
        synchronize()
        if let directory = self.repository?.url.deletingLastPathComponent() {
            monitor = TaskFileMonitor(directory: directory) { [weak self] in
                self?.synchronize()
            }
        }
    }

    var activeItems: [Todo] { items.filter { $0.archivedAt == nil } }
    var archivedItems: [Todo] {
        items.filter { $0.archivedAt != nil }.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    func synchronize(refreshWidget force: Bool = false) {
        do {
            guard let repository else { throw CocoaError(.fileNoSuchFile) }
            let fresh = try repository.read()
            let changed = fresh != items
            if changed { items = fresh }
            if changed || force { refreshWidget() }
        } catch {
            self.error = "无法读取待办，原数据不会被覆盖。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func commit(_ change: (inout [Todo]) -> Void) -> Bool {
        do {
            guard let repository else { throw CocoaError(.fileNoSuchFile) }
            let fresh = try repository.update(change)
            if fresh != items {
                items = fresh
                // Only notify WidgetKit once the shared file has been saved successfully.
                refreshWidget()
            }
            hasSaveFailure = false
            return true
        } catch {
            hasSaveFailure = true
            self.error = "保存失败，原数据未被覆盖。\n\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func add(_ title: String) -> Bool {
        guard let clean = normalized(title) else { return false }
        return commit { $0.append(Todo(title: clean)) }
    }

    @discardableResult
    func edit(_ id: UUID, title: String) -> Bool {
        guard let clean = normalized(title) else { return false }
        return update(id) { $0.title = clean }
    }

    func archive(_ id: UUID) { update(id) { if $0.archivedAt == nil { $0.archivedAt = Date() } } }
    func restore(_ id: UUID) { update(id, includeArchived: true) { $0.archivedAt = nil } }
    func toggle(_ id: UUID) {
        update(id) {
            $0.completed.toggle()
            $0.completedAt = $0.completed ? Date() : nil
            for index in $0.subtasks.indices {
                $0.subtasks[index].completed = $0.completed
                $0.subtasks[index].completedAt = $0.completedAt
            }
        }
    }
    @discardableResult
    func addSubtask(_ parent: UUID, title: String) -> Bool {
        guard let clean = normalized(title) else { return false }
        return update(parent) {
            $0.subtasks.append(Subtask(title: clean))
            $0.completed = false
            $0.completedAt = nil
        }
    }

    @discardableResult
    func editSubtask(_ parent: UUID, id: UUID, title: String) -> Bool {
        guard let clean = normalized(title) else { return false }
        return updateSubtask(parent, id: id) { $0.title = clean }
    }

    func toggleSubtask(_ parent: UUID, id: UUID) {
        updateSubtask(parent, id: id) {
            $0.completed.toggle()
            $0.completedAt = $0.completed ? Date() : nil
        }
    }

    func deleteSubtask(_ parent: UUID, id: UUID) {
        update(parent) {
            $0.subtasks.removeAll { $0.id == id }
            Self.reconcile(&$0)
        }
    }

    @discardableResult
    private func updateSubtask(_ parent: UUID, id: UUID, change: (inout Subtask) -> Void) -> Bool {
        var applied = false
        let saved = update(parent) {
            guard let index = $0.subtasks.firstIndex(where: { $0.id == id }) else { return }
            change(&$0.subtasks[index])
            Self.reconcile(&$0)
            applied = true
        }
        return saved && applied
    }

    private static func reconcile(_ task: inout Todo) {
        guard !task.subtasks.isEmpty else { return }
        let completed = task.subtasks.allSatisfy(\.completed)
        if task.completed != completed {
            task.completed = completed
            task.completedAt = completed ? Date() : nil
        }
    }

    func delete(_ id: UUID) { commit { $0.removeAll { $0.id == id } } }

    @discardableResult
    private func update(_ id: UUID, includeArchived: Bool = false, change: (inout Todo) -> Void) -> Bool {
        var applied = false
        let saved = commit { tasks in
            if let index = tasks.firstIndex(where: { $0.id == id && (includeArchived || $0.archivedAt == nil) }) {
                change(&tasks[index])
                applied = true
            }
        }
        return saved && applied
    }

    @discardableResult
    func move(_ id: UUID, relativeTo targetID: UUID, after: Bool) -> Bool {
        guard id != targetID else { return false }
        var moved = false
        let saved = commit { tasks in
            guard let from = tasks.firstIndex(where: { $0.id == id && $0.archivedAt == nil }),
                  let target = tasks.firstIndex(where: { $0.id == targetID && $0.archivedAt == nil }) else { return }
            var destination = target + (after ? 1 : 0)
            if from < destination { destination -= 1 }
            guard destination != from else { return }
            let task = tasks.remove(at: from)
            tasks.insert(task, at: destination)
            moved = true
        }
        return saved && moved
    }

    @discardableResult
    func prepareForUpdate() -> Bool {
        guard !hasSaveFailure else {
            error = "请先解决保存失败，再安装更新。"
            return false
        }
        do {
            guard let repository else { throw CocoaError(.fileNoSuchFile) }
            try repository.backupForUpdate()
            return true
        } catch {
            self.error = "更新前备份失败，已取消更新。\n\(error.localizedDescription)"
            return false
        }
    }

    private func normalized(_ title: String) -> String? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        guard clean.utf16.count <= 200 else {
            error = "事项最多 200 个字符，内容未被截断。"
            return nil
        }
        return clean
    }
}

// Watch the directory because atomic saves replace the file's inode.
private final class TaskFileMonitor {
    private let source: DispatchSourceFileSystemObject
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    init?(directory: URL, onChange: @escaping () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        self.onChange = onChange
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let pending = DispatchWorkItem { [weak self] in self?.onChange() }
            self.pending = pending
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: pending)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        pending?.cancel()
        source.cancel()
    }
}
