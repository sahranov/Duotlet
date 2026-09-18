import Foundation

/// Acquiring a drawable may block while WindowServer resumes. Keep that wait
/// off the animation/sensor thread and retain at most one ready surface.
final class DrawablePrefetch<Frame>: @unchecked Sendable {
    // An invalidated layer may still be blocked in nextDrawable. A new
    // generation must not queue behind it; generation checks reject its result.
    private let queue = DispatchQueue(label: "Duotlet.drawables", qos: .userInteractive, attributes: .concurrent)
    private let lock = NSLock()
    private var ready: Frame?
    private var pending = false
    private var generation: UInt64 = 0

    func request(_ produce: @escaping () -> Frame?) {
        lock.lock()
        guard !pending, ready == nil else { lock.unlock(); return }
        pending = true
        let generation = generation
        lock.unlock()
        queue.async { [self] in
            // Release autoreleased Metal objects after each acquisition, even
            // when display callbacks arrive without a run-loop drain.
            autoreleasepool {
                let frame = produce()
                lock.lock()
                defer { lock.unlock() }
                guard generation == self.generation else { return }
                pending = false
                ready = frame
            }
        }
    }

    func take() -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        let frame = ready
        ready = nil
        return frame
    }

    /// An old layer's completion must not enter a new window's drawable pool.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        ready = nil
        pending = false
    }
}
