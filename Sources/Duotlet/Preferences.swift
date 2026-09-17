import Combine
import Foundation

/// User settings, backed by `UserDefaults`.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let isEnabled = "isEnabled"
        static let isTimeoutEnabled = "isTimeoutEnabled"
        static let thresholdAngle = "thresholdAngle"
        static let blurSpan = "blurSpan"
        static let maxBlurRadius = "maxBlurRadius"
        static let maxDim = "maxDim"
        static let viewingDistance = "viewingDistance"
        static let recession = "recession"
        static let blurEvenness = "blurEvenness"
        static let dimReach = "dimReach"
        static let showsDockIcon = "showsDockIcon"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let showsAngleInMenuBar = "showsAngleInMenuBar"
        static let isLivePicture = "isLivePicture"
        static let sharesAnonymousAnalytics = "sharesAnonymousAnalytics"

        static let all = [
            isEnabled, isTimeoutEnabled, thresholdAngle, blurSpan, maxBlurRadius,
            maxDim, viewingDistance, recession, blurEvenness, dimReach,
            showsAngleInMenuBar, showsMenuBarIcon, showsDockIcon, isLivePicture,
            sharesAnonymousAnalytics,
        ]
    }

    private static let factory: [String: Any] = [
        Key.isEnabled: true,
        Key.isTimeoutEnabled: false,
        Key.thresholdAngle: 90.0,
        Key.blurSpan: 60.0,
        Key.showsAngleInMenuBar: false,
        Key.showsMenuBarIcon: true,
        Key.showsDockIcon: true,
        Key.sharesAnonymousAnalytics: true,
    ]

    /// Master switch for the depth effect.
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.isEnabled)
            if ControlState.isEnabled != isEnabled { ControlState.setEnabled(isEnabled) }
        }
    }

    /// Ends the effect early if the angle holds still while below the
    /// threshold, instead of waiting for the lid to open back past it.
    @Published var isTimeoutEnabled: Bool {
        didSet { defaults.set(isTimeoutEnabled, forKey: Key.isTimeoutEnabled) }
    }

    /// Closing past this angle starts the depth effect. Degrees.
    @Published var thresholdAngle: Double {
        didSet { defaults.set(thresholdAngle, forKey: Key.thresholdAngle) }
    }

    /// How many degrees below the threshold the blur takes to reach maximum.
    @Published var blurSpan: Double {
        didSet { defaults.set(blurSpan, forKey: Key.blurSpan) }
    }

    /// Gaussian blur radius at full effect, in points.
    let maxBlurRadius: Double = 69.0

    /// Black overlay opacity where the blur is at full strength, 0...1.
    let maxDim: Double = 0.2

    /// Distance from the eye to the middle of the screen, as a multiple of
    /// the screen height.
    let viewingDistance: Double = 6.0

    /// Degrees the picture turns away from the glass for each degree the lid
    /// closes. One holds the picture still in the room.
    let recession: Double = 0.5

    /// Blur at the hinge edge as a fraction of the blur at the far edge. One
    /// blurs the whole picture by the same amount.
    let blurEvenness: Double = 0.0

    /// Height at which the dimming reaches full strength, as a fraction of
    /// the screen height.
    let dimReach: Double = 0.4

    @Published var showsDockIcon: Bool {
        didSet { defaults.set(showsDockIcon, forKey: Key.showsDockIcon) }
    }

    @Published var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    /// Draw the live angle next to the menu bar icon.
    @Published var showsAngleInMenuBar: Bool {
        didSet { defaults.set(showsAngleInMenuBar, forKey: Key.showsAngleInMenuBar) }
    }

    /// Keep the picture under the effect updating, instead of holding the one
    /// frame that was on screen at the trigger angle.
    let isLivePicture = true

    /// Sends anonymous usage signals so active installs can be counted.
    @Published var sharesAnonymousAnalytics: Bool {
        didSet {
            defaults.set(sharesAnonymousAnalytics, forKey: Key.sharesAnonymousAnalytics)
            if sharesAnonymousAnalytics {
                Analytics.signal("Analytics.enabled", preferences: self)
            }
        }
    }

    /// Eye distance in screen heights, at the two ends of the perspective
    /// slider. The panel offers the strength, which runs the other way.
    static let farthestEye: Double = 6
    static let nearestEye: Double = 1
    static let eyeRange: Double = farthestEye - nearestEye

    /// Highest angle above the threshold at which the pre-warm may run.
    let prewarmCeiling: Double = 70

    /// Closing speed in degrees per second that starts the pre-warm.
    let closingSpeed: Double = 8

    /// How long the pre-warm runs after the lid stops moving.
    let prewarmLinger: TimeInterval = 2

    /// Seconds between pre-warm screenshots.
    let prewarmInterval: TimeInterval = 0.25

    /// Degrees above the threshold before the overlay is released.
    let hysteresis: Double = 4

    /// Settings from earlier versions, removed at launch.
    private static let retired = [
        "blurFrontWidth", "maxTilt", "tiltDegrees", "tiltRatio", "dimEvenness",
        Key.maxBlurRadius, Key.maxDim, Key.viewingDistance, Key.recession, Key.blurEvenness, Key.dimReach, Key.isLivePicture,
    ]

    private let defaults = UserDefaults.standard

    // No inline values on purpose. Swift skips property observers for the
    // assignment that initialises a property.
    private init() {
        let defaults = UserDefaults.standard
        // Keep existing users' preferences when moving to the public bundle ID.
        if Bundle.main.bundleIdentifier == "app.duotlet.Duotlet",
           !defaults.bool(forKey: "migratedLegacyPreferences") {
            for (key, value) in defaults.persistentDomain(forName: "to.maki.MacDuoPatched") ?? [:]
                where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            defaults.set(true, forKey: "migratedLegacyPreferences")
        }
        defaults.register(defaults: Self.factory)
        for key in Self.retired { defaults.removeObject(forKey: key) }
        ControlState.migrate(from: defaults)
        isEnabled = ControlState.isEnabled
        isTimeoutEnabled = defaults.bool(forKey: Key.isTimeoutEnabled)
        thresholdAngle = defaults.double(forKey: Key.thresholdAngle)
        blurSpan = defaults.double(forKey: Key.blurSpan)
        showsDockIcon = defaults.bool(forKey: Key.showsDockIcon)
        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        showsAngleInMenuBar = defaults.bool(forKey: Key.showsAngleInMenuBar)
        sharesAnonymousAnalytics = defaults.bool(forKey: Key.sharesAnonymousAnalytics)
    }

    func refreshControlState() {
        let enabled = ControlState.isEnabled
        if isEnabled != enabled { isEnabled = enabled }
    }

    func resetToDefaults() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        isTimeoutEnabled = defaults.bool(forKey: Key.isTimeoutEnabled)
        thresholdAngle = defaults.double(forKey: Key.thresholdAngle)
        blurSpan = defaults.double(forKey: Key.blurSpan)
        showsDockIcon = defaults.bool(forKey: Key.showsDockIcon)
        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        showsAngleInMenuBar = defaults.bool(forKey: Key.showsAngleInMenuBar)
        sharesAnonymousAnalytics = defaults.bool(forKey: Key.sharesAnonymousAnalytics)
    }
}
