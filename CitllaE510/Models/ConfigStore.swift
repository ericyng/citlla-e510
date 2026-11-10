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

    /// One-shot launches that must not touch the user's real config.
    ///
    /// The unit tests run *inside this app* — it is the test host — so the
    /// `@main` scene builds `AppModel.shared` and therefore this initialiser,
    /// which writes the merged config back. Without this guard every test run
    /// rewrites the live `config.json`, and parallel worktree test runs race on
    /// it. `--snapshot` and the probes have the same shape: they are launched
    /// from a built copy and have no business changing the installed app's
    /// settings.
    nonisolated static var isEphemeralLaunch: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        if ProcessInfo.processInfo.environment["CITLLA_CONFIG_DIR"] != nil { return true }
        let oneShot = ["--snapshot", "--status", "--perform", "--post-shortcut", "--coredock"]
        return CommandLine.arguments.contains { oneShot.contains($0) }
    }

    /// The directory a config store should use when the caller does not name
    /// one: an explicit override, a throwaway directory for one-shot launches,
    /// or the real support directory.
    nonisolated static func defaultDirectory(fileManager: FileManager) -> URL {
        if let override = ProcessInfo.processInfo.environment["CITLLA_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if isEphemeralLaunch {
            return fileManager.temporaryDirectory
                .appendingPathComponent("CitllaE510-one-shot-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("CitllaE510", isDirectory: true)
    }

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        let directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
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
