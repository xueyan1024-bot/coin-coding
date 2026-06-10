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

final class CoinView: NSView {
    let value: Int
    var onCollect: ((CoinView) -> Void)?

    init(value: Int, size: CGFloat, x: CGFloat, y: CGFloat) {
        self.value = value
        super.init(frame: NSRect(x: x, y: y, width: size, height: size))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let big = value >= 10
        let body = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        (big ? NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.37, alpha: 1)
             : NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.20, alpha: 1)).setFill()
        body.fill()
        NSColor.white.withAlphaComponent(0.6).setStroke()
        body.lineWidth = 2
        body.stroke()
        let text = "\(value)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: bounds.width * 0.38),
            .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.30, blue: 0, alpha: 1),
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: GamePanel!
    var hud: NSTextField!
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

        hud = NSTextField(labelWithString: "")
        hud.font = NSFont.boldSystemFont(ofSize: 15)
        hud.textColor = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.37, alpha: 1)
        hud.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        hud.drawsBackground = true
        hud.alignment = .center
        hud.frame = NSRect(x: w - 120, y: h - 38, width: 110, height: 28)
        hud.wantsLayer = true
        hud.layer?.cornerRadius = 14
        panel.contentView?.addSubview(hud)
        panel.orderFrontRegardless()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        coinsItem = NSMenuItem(title: "金币：0", action: nil, keyEquivalent: "")
        menu.addItem(coinsItem)
        testItem = NSMenuItem(title: "测试模式：开始掉币", action: #selector(toggleTest), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateHUD() {
        hud?.stringValue = "🪙 \(coins)"
        statusItem?.button?.title = "🪙 \(coins)"
        coinsItem?.title = "金币：\(coins)"
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
        let size: CGFloat = big ? 56 : 40
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

    func updateClickThrough() {
        let loc = NSEvent.mouseLocation
        var interactive = false
        if panel.frame.contains(loc) {
            let p = NSPoint(x: loc.x - panel.frame.origin.x, y: loc.y - panel.frame.origin.y)
            if hud.frame.contains(p) {
                interactive = true
            } else {
                for c in coinViews where c.frame.contains(p) { interactive = true; break }
            }
        }
        panel.ignoresMouseEvents = !interactive
    }

    @objc func toggleTest() {
        testMode = !testMode
        testItem.title = testMode ? "测试模式：停止" : "测试模式：开始掉币"
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 无 Dock 图标
let delegate = AppDelegate()
app.delegate = delegate
app.run()
