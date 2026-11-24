import AppIntents

enum HandsError: Error, CustomLocalizedStringResourceConvertible {
    case cameraDenied

    var localizedStringResource: LocalizedStringResource { "Hands needs camera permission" }
}

struct HandsOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Hands on"
    static let description = IntentDescription("Enciende la cámara y el control con las manos.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await AppModel.shared.turnOn() else { throw HandsError.cameraDenied }
        return .result()
    }
}

struct HandsDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Hands down"
    static let description = IntentDescription("Apaga la cámara y el control con las manos.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.stop()
        return .result()
    }
}

struct HandsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HandsOnIntent(),
            phrases: ["\(.applicationName) on", "Turn \(.applicationName) on", "Turn on \(.applicationName)"],
            shortTitle: "Hands on",
            systemImageName: "hand.raised"
        )
        AppShortcut(
            intent: HandsDownIntent(),
            phrases: ["\(.applicationName) down", "\(.applicationName) off", "Turn \(.applicationName) off", "Turn off \(.applicationName)"],
            shortTitle: "Hands down",
            systemImageName: "hand.raised.slash"
        )
    }
}
