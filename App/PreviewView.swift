import AVFoundation
import HandCore
import SwiftUI

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let connection = (view.layer as? AVCaptureVideoPreviewLayer)?.connection,
              connection.isVideoMirroringSupported, !connection.isVideoMirrored
        else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}

struct SkeletonView: View {
    let status: PipelineStatus
    let area: Double

    var body: some View {
        Canvas { context, size in
            func place(_ p: Vec2) -> CGPoint {
                CGPoint(x: p.x / status.aspect * size.width, y: (1 - p.y) * size.height)
            }
            let inset = (1 - area) / 2
            let zone = CGRect(x: size.width * inset, y: size.height * inset, width: size.width * area, height: size.height * area)
            context.stroke(Path(roundedRect: zone, cornerRadius: 6), with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            let color: Color = status.engaged ? .green : .white
            for hand in status.hands {
                var path = Path()
                for (a, b) in Joint.bones {
                    guard let pa = hand.points[a], let pb = hand.points[b] else { continue }
                    path.move(to: place(pa))
                    path.addLine(to: place(pb))
                }
                context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 2)
                if let thumb = hand.points[.thumbTip], let index = hand.points[.indexTip] {
                    let c = place((thumb + index) / 2)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.yellow))
                }
                for p in hand.points.values {
                    let c = place(p)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(color))
                }
            }
        }
    }
}

struct PreviewTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveStatus

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.black
                if model.isRunning {
                    CameraPreview(session: model.camera.session)
                    SkeletonView(status: live.status, area: model.settings.pointerArea)
                } else {
                    Text("Apagado. Di «Hey Siri, Hands on»").foregroundStyle(.secondary)
                }
            }
            .aspectRatio(live.status.aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            LabeledContent("Estado", value: live.status.engaged ? "Activado" : "Esperando mano abierta")
            LabeledContent("Pose", value: Labels.name(live.status.pose))
            LabeledContent("Última acción", value: live.lastAction ?? "—")

            Picker("Cámara", selection: $model.cameraID) {
                Text("Automática").tag(String?.none)
                ForEach(model.cameras, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(String?.some(device.uniqueID))
                }
            }
            if AVCaptureDevice.reactionEffectGesturesEnabled {
                Label("Las reacciones de video de macOS están activas. Desactívalas en el menú de video para que no tapen la imagen.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
