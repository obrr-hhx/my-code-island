#!/usr/bin/env swift
// swift tools/clawd_preview.swift

func q(_ ch: Character) -> (Int,Int,Int,Int) {
    switch ch {
    case " ": return (0,0,0,0); case "▐": return (0,1,0,1); case "▌": return (1,0,1,0)
    case "█": return (1,1,1,1); case "▛": return (1,1,1,0); case "▜": return (1,1,0,1)
    case "▝": return (0,1,0,0); case "▘": return (1,0,0,0); case "▗": return (0,0,0,1)
    case "▟": return (0,1,1,1); case "▙": return (1,0,1,1); case "▖": return (0,0,1,0)
    default:  return (0,0,0,0)
    }
}

func convert(_ chars: [Character], padTo: Int = 0) -> ([Int], [Int]) {
    var top: [Int] = []; var bot: [Int] = []
    for ch in chars { let p = q(ch); top += [p.0, p.1]; bot += [p.2, p.3] }
    while top.count < padTo { top.insert(0, at: 0); top.append(0); bot.insert(0, at: 0); bot.append(0) }
    return (top, bot)
}

// Pad head row with 1 extra on LEFT (not centered) to align with body
var (r1t, r1b) = convert(Array(" ▐▛███▜▌"))
// Currently 16px, need 18. Add 1 left + 1 right → but shift left by inserting 2 on right, 0 on left
// Original centered padding adds 1 each side. We want to shift left 1, so: 0 left, 2 right.
r1t = r1t + [0, 0]; r1b = r1b + [0, 0]
let (r2t, r2b) = convert(Array("▝▜█████▛▘"))
let (r3t, r3b) = convert(Array("  ▘▘ ▝▝  "))

let subRows = [r1t, r1b, r2t, r2b, r3t, r3b]

print()
print("  Clawd (height-doubled)")
print()
for row in subRows {
    var line = "    "
    for px in row { line += px == 1 ? "██" : "  " }
    print("\(line)")
    print("\(line)")
}

print()
print("  Original terminal:")
print("      ▐▛███▜▌")
print("     ▝▜█████▛▘")
print("       ▘▘ ▝▝")
print()
