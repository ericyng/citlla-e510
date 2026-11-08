import AppKit
import XCTest
@testable import CitllaE510

final class AppConfigTests: XCTestCase {
    func testDefaultsBindSideButtonsToBackAndForward() {
        let config = AppConfig()

        XCTAssertEqual(config.bindings.count, 8)
        XCTAssertEqual(config.action(for: 4), MouseAction(kind: .system, system: .back))
        XCTAssertEqual(config.action(for: 5), MouseAction(kind: .system, system: .forward))
        XCTAssertFalse(config.action(for: 1)?.isBound ?? true)
        XCTAssertFalse(config.action(for: 8)?.isBound ?? true)
    }

    func testActionForUnknownButtonIsNil() {
        XCTAssertNil(AppConfig().action(for: 42))
    }

    func testSetActionUpdatesExistingButton() {
        var config = AppConfig()
        config.setAction(MouseAction(kind: .system, system: .missionControl), for: 4)

        XCTAssertEqual(config.action(for: 4)?.system, .missionControl)
        XCTAssertEqual(config.bindings.count, 8, "existing buttons should be updated, not duplicated")
    }

    func testSetActionAppendsNewButton() {
        var config = AppConfig()
        config.setAction(MouseAction(kind: .system, system: .mute), for: 12)

        XCTAssertEqual(config.action(for: 12)?.system, .mute)
        XCTAssertEqual(config.bindings.count, 9)
    }

    func testResetToDefaults() {
        var config = AppConfig()
        config.setAction(.none, for: 4)
        config.resetToDefaults()

        XCTAssertEqual(config.action(for: 4)?.system, .back)
    }

    func testDecodingOlderConfigKeepsDefaultsForMissingKeys() throws {
        let json = Data(#"{"enabled": false}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.bindings.count, 8)
        XCTAssertEqual(config.action(for: 4)?.system, .back)
    }

    func testCodableRoundTrip() throws {
        var config = AppConfig()
        config.enabled = false
        config.setAction(MouseAction(kind: .openURL, text: "https://example.com"), for: 6)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }
}

final class ButtonBindingTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(ButtonBinding.defaults.map(\.name), [
            "Left Click", "Right Click", "Middle Click",
            "Button 4", "Button 5", "Button 6", "Button 7", "Button 8"
        ])
        XCTAssertEqual(ButtonBinding(button: 9, action: .none).name, "Button 9")
    }

    func testSubtitles() {
        XCTAssertEqual(ButtonBinding(button: 1, action: .none).subtitle, "Primary button")
        XCTAssertEqual(ButtonBinding(button: 3, action: .none).subtitle, "Scroll wheel click")
        XCTAssertEqual(ButtonBinding(button: 4, action: .none).subtitle, "Usually the rear side button")
        XCTAssertEqual(ButtonBinding(button: 9, action: .none).subtitle, "Extra mouse button")
    }

    func testIdentityIsTheButtonNumber() {
        XCTAssertEqual(ButtonBinding(button: 7, action: .none).id, 7)
    }
}

final class MouseActionTests: XCTestCase {
    func testUnboundAction() {
        XCTAssertFalse(MouseAction.none.isBound)
        XCTAssertEqual(MouseAction.none.summary, "Pass through")
        XCTAssertEqual(MouseAction.none.symbolName, "nosign")
    }

    func testSystemActionSummaryUsesTitle() {
        XCTAssertEqual(MouseAction(kind: .system, system: .back).summary, "Back")
        XCTAssertTrue(MouseAction(kind: .system, system: .missionControl).isBound)
    }

    func testKeyboardShortcutSummary() {
        XCTAssertEqual(MouseAction(kind: .keyboardShortcut).summary, "No shortcut recorded")

        let shortcut = MouseAction(
            kind: .keyboardShortcut,
            keyCode: 33,
            modifiers: NSEvent.ModifierFlags.command.rawValue,
            hasShortcut: true
        )
        XCTAssertEqual(shortcut.summary, "⌘[")
    }

    func testOpenAppSummaryShowsBundleName() {
        XCTAssertEqual(
            MouseAction(kind: .openApp, text: "/System/Applications/Calculator.app").summary,
            "Calculator.app"
        )
        XCTAssertEqual(MouseAction(kind: .openApp).summary, "No app selected")
    }

