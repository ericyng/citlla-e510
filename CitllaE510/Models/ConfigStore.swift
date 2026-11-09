import Foundation
import os

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { save() }
    }

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "config")

    /// True when `config.json` already existed, so this is not a first run.
    let hadStoredConfig: Bool

    /// `~/Library/Application Support/CitllaE510`
    nonisolated static var supportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CitllaE510", isDirectory: true)
    }

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = directory ?? support.appendingPathComponent("CitllaE510", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            hadStoredConfig = true
            config = decoded
            // The decoder merges in defaults for controls this build maps but
            // the file predates. Write the merged config back so the file and
            // the running app agree.
            save()
        } else {
            hadStoredConfig = false
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

    /// Keboard/consumer controls the mouse sends. These are not mouse buttons,
    /// so they are kept apart from `bindings`.
    var shortcutBindings: [ShortcutBinding] { config.shortcutBindings }

    func shortcut(id: String) -> ShortcutBinding? {
        config.shortcut(id: id)
    }

    func action(forKeyboardKeyCode keyCode: UInt16, modifiers: UInt) -> MouseAction? {
        config.action(forKeyboardKeyCode: keyCode, modifiers: modifiers)?.1
    }

    func action(forConsumerKey key: Int32) -> MouseAction? {
        config.action(forConsumerKey: key)?.1
    }

    func setAction(_ action: MouseAction, forShortcut id: String) {
        config.setAction(action, forShortcut: id)
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
