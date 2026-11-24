import AppKit
import AVFoundation
import Carbon.HIToolbox
import HandCore
import SwiftUI

@MainActor
final class LiveStatus: ObservableObject {
    @Published var status = PipelineStatus()
    @Published var lastAction: String?
    @Published var lastGesture: HandGesture?
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var isRunning = false { didSet { remote.publish(isRunning) } }
    @Published private(set) var engaged = false
    @Published private(set) var error: String?
    @Published private(set) var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published var showHUD: Bool { didSet { defaults.set(showHUD, forKey: "showHUD"); refreshPanels() } }
    @Published var showCorner: Bool { didSet { defaults.set(showCorner, forKey: "showCorner"); refreshPanels() } }
    @Published var showLegend: Bool { didSet { defaults.set(showLegend, forKey: "showLegend"); refreshSoon() } }
    @Published var corner: Corner { didSet { defaults.set(corner.rawValue, forKey: "corner"); refreshPanels() } }
    @Published var cameraID: String? {
        didSet {
            defaults.set(cameraID, forKey: "cameraID")
            if isRunning { camera.start(deviceID: cameraID) }
        }
    }
    @Published var settings: GestureSettings {
        didSet {
            pipeline.apply(settings)
            refreshSoon()
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings.v2") }
        }
    }

    let camera = CameraCapture()
    let live = LiveStatus()
    private let pipeline: Pipeline
    private let defaults = UserDefaults.standard
    private let hud = HUDController()
    private let cornerPanel = CornerPanelController()
    private var hotKey: HotKey?
    private let remote = RemoteControl { command in
        MainActor.assumeIsolated {
            switch command {
            case .on: AppModel.shared.start()
            case .off: AppModel.shared.stop()
            }
        }
    }
    private var timer: Timer?
    private var actionClear: DispatchWorkItem?

    private init() {
        let stored = UserDefaults.standard.data(forKey: "settings.v2")
            .flatMap { try? JSONDecoder().decode(GestureSettings.self, from: $0) }
            .map(Self.enableVerticalSwipes) ?? GestureSettings()
        settings = stored
        showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        showCorner = UserDefaults.standard.object(forKey: "showCorner") as? Bool ?? true
        showLegend = UserDefaults.standard.object(forKey: "showLegend") as? Bool ?? true
        corner = UserDefaults.standard.string(forKey: "corner").flatMap(Corner.init) ?? .bottomRight
        cameraID = UserDefaults.standard.string(forKey: "cameraID")
        pipeline = Pipeline(queue: camera.frameQueue, settings: stored)

        let pipeline = pipeline
        camera.onFrame = { buffer, time in pipeline.process(buffer, time: time) }
        camera.onStopped = { message in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppModel.shared.cameraStopped(message) } }
        }
        pipeline.onStatus = { status in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppModel.shared.receive(status) } }
        }
    }

    private static func enableVerticalSwipes(_ stored: GestureSettings) -> GestureSettings {
        let key = "verticalSwipesEnabled"
        guard !UserDefaults.standard.bool(forKey: key) else { return stored }
        UserDefaults.standard.set(true, forKey: key)
        var settings = stored
        settings.disabled.subtract([.swipeUp, .swipeDown])
        if settings.action(for: .swipeDown) == .none { settings.bindings[.swipeDown] = .appExpose }
        return settings
    }

    func launch() {
        remote.publish(isRunning)
        remote.start()
        refreshDevices()
        hotKey = HotKey(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppModel.shared.stop() }
            }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppModel.shared.refreshDevices() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.refreshPermissions() }
        }
    }

    func shutdown() {
        remote.publish(false)
        pipeline.deactivate(sync: true)
        camera.stop()
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        Task { await turnOn() }
    }

    @discardableResult
    func turnOn() async -> Bool {
        guard !isRunning else { return true }
        error = nil
        if !accessibilityGranted { requestAccessibility() }
        cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraGranted else {
            error = "Falta el permiso de Cámara"
            return false
        }
        guard !isRunning else { return true }
        isRunning = true
        pipeline.activate()
        camera.start(deviceID: cameraID)
        refreshPanels()
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        camera.stop()
        pipeline.deactivate()
        live.status = PipelineStatus()
        if engaged { engaged = false }
        refreshPanels()
    }

    func recordTrace() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hands", isDirectory: true)
        pipeline.startTrace(seconds: 30, to: folder.appendingPathComponent("trace.jsonl"))
    }

    func resetSettings() { settings = GestureSettings() }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityGranted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshDevices() { cameras = CameraCapture.devices() }

    private func refreshPermissions() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted { accessibilityGranted = trusted }
        let camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if camera != cameraGranted { cameraGranted = camera }
    }

    private func cameraStopped(_ message: String?) {
        stop()
        error = message
    }

    private func receive(_ new: PipelineStatus) {
        guard isRunning else { return }
        live.status = new
        if engaged != new.engaged { engaged = new.engaged }
        for event in new.events {
            if let text = Labels.describe(event, settings: settings) { flash(text, Labels.gesture(event)) }
        }
        refreshPanels()
    }

    private func flash(_ text: String, _ gesture: HandGesture?) {
        live.lastAction = text
        live.lastGesture = gesture
        actionClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.live.lastAction = nil
                self?.live.lastGesture = nil
            }
        }
        actionClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func refreshSoon() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refreshPanels() }
        }
    }

    private func refreshPanels() {
        let visible = showHUD && !showCorner && isRunning && (live.status.engaged || live.status.progress > 0.15)
        hud.setVisible(visible)
        cornerPanel.update(visible: showCorner && isRunning, corner: corner)
    }
}
