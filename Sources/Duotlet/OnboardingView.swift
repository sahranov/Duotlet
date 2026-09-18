import AppKit
import SwiftUI

/// All entry points use the same window, including reopening from the Dock.
struct SetupOrSettingsView: View {
    @ObservedObject var preferences: Preferences
    let controller: LidController
    @ObservedObject var updater: AppUpdater

    var body: some View {
        if preferences.hasCompletedOnboarding {
            SettingsView(preferences: preferences, controller: controller, updater: updater)
        } else {
            OnboardingView(preferences: preferences)
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject private var permission = ScreenCapturePermission.shared
    @State private var step = 1
    @State private var language = ControlState.language
    @State private var sharingAnalytics: Bool
    @State private var settingsOpenFailed = false
    @State private var requestedAccess = false

    init(preferences: Preferences) {
        self.preferences = preferences
        _sharingAnalytics = State(initialValue: preferences.sharesAnonymousAnalytics)
    }

    private func localized(_ key: String) -> String {
        (SettingsLanguage(rawValue: language) ?? .english).localized(key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Duotlet").font(.headline)
                Spacer()
                Picker(localized("Language"), selection: $language) {
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Русский").tag("ru")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                }
                .labelsHidden()
                .frame(width: 120)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    if step == 1 { screenAccess } else { analytics }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if step == 2 {
                    Button(localized("Back")) { step = 1 }
                }
                Spacer()
                Button(localized("Next")) { advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permission.hasAccess)
            }
        }
        .padding(32)
        .frame(width: 500, height: 580)
        .onAppear { permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
        .onChange(of: permission.hasAccess) { _, granted in
            if !granted { step = 1 }
        }
        .onChange(of: language) { _, value in
            ControlState.language = value
            NotificationCenter.default.post(name: .init("DuotletLanguageChanged"), object: nil)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: step == 1 ? "display" : "heart.text.clipboard")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(localized(step == 1 ? "Step 1 of 2" : "Step 2 of 2"))
                .font(.subheadline).foregroundStyle(.secondary)
            Text(localized(step == 1 ? "Allow screen access" : "Help improve Duotlet"))
                .font(.system(size: 26, weight: .semibold))
            Text(localized(step == 1
                ? "Duotlet uses your screen image to create the depth effect when you close the lid. Without this access, the effect cannot work."
                : "Anonymous analytics helps find and fix bugs in Duotlet."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var screenAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Your screen image stays on your Mac. It is never sent anywhere."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if permission.hasAccess {
                Label(localized("Screen access allowed"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(localized("In System Settings, enable Duotlet under Screen Recording, then return here. If macOS asks you to restart Duotlet, reopen it to continue."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(localized(requestedAccess ? "Open System Settings" : "Allow Screen Recording")) {
                    requestedAccess = true
                    if !permission.requestAccess() { openScreenSettings() }
                }
                .disabled(permission.isRequesting)
            }
            if settingsOpenFailed {
                Text(localized("Could not open System Settings. Open it manually and enable screen recording for Duotlet under Privacy & Security."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var analytics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(localized("Share anonymous analytics"), isOn: $sharingAnalytics)
                .toggleStyle(.switch)
            Text(localized("Sends app launches and technical failure types to help fix bugs. No screen content is sent. You can turn this off at any time."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func advance() {
        permission.refresh()
        guard permission.hasAccess else { step = 1; return }
        if step == 1 {
            step = 2
        } else {
            preferences.completeOnboarding(sharingAnalytics: sharingAnalytics)
        }
    }

    private func openScreenSettings() {
        settingsOpenFailed = false
        Task { @MainActor in
            do {
                let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            } catch {
                settingsOpenFailed = true
            }
        }
    }
}
