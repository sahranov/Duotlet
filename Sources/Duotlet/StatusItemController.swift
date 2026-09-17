import AppKit
import Combine

/// A compact native menu; all preferences live in the app's settings window.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let preferences: Preferences
    private let controller: LidController
    private let updater: AppUpdater
    private let showSettings: () -> Void
    private var subscriptions = Set<AnyCancellable>()
    private var titleTimer: Timer?
    private let effectItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    private let updateItem = NSMenuItem()

    init(controller: LidController, preferences: Preferences, updater: AppUpdater, showSettings: @escaping () -> Void) {
        self.controller = controller
        self.preferences = preferences
        self.updater = updater
        self.showSettings = showSettings
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        effectItem.target = self
        effectItem.action = #selector(toggleEffect)
        settingsItem.target = self
        settingsItem.action = #selector(openSettings)
        settingsItem.keyEquivalent = ","
        updateItem.target = updater
        updateItem.action = #selector(AppUpdater.checkForUpdates(_:))
        quitItem.target = NSApp
        quitItem.action = #selector(NSApplication.terminate(_:))
        quitItem.keyEquivalent = "q"
        menu.addItem(effectItem)
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(updateItem)
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.image = Self.makeMenuBarIcon()
        statusItem.button?.imagePosition = .imageLeading
        preferences.$showsMenuBarIcon.removeDuplicates().sink { [weak self] visible in
            self?.statusItem.isVisible = visible
        }.store(in: &subscriptions)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTitle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
        refreshTitle()
    }

    deinit { titleTimer?.invalidate() }

    func menuWillOpen(_ menu: NSMenu) {
        let language = SettingsLanguage.selected
        ScreenCapturePermission.shared.refresh()
        let paused = preferences.isEnabled && !ScreenCapturePermission.shared.hasAccess
        effectItem.title = language.localized(preferences.isEnabled ? "Turn effect off" : "Turn effect on")
        effectItem.state = paused ? .mixed : (preferences.isEnabled ? .on : .off)
        permissionItem.title = language.localized("Effect paused — screen access required")
        permissionItem.isHidden = !paused
        settingsItem.title = language.localized("Settings…")
        updateItem.title = language.localized(updater.availableVersion == nil ? "Check for Updates…" : "Update Available…")
        quitItem.title = language.localized("Quit Duotlet")
    }

    @objc private func toggleEffect() { preferences.isEnabled.toggle() }
    @objc private func openSettings() { showSettings() }

    private func refreshTitle() {
        statusItem.button?.title = preferences.showsAngleInMenuBar
            ? String(format: " %.0f°", controller.currentAngle) : ""
    }

    private static var fallbackResources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private static func makeMenuBarIcon() -> NSImage {
        // Load the vector export of Resources/MenuBarIcon.svg. Packaged apps
        // keep the SwiftPM resource bundle inside Contents/Resources.
        let resources = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("Duotlet_Duotlet.bundle")) }
            ?? Self.fallbackResources
        let image = resources.url(forResource: "MenuBarIcon", withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Duotlet")
            ?? NSImage(size: NSSize(width: 20, height: 20))
        image.size = NSSize(width: 20, height: 20)
        image.accessibilityDescription = "Duotlet"
        image.isTemplate = true
        return image
    }
}
