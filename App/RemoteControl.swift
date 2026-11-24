import Foundation

final class RemoteControl {
    enum Command: String { case on, off }

    private let folder: URL
    private let handler: (Command) -> Void
    private var watcher: DispatchSourceFileSystemObject?
    private let maxAge = 10.0

    private var commandFile: URL { folder.appendingPathComponent("command") }
    private var stateFile: URL { folder.appendingPathComponent("state") }

    init(handler: @escaping (Command) -> Void) {
        self.handler = handler
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hands", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func start() {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.consume() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
        consume()
    }

    func publish(_ isOn: Bool) {
        try? Data((isOn ? "on" : "off").utf8).write(to: stateFile, options: .atomic)
    }

    private func consume() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: commandFile.path),
              let modified = attributes[.modificationDate] as? Date,
              let text = try? String(contentsOf: commandFile, encoding: .utf8)
        else { return }
        try? FileManager.default.removeItem(at: commandFile)
        guard Date().timeIntervalSince(modified) < maxAge,
              let command = Command(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        handler(command)
    }
}
