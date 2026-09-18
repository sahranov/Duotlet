import Foundation
import WidgetKit

/// The app and its embedded control read and write the same App Group value.
/// Notifications carry no state: receivers always read the durable value.
enum ControlState {
    static let kind = "app.duotlet.depth-effect"
    static let changed = Notification.Name("app.duotlet.effect-changed")
    static let enabledKey = "isEnabled"
    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "DuotletAppGroup") as? String
            ?? "group.app.duotlet.shared"
    }
    /// Experimental distribution omits the extension and needs no App Group.
    private static var supportsControlCenter: Bool {
        Bundle.main.object(forInfoDictionaryKey: "DuotletStandalone") as? Bool != true
    }
    private static var defaults: UserDefaults {
        supportsControlCenter ? UserDefaults(suiteName: groupIdentifier)! : .standard
    }

    static var language: String {
        get { defaults.string(forKey: "settingsLanguage") ?? "en" }
        set {
            defaults.set(newValue, forKey: "settingsLanguage")
            defaults.synchronize()
            if supportsControlCenter, #available(macOS 26.0, *) { ControlCenter.shared.reloadControls(ofKind: kind) }
        }
    }

    static var isEnabled: Bool {
        defaults.synchronize()
        return defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func migrate(from legacy: UserDefaults) {
        guard defaults.object(forKey: enabledKey) == nil else { return }
        setEnabled(legacy.object(forKey: enabledKey) as? Bool ?? true)
    }

    static func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            changed, object: nil, userInfo: nil, deliverImmediately: true)
        if supportsControlCenter, #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: kind)
        }
    }
}
