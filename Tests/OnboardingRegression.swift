import Foundation
import TelemetryDeck

// Keep tests away from the installed app's shared defaults and native control.
enum ControlState {
    static var isEnabled = true
    static func setEnabled(_ enabled: Bool) { isEnabled = enabled }
    static func migrate(from defaults: UserDefaults) {}
}

@main
struct OnboardingRegression {
    @MainActor static func main() {
        let suite = "Duotlet.OnboardingRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        var granted = false
        var requests = 0
        let permission = ScreenCapturePermission(preflight: { granted }, request: {
            requests += 1
            return granted
        })

        precondition(!preferences.hasCompletedOnboarding)
        precondition(preferences.sharesAnonymousAnalytics, "New installs default to on")
        Analytics.startIfAllowed(preferences: preferences)
        Analytics.signal("Test.beforeSetup", preferences: preferences)
        preferences.sharesAnonymousAnalytics = false
        preferences.sharesAnonymousAnalytics = true
        precondition(TelemetryDeck.configuration == nil, "No SDK initialization before setup")

        preferences.completeOnboarding(sharingAnalytics: false, permission: permission)
        precondition(!preferences.hasCompletedOnboarding, "Permission is mandatory")
        granted = true
        permission.refresh()
        granted = false
        preferences.completeOnboarding(sharingAnalytics: true, permission: permission)
        precondition(!preferences.hasCompletedOnboarding, "Completion must detect revoked access")

        granted = true
        preferences.completeOnboarding(sharingAnalytics: false, permission: permission)
        precondition(preferences.hasCompletedOnboarding)
        precondition(!preferences.sharesAnonymousAnalytics)
        Analytics.startIfAllowed(preferences: preferences)
        Analytics.signal("Test.optedOut", preferences: preferences)
        precondition(TelemetryDeck.configuration == nil, "Opt-out never initializes analytics")
        precondition(requests == 0, "Setup checks must never trigger a permission prompt")

        let reopened = Preferences(defaults: defaults)
        precondition(reopened.hasCompletedOnboarding, "Do not repeat setup on relaunch")
        precondition(!reopened.sharesAnonymousAnalytics, "Persist the opt-out")
        reopened.sharesAnonymousAnalytics = true
        precondition(TelemetryDeck.signals == ["Analytics.enabled"])
        reopened.sharesAnonymousAnalytics = false
        precondition(TelemetryDeck.configuration?.analyticsDisabled == true)
        Analytics.signal("Test.disabled", preferences: reopened)
        precondition(TelemetryDeck.signals == ["Analytics.enabled"])
        reopened.resetToDefaults()
        precondition(reopened.hasCompletedOnboarding, "Settings reset must not repeat setup")

        defaults.removePersistentDomain(forName: suite)
        let optedIn = Preferences(defaults: defaults)
        optedIn.completeOnboarding(sharingAnalytics: true, permission: permission)
        precondition(optedIn.hasCompletedOnboarding && optedIn.sharesAnonymousAnalytics)
        precondition(TelemetryDeck.signals.last == "App.launched")
        print("PASS: mandatory permission, revocation, persisted setup and opt-out, analytics gate, no automatic prompts")
    }
}
