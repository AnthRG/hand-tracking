public enum GestureEvent: Sendable, Equatable {
    case engaged
    case disengaged
    case moveTo(Vec2)
    case click(count: Int)
    case dragBegan
    case dragEnded
    case scroll(Vec2)
    case trigger(Gesture)
}

public enum CursorState: String, Sendable, Codable {
    case notEngaged, noHand, coasting, notPointing, frozen, pressed, steady, moved
}

public struct TrackingHint: Sendable {
    public let center: Vec2
    public let palm: Double

    public init(center: Vec2, palm: Double) {
        self.center = center
        self.palm = palm
    }
}

public final class GestureEngine {
    public var settings: GestureSettings
    public private(set) var isEngaged = false
    public private(set) var engageProgress = 0.0
    public private(set) var currentPose: Pose = .other
    public private(set) var cursorState: CursorState = .notEngaged

    private enum Press: Equatable {
        case idle
        case pending(since: Double, moved: Vec2)
        case dragging
        case suppressed
        case twoHand(startSpan: Double, fired: Bool)
    }

    private struct Sample {
        var time: Double
        var position: Vec2
        var open: Bool
    }

    private let minPalm = 0.05
    private let releaseGrace = 0.25
    private let lostTimeout = 0.6
    private let coastTime = 0.15
    private let pointingGrace = 0.15
    private let fastSpeed = 1.2
    private let idleTimeout = 10.0
    private let dragThreshold = 0.14
    private let longPress = 0.4
    private let doubleClickWindow = 0.6
    private let swipeWindow = 0.3

