import AppKit

private let pixelsPath = (stateDir as NSString).appendingPathComponent("pixels.json")

final class PixelCanvasView: NSView {
    static let n = 16
    var pixels: [[Bool]] = Array(repeating: Array(repeating: false, count: n), count: n)
    var onChange: (() -> Void)?
    var showingDefault = false           // 重置后预览默认 $ 金币，点 save 才真正生效
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
                    continue   // 圆外不画，与窗口背景融为一体
                } else if pixels[row][col] {
                    colAmber.setFill()
                    NSBezierPath(rect: rect).fill()
                } else {
                    colDim.withAlphaComponent(0.25).setStroke()
                    let g = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
                    g.lineWidth = 0.5; g.stroke()
                }
            }
        }
        // 圆圈边界（与游戏金币同款粗描边）
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        colAmber.setStroke()
        ring.lineWidth = 4; ring.stroke()

        // 默认金币预览：画布大圆即金币圆框，居中一个等宽 $ 即可
        if showingDefault {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: bounds.width * 0.45, weight: .semibold),
                .foregroundColor: colAmber,
            ]
            let t = "$", ts = t.size(withAttributes: attrs)
            t.draw(at: NSPoint(x: bounds.midX - ts.width / 2,
                               y: bounds.midY - ts.height / 2), withAttributes: attrs)
        }
    }

    // MARK: - Mouse（按下时确定涂/擦模式，拖拽保持一致）

    override func mouseDown(with e: NSEvent) {
        guard let (col, row) = cellAt(convert(e.locationInWindow, from: nil)) else { return }
        showingDefault = false   // 开始画就退出默认预览
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
        showingDefault = false
        needsDisplay = true; onChange?()
    }

    func showDefault() {
        pixels = Array(repeating: Array(repeating: false, count: Self.n), count: Self.n)
        showingDefault = true
        needsDisplay = true; onChange?()
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
