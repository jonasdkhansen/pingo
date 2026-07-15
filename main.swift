import AppKit
import CoreLocation
import CoreWLAN
import UniformTypeIdentifiers

// Ping several public resolvers; we're "online" if any one of them replies, so a
// single provider's blip doesn't trigger a false "internet down" alert.
private let pingHosts = ["1.1.1.1", "8.8.8.8"]

// Where "Check for Updates…" sends the user. Hardcoded rather than following a
// URL taken from the API response — see AppDelegate.trustedReleaseURL.
private let releasesPageURL = URL(string: "https://github.com/jonasdkhansen/pingo/releases/latest")!

private enum ConnectionState {
    case online, offline, paused
}

private enum WiFiRecoveryState {
    case idle, reconnectingPrimary, joiningBackup
}

private enum WiFiPasswordLookup {
    case found(String), notFound, accessDenied
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

// Longer form used in the outage log, where entries may span multiple days.
private let logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, HH:mm:ss"
    return f
}()

private let exportDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// One recorded outage. `end` is nil while the outage is still in progress.
private struct OutageRecord: Codable {
    let start: Date
    var end: Date?
}

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

    /// macOS grants either `.authorizedWhenInUse` or `.authorizedAlways` in
    /// response to `requestWhenInUseAuthorization()`; both permit reading
    /// Wi-Fi network names, so every Location-access check must accept both.
    private var hasLocationAccess: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

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

    // Persisted log of past outages, oldest first. The last entry may still be
    // ongoing (end == nil); everything else has a known start and end.
    private var outages: [OutageRecord] = {
        guard let data = UserDefaults.standard.data(forKey: "outageLog"),
              let decoded = try? JSONDecoder().decode([OutageRecord].self, from: data)
        else { return [] }
        return decoded
    }()

    // Settings (persisted)
    private var monitoringEnabled = (UserDefaults.standard.object(forKey: "monitoringEnabled") as? Bool) ?? true
    private var checkInterval: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "checkInterval")
        return (1...60).contains(stored) ? stored : 15
    }()
    private var autoFixEnabled = UserDefaults.standard.bool(forKey: "autoFixWifi")
    private var backupSSIDData = UserDefaults.standard.data(forKey: "backupSSIDData")
    private var backupSSIDName = UserDefaults.standard.string(forKey: "backupSSIDName")
    private var backupBSSID = UserDefaults.standard.string(forKey: "backupBSSID")
    private var backupSecurityFingerprint = UserDefaults.standard.array(forKey: "backupSecurityFingerprint")?
        .compactMap { ($0 as? NSNumber)?.intValue }
    private var wifiPasswords: [Data: String] = [:]

    // Wi-Fi recovery state
    private var recoveryState = WiFiRecoveryState.idle
    private var recoveryGeneration = 0
    private var nextAutoFixAttempt: Date?
    // A failed association can happen while an access point is still returning,
    // so retry it quickly. A completed rejoin uses a longer guard to avoid
    // cycling Wi-Fi during an ISP or router outage.
    private let autoFixRetryDelay: TimeInterval = 10
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
    private let outageLogMenu = NSMenu(title: "Outage Log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.delegate = self
        // If the app quit mid-outage, resume that ongoing outage so the first
        // check continues it (when still down) or closes it (when back), rather
        // than starting a duplicate or leaving it "ongoing" forever.
        if let last = outages.last, last.end == nil {
            downSince = last.start
        }
        if backupSSIDData != nil && (backupBSSID == nil || backupSecurityFingerprint == nil) {
            disableBackupNetwork()
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.addItem(viewItem(header))
        menu.addItem(.separator())
        menu.addItem(makeStatsItem())
        menu.addItem(viewItem(historyView))

        outageLogMenu.delegate = self
        let logItem = NSMenuItem(title: "Outage Log", action: nil, keyEquivalent: "")
        logItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath",
                                accessibilityDescription: "Outage Log")
        logItem.toolTip = "Past outages with their start time and duration"
        logItem.submenu = outageLogMenu
        menu.addItem(logItem)

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

        let updateRow = MenuRow(
            title: "Check for Updates…",
            helpText: "Check GitHub Releases for a newer version of Pingo. Pingo only contacts GitHub when you choose this action.",
            symbol: "arrow.down.circle",
            target: self, action: #selector(checkForUpdates))
        menu.addItem(rowItem(updateRow))

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
        DispatchQueue.main.async { [weak self] in
            self?.requestLocationAccessAtLaunch()
        }
    }

    @objc private func checkForUpdates() {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/jonasdkhansen/pingo/releases/latest")!)
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        request.setValue("Pingo/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<GitHubRelease, Error>
            do {
                if let error { throw error }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode), let data else {
                    throw URLError(.badServerResponse)
                }
                result = .success(try JSONDecoder().decode(GitHubRelease.self, from: data))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { self.presentUpdateResult(result) }
        }.resume()
    }

    private func presentUpdateResult(_ result: Result<GitHubRelease, Error>) {
        let alert = NSAlert()
        switch result {
        case .success(let release):
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                alert.messageText = "Pingo \(latestVersion) is available"
                alert.informativeText = "You have Pingo \(currentVersion). Download the update, quit Pingo, then replace it in your Applications folder."
                alert.addButton(withTitle: "Open Release")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(Self.trustedReleaseURL(release.htmlURL))
                }
            } else {
                alert.messageText = "Pingo is up to date"
                alert.informativeText = "You’re using the latest version, Pingo \(currentVersion)."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        case .failure:
            alert.messageText = "Unable to check for updates"
            alert.informativeText = "Pingo couldn’t reach GitHub Releases. Check your internet connection and try again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// `NSWorkspace.open` launches the default handler for *any* URL scheme —
    /// including file:// and third-party custom schemes — and `html_url` arrives
    /// in the GitHub API response. Follow it only when it's an HTTPS github.com
    /// link; otherwise fall back to the canonical releases page instead of
    /// trusting a network-supplied URL.
    private static func trustedReleaseURL(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com") else {
            return releasesPageURL
        }
        return url
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
            text: "When the internet stops answering, reconnect the same Wi-Fi network without powering Wi-Fi off. Location access is required so Pingo can identify the network name. Failed reconnects retry after 10 seconds; a completed rejoin waits one minute before another attempt.")
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

        guard hasLocationAccess else {
            let item = NSMenuItem(title: "Location Access Required", action: nil, keyEquivalent: "")
            item.isEnabled = false
            backupMenu.addItem(item)
            if locationManager.authorizationStatus == .notDetermined {
                NSApp.activate(ignoringOtherApps: true)
                locationManager.requestWhenInUseAuthorization()
            } else if locationManager.authorizationStatus == .denied ||
                        locationManager.authorizationStatus == .restricted {
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
              let ssidData = network.ssidData, let bssid = network.bssid else { return }
        guard !network.supportsSecurity(.none) else {
            notify(title: "Backup Network Not Selected",
                   body: "Pingo won't automatically join open Wi-Fi networks because their identity cannot be authenticated.")
            return
        }
        switch Self.savedWifiPassword(for: ssidData) {
        case .found(let password):
            wifiPasswords[ssidData] = password
        case .notFound:
            notify(title: "Backup Network Not Selected",
                   body: "No saved password is available for “\(sender.title)”. Join it once in macOS first.")
            return
        case .accessDenied:
            notify(title: "Backup Network Not Selected",
                   body: "Pingo couldn't access Wi-Fi passwords. Quit and reopen Pingo, then allow Keychain access when asked.")
            return
        }
        backupSSIDData = ssidData
        backupSSIDName = sender.title
        backupBSSID = bssid
        backupSecurityFingerprint = Self.securityFingerprint(of: network)
        UserDefaults.standard.set(ssidData, forKey: "backupSSIDData")
        UserDefaults.standard.set(sender.title, forKey: "backupSSIDName")
        UserDefaults.standard.set(bssid, forKey: "backupBSSID")
        UserDefaults.standard.set(backupSecurityFingerprint, forKey: "backupSecurityFingerprint")
        updateBackupMenuTitle()
    }

    @objc private func disableBackupNetwork() {
        if let backupSSIDData {
            wifiPasswords.removeValue(forKey: backupSSIDData)
        }
        backupSSIDData = nil
        backupSSIDName = nil
        backupBSSID = nil
        backupSecurityFingerprint = nil
        UserDefaults.standard.removeObject(forKey: "backupSSIDData")
        UserDefaults.standard.removeObject(forKey: "backupSSIDName")
        UserDefaults.standard.removeObject(forKey: "backupBSSID")
        UserDefaults.standard.removeObject(forKey: "backupSecurityFingerprint")
        updateBackupMenuTitle()
    }

    @objc private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestLocationAccessAtLaunch() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Location Access Needed"
            alert.informativeText = "Pingo needs Location access to identify Wi-Fi network names for Auto-Fix and backup switching."
            alert.addButton(withTitle: "Open Location Settings")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                openLocationSettings()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }
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
            recordOutageEnd(Date())
            downSince = nil
        } else {
            if downSince == nil {
                downSince = Date()
                recordOutageStart(downSince!)
            }
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
                }
                // If backup failover is unavailable or already attempted, keep
                // retrying Auto-Fix after its cooldown instead of giving up.
                maybeAutoFixWifi()
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
        if menu === outageLogMenu {
            refreshOutageLog()
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
        guard menu !== backupMenu, menu !== outageLogMenu else { return }
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
        HelpButton.closeHelp()
    }

    // MARK: - Auto-fix Wi-Fi

    /// Remembers and reconnects the active Wi-Fi network when checks fail,
    /// without power-cycling the Wi-Fi radio.
    private func maybeAutoFixWifi() {
        guard autoFixEnabled, recoveryState == .idle else { return }
        if let nextAutoFixAttempt, Date() < nextAutoFixAttempt { return }

        guard hasLocationAccess else {
            if locationManager.authorizationStatus == .notDetermined {
                NSApp.activate(ignoringOtherApps: true)
                locationManager.requestWhenInUseAuthorization()
            }
            notify(title: "Auto-Fix Wi-Fi needs Location access",
                   body: "Allow Location access for Pingo so it can identify and reconnect your current Wi-Fi network.")
            return
        }

        recoveryState = .reconnectingPrimary
        let generation = recoveryGeneration

        notify(title: "Auto-Fix Wi-Fi",
               body: "Internet not answering — reconnecting the current Wi-Fi network.")

        DispatchQueue.global().async { [weak self] in
            let reconnectError = Self.reconnectCurrentWifi()
            DispatchQueue.main.async {
                guard let self, generation == self.recoveryGeneration else { return }
                if let reconnectError {
                    self.recoveryState = .idle
                    self.nextAutoFixAttempt = Date().addingTimeInterval(self.autoFixRetryDelay)
                    self.notify(title: "Auto-Fix Wi-Fi couldn't reconnect", body: reconnectError)
                    // Check again when the short retry window opens instead of
                    // waiting for the user-selected monitoring interval.
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.autoFixRetryDelay) {
                        guard generation == self.recoveryGeneration,
                              self.monitoringEnabled else { return }
                        self.runCheck()
                    }
                    return
                }
                self.nextAutoFixAttempt = Date().addingTimeInterval(self.autoFixCooldown)
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
        guard let backupSSIDData, let backupSSIDName, let backupBSSID,
              let backupSecurityFingerprint,
              !backupAttemptedThisOutage, recoveryState == .idle else { return }
        guard CWWiFiClient.shared().interface()?.ssidData() != backupSSIDData else { return }

        guard hasLocationAccess else {
            if locationManager.authorizationStatus == .notDetermined {
                NSApp.activate(ignoringOtherApps: true)
                locationManager.requestWhenInUseAuthorization()
            }
            backupAttemptedThisOutage = true
            notify(title: "Backup Network needs Location access",
                     body: "Allow Location access for Pingo so it can find and join “\(backupSSIDName)”.")
            return
        }

        backupAttemptedThisOutage = true
        recoveryState = .joiningBackup
        let generation = recoveryGeneration
        let backupPassword = wifiPasswords[backupSSIDData]
        notify(title: "Switching to Backup Network",
             body: "Three checks failed — trying “\(backupSSIDName)”.")

        DispatchQueue.global().async { [weak self] in
            let connectionError = Self.connectWifi(to: backupSSIDData, named: backupSSIDName,
                                                   bssid: backupBSSID,
                                                   securityFingerprint: backupSecurityFingerprint,
                                                   savedPassword: backupPassword)
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
              let ssid = interface.ssid(), !ssid.isEmpty,
              let bssid = interface.bssid() else {
            return "Pingo couldn't identify the current Wi-Fi network."
        }

        let networks: Set<CWNetwork>
        do {
            networks = try interface.scanForNetworks(withSSID: ssidData)
        } catch {
            return "“\(ssid)” couldn't be verified: \(error.localizedDescription)"
        }
        guard let currentNetwork = networks.first(where: { Self.sameBSSID($0.bssid, bssid) }) else {
            return "Pingo couldn't verify the current Wi-Fi access point."
        }

        return connectWifi(to: ssidData, named: ssid, bssid: bssid,
                           securityFingerprint: securityFingerprint(of: currentNetwork),
                           allowPasswordless: true)
    }

    private static func connectWifi(to ssidData: Data, named ssid: String, bssid: String,
                                    securityFingerprint expectedSecurity: [Int],
                                    savedPassword: String? = nil,
                                    allowPasswordless: Bool = false) -> String? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return "The Wi-Fi interface is unavailable or powered off."
        }

        let networks: Set<CWNetwork>
        do {
            networks = try interface.scanForNetworks(withSSID: ssidData)
        } catch {
            return "“\(ssid)” couldn't be found: \(error.localizedDescription)"
        }
        guard let network = networks.first(where: { sameBSSID($0.bssid, bssid) }) else {
            return "The trusted access point for “\(ssid)” is not in range. Pingo refused other networks using that name."
        }
        guard securityFingerprint(of: network) == expectedSecurity else {
            return "The security settings for “\(ssid)” changed. Pingo refused to connect."
        }

        let password: String?
        if network.supportsSecurity(.none) {
            guard allowPasswordless else {
                return "Pingo won't automatically join open Wi-Fi networks."
            }
            password = nil
        } else if let savedPassword {
            password = savedPassword
        } else {
            switch savedWifiPassword(for: ssidData) {
            case .found(let savedPassword):
                password = savedPassword
            case .notFound:
                guard allowPasswordless else {
                    return "No saved password is available for “\(ssid)”."
                }
                password = nil
            case .accessDenied:
                return "Pingo couldn't access Wi-Fi passwords. Quit and reopen Pingo, then allow Keychain access when asked."
            }
        }

        interface.disassociate()
        Thread.sleep(forTimeInterval: 1)
        do {
            try interface.associate(to: network, password: password)
            guard sameBSSID(interface.bssid(), bssid) else {
                interface.disassociate()
                return "Pingo joined an unexpected access point for “\(ssid)” and disconnected immediately."
            }
            return nil
        } catch {
            return "Could not rejoin “\(ssid)”: \(error.localizedDescription)"
        }
    }

    private static func securityFingerprint(of network: CWNetwork) -> [Int] {
        (0...15).compactMap { rawValue in
            guard let security = CWSecurity(rawValue: rawValue) else { return nil }
            return network.supportsSecurity(security) ? rawValue : nil
        }
    }

    private static func sameBSSID(_ first: String?, _ second: String) -> Bool {
        first?.caseInsensitiveCompare(second) == .orderedSame
    }

    private static func savedWifiPassword(for ssidData: Data) -> WiFiPasswordLookup {
        var password: NSString?
        if CWKeychainFindWiFiPassword(.user, ssidData, &password) == errSecSuccess,
           let password {
            return .found(password as String)
        }
        password = nil
        let systemStatus = CWKeychainFindWiFiPassword(.system, ssidData, &password)
        if systemStatus == errSecSuccess, let password {
            return .found(password as String)
        }
        return systemStatus == errSecItemNotFound ? .notFound : .accessDenied
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

    // MARK: - Outage log

    /// Begins a new outage record. Called on the transition into a down state.
    private func recordOutageStart(_ date: Date) {
        outages.append(OutageRecord(start: date, end: nil))
        saveOutages()
    }

    /// Closes the most recent still-open outage. No-op if none is open, so it's
    /// safe to call on any restored check (including one that closes a dangling
    /// outage left over from a previous session).
    private func recordOutageEnd(_ date: Date) {
        guard let idx = outages.lastIndex(where: { $0.end == nil }) else { return }
        outages[idx].end = date
        saveOutages()
    }

    private func saveOutages() {
        // Keep the log bounded; the newest entries are the ones worth keeping.
        if outages.count > 100 { outages.removeFirst(outages.count - 100) }
        if let data = try? JSONEncoder().encode(outages) {
            UserDefaults.standard.set(data, forKey: "outageLog")
        }
    }

    /// Rebuilds the Outage Log submenu, newest first. Called each time it opens.
    private func refreshOutageLog() {
        outageLogMenu.removeAllItems()

        guard !outages.isEmpty else {
            let empty = NSMenuItem(title: "No outages recorded", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            outageLogMenu.addItem(empty)
            return
        }

        let count = outages.count
        let header = NSMenuItem(title: "\(count) outage\(count == 1 ? "" : "s") · newest first",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        outageLogMenu.addItem(header)
        outageLogMenu.addItem(.separator())

        for outage in outages.reversed() {
            let duration = Self.formatDuration((outage.end ?? Date()).timeIntervalSince(outage.start))
            let item: NSMenuItem
            if let end = outage.end {
                item = NSMenuItem(title: "\(logDateFormatter.string(from: outage.start)) · \(duration)",
                                  action: nil, keyEquivalent: "")
                item.toolTip = "Down \(logDateFormatter.string(from: outage.start)) → \(timeFormatter.string(from: end))"
            } else {
                item = NSMenuItem(title: "\(logDateFormatter.string(from: outage.start)) · \(duration) · ongoing",
                                  action: nil, keyEquivalent: "")
                item.toolTip = "Down since \(logDateFormatter.string(from: outage.start)) — still ongoing"
            }
            item.isEnabled = false
            outageLogMenu.addItem(item)
        }

        outageLogMenu.addItem(.separator())
        let export = NSMenuItem(title: "Export Full Log…", action: #selector(exportOutageLog), keyEquivalent: "")
        export.target = self
        outageLogMenu.addItem(export)
        let clear = NSMenuItem(title: "Clear Log", action: #selector(clearOutageLog), keyEquivalent: "")
        clear.target = self
        outageLogMenu.addItem(clear)
    }

    @objc private func exportOutageLog() {
        let panel = NSSavePanel()
        panel.title = "Export Outage Log"
        panel.nameFieldStringValue = "pingo-outage-log.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exportedAt = Date()
        let rows = outages.map { outage -> String in
            let end = outage.end
            let duration = (end ?? exportedAt).timeIntervalSince(outage.start)
            return [
                exportDateFormatter.string(from: outage.start),
                end.map { exportDateFormatter.string(from: $0) } ?? "",
                Self.formatDuration(duration),
                String(format: "%.3f", duration),
                end == nil ? "ongoing" : "completed"
            ].map(Self.csvField).joined(separator: ",")
        }
        let csv = (["start,end,duration,duration_seconds,status"] + rows).joined(separator: "\n") + "\n"

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func clearOutageLog() {
        // Preserve an ongoing outage so the current state isn't lost.
        outages = outages.filter { $0.end == nil }
        saveOutages()
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

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
