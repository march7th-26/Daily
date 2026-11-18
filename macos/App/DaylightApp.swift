import SwiftUI
import AppKit

@main struct DaylightApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var quotes = QuoteStore()
    @StateObject private var updates = UpdateStore()
    @StateObject private var journal = JournalStore()
    @StateObject private var windows = WindowController()
    @NSApplicationDelegateAdaptor(DailyApplicationDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Daily", id: "main") {
            TodoView().environmentObject(journal).environmentObject(store).environmentObject(quotes).environmentObject(updates).environmentObject(windows)
                .frame(minWidth: 280, minHeight: 320)
                .background(WindowAttachment(controller: windows))
                .onAppear { delegate.store = store; delegate.journal = journal; delegate.windows = windows; refresh(); updates.cleanupDownloads() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
                .onOpenURL { _ in showMainWindow() }
                .sheet(isPresented: $updates.showsDetails) { UpdateDetailsView().environmentObject(updates).environmentObject(store) }
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.hiddenTitleBar).windowResizability(.automatic)
        MenuBarExtra("Daily", systemImage: "checkmark.circle") {
            QuickNoteView().environmentObject(journal)
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
