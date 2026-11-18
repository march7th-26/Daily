import SwiftUI
import AppKit

@main struct DaylightApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var quotes = QuoteStore()
    @StateObject private var updates = UpdateStore()
    @StateObject private var windows = WindowController()
    @NSApplicationDelegateAdaptor(DailyApplicationDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Daily", id: "main") {
            TodoView().environmentObject(store).environmentObject(quotes).environmentObject(updates).environmentObject(windows)
                .frame(minWidth: 280, minHeight: 320)
                .background(WindowAttachment(controller: windows))
                .onAppear { delegate.store = store; delegate.windows = windows; refresh(); updates.cleanupDownloads() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
                .onOpenURL { _ in showMainWindow() }
                .sheet(isPresented: $updates.showsDetails) { UpdateDetailsView().environmentObject(updates).environmentObject(store) }
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.hiddenTitleBar).windowResizability(.automatic)
        MenuBarExtra("Daily", systemImage: "checkmark.circle") {
            VStack(spacing: 0) {
                TodoView(compact: true).environmentObject(store).environmentObject(quotes).environmentObject(updates).environmentObject(windows)
                Divider()
                MenuPanelToolbar(
                    showWindow: { showMainWindow() },
                    minimizeWindow: { windows.minimize() },
                    checkUpdates: {
                        showMainWindow(focus: false)
                        Task { await updates.presentDetails() }
                    },
                    quit: { NSApp.terminate(nil) },
                    isUpdating: updates.isBusy,
                    hasUpdate: updates.latestVersion != nil
                )
            }.frame(width: 360, height: 520).onAppear { store.synchronize() }
        }.menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建待办") { showMainWindow() }.keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    @MainActor private func refresh() {
        store.synchronize()
        Task {
            await quotes.refresh(for: Date())
            await updates.checkIfNeeded()
        }
    }
    @MainActor private func showMainWindow(focus: Bool = true) {
        store.synchronize()
        if windows.window?.isVisible != true { openWindow(id: "main") }
        DispatchQueue.main.async { windows.show(focus: focus) }
    }
}
