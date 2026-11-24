import AVFoundation

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let frameQueue = DispatchQueue(label: "handtracking.frames", qos: .userInteractive)
    var onFrame: ((CVPixelBuffer, Double) -> Void)?
    var onStopped: ((String?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "handtracking.session")
    private let output = AVCaptureVideoDataOutput()
    private var observers: [NSObjectProtocol] = []

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func defaultDevice(id: String?) -> AVCaptureDevice? {
        let all = devices()
        if let id, let match = all.first(where: { $0.uniqueID == id }) { return match }
        return all.first { $0.deviceType == .builtInWideAngleCamera } ?? all.first
    }

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.onStopped?(error?.localizedDescription ?? "La cámara se detuvo")
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.onStopped?("Otra app interrumpió la cámara")
        })
        observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] note in
            guard let self, let device = note.object as? AVCaptureDevice else { return }
            let current = (session.inputs.first as? AVCaptureDeviceInput)?.device.uniqueID
            if device.uniqueID == current { onStopped?("La cámara se desconectó") }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start(deviceID: String?) {
        sessionQueue.async { [self] in
            do {
                try configure(deviceID: deviceID)
                if !session.isRunning { session.startRunning() }
            } catch {
                onStopped?(error.localizedDescription)
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private struct CameraError: LocalizedError {
        let errorDescription: String?
    }

    private func configure(deviceID: String?) throws {
        guard let device = Self.defaultDevice(id: deviceID) else {
            throw CameraError(errorDescription: "No se encontró ninguna cámara")
        }
        if device.activeFormat.isCenterStageSupported || AVCaptureDevice.isCenterStageEnabled {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError(errorDescription: "No se pudo abrir \(device.localizedName)")
        }
        session.addInput(input)
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high

        let target = CMTime(value: 1, timescale: 30)
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        }
        if supported, (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = target
            device.activeVideoMaxFrameDuration = target
            device.unlockForConfiguration()
        }

        if session.outputs.isEmpty {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            output.setSampleBufferDelegate(self, queue: frameQueue)
            guard session.canAddOutput(output) else {
                throw CameraError(errorDescription: "No se pudo leer el video de la cámara")
            }
            session.addOutput(output)
        }
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
    }
}
