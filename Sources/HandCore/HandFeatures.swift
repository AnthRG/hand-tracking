import Foundation

public enum Pose: Sendable, Equatable {
    case open, point, twoFingers, fist
    case thumbUp, thumbDown, thumbLeft, thumbRight
    case other
}

public struct HandFeatures: Sendable {
    public let id: Int
    public let palm: Double
    public let anchor: Vec2
    public let center: Vec2
    public let extensions: [Finger: Double]
    public let pinches: [Finger: Double]
    public let thumbReach: Double
    public let tip: Vec2?
    public let pose: Pose

    public init?(_ hand: Hand) {
        let p = hand.points
        guard let wrist = p[.wrist], let index = p[.indexMCP],
              let middle = p[.middleMCP], let little = p[.littleMCP]
        else { return nil }

        let scale = max(wrist.distance(to: middle), 1.25 * index.distance(to: little))
        guard scale > 0.001 else { return nil }

        var ext: [Finger: Double] = [:]
        var pinch: [Finger: Double] = [:]
        for finger in Finger.allCases {
            guard let tip = p[Joint.tip(finger)] else { continue }
            if let mcp = p[Joint.mcp(finger)] {
                ext[finger] = (tip.distance(to: wrist) - mcp.distance(to: wrist)) / scale
            }
            if let thumb = p[.thumbTip] {
                pinch[finger] = thumb.distance(to: tip) / scale
            }
        }

        id = hand.id
        palm = scale
        anchor = (index + middle) / 2
        center = (wrist + index + middle + little) / 4
        extensions = ext
        pinches = pinch
        thumbReach = p[.thumbTip].map { $0.distance(to: index) / scale } ?? 0
        if let thumb = p[.thumbTip], let indexTip = p[.indexTip] {
            tip = (thumb + indexTip) / 2
        } else {
            tip = nil
        }
        pose = Self.classify(ext: ext, pinch: pinch, reach: thumbReach, thumbMP: p[.thumbMP], thumbTip: p[.thumbTip])
    }

    public func isExtended(_ f: Finger) -> Bool { Self.extended(extensions, f) }
    public func isCurled(_ f: Finger) -> Bool { Self.curled(extensions, f) }

    private static func extended(_ e: [Finger: Double], _ f: Finger) -> Bool {
        (e[f] ?? 0) > (f == .little ? 0.35 : 0.5)
    }

    private static func curled(_ e: [Finger: Double], _ f: Finger) -> Bool {
        (e[f] ?? 1) < (f == .little ? 0.22 : 0.28)
    }

    static let hoverEnter = 0.6
    static let hoverExit = 0.8

    private static func isPointing(_ e: [Finger: Double], _ pinch: [Finger: Double]) -> Bool {
        (pinch[.index] ?? 1) < hoverEnter && (e[.index] ?? 0) > 0.04
    }

    private static func isTwoFingers(_ e: [Finger: Double], _ pinch: [Finger: Double]) -> Bool {
        guard let index = e[.index], let middle = e[.middle], let ring = e[.ring], let little = e[.little] else { return false }
        return index > 0.5 && middle > 0.5 && ring < 0.35 && little < 0.3 && (pinch[.index] ?? 1) > hoverEnter
    }

    private static func classify(ext: [Finger: Double], pinch: [Finger: Double], reach: Double, thumbMP: Vec2?, thumbTip: Vec2?) -> Pose {
        if isPointing(ext, pinch) { return .point }
        if Finger.allCases.allSatisfy({ extended(ext, $0) }) { return .open }
        if isTwoFingers(ext, pinch) { return .twoFingers }
        guard Finger.allCases.allSatisfy({ curled(ext, $0) }) else { return .other }
        guard let thumbMP, let thumbTip else { return .other }
        if reach < 0.5 { return .fist }
        guard reach > 0.58 else { return .other }

        let d = thumbTip - thumbMP
        let angle = atan2(d.y, d.x) * 180 / .pi
        switch angle {
        case 55...125: return .thumbUp
        case -125 ... -55: return .thumbDown
        case -35...35: return .thumbRight
        case 145...180, -180 ... -145: return .thumbLeft
        default: return .other
        }
    }
}
