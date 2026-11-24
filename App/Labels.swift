import HandCore

typealias HandGesture = HandCore.Gesture

enum Labels {
    static func name(_ g: HandGesture) -> String {
        switch g {
        case .pointer: "Índice y pulgar casi juntos"
        case .indexPinch: "Pellizco índice + pulgar"
        case .twoFingers: "Índice y medio arriba"
        case .middlePinch: "Pellizco medio + pulgar"
        case .swipeLeft: "Swipe a la izquierda"
        case .swipeRight: "Swipe a la derecha"
        case .swipeUp: "Swipe hacia arriba"
        case .swipeDown: "Swipe hacia abajo"
        case .fist: "Puño sostenido"
        case .thumbUp: "Pulgar arriba"
        case .thumbDown: "Pulgar abajo"
        case .thumbLeft: "Pulgar a la izquierda"
        case .thumbRight: "Pulgar a la derecha"
        case .spread: "Dos pellizcos separándose"
        case .squeeze: "Dos pellizcos juntándose"
        }
    }

    static func short(_ g: HandGesture) -> String {
        switch g {
        case .pointer: "Índice y pulgar casi juntos"
        case .indexPinch: "Tocar índice y pulgar"
        case .twoFingers: "Índice y medio arriba"
        case .middlePinch: "Tocar medio y pulgar"
        case .swipeLeft: "Mano abierta ←"
        case .swipeRight: "Mano abierta →"
        case .swipeUp: "Mano abierta ↑"
        case .swipeDown: "Mano abierta ↓"
        case .fist: "Puño sostenido"
        case .thumbUp: "Pulgar ↑"
        case .thumbDown: "Pulgar ↓"
        case .thumbLeft: "Pulgar ←"
        case .thumbRight: "Pulgar →"
        case .spread: "Dos pellizcos, separar"
        case .squeeze: "Dos pellizcos, juntar"
        }
    }

    static func gesture(_ e: GestureEvent) -> HandGesture? {
        switch e {
        case .engaged, .disengaged, .moveTo, .dragEnded: nil
        case .click, .dragBegan: .indexPinch
        case .scroll: .twoFingers
        case let .trigger(g): g
        }
    }

    static func fixedAction(_ g: HandGesture) -> String {
        switch g {
        case .pointer: "Mover el cursor"
        case .indexPinch: "Click / arrastrar"
        case .twoFingers: "Scroll"
        default: ""
        }
    }

    static func symbol(_ g: HandGesture) -> String {
        switch g {
        case .pointer: "cursorarrow"
        case .indexPinch, .middlePinch: "hand.pinch"
        case .twoFingers: "arrow.up.and.down"
        case .swipeLeft: "arrow.left"
        case .swipeRight: "arrow.right"
        case .swipeUp: "arrow.up"
        case .swipeDown: "arrow.down"
        case .fist: "circle.fill"
        case .thumbUp: "hand.thumbsup"
        case .thumbDown: "hand.thumbsdown"
        case .thumbLeft: "chevron.left"
        case .thumbRight: "chevron.right"
        case .spread: "arrow.up.left.and.arrow.down.right"
        case .squeeze: "arrow.down.right.and.arrow.up.left"
        }
    }

    static func name(_ a: SystemAction) -> String {
        switch a {
        case .none: "Sin acción"
        case .rightClick: "Click derecho"
        case .middleClick: "Click central"
        case .spaceLeft: "Escritorio izquierdo"
        case .spaceRight: "Escritorio derecho"
        case .missionControl: "Mission Control"
        case .appExpose: "Ventanas de la app"
        case .showDesktop: "Mostrar escritorio"
        case .switchApp: "App anterior (⌘⇥)"
        case .playPause: "Play / pausa"
        case .nextTrack: "Siguiente"
        case .previousTrack: "Anterior"
        case .volumeUp: "Subir volumen"
        case .volumeDown: "Bajar volumen"
        case .mute: "Silenciar"
        case .brightnessUp: "Subir brillo"
        case .brightnessDown: "Bajar brillo"
        case .enterFullScreen: "Entrar a pantalla completa"
        case .exitFullScreen: "Salir de pantalla completa"
        case .toggleFullScreen: "Alternar pantalla completa"
        case .videoFullScreen: "Video a pantalla completa (F)"
        case .browserBack: "Atrás en el navegador"
        case .browserForward: "Adelante en el navegador"
        case .escape: "Escape"
        }
    }

    static func name(_ p: Pose) -> String {
        switch p {
        case .open: "Mano abierta"
        case .point: "Apuntando"
        case .twoFingers: "Scroll"
        case .fist: "Puño"
        case .thumbUp: "Pulgar arriba"
        case .thumbDown: "Pulgar abajo"
        case .thumbLeft: "Pulgar izquierda"
        case .thumbRight: "Pulgar derecha"
        case .other: "—"
        }
    }

    static func describe(_ e: GestureEvent, settings: GestureSettings) -> String? {
        switch e {
        case .engaged: "Activado"
        case .disengaged, .moveTo, .dragEnded: nil
        case let .click(count): count == 2 ? "Doble click" : "Click"
        case .dragBegan: "Arrastrando"
        case .scroll: "Scroll"
        case let .trigger(g): name(settings.action(for: g))
        }
    }
}
