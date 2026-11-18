import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter = "全部"
    @State private var editing: JournalEntry?

    private enum Record: Identifiable {
        case task(Todo), journal(JournalEntry)
        var id: String {
            switch self {
            case .task(let task): return "task-" + task.id.uuidString
            case .journal(let entry): return "journal-" + entry.id.uuidString
            }
        }
        var date: Date {
            switch self {
            case .task(let task): return task.archivedAt ?? .distantPast
            case .journal(let entry): return entry.createdAt
            }
        }
    }
    private var records: [Record] {
        let tasks = filter == "日志" ? [] : store.archivedItems.map(Record.task)
        let notes = filter == "待办" ? [] : journal.entries.map(Record.journal)
        return (tasks + notes).sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("历史记录").font(.system(size: 20, weight: .semibold))
            Picker("记录类型", selection: $filter) {
                ForEach(["全部", "待办", "日志"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if records.isEmpty {
                        Text("暂无记录").font(.system(size: 13)).foregroundColor(Palette.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(records) { record in
                        recordView(record).padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if let error = journal.error { Text(error).font(.caption).foregroundColor(Palette.secondary) }
            HStack {
                Text("共 \(records.count) 项").font(.caption).foregroundColor(Palette.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).foregroundColor(Palette.ink).tint(Palette.accent).background(Palette.background)
            .sheet(item: $editing) { entry in JournalEditor(entry: entry).environmentObject(journal) }
    }

    @ViewBuilder private func recordView(_ record: Record) -> some View {
        switch record {
        case .task(let task):
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title).font(.system(size: 14)).strikethrough(task.completed)
                    Text("待办 · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundColor(Palette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("恢复") { store.restore(task.id) }.buttonStyle(.borderless)
                deleteButton { store.delete(task.id) }
            }
        case .journal(let entry):
            HStack(alignment: .top, spacing: 12) {
                Button { editing = entry } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.text).font(.system(size: 14)).lineSpacing(4).lineLimit(3)
                        Text("日志 · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11)).foregroundColor(Palette.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("查看或编辑日志")
                deleteButton { journal.delete(entry.id) }
            }
        }
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash").font(.system(size: 12)).foregroundColor(Palette.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).help("删除记录").accessibilityLabel("删除记录")
    }
}
