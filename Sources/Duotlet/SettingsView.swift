import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var controller: LidController
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var screenPermission = ScreenCapturePermission.shared

    @State private var language = ControlState.language

    private var selectedLanguage: SettingsLanguage {
        SettingsLanguage(rawValue: language) ?? .english
    }

    private func localized(_ key: String) -> String { selectedLanguage.localized(key) }

    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var settingsOpenFailed = false
    @State private var loginError: String?

    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
    )!

    var body: some View {
        Form {
            Section(localized("Effect")) {
                toggleRow(localized("Depth effect"), isOn: $preferences.isEnabled, help: nil)
                if controller.isSensorAvailable {
                    LabeledContent(localized("Lid angle")) {
                        Text(String(format: "%.1f°", controller.currentAngle)).monospacedDigit()
                    }
                } else { unavailableNotice }
                if preferences.isEnabled && !screenPermission.hasAccess { permissionNotice }
            }
            Section(localized("General")) {
                Picker(localized("Language"), selection: $language) {
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Русский").tag("ru")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                }
                .onChange(of: language) { _, value in
                    ControlState.language = value
                    NotificationCenter.default.post(name: .init("DuotletLanguageChanged"), object: nil)
                }
                toggleRow(localized("Launch at login"), isOn: $launchesAtLogin, help: nil)
                    .onChange(of: launchesAtLogin) { _, value in setLaunchAtLogin(value) }
                toggleRow(
                    localized("Share anonymous analytics"),
                    isOn: $preferences.sharesAnonymousAnalytics,
                    help: localized("Helps count active users. No screen content or personal data is sent.")
                )
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
            }
            Section(localized("Appearance")) {
                toggleRow(localized("Show in Dock"), isOn: $preferences.showsDockIcon, help: nil)
                toggleRow(localized("Show menu bar icon"), isOn: $preferences.showsMenuBarIcon,
                    help: localized("You can always reopen settings from Applications or Spotlight."))
                toggleRow(localized("Show angle in menu bar"), isOn: $preferences.showsAngleInMenuBar, help: nil)
                    .disabled(!preferences.showsMenuBarIcon)
            }
            if #available(macOS 26.0, *) {
                Section(localized("Control Center")) {
                    Text(localized("Add Duotlet in Control Center → Edit Controls. The button turns the depth effect on or off."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section(localized("Updates")) {
                LabeledContent(localized("Version"), value: updater.version)
                LabeledContent(localized("Build"), value: updater.build)
                toggleRow(localized("Automatically check for updates"),
                    isOn: $updater.automaticallyChecksForUpdates, help: nil)
                if let date = updater.lastUpdateCheckDate {
                    LabeledContent(localized("Last checked")) {
                        Text(date, format: .dateTime.day().month().hour().minute())
                    }
                }
                if let status = updater.statusKey {
                    Text(localized(status))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(localized(updater.isChecking ? "Checking…" : "Check for Updates…")) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            HStack {
                Button(localized("Reset")) { preferences.resetToDefaults() }
                Spacer()
                Button(localized("Close")) { NSApp.keyWindow?.performClose(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .onAppear { refreshSystemState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemState()
        }
    }

    private func refreshSystemState() {
        screenPermission.refresh()
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var unavailableNotice: some View {
        Text(localized("This Mac has no lid angle sensor. Only some MacBook models have one."))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, help: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(title)
            }
            description(help)
        }
    }

    @ViewBuilder
    private func description(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localized("Effect paused"), systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(localized("Duotlet needs access to your screen to display the effect. Allow Screen Recording to continue."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(localized("Allow Screen Recording")) {
                    if !screenPermission.requestAccess() { openScreenRecordingSettings() }
                }
                .controlSize(.small)
                .disabled(screenPermission.isRequesting)
            }
            if settingsOpenFailed {
                Text(localized("Could not open System Settings. Open it manually and enable screen recording for Duotlet under Privacy & Security."))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func openScreenRecordingSettings() {
        settingsOpenFailed = false
        Task { @MainActor in
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.open(Self.screenRecordingSettingsURL, configuration: configuration)
            } catch {
                settingsOpenFailed = true
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            loginError = localized("Could not change login settings. Try again in System Settings → General → Login Items.")
        }
    }
}
