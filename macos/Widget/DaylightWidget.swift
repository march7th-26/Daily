import SwiftUI
import WidgetKit

struct DailyEntry: TimelineEntry {
    let date: Date
    let tasks: [Todo]
    var failed = false
}
struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: Date(), tasks: [Todo(title: "读几页喜欢的书"), Todo(title: "出去走走", completed: true)])
    }
    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        // The app explicitly reloads this widget kind after each successful save.
        // A periodic reload competes with WidgetKit's daily budget and can make
        // changes appear stale; there are no time-based task changes to predict.
        completion(Timeline(entries: [entry()], policy: .never))
    }
    private func entry() -> DailyEntry {
        do {
            return DailyEntry(date: Date(), tasks: try TaskDisk.read().filter { $0.archivedAt == nil })
        } catch { return DailyEntry(date: Date(), tasks: [], failed: true) }
    }
}
// Resolve concrete RGB colors from WidgetKit's own environment. NSColor providers
// can be flattened while WidgetKit archives a view for Notification Center.
struct WidgetColors {
    let dark: Bool
    var background: Color { dark ? Color(red: 0.105, green: 0.109, blue: 0.117) : Color(red: 0.967, green: 0.976, blue: 0.969) }
    var ink: Color { dark ? Color(red: 0.91, green: 0.92, blue: 0.94) : Color(red: 0.15, green: 0.20, blue: 0.17) }
    var secondary: Color { dark ? Color(red: 0.59, green: 0.61, blue: 0.65) : Color(red: 0.44, green: 0.51, blue: 0.47) }
    var accent: Color { dark ? Color(red: 0.72, green: 0.65, blue: 0.86) : Color(red: 0.20, green: 0.48, blue: 0.36) }
}
struct DailyWidgetView: View {
    let entry: DailyEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    private var colors: WidgetColors { WidgetColors(dark: scheme == .dark) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("待办").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(entry.date.formatted(.dateTime.month().day())).font(.system(size: 10)).foregroundColor(colors.secondary)
            }
            Text("已完成 \(entry.tasks.filter(\.completed).count) / \(entry.tasks.count) 项")
                .font(.system(size: 11)).foregroundColor(colors.secondary)
            if entry.failed {
                Text("打开应用检查数据共享配置").font(.system(size: 12)).foregroundColor(colors.secondary)
            } else if entry.tasks.isEmpty {
                Text("写下今天的第一件小事吧").font(.system(size: 12)).foregroundColor(colors.secondary)
            } else {
                ForEach(Array(entry.tasks.prefix(family == .systemSmall ? 2 : 3))) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").foregroundColor(colors.accent)
                        Text(task.title).strikethrough(task.completed).foregroundColor(task.completed ? colors.secondary : colors.ink).lineLimit(1)
                    }.font(.system(size: 12))
                }
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundColor(colors.ink)
            .background(colors.background)
            .widgetURL(URL(string: "daylight://today"))
    }
}
struct DailyWidgetRoot: View {
    let entry: DailyEntry
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if #available(macOS 14.0, *) {
            DailyWidgetView(entry: entry).containerBackground(for: .widget) {
                WidgetColors(dark: scheme == .dark).background
            }
        } else {
            DailyWidgetView(entry: entry)
        }
    }
}
@main struct DaylightWidget: Widget {
    let kind = "DaylightWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyProvider()) { entry in
            DailyWidgetRoot(entry: entry)
        }
        .configurationDisplayName("Daily")
        .description("随手记下，慢慢完成。点击打开应用。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
