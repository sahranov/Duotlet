import Foundation
import TelemetryDeck

enum Analytics {
    private static let appID = "D21EC6ED-5A15-4FA5-A011-5BA7C73B608C"
    private static var isInitialized = false

    @MainActor
    static func startIfAllowed(preferences: Preferences) {
        guard preferences.sharesAnonymousAnalytics else { return }
        initializeIfNeeded()
        TelemetryDeck.signal("App.launched")
    }

    @MainActor
    static func signal(_ name: String, preferences: Preferences) {
        guard preferences.sharesAnonymousAnalytics else { return }
        initializeIfNeeded()
        TelemetryDeck.signal(name)
    }

    private static func initializeIfNeeded() {
        guard !isInitialized else { return }
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        isInitialized = true
    }
}
