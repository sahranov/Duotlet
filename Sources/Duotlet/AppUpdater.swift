import AppKit
import Combine

@MainActor
final class AppUpdater: NSObject, ObservableObject, NSMenuItemValidation {
    @Published private(set) var isChecking = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var availableVersion: String?
    @Published private(set) var isPresentingUpdate = false
    @Published private(set) var statusKey: String?
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            defaults.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates")
            if automaticallyChecksForUpdates { checkAutomaticallyIfDue() }
        }
    }

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    var canCheckForUpdates: Bool { !isChecking && !isPresentingUpdate }

    private let defaults: UserDefaults
    private let checker = GitHubUpdateChecker()
    private var timer: Timer?
    private var lastAttempt: Date?

    override init() {
        defaults = .standard
        automaticallyChecksForUpdates = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
        lastUpdateCheckDate = defaults.object(forKey: "lastUpdateCheckDate") as? Date
        super.init()
    }

    func start() {
        guard timer == nil else { return }
        checkAutomaticallyIfDue()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAutomaticallyIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    @objc func checkForUpdates(_ sender: Any? = nil) { check(userInitiated: true) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }

    private func checkAutomaticallyIfDue() {
        guard automaticallyChecksForUpdates,
              Date().timeIntervalSince(lastUpdateCheckDate ?? .distantPast) >= 86400,
              Date().timeIntervalSince(lastAttempt ?? .distantPast) >= 3600 else { return }
        check(userInitiated: false)
    }

    private func check(userInitiated: Bool) {
        guard canCheckForUpdates else { return }
        isChecking = true
        statusKey = nil
        lastAttempt = Date()
        Task {
            defer { isChecking = false }
            do {
                let result = try await checker.check(currentVersion: version)
                let checked = Date()
                lastUpdateCheckDate = checked
                defaults.set(checked, forKey: "lastUpdateCheckDate")
                // Disabling automatic checks also suppresses a request already in flight.
                let shouldPresent = userInitiated || automaticallyChecksForUpdates
                switch result {
                case .available(let release):
                    availableVersion = release.version.description
                    statusKey = "An update is available."
                    if shouldPresent && (userInitiated || defaults.string(forKey: "skippedUpdateVersion") != release.version.description) {
                        showUpdate(release)
                    }
                case .upToDate:
                    availableVersion = nil
                    statusKey = "You have the latest version."
                    if userInitiated { showMessage("You have the latest version.") }
                case .noRelease:
                    availableVersion = nil
                    statusKey = "No updates have been published yet."
                    if userInitiated { showMessage("No updates have been published yet.") }
                }
            } catch {
                let key = (error as? UpdateCheckError)?.messageKey
                    ?? "Could not connect to GitHub. Check your internet connection and try again."
                statusKey = key
                if userInitiated { showMessage("Could not check for updates.", detail: key) }
            }
        }
    }

    private func showUpdate(_ release: AppRelease) {
        let language = SettingsLanguage.selected
        let alert = NSAlert()
        alert.messageText = String(format: language.localized("Duotlet %@ is available"), release.version.description)
        alert.informativeText = String(format: language.localized("You have version %@. Download the new version, quit Duotlet, and replace it in Applications."), version)
        alert.addButton(withTitle: language.localized("Download"))
        alert.addButton(withTitle: language.localized("Later"))
        alert.addButton(withTitle: language.localized("Skip this version"))
        let response = present(alert)
        if response == .alertFirstButtonReturn {
            if !NSWorkspace.shared.open(release.downloadURL) {
                showMessage("Could not open the download.", detail: "Open github.com/sahranov/Duotlet/releases in your browser.")
            }
        } else if response == .alertThirdButtonReturn {
            defaults.set(release.version.description, forKey: "skippedUpdateVersion")
        }
    }

    private func showMessage(_ title: String, detail: String? = nil) {
        let language = SettingsLanguage.selected
        let alert = NSAlert()
        alert.messageText = language.localized(title)
        alert.informativeText = detail.map(language.localized) ?? "Duotlet \(version)"
        alert.addButton(withTitle: language.localized("Close"))
        _ = present(alert)
    }

    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        isPresentingUpdate = true
        defer { isPresentingUpdate = false }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
