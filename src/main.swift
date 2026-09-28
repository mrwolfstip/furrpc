import AppKit
import ServiceManagement

let defaultid = "1554136413669433354"
let fallbackimage = "https://files.catbox.moe/95gjsg.png"
let githuburl = "https://github.com/mrwolfstip/furrpc"
let supportdir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("furrpc")
let configurl = supportdir.appendingPathComponent("config.json")
let logurl = supportdir.appendingPathComponent("furrpc.log")

// plain text log next to the config. one line per event, old lines are dropped once the file passes 512 kb
enum logger {
    static let queue = DispatchQueue(label: "furrpc.log")
    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ level: String, _ msg: String) {
        let line = "\(stamp.string(from: Date())) [\(level)] \(msg)\n"
        queue.sync {
            let fm = FileManager.default
            try? fm.createDirectory(at: supportdir, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: logurl.path))?[.size] as? Int, size > 512_000 {
                let old = logurl.appendingPathExtension("old")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: logurl, to: old)
            }
            if !fm.fileExists(atPath: logurl.path) { fm.createFile(atPath: logurl.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: logurl), let d = line.data(using: .utf8) else { return }
            h.seekToEndOfFile()
            h.write(d)
            try? h.close()
        }
    }
    static func info(_ msg: String) { write("info", msg) }
    static func warn(_ msg: String) { write("warn", msg) }
    static func error(_ msg: String) { write("error", msg) }
}

// config is a plain json dictionary so a missing key never breaks anything
var cfg: [String: Any] = [:]

func loadcfg() {
    cfg = (try? JSONSerialization.jsonObject(with: Data(contentsOf: configurl))) as? [String: Any] ?? [:]
    logger.info("config loaded: \(apps.count) apps, temp \(flag("temperature") ? "on" : "off"), menubar \(flag("menubar") ? "on" : "off")")
}

func savecfg() {
    try? FileManager.default.createDirectory(at: supportdir, withIntermediateDirectories: true)
    let data = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys])
    do {
        try data?.write(to: configurl)
        logger.info("config saved")
    } catch {
        logger.error("could not save config: \(error.localizedDescription)")
    }
}

var clientid: String { cfg["client_id"] as? String ?? defaultid }
var apps: [String] {
    get { cfg["apps"] as? [String] ?? [] }
    set { cfg["apps"] = newValue }
}
// flag defaults to on, flagoff defaults to off (for options that must be opted into)
func flag(_ key: String) -> Bool { cfg[key] as? Bool ?? true }
func flagoff(_ key: String) -> Bool { cfg[key] as? Bool ?? false }
// apps the user switched off in the table. they stay in the list but get no presence
var disabled: [String] {
    get { cfg["disabled"] as? [String] ?? [] }
    set { cfg["disabled"] = newValue }
}
// per app name, image and client id chosen by the user, stored as { bundle id: { "name": ..., "image": ..., "client_id": ... } }
var overrides: [String: [String: String]] {
    get { cfg["overrides"] as? [String: [String: String]] ?? [:] }
    set { cfg["overrides"] = newValue }
}

struct approw {
    var id: String
    var enabled = true
    var name = ""
    var clientid = ""
    var image = ""
}

func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in parent: NSView) {
    view.frame = NSRect(x: x, y: y, width: w, height: h)
    parent.addSubview(view)
}

func setlogin(_ on: Bool) {
    do {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        logger.info("start at login \(on ? "enabled" : "disabled")")
    } catch {
        logger.error("could not \(on ? "enable" : "disable") start at login: \(error.localizedDescription)")
    }
}
var loginon: Bool { SMAppService.mainApp.status == .enabled }

// games.json is local only: the bundled example (shows the format), then the user's own file on top of it. nothing is downloaded
func loadgames() -> [String: [String: String]] {
    var out: [String: [String: String]] = [:]
    let files = [Bundle.main.url(forResource: "games", withExtension: "json"), supportdir.appendingPathComponent("games.json")]
    for case let url? in files {
        guard let data = try? Data(contentsOf: url) else { continue }
        guard let map = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            logger.warn("games file is not valid, skipped: \(url.path)")
            continue
        }
        out.merge(map) { $1 }
        logger.info("games file read: \(url.lastPathComponent) (\(map.count) entries)")
    }
    return out.filter { !$0.key.hasPrefix("_") }
}

