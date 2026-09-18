import SwiftUI
import WidgetKit

@main
struct DuotletControls: WidgetBundle {
    var body: some Widget { DepthEffectControl() }
}

struct DepthEffectControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlState.kind, provider: EffectValueProvider()) { enabled in
            ControlWidgetToggle("Duotlet", isOn: enabled, action: SetDepthEffectIntent()) { isOn in
                Label(SettingsLanguage.selected.localized(isOn ? "On" : "Off"), image: "DuotletControlIcon")
                    .symbolRenderingMode(.hierarchical)
                    // Keep the fan still when the host changes the toggle state.
                    .symbolEffectsRemoved()
                    .contentTransition(.identity)
            }
        }
        .displayName("Duotlet")
        .description(LocalizedStringResource(stringLiteral: SettingsLanguage.selected.localized("Turn the depth effect on or off.")))
    }
}

struct EffectValueProvider: ControlValueProvider {
    var previewValue: Bool { true }
    func currentValue() async throws -> Bool { ControlState.isEnabled }
}
