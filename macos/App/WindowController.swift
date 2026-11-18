import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let dailyCommitEdits = Notification.Name("Daily.commitEdits")
    static let dailyEditFocusedTask = Notification.Name("Daily.editFocusedTask")
    static let dailyCancelDrag = Notification.Name("Daily.cancelDrag")
}

@MainActor final class EditCommitRequest { var succeeded = true }

@MainActor final class WindowController: ObservableObject {
    static func commitEdits() -> Bool {
        let request = EditCommitRequest()
        NotificationCenter.default.post(name: .dailyCommitEdits, object: request)
        return request.succeeded
    }

    @Published var focusInput = false
    private let defaults: UserDefaults
    private(set) weak var window: NSWindow?
    private var eventMonitor: Any?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: "dailyPinned")
        defaults.removeObject(forKey: "dailyEdgeDocking")
    }

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        self.window = window
        window.identifier = NSUserInterfaceItemIdentifier("Daily.main")
        window.level = .normal
        if defaults.object(forKey: "NSWindow Frame Daily.main.frame") != nil {
            window.setFrameUsingName("Daily.main.frame")
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
                window.center()
            }
        }
        window.setFrameAutosaveName("Daily.main.frame")
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.type == .keyDown, event.keyCode == 120, !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
                NotificationCenter.default.post(name: .dailyEditFocusedTask, object: event.window)
                return nil
            }
            if event.type == .keyDown, event.keyCode == 53 {
                NotificationCenter.default.post(name: .dailyCancelDrag, object: nil)
            }
            return event
        }
    }

    func show(focus: Bool = false) {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        if focus { focusInput = true }
    }

    func minimize() {
        guard Self.commitEdits() else { return }
        window?.miniaturize(nil)
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

struct WindowAttachment: NSViewRepresentable {
    @ObservedObject var controller: WindowController
    func makeNSView(context: Context) -> AttachmentView { AttachmentView(controller: controller) }
    func updateNSView(_ view: AttachmentView, context: Context) {}
    final class AttachmentView: NSView {
        let controller: WindowController
        init(controller: WindowController) { self.controller = controller; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { controller.attach(window) }
        }
    }
}

@MainActor final class DailyApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var store: TaskStore?
    weak var windows: WindowController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.show()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard WindowController.commitEdits(), store?.hasSaveFailure != true else { return .terminateCancel }
        return .terminateNow
    }
}

// A single row of quiet icon controls, shared by the menu panel and previews.
struct MenuPanelToolbar: View {
    let showWindow: () -> Void
    let minimizeWindow: () -> Void
    let checkUpdates: () -> Void
    let quit: () -> Void
    var isUpdating = false
    var hasUpdate = false

    var body: some View {
        HStack(spacing: 6) {
            control("macwindow", label: "打开主窗口", action: showWindow)
            control("minus.rectangle", label: "最小化主窗口到 Dock，Daily 继续运行", action: minimizeWindow)
            Spacer(minLength: 0)
            control("arrow.clockwise", label: hasUpdate ? "查看可用更新" : "检查更新", action: checkUpdates)
                .overlay(alignment: .topTrailing) {
                    if hasUpdate { Circle().fill(Palette.accent).frame(width: 5, height: 5).padding(4).allowsHitTesting(false) }
                }
                .disabled(isUpdating)
            control("power", label: "退出 Daily", action: quit)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Palette.background)
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.secondary).frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