func sysctlstr(_ key: String) -> String {
    var n = 0
    sysctlbyname(key, nil, &n, nil, 0)
    var buf = [CChar](repeating: 0, count: n)
    sysctlbyname(key, &buf, &n, nil, 0)
    return String(cString: buf)
}
let hwline = "\(sysctlstr("hw.model")) - \(sysctlstr("machdep.cpu.brand_string"))".lowercased()

// apple silicon die temperature through the hid sensor api (private symbols, no root needed).
// returns nil whenever no sane reading exists, so intel macs and odd chips just show no temperature
@_silgen_name("IOHIDEventSystemClientCreate") func hidcreate(_ a: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching") func hidmatch(_ c: AnyObject, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") func hidservices(_ c: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyEvent") func hidevent(_ s: AnyObject, _ t: Int64, _ o: Int32, _ ts: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyProperty") func hidprop(_ s: AnyObject, _ k: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue") func hidfloat(_ e: AnyObject, _ f: Int32) -> Double

func readtemp() -> Double? {
    guard let client = hidcreate(nil)?.takeRetainedValue() else { return nil }
    _ = hidmatch(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
    guard let list = hidservices(client)?.takeRetainedValue() as? [AnyObject] else { return nil }
    var hot: Double?
    for s in list {
        guard let name = hidprop(s, "Product" as CFString)?.takeRetainedValue() as? String, name.contains("tdie"),
              let event = hidevent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
        let v = hidfloat(event, 15 << 16)
        if v > 10 && v < 130 { hot = max(hot ?? v, v) }
    }
    return hot
}

// when the app itself started. launchDate is missing for some apps, and falling back to "now" would make the
// timer count from whenever furrpc first noticed the app, so ask the system for the real process start time instead
func procstart(_ pid: pid_t) -> Date? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let t = info.kp_proc.p_starttime
    guard t.tv_sec > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
}

var firstseen: [pid_t: Date] = [:]
func starttime(_ a: NSRunningApplication) -> Date {
    let pid = a.processIdentifier
    if let d = a.launchDate ?? procstart(pid) { return d }
    // last resort, remembered so the timer does not restart on every refresh
    if let d = firstseen[pid] { return d }
    let d = Date()
    firstseen[pid] = d
    logger.warn("no start time for pid \(pid), counting from now")
    return d
}

// minimal discord ipc: unix socket, 8 byte header (opcode + length, little endian) then json
final class ipc {
    var fd: Int32 = -1
    var ready = false
    var src: DispatchSourceRead?
    var pending: [String: Any]?
    var last: [String: Any]?
    var warned = false
    var lastname: String?
    var cid = ""

    var connected: Bool { fd >= 0 }

    func connect(_ id: String) {
        guard fd < 0 else { return }
        cid = id
        for i in 0..<10 {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { return }
            var one: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, 4)
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let path = NSTemporaryDirectory() + "discord-ipc-\(i)"
            _ = withUnsafeMutableBytes(of: &addr.sun_path) { p in
                strlcpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), path, p.count)
            }
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if ok != 0 { close(s); continue }
            fd = s
            break
        }
        guard fd >= 0 else {
            // refresh runs every few seconds, so only say this once until discord comes back
            if !warned { logger.warn("discord ipc socket not found, is discord open?") }
            warned = true
            return
        }
        warned = false
        logger.info("connected to discord ipc")
        let f = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: f, queue: .main)
        source.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            if read(f, &buf, buf.count) <= 0 {
                logger.warn("discord closed the connection")
                self?.drop()
                return
            }
            // the first frame back is discord's ready, so send whatever was waiting
            if let me = self, !me.ready {
                me.ready = true
                logger.info("discord is ready")
                if let p = me.pending { me.set(p) }
            }
        }
        source.setCancelHandler { close(f) }
        source.resume()
        src = source
        send(0, ["v": 1, "client_id": id])
    }

    func drop() {
        if fd >= 0 { logger.info("dropping discord connection") }
        src?.cancel()
        src = nil
        fd = -1
        ready = false
        last = nil
        lastname = nil
    }

    func send(_ op: UInt32, _ obj: [String: Any]) {
        guard fd >= 0, let body = try? JSONSerialization.data(withJSONObject: obj) else { return }
        var head = [op.littleEndian, UInt32(body.count).littleEndian]
        var buf = Data(bytes: &head, count: 8)
        buf.append(body)
        let n = buf.count
        if buf.withUnsafeBytes({ write(fd, $0.baseAddress, n) }) < 0 {
            logger.error("could not write to discord (errno \(errno))")
            drop()
        }
    }

    // nil clears the presence
    func set(_ activity: [String: Any]?) {
        pending = activity
        guard ready else { return }
        if let a = activity, let l = last, NSDictionary(dictionary: a).isEqual(to: l) { return }
        if activity == nil && last == nil { return }
        var args: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier]
        if let a = activity { args["activity"] = a }
        send(1, ["cmd": "SET_ACTIVITY", "args": args, "nonce": UUID().uuidString])
        // temperature changes resend the presence often, so only log when the game changes
        let name = activity?["name"] as? String
        if name != lastname {
            if let n = name { logger.info("presence set: \(n)") } else { logger.info("presence cleared") }
            lastname = name
        }
        last = activity
    }
}

