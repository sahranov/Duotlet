import AppKit
import Combine
#if SWIFT_PACKAGE
import LidAngleKit
#endif
import QuartzCore

/// Watches the lid angle and drives the depth effect overlay.
///
/// A timer polls the sensor, and a display link advances a spring at the
/// screen refresh rate so the ramp stays smooth between readings.

/// Identity of the built-in display. `NSApplication` posts a screen change for
/// a backlight change too, and this tells the two apart.
struct Layout: Equatable {
    var displayID: CGDirectDisplayID?
    var frame: CGRect?
}

@MainActor
final class LidController: ObservableObject {

    @Published private(set) var currentAngle: Double = 0
    @Published private(set) var isSensorAvailable = false
    @Published private(set) var isActive = false

    let snapshotter = ScreenSnapshotter()

    private let preferences: Preferences
    private let sensor = LidAngleSensor()
    private lazy var sensorReader = BackgroundLidReader { [sensor] in sensor.angle() }
    private var sensorReadPending = false
    private let overlay = DepthOverlay()
    private let streamer = ScreenStreamer()

    private var enabledSubscription: AnyCancellable?
    private var pictureTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var lastPublishTime: CFTimeInterval = 0

    private var rawAngle: Double = 0
    /// Degrees per second, negative while the lid closes.
    private var angularVelocity: Double = 0
    private var lastChangedAngle: Double?
    private var lastChangeTime: CFTimeInterval = 0
    private var lastClosingTime: CFTimeInterval = -.greatestFiniteMagnitude
    private var visualAngle = CriticallyDampedSpring()
    private var consecutiveFailedReads = 0
    private var startedAt: CFTimeInterval = 0
    private var preview: PreviewRun?
    private var isSuspended = false
    private var wakeRestoration = WakeEffectRestoration()
    private var isAwaitingWakePicture = false
    private var isCapturePending = false
    private var motionPolicy = AdaptiveLidPolicy()
    /// Frozen for a run, including its ease back to the unmodified screen.
    private var effectStartAngle: Double = 90
    private var releaseAngle: Double = 90
    private var blurEnvelope = BlurEnvelope()
    private var releaseBlur = 0.0
    /// True while `beginClosingOut()` is easing the picture back to flat.
    private var isClosingOut = false
    private var closingOutStartedAt: CFTimeInterval = 0
    private var builtInLayout = Layout()

    private static let idlePollInterval: TimeInterval = 1.0 / 8
    private static let activePollInterval: TimeInterval = 1.0 / 30
    private static let fadeInDuration: TimeInterval = 0.07
    private static let triggerOpeningSpeed: Double = 2

    private static let predictionSpeedFloor: Double = 40

    /// Sensor latency the prediction adds on top of the reading's own age.
    private static let predictionLatency: TimeInterval = 0.04

    /// A scripted angle sweep, so the settings panel can show the effect
    /// without the lid moving. It feeds the same path the sensor feeds.
    private struct PreviewRun {
        let startedAt: CFTimeInterval
        let open: Double
        let shut: Double
        var scenario = "full"
        let closing: CFTimeInterval = 1.4
        let hold: CFTimeInterval = 0.8
        let opening: CFTimeInterval = 0.6

