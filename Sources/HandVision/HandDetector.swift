import CoreGraphics
import CoreVideo
import HandCore
import Vision

public final class HandDetector {
    private let request: VNDetectHumanHandPoseRequest
    public var minConfidence: Float = 0.3

    public static var revision: Int { VNDetectHumanHandPoseRequest.currentRevision }

    public init() {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
    }

    public func detect(_ buffer: CVPixelBuffer, hint: TrackingHint? = nil) throws -> [[HandCore.Joint: Vec2]] {
        let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
        return try run(VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up), aspect: aspect, hint: hint)
    }

    public func detect(_ image: CGImage, hint: TrackingHint? = nil, forceRegion: Bool = false) throws -> [[HandCore.Joint: Vec2]] {
        let aspect = Double(image.width) / Double(image.height)
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        if forceRegion, let hint { return try perform(handler, aspect: aspect, region: Self.region(hint, aspect: aspect)) }
        return try run(handler, aspect: aspect, hint: hint)
    }

    private func run(_ handler: VNImageRequestHandler, aspect: Double, hint: TrackingHint?) throws -> [[HandCore.Joint: Vec2]] {
        let found = try perform(handler, aspect: aspect, region: Self.full)
        guard let hint else { return found }
        let tracked = found.contains { points in
            guard points[.thumbTip] != nil, points[.indexTip] != nil, let p = points[.middleMCP] else { return false }
            return p.distance(to: hint.center) < 0.4
        }
        if tracked { return found }
        let retry = try perform(handler, aspect: aspect, region: Self.region(hint, aspect: aspect))
        guard let best = retry.max(by: { $0.count < $1.count }), let p = best[.middleMCP] ?? best[.wrist] else { return found }
        let others = found.filter { points in
            guard let q = points[.middleMCP] ?? points[.wrist] else { return false }
            return q.distance(to: p) > 1.5 * hint.palm
        }
        return others + [best]
    }

    private static let full = CGRect(x: 0, y: 0, width: 1, height: 1)

    private static func region(_ hint: TrackingHint, aspect: Double) -> CGRect {
        let half = max(hint.palm * 3, 0.2)
        let x = 1 - hint.center.x / aspect
        return CGRect(x: x - half / aspect, y: hint.center.y - half, width: 2 * half / aspect, height: 2 * half)
            .intersection(full)
    }

    private func perform(_ handler: VNImageRequestHandler, aspect: Double, region: CGRect) throws -> [[HandCore.Joint: Vec2]] {
        guard !region.isNull, region.width > 0.05, region.height > 0.05 else { return [] }
        request.regionOfInterest = region
        try handler.perform([request])
        return try (request.results ?? []).map { observation in
            let recognized = try observation.recognizedPoints(.all)
            var points: [HandCore.Joint: Vec2] = [:]
            for (joint, name) in Self.names {
                guard let p = recognized[name], p.confidence >= minConfidence else { continue }
                let x = region.minX + p.location.x * region.width
                let y = region.minY + p.location.y * region.height
                points[joint] = Vec2((1 - Double(x)) * aspect, Double(y))
            }
            return points
        }
    }

    private static let names: [(HandCore.Joint, VNHumanHandPoseObservation.JointName)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]
}
