import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TodoView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var quotes: QuoteStore
    @EnvironmentObject private var updates: UpdateStore
    @EnvironmentObject private var windows: WindowController
    var compact = false
    @State private var text = ""
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var showHistory = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @StateObject private var drag = TaskDrag()
    @FocusState private var inputFocused: Bool
    @FocusState private var focusedEdit: UUID?
    @FocusState private var focusedRow: UUID?
    private var tasks: [Todo] { store.activeItems }
    private var done: Int { tasks.reduce(0) { $0 + ($1.completed ? 1 : 0) } }

    var body: some View {
        GeometryReader { geometry in
            let tight = compact || geometry.size.width < 400 || geometry.size.height < 460
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                content(date: clock.date, tight: tight)
                    .task(id: Calendar.current.startOfDay(for: clock.date)) {
                        await quotes.refresh(for: clock.date)
                        await updates.checkIfNeeded()
                    }
            }.frame(maxWidth: 640).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
        }
        .onChange(of: focusedEdit) { if $0 == nil { finishEditing(save: true) } }
        .onChange(of: windows.focusInput) { _ in focusInputIfRequested() }
        .onAppear { focusInputIfRequested() }
        .onDisappear { drag.clear(); rowFrames.removeAll() }
        .onReceive(NotificationCenter.default.publisher(for: .dailyCommitEdits)) { notification in
            if !finishEditing(save: true) { (notification.object as? EditCommitRequest)?.succeeded = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dailyEditFocusedTask)) { _ in
            if let id = focusedRow, let task = tasks.first(where: { $0.id == id }) { beginEditing(task) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dailyCancelDrag)) { _ in drag.clear() }
    }

    private func content(date: Date, tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tight ? 12 : 24) {
            VStack(alignment: .leading, spacing: 9) {
                Text(date.formatted(.dateTime.month().day().weekday(.wide))).font(.system(size: 12)).foregroundColor(Palette.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("Daily").font(.system(size: tight ? 23 : 27, weight: .semibold))
                    Spacer()
                    Button { if finishEditing(save: true) { Task { await updates.presentDetails() } } } label: {
                        Image(systemName: updates.isBusy ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .foregroundColor(Palette.secondary).frame(width: 26, height: 26).contentShape(Rectangle())
                            .overlay(alignment: .topTrailing) {
                                if updates.latestVersion != nil { Circle().fill(.red).frame(width: 6, height: 6).allowsHitTesting(false) }
                            }
                    }.buttonStyle(.plain).disabled(updates.isBusy).help("检查更新")
                }
                quoteView(tight: tight)
            }
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 15)).foregroundColor(Palette.secondary)
                TextField("添加待办…", text: $text).font(.system(size: 14)).textFieldStyle(.plain).focused($inputFocused).onSubmit(add)
                Button(action: add) {
                    Image(systemName: "arrow.turn.down.left").font(.system(size: 12)).foregroundColor(Palette.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("添加待办")
            }.padding(.horizontal, 14).padding(.vertical, 10)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("全部事项")
                    Spacer()
                    Button("历史记录") { if finishEditing(save: true) { showHistory = true } }.buttonStyle(.plain)
                }.font(.system(size: 11)).foregroundColor(Palette.secondary).padding(.horizontal, 2)
                taskList(tight: tight)
            }.frame(maxHeight: .infinity)
            VStack(spacing: 10) {
                HStack {
                    Text("已完成 \(done) / \(tasks.count)").monospacedDigit()
                    Spacer()
                }.font(.system(size: 11)).foregroundColor(Palette.secondary)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.border.opacity(0.75))
                        Capsule().fill(Palette.accent).frame(width: geometry.size.width * (tasks.isEmpty ? 0 : CGFloat(done) / CGFloat(tasks.count)))
                    }
                }.frame(height: 4)
            }.accessibilityElement(children: .ignore).accessibilityLabel("完成进度").accessibilityValue("\(done) / \(tasks.count)")
        }.padding(tight ? 16 : 28).foregroundColor(Palette.ink)
            .alert("需要留意", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("好") { store.error = nil }
            } message: { Text(store.error ?? "") }
            .sheet(isPresented: $showHistory) { HistoryView().environmentObject(store).frame(minWidth: 360, minHeight: 400) }
    }

    private func taskList(tight: Bool) -> some View {
        let tasks = self.tasks
        return GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if tasks.isEmpty { Text("暂无待办").font(.system(size: 13)).foregroundColor(Palette.secondary).frame(maxWidth: .infinity).padding(.vertical, 42) }
                        ForEach(tasks) { task in
                            TaskRow(task: task, tight: tight, isEditing: editingID == task.id, editingText: $editingText,
                                    editFocus: $focusedEdit, rowFocus: $focusedRow,
                                    toggle: { withAnimation(.easeInOut(duration: 0.18)) { store.toggle(task.id) } },
                                    edit: { beginEditing(task) }, finish: { finishEditing(save: $0) },
                                    archive: { if finishEditing(save: true) { store.archive(task.id) } },
                                    delete: { store.delete(task.id) }, startDrag: {
                                        guard finishEditing(save: true) else { return NSItemProvider() }
                                        drag.begin(task.id)
                                        return NSItemProvider(object: task.id.uuidString as NSString)
                                    })
                                .id(task.id)
                                .background(GeometryReader { row in Color.clear.preference(key: TaskFrames.self, value: [task.id: row.frame(in: .named("TaskViewport"))]) })
                                .overlay(alignment: drag.after ? .bottom : .top) {
                                    if drag.targetID == task.id { Rectangle().fill(Palette.accent).frame(height: 2).allowsHitTesting(false) }
                                }
                                .onDrop(of: [UTType.text], delegate: TaskRowDrop(task: task, frame: rowFrames[task.id] ?? CGRect(x: 0, y: 0, width: 1, height: 52), store: store, drag: drag))
                            if task.id != tasks.last?.id { Rectangle().fill(Palette.border).frame(height: 0.5).padding(.leading, 47) }
                        }
                    }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }.coordinateSpace(name: "TaskViewport")
                    .onPreferenceChange(TaskFrames.self) { rowFrames = $0 }
                    .onReceive(drag.pulse) { _ in scrollDuringDrag(proxy: proxy, height: viewport.size.height) }

            }
        }
    }

    private func scrollDuringDrag(proxy: ScrollViewProxy, height: CGFloat) {
        guard drag.draggedID != nil, let y = drag.pointerY else { return }
        let visible = tasks.indices.filter { index in
            guard let frame = rowFrames[tasks[index].id] else { return false }
            return frame.maxY > 0 && frame.minY < height
        }
        if y < 28, let first = visible.first, first > 0 {
            withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(tasks[first - 1].id, anchor: .top) }
        } else if y > height - 28, let last = visible.last, last + 1 < tasks.count {
            withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(tasks[last + 1].id, anchor: .bottom) }
        }
    }

    private func quoteView(tight: Bool) -> some View {
        Button { Task { await quotes.refresh(for: Date(), force: true) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(quotes.text).font(.system(size: tight ? 11 : 12)).lineSpacing(3).lineLimit(tight ? 2 : 3).foregroundColor(Palette.secondary)
                if let source = quotes.source { Text("— " + source).font(.system(size: 10)).foregroundColor(Palette.secondary.opacity(0.8)).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(quotes.isLoading).help(quotes.status).accessibilityLabel("每日一言，点击换一句")
    }

    private func add() { if store.add(text) { text = "" }; inputFocused = true }
    @discardableResult private func finishEditing(save: Bool) -> Bool {
        guard let id = editingID else { return true }
        let clean = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if save && !clean.isEmpty && !store.edit(id, title: editingText) { focusedEdit = id; return false }
        editingID = nil
        focusedEdit = nil
        return true
    }
    private func beginEditing(_ task: Todo) {
        guard finishEditing(save: true) else { return }
        editingID = task.id; editingText = task.title; focusedEdit = task.id
    }
    private func focusInputIfRequested() {
        guard !compact, windows.focusInput else { return }
        guard finishEditing(save: true) else { return }
        inputFocused = true
        windows.focusInput = false
    }
}
