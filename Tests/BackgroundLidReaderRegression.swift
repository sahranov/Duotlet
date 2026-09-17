import Foundation

@main struct BackgroundLidReaderRegression {
    static func main() {
        let unblock = DispatchSemaphore(value: 0)
        var readOnMain = true
        var completedOnMain = false
        var received: Double?
        let reader = BackgroundLidReader {
            readOnMain = Thread.isMainThread
            _ = unblock.wait(timeout: .now() + 0.3)
            return 42
        }
        let start = ProcessInfo.processInfo.systemUptime
        reader.sample { value in
            completedOnMain = Thread.isMainThread
            received = value
        }
        let dispatchTime = ProcessInfo.processInfo.systemUptime - start
        // A slow hardware request cannot delay this main-thread work.
        unblock.signal()
        let deadline = Date(timeIntervalSinceNow: 2)
        while received == nil, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        let passed = dispatchTime < 0.05 && !readOnMain && completedOnMain && received == 42
        print(passed ? "PASS: hardware read does not block main; result returns on main" : "FAIL: blocked or misplaced hardware callback")
        if !passed { exit(1) }
    }
}
