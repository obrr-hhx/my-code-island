import AppKit
import SwiftUI

/// An NSPanel subclass that accepts mouse clicks even when
/// the app is not the active (frontmost) application.
final class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }
}

/// An NSHostingView subclass that accepts first-mouse clicks.
/// Without this, SwiftUI buttons inside a non-key window are
/// completely unresponsive — the first click is swallowed by
/// the system to activate the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // Prevent NSHostingView from auto-resizing the window, which causes
        // recursive layout crashes in borderless panels.
        if #available(macOS 13.0, *) {
            self.sizingOptions = []
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Recursively set acceptsFirstMouse on all subviews.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enableFirstMouse(in: self)
    }

    private func enableFirstMouse(in view: NSView) {
        for subview in view.subviews {
            enableFirstMouse(in: subview)
        }
    }
}