        /// `nil` once the run is over.
        func angle(at now: CFTimeInterval) -> Double? {
            let elapsed = now - startedAt
            if scenario == "reversals" || scenario == "shallow" {
                let points: [(Double, Double)] = scenario == "shallow"
                    ? [(0, open), (0.6, open - 28), (0.7, open - 28), (1.2, open)]
                    : [(0, open), (0.7, 42), (0.9, 42), (1.1, 48),
                       (1.3, 38), (1.5, 45), (1.7, 32), (2.0, 40), (2.7, open)]
                for (a, b) in zip(points, points.dropFirst()) where elapsed < b.0 {
                    return a.1 + (b.1 - a.1) * max((elapsed - a.0) / (b.0 - a.0), 0)
                }
                return nil
            }
            if elapsed < closing { return open + (shut - open) * (elapsed / closing) }
            if elapsed < closing + hold { return shut }
            if elapsed < closing + hold + opening {
                return shut + (open - shut) * ((elapsed - closing - hold) / opening)
            }
            return nil
        }
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        enabledSubscription = preferences.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard !enabled else { return }
                self?.disableEffect()
            }
    }

    // MARK: - Lifecycle

    func start() {
        isSensorAvailable = sensor.isAvailable
        guard isSensorAvailable else { return }

        if let angle = sensor.angle() {
            rawAngle = angle
            currentAngle = angle
            visualAngle.reset(to: angle)
        }
        // Before the first poll, which reads it.
        builtInLayout = Layout(displayID: NSScreen.builtIn?.displayID, frame: NSScreen.builtIn?.frame)
        setPollInterval(Self.idlePollInterval)
        observeSystemEvents()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("to.maki.Duotlet.preview"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.runPreview() }
        }
        if AnimationProfile.enabled {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("to.maki.Duotlet.profileScenario"),
                object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let scenario = notification.object as? String else { return }
                    self.runPreview()
                    if scenario == "wake" {
                        // Exercise the actual sleep/wake handlers and fresh
                        // capture without putting the user's Mac to sleep.
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 1_900_000_000)
                            guard let self, self.preview != nil else { return }
                            self.suspend()
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            self.resume()
                        }
                    } else {
                        self.preview?.scenario = scenario
                    }
                }
            }
        }
        overlay.warmUp()
        Task {
            await snapshotter.warmFilter()
            // After the overlay has put its presence window up, so the filter
            // can name this app and leave the overlay out of the picture.
            try? await Task.sleep(nanoseconds: 500_000_000)
            await streamer.warmFilter()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollInterval = 0
        stopEffectAndCapture()
    }

    private func stopEffectAndCapture(preserveWakeEffect: Bool = false) {
        if !preserveWakeEffect { wakeRestoration.clear() }
        isAwaitingWakePicture = false
        blurEnvelope.reset()
        motionPolicy.reset()
        pictureTask?.cancel()
        pictureTask = nil
        isCapturePending = false
        isClosingOut = false
        stopDisplayLink()
        overlay.dismiss(animated: false)
        snapshotter.stop()
        streamer.stop()
        overlay.discardLive()
        preview = nil
        isActive = false
    }

    private func disableEffect() {
        stopEffectAndCapture()
        lastChangedAngle = nil
        angularVelocity = 0
        lastClosingTime = -.greatestFiniteMagnitude
        motionPolicy.reset()
        if pollTimer != nil { setPollInterval(Self.idlePollInterval) }
    }

    /// Plays the effect once on the current screen contents.
    func runPreview() {
        guard preferences.isEnabled, !isSuspended, preview == nil, !isActive else { return }
        motionPolicy.reset()
        preview = PreviewRun(
            startedAt: CACurrentMediaTime(),
            open: max(rawAngle, 60),
            shut: 20
        )
        setPollInterval(Self.activePollInterval)
    }

    // MARK: - Polling

    private func setPollInterval(_ interval: TimeInterval) {
        guard pollInterval != interval else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard !isSuspended else { return }

        if let run = preview {
            guard let scripted = run.angle(at: CACurrentMediaTime()) else {
                preview = nil
                motionPolicy.reset()
                if isActive { setActive(false) }
                return
            }
            consume(angle: scripted)
        } else {
            guard !sensorReadPending else { return }
            sensorReadPending = true
            sensorReader.sample { [weak self] read in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sensorReadPending = false
                    guard !self.isSuspended, self.pollTimer != nil, self.preview == nil else { return }
                    self.consumeSensor(read)
                }
            }
        }
    }

    private func consumeSensor(_ read: Double?) {
        guard let read else {
            consecutiveFailedReads += 1
            if consecutiveFailedReads > 30, isActive {
                Diagnostics.lid.notice(
                    """
                    release: sensor read failed \(self.consecutiveFailedReads) times in a row, \
                    last angle \(self.rawAngle, format: .fixed(precision: 2))
                    """
                )
                setActive(false)
            }
            return
        }
        if consecutiveFailedReads > 0 {
            Diagnostics.lid.notice(
                "sensor recovered after \(self.consecutiveFailedReads) failed reads, angle \(read, format: .fixed(precision: 2))"
            )
        }
        consecutiveFailedReads = 0
        if lastChangedAngle == nil { visualAngle.reset(to: read) }
        consume(angle: read)
    }

    private func consume(angle: Double) {
        rawAngle = angle
        publish(angle: angle)

        if preferences.isEnabled {
            updateVelocity(with: angle)
            reconcile(angle: angle)
        }

        setPollInterval(preferences.isEnabled ? Self.activePollInterval : Self.idlePollInterval)
    }

    private func wantsEffect(angle: Double) -> Bool {
        guard preferences.isEnabled, builtInLayout.displayID != nil else { return false }
        return motionPolicy.update(angle: angle, at: CACurrentMediaTime())
    }

    /// Brings the screen in line with `wantsEffect` on every sample. A run
    /// whose screenshot failed is retried here.
    private func reconcile(angle: Double) {
        guard preferences.isEnabled, !isSuspended else { return }
        if isAwaitingWakePicture {
            if preferences.isLivePicture { streamer.start() }
            if !isCapturePending {
                if !overlay.isVisible { presentPicture() }
                else if preferences.isLivePicture, !overlay.isPictureReady { requestSeed() }
            }
            return
        }
        if wakeRestoration.pending != nil {
            guard let restored = wakeRestoration.take(
                screenReady: NSScreen.builtIn != nil && snapshotter.hasPermission,
                enabled: preferences.isEnabled) else { return }
            effectStartAngle = restored.startAngle
            visualAngle.reset(to: restored.angle)
            blurEnvelope.restore(restored.blur)
            isActive = true
            isAwaitingWakePicture = true
            if preferences.isLivePicture { streamer.start() }
            presentPicture()
            return
        }
        let wanted = wantsEffect(angle: angle)
        if isClosingOut {
            if wanted {
                effectStartAngle = motionPolicy.startAngle
                setActive(true)
            }
            return
        }
        if wanted != isActive {
            Diagnostics.lid.notice(
                """
                \(wanted ? "start" : "end", privacy: .public) raw \(angle, format: .fixed(precision: 2)) \
                predicted \(self.predictedAngle(), format: .fixed(precision: 2)) \
                velocity \(self.angularVelocity, format: .fixed(precision: 1)) deg/s \
                snapshot \(self.snapshotter.latestImage != nil)
                """
            )
            setActive(wanted)
            return
        }
        if isActive {
            if preferences.isLivePicture { streamer.start() }
            if !overlay.isVisible, !isCapturePending { presentPicture() }
            // A visible overlay with no link would sit at its first frame.
            if overlay.isVisible, displayLink == nil { startDisplayLink() }
        } else if !isClosingOut {
            // The ease back to flat still draws the live picture, and this
            // would free it.
            updatePrewarm(angle: angle, ceiling: 180)
        }
    }

    private func updateVelocity(with angle: Double) {
        let now = CACurrentMediaTime()
        guard let last = lastChangedAngle else {
            lastChangedAngle = angle
            lastChangeTime = now
            return
        }
        if angle != last {
            let dt = now - lastChangeTime
            if dt > 0.001 {
                let instant = (angle - last) / dt
                angularVelocity = 0.5 * instant + 0.5 * angularVelocity
            }
            lastChangedAngle = angle
            lastChangeTime = now
        } else if now - lastChangeTime > 0.4 {
            angularVelocity = 0
        }
        if angularVelocity >= Self.triggerOpeningSpeed {
            lastClosingTime = -.greatestFiniteMagnitude
        } else if angularVelocity <= -preferences.closingSpeed {
            lastClosingTime = now
        }
    }

    /// Runs only while the lid is closing, so holding it still does not leave
    /// a capture loop running.
    private func updatePrewarm(angle: Double, ceiling: Double) {
        let closingRecently = CACurrentMediaTime() - lastClosingTime < preferences.prewarmLinger
        guard angle <= ceiling, closingRecently else {
            snapshotter.endPrewarm()
            streamer.stop()
            overlay.discardLive()
            return
        }
        guard preferences.isLivePicture else {
            streamer.stop()
            overlay.discardLive()
            snapshotter.beginPrewarm(interval: preferences.prewarmInterval)
            return
        }
        // Only the stream. Asking ScreenCaptureKit for a screenshot at the
        // same time makes it serve neither quickly.
        snapshotter.endPrewarm()
        streamer.start()
    }

    /// A reading can be a full sensor refresh old, so a fast close works from
    /// where the lid is heading rather than the last reading.
    private func predictedAngle() -> Double {
        guard angularVelocity < -Self.predictionSpeedFloor else { return rawAngle }
        let staleness = min(CACurrentMediaTime() - lastChangeTime, 0.12)
        return rawAngle + angularVelocity * (staleness + Self.predictionLatency)
    }

    private func publish(angle: Double) {
        let now = CACurrentMediaTime()
        guard now - lastPublishTime > 0.08 else { return }
        lastPublishTime = now
        if abs(currentAngle - angle) > 0.001 { currentAngle = angle }
    }

    // MARK: - Depth effect

    private func setActive(_ active: Bool) {
        isActive = active
        if active {
            if isClosingOut {
                isClosingOut = false
                return
            }
            effectStartAngle = motionPolicy.startAngle
            isClosingOut = false
            startedAt = CACurrentMediaTime()
            // A reversal continues the existing picture and its motion.
            // Rebuilding here briefly hid the window and restarted the taper.
            if overlay.isVisible {
                if displayLink == nil { startDisplayLink() }
                return
            }
            visualAngle.reset(to: effectStartAngle)
            snapshotter.endPrewarm()
            setPollInterval(Self.activePollInterval)
            presentPicture()
        } else {
            snapshotter.discard()
            beginClosingOut()
        }
    }

    /// Eases the picture back to flat before the overlay fades away. Ending
    /// the effect with the lid still shut would otherwise fade out a warped
    /// picture. `step(_:)` drives the ease and calls `finishClosingOut()`.
    private func beginClosingOut() {
        // Nothing to ease before the picture is up, or with no link to draw it.
        guard overlay.isVisible, displayLink != nil else {
            stopDisplayLink()
            overlay.dismiss(animated: true)
            return
        }
        isClosingOut = true
        overlay.beginRelease()
        releaseBlur = blurEnvelope.value
        releaseAngle = visualAngle.value
        closingOutStartedAt = CACurrentMediaTime()
    }

    private func finishClosingOut() {
        isClosingOut = false
        blurEnvelope.reset()
        stopDisplayLink()
        // The display link has already drawn the zero-opacity final frame.
        overlay.dismiss(animated: false)
        streamer.stop()
        overlay.discardLive()
    }

    private func endEffect() {
        setActive(false)
    }

    /// Shows the held screenshot, or waits for one. A pre-warm capture that is
    /// already running counts as that wait.
    private func presentPicture() {
        guard preferences.isEnabled, !isSuspended, isActive else { return }
        if preferences.isLivePicture, let screen = NSScreen.builtIn,
           overlay.showLive(
               on: screen,
               startAngle: effectStartAngle,
               tuning: tuning,
               fadeIn: Self.fadeInDuration
           ) {
            startDisplayLink()
            if let frame = streamer.newFrame() {
                Diagnostics.lid.notice("present: live, a stream frame was ready")
                overlay.absorb(frame)
                return
            }
            // A fast close can reach the trigger angle before the stream has a
            // frame. One screenshot starts the picture off.
            if let image = snapshotter.latestImage {
                Diagnostics.lid.notice("present: live, seeding from the pre-warm screenshot")
                overlay.seed(image: image)
                return
            }
            Diagnostics.lid.notice("present: live, no picture yet, asking for a screenshot")
            requestSeed()
            return
        }

        if let image = snapshotter.latestImage, let screen = snapshotter.latestScreen {
            show(image: image, on: screen)
            return
        }
        isCapturePending = true
        pictureTask?.cancel()
        pictureTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.snapshotter.captureOnce()
            guard !Task.isCancelled else { return }
            self.pictureTask = nil
            self.isCapturePending = false
            Diagnostics.lid.notice(
                """
                capture landed: image \(self.snapshotter.latestImage != nil) \
                on \(self.isActive) overlay \(self.overlay.isVisible)
                """
            )
            guard self.isActive, !self.overlay.isVisible,
                  let image = self.snapshotter.latestImage,
                  let screen = self.snapshotter.latestScreen else { return }
            self.show(image: image, on: screen)
        }
    }

    /// Takes one screenshot to start a live overlay that has nothing to show
    /// yet. A stream frame that lands first makes it unnecessary.
    private func requestSeed() {
        isCapturePending = true
        let started = CACurrentMediaTime()
        pictureTask?.cancel()
        pictureTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.snapshotter.captureOnce()
            guard !Task.isCancelled else { return }
            self.pictureTask = nil
            self.isCapturePending = false
            Diagnostics.lid.notice(
                """
                seed capture landed after \((CACurrentMediaTime() - started) * 1000, format: .fixed(precision: 0)) ms: \
                image \(self.snapshotter.latestImage != nil) on \(self.isActive) \
                ready \(self.overlay.isPictureReady)
                """
            )
            guard self.isActive, !self.overlay.isPictureReady,
                  let image = self.snapshotter.latestImage else { return }
            self.overlay.seed(image: image)
        }
    }

    private func show(image: CGImage, on screen: NSScreen) {
        overlay.show(
            image: image,
            on: screen,
            startAngle: effectStartAngle,
            tuning: tuning,
            fadeIn: Self.fadeInDuration
        )
        // The link belongs to the overlay window.
        startDisplayLink()
    }

    private func blurProgress(for angle: Double) -> Double {
        let span = max(effectStartAngle - AdaptiveLidPolicy.closedZone, 1)
        return min(max((effectStartAngle - angle) / span, 0), 1)
    }

    // MARK: - Animation

    private func startDisplayLink() {
        stopDisplayLink()
        guard let window = overlay.hostWindow else {
            Diagnostics.lid.notice("display link skipped, no overlay window")
            return
        }
        Diagnostics.lid.notice("display link started")
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        // Match ScreenStreamer's 60 Hz source instead of requesting up to
        // 120 callbacks on a ProMotion panel while compositing at 60 Hz.
        let maximumFPS = min(Float(NSScreen.builtIn?.maximumFramesPerSecond ?? 60), 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximumFPS),
            maximum: maximumFPS, preferred: maximumFPS)
        link.add(to: .main, forMode: .common)
        lastFrameTime = CACurrentMediaTime()
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let rawInterval = now - lastFrameTime
        let dt = min(max(rawInterval, 1.0 / 240), 1.0 / 20)
        lastFrameTime = now
        if let frame = streamer.newFrame() {
            overlay.absorb(frame)
        }
        if isAwaitingWakePicture {
            guard overlay.isPictureReady else { return }
            isAwaitingWakePicture = false
            overlay.restoreGeometry(angle: visualAngle.value, startAngle: effectStartAngle, tuning: tuning)
            isActive = false
            motionPolicy.reset()
            beginClosingOut()
            Diagnostics.lid.notice("wake: fresh picture ready, returning saved effect")
        }
        if isClosingOut {
            let release = EffectRelease(elapsed: now - closingOutStartedAt)
            let ease = 1 - release.strength
            let angle = releaseAngle + (effectStartAngle - releaseAngle) * ease
            visualAngle.reset(to: angle)
            blurEnvelope.restore(releaseBlur * release.strength)
            overlay.update(progress: blurEnvelope.value, currentAngle: releaseAngle,
                           tuning: tuning, geometryStrength: release.strength,
                           geometryStart: effectStartAngle, releaseOpacity: release.opacity, dt: dt,
                           release: release)
            if release.isFinished { finishClosingOut() }
            return
        }
        let target = rawAngle
        visualAngle.advance(to: target, dt: dt)
        blurEnvelope.advance(target: blurProgress(for: rawAngle), dt: dt)

        applyVisual(angle: visualAngle.value, dt: dt)
    }

    /// The geometry takes the lid angle itself, so only the blur saturates.
    private func applyVisual(angle: Double, dt: Double) {
        let progress = blurEnvelope.value
        overlay.update(progress: progress, currentAngle: angle, tuning: tuning,
                       geometryAngle: rawAngle,
                       geometryStart: effectStartAngle, dt: dt)
    }

    private var tuning: DepthTuning {
        DepthTuning(
            viewingDistance: preferences.viewingDistance,
            recession: preferences.recession,
            blurEvenness: preferences.blurEvenness,
            dimReach: preferences.dimReach,
            maxBlurRadius: preferences.maxBlurRadius,
            maxDim: preferences.maxDim
        )
    }

    // MARK: - System events

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resume()
            }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // macOS posts this for backlight and colour changes too.
                let screen = NSScreen.builtIn
                let layout = Layout(displayID: screen?.displayID, frame: screen?.frame)
                guard layout != self.builtInLayout else {
                    Diagnostics.lid.notice("screen parameters changed, layout unchanged")
                    return
                }
                Diagnostics.lid.notice(
                    "screen parameters changed, layout now \(String(describing: layout), privacy: .public)"
                )
                self.builtInLayout = layout
                if layout.displayID == nil {
                    self.rememberEffectForWake()
                    self.stopEffectAndCapture(preserveWakeEffect: true)
                    self.streamer.invalidateFilter()
                    self.snapshotter.invalidateFilter()
                    return
                }
                if self.isAwaitingWakePicture {
                    self.wakeRestoration.remember(angle: self.visualAngle.value,
                        startAngle: self.effectStartAngle, blur: self.blurEnvelope.value,
                        closing: true, enabled: self.preferences.isEnabled)
                }
                if self.wakeRestoration.pending != nil {
                    self.stopEffectAndCapture(preserveWakeEffect: true)
                    self.streamer.invalidateFilter()
                    self.snapshotter.invalidateFilter()
                    self.poll()
                    return
                }
                if self.isActive { self.setActive(false) }
                self.streamer.stop()
                self.streamer.invalidateFilter()
                Task { await self.streamer.warmFilter() }
                self.overlay.discardLive()
                self.snapshotter.discard()
                Task { await self.snapshotter.warmFilter() }
            }
        }
    }

    private func suspend() {
        Diagnostics.lid.notice("suspend")
        rememberEffectForWake()
        isSuspended = true
        stopEffectAndCapture(preserveWakeEffect: true)
    }

    private func rememberEffectForWake() {
        wakeRestoration.remember(angle: rawAngle, startAngle: effectStartAngle,
            blur: blurEnvelope.value,
            closing: isActive || (rawAngle < 80 && CACurrentMediaTime() - lastClosingTime < 2),
            enabled: preferences.isEnabled)
    }

    private func resume() {
        guard isSuspended || wakeRestoration.pending != nil else { poll(); return }
        Diagnostics.lid.notice("resume")
        isSuspended = false
        builtInLayout = Layout(displayID: NSScreen.builtIn?.displayID, frame: NSScreen.builtIn?.frame)
        streamer.invalidateFilter()
        snapshotter.invalidateFilter()
        // A fresh baseline, so waking with a nearly shut lid does not read as
        // closing movement.
        lastChangedAngle = nil
        angularVelocity = 0
        lastClosingTime = -.greatestFiniteMagnitude
        motionPolicy.reset()
        isClosingOut = false
        setPollInterval(Self.activePollInterval)
        poll()
    }
}