    func testOpenURLAndShellCommandSummary() {
        XCTAssertEqual(MouseAction(kind: .openURL, text: "https://example.com").summary, "https://example.com")
        XCTAssertEqual(MouseAction(kind: .openURL).summary, "No URL set")
        XCTAssertEqual(MouseAction(kind: .shellCommand, text: "echo hi").summary, "echo hi")
        XCTAssertEqual(MouseAction(kind: .shellCommand).summary, "No command set")
    }

    func testMouseClickSummary() {
        XCTAssertEqual(MouseAction(kind: .mouseClick, click: .middle).summary, "Middle Click")
    }
}

final class MouseMapTests: XCTestCase {
    func testEveryCalloutFromTheDiagramIsPresent() {
        XCTAssertEqual(MouseMap.controls.map(\.number), Array(1...9))
        XCTAssertEqual(MouseMap.control(number: 3)?.title, "Smart Flying Scroll Wheel")
        XCTAssertEqual(MouseMap.control(number: 8)?.title, "Forward / Back Buttons")
        XCTAssertNil(MouseMap.control(number: 10))
    }

    func testIndicatorsAreNotRemappable() {
        XCTAssertFalse(MouseMap.control(number: 7)!.isRemappable)
        XCTAssertEqual(MouseMap.remappableControls.count, 8)
    }

    func testButtonsResolveToCallouts() {
        XCTAssertEqual(MouseMap.control(forButton: 1)?.number, 1)
        XCTAssertEqual(MouseMap.control(forButton: 2)?.number, 2)
        XCTAssertEqual(MouseMap.control(forButton: 3)?.number, 3)
        XCTAssertEqual(MouseMap.control(forButton: 4)?.number, 8)
        XCTAssertEqual(MouseMap.control(forButton: 5)?.number, 8)
        XCTAssertNil(MouseMap.control(forButton: 9))
    }

    func testFactoryShortcutsResolveToCallouts() {
        let command = NSEvent.ModifierFlags.command.rawValue
        XCTAssertEqual(MouseMap.control(forKeyCode: 48, modifiers: command)?.number, 6)

        let fullScreen = NSEvent.ModifierFlags([.control, .command]).rawValue
        XCTAssertEqual(MouseMap.control(forKeyCode: 3, modifiers: fullScreen)?.number, 9)

        // Caps Lock and the numeric pad flag must not defeat the match.
        XCTAssertEqual(
            MouseMap.control(forKeyCode: 3, modifiers: fullScreen | NSEvent.ModifierFlags.capsLock.rawValue)?.number,
            9
        )
        XCTAssertNil(MouseMap.control(forKeyCode: 3, modifiers: command))
    }
}

final class KeyCodeMapTests: XCTestCase {    func testKnownNames() {
        XCTAssertEqual(KeyCodeMap.name(for: 33), "[")
        XCTAssertEqual(KeyCodeMap.name(for: 36), "Return")
        XCTAssertEqual(KeyCodeMap.name(for: 999), "Key 999")
    }

    func testDescribeOrdersModifiersControlOptionShiftCommand() {
        let all = NSEvent.ModifierFlags([.control, .option, .shift, .command]).rawValue

        XCTAssertEqual(KeyCodeMap.describe(keyCode: 0, modifiers: all), "⌃⌥⇧⌘A")
        XCTAssertEqual(KeyCodeMap.describe(keyCode: 0, modifiers: 0), "A")
    }

    func testEventMarkerIsStable() {
        XCTAssertEqual(EventMarker.value, 0x4349_544C_4C41_3531)
    }
}

@MainActor
final class ConfigStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CitllaE510Tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testFreshDirectoryHasNoStoredConfig() {
        let store = ConfigStore(directory: directory)

        XCTAssertFalse(store.hadStoredConfig)
        XCTAssertEqual(store.config.action(for: 4)?.system, .back)
    }

    func testConfigIsPersistedAndReloaded() {
        let store = ConfigStore(directory: directory)
        store.setAction(MouseAction(kind: .system, system: .spotlight), for: 6)
        store.config.enabled = false

        let reopened = ConfigStore(directory: directory)

        XCTAssertTrue(reopened.hadStoredConfig)
        XCTAssertFalse(reopened.config.enabled)
        XCTAssertEqual(reopened.config.action(for: 6)?.system, .spotlight)
    }

    func testBindingForUnknownButtonFallsBackToUnbound() {
        let store = ConfigStore(directory: directory)

        XCTAssertEqual(store.binding(for: 99).button, 99)
        XCTAssertFalse(store.binding(for: 99).action.isBound)
    }
}
