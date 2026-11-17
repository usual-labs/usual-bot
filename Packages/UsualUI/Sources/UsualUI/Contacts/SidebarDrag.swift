import CoreGraphics
import HermesKit

/// Where a dragged chat would land.
enum SidebarDropTarget: Hashable {
    /// A section, the chats in no section, or the pinned chats' empty space.
    case block(SidebarBlock.ID)
    /// The place of a pinned chat.
    case pin(Contact.ID)
}

/// Where the sections and pinned chats are, in the sidebar's coordinate space. Not observed: only
/// a drag reads it, so a change shouldn't redraw the sidebar.
final class SidebarDragGeometry {
    static let space = "sidebarDrag"
    var blocks: [SidebarBlock.ID: CGRect] = [:]
    var pins: [Contact.ID: CGRect] = [:]
}

/// What a chat dropped on the sidebar does. On a pinned chat it takes that one's place, pinned if it
/// wasn't. On the pinned chats' empty space it's pinned last. On a section it leaves the pinned
/// chats and is filed there; with no sections, it only leaves the pinned chats.
struct SidebarDropRules {
    let blocks: [SidebarBlock]
    let isGrouped: Bool
    let geometry: SidebarDragGeometry

    func target(for contact: Contact, at point: CGPoint) -> SidebarDropTarget? {
        let pinned = blocks.first(where: \.isPinned)?.contacts.map(\.id) ?? []
        if let pin = pinned.first(where: { geometry.pins[$0]?.contains(point) == true }) {
            return pin == contact.id ? nil : .pin(pin)
        }
        guard let block = blocks.first(where: { geometry.blocks[$0.id]?.contains(point) == true }) else { return nil }
        if block.isPinned { return contact.isPinned ? nil : .block(block.id) }
        return isGrouped || contact.isPinned ? .block(block.id) : nil
    }
}

#if os(macOS)
    import AppKit
    import SwiftUI

    // The sidebar drags in AppKit, not SwiftUI. A SwiftUI drop destination keeps the drag picture
    // frozen on screen for about a third of a second after the drop, even when the drop is handled
    // at once; AppKit takes it away as the mouse comes up.

    @MainActor enum SidebarDragging {
        /// The chat being dragged, while one is.
        static var id: Contact.ID?
        static let type = NSPasteboard.PasteboardType("dev.usualbot.sidebar-chat")
    }

    /// Lies over a row or tile without taking its clicks, and drags its chat when the mouse pressed
    /// on it moves a few points.
    struct SidebarDragSource<Preview: View>: NSViewRepresentable {
        let id: Contact.ID
        @ViewBuilder let preview: () -> Preview
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.botPictures) private var pictures

        func makeNSView(context: Context) -> SidebarDragSourceView { SidebarDragSourceView() }

        func updateNSView(_ view: SidebarDragSourceView, context: Context) {
            view.id = id
            let preview = preview().environment(\.colorScheme, colorScheme).environment(\.botPictures, pictures)
            view.makeImage = { scale in
                let renderer = ImageRenderer(content: preview)
                renderer.scale = scale
                return renderer.nsImage
            }
        }

        static func dismantleNSView(_ view: SidebarDragSourceView, coordinator: ()) { view.stopWatching() }
    }

    final class SidebarDragSourceView: NSView, NSDraggingSource {
        var id: Contact.ID = ""
        var makeImage: (CGFloat) -> NSImage? = { _ in nil }
        private var monitor: Any?
        private var pressed: NSPoint?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopWatching()
            guard window != nil else { return }
            // The row's button takes the clicks, so the press is watched rather than received.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
                [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stopWatching() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window else { return }
            let point = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDown:
                pressed = bounds.contains(point) && !event.modifierFlags.contains(.control) ? point : nil
            case .leftMouseDragged:
                guard let start = pressed, hypot(point.x - start.x, point.y - start.y) > 4 else { return }
                pressed = nil
                begin(event, at: point)
            default:
                pressed = nil
            }
        }

        private func begin(_ event: NSEvent, at point: NSPoint) {
            let item = NSPasteboardItem()
            item.setString(id, forType: SidebarDragging.type)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let image = makeImage(window?.backingScaleFactor ?? 2) ?? NSImage(size: NSSize(width: 32, height: 32))
            let size = image.size
            dragging.setDraggingFrame(
                NSRect(
                    x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
                contents: image)
            SidebarDragging.id = id
            beginDraggingSession(with: [dragging], event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            SidebarDragging.id = nil
        }
    }

    /// Lies over the whole sidebar and takes the dragged chat. It lets itself be found only while a
    /// chat is being dragged, so clicks and scrolling pass through it.
    struct SidebarDropLayer: NSViewRepresentable {
        /// Where a chat dropped at a point would land, in the sidebar's coordinate space.
        let target: (Contact.ID, CGPoint) -> SidebarDropTarget?
        @Binding var highlighted: SidebarDropTarget?
        let drop: (Contact.ID, SidebarDropTarget) -> Void

        func makeNSView(context: Context) -> SidebarDropLayerView { SidebarDropLayerView() }

        func updateNSView(_ view: SidebarDropLayerView, context: Context) {
            view.target = target
            view.highlight = { target in
                if highlighted != target { highlighted = target }
            }
            view.drop = drop
        }
    }

    final class SidebarDropLayerView: NSView {
        var target: (Contact.ID, CGPoint) -> SidebarDropTarget? = { _, _ in nil }
        var highlight: (SidebarDropTarget?) -> Void = { _ in }
        var drop: (Contact.ID, SidebarDropTarget) -> Void = { _, _ in }

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([SidebarDragging.type])
        }

        required init?(coder: NSCoder) { fatalError("Not used.") }

        // SwiftUI's coordinate space runs down the page.
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            SidebarDragging.id != nil && frame.contains(point) ? self : nil
        }

        private func landing(_ info: NSDraggingInfo) -> (Contact.ID, SidebarDropTarget)? {
            guard let id = info.draggingPasteboard.string(forType: SidebarDragging.type),
                let target = target(id, convert(info.draggingLocation, from: nil))
            else { return nil }
            return (id, target)
        }

        private func update(_ info: NSDraggingInfo) -> NSDragOperation {
            let landing = landing(info)
            highlight(landing?.1)
            return landing == nil ? [] : .move
        }

        override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { update(info) }
        override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { update(info) }
        override func draggingExited(_ info: NSDraggingInfo?) { highlight(nil) }

        override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
            highlight(nil)
            guard let (id, target) = landing(info) else { return false }
            drop(id, target)
            return true
        }
    }
#endif
