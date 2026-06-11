// Coin Coding 原生版：macOS 菜单栏应用 + 置顶透明悬浮窗
// 编译：swiftc -O native/main.swift -o native/CoinCoding
import AppKit
import AVFoundation

let stateDir   = NSString(string: "~/.coincoding").expandingTildeInPath
let stateFile  = stateDir + "/state.txt"
let coinsFile  = stateDir + "/coins.txt"
let pendingFile = stateDir + "/pending.json"

// 数值（与 PRD V1.1 一致；正式版改为服务端下发）
let spawnInterval: TimeInterval = 0.8
let fallSeconds: CGFloat = 6.0
// 固定像素速度（按默认窗高 480 折算），窗口改大小不影响金币下落快慢
let fallSpeed: CGFloat = (480 + 44) / fallSeconds
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
    var spinAngle: CGFloat = 0      // 大金币绕屏幕竖直轴翻面的角度
    var customImage: NSImage?       // 用户上传的自定义金币图片

    init(value: Int, size: CGFloat, x: CGFloat, y: CGFloat) {
        self.value = value
        super.init(frame: NSRect(x: x, y: y, width: size, height: size))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        // 代码风金币：琥珀色圆圈描边 + 等宽 $，无填充；大金币同款同尺寸，靠翻面旋转区分
        let big = value >= 10
        if big {
            // 模拟绕竖直轴的 3D 翻面：按 cos 横向压扁，转到背面时文字自然镜像
            var k = cos(spinAngle)
            if abs(k) < 0.06 { k = k < 0 ? -0.06 : 0.06 }   // 侧面时留一条线，避免压成零宽
            let flip = NSAffineTransform()
            flip.translateX(by: bounds.midX, yBy: 0)
            flip.scaleX(by: k, yBy: 1)
            flip.translateX(by: -bounds.midX, yBy: 0)
            flip.concat()
        }
        if let img = customImage {
            // 用户自定义像素画：圆形裁切填满，再叠画琥珀色圆框
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).addClip()
            img.draw(in: bounds.insetBy(dx: 1, dy: 1))
            let ring2 = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            colAmber.setStroke(); ring2.lineWidth = 2; ring2.stroke()
            return
        }
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
    // 音色预设：beep 方波（默认）/ bubble 水泡滑音 / ding 金属铃声 / off 静音
    enum Style: String, CaseIterable { case beep, bubble, ding, off }
    var style: Style = Style(rawValue: UserDefaults.standard.string(forKey: "soundStyle") ?? "beep") ?? .beep {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "soundStyle") }
    }

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
        guard engine.isRunning, style != .off else { return }
        var dur = dur, vol = vol
        switch style {
        case .ding:   dur = max(dur, 0.4); vol *= 2.5  // 铃声要余音，正弦能量低补音量
        case .bubble: vol *= 3                         // 正弦波能量低，补偿音量
        default: break
        }
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(sr * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        var phaseAcc = 0.0    // 相位累加，滑音时频率连续变化不破音
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let p = t / dur   // 0→1 进度
            var f = freq
            if style == .bubble { f = freq * (0.8 + 1.2 * p) }   // 频率上滑，像“啵”
            phaseAcc += 2 * .pi * f / sr
            let frac = (phaseAcc / (2 * .pi)).truncatingRemainder(dividingBy: 1)
            let wave: Double
            switch style {
            case .bubble: wave = sin(phaseAcc)                       // 圆润正弦
            case .ding:   // 铃铛：基音 + 两个非整数倍泛音（金属感来源），余音更长
                wave = 0.6 * sin(2 * .pi * freq * 2 * t)
                     + 0.3 * sin(2 * .pi * freq * 2 * 2.41 * t)
                     + 0.15 * sin(2 * .pi * freq * 2 * 5.93 * t)
            default:      wave = sine ? sin(phaseAcc) : (frac < 0.5 ? 1.0 : -1.0)
            }
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

// 左上角关闭按钮：点击只收起悬浮窗，应用留在菜单栏，可从菜单重新打开
final class CloseView: NSView {
    var onClose: (() -> Void)?
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
    override func mouseDown(with event: NSEvent) { onClose?() }
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var statusItem: NSStatusItem!
    var panel: GamePanel!
    var hud: HUDTextView!
    var hudBox: NSVisualEffectView!   // 计数文字的毛玻璃底，浅色桌面下保证可读
    var grip: GripView!
    var coinsItem: NSMenuItem!

    var windowItem: NSMenuItem!
    var coinViews: [CoinView] = []
    var working = false

    var timers: [Timer] = []
    let beeper = Beeper()
    var streak = 0
    let penta = [0, 2, 4, 7, 9]   // 连击沿五声音阶上行（与 demo 一致）
    // 后端 & 个性化
    var sessionStart: Date?
    var sessionClicks: [Double] = []
    var sessionCoins = 0
    var coinLabel = "coins"
    var customCoinImage: NSImage? {
        didSet { coinViews.forEach { $0.customImage = customCoinImage; $0.needsDisplay = true } }
    }
    var loginItem: NSMenuItem!
    var logoutItem: NSMenuItem!
    var userItem: NSMenuItem!
    var leaderboardPanel: NSWindow?
    var settingsPanel: NSWindow?
    var pixelCanvas: PixelCanvasView?
    var savedPixels: [[Bool]] = Array(repeating: Array(repeating: false, count: 16), count: 16)
    var savedShowingDefault = false
    var createButton: NSButton?
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
        setupAuth()
        loadSavedCoinImage()
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
        close.onClose = { [weak self] in self?.setWindowShown(false) }
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

        let lbItem = NSMenuItem(title: "Leaderboard", action: #selector(openLeaderboard), keyEquivalent: "l")
        lbItem.target = self
        menu.addItem(lbItem)

        // —— 个性化 ——
        menu.addItem(.separator())

        let coinfaceItem = NSMenuItem(title: "Coinface", action: #selector(openSettings), keyEquivalent: ",")
        coinfaceItem.target = self
        menu.addItem(coinfaceItem)

        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        for s in Beeper.Style.allCases {
            let item = NSMenuItem(title: s.rawValue,
                                  action: #selector(selectSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.rawValue
            item.state = beeper.style == s ? .on : .off
            soundMenu.addItem(item)
        }
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        // —— 窗口 / 测试 ——
        menu.addItem(.separator())
        windowItem = NSMenuItem(title: "window --hide", action: #selector(toggleWindow), keyEquivalent: "w")
        windowItem.target = self
        menu.addItem(windowItem)

        // —— 账号 ——
        menu.addItem(.separator())
        userItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(userItem)
        loginItem = NSMenuItem(title: "Login with GitHub", action: #selector(doLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        logoutItem = NSMenuItem(title: "Logout", action: #selector(doLogout), keyEquivalent: "")
        logoutItem.target = self
        menu.addItem(logoutItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateHUD() {
        // 命令行样式：coins = N（N 为琥珀色），毛玻璃底紧贴文字、靠右上角
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        if let hud = hud, let box = hudBox, let content = panel?.contentView {
            let pad: CGFloat = 8   // 文字四周统一留白
            let avail = content.bounds.width - 24
            // 窗口很窄且数字很大时，自动从 coins = N 降级为 $ N
            let fullWidth = NSAttributedString(string: "\(coinLabel) = \(coins)",
                attributes: [.font: mono]).size().width + pad * 2
            let narrow = fullWidth > avail
            let s = NSMutableAttributedString(string: narrow ? "$ " : "\(coinLabel) = ",
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
        coinsItem?.title = "\(coinLabel) = \(coins)"
    }

    func startTimers() {
        // 读取 hooks 写入的 Claude 状态
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let s = (try? String(contentsOfFile: stateFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "idle"
            let now = s == "working"
            if !self.working && now {   // 开始工作
                self.sessionStart = Date(); self.sessionClicks = []; self.sessionCoins = 0
            }
            if self.working && !now {   // 结束工作
                self.streak = 0; self.endSession()
            }
            self.working = now
        })
        // 掉币
        timers.append(Timer.scheduledTimer(withTimeInterval: spawnInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.working, self.panel.isVisible else { return }
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
        coin.customImage = customCoinImage
        content.addSubview(coin)
        coinViews.append(coin)
    }

    func tick(dt: CGFloat) {
        guard !coinViews.isEmpty else { return }
        for coin in coinViews {
            coin.setFrameOrigin(NSPoint(x: coin.frame.origin.x, y: coin.frame.origin.y - fallSpeed * dt))
            if coin.value >= 10 {   // 大金币边落边绕竖直轴翻面
                coin.spinAngle += 3.5 * dt
                coin.needsDisplay = true
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
        sessionCoins += coin.value
        sessionClicks.append(Date().timeIntervalSince1970)
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

    // 收起/恢复悬浮窗：收起时应用留在菜单栏，掉币暂停
    func setWindowShown(_ shown: Bool) {
        if shown { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        windowItem.title = shown ? "window --hide" : "window --show"
    }

    @objc func toggleWindow() { setWindowShown(!panel.isVisible) }

    @objc func selectSound(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let s = Beeper.Style(rawValue: raw) else { return }
        beeper.style = s
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        if s != .off { beeper.beep(freq: 659, vol: 0.04, dur: 0.1) }   // 试听一声
    }


    // MARK: - Auth

    func setupAuth() {
        SupabaseAuth.shared.onChange = { [weak self] session in
            self?.updateAuthMenu()
            if session != nil { self?.syncFromServer(); self?.submitPending() }
        }
        updateAuthMenu()
        if SupabaseAuth.shared.isLoggedIn { syncFromServer() }
    }

    func updateAuthMenu() {
        let loggedIn = SupabaseAuth.shared.isLoggedIn
        userItem.title  = loggedIn ? "Signed in as @\(SupabaseAuth.shared.session!.githubUsername)" : ""
        userItem.isHidden = !loggedIn
        loginItem.isHidden  = loggedIn
        logoutItem.isHidden = !loggedIn
    }

    func syncFromServer() {
        SupabaseAPI.shared.fetchProfile { [weak self] profile in
            guard let self, let profile else { return }
            self.coins     = profile.totalCoins
            self.coinLabel = profile.coinName
            self.updateHUD()
            if let urlStr = profile.coinImageUrl, let url = URL(string: urlStr) {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let img = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self.customCoinImage = img }
                }.resume()
            }
        }
    }

    func endSession() {
        guard let start = sessionStart, sessionCoins > 0 else { sessionStart = nil; return }
        let end = Date()
        let clicks = sessionClicks
        sessionStart = nil; sessionClicks = []

        if SupabaseAuth.shared.isLoggedIn {
            SupabaseAPI.shared.submitCoins(start: start, end: end, earned: sessionCoins, clicks: clicks) { [weak self] ok in
                if ok { self?.syncFromServer() }
            }
            submitPending()
        } else {
            savePending(start: start, end: end, earned: sessionCoins, clicks: clicks)
        }
        sessionCoins = 0
    }

    // MARK: - 未登录时的本地存档

    struct PendingSession: Codable {
        let start: Double; let end: Double; let earned: Int; let clicks: [Double]
    }

    func savePending(start: Date, end: Date, earned: Int, clicks: [Double]) {
        var list = loadPending()
        list.append(PendingSession(start: start.timeIntervalSince1970,
                                   end: end.timeIntervalSince1970,
                                   earned: earned, clicks: clicks))
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: URL(fileURLWithPath: pendingFile))
        }
    }

    func loadPending() -> [PendingSession] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pendingFile)),
              let list = try? JSONDecoder().decode([PendingSession].self, from: data) else { return [] }
        return list
    }

    func submitPending() {
        let list = loadPending()
        guard !list.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: pendingFile)
        for s in list {
            SupabaseAPI.shared.submitCoins(
                start: Date(timeIntervalSince1970: s.start),
                end:   Date(timeIntervalSince1970: s.end),
                earned: s.earned, clicks: s.clicks) { _ in }
        }
    }

    @objc func doLogin()  { SupabaseAuth.shared.login() }
    @objc func doLogout() { SupabaseAuth.shared.logout(); updateAuthMenu() }

    // MARK: - Leaderboard

    @objc func openLeaderboard() {
        leaderboardPanel?.close()
        leaderboardPanel = nil
        let w = 340, h = 460
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Leaderboard"
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = colBg
        win.isReleasedWhenClosed = false
        win.center()
        leaderboardPanel = win

        let tv = NSTextField(wrappingLabelWithString: "loading…")
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = colBright
        tv.backgroundColor = .clear
        tv.frame = NSRect(x: 20, y: 20, width: w - 40, height: h - 50)
        tv.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(tv)
        win.orderFrontRegardless()

        SupabaseAPI.shared.fetchLeaderboard { [weak self] entries in
            guard let self else { return }
            let myName = SupabaseAuth.shared.session?.githubUsername ?? ""
            var lines = ["  rank   user                    coins", String(repeating: "─", count: 38)]
            for (i, e) in entries.enumerated() {
                let rank  = String(format: "%4d", i + 1)
                let user  = e.githubUsername.padding(toLength: 22, withPad: " ", startingAt: 0)
                let score = "\(e.totalCoins)"
                lines.append("  \(rank)   \(user)  \(score)")
            }
            if !myName.isEmpty && !entries.contains(where: { $0.githubUsername == myName }) {
                // 不在前 20：另查自己的真实名次显示在底部
                SupabaseAPI.shared.fetchMyRank { rank in
                    lines.append(String(repeating: "─", count: 38))
                    if let r = rank {
                        let user = "you (@\(myName))".padding(toLength: 22, withPad: " ", startingAt: 0)
                        lines.append("  \(String(format: "%4d", r))   \(user)  \(self.coins)")
                    } else {
                        lines.append("   →    you're not ranked yet")
                    }
                    tv.stringValue = lines.joined(separator: "\n")
                }
                return
            }
            tv.stringValue = lines.joined(separator: "\n")
        }
    }

    func loadSavedCoinImage() {
        let tmp = PixelCanvasView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        guard tmp.pixelCount > 0 else { return }
        customCoinImage = tmp.renderToImage()
    }

    // MARK: - Settings（像素画编辑器）

    @objc func openSettings() {
        settingsPanel?.close()
        settingsPanel = nil
        let w: CGFloat = 360, h: CGFloat = 460
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Coinface"
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = colBg
        win.isReleasedWhenClosed = false
        win.center()
        settingsPanel = win

        // coin name 一行
        let nameLabel = NSTextField(labelWithString: "Coin name")
        nameLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = colDim
        nameLabel.frame = NSRect(x: 20, y: h - 48, width: 90, height: 20)
        win.contentView?.addSubview(nameLabel)

        let nameField = NSTextField(frame: NSRect(x: 118, y: h - 50, width: 200, height: 22))
        nameField.stringValue = coinLabel
        nameField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        nameField.tag = 9001
        nameField.delegate = self
        win.contentView?.addSubview(nameField)

        // 像素画布（288×288，居中）
        let canvasSize: CGFloat = 288
        let canvasX = (w - canvasSize) / 2
        let canvasY: CGFloat = 80
        let canvas = PixelCanvasView(frame: NSRect(x: canvasX, y: canvasY,
                                                   width: canvasSize, height: canvasSize))
        canvas.onChange = { [weak self] in self?.refreshCreateButton() }
        win.contentView?.addSubview(canvas)
        pixelCanvas = canvas
        // 如果本地没有自定义像素，显示默认 $ 作为当前状态
        if canvas.pixelCount == 0 { canvas.showDefault() }
        savedPixels = canvas.pixels.map { $0 }
        savedShowingDefault = canvas.showingDefault

        // 三个按钮（等宽，底部对齐）
        let btnW: CGFloat = 90, btnH: CGFloat = 28, btnY: CGFloat = 30
        let spacing: CGFloat = (w - btnW * 3) / 4

        let resetBtn = makeBtn("Reset", x: spacing, y: btnY, w: btnW, h: btnH,
                               action: #selector(resetCanvas))
        win.contentView?.addSubview(resetBtn)

        let clearBtn = makeBtn("Clear", x: spacing * 2 + btnW, y: btnY, w: btnW, h: btnH,
                               action: #selector(clearCanvas))
        win.contentView?.addSubview(clearBtn)

        let createBtn = makeBtn("Save", x: spacing * 3 + btnW * 2, y: btnY, w: btnW, h: btnH,
                                action: #selector(createCoinArt))
        createBtn.tag = 9002
        win.contentView?.addSubview(createBtn)
        createButton = createBtn

        refreshCreateButton()
        win.orderFrontRegardless()
    }

    private func makeBtn(_ title: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                         action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: w, height: h))
        btn.title = title
        btn.bezelStyle = .rounded
        btn.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        btn.target = self
        btn.action = action
        return btn
    }

    private func refreshCreateButton() {
        guard let canvas = pixelCanvas else { createButton?.isEnabled = false; return }
        let nameChanged = (settingsPanel?.contentView?.viewWithTag(9001) as? NSTextField)
            .map { !$0.stringValue.trimmingCharacters(in: .whitespaces).isEmpty && $0.stringValue != coinLabel } ?? false
        let canvasChanged = canvas.showingDefault != savedShowingDefault || canvas.pixels.elementsEqual(savedPixels, by: { $0 == $1 }) == false
        createButton?.isEnabled = canvasChanged || nameChanged
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField)?.tag == 9001 { refreshCreateButton() }
    }

    @objc func resetCanvas() {
        // 只在画布里预览默认 $ 金币，点 save 才真正生效
        pixelCanvas?.showDefault()
        refreshCreateButton()
    }

    @objc func clearCanvas() {
        pixelCanvas?.clear()
        refreshCreateButton()
    }

    @objc func createCoinArt() {
        guard let canvas = pixelCanvas else { return }

        if canvas.showingDefault {
            // 保存"恢复默认"：删本地图案、游戏恢复 $、服务端也清掉
            try? FileManager.default.removeItem(atPath: stateDir + "/pixels.json")
            customCoinImage = nil
            SupabaseAPI.shared.updateProfile(coinImageUrl: "")
        } else if canvas.pixelCount > 0 {
            canvas.savePixels()
            let img = canvas.renderToImage()
            customCoinImage = img
            // 上传到 Supabase（如果已登录）
            if SupabaseAuth.shared.isLoggedIn,
               let tiff = img.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff),
               let png = bmp.representation(using: .png, properties: [:]) {
                SupabaseAPI.shared.uploadCoinImage(png) { _ in }
            }
        } else { return }

        // 更新 coin name
        if let field = settingsPanel?.contentView?.viewWithTag(9001) as? NSTextField {
            let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty && newName != coinLabel {
                coinLabel = newName
                updateHUD()
                SupabaseAPI.shared.updateProfile(coinName: newName)
            }
        }

        settingsPanel?.close()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 无 Dock 图标
let delegate = AppDelegate()
app.delegate = delegate
app.run()
