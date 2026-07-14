import AppKit

// Ping several public resolvers; we're "online" if any one of them replies, so a
// single provider's blip doesn't trigger a false "internet down" alert.
private let pingHosts = ["1.1.1.1", "8.8.8.8"]

private enum ConnectionState {
    case online, offline, paused
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

// MARK: - Menu building blocks

private let menuRowWidth: CGFloat = 320
private let menuMargin: CGFloat = 14

/// The round macOS "?" button; clicking it pops up a short explanation.
final class HelpButton: NSButton {
    private static var popover: NSPopover?
    private let helpText: String

    init(_ helpText: String) {
        self.helpText = helpText
        super.init(frame: .zero)
        bezelStyle = .helpButton
        title = ""
        controlSize = .small
        target = self
        action = #selector(showHelp)
        sizeToFit()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func showHelp() {
        Self.popover?.close()

        let label = NSTextField(wrappingLabelWithString: helpText)
        label.font = .systemFont(ofSize: 12)
        label.preferredMaxLayoutWidth = 210
        let textHeight = label.fittingSize.height
        label.frame = NSRect(x: 12, y: 10, width: 210, height: textHeight)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 234, height: textHeight + 20))
        content.addSubview(label)
        let controller = NSViewController()
        controller.view = content

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxX)
        Self.popover = popover
    }

    static func closeHelp() {
        popover?.close()
        popover = nil
    }
}

/// A menu row that looks and acts like a regular menu item (hover highlight,
/// click runs the action and closes the menu) but hosts an icon and a "?"
/// help button. NSMenuItem can't show extra controls, so these are custom views.
final class MenuRow: NSView {
    let rowTarget: AnyObject?
    let rowAction: Selector?
    private let titleLabel: NSTextField
    private let iconView = NSImageView()
    private var highlighted = false {
        didSet {
            needsDisplay = true
            updateColors()
        }
    }

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var symbolName: String? {
        didSet { applySymbol() }
    }

    init(title: String, helpText: String, symbol: String? = nil,
         target: AnyObject? = nil, action: Selector? = nil) {
        rowTarget = target
        rowAction = action
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 26))

        iconView.frame = NSRect(x: menuMargin + 2, y: 5, width: 16, height: 16)
        iconView.imageScaling = .scaleNone
        addSubview(iconView)

        let helpButton = HelpButton(helpText)
        helpButton.setFrameOrigin(NSPoint(x: menuRowWidth - helpButton.frame.width - 12,
                                          y: (frame.height - helpButton.frame.height) / 2))
        addSubview(helpButton)

        titleLabel.font = .menuFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 38, y: 4.5, width: helpButton.frame.minX - 46, height: 17)
        addSubview(titleLabel)

        symbolName = symbol
        applySymbol()
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func applySymbol() {
        guard let symbolName else {
            iconView.image = nil
            return
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        updateColors()
    }

    private func updateColors() {
        let active = rowAction != nil && highlighted
        titleLabel.textColor = active ? .selectedMenuItemTextColor : .labelColor
        iconView.contentTintColor = active ? .selectedMenuItemTextColor : .secondaryLabelColor
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlighted, rowAction != nil else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { highlighted = true }
    override func mouseExited(with event: NSEvent) { highlighted = false }

    override func mouseUp(with event: NSEvent) {
        guard let rowAction else { return }
        highlighted = false
        enclosingMenuItem?.menu?.cancelTracking()
        NSApp.sendAction(rowAction, to: rowTarget, from: self)
    }
}

/// The big header at the top of the menu: a tinted circular badge with an SF
/// Symbol, a bold verdict ("Connected"), and a detail line underneath.
final class StatusHeaderView: NSView {
    private let badge = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var badgeColor = NSColor.systemGray

    init(helpText: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 58))

        badge.wantsLayer = true
        badge.layer?.cornerRadius = 18
        badge.frame = NSRect(x: menuMargin, y: 11, width: 36, height: 36)
        addSubview(badge)

        iconView.frame = badge.bounds
        iconView.imageScaling = .scaleNone
        badge.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 60, y: 29, width: menuRowWidth - 60 - 40, height: 19)
        addSubview(titleLabel)

        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.frame = NSRect(x: 60, y: 13, width: menuRowWidth - 60 - 40, height: 14)
        addSubview(subtitleLabel)

        let helpButton = HelpButton(helpText)
        helpButton.setFrameOrigin(NSPoint(x: menuRowWidth - helpButton.frame.width - 12,
                                          y: (frame.height - helpButton.frame.height) / 2))
        addSubview(helpButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(color: NSColor, symbol: String, title: String, subtitle: String) {
        badgeColor = color
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        applyBadgeColor()
    }

    private func applyBadgeColor() {
        badge.layer?.backgroundColor = badgeColor.withAlphaComponent(0.15).cgColor
        iconView.contentTintColor = badgeColor
    }

    // CGColors don't adapt to appearance changes on their own; re-resolve.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBadgeColor()
    }
}

