public enum Finger: String, Sendable, CaseIterable, Codable {
    case index, middle, ring, little
}

public enum Joint: String, Sendable, CaseIterable, Codable, CodingKeyRepresentable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    public static func mcp(_ f: Finger) -> Joint {
        switch f {
        case .index: .indexMCP
        case .middle: .middleMCP
        case .ring: .ringMCP
        case .little: .littleMCP
        }
    }

    public static func tip(_ f: Finger) -> Joint {
        switch f {
        case .index: .indexTip
        case .middle: .middleTip
        case .ring: .ringTip
        case .little: .littleTip
        }
    }

    public static let bones: [(Joint, Joint)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP),
    ]
}

public struct Hand: Sendable, Equatable {
    public var id: Int
    public var points: [Joint: Vec2]

    public init(id: Int = 0, points: [Joint: Vec2]) {
        self.id = id
        self.points = points
    }
}

public struct HandFrame: Sendable {
    public var time: Double
    public var hands: [Hand]
    public var aspect: Double

    public init(time: Double, hands: [Hand], aspect: Double = 16.0 / 9.0) {
        self.aspect = aspect
        self.time = time
        self.hands = hands
    }
}
