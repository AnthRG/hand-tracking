struct PinchTracker {
    private(set) var current: Finger?
    private var pending: Finger?
    private var pendingSince: Double?
    private let debounce = 0.03

    mutating func update(_ f: HandFeatures, sensitivity: Double, time: Double, fast: Bool = false) {
        let on = 0.12 + 0.2 * sensitivity
        let raw: Finger?
        if let current {
            raw = (f.pinches[current] ?? 1) > on + 0.12 ? nil : current
        } else {
            raw = Self.candidate(f, threshold: on)
        }

        guard raw != current else {
            pendingSince = nil
            return
        }
        guard let since = pendingSince, pending == raw else {
            pending = raw
            pendingSince = time
            return
        }
        if time - since >= (fast ? 0.1 : debounce) {
            current = raw
            pendingSince = nil
        }
    }

    private static func candidate(_ f: HandFeatures, threshold: Double) -> Finger? {
        var best: (Finger, Double)?
        func consider(_ finger: Finger, _ allowed: Bool) {
            guard allowed, let ratio = f.pinches[finger], ratio < threshold else { return }
            if best == nil || ratio < best!.1 { best = (finger, ratio) }
        }
        consider(.index, (f.extensions[.index] ?? 0) > 0.04)
        consider(.middle, (f.pinches[.index] ?? 0) > 0.5 && (f.extensions[.index] ?? 0) > 0.4 && !f.isCurled(.little))
        return best?.0
    }
}