final class furrpc: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let rpc = ipc()
    var games: [String: [String: String]] = [:]
    var timer: Timer?
    var item: NSStatusItem?
    var win: NSWindow?
    var tabs: NSTabView!
    var table: NSTableView!
    var hint: NSTextField!
    var status: NSTextField!
    var idfield: NSTextField!
    var popup: NSPopUpButton!
    var checks: [NSButton] = []
    var running: [String] = []
    var rows: [approw] = []
    var tempwarned = false

    func applicationDidFinishLaunching(_ n: Notification) {
        logger.info("furrpc started, \(hwline)")
        signal(SIGPIPE, SIG_IGN)
        makemenu()
        let first = !FileManager.default.fileExists(atPath: configurl.path)
        loadcfg()
        if first { logger.info("first launch, writing default config"); savecfg(); setlogin(true) }
        // no polling: the system tells us when the active app changes
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("furrpc.reload"), object: nil, queue: .main) { [weak self] _ in self?.reload() }
        reload()
        if apps.isEmpty { showwindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showwindow()
        return true
    }

    func reload() {
        logger.info("reloading")
        loadcfg()
        games = loadgames()
        rpc.drop()
        if flag("menubar") {
            if item == nil { makeitem() }
        } else if let i = item {
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
        refresh()
    }

    // the app to show: the one in front if it is on the list, otherwise (with background on) the first listed app that is running
    func target() -> NSRunningApplication? {
        let on = apps.filter { !disabled.contains($0) }
        if let f = NSWorkspace.shared.frontmostApplication, let id = f.bundleIdentifier, on.contains(id) { return f }
        guard flagoff("background") else { return nil }
        for id in on {
            if let r = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { !$0.isTerminated }) { return r }
        }
        return nil
    }

    func refresh() {
        // opening our own window should not wipe the presence
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() { return }
        timer?.invalidate()
        timer = nil
        guard let a = target(), let id = a.bundleIdentifier else {
            rpc.set(nil)
            return
        }
        let g = games[id]
        let mine = overrides[id]
        func pick(_ v: String?) -> String? { (v?.isEmpty ?? true) ? nil : v }
        // each app can use its own discord application. a different client id means a new connection
        let cid = pick(mine?["client_id"]) ?? pick(g?["client_id"]) ?? clientid
        if rpc.connected && rpc.cid != cid {
            logger.info("client id changed, reconnecting")
            rpc.drop()
        }
        rpc.connect(cid)
        let name = pick(mine?["name"]) ?? g?["name"] ?? a.localizedName?.lowercased() ?? id
        let image = pick(mine?["image"]) ?? g?["image"] ?? fallbackimage
        var act: [String: Any] = [
            "name": name,
            "type": 0,
            "timestamps": ["start": Int(starttime(a).timeIntervalSince1970)],
            "assets": ["large_image": image, "large_text": name],
        ]
        let showtemp = flag("temperature")
        if showtemp, let t = readtemp() {
            tempwarned = false
            act["details"] = "temp \(Int(t.rounded()))°c"
            act["state"] = hwline
        } else {
            if showtemp && !tempwarned {
                tempwarned = true
                logger.warn("temperature is on but no sensor reading is available")
            }
            act["details"] = hwline
        }
        rpc.set(act)
        // playtime is drawn by discord from the start time. this timer refreshes the temperature every 5 seconds
        // (rpc.set skips the update when nothing changed) and retries a missing discord connection
        let every: TimeInterval = showtemp ? 5 : 60
        let t = Timer(timeInterval: every, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = showtemp ? 1 : 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func makeitem() {
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = Bundle.main.image(forResource: "menubar") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            i.button?.image = img
        } else {
            i.button?.title = ":3"
        }
        let m = NSMenu()
        m.addItem(withTitle: "open furrpc", action: #selector(showwindow), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "quit furrpc", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        i.menu = m
        item = i
    }

    // accessory apps have no menu bar, but text fields still need the edit shortcuts
    func makemenu() {
        let bar = NSMenu()
        let appitem = NSMenuItem()
        let appmenu = NSMenu()
        appmenu.addItem(withTitle: "quit furrpc", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appitem.submenu = appmenu
        let edititem = NSMenuItem()
        let edit = NSMenu(title: "edit")
        edit.addItem(withTitle: "cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "select all", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edititem.submenu = edit
        bar.addItem(appitem)
        bar.addItem(edititem)
        NSApp.mainMenu = bar
    }

    func buildwindow() {
        let W: CGFloat = 640, H: CGFloat = 620
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "furrpc"
        w.isReleasedWhenClosed = false
        w.center()
        let v = w.contentView!

        // header: name and one line summary on the left, github link and logo top right
        let title = NSTextField(labelWithString: "furrpc")
        title.font = .boldSystemFont(ofSize: 22)
        place(title, 20, 574, 200, 28, in: v)
        let sub = NSTextField(labelWithString: "finds the process, matches it to an image, and sends it to your discord")
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor
        place(sub, 20, 556, 440, 16, in: v)
        if let logo = Bundle.main.image(forResource: "furrpc") {
            let iv = NSImageView(image: logo)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 10
            iv.layer?.masksToBounds = true
            place(iv, W - 20 - 48, 562, 48, 48, in: v)
        }
        // white icon and text, so it sits on a black pill to stay readable in light and dark mode
        let gh = NSButton(title: "github", target: self, action: #selector(opengithub))
        gh.isBordered = false
        gh.wantsLayer = true
        gh.layer?.backgroundColor = NSColor.black.cgColor
        gh.layer?.cornerRadius = 6
        gh.attributedTitle = NSAttributedString(string: " github", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
        if let icon = githubicon() {
            gh.image = icon
            gh.imagePosition = .imageLeft
        }
        gh.toolTip = githuburl
        place(gh, W - 20 - 48 - 12 - 88, 574, 88, 24, in: v)

        let t = NSTabView()
        tabs = t
        place(t, 12, 56, W - 24, 490, in: v)
        let cr = t.contentRect
        let cw = cr.width, ch = cr.height
        func tab(_ label: String) -> NSView {
            let item = NSTabViewItem()
            item.label = label
            let view = NSView(frame: NSRect(x: 0, y: 0, width: cw, height: ch))
            item.view = view
            t.addTabViewItem(item)
            return view
        }

        // tab 1: setup guide
        let guide = tab("setup")
        let gs = NSTextView.scrollableTextView()
        let gt = gs.documentView as! NSTextView
        gt.isEditable = false
        gt.isSelectable = true
        gt.textContainerInset = NSSize(width: 10, height: 10)
        gt.textStorage?.setAttributedString(guidetext())
        gs.borderType = .bezelBorder
        place(gs, 8, 8, cw - 16, ch - 16, in: guide)

        // tab 2: apps table
        let appsview = tab("apps")
        hint = NSTextField(labelWithString: "")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        place(hint, 8, ch - 24, cw - 16, 16, in: appsview)
        table = NSTableView()
        let cols: [(String, String, CGFloat, CGFloat)] = [
            ("on", "on", 30, 30), ("name", "name", 105, 60), ("bundle", "bundle id", 140, 80),
            ("client", "client id", 125, 70), ("image", "image / asset", 100, 60), ("actions", "", 96, 96),
        ]
        for (id, label, width, minw) in cols {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = label
            c.width = width
            c.minWidth = minw
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = false
        table.target = self
        table.doubleAction = #selector(editclicked(_:))
        let ts = NSScrollView()
        ts.documentView = table
        ts.hasVerticalScroller = true
        ts.hasHorizontalScroller = true
        ts.borderType = .bezelBorder
        place(ts, 8, 72, cw - 16, ch - 104, in: appsview)
        popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.menu?.delegate = self
        place(popup, 8, 38, cw - 16 - 150, 26, in: appsview)
        place(NSButton(title: "add running app", target: self, action: #selector(addrunning)), cw - 8 - 142, 38, 142, 26, in: appsview)
        place(NSButton(title: "add by bundle id…", target: self, action: #selector(addmanual)), 8, 8, 150, 26, in: appsview)

        // tab 3: settings
        let sv = tab("settings")
        let idlabel = NSTextField(labelWithString: "default client id (discord application id)")
        idlabel.font = .boldSystemFont(ofSize: 12)
        place(idlabel, 12, ch - 32, cw - 24, 17, in: sv)
        idfield = NSTextField(string: "")
        place(idfield, 12, ch - 58, cw - 24, 22, in: sv)
        let idhint = NSTextField(labelWithString: "used by every app without a client id of its own. see step 2 in the setup tab.")
        idhint.font = .systemFont(ofSize: 11)
        idhint.textColor = .secondaryLabelColor
        place(idhint, 12, ch - 78, cw - 24, 16, in: sv)
        let titles = ["show temperature", "menu bar item", "start at login", "show even when the app is in the background"]
        for (n, title) in titles.enumerated() {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            place(b, 12, ch - 116 - CGFloat(n * 26), cw - 24, 20, in: sv)
            checks.append(b)
        }
        place(NSButton(title: "show local folder", target: self, action: #selector(openfolder)), 12, ch - 238, 150, 26, in: sv)
        let fh = NSTextField(labelWithString: "config.json, furrpc.log and your own games.json live there.")
        fh.font = .systemFont(ofSize: 11)
        fh.textColor = .secondaryLabelColor
        place(fh, 170, ch - 233, cw - 182, 16, in: sv)

        // bottom bar
        status = NSTextField(labelWithString: "")
        status.textColor = .secondaryLabelColor
        place(status, 20, 24, 400, 17, in: v)
        let save = NSButton(title: "save", target: self, action: #selector(savewin))
        save.keyEquivalent = "\r"
        place(save, W - 20 - 100, 16, 100, 30, in: v)
        win = w
    }

    // the github icon is black on transparent. invert the colors (black becomes white) and keep the alpha
    func githubicon() -> NSImage? {
        guard let src = Bundle.main.image(forResource: "github"),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let wd = cg.width, ht = cg.height
        guard wd > 0, ht > 0,
              let ctx = CGContext(data: nil, width: wd, height: ht, bitsPerComponent: 8, bytesPerRow: wd * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: wd, height: ht))
        let px = data.bindMemory(to: UInt8.self, capacity: wd * ht * 4)
        for i in 0..<(wd * ht) {
            let a = Int(px[i * 4 + 3])
            if a == 0 { continue }
            for c in 0..<3 {
                let straight = min(255, Int(px[i * 4 + c]) * 255 / a)
                px[i * 4 + c] = UInt8((255 - straight) * a / 255)
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: 14, height: 14))
    }

    func guidetext() -> NSAttributedString {
        let parts: [(String, Bool)] = [
            ("welcome to furrpc\n", true),
            ("furrpc finds the process, matches it to an image, and sends it to your discord. set it up once, change it any time. keep the discord desktop app open while you use it.\n\n", false),
            ("1. create a discord application\n", true),
            ("open discord.com/developers/applications, press new application, name it and create it. discord shows this name as what you are playing.\n\n", false),
            ("2. copy its client id\n", true),
            ("on the application page open general information and copy the application id. this long number is the client id. paste it in the settings tab as the default client id, or give a single app its own in the apps tab.\n\n", false),
            ("3. upload rich presence assets\n", true),
            ("in the application open rich presence, then art assets, and upload your pictures. the name of each asset is what you type as the image. new assets can take a few minutes to show up in discord.\n\n", false),
            ("4. pick an image\n", true),
            ("for each app use an asset name from step 3 (like my_game) or a full image url starting with https://. leave it blank to use the default image.\n\n", false),
            ("5. add your apps\n", true),
            ("open the app or game you want to show, come back here and open the apps tab. choose it in the list and press add running app, or press add by bundle id and type it (like com.example.game). use edit on a row to set its name, client id and image.\n\n", false),
            ("6. save\n", true),
            ("press save at the bottom right. only enabled apps are shown, and only while they are in front unless you turn on the background option in settings.\n\n", false),
            ("changing things later\n", true),
            ("everything can be changed at any time. click :3 in the menu bar and choose open furrpc, or open the app again. use the checkbox to turn an app off, edit to change it and remove to delete it, then press save.", false),
        ]
        let out = NSMutableAttributedString()
        for (text, heading) in parts {
            out.append(NSAttributedString(string: text, attributes: [
                .font: heading ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]))
        }
        let s = out.string as NSString
        let r = s.range(of: "discord.com/developers/applications")
        if r.location != NSNotFound {
            out.addAttribute(.link, value: URL(string: "https://discord.com/developers/applications")!, range: r)
        }
        return out
    }

    // table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn?.identifier.rawValue, row >= 0, row < rows.count else { return nil }
        let r = rows[row]
        func label(_ text: String, dim: Bool) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.lineBreakMode = .byTruncatingTail
            f.textColor = dim ? .secondaryLabelColor : .labelColor
            f.alphaValue = r.enabled ? 1 : 0.5
            f.toolTip = text
            return f
        }
        let g = games[r.id]
        switch col {
        case "on":
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(togglerow(_:)))
            b.state = r.enabled ? .on : .off
            b.tag = row
            return b
        case "name": return label(r.name.isEmpty ? (g?["name"] ?? "default") : r.name, dim: r.name.isEmpty)
        case "bundle": return label(r.id, dim: false)
        case "client": return label(r.clientid.isEmpty ? (g?["client_id"] ?? "default") : r.clientid, dim: r.clientid.isEmpty)
        case "image": return label(r.image.isEmpty ? (g?["image"] ?? "default") : r.image, dim: r.image.isEmpty)
        case "actions":
            let box = NSView()
            for (n, title) in ["edit", "remove"].enumerated() {
                let b = NSButton(title: title, target: self, action: n == 0 ? #selector(editclicked(_:)) : #selector(removeclicked(_:)))
                b.bezelStyle = .inline
                b.controlSize = .small
                b.font = .systemFont(ofSize: 11)
                b.tag = row
                b.frame = NSRect(x: n == 0 ? 0 : 46, y: 3, width: n == 0 ? 42 : 56, height: 20)
                box.addSubview(b)
            }
            return box
        default: return nil
        }
    }

    @objc func togglerow(_ sender: NSButton) {
        guard sender.tag >= 0 && sender.tag < rows.count else { return }
        rows[sender.tag].enabled = sender.state == .on
        table.reloadData()
    }

    @objc func removeclicked(_ sender: NSButton) {
        guard sender.tag >= 0 && sender.tag < rows.count else { return }
        rows.remove(at: sender.tag)
        table.reloadData()
        updatehint()
    }

    // the edit button passes its row in the tag, a double click on the table uses the clicked row
    @objc func editclicked(_ sender: Any?) {
        let i = (sender as? NSButton)?.tag ?? table.clickedRow
        guard i >= 0 && i < rows.count else { return }
        if let r = editrow(rows[i], isnew: false) {
            rows[i] = r
            table.reloadData()
        }
    }

    func updatehint() {
        hint.stringValue = rows.isEmpty
            ? "no apps yet. read the setup tab, add an app below, then press save."
            : "tick to turn an app on or off. edit or remove it with the buttons. press save to apply."
    }

    func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.addButton(withTitle: "ok")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func checkclient(_ s: String) -> String? {
        (s.isEmpty || s.allSatisfy { $0.isASCII && $0.isNumber }) ? nil : "a client id is a long number, digits only"
    }

    func checkimage(_ s: String) -> String? {
        if s.contains(" ") { return "an image url or asset name has no spaces" }
        if s.contains("://") && !(s.hasPrefix("https://") || s.hasPrefix("http://")) { return "use an https:// image url or an asset name" }
        return nil
    }

    func validate(_ r: approw, isnew: Bool) -> String? {
        if r.id.isEmpty { return "enter a bundle id, like com.example.game" }
        if r.id.contains(" ") { return "a bundle id has no spaces" }
        if isnew && rows.contains(where: { $0.id == r.id }) { return "that app is already in the list" }
        return checkclient(r.clientid) ?? checkimage(r.image)
    }

    // one small dialog for both adding and editing an app. blank fields mean default
    func editrow(_ start: approw, isnew: Bool) -> approw? {
        var r = start
        while true {
            let a = NSAlert()
            a.messageText = isnew ? "add an app" : "edit app"
            a.informativeText = "leave name, client id or image blank to use the default."
            a.addButton(withTitle: "ok")
            a.addButton(withTitle: "cancel")
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 176))
            let labels = ["bundle id", "name shown in discord", "client id (discord application id)", "image url or asset name"]
            let vals = [r.id, r.name, r.clientid, r.image]
            var fields: [NSTextField] = []
            for (n, text) in labels.enumerated() {
                let y = CGFloat(176 - (n + 1) * 44)
                place(NSTextField(labelWithString: text), 0, y + 22, 360, 16, in: box)
                let f = NSTextField(string: vals[n])
                place(f, 0, y, 360, 22, in: box)
                fields.append(f)
            }
            fields[0].isEnabled = isnew
            fields[0].placeholderString = "com.example.game"
            fields[1].placeholderString = games[r.id]?["name"] ?? "default name"
            fields[2].placeholderString = games[r.id]?["client_id"] ?? "default (settings tab)"
            fields[3].placeholderString = games[r.id]?["image"] ?? "default image"
            a.accessoryView = box
            a.window.initialFirstResponder = fields[isnew ? 0 : 1]
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return nil }
            func val(_ i: Int) -> String { fields[i].stringValue.trimmingCharacters(in: .whitespaces) }
            r.id = val(0)
            r.name = val(1)
            r.clientid = val(2)
            r.image = val(3)
            if let err = validate(r, isnew: isnew) {
                alert(err)
                continue
            }
            return r
        }
    }

    @objc func addmanual() {
        if let r = editrow(approw(id: ""), isnew: true) {
            rows.append(r)
            table.reloadData()
            table.scrollRowToVisible(rows.count - 1)
            updatehint()
        }
    }

    @objc func addrunning() {
        let i = popup.indexOfSelectedItem
        guard i >= 0 && i < running.count else { return }
        let id = running[i]
        if rows.contains(where: { $0.id == id }) {
            alert("that app is already in the list")
            return
        }
        rows.append(approw(id: id))
        table.reloadData()
        table.scrollRowToVisible(rows.count - 1)
        updatehint()
    }

    func refreshrunning() {
        var seen = Set<String>()
        let list = NSWorkspace.shared.runningApplications.filter {
            guard $0.activationPolicy == .regular, let id = $0.bundleIdentifier, $0 != NSRunningApplication.current else { return false }
            return seen.insert(id).inserted
        }
        let keep = popup.titleOfSelectedItem
        running = list.map { $0.bundleIdentifier! }
        popup.removeAllItems()
        popup.addItems(withTitles: list.map { ($0.localizedName ?? "").lowercased() + "  " + $0.bundleIdentifier! })
        if let k = keep, popup.itemTitles.contains(k) { popup.selectItem(withTitle: k) }
    }

    // the running list is refreshed every time the popup opens
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard popup != nil, menu === popup.menu else { return }
        refreshrunning()
    }

    @objc func opengithub() {
        if let u = URL(string: githuburl) { NSWorkspace.shared.open(u) }
    }

    @objc func openfolder() {
        try? FileManager.default.createDirectory(at: supportdir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(supportdir)
    }

    // fills the window from the saved config
    func loadwindow() {
        idfield.stringValue = clientid
        checks[0].state = flag("temperature") ? .on : .off
        checks[1].state = flag("menubar") ? .on : .off
        checks[2].state = loginon ? .on : .off
        checks[3].state = flagoff("background") ? .on : .off
        let off = disabled
        rows = apps.map { id in
            let o = overrides[id] ?? [:]
            return approw(id: id, enabled: !off.contains(id), name: o["name"] ?? "", clientid: o["client_id"] ?? "", image: o["image"] ?? "")
        }
        table.reloadData()
        updatehint()
        refreshrunning()
        // nothing set up yet: start on the setup guide
        tabs.selectTabViewItem(at: apps.isEmpty ? 0 : 1)
        status.stringValue = ""
    }

    @objc func showwindow() {
        if win == nil { buildwindow() }
        // do not throw away edits when the window is already open
        if win?.isVisible != true { loadwindow() }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }

    @objc func savewin() {
        let id = idfield.stringValue.trimmingCharacters(in: .whitespaces)
        if let m = checkclient(id) {
            alert(m)
            return
        }
        apps = rows.map { $0.id }
        disabled = rows.filter { !$0.enabled }.map { $0.id }
        var o: [String: [String: String]] = [:]
        for r in rows {
            var e: [String: String] = [:]
            if !r.name.isEmpty { e["name"] = r.name }
            if !r.clientid.isEmpty { e["client_id"] = r.clientid }
            if !r.image.isEmpty { e["image"] = r.image }
            if !e.isEmpty { o[r.id] = e }
        }
        overrides = o
        cfg["client_id"] = id.isEmpty ? defaultid : id
        cfg["temperature"] = checks[0].state == .on
        cfg["menubar"] = checks[1].state == .on
        cfg["background"] = checks[3].state == .on
        savecfg()
        setlogin(checks[2].state == .on)
        reload()
        idfield.stringValue = clientid
        status.stringValue = "saved"
    }
}

func onoff(_ b: Bool) -> String { b ? "on" : "off" }

func runcli(_ a: [String]) {
    loadcfg()
    let usage = """
    usage: furrpc <command>
      list                      show the apps that get a presence
      running                   show running apps and their bundle ids
      add <bundle id>           add an app
      remove <bundle id>        remove an app
      set temp on|off           show the mac temperature
      set menubar on|off        show the menu bar item
      set login on|off          start at login
      set id <application id>   use another discord application
      set background on|off     show even when the app is not in front
      enable <bundle id>        turn an app on
      disable <bundle id>       turn an app off without removing it
      set name <bundle id> [name]     change the name shown in discord (no name resets it)
      set image <bundle id> [url]     change the icon url or asset name (no url resets it)
      set appid <bundle id> [id]      give one app its own client id (no id resets it)
      status                    show all settings
      log [lines]               show the log file path and its last lines (default 40)
    """
    let arg = a.count > 1 ? a[1] : ""
    let val = a.count > 2 ? a[2] : ""
    var changed = true
    switch a[0] {
    case "list":
        apps.forEach { print($0) }
        changed = false
    case "running":
        for r in NSWorkspace.shared.runningApplications where r.activationPolicy == .regular {
            print("\((r.localizedName ?? "").lowercased())  \(r.bundleIdentifier ?? "")")
        }
        changed = false
    case "add" where !arg.isEmpty:
        if !apps.contains(arg) { apps.append(arg) }
    case "remove" where !arg.isEmpty:
        apps.removeAll { $0 == arg }
        disabled.removeAll { $0 == arg }
    case "enable" where !arg.isEmpty:
        disabled.removeAll { $0 == arg }
    case "disable" where !arg.isEmpty:
        if !disabled.contains(arg) { disabled.append(arg) }
    case "set" where !val.isEmpty:
        switch arg {
        case "temp": cfg["temperature"] = val == "on"
        case "menubar": cfg["menubar"] = val == "on"
        case "login": setlogin(val == "on")
        case "background": cfg["background"] = val == "on"
        case "name", "image", "appid":
            // furrpc set name <bundle id> <name...>, an empty value removes the customization
            let key = arg == "appid" ? "client_id" : arg
            let rest = a.dropFirst(3).joined(separator: " ")
            var o = overrides
            var e = o[val] ?? [:]
            e[key] = rest.isEmpty ? nil : rest
            o[val] = e.isEmpty ? nil : e
            overrides = o
        case "id": cfg["client_id"] = val
        default: print(usage); changed = false
        }
    case "log":
        print(logurl.path)
        let n = Int(arg) ?? 40
        if let text = try? String(contentsOf: logurl, encoding: .utf8) {
            text.split(separator: "\n", omittingEmptySubsequences: true).suffix(n).forEach { print($0) }
        } else {
            print("no log yet")
        }
        changed = false
    case "status":
        print("apps: \(apps.count)")
        print("temp: \(onoff(flag("temperature")))")
        print("menubar: \(onoff(flag("menubar")))")
        print("login: \(onoff(loginon))")
        print("background: \(onoff(flagoff("background")))")
        print("disabled: \(disabled.count)")
        print("customized: \(overrides.count)")
        print("id: \(clientid)")
        changed = false
    default:
        print(usage)
        changed = false
    }
    if changed {
        logger.info("cli: \(a.joined(separator: " "))")
        savecfg()
        // tell a running furrpc to reload
        DistributedNotificationCenter.default().postNotificationName(.init("furrpc.reload"), object: nil, userInfo: nil, deliverImmediately: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if !args.isEmpty { runcli(args); exit(0) }

let nsapp = NSApplication.shared
let delegate = furrpc()
nsapp.delegate = delegate
nsapp.setActivationPolicy(.accessory)
nsapp.run()
