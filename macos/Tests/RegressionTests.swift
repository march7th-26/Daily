import Foundation
import CryptoKit

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}
private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
}

private final class StubProtocol: URLProtocol {
    static var payload = Data("[]".utf8)
    static var requests = 0
    static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class ConcurrentFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.lock(); count += 1; lock.unlock() }
    var total: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@main struct RegressionTests {
    @MainActor static func main() async {
        do {
            try await taskAndWidgetTests()
            try await updateTests()
            try await quoteTests()
            try parityTests()
            try await journalTests()
            try subtaskTests()
            print("PASS: all regression checks; tests used temporary files and isolated preferences")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<60 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw TestFailure(description: "File watcher failed to update another store within 3 seconds")
    }

    @MainActor private static func taskAndWidgetTests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Daily-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(url: directory.appendingPathComponent("todos.json"))
        var savedSnapshots: [[Todo]] = []
        let first = TaskStore(repository: repository, refreshWidget: { savedSnapshots.append((try? repository.read()) ?? []) })
        let second = TaskStore(repository: repository, refreshWidget: {})
        try expect(first.add("事项 A"), "First add failed")
        let a = first.items[0].id
        try expect(second.add("事项 B"), "Second store add failed")
        first.toggle(a)
        try expect(try repository.read().count == 2, "A stale store overwrote the other store's task")
        try expect(savedSnapshots.last?.first(where: { $0.id == a })?.completed == true, "Widget reload occurred before completed state was saved")
        for _ in 0..<20 { first.toggle(a) }
        try expect(first.items.first(where: { $0.id == a })?.completed == true, "Repeated toggles lost state")
        try expect(first.items.first(where: { $0.id == a })?.completedAt != nil, "Completion timestamp missing")
        try await waitUntil { second.items == first.items }
        try expect(first.edit(a, title: "修改后的事项"), "Edit failed")
        try await waitUntil { second.items.first(where: { $0.id == a })?.title == "修改后的事项" }
        let noOpCount = savedSnapshots.count
        try expect(first.edit(a, title: "修改后的事项"), "Unchanged edit should still succeed")
        try expect(savedSnapshots.count == noOpCount, "Unchanged edit needlessly reloaded the widget")
        first.archive(a)
        var widget = DailyEntry.load(from: repository)
        try expect(widget.tasks.count == 1 && !widget.tasks.contains { $0.id == a }, "Widget displayed archived task")
        try expect(first.archivedItems.count == 1, "Archive missing from history")
        first.restore(a)
        widget = DailyEntry.load(from: repository)
        try expect(widget.tasks.count == 2 && widget.tasks.first(where: { $0.id == a })?.completed == true, "Restore did not reach widget data")
        first.delete(a)
        try expect(!DailyEntry.load(from: repository).tasks.contains { $0.id == a }, "Deleted task remained in widget data")

        let goodData = try Data(contentsOf: repository.url)
        let corrupt = Data("{invalid JSON".utf8)
        try corrupt.write(to: repository.url, options: .atomic)
        let visible = first.items
        try expect(!first.add("不能覆盖损坏文件"), "Corrupt file was accepted for writing")
        try expect(try Data(contentsOf: repository.url) == corrupt, "Corrupt original was overwritten")
        try expect(first.items == visible, "Failed write erased the visible tasks")
        try expect(DailyEntry.load(from: repository).failed, "Widget masked read failure as an empty task list")
        try goodData.write(to: repository.url, options: .atomic)
        try expect(first.add("修复后可继续保存"), "Read failure permanently disabled the store")
        try await waitUntil { second.items == first.items }
        print("PASS: concurrent stores, post-save widget reads, toggles, edit, archive/restore/delete, file watcher, corruption recovery")

        let legacy = "[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"旧版事项\",\"completed\":true}]"
        try Data(legacy.utf8).write(to: repository.url, options: .atomic)
        first.synchronize()
        try expect(first.items.count == 1 && first.items[0].completed && first.items[0].createdAt == nil, "Legacy format failed to load")
        first.toggle(first.items[0].id)
        try expect(!DailyEntry.load(from: repository).tasks[0].completed, "Legacy task update failed")

        let concurrent = TaskRepository(url: directory.appendingPathComponent("concurrent.json"))
        try concurrent.update { $0.append(Todo(title: "seed")) }
        try await Task.detached {
            let failures = ConcurrentFailures()
            DispatchQueue.concurrentPerform(iterations: 12) { index in
                do { try concurrent.update { $0.append(Todo(title: "writer-\(index)")) } }
                catch { failures.record() }
            }
            try expect(failures.total == 0, "Concurrent writer threw an error")
            try expect(try concurrent.read().count == 13, "Concurrent writers lost tasks")
        }.value
        print("PASS: legacy records and coordinated concurrent writers")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 55))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19))!
        try expect(DailyShared.nextWidgetRefresh(after: late, calendar: calendar) == midnight, "Widget date would not refresh at midnight")
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
        try expect(DailyShared.nextWidgetRefresh(after: noon, calendar: calendar).timeIntervalSince(noon) == 1800, "Missing periodic recovery reload")
        print("PASS: widget midnight and missed-notification recovery schedule")
    }

    @MainActor private static func updateTests() async throws {
        let suite = "com.example.Daily.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        func release(_ tag: String, prerelease: Bool = false) -> [String: Any] {
            ["tag_name": tag, "html_url": "https://github.com/march7th-26/Daily/releases/tag/" + tag,
             "draft": false, "prerelease": prerelease, "assets": [], "body": "发布说明：" + tag]
        }
        StubProtocol.payload = try JSONSerialization.data(withJSONObject: [release("v99.0.0"), release("macos-v1.8.0"), release("macos-vbad"), release("macos-v9.0.0", prerelease: true)])
        let store = UpdateStore(session: session, defaults: defaults, localVersion: "1.6.2")
        await store.check(force: true)
        try expect(store.releaseNotes.contains("发布说明：macos-v1.8.0"), "Release notes were not loaded")
        try expect(store.latestVersion == "1.8.0", "Updater selected the wrong platform, malformed tag, or prerelease")
        let restored = UpdateStore(session: session, defaults: defaults, localVersion: "1.6.2")
        try expect(restored.latestVersion == "1.8.0", "Update badge vanished after relaunch")
        let requests = StubProtocol.requests
        await restored.checkIfNeeded()
        try expect(StubProtocol.requests == requests, "Updater ignored daily cache")
        StubProtocol.payload = try JSONSerialization.data(withJSONObject: [])
        await restored.check(force: true)
        try expect(restored.latestVersion == nil, "Empty release list left a stale update")
        let cleared = UpdateStore(session: session, defaults: defaults, localVersion: "1.6.2")
        try expect(cleared.latestVersion == nil, "No-release result was not persisted")

        let data = Data("valid package fixture".utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = "Daily-macOS-1.8.0.pkg"
        try expect(UpdateStore.validate(package: data, checksums: hash + "  " + file, fileName: file), "Valid package checksum rejected")
        try expect(!UpdateStore.validate(package: data, checksums: hash + "  wrong-" + file, fileName: file), "Suffix-matched another package's checksum")
        try expect(!UpdateStore.validate(package: Data("tampered".utf8), checksums: hash + "  " + file, fileName: file), "Tampered package accepted")
        print("PASS: update selection, cached badge on relaunch, no-update cache, exact package checksum")
    }
    @MainActor private static func quoteTests() async throws {
        let suite = "Daily.quote.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); StubProtocol.statusCode = 200 }
        var clock = Date()
        func payload(_ text: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["hitokoto": text, "from": "测试"])
        }
        StubProtocol.statusCode = 200
        StubProtocol.payload = try payload("第一句测试语句，仅用于隔离回归测试。")
        let quotes = QuoteStore(session: session, defaults: defaults, now: { clock })
        await quotes.refresh(for: clock)
        let original = quotes.text
        let count = StubProtocol.requests
        await quotes.refresh(for: clock)
        try expect(StubProtocol.requests == count, "Quote daily cache was ignored")
        StubProtocol.payload = try payload("手动点击后取得的另一句测试语句。")
        await quotes.refresh(for: clock, force: true)
        try expect(quotes.text != original, "Manual quote refresh used the daily cache")
        let restored = QuoteStore(session: session, defaults: defaults, now: { clock })
        try expect(restored.text == quotes.text, "Manual quote did not persist")
        clock = clock.addingTimeInterval(86400)
        StubProtocol.statusCode = 500
        let retained = quotes.text
        await quotes.refresh(for: clock)
        try expect(quotes.text == retained && quotes.status.contains("原句已保留"), "Quote failure erased cached content")
        let failedCount = StubProtocol.requests
        await quotes.refresh(for: clock)
        try expect(StubProtocol.requests == failedCount, "Quote failure retried before backoff elapsed")
        StubProtocol.statusCode = 200
        StubProtocol.payload = try payload("失败之后手动重试，也能马上更新语句。")
        await quotes.refresh(for: clock, force: true)
        try expect(quotes.text != retained, "Manual retry failed to bypass quote backoff")
        print("PASS: quote click refresh, daily cache, persisted replacement, failure retention and manual retry")
    }

    @MainActor private static func parityTests() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Daily-parity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(url: directory.appendingPathComponent("todos.json"))
        let emptyRepository = TaskRepository(url: directory.appendingPathComponent("empty.json"))
        try emptyRepository.backupForUpdate()
        try expect(try JSONDecoder().decode([Todo].self, from: Data(contentsOf: emptyRepository.url.appendingPathExtension("update.bak"))).isEmpty, "Empty installation could not prepare an update backup")
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Todo(title: "A", createdAt: fixed)
        let b = Todo(title: "B", completed: true, createdAt: fixed, completedAt: fixed)
        let archived = Todo(title: "history", createdAt: fixed, archivedAt: fixed)
        let c = Todo(title: "C", createdAt: fixed)
        try repository.update { $0 = [a, archived, b, c] }
        let store = TaskStore(repository: repository, refreshWidget: {})
        try expect(store.move(c.id, relativeTo: a.id, after: false), "Move before target failed")
        try expect(store.activeItems.map(\.id) == [c.id, a.id, b.id], "Move did not preserve expected order")
        try expect(store.move(c.id, relativeTo: b.id, after: true), "Move after target failed")
        try expect(store.activeItems.map(\.id) == [a.id, b.id, c.id], "Move after target produced wrong order")
        try expect(!store.move(a.id, relativeTo: a.id, after: false), "Self move should do nothing")
        try expect(!store.move(a.id, relativeTo: archived.id, after: false), "Archived target accepted for dragging")
        try expect(try repository.read().first(where: { $0.id == b.id }) == b, "Reordering changed completion/timestamps")
        let reloaded = TaskStore(repository: repository, refreshWidget: {})
        try expect(reloaded.activeItems.map(\.id) == store.activeItems.map(\.id), "Sort order did not survive reload")
        try expect(!store.add(String(repeating: "长", count: 201)), "Overlong task was silently truncated")
        try expect(!store.edit(archived.id, title: "不能改归档"), "Archived task was edited")
        store.toggle(archived.id)
        try expect(try repository.read().first(where: { $0.id == archived.id }) == archived, "Archived task completion changed")
        let backup = repository.url.appendingPathExtension("bak")
        try expect(FileManager.default.fileExists(atPath: backup.path), "Missing previous-save backup")
        try expect(store.prepareForUpdate(), "Update backup failed")
        try expect(try Data(contentsOf: repository.url.appendingPathExtension("update.bak")) == Data(contentsOf: repository.url), "Update backup does not match current data")
        try FileManager.default.removeItem(at: repository.url.appendingPathExtension("update.bak"))
        try FileManager.default.createDirectory(at: repository.url.appendingPathExtension("update.bak"), withIntermediateDirectories: true)
        try expect(!store.prepareForUpdate(), "Update allowed after backup failure")
        print("PASS: persisted drag order, unchanged timestamps, archive guards, length limit and update backup")

        let xml = "<pkg-info identifier=\"com.example.Daylight.installer\" version=\"1.7.0\"><bundle path=\"./Applications/Daily.app\" id=\"com.example.Daylight\" CFBundleShortVersionString=\"1.7.0\"/><bundle-version><bundle id=\"com.example.Daylight\"/></bundle-version><upgrade-bundle><bundle id=\"com.example.Daylight\"/></upgrade-bundle></pkg-info>"
        try expect(PackageValidator.matches(Data(xml.utf8), version: "1.7.0"), "Correct package manifest rejected")
        try expect(!PackageValidator.matches(Data(xml.utf8), version: "9.0.0"), "Wrong package version accepted")
        try expect(!PackageValidator.matches(Data(xml.replacingOccurrences(of: "com.example.Daylight.installer", with: "other.app").utf8), version: "1.7.0"), "Wrong installer identity accepted")
        let old = directory.appendingPathComponent(UUID().uuidString)
        let recent = directory.appendingPathComponent(UUID().uuidString)
        let other = directory.appendingPathComponent("not-owned")
        for item in [old, recent, other] { try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true) }
        for item in [old, other] { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90000)], ofItemAtPath: item.path) }
        UpdateStore.cleanup(at: directory)
        try expect(!FileManager.default.fileExists(atPath: old.path), "Stale update stage was not cleaned")
        try expect(FileManager.default.fileExists(atPath: recent.path) && FileManager.default.fileExists(atPath: other.path), "Cleanup removed recent or unrelated files")
        print("PASS: installer identity/version and bounded cache cleanup")

        let suite = "Daily.window.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "dailyPinned")
        defaults.set(true, forKey: "dailyEdgeDocking")
        _ = WindowController(defaults: defaults)
        try expect(defaults.object(forKey: "dailyPinned") == nil && defaults.object(forKey: "dailyEdgeDocking") == nil, "Retired window preferences were not removed")
        print("PASS: retired window preferences cleaned")
    }

    @MainActor private static func journalTests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Daily-journal-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let store = JournalStore(url: url)
        store.draft = "今天的想法\n第二行 📝"
        try await Task.sleep(nanoseconds: 600_000_000)
        try expect(JournalStore(url: url).draft == store.draft, "Debounced draft was not saved")
        try expect(store.entries.isEmpty, "Draft was automatically archived")
        try expect(store.archive(), "Manual archive failed")
        let reopened = JournalStore(url: url)
        try expect(reopened.draft.isEmpty && reopened.entries.count == 1, "Archive and draft clearing were not atomic")
        let entry = reopened.entries[0]
        try expect(entry.text == "今天的想法\n第二行 📝", "Multiline Unicode text was lost")
        try expect(reopened.edit(entry.id, text: "编辑后的日志"), "Journal edit failed")
        try expect(JournalStore(url: url).entries[0].text == "编辑后的日志", "Journal edit was not persisted")
        try expect(!reopened.archive(), "Empty draft created a journal entry")
        try expect(reopened.delete(entry.id) && JournalStore(url: url).entries.isEmpty, "Journal delete failed")
        let blocked = directory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocked)
        let failing = JournalStore(url: blocked.appendingPathComponent("journal.json"))
        failing.draft = "不能丢失的草稿"
        try expect(!failing.archive() && failing.draft == "不能丢失的草稿" && failing.entries.isEmpty, "Failed archive discarded draft")
        try Data("corrupt".utf8).write(to: url)
        let corrupt = JournalStore(url: url)
        corrupt.draft = "新内容"
        try expect(!corrupt.flush() && String(data: try Data(contentsOf: url), encoding: .utf8) == "corrupt", "Corrupt journal was overwritten")
        print("PASS: journal draft autosave, manual archive, multiline Unicode, edit/delete and failure protection")
    }

    @MainActor private static func subtaskTests() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Daily-subtask-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(url: directory.appendingPathComponent("todos.json"))
        let store = TaskStore(repository: repository, refreshWidget: {})
        try expect(store.add("父事项"), "Parent creation failed")
        let parent = store.items[0].id
        try expect(store.addSubtask(parent, title: "补充测试"), "Subtask creation failed")
        try expect(store.addSubtask(parent, title: "修复 CI"), "Second subtask creation failed")
        try expect(!store.addSubtask(parent, title: "  "), "Empty subtask was created")
        try expect(!store.addSubtask(parent, title: String(repeating: "a", count: 201)), "Long subtask was accepted")
        let first = store.items[0].subtasks[0].id
        let second = store.items[0].subtasks[1].id
        store.toggleSubtask(parent, id: first)
        try expect(!store.items[0].completed, "Parent completed prematurely")
        store.toggleSubtask(parent, id: second)
        try expect(store.items[0].completed && store.items[0].completedAt != nil, "All children failed to complete parent")
        store.toggleSubtask(parent, id: first)
        try expect(!store.items[0].completed && store.items[0].completedAt == nil, "Parent did not reopen")
        store.toggle(parent)
        try expect(store.items[0].subtasks.allSatisfy(\.completed), "Parent completion did not complete children")
        store.toggle(parent)
        try expect(store.items[0].subtasks.allSatisfy { !$0.completed && $0.completedAt == nil }, "Parent reopening did not reopen children")
        try expect(store.editSubtask(parent, id: first, title: "更新测试"), "Subtask edit failed")
        let other = TaskStore(repository: repository, refreshWidget: {})
        other.addSubtask(parent, title: "并发添加")
        store.editSubtask(parent, id: second, title: "最新修改")
        try expect(store.items[0].subtasks.count == 3, "Sibling edit lost concurrent child")
        store.archive(parent)
        try expect(store.activeItems.isEmpty && store.archivedItems[0].subtasks.count == 3, "Archive lost children")
        try expect(!store.addSubtask(parent, title: "不能修改归档"), "Archived parent accepted child")
        store.restore(parent)
        store.deleteSubtask(parent, id: first)
        try expect(store.items[0].subtasks.count == 2, "Child deletion failed")
        try expect(try repository.read() == store.items, "Child data was not persisted")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.items)) as! [[String: Any]]
        legacy[0].removeValue(forKey: "subtasks")
        let decoded = try JSONDecoder().decode([Todo].self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(decoded[0].subtasks.isEmpty, "Legacy data could not be decoded")
        store.delete(parent)
        try expect(try repository.read().isEmpty, "Parent deletion left orphan children")
        print("PASS: child CRUD, completion propagation, concurrent edits, archive/restore and legacy compatibility")
    }

}
