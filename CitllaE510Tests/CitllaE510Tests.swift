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
        XCTAssertEqual(config.shortcutBindings, ShortcutBinding.defaults)
    }

    func testCodableRoundTrip() throws {
        var config = AppConfig()
        config.enabled = false
        config.setAction(MouseAction(kind: .openURL, text: "https://example.com"), for: 6)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    // MARK: - Keys the mouse sends

    func testDefaultsBindThumbButtonKeystrokes() {
        let config = AppConfig()
        let control = NSEvent.ModifierFlags.control.rawValue

        XCTAssertEqual(config.shortcutBindings.count, 2)
        XCTAssertEqual(
            config.action(forKeyboardKeyCode: 123, modifiers: control)?.1,
            MouseAction(kind: .system, system: .back)
        )
        XCTAssertEqual(
            config.action(forKeyboardKeyCode: 124, modifiers: control)?.1,
            MouseAction(kind: .system, system: .forward)
        )
        XCTAssertNil(config.action(forKeyboardKeyCode: 123, modifiers: 0))
    }

    func testCapsLockDoesNotDefeatShortcutMatching() {
        let config = AppConfig()
        let modifiers = NSEvent.ModifierFlags([.control, .capsLock, .numericPad]).rawValue

        XCTAssertEqual(
            config.action(forKeyboardKeyCode: 123, modifiers: modifiers)?.1.system,
            .back
        )
    }

    func testSetActionForShortcut() {
        var config = AppConfig()
        let id = ShortcutBinding.defaults[0].id

        config.setAction(MouseAction(kind: .system, system: .missionControl), forShortcut: id)

        XCTAssertEqual(config.shortcut(id: id)?.action.system, .missionControl)
        XCTAssertEqual(config.shortcutBindings.count, 2, "existing shortcuts should be updated, not duplicated")
    }

    func testLearnKeyboardShortcutAddsOnce() {
        var config = AppConfig()
        let command = NSEvent.ModifierFlags.command.rawValue

        let first = config.learnKeyboardShortcut(keyCode: 48, modifiers: command)
        let second = config.learnKeyboardShortcut(keyCode: 48, modifiers: command)

        XCTAssertEqual(first, second)
        XCTAssertEqual(config.shortcutBindings.count, 3)
        XCTAssertFalse(config.shortcut(id: first)?.action.isBound ?? true)
    }

    func testLearnConsumerKey() {
        var config = AppConfig()

        let id = config.learnConsumerKey(0)
        let again = config.learnConsumerKey(0)

        XCTAssertEqual(id, again)
        XCTAssertEqual(config.shortcut(id: id)?.source, .consumer)
        XCTAssertEqual(config.shortcutBindings.count, 3)
    }

    func testActionForConsumerKey() {
        var config = AppConfig()
        let id = config.learnConsumerKey(0)
        config.setAction(MouseAction(kind: .system, system: .playPause), forShortcut: id)

        XCTAssertEqual(config.action(forConsumerKey: 0)?.1.system, .playPause)
        XCTAssertNil(config.action(forConsumerKey: 16))
    }

    func testResetRestoresShortcutDefaults() {
        var config = AppConfig()
        config.setAction(.none, forShortcut: ShortcutBinding.defaults[0].id)
        config.learnConsumerKey(0)

        config.resetToDefaults()

        XCTAssertEqual(config.shortcutBindings, ShortcutBinding.defaults)
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
        // This mouse does not send buttons 4 and 5; its thumb buttons send
        // keystrokes instead (see `testShortcutBindingsResolveToCallouts`).
        XCTAssertNil(MouseMap.control(forButton: 4))
        XCTAssertNil(MouseMap.control(forButton: 5))
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

    func testShortcutBindingsResolveToCallouts() {
        let control = NSEvent.ModifierFlags.control.rawValue

        let back = ShortcutBinding(
            keyCode: 123,
            modifiers: control,
            action: MouseAction(kind: .system, system: .back)
        )
        let forward = ShortcutBinding(keyCode: 124, modifiers: control)

        XCTAssertEqual(MouseMap.control(forShortcut: back)?.number, 8)
        XCTAssertEqual(MouseMap.control(forShortcut: forward)?.number, 8)

        let volume = ShortcutBinding(source: .consumer, consumerKey: 0)
        XCTAssertNil(MouseMap.control(forShortcut: volume), "consumer keys are not on the diagram")
    }
}

final class ShortcutBindingTests: XCTestCase {
    func testIdentityStableAcrossMatchingFlags() {
        let control = NSEvent.ModifierFlags.control.rawValue
        let capsLock = NSEvent.ModifierFlags.capsLock.rawValue

        let plain = ShortcutBinding(keyCode: 123, modifiers: control)
        let noisy = ShortcutBinding(keyCode: 123, modifiers: control | capsLock)

        XCTAssertEqual(plain.id, noisy.id)
        XCTAssertTrue(plain.matches(keyCode: 123, modifiers: control | capsLock))
        XCTAssertFalse(plain.matches(keyCode: 123, modifiers: 0))
        XCTAssertFalse(plain.matches(keyCode: 124, modifiers: control))
    }

    func testConsumerBindingsDoNotMatchKeyboardEvents() {
        let binding = ShortcutBinding(source: .consumer, consumerKey: 0)

        XCTAssertEqual(binding.id, "consumer-0")
        XCTAssertFalse(binding.matches(keyCode: 0, modifiers: 0))
    }

    func testNamesComeFromKeyCodeAndNXKeyType() {
        let control = NSEvent.ModifierFlags.control.rawValue

        XCTAssertEqual(ShortcutBinding(keyCode: 123, modifiers: control).name, "⌃Left Arrow")
        XCTAssertEqual(ShortcutBinding(source: .consumer, consumerKey: 0).name, "Volume Up")
        XCTAssertEqual(ShortcutBinding(source: .consumer, consumerKey: 7).name, "Mute")
    }
}

final class NXKeyStateTests: XCTestCase {
    func testMediaKeyStateLivesInBits8To15() {
        let down = (16 << 16) | (0xA << 8)
        let up = (16 << 16) | (0xB << 8)

        XCTAssertEqual(NXKeyState.keyType(from: down), 16)
        XCTAssertTrue(NXKeyState.isDown(down))
        XCTAssertFalse(NXKeyState.isDown(up))
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
