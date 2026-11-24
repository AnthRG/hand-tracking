import Foundation
import Testing
@testable import HandCore

@Test func engagesOnlyAfterHoldingOpenHand() {
    let rig = Rig()
    #expect(rig.run(.open, 0.4).isEmpty)
    #expect(rig.run(.open, 0.4) == [.engaged])
}

@Test func doesNotEngageWhileMoving() {
    let rig = Rig()
    #expect(rig.run(.open, 1, move: Vec2(0.6, 0)).isEmpty)
}

@Test func ignoresEverythingWhenNotEngaged() {
    let rig = Rig()
    rig.run(.point, 0.5, move: Vec2(0.2, 0))
    rig.run(.indexPinch, 0.2)
    rig.run(.fist, 1)
    rig.run(.thumbUp, 1)
    #expect(rig.events.isEmpty)
}

@Test func pointingMovesCursorInHandDirection() {
    let rig = Rig()
    rig.engage()
    rig.run(.point, 0.2)
    let right = rig.run(.point, 0.5, move: Vec2(0.15, 0)).total
    #expect(right.x > 0.1 && abs(right.y) < 0.01)
    rig.run(.point, 0.3)
    let up = rig.run(.point, 0.5, move: Vec2(0, 0.15)).total
    #expect(up.y > 0.18 && abs(up.x) < 0.02)
}

@Test func openHandDoesNotMoveCursor() {
    let rig = Rig()
    rig.engage()
    #expect(rig.run(.open, 1, move: Vec2(0.15, 0)).moves.isEmpty)
}

@Test func jitterBarelyMovesCursor() {
    let rig = Rig()
    rig.engage()
    rig.run(.point, 0.3)
    var seen: [Double] = []
    for i in 0..<60 {
        rig.position += Vec2(i % 2 == 0 ? 0.002 : -0.002, 0)
        seen += rig.run(.point, rig.dt).moves.map(\.x)
    }
    #expect((seen.max() ?? 0) - (seen.min() ?? 0) < 0.004)
}

@Test func quickPinchClicksOnce() {
    let rig = Rig()
    rig.engage()
    rig.run(.point, 0.3)
    rig.run(.indexPinch, 0.15)
    rig.run(.point, 0.3)
    #expect(rig.events.withoutMoves == [.click(count: 1)])
}

@Test func twoQuickPinchesDoubleClickAndThirdStartsOver() {
    let rig = Rig()
    rig.engage()
    for _ in 0..<3 {
        rig.run(.indexPinch, 0.13)
        rig.run(.point, 0.16)
    }
    #expect(rig.events.withoutMoves == [.click(count: 1), .click(count: 2), .click(count: 1)])
}

@Test func singleFramePinchIsIgnored() {
    let rig = Rig()
    rig.engage()
    rig.run(.point, 0.2)
    rig.run(.indexPinch, rig.dt)
    rig.run(.point, 0.3)
    #expect(rig.events.withoutMoves.isEmpty)
}

@Test func pinchAndMoveDrags() throws {
    let rig = Rig()
    rig.engage()
    rig.run(.indexPinch, 0.15)
    rig.run(.indexPinch, 0.6, move: Vec2(0.2, 0))
    rig.run(.point, 0.2)
    let began = try #require(rig.events.firstIndex(of: .dragBegan))
    let ended = try #require(rig.events.firstIndex(of: .dragEnded))
    #expect(began < ended)
    #expect(Array(rig.events[began...ended]).total.x > 0.1)
    #expect(!rig.events.contains(.click(count: 1)))
}

@Test func losingHandMidDragReleasesButton() {
    let rig = Rig()
    rig.engage()
    rig.run(.indexPinch, 0.7)
    #expect(rig.events.withoutMoves == [.dragBegan])
    let lost = rig.run(nil, 0.7)
    #expect(lost == [.dragEnded, .disengaged])
}

@Test func briefOcclusionKeepsDrag() {
    let rig = Rig()
    rig.engage()
    rig.run(.indexPinch, 0.7)
    rig.run(nil, 0.15)
    rig.run(.indexPinch, 0.2)
    #expect(!rig.events.contains(.dragEnded))
}

@Test func resetAndTypingReleaseButton() {
    let a = Rig()
    a.engage()
    a.run(.indexPinch, 0.7)
    #expect(a.engine.reset() == [.dragEnded, .disengaged])

    let b = Rig()
    b.engage()
    b.run(.indexPinch, 0.7)
    #expect(b.run(.indexPinch, 0.1, typing: true) == [.dragEnded, .disengaged])
    #expect(b.run(.open, 1, typing: true).isEmpty)
}

@Test func middlePinchRightClicksOnce() {
    let rig = Rig()
    rig.engage()
    rig.run(.middlePinch, 0.5)
    rig.run(.open, 0.3)
    #expect(rig.events == [.trigger(.middlePinch)])
}

