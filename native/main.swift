// Coin Coding 原生版：macOS 菜单栏应用 + 置顶透明悬浮窗
// 编译：swiftc -O native/main.swift -o native/CoinCoding
import AppKit

let stateDir = NSString(string: "~/.coincoding").expandingTildeInPath
let stateFile = stateDir + "/state.txt"
let coinsFile = stateDir + "/coins.txt"

// 数值（与 PRD V1.1 一致；正式版改为服务端下发）
let spawnInterval: TimeInterval = 1.5
let fallSeconds: CGFloat = 6.0
let bigChance: Double = 0.05

// 调色板（与 demo/index.html 的 :root 变量一致）
func hexColor(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let colBg = hexColor(0x0d1117)
let colDim = hexColor(0x484f58)
let colBright = hexColor(0xe6edf3)
let colGreen = hexColor(0x3fb950)
let colAmber = hexColor(0xd29922)

final class CoinView: NSView {
    let value: Int
    var onCollect: ((CoinView) -> Void)?

    init(value: Int, size: CGFloat, x: CGFloat, y: CGFloat) {
        self.value = value
        super.init(frame: NSRect(x: x, y: y, width: size, height: size))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        // 代码风金币：同色圆圈描边 + 等宽 $，无填充（大金币绿色 $10）
        let big = value >= 10
        let color = big ? colGreen : colAmber
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        color.setStroke()
        ring.lineWidth = 2
        ring.stroke()
        let text = big ? "$\(value)" : "$"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: big ? 22 : 20, weight: .semibold),
            .foregroundColor: color,
        ]
        let s = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - s.width) / 2,
                              y: (bounds.height - s.height) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { onCollect?(self) }
}

// 不抢焦点的悬浮面板：点金币不会让终端失去输入焦点
final class GamePanel: NSPanel {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}

// 右下角改大小的把手：斜纹图案，按住拖动调整窗口尺寸（顶边保持不动）
final class GripView: NSView {
    weak var panelRef: NSPanel?
    private(set) var dragging = false
    private var startMouse = NSPoint.zero
    private var startFrame = NSRect.zero

