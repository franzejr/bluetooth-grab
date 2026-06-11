// make-icon.swift — draw the Bluetooth logo (white on blue) as an iconset.
// Usage:  swift make-icon.swift <output-iconset-dir>
//
// The Bluetooth mark is one continuous stroke through these points (logo space,
// x in [-1,1], y in [-2,2], y up): the two right "knees" connect to the top and
// bottom of the central spine, and the crossing diagonals run out to the left.

import AppKit

let outDir = CommandLine.arguments[1]

let bluetoothBlue = NSColor(srgbRed: 0.0, green: 0.51, blue: 0.99, alpha: 1.0)

// (filename, pixel size) — the sizes `iconutil` expects in an .iconset.
let variants: [(String, Int)] = [
  ("icon_16x16", 16),   ("icon_16x16@2x", 32),
  ("icon_32x32", 32),   ("icon_32x32@2x", 64),
  ("icon_128x128", 128),("icon_128x128@2x", 256),
  ("icon_256x256", 256),("icon_256x256@2x", 512),
  ("icon_512x512", 512),("icon_512x512@2x", 1024),
]

let logoPoints: [(CGFloat, CGFloat)] =
  [(-1, 1), (1, -1), (0, -2), (0, 2), (1, 1), (-1, -1)]

func drawIcon(size: Int) -> NSBitmapImageRep {
  let s = CGFloat(size)
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: s, height: s)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

  // Rounded-rect ("squircle"-ish) tile with the standard macOS margin.
  let inset = s * 0.098
  let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
  let radius = rect.width * 0.2237
  let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
  bluetoothBlue.setFill()
  tile.fill()

  // White Bluetooth mark, centered, ~50% of canvas height.
  let unit = (s * 0.5) / 4.0
  let cx = s / 2, cy = s / 2
  let mark = NSBezierPath()
  for (i, p) in logoPoints.enumerated() {
    let pt = NSPoint(x: cx + p.0 * unit, y: cy + p.1 * unit)
    if i == 0 { mark.move(to: pt) } else { mark.line(to: pt) }
  }
  mark.lineWidth = s * 0.072
  mark.lineJoinStyle = .round
  mark.lineCapStyle = .round
  NSColor.white.setStroke()
  mark.stroke()

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

for (name, size) in variants {
  let rep = drawIcon(size: size)
  guard let data = rep.representation(using: .png, properties: [:]) else { continue }
  let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
  try! data.write(to: url)
}
print("icons written to \(outDir)")
