import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.launch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
}

@main
struct HandTrackingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(systemName: icon)
        }
        Window("Hand Tracking", id: "settings") {
            SettingsView().environmentObject(model).environmentObject(model.live)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    private var icon: String {
        if !model.isRunning { return "hand.raised.slash" }
        return model.engaged ? "hand.point.up.left.fill" : "hand.raised"
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.error ?? (model.isRunning ? "Encendido: cámara activa" : "Apagado: cámara apagada"))
        if !model.accessibilityGranted {
            Button("Dar permiso de Accesibilidad…") { model.requestAccessibility() }
        }
        if !model.cameraGranted {
            Button("Dar permiso de Cámara…") { model.openPrivacy("Privacy_Camera") }
        }
        Divider()
        Button(model.isRunning ? "Hands down (⌃⌥⌘H)" : "Hands on (⌃⌥⌘H)") { model.toggle() }
        Toggle("Mostrar mi mano en una esquina", isOn: $model.showCorner)
        Toggle("Mostrar leyenda", isOn: $model.showLegend)
        Picker("Esquina", selection: $model.corner) {
            ForEach(Corner.allCases, id: \.self) { Text($0.name).tag($0) }
        }
        Button("Grabar diagnóstico (30 s, solo puntos)") { model.recordTrace() }
            .disabled(!model.isRunning)
        Button("Ajustes…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Salir") { NSApp.terminate(nil) }
    }
}