@Test func twoFingersScrollNaturally() {
    let rig = Rig()
    rig.engage()
    rig.run(.twoFingers, 0.3)
    let up = rig.run(.twoFingers, 0.5, move: Vec2(0, 0.2)).scrolls.reduce(.zero, +)
    #expect(up.y > 100)
    #expect(rig.events.moves.isEmpty)
}

@Test(arguments: [
    (Vec2(0.5, 0), Gesture.swipeRight), (Vec2(-0.5, 0), .swipeLeft), (Vec2(0, 0.5), .swipeUp), (Vec2(0, -0.5), .swipeDown),
])
func swipeFiresOnceAndIgnoresReturn(move: Vec2, gesture: Gesture) {
    let rig = Rig(.allOn)
    rig.engage()
    rig.run(.open, 0.25, move: move)
    rig.run(.open, 0.1)
    rig.run(.open, 0.25, move: move * -1)
    rig.run(.open, 0.2)
    #expect(rig.events.triggers == [gesture])
}

@Test func swipeRearmsAfterPause() {
    let rig = Rig()
    rig.engage()
    rig.run(.open, 0.25, move: Vec2(0.5, 0))
    rig.run(.open, 0.8)
    rig.run(.open, 0.25, move: Vec2(-0.5, 0))
    #expect(rig.events.triggers == [.swipeRight, .swipeLeft])
}

@Test func slowOpenHandMoveIsNotSwipe() {
    let rig = Rig()
    rig.engage()
    rig.run(.open, 1.5, move: Vec2(0.5, 0))
    #expect(rig.events.triggers.isEmpty)
}

@Test func fistTogglesOncePerHold() {
    let rig = Rig(.allOn)
    rig.engage()
    rig.run(.fist, 2)
    #expect(rig.events.triggers == [.fist])
    rig.run(.open, 0.4)
    rig.run(.fist, 1)
    #expect(rig.events.triggers == [.fist, .fist])
}

@Test func briefFistDoesNothing() {
    let rig = Rig()
    rig.engage()
    rig.run(.fist, 0.25)
    rig.run(.open, 0.4)
    #expect(rig.events.isEmpty)
}

@Test func thumbVolumeRepeatsAndSkipDoesNot() {
    let rig = Rig(.allOn)
    rig.engage()
    rig.run(.thumbUp, 1.5)
    #expect(rig.events.triggers.count >= 6)
    #expect(Set(rig.events.triggers) == [.thumbUp])
    rig.events = []
    rig.run(.open, 0.3)
    rig.run(.thumbRight, 1.5)
    #expect(rig.events.triggers == [.thumbRight])
}

@Test(arguments: [(0.5, Gesture.spread), (-0.35, .squeeze)])
func twoHandPinchZoomsWithoutClicking(shift: Double, gesture: Gesture) {
    let rig = Rig(.allOn)
    rig.position = Vec2(0.5, 0.4)
    rig.run(.open, 0.8)
    rig.events = []
    let base = Vec2(1.1, 0.4)
    rig.run(.indexPinch, 0.2, second: (.indexPinch, { _ in base }))
    rig.run(.indexPinch, 0.8, second: (.indexPinch, { base + Vec2(shift * $0, 0) }))
    let end = base + Vec2(shift, 0)
    rig.run(.open, 0.4, second: (.open, { _ in end }))
    #expect(rig.events.withoutMoves == [.trigger(gesture)])
}

@Test func disabledAndUnboundGesturesStaySilent() {
    var settings = GestureSettings()
    settings.disabled = [.fist, .indexPinch, .pointer]
    settings.bindings[.thumbUp] = SystemAction.none
    settings.bindings[.spread] = SystemAction.none
    settings.bindings[.squeeze] = SystemAction.none
    let rig = Rig(settings)
    rig.engage()
    rig.run(.fist, 1)
    rig.run(.thumbUp, 1)
    rig.run(.point, 0.5, move: Vec2(0.2, 0))
    rig.run(.indexPinch, 0.7)
    rig.run(.point, 0.2)
    #expect(rig.events.isEmpty)
}

@Test func idleHandDisengages() {
    let rig = Rig()
    rig.engage()
    #expect(rig.run(.open, 11).contains(.disengaged) || rig.events.contains(.disengaged))
}

@Test func settingsSurviveRoundTripAndMissingKeys() throws {
    var s = GestureSettings()
    s.bindings[.fist] = .mute
    s.disabled = [.swipeUp]
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(GestureSettings.self, from: data) == s)
    #expect(try JSONDecoder().decode(GestureSettings.self, from: Data("{}".utf8)) == GestureSettings())
}

@Test func cursorGoesWhereTheTipIs() throws {
    let rig = Rig()
    rig.engage()
    let last = try #require(rig.run(.point, 0.8).moves.last)
    let tip = try #require(HandFeatures(makeHand(.point, at: rig.position))?.tip)
    #expect(abs(last.x - ((tip.x / (16.0 / 9.0) - 0.5) / 0.6 + 0.5)) < 0.01)
    #expect(abs(last.y - ((tip.y - 0.5) / 0.6 + 0.5)) < 0.01)
}

