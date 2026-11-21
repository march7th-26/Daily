import SwiftUI
import AppKit

struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    let task: Todo
    let tight: Bool
    let isEditing: Bool
    @Binding var editingText: String
    var editFocus: FocusState<UUID?>.Binding
    var rowFocus: FocusState<UUID?>.Binding
    let toggle: () -> Void
    let edit: () -> Void
    let finish: (Bool) -> Void
    let archive: () -> Void
    let delete: () -> Void
    let startDrag: () -> NSItemProvider
    var initiallyExpanded = false
    @State private var expanded = false
    @State private var adding = false
    @State private var childTitle = ""
    @State private var editingChild: UUID?
    @State private var childEditText = ""
    @State private var confirmDelete = false
    @FocusState private var addingFocus: Bool
    @FocusState private var childEditFocus: UUID?
    @State private var hovering = false
    private var actionsVisible: Bool { hovering || isEditing || rowFocus.wrappedValue == task.id }

    private var parentRow: some View {
        HStack(alignment: .top, spacing: 7) {
            Button {
                let wasExpanded = expanded
                guard finishChildren() else { return }
                expanded = !wasExpanded && !task.subtasks.isEmpty
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium)).foregroundColor(Palette.secondary)
                    .frame(width: 12, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).opacity(task.subtasks.isEmpty && !adding && !expanded ? 0 : 1)
                .disabled(task.subtasks.isEmpty && !adding && !expanded).accessibilityLabel(expanded ? "收起子待办" : "展开子待办")
            Button(action: toggle) {
                ZStack {
                    Circle().fill(task.completed ? Palette.accent : .clear)
                    Circle().stroke(task.completed ? Palette.accent : Palette.outline, lineWidth: 1.3)
                    if task.completed { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundColor(Palette.checkInk) }
                }.frame(width: 20, height: 20).padding(4).contentShape(Rectangle())
            }.buttonStyle(.plain).focused(rowFocus, equals: task.id)
                .accessibilityLabel(task.completed ? "标为未完成" : "标为已完成").accessibilityValue(task.title)
            if isEditing {
                TextField("待办事项", text: $editingText)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused(editFocus, equals: task.id)
                    .onSubmit { finish(true) }.onExitCommand { finish(false) }
            } else {
                Text(task.title).font(.system(size: 14)).strikethrough(task.completed)
                    .foregroundColor(task.completed ? Palette.secondary : Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3).onTapGesture(count: 2, perform: edit)
                    .onDrag(startDrag)
            }
            HStack(spacing: 1) {
                Button(action: beginAdding) { Image(systemName: "plus").frame(width: 22, height: 24).contentShape(Rectangle()) }
                    .help("添加子待办").accessibilityLabel("添加子待办：" + task.title)
                Button(action: { if finishChildren() { archive() } }) { Image(systemName: "archivebox").frame(width: 22, height: 24).contentShape(Rectangle()) }
                    .help("归档到历史记录").accessibilityLabel("归档：" + task.title)
                Button(action: requestDelete) { Image(systemName: "xmark").frame(width: 22, height: 24).contentShape(Rectangle()) }
                    .accessibilityLabel("删除：" + task.title)
            }.font(.system(size: 10)).foregroundColor(Palette.secondary).buttonStyle(.plain)
                .opacity(actionsVisible ? 1 : 0).allowsHitTesting(actionsVisible).accessibilityHidden(!actionsVisible)
        }.padding(.horizontal, 12).padding(.vertical, tight ? 9 : 13)
            .contentShape(Rectangle()).onHover { hovering = $0 }
            .contextMenu {
                Button("添加子待办", action: beginAdding)
                Button("编辑", action: edit)
                Button("归档到历史记录") { if finishChildren() { archive() } }
                Button("删除", role: .destructive, action: requestDelete)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            parentRow
            if !task.subtasks.isEmpty {
                Text("\(task.subtasks.filter(\.completed).count) / \(task.subtasks.count)")
                    .font(.system(size: 10)).monospacedDigit().foregroundColor(Palette.secondary)
                    .padding(.leading, 59).padding(.top, -6).padding(.bottom, 8)
            }
            if expanded && (!task.subtasks.isEmpty || adding) {
                ForEach(task.subtasks) { child in
                    SubtaskLine(child: child, editing: editingChild == child.id, title: $childEditText,
                                focus: $childEditFocus,
                                toggle: { store.toggleSubtask(task.id, id: child.id) },
                                edit: { if finishChildren() { editingChild = child.id; childEditText = child.title; childEditFocus = child.id } },
                                finish: { save in _ = finishChildEdit(save: save) },
                                delete: { store.deleteSubtask(task.id, id: child.id) })
                }
                if adding {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").foregroundColor(Palette.secondary)
                        TextField("输入子待办…", text: $childTitle).textFieldStyle(.plain)
                            .focused($addingFocus).onSubmit { _ = submitChild(keepOpen: true) }
                            .background(OutsideTextInput { _ = submitChild(keepOpen: false) })
                            .onExitCommand(perform: cancelAdding)
                    }.font(.system(size: 12)).padding(.leading, 59).padding(.trailing, 16).padding(.vertical, 9)
                }
            }
        }
        .onAppear { if initiallyExpanded && !task.subtasks.isEmpty { expanded = true } }
        .onChange(of: task.subtasks.count) { count in
            if count == 0 && !adding { expanded = false }
        }
        .onChange(of: addingFocus) { if !$0 && adding { _ = submitChild(keepOpen: false) } }
        .onChange(of: childEditFocus) { if $0 == nil { _ = finishChildEdit(save: true) } }
        .onReceive(NotificationCenter.default.publisher(for: .dailyCommitEdits)) { notification in
            if !finishChildren() { (notification.object as? EditCommitRequest)?.succeeded = false }
        }
        .alert("删除事项？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: delete)
        } message: { Text("此事项包含 \(task.subtasks.count) 个子待办，将一并删除。") }
    }

    private func beginAdding() {
        finish(true)
        guard finishChildren() else { return }
        expanded = true; adding = true; addingFocus = true
    }
    private func requestDelete() {
        if task.subtasks.isEmpty { delete() } else { confirmDelete = true }
    }
    @discardableResult private func submitChild(keepOpen: Bool) -> Bool {
        guard adding else { return true }
        let hasTitle = !childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasTitle {
            guard store.addSubtask(task.id, title: childTitle) else { addingFocus = true; return false }
        }
        childTitle = ""
        adding = keepOpen
        addingFocus = keepOpen
        if !keepOpen && task.subtasks.isEmpty && !hasTitle { expanded = false }
        return true
    }
    private func cancelAdding() {
        adding = false
        childTitle = ""
        addingFocus = false
        if task.subtasks.isEmpty { expanded = false }
    }
    private func finishChildEdit(save: Bool) -> Bool {
        guard let id = editingChild else { return true }
        if save, !childEditText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !store.editSubtask(task.id, id: id, title: childEditText) { childEditFocus = id; return false }
        editingChild = nil; childEditFocus = nil
        return true
    }
    private func finishChildren() -> Bool { finishChildEdit(save: true) && submitChild(keepOpen: false) }
}

