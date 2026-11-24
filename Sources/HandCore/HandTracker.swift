public final class HandTracker {
    private struct Track {
        var id: Int
        var points: [Joint: Vec2]
        var seen: [Joint: Double]
        var lastTime: Double
    }

    private let maxJump = 0.35
    private let jointMemory = 0.12
    private let trackMemory = 0.3
    private var tracks: [Track] = []
    private var nextID = 1

    public init() {}

    public func update(observations: [[Joint: Vec2]], time: Double, aspect: Double = 16.0 / 9.0) -> HandFrame {
        tracks.removeAll { time - $0.lastTime > trackMemory }

        var pairs: [(track: Int, obs: Int, distance: Double)] = []
        for (t, track) in tracks.enumerated() {
            guard let a = Self.position(track.points) else { continue }
            for (o, points) in observations.enumerated() {
                guard let b = Self.position(points) else { continue }
                let d = a.distance(to: b)
                if d < maxJump { pairs.append((t, o, d)) }
            }
        }
        pairs.sort { $0.distance < $1.distance }

        var assigned: [Int: Int] = [:]
        var usedTracks: Set<Int> = []
        for pair in pairs where assigned[pair.obs] == nil && !usedTracks.contains(pair.track) {
            assigned[pair.obs] = pair.track
            usedTracks.insert(pair.track)
        }

        var hands: [Hand] = []
        for (o, points) in observations.enumerated() {
            guard Self.position(points) != nil else { continue }
            let index: Int
            if let existing = assigned[o] {
                index = existing
            } else {
                tracks.append(Track(id: nextID, points: [:], seen: [:], lastTime: time))
                nextID += 1
                index = tracks.count - 1
            }
            for (joint, p) in points {
                tracks[index].points[joint] = p
                tracks[index].seen[joint] = time
            }
            tracks[index].lastTime = time
            for (joint, seen) in tracks[index].seen where time - seen > jointMemory {
                tracks[index].points[joint] = nil
                tracks[index].seen[joint] = nil
            }
            hands.append(Hand(id: tracks[index].id, points: tracks[index].points))
        }
        return HandFrame(time: time, hands: hands, aspect: aspect)
    }

    public func reset() { tracks.removeAll() }

    private static func position(_ points: [Joint: Vec2]) -> Vec2? {
        points[.middleMCP] ?? points[.wrist]
    }
}
