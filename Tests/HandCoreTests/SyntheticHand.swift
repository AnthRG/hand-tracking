@testable import HandCore

enum Shape {
    case open, point, twoFingers, fist
    case indexPinch, middlePinch
    case thumbUp, thumbDown, thumbLeft, thumbRight
    case half
}

func makeHand(_ shape: Shape, at position: Vec2, scale: Double = 0.2, id: Int = 1) -> Hand {
    let wrist = Vec2(0, 0)
    let mcp: [Finger: Vec2] = [
        .index: Vec2(-0.27, 0.95), .middle: Vec2(0, 1), .ring: Vec2(0.22, 0.93), .little: Vec2(0.42, 0.82),
    ]
    var ext: [Finger: Double] = [.index: 0.9, .middle: 0.93, .ring: 0.9, .little: 0.7]
    let curledAll: [Finger: Double] = [.index: -0.1, .middle: -0.08, .ring: -0.1, .little: -0.1]
    switch shape {
    case .open: break
    case .point:
        ext = [.index: 0.4, .middle: 0.5, .ring: 0.45, .little: 0.3]
    case .twoFingers:
        ext = curledAll
        ext[.index] = 0.9
        ext[.middle] = 0.93
    case .fist, .thumbUp, .thumbDown, .thumbLeft, .thumbRight: ext = curledAll
    case .indexPinch: ext[.index] = 0.18
    case .middlePinch: ext[.middle] = 0.2
    case .half: ext = [.index: 0.4, .middle: 0.4, .ring: 0.4, .little: 0.3]
    }

    var p: [Joint: Vec2] = [.wrist: wrist]
    var tips: [Finger: Vec2] = [:]
    for f in Finger.allCases {
        let m = mcp[f]!
        p[Joint.mcp(f)] = m
        let tip = m * ((m.length + ext[f]!) / m.length)
        tips[f] = tip
        p[Joint.tip(f)] = tip
    }
    let thumbMP = Vec2(-0.45, 0.55)
    p[.thumbMP] = thumbMP
    switch shape {
    case .open, .half: p[.thumbTip] = Vec2(-1.0, 1.0)
    case .point: p[.thumbTip] = tips[.index]! + Vec2(-0.45, -0.2)
    case .twoFingers: p[.thumbTip] = Vec2(-0.1, 0.75)
    case .fist: p[.thumbTip] = Vec2(-0.1, 0.8)
    case .indexPinch: p[.thumbTip] = tips[.index]! + Vec2(-0.08, 0)
    case .middlePinch: p[.thumbTip] = tips[.middle]! + Vec2(0, -0.08)
    case .thumbUp: p[.thumbTip] = Vec2(-0.45, 1.75)
    case .thumbDown: p[.thumbTip] = Vec2(-0.45, -0.4)
    case .thumbLeft: p[.thumbTip] = Vec2(-1.3, 0.55)
    case .thumbRight: p[.thumbTip] = Vec2(0.6, 0.55)
    }
    return Hand(id: id, points: p.mapValues { $0 * scale + position })
}

final class Rig {
    let engine: GestureEngine
    var time = 0.0
    var position = Vec2(0.8, 0.4)
    var events: [GestureEvent] = []
    let dt = 1.0 / 30

    init(_ settings: GestureSettings = GestureSettings()) { engine = GestureEngine(settings: settings) }

    @discardableResult
    func run(_ shape: Shape?, _ seconds: Double, move: Vec2 = .zero, typing: Bool = false,
             second: (Shape, (Double) -> Vec2)? = nil) -> [GestureEvent] {
        let frames = max(1, Int((seconds / dt).rounded()))
        let start = position
        var out: [GestureEvent] = []
        for i in 1...frames {
            time += dt
            let k = Double(i) / Double(frames)
            position = start + move * k
            var hands: [Hand] = []
            if let shape { hands.append(makeHand(shape, at: position)) }
            if let second { hands.append(makeHand(second.0, at: second.1(k), id: 2)) }
            out += engine.update(HandFrame(time: time, hands: hands), typing: typing)
        }
        events += out
        return out
    }

    func engage() {
        run(.open, 0.8)
        events = []
    }
}

extension [GestureEvent] {
    var triggers: [Gesture] { compactMap { if case let .trigger(g) = $0 { g } else { nil } } }
    var moves: [Vec2] { compactMap { if case let .moveTo(v) = $0 { v } else { nil } } }
    var total: Vec2 { moves.count < 2 ? .zero : moves[moves.count - 1] - moves[0] }
    var withoutMoves: [GestureEvent] { filter { if case .moveTo = $0 { false } else { true } } }
    var scrolls: [Vec2] { compactMap { if case let .scroll(v) = $0 { v } else { nil } } }
}

extension GestureSettings {
    static var allOn: GestureSettings {
        var s = GestureSettings()
        s.disabled = []
        return s
    }
}
