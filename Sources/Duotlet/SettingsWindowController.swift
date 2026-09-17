import AppKit
import SwiftUI
import Combine

/// A regular settings window remains reachable even with the menu item hidden.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let preferences: Preferences
    private let updater: AppUpdater
    private var dockSubscription: AnyCancellable?

    init(controller: LidController, preferences: Preferences, updater: AppUpdater) {
        self.preferences = preferences
        self.updater = updater
        let content = NSHostingController(rootView: SettingsView(
            preferences: preferences, controller: controller, updater: updater))
        content.sizingOptions = [.preferredContentSize]
        window = NSWindow(contentViewController: content)
        super.init()
        window.title = "Duotlet"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("DuotletSettings")
        window.center()
        dockSubscription = preferences.$showsDockIcon.combineLatest(updater.$isPresentingUpdate).sink { visible, updating in
            NSApp.setActivationPolicy(visible || updating ? .regular : .accessory)
        }
    }

    func show() {
        NSApp.setActivationPolicy(preferences.showsDockIcon || updater.isPresentingUpdate ? .regular : .accessory)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(preferences.showsDockIcon || updater.isPresentingUpdate ? .regular : .accessory)
    }
}
