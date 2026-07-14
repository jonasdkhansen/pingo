import AppKit
import CoreLocation
import CoreWLAN

// Ping several public resolvers; we're "online" if any one of them replies, so a
// single provider's blip doesn't trigger a false "internet down" alert.
private let pingHosts = ["1.1.1.1", "8.8.8.8"]

private enum ConnectionState {
    case online, offline, paused
}

private enum WiFiRecoveryState {
    case idle, reconnectingPrimary, joiningBackup
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

// MARK: - Menu building blocks

private let menuRowWidth: CGFloat = 320
private let menuMargin: CGFloat = 14

/// Compact contextual help that opens a structured native popover on click.
final class HelpButton: NSButton {
    private static var popover: NSPopover?
    private static weak var activeButton: HelpButton?
    private let helpTitle: String
    private let helpText: String

    init(title: String, text: String) {
        helpTitle = title
        helpText = text
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        self.title = ""
        image = NSImage(systemSymbolName: "info.circle",
                        accessibilityDescription: "About \(title)")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        contentTintColor = .tertiaryLabelColor
        focusRingType = .exterior
        setAccessibilityLabel("About \(title)")
        toolTip = "About \(title)"
        target = self
        action = #selector(showHelp)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func showHelp() {
        if Self.activeButton === self, Self.popover?.isShown == true {
            Self.closeHelp()
            return
        }
        Self.popover?.close()

        let width: CGFloat = 238
        let heading = NSTextField(labelWithString: helpTitle)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = NSRect(x: 14, y: 0, width: width, height: 18)

        let body = NSTextField(wrappingLabelWithString: helpText)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = width
        let bodyHeight = body.fittingSize.height
        body.frame = NSRect(x: 14, y: 14, width: width, height: bodyHeight)
        heading.frame.origin.y = body.frame.maxY + 8

        let contentHeight = heading.frame.maxY + 14
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width + 28, height: contentHeight))
        content.addSubview(heading)
        content.addSubview(body)
        let controller = NSViewController()
        controller.view = content

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minX)
        Self.popover = popover
        Self.activeButton = self
    }

    static func closeHelp() {
        popover?.close()
        popover = nil
        activeButton = nil
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

        let helpButton = HelpButton(title: title, text: helpText)
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

final class GreenSwitch: NSButton {
    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 18) }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 18))
        setButtonType(.toggle)
        isBordered = false
        title = ""
        focusRingType = .exterior
        setAccessibilityLabel("Auto-Fix Wi-Fi")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0, dy: 1)
        let trackColor = state == .on
            ? NSColor.systemGreen
            : NSColor.tertiaryLabelColor.withAlphaComponent(0.45)
        trackColor.withAlphaComponent(isHighlighted ? 0.75 : 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()

        let knobSize = track.height - 4
        let knobX = state == .on ? track.maxX - knobSize - 2 : track.minX + 2
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: track.minY + 2,
                                    width: knobSize, height: knobSize)).fill()
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

        let helpButton = HelpButton(title: "Connection status", text: helpText)
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

        let helpButton = HelpButton(title: "Connection history", text: helpText)
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CLLocationManagerDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var menuRefreshTimer: Timer?
    private let checkQueue = DispatchQueue(label: "network-check")
    private let locationManager = CLLocationManager()

    private var isOnline: Bool?          // nil until the first check completes
    private var downSince: Date?
    private var checkInFlight = false
    private var consecutiveFailures = 0
    private var failureNetworkSSIDData: Data?
    private var backupAttemptedThisOutage = false

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
    private var backupSSIDData = UserDefaults.standard.data(forKey: "backupSSIDData")
    private var backupSSIDName = UserDefaults.standard.string(forKey: "backupSSIDName")

    // Wi-Fi recovery state
    private var recoveryState = WiFiRecoveryState.idle
    private var recoveryGeneration = 0
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
    private var autoFixSwitch: GreenSwitch!
    private var intervalValueLabel: NSTextField!
    private let backupMenu = NSMenu(title: "Backup Network")
    private var backupMenuItem: NSMenuItem!
    private var backupScanInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.delegate = self
        if autoFixEnabled, locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
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

        backupMenu.delegate = self
        backupMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        backupMenuItem.image = NSImage(systemSymbolName: "wifi.router",
                           accessibilityDescription: "Backup Network")
        backupMenuItem.toolTip = "Switch after three consecutive failed internet checks"
        backupMenuItem.submenu = backupMenu
        menu.addItem(backupMenuItem)
        updateBackupMenuTitle()

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

        let helpButton = HelpButton(
            title: "Session statistics",
            text: "This session's numbers: the share of checks the internet answered, how many checks have run, and how many failed.")
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

        let helpButton = HelpButton(
            title: "Check interval",
            text: "How often Pingo pings \(pingHosts.joined(separator: " and ")) to see if the internet is answering.")
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

        autoFixSwitch = GreenSwitch()
        autoFixSwitch.target = self
        autoFixSwitch.action = #selector(autoFixSwitchChanged(_:))
        autoFixSwitch.state = autoFixEnabled ? .on : .off
        autoFixSwitch.setFrameSize(autoFixSwitch.intrinsicContentSize)
        autoFixSwitch.setFrameOrigin(NSPoint(x: container.frame.width - autoFixSwitch.frame.width - 14,
                                             y: (container.frame.height - autoFixSwitch.frame.height) / 2))
        container.addSubview(autoFixSwitch)

        let helpButton = HelpButton(
            title: "Auto-Fix Wi-Fi",
            text: "When the internet stops answering, reconnect the same Wi-Fi network without powering Wi-Fi off. Location access is required so Pingo can identify the network name. Runs at most once per minute so a real outage isn't made worse.")
        helpButton.setFrameOrigin(NSPoint(x: autoFixSwitch.frame.minX - helpButton.frame.width - 8,
                                          y: (container.frame.height - helpButton.frame.height) / 2))
        container.addSubview(helpButton)

        return viewItem(container)
    }

    @objc private func autoFixSwitchChanged(_ sender: GreenSwitch) {
        autoFixEnabled = sender.state == .on
        UserDefaults.standard.set(autoFixEnabled, forKey: "autoFixWifi")
        if autoFixEnabled, locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Backup network selection

    private func updateBackupMenuTitle() {
        backupMenuItem?.title = backupSSIDName.map { "Backup Network: \($0)" } ?? "Choose Backup Network"
    }

    private func refreshBackupMenu() {
        refreshBackupMenuHeader()

        guard locationManager.authorizationStatus == .authorizedAlways else {
            let item = NSMenuItem(title: "Location Access Required", action: nil, keyEquivalent: "")
            item.isEnabled = false
            backupMenu.addItem(item)
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else {
                let settings = NSMenuItem(title: "Open Location Settings…",
                                          action: #selector(openLocationSettings), keyEquivalent: "")
                settings.target = self
                backupMenu.addItem(settings)
            }
            return
        }

        let scanning = NSMenuItem(title: "Scanning…", action: nil, keyEquivalent: "")
        scanning.isEnabled = false
        backupMenu.addItem(scanning)
        guard !backupScanInFlight else { return }
        backupScanInFlight = true

        DispatchQueue.global().async { [weak self] in
            let interface = CWWiFiClient.shared().interface()
            let currentSSIDData = interface?.ssidData()
            let scanResult = Result { try interface?.scanForNetworks(withName: nil) ?? [] }
            DispatchQueue.main.async {
                self?.backupScanInFlight = false
                self?.showBackupNetworks(scanResult, excluding: currentSSIDData)
            }
        }
    }

    private func showBackupNetworks(_ result: Result<Set<CWNetwork>, Error>, excluding currentSSIDData: Data?) {
        refreshBackupMenuHeader()

        switch result {
        case .success(let networks):
            var strongestBySSID: [Data: CWNetwork] = [:]
            for network in networks {
                guard let ssidData = network.ssidData, let ssid = network.ssid, !ssid.isEmpty,
                      ssidData != currentSSIDData else { continue }
                if let existing = strongestBySSID[ssidData], existing.rssiValue >= network.rssiValue { continue }
                strongestBySSID[ssidData] = network
            }

            let sortedNetworks = Array(strongestBySSID.values).sorted {
                ($0.ssid ?? "").localizedCaseInsensitiveCompare($1.ssid ?? "") == .orderedAscending
            }
            if sortedNetworks.isEmpty {
                let item = NSMenuItem(title: "No Other Networks Found", action: nil, keyEquivalent: "")
                item.isEnabled = false
                backupMenu.addItem(item)
            }
            for network in sortedNetworks {
                guard let ssidData = network.ssidData, let ssid = network.ssid else { continue }
                let item = NSMenuItem(title: ssid, action: #selector(selectBackupNetwork(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = network
                item.state = ssidData == backupSSIDData ? .on : .off
                backupMenu.addItem(item)
            }
        case .failure(let error):
            let item = NSMenuItem(title: "Scan Failed: \(error.localizedDescription)", action: nil,
                                  keyEquivalent: "")
            item.isEnabled = false
            backupMenu.addItem(item)
        }
    }

    private func refreshBackupMenuHeader() {
        backupMenu.removeAllItems()
        if backupSSIDData != nil {
            let disable = NSMenuItem(title: "Disable Backup", action: #selector(disableBackupNetwork),
                                     keyEquivalent: "")
            disable.target = self
            backupMenu.addItem(disable)
            backupMenu.addItem(.separator())
        }
    }

    @objc private func selectBackupNetwork(_ sender: NSMenuItem) {
        guard let network = sender.representedObject as? CWNetwork,
              let ssidData = network.ssidData else { return }
        if !network.supportsSecurity(.none), Self.savedWifiPassword(for: ssidData) == nil {
            notify(title: "Backup Network Not Selected",
                   body: "No saved password is available for “\(sender.title)”. Join it once in macOS first.")
            return
        }
        backupSSIDData = ssidData
        backupSSIDName = sender.title
        UserDefaults.standard.set(ssidData, forKey: "backupSSIDData")
        UserDefaults.standard.set(sender.title, forKey: "backupSSIDName")
        updateBackupMenuTitle()
    }

    @objc private func disableBackupNetwork() {
        backupSSIDData = nil
        backupSSIDName = nil
        UserDefaults.standard.removeObject(forKey: "backupSSIDData")
        UserDefaults.standard.removeObject(forKey: "backupSSIDName")
        updateBackupMenuTitle()
    }

    @objc private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
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
            recoveryGeneration += 1
            recoveryState = .idle
            consecutiveFailures = 0
            failureNetworkSSIDData = nil
            backupAttemptedThisOutage = false
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
        guard !checkInFlight, recoveryState == .idle else { return }
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
            consecutiveFailures = 0
            failureNetworkSSIDData = nil
            backupAttemptedThisOutage = false
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
            if monitoringEnabled {
                let currentSSIDData = CWWiFiClient.shared().interface()?.ssidData()
                if consecutiveFailures == 0 || currentSSIDData != failureNetworkSSIDData {
                    consecutiveFailures = 1
                    failureNetworkSSIDData = currentSSIDData
                } else {
                    consecutiveFailures += 1
                }
            }
            if previous == true {
                notify(title: "Internet is down",
                       body: "No reply from \(pingHosts.joined(separator: " or ")). Will keep checking every \(Int(checkInterval))s.")
            }
            if monitoringEnabled {
                if consecutiveFailures >= 3 {
                    maybeSwitchToBackup()
                } else {
                    maybeAutoFixWifi()
                }
            }
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
        if menu === backupMenu {
            refreshBackupMenu()
            return
        }
        refreshUI()
        let refresh = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }
        RunLoop.main.add(refresh, forMode: .common)
        menuRefreshTimer = refresh
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu !== backupMenu else { return }
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
        HelpButton.closeHelp()
    }

    // MARK: - Auto-fix Wi-Fi

    /// Remembers and reconnects the active Wi-Fi network when checks fail,
    /// without power-cycling the Wi-Fi radio.
    private func maybeAutoFixWifi() {
        guard autoFixEnabled, recoveryState == .idle else { return }
        if let last = lastAutoFix, Date().timeIntervalSince(last) < autoFixCooldown { return }

        guard locationManager.authorizationStatus == .authorizedAlways else {
            notify(title: "Auto-Fix Wi-Fi needs Location access",
                   body: "Allow Location access for Pingo so it can identify and reconnect your current Wi-Fi network.")
            return
        }

        recoveryState = .reconnectingPrimary
        lastAutoFix = Date()
        let generation = recoveryGeneration

        notify(title: "Auto-Fix Wi-Fi",
               body: "Internet not answering — reconnecting the current Wi-Fi network.")

        DispatchQueue.global().async { [weak self] in
            let reconnectError = Self.reconnectCurrentWifi()
            DispatchQueue.main.async {
                guard let self, generation == self.recoveryGeneration else { return }
                if let reconnectError {
                    self.recoveryState = .idle
                    self.notify(title: "Auto-Fix Wi-Fi couldn't reconnect", body: reconnectError)
                    return
                }
                // Give the network stack a moment to settle, then verify right
                // away instead of waiting for the next scheduled check.
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    guard generation == self.recoveryGeneration else { return }
                    self.recoveryState = .idle
                    if self.monitoringEnabled { self.runCheck() }
                }
            }
        }
    }

    private func maybeSwitchToBackup() {
        guard let backupSSIDData, let backupSSIDName,
              !backupAttemptedThisOutage, recoveryState == .idle else { return }
        guard CWWiFiClient.shared().interface()?.ssidData() != backupSSIDData else { return }

        guard locationManager.authorizationStatus == .authorizedAlways else {
            backupAttemptedThisOutage = true
            notify(title: "Backup Network needs Location access",
                     body: "Allow Location access for Pingo so it can find and join “\(backupSSIDName)”.")
            return
        }

        backupAttemptedThisOutage = true
        recoveryState = .joiningBackup
        let generation = recoveryGeneration
        notify(title: "Switching to Backup Network",
             body: "Three checks failed — trying “\(backupSSIDName)”.")

        DispatchQueue.global().async { [weak self] in
            let connectionError = Self.connectWifi(to: backupSSIDData, named: backupSSIDName)
            DispatchQueue.main.async {
                guard let self, generation == self.recoveryGeneration else { return }
                if let connectionError {
                    self.recoveryState = .idle
                    self.notify(title: "Backup Network couldn't connect", body: connectionError)
                    return
                }
                self.notify(title: "Connected to Backup Network",
                            body: "Joined “\(backupSSIDName)”. Verifying internet access.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    guard generation == self.recoveryGeneration else { return }
                    self.recoveryState = .idle
                    if self.monitoringEnabled { self.runCheck() }
                }
            }
        }
    }

    /// Returns an error message on failure. Every prerequisite is resolved
    /// before disassociating, so a failed preflight leaves Wi-Fi untouched.
    private static func reconnectCurrentWifi() -> String? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return "The Wi-Fi interface is unavailable or powered off."
        }
        guard let ssidData = interface.ssidData(),
              let ssid = interface.ssid(), !ssid.isEmpty else {
            return "Pingo couldn't identify the current Wi-Fi network."
        }

        return connectWifi(to: ssidData, named: ssid)
    }

    private static func connectWifi(to ssidData: Data, named ssid: String) -> String? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return "The Wi-Fi interface is unavailable or powered off."
        }

        let networks: Set<CWNetwork>
        do {
            networks = try interface.scanForNetworks(withSSID: ssidData)
        } catch {
            return "“\(ssid)” couldn't be found: \(error.localizedDescription)"
        }
        guard let network = networks.max(by: { $0.rssiValue < $1.rssiValue }) else {
            return "The Wi-Fi network “\(ssid)” is not in range."
        }

        let password: String?
        if network.supportsSecurity(.none) {
            password = nil
        } else {
            guard let savedPassword = savedWifiPassword(for: ssidData) else {
                return "No saved password is available for “\(ssid)”."
            }
            password = savedPassword
        }

        interface.disassociate()
        Thread.sleep(forTimeInterval: 1)
        do {
            try interface.associate(to: network, password: password)
            return nil
        } catch {
            return "Could not rejoin “\(ssid)”: \(error.localizedDescription)"
        }
    }

    private static func savedWifiPassword(for ssidData: Data) -> String? {
        var password: NSString?
        if CWKeychainFindWiFiPassword(.user, ssidData, &password) == errSecSuccess,
           let password {
            return password as String
        }
        password = nil
        if CWKeychainFindWiFiPassword(.system, ssidData, &password) == errSecSuccess,
           let password {
            return password as String
        }
        return nil
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
        let script = """
        on run argv
            display notification (item 2 of argv) with title (item 1 of argv) sound name "Submarine"
        end run
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script, "--", title, body]
        do {
            try task.run()
        } catch {
            NSLog("Pingo notification failed: %@", error.localizedDescription)
        }
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
