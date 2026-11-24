public struct TraceFrame: Codable, Sendable {
    public var time: Double
    public var aspect: Double
    public var detectMs: Double
    public var state: CursorState
    public var hands: [[Joint: Vec2]]

    public init(time: Double, aspect: Double, detectMs: Double, state: CursorState, hands: [[Joint: Vec2]]) {
        self.time = time
        self.aspect = aspect
        self.detectMs = detectMs
        self.state = state
        self.hands = hands
    }
}
