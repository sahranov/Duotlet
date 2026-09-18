import Foundation
import TelemetryDeck

enum Analytics {
    private static let appID = "D21EC6ED-5A15-4FA5-A011-5BA7C73B608C"
    private static var isInitialized = false
    private static var configuration: TelemetryDeck.Config?
    private static var reportedFailures: Set<Failure> = []

    enum Failure: String {
        case captureStart = "Error.captureStart"
        case captureStopped = "Error.captureStopped"
        case captureFilter = "Error.captureFilter"
    }

    @MainActor
    static func updateConsent(preferences: Preferences) {
        configuration?.analyticsDisabled = !preferences.hasCompletedOnboarding || !preferences.sharesAnonymousAnalytics
    }

    @MainActor
    static func startIfAllowed(preferences: Preferences) {
        guard preferences.hasCompletedOnboarding, preferences.sharesAnonymousAnalytics else { return }
        initializeIfNeeded()
        updateConsent(preferences: preferences)
        TelemetryDeck.signal("App.launched")
    }

    @MainActor
    static func signal(_ name: String, preferences: Preferences) {
        guard preferences.hasCompletedOnboarding, preferences.sharesAnonymousAnalytics else { return }
        initializeIfNeeded()
        updateConsent(preferences: preferences)
        TelemetryDeck.signal(name)
    }

    /// Fixed categories only: never send error descriptions, window titles or pixels.
    /// Capture retries can be frequent, so report each category once per launch.
    @MainActor
    static func failure(_ failure: Failure) {
        let preferences = Preferences.shared
        guard preferences.hasCompletedOnboarding, preferences.sharesAnonymousAnalytics,
              reportedFailures.insert(failure).inserted else { return }
        signal(failure.rawValue, preferences: preferences)
    }

    private static func initializeIfNeeded() {
        guard !isInitialized else { return }
        let config = TelemetryDeck.Config(appID: appID)
        configuration = config
        TelemetryDeck.initialize(config: config)
        isInitialized = true
    }
}
