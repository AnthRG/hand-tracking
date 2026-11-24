public enum Gesture: String, Sendable, CaseIterable, Codable, CodingKeyRepresentable {
    case pointer, indexPinch, twoFingers
    case middlePinch
    case swipeLeft, swipeRight, swipeUp, swipeDown
    case fist
    case thumbUp, thumbDown, thumbLeft, thumbRight
    case spread, squeeze

    public var isBindable: Bool {
        switch self {
        case .pointer, .indexPinch, .twoFingers: false
        default: true
        }
    }
}

public enum SystemAction: String, Sendable, CaseIterable, Codable {
    case none
    case rightClick, middleClick
    case spaceLeft, spaceRight, missionControl, appExpose, showDesktop, switchApp
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    case enterFullScreen, exitFullScreen, toggleFullScreen, videoFullScreen
    case browserBack, browserForward, escape

    public var repeats: Bool {
        switch self {
        case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown: true
        default: false
        }
    }
}

public struct GestureSettings: Sendable, Codable, Equatable {
    public var pointerArea = 0.6
    public var smoothing = 0.5
    public var scrollSpeed = 1.0
    public var naturalScroll = true
    public var pinchSensitivity = 0.5
    public var swipeSensitivity = 0.5
    public var engageHold = 0.6
    public var disabled: Set<Gesture> = Self.defaultDisabled
    public var bindings: [Gesture: SystemAction] = Self.defaultBindings

    public init() {}

    public static let defaultDisabled: Set<Gesture> = [
        .fist, .thumbUp, .thumbDown, .thumbLeft, .thumbRight, .spread, .squeeze,
    ]

    public static let defaultBindings: [Gesture: SystemAction] = [
        .middlePinch: .rightClick,
        .swipeLeft: .spaceRight,
        .swipeRight: .spaceLeft,
        .swipeUp: .missionControl,
        .swipeDown: .appExpose,
        .fist: .playPause,
        .thumbRight: .nextTrack,
        .thumbLeft: .previousTrack,
        .thumbUp: .volumeUp,
        .thumbDown: .volumeDown,
        .spread: .enterFullScreen,
        .squeeze: .exitFullScreen,
    ]

    public func isEnabled(_ gesture: Gesture) -> Bool { !disabled.contains(gesture) }

    public func action(for gesture: Gesture) -> SystemAction {
        isEnabled(gesture) ? (bindings[gesture] ?? .none) : .none
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureSettings()
        pointerArea = try c.decodeIfPresent(Double.self, forKey: .pointerArea) ?? d.pointerArea
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? d.smoothing
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? d.scrollSpeed
        naturalScroll = try c.decodeIfPresent(Bool.self, forKey: .naturalScroll) ?? d.naturalScroll
        pinchSensitivity = try c.decodeIfPresent(Double.self, forKey: .pinchSensitivity) ?? d.pinchSensitivity
        swipeSensitivity = try c.decodeIfPresent(Double.self, forKey: .swipeSensitivity) ?? d.swipeSensitivity
        engageHold = try c.decodeIfPresent(Double.self, forKey: .engageHold) ?? d.engageHold
        disabled = try c.decodeIfPresent(Set<Gesture>.self, forKey: .disabled) ?? d.disabled
        bindings = try c.decodeIfPresent([Gesture: SystemAction].self, forKey: .bindings) ?? d.bindings
    }
}
