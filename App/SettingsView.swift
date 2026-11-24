import HandCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PreviewTab().tabItem { Label("Cámara", systemImage: "camera") }
            GesturesTab().tabItem { Label("Gestos", systemImage: "hand.raised") }
            TuningTab().tabItem { Label("Sensibilidad", systemImage: "slider.horizontal.3") }
            PermissionsTab().tabItem { Label("Permisos", systemImage: "lock") }
        }
        .frame(width: 560, height: 620)
    }
}

struct GesturesTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            ForEach(HandGesture.allCases, id: \.self) { gesture in
                HStack {
                    Toggle(isOn: enabled(gesture)) {
                        Label(Labels.name(gesture), systemImage: Labels.symbol(gesture))
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    if gesture.isBindable {
                        Picker("Acción", selection: binding(gesture)) {
                            ForEach(SystemAction.allCases, id: \.self) { Text(Labels.name($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                        .disabled(!model.settings.isEnabled(gesture))
                    } else {
                        Text(Labels.fixedAction(gesture)).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Restaurar valores por defecto") { model.resetSettings() }
        }
        .formStyle(.grouped)
    }

    private func enabled(_ g: HandGesture) -> Binding<Bool> {
        Binding(
            get: { model.settings.isEnabled(g) },
            set: { on in
                if on { model.settings.disabled.remove(g) } else { model.settings.disabled.insert(g) }
            }
        )
    }

    private func binding(_ g: HandGesture) -> Binding<SystemAction> {
        Binding(
            get: { model.settings.bindings[g] ?? .none },
            set: { model.settings.bindings[g] = $0 }
        )
    }
}

struct TuningTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Cursor") {
                slider("Área de la cámara", $model.settings.pointerArea, 0.3...1)
                slider("Suavizado", $model.settings.smoothing, 0...1)
            }
            Section("Scroll") {
                slider("Velocidad", $model.settings.scrollSpeed, 0.3...3)
                Toggle("El contenido sigue a la mano", isOn: $model.settings.naturalScroll)
            }
            Section("Gestos") {
                slider("Facilidad del pellizco", $model.settings.pinchSensitivity, 0...1)
                slider("Facilidad del swipe", $model.settings.swipeSensitivity, 0...1)
                slider("Espera para activar (s)", $model.settings.engageHold, 0.2...2)
            }
            Section {
                Toggle("Mostrar mi mano en una esquina", isOn: $model.showCorner)
                Picker("Esquina", selection: $model.corner) {
                    ForEach(Corner.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .disabled(!model.showCorner)
                Toggle("Mostrar leyenda de gestos", isOn: $model.showLegend)
                    .disabled(!model.showCorner)
                Toggle("Mostrar indicador pequeño", isOn: $model.showHUD)
                    .disabled(model.showCorner)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Slider(value: value, in: range) { Text(title) }
            Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct PermissionsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            row("Cámara", "Para ver tus manos.", model.cameraGranted) { model.openPrivacy("Privacy_Camera") }
            row("Accesibilidad", "Para mover el cursor, hacer click y enviar atajos.", model.accessibilityGranted) {
                model.requestAccessibility()
                model.openPrivacy("Privacy_Accessibility")
            }
            Section {
                Text("El video se procesa en esta Mac. No se guarda ni se envía.")
                Text("Encender: «Hey Siri, Hands on». Apagar: «Hey Siri, Hands down».")
                Text("También con ⌃⌥⌘H")
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func row(_ name: String, _ detail: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
                .accessibilityLabel(granted ? "Concedido" : "Pendiente")
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Abrir Ajustes", action: action) }
        }
    }
}
