// Coin Coding 原生版：macOS 菜单栏应用 + 置顶透明悬浮窗
// 编译：swiftc -O native/main.swift -o native/CoinCoding
import AppKit
import AVFoundation

let stateDir = NSString(string: "~/.coincoding").expandingTildeInPath
let stateFile = stateDir + "/state.txt"
let coinsFile = stateDir + "/coins.txt"

// 数值（与 PRD V1.1 一致；正式版改为服务端下发）
let spawnInterval: TimeInterval = 0.8
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
        // 代码风金币：琥珀色圆圈描边 + 等宽 $，无填充；大金币同款同尺寸，靠旋转区分
        let big = value >= 10
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        colAmber.setStroke()
        ring.lineWidth = 2
        ring.stroke()
        let text = big ? "$\(value)" : "$"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: big ? 14 : 20, weight: .semibold),
            .foregroundColor: colAmber,
        ]
        let s = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - s.width) / 2,
                              y: (bounds.height - s.height) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { onCollect?(self) }
}

// 8-bit 风格蜂鸣器（与 demo 的 WebAudio beep 等价：方波/正弦 + 指数衰减）
final class Beeper {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
        if engine.isRunning { player.play() }
    }

    func beep(freq: Double, vol: Float, dur: Double, sine: Bool = false) {
        guard engine.isRunning else { return }
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(sr * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let phase = sin(2 * .pi * freq * t)
            let wave = sine ? phase : (phase >= 0 ? 1.0 : -1.0)
            data[i] = Float(wave * pow(0.001, t / dur)) * vol
        }
        player.scheduleBuffer(buf)
    }
}

// 自绘文字视图：NSTextField 在毛玻璃环境下颜色会被系统活力混合洗掉（实测关不掉），
// 自己 draw 的内容不受影响（金币 CoinView 同理，琥珀色一直正常）
final class HUDTextView: NSView {
    var text = NSAttributedString() { didSet { needsDisplay = true } }
    override var allowsVibrancy: Bool { return false }
    override func draw(_ dirtyRect: NSRect) {
        text.draw(at: NSPoint(x: 1, y: (bounds.height - text.size().height) / 2))
    }
}

