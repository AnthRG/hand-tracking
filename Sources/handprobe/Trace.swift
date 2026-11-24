import Foundation
import HandCore

func summarizeTrace(_ path: String) throws {
    let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
    let frames = lines.compactMap { try? JSONDecoder().decode(TraceFrame.self, from: Data($0.utf8)) }
    guard frames.count > 1 else {
        print("trace vacío")
        return
    }
    let times = frames.map(\.time)
    let gaps = zip(times.dropFirst(), times).map { $0 - $1 }.sorted()
    let detect = frames.map(\.detectMs).sorted()
    func pick(_ v: [Double], _ q: Double) -> Double { v[min(v.count - 1, Int(Double(v.count) * q))] }
    print(String(format: "cuadros=%d duración=%.1fs fps=%.1f", frames.count, times.last! - times.first!, Double(frames.count - 1) / (times.last! - times.first!)))
    print(String(format: "intervalo ms p50=%.0f p95=%.0f max=%.0f", pick(gaps, 0.5) * 1000, pick(gaps, 0.95) * 1000, gaps.last! * 1000))
    print(String(format: "detección ms p50=%.0f p95=%.0f max=%.0f", pick(detect, 0.5), pick(detect, 0.95), detect.last!))

    var counts: [CursorState: Int] = [:]
    for f in frames { counts[f.state, default: 0] += 1 }
    for (state, n) in counts.sorted(by: { $0.value > $1.value }) {
        print(String(format: "  %@ %d (%.0f%%)", state.rawValue, n, 100 * Double(n) / Double(frames.count)))
    }

    func replay() -> Int {
        let engine = GestureEngine()
        let tracker = HandTracker()
        var cuts = 0
        var previous: CursorState = .notEngaged
        for f in frames {
            let frame = tracker.update(observations: f.hands, time: f.time, aspect: f.aspect)
            _ = engine.update(frame)
            if previous == .moved, [.noHand, .notPointing, .frozen].contains(engine.cursorState) { cuts += 1 }
            previous = engine.cursorState
        }
        return cuts
    }
    print("cortes a mitad de movimiento: \(replay())")
}
