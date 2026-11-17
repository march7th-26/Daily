import SwiftUI
import AppKit
import WidgetKit
import CryptoKit

@main struct DaylightApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var quotes = QuoteStore()
    @StateObject private var updates = UpdateStore()
    @Environment(\.openWindow) private var openWindow
    @State private var pinned = UserDefaults.standard.bool(forKey: "dailyPinned")
    var body: some Scene {
        Window("Daily", id: "main") {
            TodoView().environmentObject(store).environmentObject(quotes).environmentObject(updates)
                .frame(minWidth: 280, minHeight: 320)
                .onAppear { WidgetCenter.shared.reloadTimelines(ofKind: "DaylightWidget"); Task { await updates.checkIfNeeded() } }
                .onOpenURL { _ in showMainWindow() }
                .background(WindowPin(isPinned: pinned))
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        MenuBarExtra("Daily", systemImage: "checkmark.circle") {
            VStack(spacing: 0) {
                TodoView(compact: true).environmentObject(store).environmentObject(quotes).environmentObject(updates)
                Divider()
                HStack {
                    Toggle("窗口置顶", isOn: $pinned).toggleStyle(.checkbox)
                    Button(updates.isBusy ? updates.status : updates.latestVersion.map { "安装更新 v\($0)" } ?? "检查更新…") {
                        Task {
                            if updates.latestVersion != nil { await updates.installUpdate() }
                            else { await updates.check(force: true) }
                        }
                    }.disabled(updates.isBusy)
                    if updates.latestVersion != nil {
                        Button("打开下载页") { updates.openRelease() }
                    }
                    Button("打开主窗口") {
                        showMainWindow()
                    }
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }
                }.padding(14)
                if !updates.status.isEmpty {
                    Text(updates.status).font(.system(size: 11)).foregroundColor(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 10)
                }
            }.frame(width: 360, height: 480)
        }.menuBarExtraStyle(.window)
        .commands { CommandGroup(replacing: .newItem) { Button("新建待办") { showMainWindow() }.keyboardShortcut("n", modifiers: .command) } }
    }

    @MainActor private func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "Daily.main" }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct TodoView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var quotes: QuoteStore
    @EnvironmentObject private var updates: UpdateStore
    var compact = false
    @State private var text = ""
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var showHistory = false
    @State private var cancelEdit = false
    @FocusState private var inputFocused: Bool
    @FocusState private var focusedEdit: UUID?
    private var tasks: [Todo] { store.activeItems }
    private var done: Int { tasks.filter(\.completed).count }
    var body: some View {
        GeometryReader { geometry in
            let tight = compact || geometry.size.width < 400 || geometry.size.height < 460
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                content(date: clock.date, tight: tight)
                    .task(id: Calendar.current.startOfDay(for: clock.date)) {
                        await quotes.refresh(for: clock.date)
                    }
            }
        }
        .onChange(of: focusedEdit) { focused in
            guard focused == nil, let id = editingID else { return }
            if cancelEdit { cancelEdit = false; editingID = nil; return }
            store.edit(id, title: editingText)
            editingID = nil
        }
    }
    private func content(date: Date, tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tight ? 12 : 24) {
            VStack(alignment: .leading, spacing: 9) {
                Text(date.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Palette.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("Daily").font(.system(size: tight ? 23 : 27, weight: .semibold))
                    Spacer()
                    Button {
                        if updates.latestVersion != nil { Task { await updates.installUpdate() } }
                        else { Task { await updates.check(force: true) } }
                    } label: {
                        Image(systemName: updates.isBusy ? "arrow.triangle.2.circlepath" : updates.latestVersion == nil ? "arrow.clockwise" : "arrow.down.circle.fill")
                            .foregroundColor(updates.latestVersion == nil ? Palette.secondary : .red)
                    }.buttonStyle(.plain).disabled(updates.isBusy)
                        .help(updates.latestVersion.map { "发现新版本 v\($0)，点击下载并启动安装器" } ?? "检查更新")
                }
                if !updates.status.isEmpty {
                    Text(updates.status).font(.system(size: 10)).foregroundColor(Palette.secondary).lineLimit(2)
                }
                quoteView(tight: tight)
            }
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 15, weight: .regular)).foregroundColor(Palette.secondary)
                TextField("添加待办…", text: $text)
                    .font(.system(size: 14)).textFieldStyle(.plain)
                    .focused($inputFocused).onSubmit(add)
                Button(action: add) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 12)).foregroundColor(Palette.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("添加待办")
            }.padding(.horizontal, 14).padding(.vertical, 10)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("全部事项")
                    Spacer()
                    Button("历史记录") { showHistory = true }.buttonStyle(.plain).foregroundColor(Palette.secondary)
                }.font(.system(size: 11)).foregroundColor(Palette.secondary)
                    .padding(.horizontal, 2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                    LazyVStack(spacing: 0) {
                        if tasks.isEmpty {
                            Text("暂无待办")
                                .font(.system(size: 13)).foregroundColor(Palette.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 42)
                        }
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            HStack(alignment: .top, spacing: 11) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) { store.toggle(task.id) }
                                } label: {
                                    ZStack {
                                        Circle().fill(task.completed ? Palette.accent : .clear)
                                        Circle().stroke(task.completed ? Palette.accent : Palette.outline, lineWidth: 1.3)
                                        if task.completed {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .semibold)).foregroundColor(Palette.checkInk)
                                        }
                                    }.frame(width: 20, height: 20).padding(4)
                                        // Keep the clear interior clickable when unchecked.
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(task.completed ? "标为未完成" : "标为已完成")
                                    .accessibilityValue(task.title)
                                if editingID == task.id {
                                    TextField("待办事项", text: $editingText, onCommit: { store.edit(task.id, title: editingText); editingID = nil; focusedEdit = nil })
                                        .textFieldStyle(.plain).focused($focusedEdit, equals: task.id)
                                        .onExitCommand { cancelEdit = true; focusedEdit = nil }
                                } else {
                                Text(task.title).font(.system(size: 14))
                                    .strikethrough(task.completed)
                                    .foregroundColor(task.completed ? Palette.secondary : Palette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 3)
                                    .onTapGesture(count: 2) { beginEditing(task) }
                                }
                                if editingID != task.id {
                                    Button { beginEditing(task) } label: {
                                        Image(systemName: "pencil").font(.system(size: 10))
                                            .foregroundColor(Palette.secondary).frame(width: 22, height: 24).contentShape(Rectangle())
                                    }.buttonStyle(.plain).help("编辑待办")
                                        .accessibilityLabel("编辑：" + task.title)
                                }
                                Button { store.archive(task.id) } label: { Image(systemName: "archivebox").font(.system(size: 10)).foregroundColor(Palette.secondary).frame(width: 22, height: 24) }
                                    .buttonStyle(.plain).help("归档到历史记录")
                                Button { store.delete(task.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 10))
                                        .foregroundColor(Palette.secondary).frame(width: 22, height: 24).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("删除：" + task.title)
                            }.padding(.horizontal, 12).padding(.vertical, tight ? 9 : 13)
                            if index < tasks.count - 1 {
                                Rectangle().fill(Palette.border).frame(height: 0.5).padding(.leading, 47)
                            }
                        }
                    }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.frame(maxHeight: .infinity)
            VStack(spacing: 10) {
                HStack {
                    Text("已完成 \(done) / \(tasks.count)").monospacedDigit()
                    Spacer()
                }.font(.system(size: 11)).foregroundColor(Palette.secondary)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.border.opacity(0.75))
                        Capsule().fill(Palette.accent)
                            .frame(width: geometry.size.width * (tasks.isEmpty ? 0 : CGFloat(done) / CGFloat(tasks.count)))
                    }
                }.frame(height: 4)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("完成进度")
                .accessibilityValue("\(done) / \(tasks.count)")
        }.padding(tight ? 16 : 28)
            .background(Palette.background).foregroundColor(Palette.ink)
            .alert("需要留意", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("好") { store.error = nil }
            } message: { Text(store.error ?? "") }
            .sheet(isPresented: $showHistory) { HistoryView().environmentObject(store).frame(minWidth: 360, minHeight: 400) }
    }
    private func quoteView(tight: Bool) -> some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(quotes.text)
                    .font(.system(size: tight ? 11 : 12, weight: .regular))
                    .lineSpacing(3).lineLimit(tight ? 2 : 3)
                    .foregroundColor(Palette.secondary)
                if let source = quotes.source {
                    Text("— " + source).font(.system(size: 10))
                        .foregroundColor(Palette.secondary.opacity(0.8)).lineLimit(1)
                }
            }.help(quotes.text + (quotes.source.map { " — " + $0 } ?? ""))
    }
    private func add() {
        store.add(text)
        if store.error == nil { text = "" }
        inputFocused = true
    }
    private func beginEditing(_ task: Todo) {
        editingID = task.id
        editingText = task.title
        focusedEdit = task.id
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var store: TaskStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("历史记录").font(.title2.weight(.semibold))
            List {
                ForEach(store.archivedItems) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).strikethrough(task.completed)
                            Text("创建：\(task.createdAt?.formatted(date: .numeric, time: .shortened) ?? "未记录") · 完成：\(task.completedAt?.formatted(date: .numeric, time: .shortened) ?? "未记录") · 归档：\(task.archivedAt?.formatted(date: .numeric, time: .shortened) ?? "未记录")")
                                .font(.caption).foregroundColor(Palette.secondary)
                        }
                        Spacer()
                        Button("恢复") { store.restore(task.id) }
                        Button("删除", role: .destructive) { store.delete(task.id) }
                    }.padding(.vertical, 4)
                }
            }
        }.padding(20)
    }
}

