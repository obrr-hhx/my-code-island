import AppKit
import SwiftUI

/// Manages the floating NSPanel that visually extends the MacBook notch.
///
/// How it works: macOS has no "Dynamic Island" API. The notch is just a black
/// physical cutout. We place a black-background window ON TOP of the notch area
/// (at a very high window level), slightly wider than the notch itself. Because
/// both the notch and our panel are black, they blend seamlessly — creating the
/// illusion that the notch is "expanding" like iOS Dynamic Island.
@MainActor
final class NotchPanelController {
    private var panel: NSPanel?
    private let appState: AppState

    /// Padding on the LEFT side (space for Clawd logo + text).
    private let notchPaddingLeft: CGFloat = 100
    /// Padding on the RIGHT side (space for status dots).
    private let notchPaddingRight: CGFloat = 80

    /// Expanded width
    private let expandedWidth: CGFloat = 380
    /// Expanded height (drops down from notch)
    private let expandedHeight: CGFloat = 420

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        let collapsed = collapsedSize()
        let panel = ClickThroughPanel(
            contentRect: NSRect(origin: .zero, size: collapsed),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        // Compute notch geometry for SwiftUI layout
        let geometry = NotchGeometry.detect(
            paddingLeft: notchPaddingLeft,
            paddingRight: notchPaddingRight
        )

        // Host SwiftUI content with first-mouse support
        let contentView = NotchContentView(appState: appState, panelController: self, notchGeometry: geometry)
        let hostingView = FirstMouseHostingView(rootView: contentView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // Position over the notch
        positionPanel(panel, expanded: false)
        panel.orderFrontRegardless()

        self.panel = panel

        // Monitor screen changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                self.positionPanel(panel, expanded: self.appState.isExpanded)
            }
        }
    }

    /// Toggle between collapsed and expanded states with smooth animation.
    func setExpanded(_ expanded: Bool) {
        guard let panel else { return }

        panel.hasShadow = expanded

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let frame = frameForPanel(expanded: expanded)
            panel.animator().setFrame(frame, display: true)
        }

        if expanded {
            // Make the panel key so buttons are clickable immediately.
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Notch Geometry

    /// Get the notch rect in screen coordinates, or nil if no notch.
    private func notchRect(on screen: NSScreen) -> NSRect? {
        guard #available(macOS 12.0, *),
              let topLeft = screen.auxiliaryTopLeftArea,
              let topRight = screen.auxiliaryTopRightArea else {
            return nil
        }

        // The notch gap is between the left and right auxiliary areas
        let notchX = topLeft.maxX + screen.frame.origin.x
        let notchWidth = topRight.minX - topLeft.maxX
        let notchY = topLeft.origin.y + screen.frame.origin.y  // Y in global coords
        let notchHeight = topLeft.height

        return NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
    }

    /// Collapsed size: wider than the notch, asymmetric (more room on left for Clawd).
    private func collapsedSize() -> NSSize {
        let screen = notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        if let notch = notchRect(on: screen) {
            return NSSize(width: notch.width + notchPaddingLeft + notchPaddingRight, height: notch.height)
        }
        return NSSize(width: 300, height: 32)
    }

    // MARK: - Positioning

    private func positionPanel(_ panel: NSPanel, expanded: Bool) {
        let frame = frameForPanel(expanded: expanded)
        panel.setFrame(frame, display: true)
    }

    private func frameForPanel(expanded: Bool) -> NSRect {
        let screen = notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]

        if let notch = notchRect(on: screen) {
            if expanded {
                // Expanded: wider panel, top aligned with screen top, drops down
                let width = expandedWidth
                let height = expandedHeight
                let x = notch.midX - width / 2
                let y = screen.frame.maxY - height
                return NSRect(x: x, y: y, width: width, height: height)
            } else {
                // Collapsed: cover the notch, more room on the left for Clawd
                let width = notch.width + notchPaddingLeft + notchPaddingRight
                let height = notch.height
                let x = notch.origin.x - notchPaddingLeft
                // Top-aligned with the notch (which is at the top of the screen)
                let y = notch.origin.y
                return NSRect(x: x, y: y, width: width, height: height)
            }
        } else {
            // No notch: floating bar at top-center
            let width = expanded ? expandedWidth : CGFloat(260)
            let height = expanded ? expandedHeight : CGFloat(32)
            let x = screen.frame.midX - width / 2
            let y = screen.frame.maxY - height - 4
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Find the screen with a notch (built-in display).
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { screenHasNotch($0) }
    }

    private func screenHasNotch(_ screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 0
        }
        return false
    }
}
