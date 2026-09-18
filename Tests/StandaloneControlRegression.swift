import Foundation

@main
struct StandaloneControlRegression {
    static func main() {
        guard let identifier = Bundle.main.bundleIdentifier,
              identifier.hasPrefix("app.duotlet.StandaloneRegression.") else {
            fatalError("Run through run-standalone-control-regression.sh")
        }
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: identifier)
        defer { defaults.removePersistentDomain(forName: identifier) }
        precondition(Bundle.main.object(forInfoDictionaryKey: "DuotletStandalone") as? Bool == true)
        precondition(ControlState.isEnabled)
        defaults.set(false, forKey: "isEnabled")
        precondition(!ControlState.isEnabled, "Standalone effect state must read standard preferences")
        defaults.set(true, forKey: "isEnabled")
        precondition(ControlState.isEnabled)
        ControlState.language = "ru"
        precondition(defaults.string(forKey: "settingsLanguage") == "ru")
        precondition(ControlState.language == "ru")
        print("PASS: experimental effect state and language work without an App Group")
    }
}
