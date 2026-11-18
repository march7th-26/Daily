import SwiftUI

struct UpdateDetailsView: View {
    @EnvironmentObject private var updates: UpdateStore
    @EnvironmentObject private var store: TaskStore
    @State private var download: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(updates.latestVersion.map { "发现更新 v\($0)" } ?? "检查更新").font(.title3.weight(.semibold))
                Spacer()
                if updates.isBusy { ProgressView().controlSize(.small) }
            }
            Text(updates.status.isEmpty ? "正在读取发布信息…" : updates.status)
                .font(.system(size: 12)).foregroundColor(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(updates.releaseNotes).font(.system(size: 12)).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(12)
            }.background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Link(destination: URL(string: "https://github.com/march7th-26/Daily/issues")!) {
                    Label("用户反馈", systemImage: "bubble.left")
                }.font(.system(size: 11))
                Spacer()
                Button(download == nil ? "关闭" : "取消下载") {
                    download?.cancel()
                    updates.showsDetails = false
                }.keyboardShortcut(.cancelAction)
                if updates.latestVersion != nil {
                    if updates.canInstall {
                        Button("下载并安装") {
                            download = Task {
                                await updates.installUpdate {
                                    WindowController.commitEdits() && store.prepareForUpdate()
                                }
                                download = nil
                            }
                        }.disabled(updates.isBusy)
                    } else { Button("打开下载页") { updates.openRelease() }.disabled(updates.isBusy) }
                }
            }
        }.padding(20).frame(width: 460, height: 380).background(Palette.background).foregroundColor(Palette.ink)
            .onDisappear { download?.cancel() }
    }
}
