import AppKit
import ApplicationServices
import HandCore

final class SystemController {
    private let source = CGEventSource(stateID: .hidSystemState)
    private let slowQueue = DispatchQueue(label: "handtracking.actions")
    private let output = DispatchQueue(label: "handtracking.output", qos: .userInteractive)
    private var smoother: DispatchSourceTimer?
    private var target: CGPoint?
    private var shown: CGPoint?
    private var overview: SystemAction?
    private var clickOrigin: CGPoint?
    private var dragging = false
    private var scrollRemainder = Vec2.zero

    private let keyLock = NSLock()
    private var lastKeyPost = -10.0

    var now: Double { ProcessInfo.processInfo.systemUptime }

    func isUserTyping(window: Double = 0.8) -> Bool {
        let elapsed = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        guard elapsed < window else { return false }
        let pressedAt = now - elapsed
        return keyLock.withLock { pressedAt > lastKeyPost + 0.25 || pressedAt < lastKeyPost - 0.05 }
    }

    func perform(_ event: GestureEvent, settings: GestureSettings) {
        output.async { self.handle(event, settings: settings) }
    }

    func flush() { output.sync {} }

    private func handle(_ event: GestureEvent, settings: GestureSettings) {
        switch event {
        case .engaged, .disengaged:
            scrollRemainder = .zero
            stopSmoothing()
        case let .moveTo(target):
            move(to: target)
        case let .click(count):
            settle()
            click(.left, count: count)
        case .dragBegan:
            settle()
            dragging = true
            postMouse(.leftMouseDown, at: cursor, button: .left, clickState: 1)
        case .dragEnded:
            settle()
            guard dragging else { return }
            dragging = false
            postMouse(.leftMouseUp, at: cursor, button: .left, clickState: 1)
        case let .scroll(amount):
            scroll(amount)
        case let .trigger(gesture):
            settle()
            run(settings.action(for: gesture))
        }
    }

    func run(_ action: SystemAction) {
        switch action {
        case .none: break
        case .rightClick: click(.right, count: 1)
        case .middleClick: click(.center, count: 1)
        case .spaceLeft: hotKey(79, fallback: (123, [.maskControl, .maskSecondaryFn]))
        case .spaceRight: hotKey(81, fallback: (124, [.maskControl, .maskSecondaryFn]))
        case .missionControl, .appExpose: toggleOverview(action)
        case .showDesktop: hotKey(36, fallback: (103, [.maskSecondaryFn]))
        case .switchApp: key(48, [.maskCommand])
        case .playPause: media(16)
        case .nextTrack: media(17)
        case .previousTrack: media(18)
        case .volumeUp: media(0)
        case .volumeDown: media(1)
        case .brightnessUp: media(2)
        case .brightnessDown: media(3)
        case .mute: media(7)
        case .enterFullScreen: fullScreen { _ in true }
        case .exitFullScreen: fullScreen { _ in false }
        case .toggleFullScreen: fullScreen { !$0 }
        case .videoFullScreen: key(3, [])
        case .browserBack: key(33, [.maskCommand])
        case .browserForward: key(30, [.maskCommand])
        case .escape: key(53, [])
        }
    }

    private var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func move(to goal: Vec2) {
        let bounds = display(containing: cursor)
        target = CGPoint(
            x: bounds.minX + goal.x * (bounds.width - 1),
            y: bounds.minY + (1 - goal.y) * (bounds.height - 1)
        )
        guard smoother == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: output)
        timer.schedule(deadline: .now(), repeating: 1.0 / 120, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.step() }
        smoother = timer
        timer.resume()
    }

    private func step() {
        guard let target else { return stopSmoothing() }
        let from = shown ?? cursor
        let d = CGPoint(x: target.x - from.x, y: target.y - from.y)
        if hypot(d.x, d.y) < 0.5 {
            postMove(target, from: from)
            stopSmoothing()
            return
        }
        let next = CGPoint(x: from.x + d.x * 0.35, y: from.y + d.y * 0.35)
        shown = next
        postMove(next, from: from)
    }

    private func settle() {
        if let target { postMove(target, from: shown ?? cursor) }
        stopSmoothing()
    }

    private func stopSmoothing() {
        smoother?.cancel()
        smoother = nil
        target = nil
        shown = nil
    }

    private func postMove(_ point: CGPoint, from base: CGPoint) {
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: dragging ? .leftMouseDragged : .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.setDoubleValueField(.mouseEventDeltaX, value: point.x - base.x)
        event?.setDoubleValueField(.mouseEventDeltaY, value: point.y - base.y)
        event?.post(tap: .cghidEventTap)
    }

    private func display(containing point: CGPoint) -> CGRect {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).map(CGDisplayBounds).first { $0.contains(point) }
            ?? CGDisplayBounds(CGMainDisplayID())
    }

    private func click(_ button: CGMouseButton, count: Int) {
        var point = cursor
        if count > 1, let clickOrigin, hypot(clickOrigin.x - point.x, clickOrigin.y - point.y) < 24 {
            point = clickOrigin
        }
        clickOrigin = point
        let types: (CGEventType, CGEventType) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
        postMouse(types.0, at: point, button: button, clickState: count)
        postMouse(types.1, at: point, button: button, clickState: count)
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event?.post(tap: .cghidEventTap)
    }

    private func scroll(_ amount: Vec2) {
        let total = scrollRemainder + Vec2(amount.x, -amount.y)
        let dx = total.x.rounded(.towardZero)
        let dy = total.y.rounded(.towardZero)
        scrollRemainder = Vec2(total.x - dx, total.y - dy)
        guard dx != 0 || dy != 0 else { return }
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        keyLock.withLock { lastKeyPost = now }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func toggleOverview(_ action: SystemAction) {
        let open = overview.flatMap { isOverviewVisible ? $0 : nil }
        overview = open == nil ? action : nil
        switch open ?? action {
        case .appExpose: hotKey(33, fallback: (125, [.maskControl, .maskSecondaryFn]))
        default: hotKey(32, fallback: (126, [.maskControl, .maskSecondaryFn]))
        }
    }

    private var isOverviewVisible: Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let main = CGDisplayBounds(CGMainDisplayID())
        return windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock",
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 18,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
            else { return false }
            return bounds.width >= main.width && bounds.height >= main.height
        }
    }

    private func hotKey(_ id: Int, fallback: (CGKeyCode, CGEventFlags)) {
        let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        let value = (all?[String(id)] as? [String: Any])?["value"] as? [String: Any]
        if let parameters = value?["parameters"] as? [Int], parameters.count == 3, parameters[1] != 65535 {
            key(CGKeyCode(parameters[1]), CGEventFlags(rawValue: UInt64(parameters[2])))
        } else {
            key(fallback.0, fallback.1)
        }
    }

    private func media(_ code: Int) {
        DispatchQueue.main.async {
            for state in [0xA, 0xB] {
                NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: (code << 16) | (state << 8),
                    data2: -1
                )?.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }

    private func fullScreen(_ desired: @escaping (Bool) -> Bool) {
        slowQueue.async { [self] in
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
                  let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
            else {
                key(3, [.maskControl, .maskCommand])
                return
            }
            let window = ref as! AXUIElement
            var state: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &state)
            let current = (state as? Bool) ?? false
            let target = desired(current)
            guard target != current else { return }
            let result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, target as CFBoolean)
            if result != .success { key(3, [.maskControl, .maskCommand]) }
        }
    }
}
