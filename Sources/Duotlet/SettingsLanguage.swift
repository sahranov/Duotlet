import Foundation

enum SettingsLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"
    case chinese = "zh-Hans"

    /// English is the product default, independent of the macOS language.
    static var preferred: Self { .english }
    static var selected: Self { Self(rawValue: ControlState.language) ?? .english }

    private static var resources: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Duotlet_Duotlet.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    func localized(_ key: String) -> String {
        guard let path = Self.resources.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
