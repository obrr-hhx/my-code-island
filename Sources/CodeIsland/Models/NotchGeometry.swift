import AppKit
import SwiftUI

/// Describes the notch layout relative to our panel.
/// The panel is wider than the notch, with visible "wings" on each side.
///
/// Panel layout:
///   [  left wing  |  notch (hidden)  |  right wing  ]
///   |<-leftWidth->|<---notchWidth--->|<-rightWidth->|
struct NotchGeometry {
    /// Width of the visible area LEFT of the notch.
    let leftWidth: CGFloat
    /// Width of the physical notch (content here is hidden).
    let notchWidth: CGFloat
    /// Width of the visible area RIGHT of the notch.
    let rightWidth: CGFloat
    /// Height of the notch area.
    let height: CGFloat

    /// Total panel width.
    var totalWidth: CGFloat { leftWidth + notchWidth + rightWidth }

    /// Detect and calculate from the current screen.
    static func detect(paddingLeft: CGFloat, paddingRight: CGFloat) -> NotchGeometry {
        guard let screen = NSScreen.screens.first(where: { hasNotch($0) }),
              #available(macOS 12.0, *),
              let topLeft = screen.auxiliaryTopLeftArea,
              let topRight = screen.auxiliaryTopRightArea else {
            // No notch fallback
            return NotchGeometry(
                leftWidth: paddingLeft,
                notchWidth: 0,
                rightWidth: paddingRight,
                height: 32
            )
        }

        let nWidth = topRight.minX - topLeft.maxX
        return NotchGeometry(
            leftWidth: paddingLeft,
            notchWidth: nWidth,
            rightWidth: paddingRight,
            height: topLeft.height
        )
    }

    private static func hasNotch(_ screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 0
        }
        return false
    }
}
