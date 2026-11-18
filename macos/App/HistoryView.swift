import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
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
            HStack {
                Text("共 \(store.archivedItems.count) 项").font(.caption).foregroundColor(Palette.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20)
    }
}
