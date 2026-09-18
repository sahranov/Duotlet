import AppKit
import CoreGraphics
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controlObserver: NSObjectProtocol?
    private var controller: LidController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?
    private let updater = AppUpdater()
    private var effectSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.geometry.notice("launched, screen recording granted: \(CGPreflightScreenCaptureAccess())")
        let preferences = Preferences.shared
        Analytics.startIfAllowed(preferences: preferences)
        controlObserver = DistributedNotificationCenter.default().addObserver(
            forName: ControlState.changed, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Preferences.shared.refreshControlState() }
        }
        let controller = LidController(preferences: preferences)
        self.controller = controller
        let settings = SettingsWindowController(controller: controller, preferences: preferences, updater: updater)
        settingsWindowController = settings
        statusItemController = StatusItemController(controller: controller, preferences: preferences, updater: updater,
            showSettings: { [weak settings] in settings?.show() })
        effectSubscription = preferences.$isEnabled.removeDuplicates().dropFirst().sink { [weak settings] enabled in
            guard enabled else { return }
            // All entry points (settings, menu, native control) use this preference.
            // Defer until @Published has committed the new value before opening UI.
            Task { @MainActor in
                ScreenCapturePermission.shared.refresh()
                if !ScreenCapturePermission.shared.hasAccess { settings?.show() }
            }
        }
        installApplicationMenu()
        NotificationCenter.default.addObserver(forName: .init("DuotletLanguageChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.installApplicationMenu() }
        }
        // Login launches remain in the background. Explicit launches open settings.
        let isLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let needsPermission = preferences.isEnabled && !ScreenCapturePermission.shared.hasAccess
        if !preferences.hasCompletedOnboarding || (!isLogin && (!CommandLine.arguments.contains("--background") || needsPermission)) {
            settings.show()
        }
        controller.start()
        updater.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ScreenCapturePermission.shared.refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openSettings() { settingsWindowController?.show() }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        let app = NSMenu(title: "Duotlet")
        let settings = NSMenuItem(title: SettingsLanguage.selected.localized("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        app.addItem(settings)
        let updates = NSMenuItem(title: SettingsLanguage.selected.localized("Check for Updates…"),
            action: #selector(AppUpdater.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = updater
        app.addItem(updates)
        app.addItem(.separator())
        app.addItem(withTitle: SettingsLanguage.selected.localized("Quit Duotlet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = app
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}
