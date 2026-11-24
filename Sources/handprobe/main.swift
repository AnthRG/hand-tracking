import CoreGraphics
import Foundation
import HandCore
import HandVision
import ImageIO

func number(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "-" }

let detector = HandDetector()
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--trace" {
    try summarizeTrace(CommandLine.arguments[2])
    exit(0)
}
print("revision \(HandDetector.revision)")
for path in CommandLine.arguments.dropFirst() {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        print("\(path): unreadable")
        continue
    }
    let start = Date()
    let hands = try detector.detect(image)
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print("\((path as NSString).lastPathComponent) \(image.width)x\(image.height) hands=\(hands.count) \(ms)ms")
    for points in hands {
        guard let f = HandFeatures(Hand(points: points)) else {
            print("  joints=\(points.count) incomplete")
            continue
        }
        let hint = TrackingHint(center: f.center, palm: f.palm)
        let cropped = try detector.detect(image, hint: hint, forceRegion: true)
            .compactMap { HandFeatures(Hand(points: $0)) }
            .min { $0.center.distance(to: f.center) < $1.center.distance(to: f.center) }
        print("  region offset=\(number(cropped.map { $0.center.distance(to: f.center) / f.palm })) palm ratio=\(number(cropped.map { $0.palm / f.palm }))")
        let ext = Finger.allCases.map { number(f.extensions[$0]) }.joined(separator: " ")
        let pinch = Finger.allCases.map { number(f.pinches[$0]) }.joined(separator: " ")
        print("  pose=\(f.pose) joints=\(points.count) palm=\(number(f.palm)) ext=[\(ext)] pinch=[\(pinch)] reach=\(number(f.thumbReach))")
    }
}
