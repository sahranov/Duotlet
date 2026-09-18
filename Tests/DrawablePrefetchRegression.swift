import Foundation

@main struct DrawablePrefetchRegression {
    static func main() {
        let source = DrawablePrefetch<Int>()
        let unblock = DispatchSemaphore(value: 0)
        let started = ProcessInfo.processInfo.systemUptime
        source.request {
            // Match the measured 153 ms nextDrawable wait at physical wake.
            _ = unblock.wait(timeout: .now() + 0.153)
            return 1
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        guard elapsed < 0.025 else {
            print("FAIL: wake drawable request stalled animation/sensor thread for \(Int(elapsed * 1000)) ms")
            exit(1)
        }
        unblock.signal()
        let limit = Date(timeIntervalSinceNow: 2)
        var frame: Int?
        while frame == nil && Date() < limit {
            frame = source.take()
            Thread.sleep(forTimeInterval: 0.001)
        }
        guard frame == 1, source.take() == nil else { fatalError("frame missing or replayed") }
        let blocked = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        source.request { entered.signal(); blocked.wait(); return 2 }
        guard entered.wait(timeout: .now() + 1) == .success else { fatalError("request missing") }
        for _ in 0..<100 {
            source.request { fatalError("unbounded requests accumulated while drawable unavailable") }
        }
        source.invalidate()
        source.request { 3 }
        frame = nil
        let nextLimit = Date(timeIntervalSinceNow: 2)
        while frame == nil && Date() < nextLimit {
            frame = source.take()
            Thread.sleep(forTimeInterval: 0.001)
        }
        blocked.signal()
        guard frame == 3 else { fatalError("old blocked layer prevented a new window from drawing") }
        // A temporarily unavailable display (nil drawable) remains retryable.
        let emptyDone = DispatchSemaphore(value: 0)
        source.request { emptyDone.signal(); return nil }
        _ = emptyDone.wait(timeout: .now() + 1)
        let retryLimit = Date(timeIntervalSinceNow: 2)
        frame = nil
        while frame == nil && Date() < retryLimit {
            source.request { 4 }
            frame = source.take()
            Thread.sleep(forTimeInterval: 0.001)
        }
        guard frame == 4 else { fatalError("nil drawable permanently stalled the renderer") }
        print("PASS: a 153 ms drawable wait does not block animation or sensor processing")
    }
}
