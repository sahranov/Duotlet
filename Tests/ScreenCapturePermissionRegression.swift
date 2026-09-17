import Foundation

@main
struct ScreenCapturePermissionRegression {
    @MainActor static func main() {
        var allowed = false
        var requestCount = 0
        var grantOnRequest = false
        let permission = ScreenCapturePermission(preflight: { allowed }, request: {
            requestCount += 1
            allowed = grantOnRequest
            return allowed
        })
        precondition(!permission.hasAccess)
        for _ in 0..<100 { permission.refresh() }
        precondition(requestCount == 0, "Background checks must never ask for access")
        precondition(!permission.requestAccess(), "A denied request must not look granted")
        precondition(requestCount == 1 && !permission.isRequesting)
        grantOnRequest = true
        precondition(permission.requestAccess())
        precondition(permission.hasAccess && requestCount == 2)
        precondition(permission.requestAccess())
        precondition(requestCount == 2, "Already authorized apps must not prompt again")
        allowed = false
        permission.refresh()
        precondition(!permission.hasAccess, "Revoked access must not retain an enabled status")
        allowed = true
        permission.refresh()
        precondition(permission.hasAccess, "Returning from System Settings must refresh access")
        precondition(requestCount == 2)
        print("PASS: permission refresh, grant, denial and revocation; no background prompts")
    }
}
