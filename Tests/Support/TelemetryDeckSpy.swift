// Network-free stand-in used only by run-onboarding-regression.sh.
public enum TelemetryDeck {
    public final class Config {
        public var analyticsDisabled = false
        public init(appID: String) {}
    }
    public private(set) static var configuration: Config?
    public private(set) static var signals: [String] = []
    public static func initialize(config: Config) { configuration = config }
    public static func signal(_ name: String) {
        guard configuration?.analyticsDisabled == false else { return }
        signals.append(name)
    }
}
