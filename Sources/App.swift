import AppKit
import WebKit

// macOS-only unofficial Superfastcode account balance utility.

let consoleURL = URL(string: "https://console.superfastcode.com/console/subscription-wallet")!

// 无边框置顶窗口：可接受键盘焦点，不抢占主窗口身份。
final class BallPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// 小球绘制与交互：原生拖动、单击菜单、无障碍标签。
final class BallView: NSView {
    var value = "登录"
    var caption = "点击连接"
    var fraction: Double? = nil
    var onClick: (() -> Void)?
    var onMove: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return hypot(p.x - bounds.midX, p.y - bounds.midY) < bounds.width / 2 - 5 ? self : nil
    }
    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 6, dy: 6)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let large = min(26.0, 112.0 / Double(max(4, value.count)))
        (value as NSString).draw(in: NSRect(x: 12, y: 42, width: bounds.width-24, height: 33), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: large, weight: .semibold),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        (caption as NSString).draw(in: NSRect(x: 10, y: 27, width: bounds.width-20, height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = window.frame.origin
        NSCursor.closedHand.push()
        window.performDrag(with: event)
        NSCursor.pop()
        let end = window.frame.origin
        if hypot(end.x-start.x, end.y-start.y) > 1 { onMove?() }
        else { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onClick?() } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver, NSWindowDelegate {
    var panel: BallPanel!
    var ball: BallView!
    var login: NSWindow!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var watchdog: Timer?
    var snapshot: QuotaSnapshot?
    var state = "正在连接"
    var inFlight = false
    var lastAttempt = Date.distantPast
    var nextAttempt = Date.distantPast
    var requestID = UUID()
    var navigationReady = false
    var metric: Metric = Metric(rawValue: UserDefaults.standard.string(forKey: "metric") ?? "weekly") ?? .weekly
    var interval: Double = UserDefaults.standard.double(forKey: "interval") == 60 ? 60 : 30
    var fixture = CommandLine.arguments.contains("--render-check")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let appMenu = NSMenu()
        let root = NSMenuItem(); appMenu.addItem(root)
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a"), ("剪切", "cut:", "x")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        root.submenu = edit; NSApp.mainMenu = appMenu
        ball = BallView(frame: NSRect(x: 0, y: 0, width: 52, height: 52))
        // Scale every drawing dimension together, including text and progress stroke.
        ball.bounds = NSRect(x: 0, y: 0, width: 104, height: 104)
        panel = BallPanel(contentRect: ball.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = ball; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        ball.setAccessibilityElement(true); ball.setAccessibilityRole(.button)
        ball.onClick = { [weak self] in self?.showMenu() }
        ball.onMove = { [weak self] in self?.savePosition() }
        positionBall()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "额度 · 连接中"
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClick)
        panel.orderFrontRegardless()
        if fixture { renderChecks(); return }

        let config = WKWebViewConfiguration()
        // A dedicated persistent WebKit store, never the user's Chrome/Safari profile.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "1719AB6D-CB3C-40EA-851C-7184EA3764EB")!)
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self; web.uiDelegate = self
        config.websiteDataStore.httpCookieStore.add(self)
        login = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        login.title = "Token 悬浮球 · 登录 Superfastcode（独立窗口）"
        login.contentView = web; login.isReleasedWhenClosed = false; login.delegate = self; login.center()
        web.load(URLRequest(url: consoleURL))
        startTimer()
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.inFlight && Date().timeIntervalSince(self.lastAttempt) > 25 {
                self.requestID = UUID(); self.inFlight = false; self.state = "连接超时"; self.nextAttempt = Date().addingTimeInterval(self.interval)
            }
            self.updateDisplay()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !UserDefaults.standard.bool(forKey: "hasConnected") { showLogin() }
        updateDisplay()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 2
    }
    @objc func wake() { nextAttempt = .distantPast; refresh(force: true) }
    @objc func screenChanged() { positionBall() }
    func positionBall() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let d = UserDefaults.standard
        var origin = NSPoint(x: screen.maxX-panel.frame.width-26, y: screen.midY)
        if d.object(forKey: "ballX") != nil { origin = NSPoint(x: d.double(forKey: "ballX"), y: d.double(forKey: "ballY")) }
        let rect = NSRect(origin: origin, size: panel.frame.size)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(rect) }) { origin = NSPoint(x: screen.maxX-panel.frame.width-26, y: screen.midY) }
        panel.setFrameOrigin(origin)
    }
    // 将小球限制在当前屏幕可见范围内，并记住用户放置位置。
    func savePosition() {
        let s = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let area = s?.visibleFrame {
            let p = panel.frame.origin
            panel.setFrameOrigin(NSPoint(x: max(area.minX,min(p.x,area.maxX-panel.frame.width)), y: max(area.minY,min(p.y,area.maxY-panel.frame.height))))
        }
        UserDefaults.standard.set(panel.frame.minX, forKey: "ballX")
        UserDefaults.standard.set(panel.frame.minY, forKey: "ballY")
    }
    @objc func showLogin() {
        if web.url?.host != "console.superfastcode.com" && !web.isLoading { web.load(URLRequest(url: consoleURL)) }
        login.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func reloadWebsite() { navigationReady = false; web.load(URLRequest(url: consoleURL)); showLogin() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { refresh() }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { navigationReady = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationReady = true; refresh(force: true)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        state = "网页未连接"; updateDisplay()
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // The user completes authentication inside the official HTTPS pages.
        guard let url = navigationAction.request.url, url.scheme == "https" || url.absoluteString == "about:blank" else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    // 只读拉取官方余额；请求互斥、超时及频率限制，防止重复请求。
    func refresh(force: Bool = false) {
        guard !inFlight, navigationReady, web.url?.host == "console.superfastcode.com" else { return }
        let now = Date()
        guard now >= nextAttempt, now.timeIntervalSince(lastAttempt) >= (force ? 2 : 10) else { return }
        lastAttempt = now; inFlight = true
        let current = UUID(); requestID = current
        // Only GET; browser credentials remain inside the isolated WebKit store.
        // Return only quota fields. No emails, cookies, API keys or payment details.
        let script = """
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 18000);
        try {
          const r = await fetch('https://api-direct.superfastcode.com/api/console/bootstrap', {
            method: 'GET', credentials: 'include', cache: 'no-store', signal: controller.signal
          });
          if (!r.ok) return {status:r.status};
          const data = await r.json();
          const a = data.account;
          if (!a || !a.credit_breakdown) return {status:200, schema:false};
          const allowed = ['available_cents','plan_total_cents','plan_remaining_cents',
            'plan_remaining_released_cents','plan_pending_cents','current_week_release_cents',
            'wallet_cents','wallet_total_cents','next_release_at'];
          const b = {};
          for (const k of allowed) if (a.credit_breakdown[k] !== undefined && a.credit_breakdown[k] !== null) b[k] = a.credit_breakdown[k];
          return {status:200, account:{credit_breakdown:b, subscription_expires_at:a.subscription_expires_at ?? null}};
        } catch (_) { return {status:0}; }
        finally { clearTimeout(timeout); }
        """
        web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.requestID == current else { return }
            self.inFlight = false
            switch result {
            case .success(let raw):
                guard let payload = raw as? [String: Any], let status = payload["status"] as? Int else { self.state = "更新失败"; self.updateDisplay(); return }
                if status == 200, let account = payload["account"] as? [String:Any], let parsed = try? QuotaSnapshot(account: account) {
                    self.snapshot = parsed; self.state = "已更新"
                    UserDefaults.standard.set(true, forKey: "hasConnected")
                } else if status == 401 {
                    self.snapshot = nil; self.state = "请先登录"
                } else if status == 403 { self.state = "需网页验证" }
                else if status == 429 { self.state = "稍后重试"; self.nextAttempt = Date().addingTimeInterval(120) }
                else if status == 200 { self.state = "字段已变化" }
                else { self.state = "更新失败" }
            case .failure: self.state = "更新失败"
            }
            self.updateDisplay()
        }
    }

    var isFresh: Bool { state == "已更新" && snapshot.map { Date().timeIntervalSince($0.fetchedAt) <= max(90, interval*2) } == true }
    // 只有新鲜数据才显示余额，网络异常时撤下数值，避免旧值误导。
    func updateDisplay() {
        if isFresh, let s = snapshot {
            ball.value = String(format: "%.2f", s.available / 100)
            ball.caption = "余额学分"
            ball.fraction = nil
        } else {
            ball.value = state == "请先登录" ? "登录" : "···"
            ball.caption = state == "已更新" ? "数据过期" : state
            ball.fraction = nil
        }
        ball.needsDisplay = true
        ball.toolTip = "账户余额：\(ball.value) 学分。点击查看明细，拖动调整位置。"
        ball.setAccessibilityLabel("额度悬浮球，\(ball.caption)，\(ball.value)。点击查看明细。")
        statusItem.button?.title = isFresh ? "余额 \(ball.value) 学分" : "额度 · \(ball.caption)"
    }
    func add(_ menu: NSMenu, _ title: String, _ action: Selector? = nil, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.tag = tag; menu.addItem(item); return item
    }
    func makeMenu() -> NSMenu {
        let m = NSMenu()
        _ = add(m, "Superfastcode 账户余额")
        _ = add(m, isFresh ? "每 \(Int(interval)) 秒更新" : (state == "已更新" ? "数据已过期，请刷新" : state))
        if let s = snapshot {
            m.addItem(.separator())
            if !isFresh { _ = add(m, "以下为上次成功读取，非当前数据") }
            _ = add(m, String(format: "账户余额：%.2f 学分", s.available/100))
            let df = DateFormatter(); df.dateFormat = "MM-dd HH:mm:ss"
            _ = add(m, "更新于 \(df.string(from: s.fetchedAt))")
        }
        m.addItem(.separator())
        _ = add(m, "立即刷新", #selector(manualRefresh))
        _ = add(m, "登录 / 查看官网", #selector(showLogin))
        _ = add(m, "重新连接网页", #selector(reloadWebsite))
        let speed = add(m, interval == 30 ? "刷新频率：30 秒" : "刷新频率：60 秒")
        let sub = NSMenu()
        for seconds in [30,60] { let item = add(sub, "\(seconds) 秒", #selector(selectInterval(_:)), tag: seconds); item.state = Int(interval) == seconds ? .on : .off }
        speed.submenu = sub
        _ = add(m, panel.isVisible ? "隐藏悬浮球" : "显示悬浮球", #selector(toggleBall))
        _ = add(m, "将小球移回屏幕右侧", #selector(resetPosition))
        m.addItem(.separator()); _ = add(m, "退出 Token 悬浮球", #selector(quit))
        return m
    }
    func dateText(_ text: String) -> String {
        let f = ISO8601DateFormatter()
        var date = f.date(from: text)
        if date == nil { f.formatOptions.insert(.withFractionalSeconds); date = f.date(from: text) }
        guard let date else { return text }
        let out = DateFormatter(); out.dateFormat = "MM-dd HH:mm（本地）"; return out.string(from: date)
    }
    func showMenu() { makeMenu().popUp(positioning: nil, at: NSPoint(x: 18,y: 12), in: ball) }
    @objc func statusClick() { if let button = statusItem.button { makeMenu().popUp(positioning: nil, at: NSPoint(x: 0,y: button.bounds.minY), in: button) } }
    @objc func manualRefresh() { refresh(force: true) }
    @objc func selectMetric(_ item: NSMenuItem) { metric = Metric.allCases[item.tag]; UserDefaults.standard.set(metric.rawValue, forKey: "metric"); updateDisplay() }
    @objc func selectInterval(_ item: NSMenuItem) { interval = Double(item.tag); UserDefaults.standard.set(interval, forKey: "interval"); startTimer(); updateDisplay() }
    @objc func toggleBall() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc func resetPosition() { UserDefaults.standard.removeObject(forKey: "ballX"); positionBall(); panel.orderFrontRegardless() }
    @objc func quit() { NSApp.terminate(nil) }

    func renderChecks() {
        let dir = CommandLine.arguments.last!
        for (name, value, caption, frac) in [("余额", "123.45", "余额学分", -1.0), ("大额余额", "12345.67", "余额学分", -1.0), ("零余额", "0.00", "余额学分", -1.0), ("待登录", "登录", "请先登录", -1.0), ("更新失败", "···", "更新失败", -1.0)] {
            for (theme, appearance) in [("浅色", NSAppearance.Name.aqua),("深色", NSAppearance.Name.darkAqua)] {
                ball.appearance = NSAppearance(named: appearance)
                ball.value=value; ball.caption=caption; ball.fraction=frac<0 ? nil : frac
                ball.display()
                let rep = ball.bitmapImageRepForCachingDisplay(in: ball.bounds)!
                ball.cacheDisplay(in: ball.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("测试_\(name)_\(theme).png"))
            }
        }
        print("Rendered synthetic UI states only; no network or account data.")
        NSApp.terminate(nil)
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
