import AppKit
import HandCore
import SwiftUI

enum Corner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var name: String {
        switch self {
        case .topLeft: "Arriba a la izquierda"
        case .topRight: "Arriba a la derecha"
        case .bottomLeft: "Abajo a la izquierda"
        case .bottomRight: "Abajo a la derecha"
        }
    }

    func origin(for size: NSSize, in frame: NSRect) -> NSPoint {
        let margin = 16.0
        let left = self == .topLeft || self == .bottomLeft
        let bottom = self == .bottomLeft || self == .bottomRight
        return NSPoint(
            x: left ? frame.minX + margin : frame.maxX - size.width - margin,
            y: bottom ? frame.minY + margin : frame.maxY - size.height - margin
        )
    }
}

@MainActor
final class CornerPanelController {
    private var panel: NSPanel?

    func update(visible: Bool, corner: Corner) {
        guard visible else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let panel = panel ?? makePanel()
        if let size = panel.contentView?.fittingSize, let frame = NSScreen.screens.first?.visibleFrame {
            let target = NSRect(origin: corner.origin(for: size, in: frame), size: size)
            if panel.frame != target { panel.setFrame(target, display: true) }
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: CornerPanelView.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(
            rootView: CornerPanelView()
                .environmentObject(AppModel.shared)
                .environmentObject(AppModel.shared.live)
        )
        self.panel = panel
        return panel
    }
}

struct CornerPanelView: View {
    static let width = 330.0

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveStatus

    var body: some View {
        VStack(spacing: 0) {
            if model.showLegend {
                LegendView(settings: model.settings, active: live.lastGesture)
                    .equatable()
            }
            ZStack {
                Color.black
                CameraPreview(session: model.camera.session)
                SkeletonView(status: live.status, area: model.settings.pointerArea)
            }
            .frame(width: Self.width, height: (Self.width / live.status.aspect).rounded())

            HStack(spacing: 10) {
                EngageRing(engaged: live.status.engaged, progress: live.status.progress)
                Text(hint)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
        }
        .frame(width: Self.width)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(live.status.engaged ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
        )
    }

    private var hint: String {
        if !model.accessibilityGranted { return "Falta el permiso de Accesibilidad: el cursor no se moverá" }
        if live.status.hands.isEmpty { return "Muestra tu mano a la cámara" }
        if !live.status.engaged { return "Abre la mano y mantenla quieta" }
        if let action = live.lastAction { return action }
        switch live.status.pose {
        case .open: return "Listo. Acerca índice y pulgar para mover"
        case .point: return "Moviendo el cursor"
        case .other: return "Acerca índice y pulgar para mover"
        default: return Labels.name(live.status.pose)
        }
    }
}

struct LegendView: View, Equatable {
    let settings: GestureSettings
    let active: HandGesture?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("hand.raised", "Mano abierta y quieta", "Activar", false)
            ForEach(visible, id: \.self) { gesture in
                row(Labels.symbol(gesture), Labels.short(gesture), action(gesture), gesture == active)
            }
        }
        .padding(8)
    }

    private var visible: [HandGesture] {
        HandGesture.allCases.filter {
            settings.isEnabled($0) && (!$0.isBindable || settings.action(for: $0) != .none)
        }
    }

    private func action(_ g: HandGesture) -> String {
        g.isBindable ? Labels.name(settings.action(for: g)) : Labels.fixedAction(g)
    }

    private func row(_ symbol: String, _ gesture: String, _ action: String, _ on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 16)
            Text(gesture)
            Spacer(minLength: 8)
            Text(action).foregroundStyle(on ? .primary : .secondary)
        }
        .font(.caption.weight(on ? .bold : .regular))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(on ? Color.green.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct EngageRing: View {
    let engaged: Bool
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: engaged ? 1 : progress)
                .stroke(engaged ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
    }
}
