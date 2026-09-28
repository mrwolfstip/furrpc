import AppKit
import ServiceManagement

let defaultid = "1554136413669433354"
let fallbackimage = "https://files.catbox.moe/95gjsg.png"
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
// per app name and image chosen by the user, stored as { bundle id: { "name": ..., "image": ... } }
var overrides: [String: [String: String]] {
    get { cfg["overrides"] as? [String: [String: String]] ?? [:] }
    set { cfg["overrides"] = newValue }
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

// bundled games.json first, then the user's own file on top of it
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

    var connected: Bool { fd >= 0 }

    func connect() {
        guard fd < 0 else { return }
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
        send(0, ["v": 1, "client_id": clientid])
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

final class furrpc: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let rpc = ipc()
    var games: [String: [String: String]] = [:]
    var timer: Timer?
    var item: NSStatusItem?
    var win: NSWindow?
    var text: NSTextView!
    var idfield: NSTextField!
    var popup: NSPopUpButton!
    var checks: [NSButton] = []
    var running: [String] = []
    var tempwarned = false
    var custompopup: NSPopUpButton!
    var namefield: NSTextField!
    var imagefield: NSTextField!
    var pending: [String: [String: String]] = [:]
    var curcustom: String?

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
        if let f = NSWorkspace.shared.frontmostApplication, let id = f.bundleIdentifier, apps.contains(id) { return f }
        guard flagoff("background") else { return nil }
        for id in apps {
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
        rpc.connect()
        let g = games[id]
        let mine = overrides[id]
        func pick(_ v: String?) -> String? { (v?.isEmpty ?? true) ? nil : v }
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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 590), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "furrpc"
        w.isReleasedWhenClosed = false
        w.center()
        let v = w.contentView!
        func put(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ wd: CGFloat, _ h: CGFloat) {
            view.frame = NSRect(x: x, y: y, width: wd, height: h)
            v.addSubview(view)
        }
        put(NSTextField(labelWithString: "apps to show (one bundle id per line)"), 20, 555, 360, 17)
        let scroll = NSTextView.scrollableTextView()
        text = scroll.documentView as? NSTextView
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        scroll.borderType = .bezelBorder
        put(scroll, 20, 415, 360, 130)
        popup = NSPopUpButton(frame: .zero, pullsDown: false)
        put(popup, 20, 380, 300, 26)
        put(NSButton(title: "add", target: self, action: #selector(addrunning)), 325, 380, 55, 26)

        put(NSTextField(labelWithString: "customize an app (blank means default)"), 20, 348, 360, 17)
        custompopup = NSPopUpButton(frame: .zero, pullsDown: false)
        custompopup.menu?.delegate = self
        custompopup.target = self
        custompopup.action = #selector(pickcustom)
        put(custompopup, 20, 318, 360, 26)
        put(NSTextField(labelWithString: "name shown in discord"), 20, 294, 360, 17)
        namefield = NSTextField(string: "")
        put(namefield, 20, 270, 360, 22)
        put(NSTextField(labelWithString: "icon url (or asset name)"), 20, 246, 360, 17)
        imagefield = NSTextField(string: "")
        put(imagefield, 20, 222, 360, 22)

        put(NSTextField(labelWithString: "discord application id"), 20, 192, 360, 17)
        idfield = NSTextField(string: "")
        put(idfield, 20, 164, 360, 22)
        let titles = ["show temperature", "menu bar item", "start at login", "show even when the app is in the background"]
        for (n, title) in titles.enumerated() {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            put(b, 20, CGFloat(132 - n * 23), n == 3 ? 360 : 250, 20)
            checks.append(b)
        }
        let save = NSButton(title: "save", target: self, action: #selector(savewin))
        save.keyEquivalent = "\r"
        put(save, 285, 20, 100, 30)
        win = w
    }

    func listedapps() -> [String] {
        text.string.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // keeps whatever is typed in the name and icon fields for the app that is selected
    func commitfields() {
        guard let id = curcustom else { return }
        var e: [String: String] = [:]
        let n = namefield.stringValue.trimmingCharacters(in: .whitespaces)
        let i = imagefield.stringValue.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { e["name"] = n }
        if !i.isEmpty { e["image"] = i }
        pending[id] = e.isEmpty ? nil : e
    }

    func loadfields() {
        curcustom = custompopup.titleOfSelectedItem
        let e = curcustom.flatMap { pending[$0] } ?? [:]
        namefield.stringValue = e["name"] ?? ""
        imagefield.stringValue = e["image"] ?? ""
        let g = curcustom.flatMap { games[$0] }
        namefield.placeholderString = g?["name"] ?? "default name"
        imagefield.placeholderString = g?["image"] ?? fallbackimage
        namefield.isEnabled = curcustom != nil
        imagefield.isEnabled = curcustom != nil
    }

    @objc func pickcustom() {
        commitfields()
        loadfields()
    }

    // the customize list always matches what is currently typed in the apps box
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard custompopup != nil, menu === custompopup.menu else { return }
        commitfields()
        let keep = custompopup.titleOfSelectedItem
        custompopup.removeAllItems()
        custompopup.addItems(withTitles: listedapps())
        if let k = keep, custompopup.itemTitles.contains(k) { custompopup.selectItem(withTitle: k) }
        loadfields()
    }

    @objc func showwindow() {
        if win == nil { buildwindow() }
        text.string = apps.joined(separator: "\n")
        idfield.stringValue = clientid
        checks[0].state = flag("temperature") ? .on : .off
        checks[1].state = flag("menubar") ? .on : .off
        checks[2].state = loginon ? .on : .off
        checks[3].state = flagoff("background") ? .on : .off
        pending = overrides
        curcustom = nil
        custompopup.removeAllItems()
        custompopup.addItems(withTitles: apps)
        loadfields()
        let list = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0 != NSRunningApplication.current
        }
        running = list.map { $0.bundleIdentifier! }
        popup.removeAllItems()
        popup.addItems(withTitles: list.map { ($0.localizedName ?? "").lowercased() + "  " + $0.bundleIdentifier! })
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }

    @objc func addrunning() {
        let i = popup.indexOfSelectedItem
        guard i >= 0 && i < running.count else { return }
        if !text.string.isEmpty && !text.string.hasSuffix("\n") { text.string += "\n" }
        text.string += running[i] + "\n"
    }

    @objc func savewin() {
        commitfields()
        apps = listedapps()
        // only keep customizations for apps that are still on the list
        overrides = pending.filter { apps.contains($0.key) }
        let id = idfield.stringValue.trimmingCharacters(in: .whitespaces)
        cfg["client_id"] = id.isEmpty ? defaultid : id
        cfg["temperature"] = checks[0].state == .on
        cfg["menubar"] = checks[1].state == .on
        cfg["background"] = checks[3].state == .on
        savecfg()
        setlogin(checks[2].state == .on)
        reload()
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
      set name <bundle id> [name]     change the name shown in discord (no name resets it)
      set image <bundle id> [url]     change the icon url or asset name (no url resets it)
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
    case "set" where !val.isEmpty:
        switch arg {
        case "temp": cfg["temperature"] = val == "on"
        case "menubar": cfg["menubar"] = val == "on"
        case "login": setlogin(val == "on")
        case "background": cfg["background"] = val == "on"
        case "name", "image":
            // furrpc set name <bundle id> <name...>, an empty value removes the customization
            let rest = a.dropFirst(3).joined(separator: " ")
            var o = overrides
            var e = o[val] ?? [:]
            e[arg] = rest.isEmpty ? nil : rest
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
