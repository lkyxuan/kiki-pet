// Kiki 桌宠的 Mac 外壳（docs/desk-pet.md）。
// 一个透明、无边框、永远置顶、所有桌面都在的小窗，里面一个透明 WKWebView 加载 Kiki 后台的 /pet.html。
// 画面和“要你的”都是网页管；这里只管：窗口放哪、透明的地方点穿过去、拖动、单击、悬停、右键菜单。
// 和 Kiki 说话只走两条路：HTTP（网页自己取 /api/pet、听 /api/events）和 kiki:// 链接（点她打开要你的）。
// 连哪台 Kiki：跟 Kiki.app 一样（读它偏好设置里的 server，没选过或选了本机就是 localhost:4567）。
import Cocoa
import ServiceManagement
import WebKit

let defaults = UserDefaults.standard

// 跟 Kiki.app 连同一台：它的偏好设置 com.lkyxuan.kiki 里 server = "local" 或远程地址
// 试新版时可以单独指一台：defaults write com.lkyxuan.kiki.pet server http://localhost:4612
func kikiBase() -> URL {
    if let s = defaults.string(forKey: "server"), let u = URL(string: s), u.scheme == "http" || u.scheme == "https" { return u }
    if let s = UserDefaults(suiteName: "com.lkyxuan.kiki")?.string(forKey: "server"), s != "local",
       let u = URL(string: s), u.scheme == "http" || u.scheme == "https" { return u }
    return URL(string: "http://localhost:4567")!
}

// 大小：窗口宽度（点），高 = 宽 × 1.75（上面留给气泡）
let sizes: [(String, CGFloat)] = [("小", 170), ("中", 220), ("大", 290)]
let outfits: [(String, String)] = [
    ("00", "假面舞会"), ("02", "猫女"), ("04", "蕾丝睡衣"), ("06", "起床"), ("08", "健身"), ("10", "咖啡"), ("12", "西装"),
    ("14", "网球"), ("16", "骑行"), ("16b", "泳衣"), ("18", "赛车"), ("20", "晚礼服"), ("22", "皮衣"),
]

// 网页报上来的“点得到的地方”：Kiki 身上（一张粗格子的不透明表）+ 数字 + 小灯 + 正在显示的气泡
struct HitMask {
    var who = CGRect.zero, cols = 0, rows = 0, bits: [Bool] = [], extra: [CGRect] = []
    // p 是网页坐标（左上角原点，单位点）
    func hit(_ p: CGPoint) -> Bool {
        if extra.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(p) }) { return true }
        guard who.contains(p), cols > 0, rows > 0 else { return false }
        let c = min(cols - 1, Int((p.x - who.minX) / who.width * CGFloat(cols)))
        let r = min(rows - 1, Int((p.y - who.minY) / who.height * CGFloat(rows)))
        // 周围一格也算，免得头发边上点不中
        for dr in -1...1 { for dc in -1...1 {
            let rr = r + dr, cc = c + dc
            if rr >= 0, rr < rows, cc >= 0, cc < cols, bits[rr * cols + cc] { return true }
        } }
        return false
    }
}

