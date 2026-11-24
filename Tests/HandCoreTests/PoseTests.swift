import Testing
@testable import HandCore

@Test(arguments: [
    (Shape.open, Pose.open), (.point, .point), (.fist, .fist), (.half, .other), (.twoFingers, .twoFingers), (.indexPinch, .point), (.middlePinch, .other),
    (.thumbUp, .thumbUp), (.thumbDown, .thumbDown), (.thumbLeft, .thumbLeft), (.thumbRight, .thumbRight),
])
func classifiesPose(shape: Shape, pose: Pose) throws {
    let f = try #require(HandFeatures(makeHand(shape, at: Vec2(0.5, 0.5))))
    #expect(f.pose == pose)
}

@Test(arguments: [0.06, 0.12, 0.4])
func poseIsScaleInvariant(scale: Double) throws {
    let f = try #require(HandFeatures(makeHand(.open, at: Vec2(0.5, 0.2), scale: scale)))
    #expect(f.pose == .open)
}

@Test func incompleteHandIsRejected() {
    #expect(HandFeatures(Hand(points: [.wrist: .zero, .indexTip: Vec2(0, 1)])) == nil)
}

@Test func trackerKeepsIdentityWhenOrderSwaps() {
    let tracker = HandTracker()
    let a = makeHand(.open, at: Vec2(0.3, 0.4)).points
    let b = makeHand(.open, at: Vec2(1.3, 0.4)).points
    let first = tracker.update(observations: [a, b], time: 0)
    let second = tracker.update(observations: [b, a], time: 0.033)
    #expect(first.hands[0].id == second.hands[1].id)
    #expect(first.hands[1].id == second.hands[0].id)
}

@Test func trackerRemembersMissingJointBriefly() {
    let tracker = HandTracker()
    var points = makeHand(.open, at: Vec2(0.3, 0.4)).points
    _ = tracker.update(observations: [points], time: 0)
    points[.indexTip] = nil
    #expect(tracker.update(observations: [points], time: 0.05).hands[0].points[.indexTip] != nil)
    #expect(tracker.update(observations: [points], time: 0.25).hands[0].points[.indexTip] == nil)
}