private struct SubtaskLine: View {
    let child: Subtask
    let editing: Bool
    @Binding var title: String
    var focus: FocusState<UUID?>.Binding
    let toggle: () -> Void
    let edit: () -> Void
    let finish: (Bool) -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: toggle) {
                ZStack {
                    Circle().fill(child.completed ? Palette.accent : .clear)
                    Circle().stroke(child.completed ? Palette.accent : Palette.outline, lineWidth: 1)
                    if child.completed { Image(systemName: "checkmark").font(.system(size: 8, weight: .semibold)).foregroundColor(Palette.checkInk) }
                }.frame(width: 15, height: 15).padding(.vertical, 2).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(child.completed ? "子待办标为未完成" : "完成子待办")
            if editing {
                TextField("子待办", text: $title).textFieldStyle(.plain).focused(focus, equals: child.id)
                    .onSubmit { finish(true) }.onExitCommand { finish(false) }
                    .background(OutsideTextInput { finish(true) })
            } else {
                Text(child.title).foregroundColor(child.completed ? Palette.secondary : Palette.ink)
                    .strikethrough(child.completed).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true).onTapGesture(count: 2, perform: edit)
            }
            Button(action: delete) { Image(systemName: "xmark").font(.system(size: 9)).frame(width: 22, height: 20).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundColor(Palette.secondary).opacity(hovering || editing ? 1 : 0)
                .allowsHitTesting(hovering || editing).help("删除子待办")
        }.font(.system(size: 12)).padding(.leading, 59).padding(.trailing, 12).padding(.vertical, 7)
            .contentShape(Rectangle()).onHover { hovering = $0 }
            .contextMenu { Button("编辑", action: edit); Button("删除", role: .destructive, action: delete) }
    }

}

// AppKit text fields keep focus when clicking a non-focusable label or blank area.
// Commit explicitly on outside mouse-down, after asking the native editor to end editing.
private struct OutsideTextInput: NSViewRepresentable {
    let commit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(commit: commit) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.commit = commit }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator {
        weak var view: NSView?
        var commit: () -> Void
        private var monitor: Any?
        init(commit: @escaping () -> Void) { self.commit = commit }
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let view = self.view, let window = view.window else { return event }
                if event.window !== window || !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                    if window.makeFirstResponder(nil) { self.commit() }
                }
                return event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { stop() }
    }
}
