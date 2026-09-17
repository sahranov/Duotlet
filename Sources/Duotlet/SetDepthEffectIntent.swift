import AppIntents
import AppKit

@available(macOS 26.0, *)
struct SetDepthEffectIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Depth effect"
    static let description = IntentDescription("Turn the Duotlet depth effect on or off.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Enabled") var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        // Persist before launching: a cold app reads the requested state.
        ControlState.setEnabled(value)
        let identifier = Bundle.main.object(forInfoDictionaryKey: "DuotletContainingApp") as? String
            ?? Bundle.main.bundleIdentifier!
        if NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.arguments = ["--background"]
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        return .result()
    }
}