// 左上角关闭按钮：点击退出应用（与菜单栏 exit 等效）
final class CloseView: NSView {
    override var allowsVibrancy: Bool { return false }
    override func draw(_ dirtyRect: NSRect) {
        let s = NSAttributedString(string: "✕", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: colDim,
        ])
        let size = s.size()
        s.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                           y: (bounds.height - size.height) / 2))
    }
    override func mouseDown(with event: NSEvent) { NSApp.terminate(nil) }
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
    var hud: HUDTextView!
    var hudBox: NSVisualEffectView!   // 计数文字的毛玻璃底，浅色桌面下保证可读
    var grip: GripView!
    var coinsItem: NSMenuItem!
    var testItem: NSMenuItem!
    var coinViews: [CoinView] = []
    var working = false
    var testMode = false
    var timers: [Timer] = []
    let beeper = Beeper()
    var streak = 0
    let penta = [0, 2, 4, 7, 9]   // 连击沿五声音阶上行（与 demo 一致）
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
        panel.ignoresMouseEvents = true                 // 鼠标在框外时不挡事，进框后接收（见 updateClickThrough）
        panel.isMovableByWindowBackground = true        // 框内任意位置按住可拖动窗口（用户拍板放弃点击穿透）
        panel.setFrameAutosaveName("CoinCodingPanel")   // 记住用户挪过的位置

        // 细描边标出窗口边界（终端窗格风格）
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.borderWidth = 1
        panel.contentView?.layer?.borderColor = colDim.withAlphaComponent(0.6).cgColor
        panel.contentView?.layer?.cornerRadius = 6
        // 近乎透明的底色：肉眼不可见，但让透明区域能接住鼠标（否则系统会让点击落到下层窗口）
        panel.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor

        panel.appearance = NSAppearance(named: .darkAqua)    // 整窗锁定深色外观

        hudBox = NSVisualEffectView(frame: NSRect(x: w - 130, y: h - 38, width: 118, height: 26))
        hudBox.material = .hudWindow
        hudBox.blendingMode = .behindWindow   // 模糊的是窗口后面的桌面内容
        hudBox.state = .active
        hudBox.wantsLayer = true
        hudBox.layer?.cornerRadius = 5
        hudBox.layer?.masksToBounds = true
        // 毛玻璃上再压一层半透明深色，浅色背景下也保持深底
        let tint = NSView(frame: hudBox.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = colBg.withAlphaComponent(0.55).cgColor
        hudBox.addSubview(tint)
        panel.contentView?.addSubview(hudBox)

        // 自绘文字层叠在毛玻璃上方（金币视图同款画法，不受系统洗色影响）
        hud = HUDTextView(frame: .zero)
        panel.contentView?.addSubview(hud)

        let close = CloseView(frame: NSRect(x: 8, y: h - 28, width: 20, height: 20))
        close.autoresizingMask = [.maxXMargin, .minYMargin]   // 始终贴在左上角
        panel.contentView?.addSubview(close)

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
        // 命令行样式：coins = N（N 为琥珀色），毛玻璃底紧贴文字、靠右上角
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        if let hud = hud, let box = hudBox, let content = panel?.contentView {
            let pad: CGFloat = 8   // 文字四周统一留白
            let avail = content.bounds.width - 24
            // 窗口很窄且数字很大时，自动从 coins = N 降级为 $ N
            let fullWidth = NSAttributedString(string: "coins = \(coins)",
                attributes: [.font: mono]).size().width + pad * 2
            let narrow = fullWidth > avail
            let s = NSMutableAttributedString(string: narrow ? "$ " : "coins = ",
                attributes: [.font: mono, .foregroundColor: colBright])
            s.append(NSAttributedString(string: "\(coins)",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                             .foregroundColor: colAmber]))
            hud.text = s
            let textSize = s.size()
            let boxW = min(ceil(textSize.width) + pad * 2, avail)
            let boxH = ceil(textSize.height) + pad * 2
            box.frame = NSRect(x: content.bounds.width - boxW - 12,
                               y: content.bounds.height - boxH - 12, width: boxW, height: boxH)
            // 文字层与毛玻璃同框叠放（文字在视图内自行垂直居中、左侧从 pad 起笔）
            hud.frame = NSRect(x: box.frame.origin.x + pad, y: box.frame.origin.y,
                               width: boxW - pad * 2 + 2, height: boxH)
        }
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
            let now = self.testMode || s == "working"
            if self.working && !now { self.streak = 0 }   // 收工时连击清零
            self.working = now
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
        let size: CGFloat = 44
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
            if coin.value >= 10 {   // 大金币边落边转
                coin.frameCenterRotation -= 150 * dt
            }
        }
        coinViews.removeAll { coin in
            if coin.frame.maxY < 0 {        // 漏接：无惩罚，但连击清零并低音提示
                coin.removeFromSuperview()
                if streak >= 2 { beeper.beep(freq: 150, vol: 0.05, dur: 0.18, sine: true) }
                streak = 0
                return true
            }
            return false
        }
    }

    func collect(_ coin: CoinView) {
        coins += coin.value
        streak += 1
        let i = min(streak, 20)
        let semis = (i / 5) * 12 + penta[i % 5]
        beeper.beep(freq: 523 * pow(2, Double(semis) / 12), vol: 0.04, dur: 0.1)
        coin.removeFromSuperview()
        coinViews.removeAll { $0 === coin }
    }

    // 窗口缩小后把跑到界外的金币拉回视野内（与 demo 行为一致），并按新宽度刷新计数样式
    func windowDidResize(_ notification: Notification) {
        updateHUD()
        guard let content = panel.contentView else { return }
        for coin in coinViews {
            let maxX = content.bounds.width - coin.frame.width
            if coin.frame.origin.x > maxX {
                coin.setFrameOrigin(NSPoint(x: max(0, maxX), y: coin.frame.origin.y))
            }
        }
    }

    func updateClickThrough() {
        // 框内整体接收鼠标（点金币/拖动/改大小），框外不挡事
        let loc = NSEvent.mouseLocation
        panel.ignoresMouseEvents = !(panel.frame.contains(loc) || grip.dragging)
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