    override func draw(_ dirtyRect: NSRect) {
        colDim.setStroke()
        let p = NSBezierPath()
        for i in 1...3 {
            let d = CGFloat(i) * 4
            p.move(to: NSPoint(x: bounds.maxX - d, y: 2))
            p.line(to: NSPoint(x: bounds.maxX - 2, y: d))
        }
        p.lineWidth = 1.5
        p.stroke()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        startMouse = NSEvent.mouseLocation
        startFrame = panelRef?.frame ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let panel = panelRef else { return }
        let loc = NSEvent.mouseLocation
        let w = max(160, startFrame.width + (loc.x - startMouse.x))
        let h = max(240, startFrame.height - (loc.y - startMouse.y))
        panel.setFrame(NSRect(x: startFrame.origin.x, y: startFrame.maxY - h,
                              width: w, height: h), display: true)
    }
    override func mouseUp(with event: NSEvent) { dragging = false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var panel: GamePanel!
    var hud: NSTextField!
    var grip: GripView!
    var coinsItem: NSMenuItem!
    var testItem: NSMenuItem!
    var coinViews: [CoinView] = []
    var working = false
    var testMode = false
    var timers: [Timer] = []
    var coins = 0 {
        didSet {
            updateHUD()
            try? "\(coins)".write(toFile: coinsFile, atomically: true, encoding: .utf8)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let saved = (try? String(contentsOfFile: coinsFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        coins = Int(saved ?? "") ?? 0
        setupPanel()
        setupStatusItem()
        startTimers()
        updateHUD()
    }

    func setupPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let w: CGFloat = 260, h: CGFloat = 480
        panel = GamePanel(
            contentRect: NSRect(x: screen.maxX - w - 20, y: screen.maxY - h - 20, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver                      // 置顶，包括全屏应用之上
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true                 // 默认整窗穿透，仅悬停金币/计数时接收点击
        panel.isMovableByWindowBackground = true        // 拖计数标签可移动窗口
        panel.setFrameAutosaveName("CoinCodingPanel")   // 记住用户挪过的位置

        // 细描边标出窗口边界（终端窗格风格）
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.borderWidth = 1
        panel.contentView?.layer?.borderColor = colDim.withAlphaComponent(0.6).cgColor
        panel.contentView?.layer?.cornerRadius = 6

        hud = NSTextField(labelWithString: "")
        hud.alignment = .center
        hud.frame = NSRect(x: w - 130, y: h - 38, width: 120, height: 26)
        hud.autoresizingMask = [.minXMargin, .minYMargin]   // 改大小时保持在右上角
        panel.contentView?.addSubview(hud)

        grip = GripView(frame: NSRect(x: w - 18, y: 0, width: 18, height: 18))
        grip.panelRef = panel
        grip.autoresizingMask = [.minXMargin, .maxYMargin]  // 始终贴在右下角
        panel.contentView?.addSubview(grip)
        panel.delegate = self
        panel.orderFrontRegardless()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        coinsItem = NSMenuItem(title: "coins = 0", action: nil, keyEquivalent: "")
        menu.addItem(coinsItem)
        testItem = NSMenuItem(title: "test --start", action: #selector(toggleTest), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateHUD() {
        // 命令行样式：coins = N（N 为琥珀色）
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let s = NSMutableAttributedString(string: "coins = ",
            attributes: [.font: mono, .foregroundColor: colBright])
        s.append(NSAttributedString(string: "\(coins)",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                         .foregroundColor: colAmber]))
        hud?.attributedStringValue = s
        statusItem?.button?.title = "$ \(coins)"
        statusItem?.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        coinsItem?.title = "coins = \(coins)"
    }

    func startTimers() {
        // 读取 hooks 写入的 Claude 状态
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let s = (try? String(contentsOfFile: stateFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "idle"
            self.working = self.testMode || s == "working"
        })
        // 掉币
        timers.append(Timer.scheduledTimer(withTimeInterval: spawnInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.working else { return }
            self.spawn()
        })
        // 下落动画
        timers.append(Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick(dt: 1.0 / 60.0)
        })
        // 按鼠标位置切换点击穿透：只有指着金币或计数时窗口才接收点击
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateClickThrough()
        })
    }

    func spawn() {
        guard let content = panel.contentView else { return }
        let big = Double.random(in: 0..<1) < bigChance
        let size: CGFloat = big ? 60 : 44
        let maxX = content.bounds.width - size
        guard maxX > 0 else { return }
        let coin = CoinView(value: big ? 10 : 1, size: size,
                            x: CGFloat.random(in: 0...maxX), y: content.bounds.height)
        coin.onCollect = { [weak self] c in self?.collect(c) }
        content.addSubview(coin)
        coinViews.append(coin)
    }

    func tick(dt: CGFloat) {
        guard !coinViews.isEmpty else { return }
        let h = panel.contentView?.bounds.height ?? 480
        for coin in coinViews {
            let speed = (h + coin.frame.height) / fallSeconds
            coin.setFrameOrigin(NSPoint(x: coin.frame.origin.x, y: coin.frame.origin.y - speed * dt))
        }
        coinViews.removeAll { coin in
            if coin.frame.maxY < 0 {        // 漏接：直接消失，无惩罚
                coin.removeFromSuperview()
                return true
            }
            return false
        }
    }

    func collect(_ coin: CoinView) {
        coins += coin.value
        coin.removeFromSuperview()
        coinViews.removeAll { $0 === coin }
    }

    // 窗口缩小后把跑到界外的金币拉回视野内（与 demo 行为一致）
    func windowDidResize(_ notification: Notification) {
        guard let content = panel.contentView else { return }
        for coin in coinViews {
            let maxX = content.bounds.width - coin.frame.width
            if coin.frame.origin.x > maxX {
                coin.setFrameOrigin(NSPoint(x: max(0, maxX), y: coin.frame.origin.y))
            }
        }
    }

    func updateClickThrough() {
        let loc = NSEvent.mouseLocation
        var interactive = false
        if panel.frame.contains(loc) {
            let p = NSPoint(x: loc.x - panel.frame.origin.x, y: loc.y - panel.frame.origin.y)
            if hud.frame.contains(p) || grip.frame.contains(p) || grip.dragging {
                interactive = true
            } else {
                for c in coinViews where c.frame.contains(p) { interactive = true; break }
            }
        }
        panel.ignoresMouseEvents = !interactive
    }

    @objc func toggleTest() {
        testMode = !testMode
        testItem.title = testMode ? "test --stop" : "test --start"
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 无 Dock 图标
let delegate = AppDelegate()
app.delegate = delegate
app.run()
