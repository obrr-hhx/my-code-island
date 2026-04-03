import AppKit

/// Renders Clawd pixel art as NSImage for menu bar icon and app icon.
enum ClawdIcon {

    private static let bodyColor = NSColor(
        red: 215.0 / 255.0,
        green: 119.0 / 255.0,
        blue: 87.0 / 255.0,
        alpha: 1.0
    )

    /// Generate a small Clawd NSImage for the menu bar (18x18 target).
    static func menuBarIcon() -> NSImage {
        let grid = ClawdSprite.grid(for: .default_)
        let rows = grid.count
        let cols = grid[0].count

        // Menu bar icons should be ~18pt tall. Our grid is 12 rows.
        // pixelSize = 1.5 → 18x27... too wide. Use 1px per cell, pad to square.
        let px: CGFloat = 1.0
        let w = CGFloat(cols) * px
        let h = CGFloat(rows) * px

        let image = NSImage(size: NSSize(width: w, height: h), flipped: true) { rect in
            for row in 0..<rows {
                for col in 0..<grid[row].count {
                    let cell = grid[row][col]
                    guard cell != .empty else { continue }

                    let color: NSColor = cell == .body ? bodyColor : .black
                    color.setFill()

                    let cellRect = NSRect(
                        x: CGFloat(col) * px,
                        y: CGFloat(row) * px,
                        width: px,
                        height: px
                    )
                    cellRect.fill()
                }
            }
            return true
        }

        image.isTemplate = false  // Keep colors, don't auto-tint
        return image
    }

    /// Generate a large Clawd NSImage for the app icon (512x512).
    static func appIcon(size: CGFloat = 512) -> NSImage {
        let grid = ClawdSprite.grid(for: .default_)
        let rows = grid.count
        let cols = grid[0].count

        let px = floor(size * 0.6 / CGFloat(max(cols, rows)))  // 60% of icon size
        let gridW = CGFloat(cols) * px
        let gridH = CGFloat(rows) * px
        let offsetX = (size - gridW) / 2
        let offsetY = (size - gridH) / 2

        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            // Background: rounded rect
            let bgColor = NSColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1)
            bgColor.setFill()
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
            bgPath.fill()

            // Draw Clawd
            for row in 0..<rows {
                for col in 0..<grid[row].count {
                    let cell = grid[row][col]
                    guard cell != .empty else { continue }

                    let color: NSColor = cell == .body ? bodyColor : .black
                    color.setFill()

                    let cellRect = NSRect(
                        x: offsetX + CGFloat(col) * px,
                        y: offsetY + CGFloat(row) * px,
                        width: px,
                        height: px
                    )
                    cellRect.fill()
                }
            }
            return true
        }
        return image
    }
}