// 盖在网页上的一层：鼠标全在这里收，单击 / 拖动 / 右键，再告诉网页（悬停看 updatePassThrough）
final class Grip: NSView {
    var onClick: () -> Void = {}
    var onMenu: (NSEvent) -> Void = { _ in }
    var onMoved: () -> Void = {}
    private var downAt: NSPoint?, startOrigin = NSPoint.zero, dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation; startOrigin = window?.frame.origin ?? .zero; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let a = downAt, let w = window else { return }
        let p = NSEvent.mouseLocation, dx = p.x - a.x, dy = p.y - a.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        w.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        if dragged { onMoved() } else { onClick() }
    }
    override func rightMouseDown(with event: NSEvent) { onMenu(event) }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }   // 点她不抢别的 App 的键盘
    override var canBecomeMain: Bool { false }
}

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSMenuDelegate {
    var panel: PetPanel!
    var web: WKWebView!
    let grip = Grip()
    var mask = HitMask()
    var hideUntil: Date?
    var hovering = false
    var lastBase = kikiBase()

    var width: CGFloat {
        get { let w = defaults.double(forKey: "width"); return w > 0 ? CGFloat(w) : 220 }
        set { defaults.set(Double(newValue), forKey: "width") }
    }
    var outfit: String {
        get { defaults.string(forKey: "outfit") ?? "auto" }
        set { defaults.set(newValue, forKey: "outfit") }
    }
    var quiet: Bool {
        get { defaults.bool(forKey: "quiet") }
        set { defaults.set(newValue, forKey: "quiet") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let size = NSSize(width: width, height: width * 1.75)
        panel = PetPanel(contentRect: NSRect(origin: savedOrigin(size), size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "kikiPet")
        web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        grip.frame = web.frame
        grip.autoresizingMask = [.width, .height]
        grip.onClick = { [weak self] in self?.js("kikiPet.click()") }
        grip.onMenu = { [weak self] e in self?.showMenu(e) }
        grip.onMoved = { [weak self] in self?.saveOrigin() }
        let root = NSView(frame: web.frame)
        root.addSubview(web)
        root.addSubview(grip)
        panel.contentView = root
        load()
        panel.orderFrontRegardless()

        // 透明的地方点穿过去：每秒 30 次看鼠标在不在她身上（不用辅助功能权限，只读鼠标位置）
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.updatePassThrough() }
        // 隐藏到点了就出来；Kiki.app 改连别的电脑了就跟着换
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        // 换了显示器排布：还在屏幕里就不动，跑出去了拉回右下角
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.keepOnScreen() }
    }

    func load() {
        lastBase = kikiBase()
        var c = URLComponents(url: lastBase.appendingPathComponent("pet.html"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "outfit", value: outfit)]
        web.load(URLRequest(url: c.url!))
    }
    // 后台还没起来（刚开机）就过一会儿再试
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.load() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        js("kikiPet.setQuiet(\(quiet))")
    }
    func js(_ s: String) { web.evaluateJavaScript("window.kikiPet && \(s)", completionHandler: nil) }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "mask":
            func r(_ v: Any?) -> CGRect? {
                guard let d = v as? [String: Any], let x = d["x"] as? Double, let y = d["y"] as? Double, let w = d["w"] as? Double, let h = d["h"] as? Double else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            }
            mask.who = r(m) ?? .zero
            mask.cols = m["cols"] as? Int ?? 0
            mask.rows = m["rows"] as? Int ?? 0
            mask.bits = (m["bits"] as? String ?? "").map { $0 == "1" }
            if mask.bits.count != mask.cols * mask.rows { mask.cols = 0 }
            mask.extra = [r(m["badge"]), r(m["lamps"]), r(m["bubble"])].compactMap { $0 }
        case "open":
            // 点了她：kiki://need 打开要你的第一张，kiki://open 只把 Kiki 叫出来；Kiki.app 没开会被拉起来
            if let s = m["link"] as? String, let u = URL(string: s), u.scheme == "kiki" { NSWorkspace.shared.open(u) }
        default: break
        }
    }

    func updatePassThrough() {
        guard panel.isVisible else { return }
        let p = NSEvent.mouseLocation, f = panel.frame
        // 网页坐标：左上角原点
        let local = CGPoint(x: p.x - f.minX, y: f.maxY - p.y)
        // 按着鼠标（正在拖）时不改，免得拖快了鼠标甩出她身上就松手
        let on = (NSEvent.pressedMouseButtons != 0 && !panel.ignoresMouseEvents) || (f.contains(p) && mask.hit(local))
        if panel.ignoresMouseEvents == on { panel.ignoresMouseEvents = !on }
        // 悬停：鼠标移到她身上（或气泡上）冒气泡，移开收起
        if on != hovering { hovering = on; js("kikiPet.hover(\(on))") }
    }

    func tick() {
        if let t = hideUntil, Date() >= t { hideUntil = nil; panel.orderFrontRegardless() }
        if kikiBase() != lastBase { load() }
    }

    // MARK: 位置

    func defaultOrigin(_ size: NSSize) -> NSPoint {
        let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: v.maxX - size.width - 12, y: v.minY)
    }
    func savedOrigin(_ size: NSSize) -> NSPoint {
        guard let s = defaults.string(forKey: "origin") else { return defaultOrigin(size) }
        let o = NSPointFromString(s), r = NSRect(origin: o, size: size)
        return NSScreen.screens.contains(where: { $0.frame.intersects(r.insetBy(dx: size.width * 0.3, dy: size.height * 0.3)) }) ? o : defaultOrigin(size)
    }
    func saveOrigin() { defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "origin") }
    func keepOnScreen() { panel.setFrameOrigin(savedOrigin(panel.frame.size)) }

    // MARK: 右键菜单

    func showMenu(_ e: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Kiki", action: #selector(openKiki), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let wear = NSMenuItem(title: "换装", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let auto = sub.addItem(withTitle: "跟着时段换", action: #selector(pickOutfit(_:)), keyEquivalent: "")
        auto.representedObject = "auto"; auto.target = self; auto.state = outfit == "auto" ? .on : .off
        sub.addItem(.separator())
        for (k, name) in outfits {
            let i = sub.addItem(withTitle: "\(k.prefix(2)) 点 · \(name)", action: #selector(pickOutfit(_:)), keyEquivalent: "")
            i.representedObject = k; i.target = self; i.state = outfit == k ? .on : .off
        }
        wear.submenu = sub
        menu.addItem(wear)
        let big = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        let bsub = NSMenu()
        for (name, w) in sizes {
            let i = bsub.addItem(withTitle: name, action: #selector(pickSize(_:)), keyEquivalent: "")
            i.representedObject = w; i.target = self; i.state = abs(width - w) < 1 ? .on : .off
        }
        big.submenu = bsub
        menu.addItem(big)
        let q = menu.addItem(withTitle: "免打扰（不主动冒气泡）", action: #selector(toggleQuiet), keyEquivalent: "")
        q.target = self; q.state = quiet ? .on : .off
        menu.addItem(withTitle: "藏起来 1 小时", action: #selector(hideHour), keyEquivalent: "").target = self
        let login = menu.addItem(withTitle: "开机自动出来", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出桌宠", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: e, for: grip)
    }

    @objc func openKiki() { NSWorkspace.shared.open(URL(string: "kiki://open")!) }
    @objc func pickOutfit(_ i: NSMenuItem) {
        outfit = i.representedObject as? String ?? "auto"
        js("kikiPet.setOutfit(\"\(outfit)\")")
    }
    @objc func pickSize(_ i: NSMenuItem) {
        guard let w = i.representedObject as? CGFloat else { return }
        width = w
        let f = panel.frame, size = NSSize(width: w, height: w * 1.75)
        // 右下角不动地缩放（她是靠右下站的）
        panel.setFrame(NSRect(x: f.maxX - size.width, y: f.minY, width: size.width, height: size.height), display: true)
        saveOrigin()
    }
    @objc func toggleQuiet() { quiet.toggle(); js("kikiPet.setQuiet(\(quiet))") }
    @objc func hideHour() { hideUntil = Date().addingTimeInterval(3600); panel.orderOut(nil) }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不进 Dock、不进 Cmd-Tab
app.run()
