import Foundation

/// Opt-in measurements of actual GPU work and presentation, not timer callbacks.
/// Launch with --profile-animation; ordinary launches allocate no sample arrays.
final class AnimationProfile: @unchecked Sendable {
    static let enabled = CommandLine.arguments.contains("--profile-animation")
    private let lock = NSLock()
    private var presentations: [Double] = []
    private var gpuTimes: [Double] = []

    func presented(at time: Double) {
        guard time > 0 else { return }
        lock.lock()
        if presentations.count < 4096 { presentations.append(time) }
        lock.unlock()
    }

    func completed(in seconds: Double) {
        lock.lock()
        if gpuTimes.count < 4096 { gpuTimes.append(seconds * 1000) }
        lock.unlock()
    }

    func reportAfterCompletion() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
            lock.lock()
            let times = presentations.sorted()
            let gpu = gpuTimes.sorted()
            lock.unlock()
            guard times.count > 4, !gpu.isEmpty else { return }
            let intervals = zip(times.dropFirst(3), times.dropFirst(2))
                .map { ($0 - $1) * 1000 }.sorted()
            let p95 = intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))]
            let gpu95 = gpu[min(gpu.count - 1, Int(Double(gpu.count) * 0.95))]
            let releaseStart = times.last! - EffectRelease.duration
            let releaseIntervals = zip(times.dropFirst(), times)
                .filter { $0.0 >= releaseStart && $0.1 >= releaseStart }
                .map { ($0.0 - $0.1) * 1000 }.sorted()
            let release95 = releaseIntervals.isEmpty ? 0
                : releaseIntervals[min(releaseIntervals.count - 1, Int(Double(releaseIntervals.count) * 0.95))]
            let summary = String(format:
                "profile: %d frames; presentation median %.2f ms, p95 %.2f ms, max %.2f ms, gaps>25ms %d; GPU p95 %.2f ms; release p95 %.2f ms, gaps>25ms %d; submitted %d",
                times.count, intervals[intervals.count / 2], p95, intervals.last!,
                intervals.filter { $0 > 25 }.count, gpu95, release95,
                releaseIntervals.filter { $0 > 25 }.count, gpu.count)
            Diagnostics.geometry.notice("\(summary, privacy: .public)")
        }
    }
}
