import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var panel: NSPanel?

    func setVisible(_ visible: Bool) {
        guard visible else {
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? makePanel()
        guard !panel.isVisible else { return }
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 24))
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HUDView().environmentObject(AppModel.shared).environmentObject(AppModel.shared.live))
        self.panel = panel
        return panel
    }
}

struct HUDView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveStatus

    var body: some View {
        HStack(spacing: 10) {
            EngageRing(engaged: live.status.engaged, progress: live.status.progress)
            Text(text).font(.callout.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.separator))
        .frame(width: 260, height: 56)
    }

    private var text: String {
        if !live.status.engaged { return "Mantén la mano quieta" }
        if !model.accessibilityGranted { return "Falta Accesibilidad" }
        return live.lastAction ?? Labels.name(live.status.pose)
    }
}
