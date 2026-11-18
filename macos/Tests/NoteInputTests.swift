import AppKit
import SwiftUI

@main struct NoteInputTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var committed = ""
        var composing = false
        let editor = NoteTextEditor(text: Binding(get: { committed }, set: { committed = $0 }), composing: Binding(get: { composing }, set: { composing = $0 }))
        let coordinator = editor.makeCoordinator()
        let view = NoteInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        view.font = .systemFont(ofSize: 14)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.textContainer?.lineFragmentPadding = 0
        view.delegate = coordinator
        coordinator.view = view
        view.didUpdateInput = { coordinator.synchronize() }
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        precondition(view.showsPlaceholder)
        precondition(view.placeholderOrigin == view.textContainerOrigin)
        let none = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("aa", selectedRange: NSRange(location: 2, length: 0), replacementRange: none)
        precondition(view.hasMarkedText() && !view.showsPlaceholder && composing)
        precondition(committed.isEmpty, "Provisional input leaked into saved draft")
        precondition(!WindowController.commitEdits(), "Unconfirmed composition could be archived on exit")
        view.insertText("啊啊", replacementRange: none)
        precondition(!view.hasMarkedText() && !composing && committed == "啊啊")
        precondition(WindowController.commitEdits())
        view.insertText("\n第二行 📝", replacementRange: none)
        precondition(committed == "啊啊\n第二行 📝" && !view.showsPlaceholder)
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.insertText("", replacementRange: none)
        precondition(view.showsPlaceholder && committed.isEmpty)
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: none)
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.insertText("", replacementRange: none)
        precondition(!composing && view.showsPlaceholder && committed.isEmpty)
        view.insertText("Hello", replacementRange: none)
        precondition(committed == "Hello")
        print("PASS: AppKit marked-text composition, commit/cancel, placeholder, multiline, English and exit guard")
    }
}
