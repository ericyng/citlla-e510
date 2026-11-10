import AppKit
@preconcurrency import IOKit.hid
import XCTest
@testable import CitllaE510

final class AppConfigTests: XCTestCase {
    func testDefaultsReportOnlyTheButtonsThisMouseSends() {
        let config = AppConfig()

        XCTAssertEqual(config.bindings.map(\.button), [1, 2, 3])
        XCTAssertFalse(config.bindings.contains { $0.action.isBound })
        XCTAssertNil(config.action(for: 4), "this mouse never sends buttons 4-8")
        XCTAssertNil(config.action(for: 8))
    }

    func testActionForUnknownButtonIsNil() {
        XCTAssertNil(AppConfig().action(for: 42))
    }

    func testSetActionUpdatesExistingButton() {
        var config = AppConfig()
        config.setAction(MouseAction(kind: .system, system: .missionControl), for: 3)

        XCTAssertEqual(config.action(for: 3)?.system, .missionControl)
        XCTAssertEqual(config.bindings.count, 3, "existing buttons should be updated, not duplicated")
    }

    func testSetActionAppendsNewButton() {
        var config = AppConfig()
        config.setAction(MouseAction(kind: .system, system: .mute), for: 12)

        XCTAssertEqual(config.action(for: 12)?.system, .mute)
        XCTAssertEqual(config.bindings.count, 4)
    }

    func testResetToDefaults() {
        var config = AppConfig()
        config.setAction(MouseAction(kind: .system, system: .missionControl), for: 3)
        config.resetToDefaults()

        XCTAssertEqual(config.bindings, ButtonBinding.defaults)
        XCTAssertFalse(config.action(for: 3)?.isBound ?? true)
    }

