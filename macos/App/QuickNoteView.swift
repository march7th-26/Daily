import SwiftUI
import AppKit

struct QuickNoteView: View {
    @EnvironmentObject private var journal: JournalStore
    @State private var composing = false
    @State private var archived = false

    var body: some View {
        VStack(spacing: 10) {
            NoteTextEditor(text: $journal.draft, composing: $composing, placeholder: "随手记下此刻的想法…", autofocus: true)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 0.7))
            if let error = journal.error {
                Text(error).font(.system(size: 11)).foregroundColor(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                if archived {
                    Text("已归档到历史记录").font(.system(size: 11)).foregroundColor(Palette.secondary)
                }
                Spacer(minLength: 0)
                icon("archivebox", label: "归档为日志") {
                    if journal.archive() { archived = true }
                }.foregroundColor(Palette.accent)
                    .disabled(composing || journal.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                icon("power", label: "退出 Daily") { NSApp.terminate(nil) }.foregroundColor(Palette.secondary)
            }
        }
        .padding(14).frame(width: 360, height: 300).background(Palette.background)
        .onDisappear { journal.flush() }
        .onChange(of: journal.draft) { if !$0.isEmpty { archived = false } }
    }

    private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct JournalEditor: View {
    let entry: JournalEntry
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var composing = false

    init(entry: JournalEntry) { self.entry = entry; _text = State(initialValue: entry.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12)).foregroundColor(Palette.secondary)
            NoteTextEditor(text: $text, composing: $composing)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if let error = journal.error { Text(error).font(.caption) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { if journal.edit(entry.id, text: text) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(composing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(minWidth: 360, idealWidth: 440, minHeight: 320)
            .foregroundColor(Palette.ink).tint(Palette.accent).background(Palette.background)
    }
}


// Keep both committed text and marked IME text in AppKit's single layout system.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var composing: Bool
    var placeholder = ""
    var autofocus = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = NoteInputView(frame: .zero)
        view.isRichText = false
        view.importsGraphics = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 14)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph]
        view.placeholder = placeholder
        view.autofocus = autofocus
        view.string = text
        view.setAccessibilityLabel("速记内容")
        view.delegate = context.coordinator
        view.didUpdateInput = { [weak coordinator = context.coordinator] in coordinator?.synchronize() }
        context.coordinator.view = view
        scroll.documentView = view
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.owner = self
        guard let view = scroll.documentView as? NoteInputView else { return }
        // A SwiftUI render must never replace the input method's marked range.
        if !view.hasMarkedText(), view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, view.string.utf16.count), length: 0))
        }
        view.placeholder = placeholder
        view.textColor = NSColor(Palette.ink)
        view.insertionPointColor = NSColor(Palette.accent)
        view.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: NoteTextEditor
        weak var view: NoteInputView?
        private var observer: NSObjectProtocol?

        init(_ owner: NoteTextEditor) {
            self.owner = owner
            super.init()
            observer = NotificationCenter.default.addObserver(forName: .dailyCommitEdits, object: nil, queue: .main) { [weak self] notification in
                guard let self, let view = self.view else { return }
                if view.hasMarkedText() {
                    (notification.object as? EditCommitRequest)?.succeeded = false
                } else { self.synchronize() }
            }
        }
        func textDidChange(_ notification: Notification) { synchronize() }
        func synchronize() {
            guard let view else { return }
            let marked = view.hasMarkedText()
            if owner.composing != marked { owner.composing = marked }
            if !marked, owner.text != view.string { owner.text = view.string }
            view.needsDisplay = true
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

final class NoteInputView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var autofocus = false
    var didUpdateInput: (() -> Void)?
    var showsPlaceholder: Bool { string.isEmpty && !hasMarkedText() }
    var placeholderOrigin: NSPoint {
        NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder else { return }
        var attributes = typingAttributes
        attributes[.font] = font ?? NSFont.systemFont(ofSize: 14)
        attributes[.foregroundColor] = NSColor(Palette.secondary)
        (placeholder as NSString).draw(at: placeholderOrigin, withAttributes: attributes)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        didUpdateInput?()
        needsDisplay = true
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        didUpdateInput?()
        needsDisplay = true
    }
    override func unmarkText() {
        super.unmarkText()
        didUpdateInput?()
        needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard autofocus, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}
