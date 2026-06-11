import AppKit

private let pixelsPath = (stateDir as NSString).appendingPathComponent("pixels.json")

final class PixelCanvasView: NSView {
    static let n = 16
    var pixels: [[Bool]] = Array(repeating: Array(repeating: false, count: n), count: n)
    var onChange: (() -> Void)?
    private var paintMode: Bool? = nil   // true=画, false=擦, nil=未按下

    var pixelCount: Int { pixels.flatMap { $0 }.filter { $0 }.count }

    override init(frame: NSRect) { super.init(frame: frame); loadPixels() }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Helpers

    func inCircle(_ col: Int, _ row: Int) -> Bool {
        let n = Double(Self.n)
        let cx = (n - 1) / 2, cy = (n - 1) / 2
        let dx = Double(col) - cx, dy = Double(row) - cy
        return sqrt(dx*dx + dy*dy) <= n / 2 - 0.3
    }

    var cellSize: CGFloat { bounds.width / CGFloat(Self.n) }

    func cellAt(_ p: NSPoint) -> (Int, Int)? {
        let s = cellSize
        let col = Int(p.x / s), row = Self.n - 1 - Int(p.y / s)
        guard (0..<Self.n).contains(col), (0..<Self.n).contains(row),
              inCircle(col, row) else { return nil }
        return (col, row)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let s = cellSize
        for row in 0..<Self.n {
            for col in 0..<Self.n {
                let rect = NSRect(x: CGFloat(col) * s,
                                  y: bounds.height - CGFloat(row + 1) * s,
                                  width: s, height: s)
                if !inCircle(col, row) {
                    NSColor.black.withAlphaComponent(0.25).setFill()
                    NSBezierPath(rect: rect).fill()
                } else if pixels[row][col] {
                    colAmber.setFill()
                    NSBezierPath(rect: rect).fill()
                } else {
                    colBg.withAlphaComponent(0.85).setFill()
                    NSBezierPath(rect: rect).fill()
                    colDim.withAlphaComponent(0.25).setStroke()
                    let g = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
                    g.lineWidth = 0.5; g.stroke()
                }
            }
        }
        // 圆圈边界
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        colAmber.withAlphaComponent(0.5).setStroke()
        ring.lineWidth = 1.5; ring.stroke()
    }

    // MARK: - Mouse（按下时确定涂/擦模式，拖拽保持一致）

    override func mouseDown(with e: NSEvent) {
        guard let (col, row) = cellAt(convert(e.locationInWindow, from: nil)) else { return }
        paintMode = !pixels[row][col]
        pixels[row][col] = paintMode!
        needsDisplay = true; onChange?()
    }
    override func mouseDragged(with e: NSEvent) {
        guard let mode = paintMode,
              let (col, row) = cellAt(convert(e.locationInWindow, from: nil)),
              pixels[row][col] != mode else { return }
        pixels[row][col] = mode
        needsDisplay = true; onChange?()
    }
    override func mouseUp(with e: NSEvent) { paintMode = nil }

    // MARK: - Actions

    func clear() {
        pixels = Array(repeating: Array(repeating: false, count: Self.n), count: Self.n)
        needsDisplay = true; onChange?()
    }

    func restore(_ saved: [[Bool]]) {
        pixels = saved; needsDisplay = true; onChange?()
    }

    // MARK: - Render to NSImage（用于设为金币图案）

    func renderToImage(size: CGFloat = 88) -> NSImage {
        let s = size / CGFloat(Self.n)
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).addClip()
        for row in 0..<Self.n {
            for col in 0..<Self.n where inCircle(col, row) && pixels[row][col] {
                colAmber.setFill()
                NSBezierPath(rect: NSRect(
                    x: CGFloat(col) * s, y: size - CGFloat(row + 1) * s,
                    width: s, height: s)).fill()
            }
        }
        img.unlockFocus()
        return img
    }

    // MARK: - 本地存储

    func savePixels() {
        let flat = pixels.flatMap { $0 }
        if let data = try? JSONSerialization.data(withJSONObject: flat) {
            try? data.write(to: URL(fileURLWithPath: pixelsPath))
        }
    }

    func loadPixels() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pixelsPath)),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Bool],
              arr.count == Self.n * Self.n else { return }
        for i in 0..<arr.count { pixels[i / Self.n][i % Self.n] = arr[i] }
    }
}
