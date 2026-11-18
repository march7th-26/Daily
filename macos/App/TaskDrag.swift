import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor final class TaskDrag: ObservableObject {
    @Published var draggedID: UUID?
    @Published var targetID: UUID?
    @Published var after = false
    let pulse = PassthroughSubject<Void, Never>()
    var pointerY: CGFloat?
    private var timer: AnyCancellable?
    private var releasedAt: Date?

    func begin(_ id: UUID) {
        clear()
        draggedID = id
        // Common run-loop mode keeps scrolling during AppKit's native drag session.
        timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                // Let performDrop receive mouse-up before cleaning up a cancelled/outside drag.
                if let releasedAt = self.releasedAt, Date().timeIntervalSince(releasedAt) > 0.3 { self.clear() }
                else if self.releasedAt == nil { self.releasedAt = Date() }
            } else {
                self.releasedAt = nil
                self.pulse.send(())
            }
        }
    }
    func clear() {
        timer?.cancel(); timer = nil
        draggedID = nil; targetID = nil; pointerY = nil; releasedAt = nil
    }
    deinit { timer?.cancel() }
}

struct TaskFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct TaskRowDrop: DropDelegate {
    let task: Todo
    let frame: CGRect
    let store: TaskStore
    let drag: TaskDrag

    func validateDrop(info: DropInfo) -> Bool { drag.draggedID != nil && drag.draggedID != task.id }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { update(info); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) {
        if drag.targetID == task.id { drag.targetID = nil; drag.pointerY = nil }
    }
    func performDrop(info: DropInfo) -> Bool {
        guard let id = drag.draggedID else { return false }
        let after = info.location.y > max(frame.height, 1) / 2
        let result = store.move(id, relativeTo: task.id, after: after)
        drag.clear()
        return result
    }
    private func update(_ info: DropInfo) {
        guard validateDrop(info: info) else { return }
        drag.targetID = task.id
        drag.after = info.location.y > max(frame.height, 1) / 2
        drag.pointerY = frame.minY + info.location.y
    }
}
