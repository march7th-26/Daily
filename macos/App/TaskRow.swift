import SwiftUI

struct TaskRow: View {
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
    @State private var hovering = false
    private var actionsVisible: Bool { hovering || isEditing || rowFocus.wrappedValue == task.id }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
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
            HStack(spacing: 3) {
                Button(action: archive) { Image(systemName: "archivebox").frame(width: 22, height: 24).contentShape(Rectangle()) }
                    .help("归档到历史记录").accessibilityLabel("归档：" + task.title)
                Button(action: delete) { Image(systemName: "xmark").frame(width: 22, height: 24).contentShape(Rectangle()) }
                    .accessibilityLabel("删除：" + task.title)
            }.font(.system(size: 10)).foregroundColor(Palette.secondary).buttonStyle(.plain)
                .opacity(actionsVisible ? 1 : 0).allowsHitTesting(actionsVisible).accessibilityHidden(!actionsVisible)
        }.padding(.horizontal, 12).padding(.vertical, tight ? 9 : 13)
            .contentShape(Rectangle()).onHover { hovering = $0 }
            .contextMenu {
                Button("编辑", action: edit)
                Button("归档到历史记录", action: archive)
                Button("删除", role: .destructive, action: delete)
            }
    }
}
