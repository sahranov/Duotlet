import Foundation

@main struct WakeEffectRegression {
    static func main() {
        var failures = 0
        func check(_ pass: Bool, _ message: String) {
            if !pass { failures += 1; print("FAIL: \(message)") }
        }
        var state = WakeEffectRestoration()
        state.remember(angle: 8, startAngle: 80, blur: 0.9, closing: true, enabled: true)
        // Sleep and display-disconnect notifications may both arrive. The
        // second must not erase the first saved effect after renderer cleanup.
        state.remember(angle: 0, startAngle: 90, blur: 0, closing: false, enabled: true)
        for _ in 0..<60 {
            check(state.take(screenReady: false, enabled: true) == nil, "wait for display after wake")
            check(state.pending != nil, "sleep effect was discarded before display returned")
        }
        let saved = state.take(screenReady: true, enabled: true)
        check(saved?.startAngle == 80 && saved?.angle == 8 && saved?.blur == 1, "restore original closing run")
        check(state.take(screenReady: true, enabled: true) == nil, "wake should restore only once")
        state.remember(angle: 90, startAngle: 90, blur: 0, closing: false, enabled: true)
        check(state.pending == nil, "ordinary sleep with open lid must stay clear")
        state.remember(angle: 0, startAngle: 80, blur: 1, closing: true, enabled: true)
        check(state.take(screenReady: true, enabled: false) == nil && state.pending == nil,
              "disabled effect must cancel pending wake")
        print(failures == 0 ? "PASS: closed-lid effect survives sleep, waits for screen and restores once" : "FAIL: \(failures) wake checks")
        if failures > 0 { exit(1) }
    }
}