    func testDecodingOlderConfigKeepsDefaultsForMissingKeys() throws {
        let json = Data(#"{"enabled": false}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.bindings.map(\.button), [1, 2, 3])
        XCTAssertFalse(config.action(for: 3)?.isBound ?? true)
        XCTAssertEqual(config.shortcutBindings, ShortcutBinding.defaults)
    }

    func testDecodingAConfigWithButtons4To8DropsThem() throws {
        // Earlier builds listed buttons 4-8, which this mouse never sends. The
        // rows are trimmed and the user's choices for buttons 1-3 survive.
        let missionControl = MouseAction(kind: .system, system: .missionControl)
        let stored = (1...8).map { button in
            ButtonBinding(button: button, action: button == 3 ? missionControl : .none)
        }
        let json = try JSONEncoder().encode(["bindings": stored])
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(config.bindings.map(\.button), [1, 2, 3])
        XCTAssertEqual(config.action(for: 3), missionControl)
    }

    func testDecodingOlderConfigAddsMissingShortcutDefaults() throws {
        // A config written before the ninth control was mapped only has the two
        // thumb buttons; loading it must add the ⌃⌘F row without touching them.
        let control = NSEvent.ModifierFlags.control.rawValue
        let thumb = ShortcutBinding(
            keyCode: 123,
            modifiers: control,
            action: MouseAction(kind: .system, system: .missionControl)
        )
        let json = try JSONEncoder().encode(["shortcutBindings": [thumb]])
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(config.shortcut(id: thumb.id)?.action.system, .missionControl)
        XCTAssertEqual(config.shortcutBindings.count, ShortcutBinding.defaults.count)

        let fullScreen = NSEvent.ModifierFlags([.control, .command]).rawValue
        XCTAssertNotNil(config.action(forKeyboardKeyCode: 3, modifiers: fullScreen))
    }

    func testCodableRoundTrip() throws {
        var config = AppConfig()
        config.enabled = false
        config.setAction(MouseAction(kind: .openURL, text: "https://example.com"), for: 3)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    // MARK: - Keys the mouse sends

    func testDefaultsBindThumbButtonKeystrokes() {
        let config = AppConfig()
        let control = NSEvent.ModifierFlags.control.rawValue

        XCTAssertEqual(config.shortcutBindings.count, 3)
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

    func testNinthControlIsListedButLeftUnbound() {
        let config = AppConfig()
        let fullScreen = NSEvent.ModifierFlags([.control, .command]).rawValue

        let binding = config.action(forKeyboardKeyCode: 3, modifiers: fullScreen)?.0

        XCTAssertEqual(binding?.name, "⌃⌘F")
        XCTAssertFalse(binding?.action.isBound ?? true, "the factory shortcut must keep working until the user picks an action")
        XCTAssertEqual(MouseMap.control(forShortcut: binding!)?.number, 9)
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
        XCTAssertEqual(config.shortcutBindings.count, 3, "existing shortcuts should be updated, not duplicated")
    }

    func testLearnKeyboardShortcutAddsOnce() {
        var config = AppConfig()
        let command = NSEvent.ModifierFlags.command.rawValue

        let first = config.learnKeyboardShortcut(keyCode: 48, modifiers: command)
        let second = config.learnKeyboardShortcut(keyCode: 48, modifiers: command)

        XCTAssertEqual(first, second)
        XCTAssertEqual(config.shortcutBindings.count, 4)
        XCTAssertFalse(config.shortcut(id: first)?.action.isBound ?? true)
    }

    func testLearnConsumerKey() {
        var config = AppConfig()

        let id = config.learnConsumerKey(0)
        let again = config.learnConsumerKey(0)

        XCTAssertEqual(id, again)
        XCTAssertEqual(config.shortcut(id: id)?.source, .consumer)
        XCTAssertEqual(config.shortcutBindings.count, 4)
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
            "Left Click", "Right Click", "Middle Click"
        ])
        XCTAssertEqual(ButtonBinding(button: 4, action: .none).name, "Button 4")
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

/// The frozen shapes every worktree track builds against.
final class ActionContractTests: XCTestCase {
    private let command = NSEvent.ModifierFlags.command.rawValue
    private let option = NSEvent.ModifierFlags.option.rawValue

    // MARK: Chord support on a single click

    func testClickChordSummaryAndCarriedField() {
        let action = MouseAction(kind: .mouseClick, click: .left, clickModifiers: command)
        XCTAssertEqual(action.summary, "⌘ Left Click")
        XCTAssertEqual(action.clickModifiers, command)

        let decoded = try? JSONDecoder().decode(
            MouseAction.self,
            from: JSONEncoder().encode(action)
        )
        XCTAssertEqual(decoded?.clickModifiers, command, "the chord must survive a config round-trip")
    }

    // MARK: Sequence shape

    func testSequenceIsUnboundUntilItHasSteps() {
        XCTAssertFalse(MouseAction(kind: .sequence).isBound, "an empty sequence must pass through")

        let steps = [ActionStep(kind: .system, system: .missionControl)]
        XCTAssertTrue(MouseAction(kind: .sequence, steps: steps).isBound)
    }

    func testSequenceSummaryListsStepsInOrder() {
        let action = MouseAction(kind: .sequence, steps: [
            ActionStep(kind: .keyboardShortcut, keyCode: 8, modifiers: command, hasShortcut: true), // ⌘C
            ActionStep(kind: .keyboardShortcut, keyCode: 9, modifiers: command, hasShortcut: true)  // ⌘V
        ])
        XCTAssertEqual(action.summary, "⌘C → ⌘V")
    }

    func testLongSequenceSummaryIsTruncated() {
        let steps = (0..<5).map { _ in ActionStep(kind: .system, system: .back) }
        XCTAssertEqual(MouseAction(kind: .sequence, steps: steps).summary, "Back → Back → … (5 steps)")
    }

    func testStepDelayIsClampedToTheLimit() {
        XCTAssertEqual(ActionStep(delayMilliseconds: -20).clampedDelay, 0)
        XCTAssertEqual(ActionStep(delayMilliseconds: 250).clampedDelay, 250)
        XCTAssertEqual(ActionStep(delayMilliseconds: 99_999).clampedDelay, SequenceLimits.maxStepDelayMilliseconds)
    }

    func testStepCannotBeASequence() {
        XCTAssertFalse(ActionKind.stepCases.contains(.sequence))
        XCTAssertFalse(ActionKind.editableCases.contains(.sequence), "the picker must not offer a kind with no editor")
    }

    // MARK: Config compatibility

    func testDecodingAPreSequenceActionKeepsItsFields() throws {
        // Exactly what a config written by the shipped build looks like: no
        // clickModifiers, no steps.
        let json = Data(#"{"click":2,"hasShortcut":false,"keyCode":0,"kind":"mouseClick","modifiers":0,"system":"missionControl","text":""}"#.utf8)
        let action = try JSONDecoder().decode(MouseAction.self, from: json)

        XCTAssertEqual(action.kind, .mouseClick)
        XCTAssertEqual(action.click, .middle)
        XCTAssertEqual(action.clickModifiers, 0)
        XCTAssertEqual(action.steps, [])
    }

    func testDecodingAnEmptyObjectGivesTheDefaults() throws {
        let action = try JSONDecoder().decode(MouseAction.self, from: Data("{}".utf8))

        XCTAssertEqual(action, MouseAction.none)
        XCTAssertEqual(action.clickModifiers, 0)
        XCTAssertEqual(action.steps, [])
    }

    func testOldConfigStillLoadsWithItsBindings() throws {
        let json = Data(#"""
        {
          "enabled": true,
          "bindings": [
            {"button": 3, "action": {"kind": "system", "system": "missionControl"}}
          ],
          "shortcutBindings": [
            {"id": "key-123-262144", "source": "keyboard", "keyCode": 123, "modifiers": 262144, "consumerKey": 0,
             "action": {"kind": "system", "system": "back"}}
          ]
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(config.action(for: 3)?.system, .missionControl)
        XCTAssertEqual(config.action(forKeyboardKeyCode: 123, modifiers: 262144)?.1.system, .back)
    }

    // MARK: Ownership

    func testMacroOwnerDistinguishesControls() {
        XCTAssertNotEqual(MacroOwner.button(3), MacroOwner.button(4))
        XCTAssertNotEqual(MacroOwner.button(3), MacroOwner.shortcut("button-3"))
        XCTAssertEqual(MacroOwner.shortcut("key-123-0"), MacroOwner.shortcut("key-123-0"))
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

    func testEveryBadgePointSitsOnItsRender() {
        for control in MouseMap.controls {
            let point = control.badgePoint
            XCTAssertTrue(
                (0.0...1.0).contains(point.x) && (0.0...1.0).contains(point.y),
                "callout \(control.number) has its badge at \(point)"
            )
        }
        // The nine callouts are split across the two renders: 1-4 and 9 on the
        // top view, 5-8 on the side view.
        let top = MouseMap.controls.filter { $0.render == .top }.map(\.number)
        let side = MouseMap.controls.filter { $0.render == .side }.map(\.number)
        XCTAssertEqual(top, [1, 2, 3, 4, 9])
        XCTAssertEqual(side, [5, 6, 7, 8])
    }

    func testUnavailableSystemActionsAreDocumented() {
        XCTAssertNotNil(SystemAction.spotlight.unavailableNote)
        XCTAssertNotNil(SystemAction.lockScreen.unavailableNote)
        XCTAssertNil(SystemAction.missionControl.unavailableNote)
        XCTAssertNil(SystemAction.showDesktop.unavailableNote)
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

final class MouseReceiverTests: XCTestCase {
    func testBothObservedReceiverRevisionsAreKnown() {
        XCTAssertNotNil(MouseReceiver.receiver(vendorID: 0x1EA7, productID: 0x66))
        XCTAssertNotNil(MouseReceiver.receiver(vendorID: 0x32C2, productID: 0x12))
        XCTAssertNil(MouseReceiver.receiver(vendorID: 0x1EA7, productID: 0x12))
    }

    func testOneExactMatchPerKnownReceiver() {
        let matches = MouseReceiver.matchingDictionaries

        XCTAssertEqual(matches.count, MouseReceiver.known.count)
        for receiver in MouseReceiver.known {
            let matching = matches.filter {
                $0[kIOHIDVendorIDKey] as? Int == receiver.vendorID
                    && $0[kIOHIDProductIDKey] as? Int == receiver.productID
            }
            XCTAssertEqual(matching.count, 1, "\(receiver.id) should have exactly one exact match")
        }
    }

    func testVendorFallbacksAreDistinctAndDoNotConstrainTheProduct() {
        let vendors = MouseReceiver.vendorMatchingDictionaries.compactMap { $0[kIOHIDVendorIDKey] as? Int }
        let knownVendors = Set(MouseReceiver.known.map(\.vendorID))

        XCTAssertEqual(vendors.count, knownVendors.count)
        XCTAssertEqual(Set(vendors), knownVendors)
        for match in MouseReceiver.vendorMatchingDictionaries {
            XCTAssertNil(match[kIOHIDProductIDKey], "a vendor fallback must not constrain the product ID")
        }
    }

    func testAppleVendorIsNeverMatched() {
        let appleVendorID = 0x05AC

        XCTAssertFalse(MouseReceiver.known.contains { $0.vendorID == appleVendorID })
        XCTAssertFalse(
            MouseReceiver.vendorMatchingDictionaries.contains { $0[kIOHIDVendorIDKey] as? Int == appleVendorID }
        )
    }

    func testReceiverIDsAreStableAndUnique() {
        XCTAssertEqual(Set(MouseReceiver.known.map(\.id)).count, MouseReceiver.known.count)
        XCTAssertEqual(MouseReceiver.receiver(vendorID: 0x1EA7, productID: 0x66)?.id, "1EA7:0066")
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
        XCTAssertFalse(store.config.action(for: 3)?.isBound ?? true)
    }

    func testConfigIsPersistedAndReloaded() {
        let store = ConfigStore(directory: directory)
        store.setAction(MouseAction(kind: .system, system: .spotlight), for: 3)
        store.config.enabled = false

        let reopened = ConfigStore(directory: directory)

        XCTAssertTrue(reopened.hadStoredConfig)
        XCTAssertFalse(reopened.config.enabled)
        XCTAssertEqual(reopened.config.action(for: 3)?.system, .spotlight)
    }

    func testBindingForUnknownButtonFallsBackToUnbound() {
        let store = ConfigStore(directory: directory)

        XCTAssertEqual(store.binding(for: 99).button, 99)
        XCTAssertFalse(store.binding(for: 99).action.isBound)
    }
}

// MARK: - Sequences

/// Records what a run posts instead of posting real events, so tests can assert
/// order, timing and that no modifier was left down.
@MainActor
final class FakeEventSink: EventSink {
    struct Posted: Equatable {
        enum Kind: Equatable {
            case key(keyCode: UInt16, flags: UInt64, isDown: Bool)
            case click(kind: MouseClickKind, flags: UInt64, isDown: Bool)
            case system(SystemAction)
            case openApp(String)
            case openURL(String)
            case shell(String)
        }

        let kind: Kind
        let at: Date
    }

    /// The key codes that press and release ⌃⌥⇧⌘; anything else is "typed".
    static let modifierKeyCodes: Set<UInt16> = [59, 58, 56, 55]

    private(set) var posted: [Posted] = []
    /// Called for every recorded event, so a test can cancel mid-run.
    var onPost: (@MainActor (Posted) -> Void)?

    var systems: [SystemAction] { posted.compactMap(\.kind.system) }
    var openedApps: [String] { posted.compactMap(\.kind.openedApp) }
    var openedURLs: [String] { posted.compactMap(\.kind.openedURL) }
    var shellCommands: [String] { posted.compactMap(\.kind.shellCommand) }

    /// Non-modifier keys pressed, in order: the keystrokes a run actually types.
    var typedKeys: [UInt16] {
        posted.compactMap { entry in
            guard case .key(let keyCode, _, let isDown) = entry.kind,
                  isDown,
                  !Self.modifierKeyCodes.contains(keyCode) else { return nil }
            return keyCode
        }
    }

    /// Modifier key codes still down at the end. Empty is the only correct
    /// answer after a run, cancelled or not.
    var heldModifiers: Set<UInt16> {
        var down = Set<UInt16>()
        for entry in posted {
            guard case .key(let keyCode, _, let isDown) = entry.kind,
                  Self.modifierKeyCodes.contains(keyCode) else { continue }
            if isDown {
                down.insert(keyCode)
            } else {
                down.remove(keyCode)
            }
        }
        return down
    }

    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, isDown: Bool) {
        record(.key(keyCode: keyCode, flags: flags.rawValue, isDown: isDown))
    }

    func postMouseClick(_ kind: MouseClickKind, flags: CGEventFlags, isDown: Bool) {
        record(.click(kind: kind, flags: flags.rawValue, isDown: isDown))
    }

    func postSystem(_ action: SystemAction) { record(.system(action)) }
    func openApp(at path: String) { record(.openApp(path)) }
    func openURL(_ string: String) { record(.openURL(string)) }
    func runShell(_ command: String) { record(.shell(command)) }

    private func record(_ kind: Posted.Kind) {
        let entry = Posted(kind: kind, at: Date())
        posted.append(entry)
        onPost?(entry)
    }
}

private extension FakeEventSink.Posted.Kind {
    var system: SystemAction? {
        if case .system(let action) = self { return action }
        return nil
    }

    var openedApp: String? {
        if case .openApp(let path) = self { return path }
        return nil
    }

    var openedURL: String? {
        if case .openURL(let url) = self { return url }
        return nil
    }

    var shellCommand: String? {
        if case .shell(let command) = self { return command }
        return nil
    }
}

/// Collects `onStep` indices without capturing a mutable local in an escaping
/// closure.
@MainActor
private final class StepRecorder {
    private(set) var indices: [Int] = []
    func record(_ index: Int) { indices.append(index) }
}

@MainActor
final class MacroRunnerTests: XCTestCase {
    private let command = NSEvent.ModifierFlags.command.rawValue
    /// The same mask as the fake sink records it in `CGEventFlags`.
    private var commandFlags: UInt64 { UInt64(command) }

    private func steps(_ actions: [SystemAction]) -> [ActionStep] {
        actions.map { ActionStep(kind: .system, system: $0) }
    }

    // MARK: Order and progress

    func testSequenceFiresStepsInOrder() async throws {
        let fake = FakeEventSink()
        MacroRunner.run(
            steps([.missionControl, .back, .forward]),
            owner: .other("order"),
            sink: fake
        )

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(fake.systems, [.missionControl, .back, .forward])
    }

    func testOnStepReportsEveryStepInOrder() async throws {
        let fake = FakeEventSink()
        let recorder = StepRecorder()
        MacroRunner.run(
            steps([.missionControl, .back, .forward]),
            owner: .other("indices"),
            onStep: { recorder.record($0) },
            sink: fake
        )

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(recorder.indices, [0, 1, 2])
        XCTAssertEqual(fake.systems.count, 3)
    }

    func testEachStepWaitsItsDelayFirst() async throws {
        let fake = FakeEventSink()
        let steps = [
            ActionStep(kind: .system, system: .missionControl),
            ActionStep(kind: .system, system: .back, delayMilliseconds: 120),
            ActionStep(kind: .system, system: .forward)
        ]
        MacroRunner.run(steps, owner: .other("delay"), sink: fake)

        try await Task.sleep(for: .milliseconds(450))

        XCTAssertEqual(fake.systems, [.missionControl, .back, .forward])
        let gap = fake.posted[1].at.timeIntervalSince(fake.posted[0].at)
        XCTAssertGreaterThanOrEqual(gap, 0.10, "the 120 ms delay must be honoured (150 ms tolerance)")
        XCTAssertLessThan(gap, 0.30)
    }

    // MARK: Cancellation

    func testEmptySequenceIsANoOp() async throws {
        let fake = FakeEventSink()
        MacroRunner.run([], owner: .other("empty"), sink: fake)
        ActionExecutor.perform(MouseAction(kind: .sequence), owner: .other("empty-action"))

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(fake.posted.isEmpty)
    }

    func testSecondRunCancelsTheFirst() async throws {
        let fake = FakeEventSink()
        let owner = MacroOwner.other("restart")

        MacroRunner.run(
            [ActionStep(kind: .system, system: .back, delayMilliseconds: 200)],
            owner: owner,
            sink: fake
        )
        MacroRunner.run(
            [ActionStep(kind: .system, system: .forward)],
            owner: owner,
            sink: fake
        )

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(fake.systems, [.forward], "the first run must not resume after the second starts")
    }

    func testCancelStopsBeforeTheNextStep() async throws {
        let fake = FakeEventSink()
        let owner = MacroOwner.other("cancel")
        fake.onPost = { _ in MacroRunner.cancel(owner: owner) }

        MacroRunner.run(
            (0..<3).map { _ in ActionStep(kind: .system, system: .missionControl, delayMilliseconds: 20) },
            owner: owner,
            sink: fake
        )

        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(fake.systems, [.missionControl], "cancelling must stop the steps that have not fired")
    }

    func testCancelDuringAStepStillReleasesModifiers() async throws {
        let fake = FakeEventSink()
        let owner = MacroOwner.other("chord-cancel")
        // Cancel from inside the step, which is the worst case the executor has
        // to survive: the press has already happened when the cancel arrives.
        fake.onPost = { entry in
            if case .click(_, _, let isDown) = entry.kind, isDown {
                MacroRunner.cancel(owner: owner)
            }
        }

        MacroRunner.run(
            [ActionStep(kind: .mouseClick, click: .left, clickModifiers: command)],
            owner: owner,
            sink: fake
        )

        try await Task.sleep(for: .milliseconds(120))

        XCTAssertTrue(fake.heldModifiers.isEmpty, "⌘ must be released even when the run is cancelled mid-click")
        XCTAssertEqual(fake.posted.map(\.kind), [
            .key(keyCode: 55, flags: commandFlags, isDown: true),
            .click(kind: .left, flags: commandFlags, isDown: true),
            .click(kind: .left, flags: commandFlags, isDown: false),
            .key(keyCode: 55, flags: 0, isDown: false)
        ])
    }

    func testCancelAllStopsEveryOwner() async throws {
        let fake = FakeEventSink()
        let slow = [ActionStep(kind: .system, system: .back, delayMilliseconds: 100)]

        MacroRunner.run(slow, owner: .button(3), sink: fake)
        MacroRunner.run(slow, owner: .shortcut("key-123-0"), sink: fake)
        MacroRunner.cancelAll()

        try await Task.sleep(for: .milliseconds(250))

        XCTAssertTrue(fake.posted.isEmpty)
    }

    // MARK: Counting and caps

    func testPlanDropsStepsBeyondTheTotalBudget() {
        let steps = (0..<SequenceLimits.maxSteps).map { _ in
            ActionStep(kind: .system, system: .back, delayMilliseconds: SequenceLimits.maxStepDelayMilliseconds)
        }

        let plan = MacroRunner.plan(for: steps)

        // 500 ms each: six steps fit in 3000 ms, the seventh would not.
        XCTAssertEqual(plan.count, 6)
        XCTAssertEqual(plan.map(\.delayMilliseconds).reduce(0, +), SequenceLimits.maxTotalMilliseconds)
        XCTAssertEqual(plan.map(\.index), [0, 1, 2, 3, 4, 5])
        XCTAssertTrue(MacroRunner.plan(for: []).isEmpty)
    }

    func testNormalisationDropsEmptyAndNestedSteps() {
        let steps = [
            ActionStep(kind: .none),
            ActionStep(kind: .system, system: .back),
            ActionStep(kind: .sequence),
            ActionStep(kind: .none),
            ActionStep(kind: .system, system: .forward)
        ]

        XCTAssertEqual(steps.normalized().map(\.system), [.back, .forward])
    }

    func testNormalisationClampsDelayOnLoad() {
        let step = ActionStep(kind: .system, system: .back, delayMilliseconds: 9_999)

        XCTAssertEqual([step].normalized().first?.delayMilliseconds, SequenceLimits.maxStepDelayMilliseconds)
        XCTAssertEqual(
            [ActionStep(kind: .system, system: .back, delayMilliseconds: -50)].normalized().first?.delayMilliseconds,
            0
        )
    }

    func testNormalisationTruncatesToMaxSteps() {
        let steps = (0..<12).map { _ in ActionStep(kind: .system, system: .back) }

        XCTAssertEqual(steps.normalized().count, SequenceLimits.maxSteps)
    }

    func testNormalisedSequenceIgnoresStepsOnOtherKinds() {
        let step = ActionStep(kind: .system, system: .back)

        XCTAssertEqual(MouseAction(kind: .sequence, steps: [step]).normalizedSequence(), [step])
        XCTAssertTrue(MouseAction(kind: .system, steps: [step]).normalizedSequence().isEmpty)
    }

    // MARK: Action executor

    func testSequenceThroughActionExecutorUsesTheInjectedSink() async throws {
        let fake = FakeEventSink()
        ActionExecutor.sink = fake
        let action = MouseAction(kind: .sequence, steps: [
            ActionStep(kind: .keyboardShortcut, keyCode: 8, modifiers: command, hasShortcut: true),
            ActionStep(kind: .system, system: .back)
        ])

        ActionExecutor.perform(action, owner: .other("sequence"))

        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(fake.typedKeys, [8])
        XCTAssertEqual(fake.systems, [.back])
        XCTAssertTrue(fake.heldModifiers.isEmpty)
        ActionExecutor.sink = LiveEventSink()
    }

    func testExistingKindsStillPostTheirEvents() {
        let fake = FakeEventSink()
        ActionExecutor.sink = fake

        ActionExecutor.perform(MouseAction(kind: .system, system: .missionControl), owner: .other("system"))
        ActionExecutor.perform(
            MouseAction(kind: .keyboardShortcut, keyCode: 8, modifiers: command, hasShortcut: true),
            owner: .other("key")
        )
        ActionExecutor.perform(MouseAction(kind: .openApp, text: "/System/Applications/Calculator.app"), owner: .other("app"))
        ActionExecutor.perform(MouseAction(kind: .openURL, text: "https://example.com"), owner: .other("url"))
        ActionExecutor.perform(MouseAction(kind: .shellCommand, text: "echo hi"), owner: .other("shell"))
        // Unbound and unrecorded actions must stay silent.
        ActionExecutor.perform(.none, owner: .other("none"))
        ActionExecutor.perform(MouseAction(kind: .keyboardShortcut, keyCode: 8), owner: .other("unrecorded"))

        XCTAssertEqual(fake.systems, [.missionControl])
        XCTAssertEqual(fake.typedKeys, [8])
        XCTAssertEqual(fake.openedApps, ["/System/Applications/Calculator.app"])
        XCTAssertEqual(fake.openedURLs, ["https://example.com"])
        XCTAssertEqual(fake.shellCommands, ["echo hi"])
        XCTAssertTrue(fake.heldModifiers.isEmpty, "the shortcut's ⌘ must be released")

        ActionExecutor.sink = LiveEventSink()
    }

    func testChordClickHoldsItsModifierAndReleasesIt() {
        let fake = FakeEventSink()
        ActionExecutor.sink = fake

        ActionExecutor.perform(
            MouseAction(kind: .mouseClick, click: .left, clickModifiers: command),
            owner: .other("chord")
        )

        XCTAssertEqual(fake.posted.map(\.kind), [
            .key(keyCode: 55, flags: commandFlags, isDown: true),
            .click(kind: .left, flags: commandFlags, isDown: true),
            .click(kind: .left, flags: commandFlags, isDown: false),
            .key(keyCode: 55, flags: 0, isDown: false)
        ])

        ActionExecutor.sink = LiveEventSink()
    }
}