@Test func cursorStaysInsideScreen() {
    let rig = Rig()
    rig.engage()
    let moves = rig.run(.point, 1, move: Vec2(1.5, 0.8)).moves
    #expect(moves.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    #expect(moves.last?.x == 1)
}

@Test func clickDoesNotMoveCursor() throws {
    let rig = Rig()
    rig.engage()
    let before = try #require(rig.run(.point, 0.8).moves.last)
    #expect(rig.run(.indexPinch, 0.2).moves.allSatisfy { $0.distance(to: before) < 0.02 })
}

@Test func hoveringNeverClicksOrTriggers() {
    let rig = Rig()
    rig.engage()
    rig.run(.point, 1, move: Vec2(0.3, 0.1))
    rig.run(.point, 0.2, move: Vec2(-0.5, 0))
    #expect(rig.events.withoutMoves.isEmpty)
}

@Test func advancedGesturesAreOffByDefault() {
    let rig = Rig()
    rig.engage()
    for shape in [Shape.fist, .thumbUp, .thumbDown, .thumbLeft, .thumbRight] { rig.run(shape, 1) }
    #expect(rig.events.isEmpty)
}

private func sweep(_ rig: Rig, frames: Int = 20, step: Double = 0.02, hand: (Int) -> Hand?) -> [GestureEvent] {
    var out: [GestureEvent] = []
    for i in 0..<frames {
        rig.time += rig.dt
        rig.position += Vec2(step, 0)
        out += rig.engine.update(HandFrame(time: rig.time, hands: [hand(i)].compactMap { $0 }))
    }
    return out
}

@Test func shortDropoutMidMoveCoastsWithoutJump() throws {
    let rig = Rig()
    rig.position = Vec2(0.5, 0.4)
    rig.engage()
    rig.run(.point, 0.3)
    let moves = sweep(rig) { (9...11).contains($0) ? nil : makeHand(.point, at: rig.position) }.moves
    #expect(moves.count >= 19)
    let steps = zip(moves.dropFirst(), moves).map { $0.x - $1.x }
    #expect(steps.allSatisfy { $0 > -0.005 && $0 < 0.06 })
}

@Test func newIdentityMidMoveKeepsMoving() {
    let rig = Rig()
    rig.position = Vec2(0.5, 0.4)
    rig.engage()
    rig.run(.point, 0.3)
    let events = sweep(rig) { makeHand(.point, at: rig.position, id: $0 < 10 ? 1 : 2) }
    #expect(events.moves.count >= 19)
    #expect(!events.contains(.disengaged))
}

@Test func poseFlickerMidMoveKeepsMoving() {
    let rig = Rig()
    rig.position = Vec2(0.5, 0.4)
    rig.engage()
    rig.run(.point, 0.3)
    let events = sweep(rig) { makeHand([7, 8, 13].contains($0) ? .half : .point, at: rig.position) }
    #expect(events.moves.count >= 18)
    #expect(events.withoutMoves.isEmpty)
}

@Test func pinchNoiseMidMoveNeitherFreezesNorClicks() {
    let rig = Rig()
    rig.position = Vec2(0.5, 0.4)
    rig.engage()
    rig.run(.point, 0.3)
    let events = sweep(rig) { makeHand([6, 10, 11, 15].contains($0) ? .indexPinch : .point, at: rig.position) }
    #expect(events.moves.count >= 18)
    #expect(events.withoutMoves.isEmpty)
}

@Test func coastingStopsAfterLongDropout() {
    let rig = Rig()
    rig.position = Vec2(0.5, 0.4)
    rig.engage()
    rig.run(.point, 0.3)
    _ = sweep(rig) { _ in makeHand(.point, at: rig.position) }
    #expect(rig.run(nil, 0.5).moves.count <= 5)
}

@Test func secondHandIsNotAdoptedWhenPrimaryVanishes() {
    let rig = Rig()
    rig.position = Vec2(0.7, 0.4)
    rig.engage()
    let near: (Double) -> Vec2 = { _ in Vec2(0.9, 0.4) }
    rig.run(.point, 0.3, second: (.point, near))
    #expect(rig.run(nil, 0.8, second: (.point, near)).contains(.disengaged))
}

@Test func loweringHandOutOfFrameIsNotSwipeDown() {
    let rig = Rig()
    rig.engage()
    rig.run(.open, 0.25, move: Vec2(0, -0.5))
    rig.run(nil, 0.8)
    #expect(rig.events.triggers.isEmpty)
}

@Test func verticalSwipesAreOnByDefault() {
    let rig = Rig()
    rig.engage()
    rig.run(.open, 0.25, move: Vec2(0, 0.5))
    rig.run(.open, 0.9)
    rig.run(.open, 0.25, move: Vec2(0, -0.5))
    rig.run(.open, 0.4)
    #expect(rig.events.triggers == [.swipeUp, .swipeDown])
}