    private var time = 0.0
    private var primaryID: Int?
    private var lastSeen = 0.0
    private var lastActivity = 0.0
    private var stillSince: [Int: Double] = [:]
    private var lastCenters: [Int: (time: Double, position: Vec2)] = [:]
    private var pinches: [Int: PinchTracker] = [:]
    private var press: Press = .idle
    private var aspect = 16.0 / 9.0
    private var tipFilter = OneEuroFilter(minCutoff: 1, beta: 1)
    private var pointing = false
    private var cursor: Vec2?
    private var offset = Vec2.zero
    private var rebase = false
    private var velocity = Vec2.zero
    private var lastTipSeen = 0.0
    private var lastPointing = -10.0
    private var lastCenter: Vec2?
    private var lastOthers: Set<Int> = []
    private var handSpeed = 0.0
    private var lastTipTime = 0.0
    private var openSince: Double?
    private var twoFingersSince: Double?
    private var filter = OneEuroFilter(minCutoff: 1, beta: 1)
    private var lastAnchor: Vec2?
    private var lastAnchorTime = 0.0
    private var palm: Double?
    private var lastPalm: Double?
    private var lastIndexPinch: (time: Double, ratio: Double)?
    private var frozenUntil = 0.0
    private var lastClick = -10.0
    private var samples: [Sample] = []
    private var swipeArmed = true
    private var swipeFiredAt = -10.0
    private var pendingDown: Double?
    private var slowSince: Double?
    private var heldPose: Pose?
    private var heldSince = 0.0
    private var heldLastSeen = 0.0
    private var heldLastFired: Double?

    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }

    public var hint: TrackingHint? {
        guard isEngaged, let lastCenter, let palm = palm ?? lastPalm else { return nil }
        return TrackingHint(center: lastCenter, palm: palm)
    }

    public func reset() -> [GestureEvent] {
        stillSince = [:]
        lastCenters = [:]
        pinches = [:]
        return disengage()
    }

    public func update(_ frame: HandFrame, typing: Bool = false) -> [GestureEvent] {
        time = frame.time
        aspect = frame.aspect
        let hands = frame.hands.compactMap(HandFeatures.init).filter { $0.palm >= minPalm }
        forgetMissing(hands)
        let speeds = measureSpeeds(hands)
        let primary = isEngaged ? hands.first { $0.id == primaryID } ?? reacquire(hands) : nil
        for hand in hands {
            let fast = hand.id == primary?.id && handSpeed > fastSpeed
            pinches[hand.id, default: PinchTracker()]
                .update(hand, sensitivity: settings.pinchSensitivity, time: time, fast: fast)
        }
        cursorState = .notEngaged

        if typing {
            stillSince = [:]
            engageProgress = 0
            currentPose = .other
            return disengage()
        }
        guard isEngaged else { return tryEngage(hands, speeds) }
        guard let hand = primary else { return handleMissing(hands) }

        lastSeen = time
        lastCenter = hand.center
        lastPalm = hand.palm
        lastOthers = Set(hands.map(\.id)).subtracting([hand.id])
        cursorState = .notPointing
        currentPose = hand.pose
        let other = hands.first { $0.id != hand.id }
        let delta = trackAnchor(hand)
        if delta.dt > 0 { handSpeed = handSpeed * 0.5 + delta.value.length / delta.dt * 0.5 }
        let tip = trackTip(hand)
        var events = updatePress(hand, other, delta, tip)
        if press == .idle {
            events += updatePointer(hand, tip)
            events += updateScroll(hand, delta)
            events += updateSwipe(hand, speeds[hand.id] ?? 0)
            events += updateHold(hand)
        } else {
            if cursorState == .notPointing { cursorState = .pressed }
            samples = []
            openSince = nil
            twoFingersSince = nil
            heldPose = nil
        }

        if !events.isEmpty || pointing { lastActivity = time }
        if press == .idle, time - lastActivity > idleTimeout { events += disengage() }
        return events
    }

    private func reacquire(_ hands: [HandFeatures]) -> HandFeatures? {
        guard let old = primaryID, let lastCenter else { return nil }
        let radius = 0.3 + 1.5 * (time - lastSeen)
        let near = hands
            .filter { !lastOthers.contains($0.id) && $0.center.distance(to: lastCenter) < radius }
            .min { $0.center.distance(to: lastCenter) < $1.center.distance(to: lastCenter) }
        guard let near else { return nil }
        pinches[near.id] = pinches[old]
        pinches[old] = nil
        primaryID = near.id
        return near
    }

    private func forgetMissing(_ hands: [HandFeatures]) {
        let ids = Set(hands.map(\.id))
        stillSince = stillSince.filter { ids.contains($0.key) }
        lastCenters = lastCenters.filter { ids.contains($0.key) }
        pinches = pinches.filter { ids.contains($0.key) || $0.key == primaryID }
    }

    private func measureSpeeds(_ hands: [HandFeatures]) -> [Int: Double] {
        var speeds: [Int: Double] = [:]
        for hand in hands {
            if let last = lastCenters[hand.id], time > last.time {
                speeds[hand.id] = hand.center.distance(to: last.position) / hand.palm / (time - last.time)
            }
            lastCenters[hand.id] = (time, hand.center)
        }
        return speeds
    }

    private func tryEngage(_ hands: [HandFeatures], _ speeds: [Int: Double]) -> [GestureEvent] {
        engageProgress = 0
        currentPose = hands.first?.pose ?? .other
        for hand in hands {
            guard hand.pose == .open, let speed = speeds[hand.id], speed < 1.0 else {
                stillSince[hand.id] = nil
                continue
            }
            let since = stillSince[hand.id] ?? time
            stillSince[hand.id] = since
            let progress = settings.engageHold > 0 ? (time - since) / settings.engageHold : 1
            engageProgress = max(engageProgress, min(progress, 1))
            if progress >= 1 {
                engage(hand)
                return [.engaged]
            }
        }
        return []
    }

    private func engage(_ hand: HandFeatures) {
        isEngaged = true
        engageProgress = 1
        primaryID = hand.id
        lastSeen = time
        lastActivity = time
        stillSince = [:]
        swipeArmed = true
        swipeFiredAt = -10
        lastClick = -10
        frozenUntil = 0
        clearMotion()
        openSince = time - settings.engageHold
    }

    private func disengage() -> [GestureEvent] {
        engageProgress = 0
        guard isEngaged else { return [] }
        let events = releasePress()
        isEngaged = false
        primaryID = nil
        clearMotion()
        return events + [.disengaged]
    }

    private func clearMotion() {
        filter.reset()
        tipFilter.reset()
        pointing = false
        cursor = nil
        velocity = .zero
        handSpeed = 0
        offset = .zero
        rebase = false
        openSince = nil
        twoFingersSince = nil
        lastAnchor = nil
        palm = nil
        lastIndexPinch = nil
        samples = []
        slowSince = nil
        pendingDown = nil
        heldPose = nil
        heldLastFired = nil
    }

    private func releasePress() -> [GestureEvent] {
        let wasDragging = press == .dragging
        press = .idle
        return wasDragging ? [.dragEnded] : []
    }

    private func handleMissing(_ hands: [HandFeatures]) -> [GestureEvent] {
        currentPose = .other
        cursorState = .noHand
        pendingDown = nil
        let gone = time - lastSeen
        if gone > lostTimeout { return disengage() }
        guard gone > releaseGrace else { return coast() }
        clearMotion()
        guard press != .idle else { return [] }
        if let primaryID { pinches[primaryID] = nil }
        return releasePress()
    }

    private func coast() -> [GestureEvent] {
        rebase = true
        guard pointing || press == .dragging, let cursor else { return [] }
        let gone = time - lastTipSeen
        let dt = min(max(time - lastTipTime, 0), 0.1)
        lastTipTime = time
        guard gone < coastTime, velocity.length > 0.1 else { return [] }
        let next = cursor + velocity * (dt * (1 - gone / coastTime))
        let target = Vec2(min(max(next.x, 0), 1), min(max(next.y, 0), 1))
        self.cursor = target
        cursorState = .coasting
        return [.moveTo(target)]
    }

    private func trackAnchor(_ hand: HandFeatures) -> (value: Vec2, dt: Double) {
        let scale = palm.map { $0 * 0.9 + hand.palm * 0.1 } ?? hand.palm
        palm = scale
        filter.minCutoff = 3.2 - 2.6 * settings.smoothing
        filter.beta = 6
        let smooth = filter.filter(hand.anchor, time: time)
        defer {
            lastAnchor = smooth
            lastAnchorTime = time
        }
        guard let lastAnchor, time > lastAnchorTime else { return (.zero, 0) }
        return ((smooth - lastAnchor) / scale, time - lastAnchorTime)
    }

    private func trackTip(_ hand: HandFeatures) -> Vec2? {
        guard let raw = hand.tip else { return nil }
        tipFilter.minCutoff = 3.0 - 2.0 * settings.smoothing
        tipFilter.beta = 12
        let p = tipFilter.filter(raw, time: time)
        let area = max(settings.pointerArea, 0.1)
        return Vec2((p.x / aspect - 0.5) / area + 0.5, (p.y - 0.5) / area + 0.5)
    }

    private func moveCursor(_ tip: Vec2?) -> [GestureEvent] {
        guard let tip else { return coast() }
        lastTipSeen = time
        if rebase, let cursor { offset = cursor - tip }
        rebase = false
        let dt = min(max(time - lastTipTime, 0), 0.1)
        lastTipTime = time
        offset = offset * max(0, 1 - dt / 0.25)
        let raw = tip + offset
        let target = Vec2(min(max(raw.x, 0), 1), min(max(raw.y, 0), 1))
        if let cursor {
            if dt > 0 {
                let rate = (target - cursor) / dt
                velocity = velocity * 0.4 + rate * (0.6 * min(1, 3 / max(rate.length, 0.001)))
            }
            if cursor.distance(to: target) < 0.0006 {
                cursorState = .steady
                return []
            }
        }
        cursor = target
        cursorState = .moved
        return [.moveTo(target)]
    }

    private func updatePress(_ hand: HandFeatures, _ other: HandFeatures?, _ delta: (value: Vec2, dt: Double), _ tip: Vec2?) -> [GestureEvent] {
        let pinch = pinches[hand.id]?.current
        let otherPinch = other.flatMap { pinches[$0.id]?.current }

        if pinch == .index, otherPinch == .index, let other, canStartTwoHand {
            press = .twoHand(startSpan: max(span(hand, other), 0.1), fired: false)
            return []
        }

        switch press {
        case .idle:
            switch pinch {
            case .index where handSpeed > fastSpeed:
                break
            case .index:
                rebase = true
                press = settings.isEnabled(.indexPinch) || twoHandEnabled
                    ? .pending(since: time, moved: .zero) : .suppressed
            case .middle:
                press = .suppressed
                return settings.action(for: .middlePinch) == .none ? [] : [.trigger(.middlePinch)]
            case .ring, .little, nil:
                break
            }
            return []

        case let .pending(since, moved):
            guard settings.isEnabled(.indexPinch) else {
                if pinch == nil { press = .idle }
                return []
            }
            if pinch == nil {
                press = .idle
                frozenUntil = time + 0.12
                let count = time - lastClick < doubleClickWindow ? 2 : 1
                lastClick = count == 2 ? -10 : time
                return [.click(count: count)]
            }
            let total = moved + delta.value
            if total.length > dragThreshold || ((other == nil || !twoHandEnabled) && time - since > longPress) {
                press = .dragging
                return [.dragBegan]
            }
            press = .pending(since: since, moved: total)
            return []

        case .dragging:
            if pinch == nil {
                press = .idle
                frozenUntil = time + 0.12
                return [.dragEnded]
            }
            return moveCursor(tip)

        case .suppressed:
            if pinch == nil { press = .idle }
            return []

        case let .twoHand(startSpan, fired):
            guard pinch == .index, otherPinch == .index, let other else {
                press = pinch == nil ? .idle : .suppressed
                return []
            }
            guard !fired else { return [] }
            let ratio = span(hand, other) / startSpan
            let gesture: Gesture
            if ratio > 1.35 {
                gesture = .spread
            } else if ratio < 0.7 {
                gesture = .squeeze
            } else {
                return []
            }
            press = .twoHand(startSpan: startSpan, fired: true)
            return settings.action(for: gesture) == .none ? [] : [.trigger(gesture)]
        }
    }

    private var twoHandEnabled: Bool {
        settings.action(for: .spread) != .none || settings.action(for: .squeeze) != .none
    }

    private var canStartTwoHand: Bool {
        guard twoHandEnabled else { return false }
        switch press {
        case .idle, .pending: return true
        default: return false
        }
    }

    private func span(_ a: HandFeatures, _ b: HandFeatures) -> Double {
        a.anchor.distance(to: b.anchor) / ((a.palm + b.palm) / 2)
    }

    private func updatePointer(_ hand: HandFeatures, _ tip: Vec2?) -> [GestureEvent] {
        let ratio = hand.pinches[.index] ?? 1
        let fast = handSpeed > fastSpeed
        if let last = lastIndexPinch, time > last.time, !fast, ratio < 0.45,
           (ratio - last.ratio) / (time - last.time) < -2.5 {
            frozenUntil = max(frozenUntil, time + 0.1)
        }
        lastIndexPinch = (time, ratio)

        let wasPointing = pointing
        let hovering = hand.pose == .point
            || (pointing && ratio < HandFeatures.hoverExit && (hand.extensions[.index] ?? 0) > 0.04)
        if hovering || (pointing && hand.tip == nil) {
            pointing = true
            lastPointing = time
        } else if time - lastPointing > pointingGrace {
            pointing = false
        }
        guard pointing, settings.isEnabled(.pointer) else { return [] }
        if !wasPointing {
            rebase = false
            offset = .zero
            velocity = .zero
            frozenUntil = 0
        }
        guard hovering || fast || tip == nil else { return [] }
        let middle = hand.pinches[.middle] ?? 1
        let aimingMiddle = !fast && middle < 0.35 && ratio > 0.45 && ratio > middle + 0.15
        guard fast || time >= frozenUntil, !aimingMiddle else {
            rebase = true
            velocity = .zero
            cursorState = .frozen
            return []
        }
        return moveCursor(tip)
    }

    private func updateScroll(_ hand: HandFeatures, _ delta: (value: Vec2, dt: Double)) -> [GestureEvent] {
        guard hand.pose == .twoFingers, settings.isEnabled(.twoFingers) else {
            twoFingersSince = nil
            return []
        }
        let since = twoFingersSince ?? time
        twoFingersSince = since
        guard time - since >= 0.12 else { return [] }
        let amount = delta.value * (700 * settings.scrollSpeed * (settings.naturalScroll ? 1 : -1))
        return amount.length < 0.3 ? [] : [.scroll(amount)]
    }

    private func updateSwipe(_ hand: HandFeatures, _ speed: Double) -> [GestureEvent] {
        if pointing {
            samples = []
            openSince = nil
            pendingDown = nil
            return []
        }
        if let since = pendingDown {
            if speed < 1.5 {
                pendingDown = nil
                return settings.action(for: .swipeDown) == .none ? [] : [.trigger(.swipeDown)]
            }
            if time - since > 0.4 { pendingDown = nil }
        }
        if !swipeArmed {
            samples = []
            if speed < 1.5 {
                let since = slowSince ?? time
                slowSince = since
                if time - since > 0.15, time - swipeFiredAt > 0.5 { swipeArmed = true }
            } else {
                slowSince = nil
            }
            return []
        }

        switch hand.pose {
        case .open:
            openSince = openSince ?? time
        case .other where openSince != nil && !pointing:
            break
        default:
            samples = []
            openSince = nil
            return []
        }
        guard let openSince, time - openSince > 0.25 else { return [] }
        samples.append(Sample(time: time, position: hand.center, open: hand.pose == .open))
        samples.removeAll { time - $0.time > swipeWindow }
        guard let first = samples.first(where: \.open) else { return [] }
        let opened = samples.filter(\.open).count
        guard opened * 3 >= samples.count * 2 else { return [] }

        let d = (hand.center - first.position) / (palm ?? hand.palm)
        let needed = 2.4 - 1.2 * settings.swipeSensitivity
        let gesture: Gesture
        if abs(d.x) > needed, abs(d.x) > 2.5 * abs(d.y) {
            gesture = d.x > 0 ? .swipeRight : .swipeLeft
        } else if abs(d.y) > needed, abs(d.y) > 2.5 * abs(d.x) {
            gesture = d.y > 0 ? .swipeUp : .swipeDown
        } else {
            return []
        }
        swipeArmed = false
        swipeFiredAt = time
        slowSince = nil
        samples = []
        if gesture == .swipeDown {
            pendingDown = time
            return []
        }
        return settings.action(for: gesture) == .none ? [] : [.trigger(gesture)]
    }

    private func updateHold(_ hand: HandFeatures) -> [GestureEvent] {
        guard let gesture = Self.heldGesture(hand.pose) else {
            if heldPose != nil, time - heldLastSeen > 0.12 {
                heldPose = nil
                heldLastFired = nil
            }
            return []
        }
        if heldPose != hand.pose {
            heldPose = hand.pose
            heldSince = time
            heldLastFired = nil
        }
        heldLastSeen = time

        let action = settings.action(for: gesture)
        guard action != .none else { return [] }
        if let fired = heldLastFired {
            guard action.repeats, time - fired >= 0.14 else { return [] }
        } else {
            guard time - heldSince >= (gesture == .fist ? 0.45 : 0.35) else { return [] }
        }
        heldLastFired = time
        return [.trigger(gesture)]
    }

    private static func heldGesture(_ pose: Pose) -> Gesture? {
        switch pose {
        case .fist: .fist
        case .thumbUp: .thumbUp
        case .thumbDown: .thumbDown
        case .thumbLeft: .thumbLeft
        case .thumbRight: .thumbRight
        default: nil
        }
    }
}