/// One rounded stat card: a big value over a small uppercase caption.
final class StatTile: NSView {
    private let valueLabel: NSTextField

    var value: String {
        get { valueLabel.stringValue }
        set { valueLabel.stringValue = newValue }
    }

    init(caption: String, frame: NSRect) {
        valueLabel = NSTextField(labelWithString: "—")
        super.init(frame: frame)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: 0, y: frame.height - 26, width: frame.width, height: 19)
        addSubview(valueLabel)

        let captionLabel = NSTextField(labelWithString: caption.uppercased())
        captionLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center
        captionLabel.frame = NSRect(x: 0, y: 5, width: frame.width, height: 11)
        addSubview(captionLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

/// Sparkline of recent checks: newest at the right, green = replied, red =
/// no reply (drawn taller so failures stand out), dim dots = no data yet.
final class HistoryView: NSView {
    var results: [Bool] = [] {
        didSet { needsDisplay = true }
    }

    private let barsLeft: CGFloat = 78
    private let barsRight: CGFloat = menuRowWidth - 44

    init(helpText: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 26))

        let caption = NSTextField(labelWithString: "HISTORY")
        caption.font = .systemFont(ofSize: 9, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: menuMargin, y: 7, width: 60, height: 11)
        addSubview(caption)

        let helpButton = HelpButton(helpText)
        helpButton.setFrameOrigin(NSPoint(x: menuRowWidth - helpButton.frame.width - 12,
                                          y: (frame.height - helpButton.frame.height) / 2))
        addSubview(helpButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth: CGFloat = 5
        let step: CGFloat = barWidth + 3
        let capacity = Int((barsRight - barsLeft) / step)
        guard capacity > 0 else { return }

        var x = barsRight - barWidth
        for ok in results.suffix(capacity).reversed() {
            let height: CGFloat = ok ? 9 : 15
            (ok ? NSColor.systemGreen : NSColor.systemRed).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: (bounds.height - height) / 2,
                                             width: barWidth, height: height),
                         xRadius: 2.5, yRadius: 2.5).fill()
            x -= step
        }

        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        var remaining = capacity - min(results.count, capacity)
        while remaining > 0 {
            NSBezierPath(roundedRect: NSRect(x: x, y: bounds.height / 2 - 1.5,
                                             width: barWidth, height: 3),
                         xRadius: 1.5, yRadius: 1.5).fill()
            x -= step
            remaining -= 1
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var menuRefreshTimer: Timer?
    private let checkQueue = DispatchQueue(label: "network-check")

    private var isOnline: Bool?          // nil until the first check completes
    private var downSince: Date?
    private var checkInFlight = false

    // Stats
    private var totalPings = 0
    private var failedPings = 0
    private var lastPingDate: Date?
    private var history: [Bool] = []     // recent check results, oldest first

    // Settings (persisted)
    private var monitoringEnabled = (UserDefaults.standard.object(forKey: "monitoringEnabled") as? Bool) ?? true
    private var checkInterval: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "checkInterval")
        return (1...60).contains(stored) ? stored : 15
    }()
    private var autoFixEnabled = UserDefaults.standard.bool(forKey: "autoFixWifi")

    // Auto-fix state
    private var autoFixInFlight = false
    private var lastAutoFix: Date?
    // Minimum time between Wi-Fi cycles, so a genuine outage (router/ISP down)
    // doesn't make us toggle Wi-Fi on every failed check.
    private let autoFixCooldown: TimeInterval = 60

    // Menu views
    private let header = StatusHeaderView(
        helpText: "Pingo's current verdict: whether the internet answered the last check and when — or, if it's down, since when.")
    private var uptimeTile: StatTile!
    private var pingsTile: StatTile!
    private var failedTile: StatTile!
    private lazy var historyView = HistoryView(
        helpText: "The most recent checks, newest on the right — green means the internet answered, red means it didn't.")
    private var pauseRow: MenuRow!
    private var autoFixSwitch: NSSwitch!
    private var intervalValueLabel: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.addItem(viewItem(header))
        menu.addItem(.separator())
        menu.addItem(makeStatsItem())
        menu.addItem(viewItem(historyView))
        menu.addItem(.separator())

        pauseRow = MenuRow(
            title: "Pause Monitoring",
            helpText: "Pause or resume the automatic checks. While paused, Pingo doesn't ping or notify and the icon dims.",
            symbol: "pause.circle",
            target: self, action: #selector(toggleMonitoring))
        menu.addItem(rowItem(pauseRow, keyEquivalent: "p"))

        let checkRow = MenuRow(
            title: "Check Now",
            helpText: "Run one check right now instead of waiting for the next scheduled one. Works even while paused.",
            symbol: "arrow.clockwise",
            target: self, action: #selector(checkNow))
        menu.addItem(rowItem(checkRow, keyEquivalent: "r"))

        menu.addItem(makeAutoFixSwitchItem())

        menu.addItem(.separator())
        menu.addItem(makeIntervalSliderItem())
        menu.addItem(.separator())

        let quitRow = MenuRow(
            title: "Quit Pingo",
            helpText: "Quit Pingo completely. Monitoring stops until you open it again.",
            symbol: "power",
            target: NSApp, action: #selector(NSApplication.terminate(_:)))
        menu.addItem(rowItem(quitRow, keyEquivalent: "q"))

        menu.delegate = self
        statusItem.menu = menu

        refreshUI()
        applyMonitoringState(initial: true)
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    /// Wraps a MenuRow in an NSMenuItem. The action/target on the item keep
    /// the keyboard shortcut working; mouse clicks are handled by the row view.
    private func rowItem(_ row: MenuRow, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: "", action: row.rowAction, keyEquivalent: keyEquivalent)
        item.target = row.rowTarget
        item.view = row
        return item
    }

    // MARK: - Stats tiles

    private func makeStatsItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 46))
        let gap: CGFloat = 8
        let tileWidth = (menuRowWidth - menuMargin * 2 - gap * 2 - 26) / 3
        func tileFrame(_ i: CGFloat) -> NSRect {
            NSRect(x: menuMargin + i * (tileWidth + gap), y: 1, width: tileWidth, height: 44)
        }
        uptimeTile = StatTile(caption: "Uptime", frame: tileFrame(0))
        pingsTile = StatTile(caption: "Pings", frame: tileFrame(1))
        failedTile = StatTile(caption: "Failed", frame: tileFrame(2))
        container.addSubview(uptimeTile)
        container.addSubview(pingsTile)
        container.addSubview(failedTile)

        let helpButton = HelpButton("This session's numbers: the share of checks the internet answered, how many checks have run, and how many failed.")
        helpButton.setFrameOrigin(NSPoint(x: menuRowWidth - helpButton.frame.width - 12,
                                          y: (container.frame.height - helpButton.frame.height) / 2))
        container.addSubview(helpButton)

        return viewItem(container)
    }

    // MARK: - Interval slider

    private func makeIntervalSliderItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 56))

        let title = NSTextField(labelWithString: "Check interval")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.frame = NSRect(x: menuMargin, y: 36, width: 140, height: 16)
        container.addSubview(title)

        let helpButton = HelpButton("How often Pingo pings \(pingHosts.joined(separator: " and ")) to see if the internet is answering.")
        helpButton.setFrameOrigin(NSPoint(x: menuRowWidth - helpButton.frame.width - 12, y: 34))
        container.addSubview(helpButton)

        intervalValueLabel = NSTextField(labelWithString: "")
        intervalValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        intervalValueLabel.textColor = .controlAccentColor
        intervalValueLabel.alignment = .right
        intervalValueLabel.frame = NSRect(x: helpButton.frame.minX - 76, y: 36, width: 70, height: 16)
        container.addSubview(intervalValueLabel)

        let slider = NSSlider(value: checkInterval, minValue: 1, maxValue: 60,
                              target: self, action: #selector(intervalChanged(_:)))
        slider.frame = NSRect(x: 12, y: 8, width: menuRowWidth - 24, height: 22)
        container.addSubview(slider)

        updateIntervalLabel()
        return viewItem(container)
    }

    @objc private func intervalChanged(_ sender: NSSlider) {
        let newInterval = TimeInterval(Int(sender.doubleValue.rounded()))
        guard newInterval != checkInterval else { return }
        checkInterval = newInterval
        UserDefaults.standard.set(checkInterval, forKey: "checkInterval")
        updateIntervalLabel()
        if monitoringEnabled { restartTimer() }
    }

    private func updateIntervalLabel() {
        intervalValueLabel.stringValue = "every \(Int(checkInterval))s"
    }

    // MARK: - Auto-fix switch row

    private func makeAutoFixSwitchItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 30))

        let icon = NSImageView(frame: NSRect(x: menuMargin + 2, y: 7, width: 16, height: 16))
        icon.imageScaling = .scaleNone
        icon.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        container.addSubview(icon)

        let label = NSTextField(labelWithString: "Auto-Fix Wi-Fi")
        label.font = .menuFont(ofSize: 13)
        label.frame = NSRect(x: 38, y: 6, width: 150, height: 18)
        container.addSubview(label)

        autoFixSwitch = NSSwitch()
        autoFixSwitch.controlSize = .small
        autoFixSwitch.target = self
        autoFixSwitch.action = #selector(autoFixSwitchChanged(_:))
        autoFixSwitch.state = autoFixEnabled ? .on : .off
        autoFixSwitch.sizeToFit()
        autoFixSwitch.setFrameOrigin(NSPoint(x: container.frame.width - autoFixSwitch.frame.width - 14,
                                             y: (container.frame.height - autoFixSwitch.frame.height) / 2))
        container.addSubview(autoFixSwitch)

        let helpButton = HelpButton("When the internet stops answering, automatically turn Wi-Fi off and back on — the classic fix for a connection that looks fine but is stuck. Runs at most once per minute so a real outage isn't made worse.")
        helpButton.setFrameOrigin(NSPoint(x: autoFixSwitch.frame.minX - helpButton.frame.width - 8,
                                          y: (container.frame.height - helpButton.frame.height) / 2))
        container.addSubview(helpButton)

        return viewItem(container)
    }

    @objc private func autoFixSwitchChanged(_ sender: NSSwitch) {
        autoFixEnabled = sender.state == .on
        UserDefaults.standard.set(autoFixEnabled, forKey: "autoFixWifi")
    }

    // MARK: - Enable / disable

    @objc private func toggleMonitoring() {
        monitoringEnabled.toggle()
        UserDefaults.standard.set(monitoringEnabled, forKey: "monitoringEnabled")
        applyMonitoringState()
    }

    private func applyMonitoringState(initial: Bool = false) {
        pauseRow.title = monitoringEnabled ? "Pause Monitoring" : "Resume Monitoring"
        pauseRow.symbolName = monitoringEnabled ? "pause.circle" : "play.circle"
        if monitoringEnabled {
            setIcon(state: isOnline == false ? .offline : .online)
            restartTimer()
            runCheck()
        } else {
            timer?.invalidate()
            timer = nil
            // Forget connection state so resuming doesn't fire a stale notification.
            isOnline = nil
            downSince = nil
            setIcon(state: .paused)
        }
        refreshUI()
    }

    private func restartTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.runCheck()
        }
        // .common keeps the timer firing while the menu is open (menu tracking
        // switches the run loop out of .default mode).
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    // MARK: - Checking

    @objc private func checkNow() {
        runCheck()
    }

    private func runCheck() {
        guard !checkInFlight else { return }
        checkInFlight = true
        checkQueue.async { [weak self] in
            let online = Self.pingSucceeds()
            DispatchQueue.main.async {
                self?.checkInFlight = false
                self?.handleResult(online: online)
            }
        }
    }

    private func handleResult(online: Bool) {
        totalPings += 1
        if !online { failedPings += 1 }
        lastPingDate = Date()
        history.append(online)
        if history.count > 60 { history.removeFirst(history.count - 60) }

        let previous = isOnline
        isOnline = online

        if online {
            // Only notify on a state change, not on every check.
            if previous == false {
                var body = "Connection restored."
                if let downSince {
                    body = "Back after \(Self.formatDuration(Date().timeIntervalSince(downSince)))."
                }
                notify(title: "Internet is back", body: body)
            }
            downSince = nil
        } else {
            if downSince == nil { downSince = Date() }
            if previous == true {
                notify(title: "Internet is down",
                       body: "No reply from \(pingHosts.joined(separator: " or ")). Will keep checking every \(Int(checkInterval))s.")
            }
            if monitoringEnabled { maybeAutoFixWifi() }
        }

        setIcon(state: monitoringEnabled ? (online ? .online : .offline) : .paused)
        refreshUI()
    }

    /// Recomputes everything in the menu that shows state: header, tiles, history.
    private func refreshUI() {
        pingsTile?.value = "\(totalPings)"
        failedTile?.value = "\(failedPings)"
        uptimeTile?.value = totalPings > 0 ? "\((totalPings - failedPings) * 100 / totalPings)%" : "—"
        historyView.results = history

        let pausedSuffix = monitoringEnabled ? "" : " · paused"
        if let online = isOnline, let date = lastPingDate {
            if online {
                let ago = max(0, Int(Date().timeIntervalSince(date)))
                header.update(color: .systemGreen, symbol: "wifi",
                              title: "Connected",
                              subtitle: "Checked at \(timeFormatter.string(from: date)) — \(ago)s ago\(pausedSuffix)")
            } else {
                let since = downSince ?? date
                header.update(color: .systemRed, symbol: "wifi.slash",
                              title: "No Internet",
                              subtitle: "Down since \(timeFormatter.string(from: since)) — \(Self.formatDuration(Date().timeIntervalSince(since)))\(pausedSuffix)")
            }
        } else if monitoringEnabled {
            header.update(color: .systemGray, symbol: "wifi",
                          title: "Checking…", subtitle: "Running the first check")
        } else {
            header.update(color: .systemGray, symbol: "pause.fill",
                          title: "Monitoring paused", subtitle: "Resume to keep watching your connection")
        }
    }

    // MARK: - NSMenuDelegate (live refresh while the menu is open)

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
        let refresh = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }
        RunLoop.main.add(refresh, forMode: .common)
        menuRefreshTimer = refresh
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
        HelpButton.closeHelp()
    }

    // MARK: - Auto-fix Wi-Fi

    /// Cycles Wi-Fi off and on when checks fail — the classic fix for a network
    /// that shows as connected but has silently stopped passing traffic.
    private func maybeAutoFixWifi() {
        guard autoFixEnabled, !autoFixInFlight else { return }
        if let last = lastAutoFix, Date().timeIntervalSince(last) < autoFixCooldown { return }
        autoFixInFlight = true
        lastAutoFix = Date()

        notify(title: "Auto-Fix Wi-Fi",
               body: "Internet not answering — turning Wi-Fi off and on again.")

        DispatchQueue.global().async { [weak self] in
            if let device = Self.wifiDevice() {
                Self.setWifiPower(device, on: false)
                Thread.sleep(forTimeInterval: 2)
                Self.setWifiPower(device, on: true)
            }
            DispatchQueue.main.async {
                self?.autoFixInFlight = false
                // Give Wi-Fi a moment to reassociate, then verify right away
                // instead of waiting for the next scheduled check.
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    self?.runCheck()
                }
            }
        }
    }

    /// Finds the Wi-Fi interface name (usually "en0") from networksetup.
    private static func wifiDevice() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallhardwareports"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        var inWifiSection = false
        for line in output.split(separator: "\n") {
            if line.hasPrefix("Hardware Port:") {
                inWifiSection = line.contains("Wi-Fi") || line.contains("AirPort")
            } else if inWifiSection, line.hasPrefix("Device:") {
                return line.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func setWifiPower(_ device: String, on: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-setairportpower", device, on ? "on" : "off"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {}
    }

    // MARK: - Icon & notifications

    private func setIcon(state: ConnectionState) {
        guard let button = statusItem.button else { return }

        let name: String
        let description: String
        switch state {
        case .online:
            name = "antenna.radiowaves.left.and.right"
            description = "Internet connected"
        case .offline:
            name = "antenna.radiowaves.left.and.right.slash"
            description = "Internet down"
        case .paused:
            name = "antenna.radiowaves.left.and.right"
            description = "Monitoring paused"
        }

        button.image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        button.imagePosition = .imageLeading

        switch state {
        case .online:
            // Active: green icon + green "Online" label so you can see at a glance
            // that Pingo is running and the connection is good.
            button.image?.isTemplate = false
            button.contentTintColor = .systemGreen
            button.attributedTitle = NSAttributedString(string: " Online", attributes: [
                .foregroundColor: NSColor.systemGreen,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            ])
        case .offline:
            // Loud: red icon + red "Offline" label so a drop is impossible to miss.
            button.image?.isTemplate = false
            button.contentTintColor = .systemRed
            button.attributedTitle = NSAttributedString(string: " Offline", attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            ])
        case .paused:
            button.image?.isTemplate = true
            button.contentTintColor = .tertiaryLabelColor
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    /// Online if *any* host replies. Hosts are pinged in parallel so a slow/dead
    /// one doesn't add its timeout to the total check time.
    private static func pingSucceeds() -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var anySucceeded = false

        for host in pingHosts {
            group.enter()
            DispatchQueue.global().async {
                let ok = pingSucceeds(host: host)
                if ok {
                    lock.lock(); anySucceeded = true; lock.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        return anySucceeded
    }

    private static func pingSucceeds(host: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -c 1: one packet, -W 3000: wait max 3s for a reply, -t 4: give up entirely after 4s
        task.arguments = ["-c", "1", "-W", "3000", "-t", "4", host]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func notify(title: String, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"Submarine\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
