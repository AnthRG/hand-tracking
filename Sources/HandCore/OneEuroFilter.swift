import Foundation

public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    private let derivativeCutoff = 1.0
    private var value: Vec2?
    private var derivative = Vec2.zero
    private var lastTime = 0.0

    public init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    public mutating func filter(_ raw: Vec2, time: Double) -> Vec2 {
        guard let previous = value, time > lastTime else {
            value = raw
            derivative = .zero
            lastTime = time
            return raw
        }
        let dt = time - lastTime
        lastTime = time
        let rate = (raw - previous) / dt
        let ad = Self.alpha(derivativeCutoff, dt)
        derivative = rate * ad + derivative * (1 - ad)
        let a = Self.alpha(minCutoff + beta * derivative.length, dt)
        let next = raw * a + previous * (1 - a)
        value = next
        return next
    }

    public mutating func reset() {
        value = nil
        derivative = .zero
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
