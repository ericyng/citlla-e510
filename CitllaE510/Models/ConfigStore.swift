import Foundation
import os

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { save() }
    }

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "config")

    /// `~/Library/Application Support/CitllaE510`
    nonisolated static var supportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CitllaE510", isDirectory: true)
    }

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent("CitllaE510", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = AppConfig()
        }
    }

    func binding(for button: Int) -> ButtonBinding {
        config.bindings.first(where: { $0.button == button })
            ?? ButtonBinding(button: button, action: .none)
    }

    func setAction(_ action: MouseAction, for button: Int) {
        config.setAction(action, for: button)
    }

    func resetToDefaults() {
        config.resetToDefaults()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save config: \(error.localizedDescription, privacy: .public)")
        }
    }
}