@MainActor final class UpdateStore: ObservableObject {
    @Published private(set) var latestVersion: String?
    @Published private(set) var status = ""
    @Published private(set) var isBusy = false
    private var releaseURL: URL?
    private var packageURL: URL?
    private var checksumsURL: URL?
    private let releaseList = URL(string: "https://api.github.com/repos/march7th-26/Daily/releases?per_page=50")!

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    func checkIfNeeded() async {
        let key = "dailyLastUpdateCheck"
        if let date = UserDefaults.standard.object(forKey: key) as? Date, Calendar.current.isDateInToday(date) { return }
        await check(force: false)
    }
    func check(force: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        if force { status = "正在检查更新…" }
        defer { isBusy = false }
        do {
            var request = URLRequest(url: releaseList); request.timeoutInterval = 20
            request.setValue("Daily-macOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.message("GitHub 暂时无法访问，请稍后重试。")
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            let macReleases = releases.filter {
                $0.tag_name.hasPrefix("macos-v") && !$0.draft && !$0.prerelease
            }
            guard let newest = macReleases.max(by: {
                compare(String($0.tag_name.dropFirst("macos-v".count)), String($1.tag_name.dropFirst("macos-v".count))) == .orderedAscending
            }) else {
                latestVersion = nil
                status = force ? "暂未发布 macOS 版本更新。" : ""
                return
            }
            let remote = String(newest.tag_name.dropFirst("macos-v".count))
            let local = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let versionOrder = compare(remote, local)
            latestVersion = versionOrder == .orderedDescending ? remote : nil
            releaseURL = newest.html_url
            packageURL = newest.assets.first(where: { $0.name == "Daily-macOS-\(remote).pkg" })?.browser_download_url
            checksumsURL = newest.assets.first(where: { $0.name == "SHA256SUMS.txt" })?.browser_download_url
            if latestVersion != nil {
                status = "发现 v\(remote)，点击下载并启动安装器。"
            } else if versionOrder == .orderedAscending, force {
                status = "当前构建 v\(local) 高于最新正式版 v\(remote)。"
            } else if force {
                status = "当前已是最新版本 v\(local)。"
            } else {
                status = ""
            }
            UserDefaults.standard.set(Date(), forKey: "dailyLastUpdateCheck")
        } catch {
            if force { status = (error as? UpdateError)?.errorDescription ?? "检查更新失败，请检查网络后重试。" }
        }
    }
    func installUpdate() async {
        guard latestVersion != nil else { return }
        guard let packageURL, let checksumsURL, let releaseURL else {
            status = "该版本没有可用安装包，正在打开下载页。"
            openRelease()
            return
        }
        guard !isBusy else { return }
        isBusy = true
        status = "正在下载并校验更新…"
        defer { isBusy = false }
        do {
            let (packageData, packageResponse) = try await URLSession.shared.data(from: packageURL)
            guard (packageResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.message("安装包下载失败，请重试。")
            }
            let (checksumsData, checksumsResponse) = try await URLSession.shared.data(from: checksumsURL)
            guard (checksumsResponse as? HTTPURLResponse)?.statusCode == 200,
                  let checksums = String(data: checksumsData, encoding: .utf8) else {
                throw UpdateError.message("无法读取更新校验文件。")
            }
            let fileName = "Daily-macOS-\(latestVersion!).pkg"
            let expected = checksums.split(whereSeparator: \.isNewline).compactMap { line -> String? in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 2, fields[1].hasSuffix(fileName) else { return nil }
                return String(fields[0]).lowercased()
            }.first
            let actual = SHA256.hash(data: packageData).map { String(format: "%02x", $0) }.joined()
            guard expected == actual else { throw UpdateError.message("更新文件校验失败，已取消安装。") }

            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Daily/Updates", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let packageFile = cache.appendingPathComponent(fileName)
            try packageData.write(to: packageFile, options: .atomic)
            guard NSWorkspace.shared.open(packageFile) else {
                throw UpdateError.message("安装器无法打开，请从下载页手动安装。")
            }
            let runningPath = Bundle.main.bundleURL.standardizedFileURL.path
            if runningPath == "/Applications/Daily.app" {
                status = "安装器已打开。按提示完成安装，再重新打开 Daily。"
            } else {
                status = "安装器会更新“应用程序”文件夹中的 Daily；桌面上的副本不会被替换。"
            }
        } catch {
            status = (error as? UpdateError)?.errorDescription ?? "下载更新失败，请检查网络后重试。"
        }
    }
    func openRelease() {
        NSWorkspace.shared.open(releaseURL ?? URL(string: "https://github.com/march7th-26/Daily/releases?q=macos-v")!)
    }
    private func compare(_ a: String, _ b: String) -> ComparisonResult {
        let lhs = a.split(separator: ".").compactMap { Int($0) }, rhs = b.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(lhs.count, rhs.count) {
            let x = index < lhs.count ? lhs[index] : 0, y = index < rhs.count ? rhs[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
    private enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(value) = self { value } else { nil } }
    }
}

private struct WindowPin: NSViewRepresentable {
    let isPinned: Bool
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { update(view) }; return view }
    func updateNSView(_ view: NSView, context: Context) { update(view) }
    private func update(_ view: NSView) {
        UserDefaults.standard.set(isPinned, forKey: "dailyPinned")
        view.window?.identifier = NSUserInterfaceItemIdentifier("Daily.main")
        view.window?.level = isPinned ? .floating : .normal
    }
}

// A single daily request shared by the main window and menu bar; no task content is sent.
@MainActor final class QuoteStore: ObservableObject {
    @Published var text = "把平凡的小事，做成今天的光。"
    @Published var source: String?
    private var loading = false
    private struct Quote: Codable {
        let hitokoto: String
        let from: String?
        let from_who: String?
    }
    private struct Cache: Codable {
        let day: Date
        let quote: Quote
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "dailyQuote"),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            show(cache.quote)
        }
    }
    private func show(_ quote: Quote) {
        text = quote.hitokoto
        source = [quote.from_who, quote.from].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if source?.isEmpty == true { source = nil }
    }
    func refresh(for date: Date) async {
        guard !loading else { return }
        if let data = UserDefaults.standard.data(forKey: "dailyQuote"),
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           Calendar.current.isDate(cache.day, inSameDayAs: date) { return }
        loading = true
        defer { loading = false }
        do {
            let url = URL(string: "https://v1.hitokoto.cn/?c=d&c=i&c=k&min_length=8&max_length=45")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let quote = try JSONDecoder().decode(Quote.self, from: data)
            guard !quote.hitokoto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  quote.hitokoto.count <= 120 else { return }
            let cache = Cache(day: date, quote: quote)
            UserDefaults.standard.set(try JSONEncoder().encode(cache), forKey: "dailyQuote")
            show(quote)
        } catch { /* Keep the cached sentence or local fallback while offline. */ }
    }
}
