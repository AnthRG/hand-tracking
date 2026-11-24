import AVFoundation
import Foundation
import HandCore
import HandVision

struct PipelineStatus: Sendable {
    var hands: [Hand] = []
    var aspect = 16.0 / 9.0
    var engaged = false
    var progress = 0.0
    var pose: Pose = .other
    var events: [GestureEvent] = []
}

final class Pipeline {
    var onStatus: ((PipelineStatus) -> Void)?

    private let queue: DispatchQueue
    private let detector = HandDetector()
    private let tracker = HandTracker()
    private let engine: GestureEngine
    private let system = SystemController()
    private var active = false
    private var trace: FileHandle?
    private var traceEnd = 0.0
    private var lastFrame = 0.0
    private var watchdog: DispatchSourceTimer?

    init(queue: DispatchQueue, settings: GestureSettings) {
        self.queue = queue
        engine = GestureEngine(settings: settings)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.releaseIfStalled() }
        timer.resume()
        watchdog = timer
    }

    func apply(_ settings: GestureSettings) {
        queue.async { self.engine.settings = settings }
    }

    func activate() {
        queue.async { self.active = true }
    }

    func deactivate(sync: Bool = false) {
        let work = { [self] in
            active = false
            dispatch(engine.reset())
            tracker.reset()
            onStatus?(PipelineStatus())
        }
        if sync { queue.sync(execute: work); system.flush() } else { queue.async(execute: work) }
    }

    func process(_ buffer: CVPixelBuffer, time: Double) {
        guard active else { return }
        defer { lastFrame = system.now }
        detector.minConfidence = engine.isEngaged ? 0.12 : 0.3
        let began = system.now
        let observations = (try? detector.detect(buffer, hint: engine.hint)) ?? []
        let detectMs = (system.now - began) * 1000
        let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
        let frame = tracker.update(observations: observations, time: time, aspect: aspect)
        let events = engine.update(frame, typing: system.isUserTyping())
        dispatch(events)
        record(TraceFrame(time: time, aspect: aspect, detectMs: detectMs, state: engine.cursorState, hands: observations))
        onStatus?(PipelineStatus(
            hands: frame.hands,
            aspect: aspect,
            engaged: engine.isEngaged,
            progress: engine.engageProgress,
            pose: engine.currentPose,
            events: events
        ))
    }

    func startTrace(seconds: Double, to url: URL) {
        queue.async { [self] in
            try? trace?.close()
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            trace = try? FileHandle(forWritingTo: url)
            traceEnd = system.now + seconds
        }
    }

    private func record(_ frame: TraceFrame) {
        guard let trace else { return }
        guard system.now < traceEnd else {
            try? trace.close()
            self.trace = nil
            return
        }
        if var data = try? JSONEncoder().encode(frame) {
            data.append(0x0A)
            try? trace.write(contentsOf: data)
        }
    }

    private func releaseIfStalled() {
        guard active, engine.isEngaged, system.now - lastFrame > 0.7 else { return }
        dispatch(engine.reset())
        onStatus?(PipelineStatus())
    }

    private func dispatch(_ events: [GestureEvent]) {
        for event in events { system.perform(event, settings: engine.settings) }
    }
}
