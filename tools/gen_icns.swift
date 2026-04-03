#!/usr/bin/env swift
import AppKit

// Clawd pixel grid (default pose, from ClawdSprite)
let o = 0, B = 1, e = 2
let grid: [[Int]] = [
    [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
    [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
    [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
    [o,o,o,B,B,e,B,B,B,B,B,B,e,B,B,o,o,o],
    [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
    [o,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,o],
    [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
    [o,o,o,B,B,B,B,B,B,B,B,B,B,B,B,o,o,o],
    [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
    [o,o,o,o,B,o,B,o,o,o,o,B,o,B,o,o,o,o],
    [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
    [o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o,o],
]

let bodyColor = NSColor(red: 215/255, green: 119/255, blue: 87/255, alpha: 1)
let eyeColor = NSColor.black
let bgColor = NSColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1)

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let rows = grid.count
    let cols = grid[0].count
    let px = floor(s * 0.55 / CGFloat(max(cols, rows)))
    let gridW = CGFloat(cols) * px
    let gridH = CGFloat(rows) * px
    let offsetX = (s - gridW) / 2
    let offsetY = (s - gridH) / 2

    return NSImage(size: NSSize(width: s, height: s), flipped: true) { rect in
        bgColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18).fill()

        for row in 0..<rows {
            for col in 0..<grid[row].count {
                let cell = grid[row][col]
                guard cell != o else { continue }
                let color: NSColor = cell == B ? bodyColor : eyeColor
                color.setFill()
                NSRect(x: offsetX + CGFloat(col) * px, y: offsetY + CGFloat(row) * px, width: px, height: px).fill()
            }
        }
        return true
    }
}

// Generate iconset
let iconsetPath = "Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    let image = renderIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to render \(name)")
        continue
    }
    let path = "\(iconsetPath)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("Generated \(path) (\(size)x\(size))")
}

print("\nNow run: iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns")
