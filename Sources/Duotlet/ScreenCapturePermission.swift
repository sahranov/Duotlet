import Combine
import CoreGraphics

/// Permission is separate from the user's effect preference. Checking never prompts.
@MainActor
final class ScreenCapturePermission: ObservableObject {
    static let shared = ScreenCapturePermission()

    @Published private(set) var hasAccess: Bool
    @Published private(set) var isRequesting = false
    private let preflight: () -> Bool
    private let request: () -> Bool

    init(preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         request: @escaping () -> Bool = { CGRequestScreenCaptureAccess() }) {
        self.preflight = preflight
        self.request = request
        hasAccess = preflight()
    }

    func refresh() {
        let granted = preflight()
        if hasAccess != granted { hasAccess = granted }
    }

    /// Called only by the explicit Allow Screen Recording button, never by capture
    /// retries, login launches, or a permission observer.
    @discardableResult
    func requestAccess() -> Bool {
        refresh()
        guard !hasAccess, !isRequesting else { return hasAccess }
        isRequesting = true
        defer { isRequesting = false }
        _ = request()
        refresh()
        return hasAccess
    }
}
