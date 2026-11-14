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
        XCTAssertTrue(ActionKind.editableCases.contains(.sequence), "the editor now offers Sequence")
        XCTAssertTrue(ActionKind.editableCases.contains(.mouseClick), "every kind should be reachable from the picker")
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

    // MARK: Editing a whole action through the step type

    func testApplyingAStepKeepsTheSequenceSteps() {
        var action = MouseAction(
            kind: .sequence,
            steps: [ActionStep(kind: .system, system: .back)]
        )
        action.apply(ActionStep(kind: .mouseClick, click: .left, clickModifiers: command))

        XCTAssertEqual(action.kind, .mouseClick)
        XCTAssertEqual(action.clickModifiers, command)
        XCTAssertEqual(action.steps.count, 1, "editing the fields must not drop the sequence")
    }

    func testStepAndActionRoundTripEveryPerKindField() {
        let original = MouseAction(
            kind: .mouseClick,
            system: .spotlight,
            keyCode: 21,
            modifiers: option,
            hasShortcut: true,
            click: .right,
            clickModifiers: command,
            text: "/Applications/Safari.app",
            steps: [ActionStep(kind: .system, system: .forward)]
        )
        var copied = original
        copied.apply(original.asStep)

        XCTAssertEqual(copied, original, "the editor's field bridge must be lossless")
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

    // MARK: - Never writing the live config

    func testTestRunsAreEphemeralAndDoNotUseTheRealDirectory() {
        // The test host is the app bundle, so AppModel.shared really does build
        // a ConfigStore during a test run. If that used the support directory,
        // every test run (and every parallel worktree run) would rewrite the
        // user's live config.
        XCTAssertTrue(ConfigStore.isEphemeralLaunch)

        let directory = ConfigStore.defaultDirectory(fileManager: .default)
        XCTAssertNotEqual(directory.path, ConfigStore.supportDirectory?.path)
        XCTAssertTrue(directory.path.contains("CitllaE510-"), "expected a throwaway directory, got \(directory.path)")
    }

    func testExplicitDirectoryOverrideWins() {
        setenv("CITLLA_CONFIG_DIR", "/tmp/citlla-config-override", 1)
        defer { unsetenv("CITLLA_CONFIG_DIR") }

        XCTAssertEqual(
            ConfigStore.defaultDirectory(fileManager: .default).path,
            "/tmp/citlla-config-override"
        )
    }

    func testExplicitOverrideDirectoryIsWhereTheConfigLands() throws {
        setenv("CITLLA_CONFIG_DIR", "/tmp/citlla-config-override", 1)
        defer {
            unsetenv("CITLLA_CONFIG_DIR")
            try? FileManager.default.removeItem(atPath: "/tmp/citlla-config-override")
        }

        let store = ConfigStore()
        store.setAction(MouseAction(kind: .system, system: .mute), for: 3)

        let fixture = URL(fileURLWithPath: "/tmp/citlla-config-override/config.json")
        let data = try Data(contentsOf: fixture)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.action(for: 3)?.system, .mute)
    }

    func testScrollSettingsArePersistedAndReloaded() {
        let store = ConfigStore(directory: directory)
        store.config.scroll.invertHorizontal = true
        store.config.scroll.setAction(MouseAction(kind: .system, system: .missionControl), for: .left)

        let reopened = ConfigStore(directory: directory)

        XCTAssertTrue(reopened.config.scroll.invertHorizontal)
        XCTAssertEqual(reopened.config.scroll.tiltLeft.system, .missionControl)
        XCTAssertFalse(reopened.config.scroll.tiltRight.isBound)
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


final class ScrollSettingsTests: XCTestCase {
    func testDefaultsLeaveScrollingStock() {
        let settings = AppConfig().scroll

        XCTAssertFalse(settings.invertVertical)
        XCTAssertFalse(settings.invertHorizontal)
        XCTAssertEqual(settings.tiltLeft, MouseAction())
        XCTAssertEqual(settings.tiltRight, MouseAction())
        XCTAssertFalse(settings.hasTiltActions)
    }

    func testOldConfigWithoutScrollKeyLoadsWithItsBindings() throws {
        // Exactly what a config written by the shipped build looks like: no
        // `scroll` key at all.
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
        XCTAssertEqual(config.scroll, ScrollSettings())
        XCTAssertFalse(config.scroll.invertVertical)
        XCTAssertFalse(config.scroll.tiltLeft.isBound)
    }

    func testPartialScrollSettingsFillInDefaults() throws {
        let json = Data(#"{"scroll": {"invertVertical": true}}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertTrue(config.scroll.invertVertical)
        XCTAssertFalse(config.scroll.invertHorizontal)
        XCTAssertEqual(config.scroll.tiltLeft, MouseAction())
        XCTAssertEqual(config.scroll.tiltRight, MouseAction())
    }

    func testScrollSettingsRoundTripThroughTheConfig() throws {
        var config = AppConfig()
        config.scroll.invertVertical = true
        config.scroll.invertHorizontal = true
        config.scroll.tiltLeft = MouseAction(kind: .system, system: .back)
        config.scroll.tiltRight = MouseAction(kind: .keyboardShortcut, keyCode: 8, modifiers: NSEvent.ModifierFlags.command.rawValue, hasShortcut: true)

        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))

        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.scroll.tiltRight.summary, "⌘C")
    }

    func testResetLeavesStockScrollingAlone() {
        var config = AppConfig()
        config.scroll.invertVertical = true
        config.scroll.tiltLeft = MouseAction(kind: .system, system: .back)

        config.resetToDefaults()

        // The reset dialog on the Buttons page talks about buttons only, so a
        // scroll setting the user chose must survive it.
        XCTAssertTrue(config.scroll.invertVertical)
        XCTAssertEqual(config.scroll.tiltLeft.system, .back)
    }

    func testTiltActionsAreAddressedByDirection() {
        var scroll = ScrollSettings()
        scroll.setAction(MouseAction(kind: .system, system: .forward), for: .right)

        XCTAssertEqual(scroll.action(for: .right).system, .forward)
        XCTAssertEqual(scroll.action(for: .left), MouseAction())
        XCTAssertTrue(scroll.hasTiltActions)
    }
}

final class ScrollControllerTests: XCTestCase {
    // MARK: - Helpers

    private func scrollEvent(
        units: CGScrollEventUnit = .line,
        vertical: Int32 = 0,
        horizontal: Int32 = 0
    ) -> CGEvent {
        CGEvent(
            scrollWheelEvent2Source: nil,
            units: units,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        )!
    }

    private static let deltaFields: [(String, CGEventField)] = [
        ("line1", .scrollWheelEventDeltaAxis1),
        ("line2", .scrollWheelEventDeltaAxis2),
        ("point1", .scrollWheelEventPointDeltaAxis1),
        ("point2", .scrollWheelEventPointDeltaAxis2),
        ("fixed1", .scrollWheelEventFixedPtDeltaAxis1),
        ("fixed2", .scrollWheelEventFixedPtDeltaAxis2)
    ]

    /// Every field the scroll path could plausibly disturb. Comparing this
    /// before and after is what "the event is untouched" means.
    private func snapshot(_ event: CGEvent) -> String {
        var parts = Self.deltaFields.map { name, field in
            "\(name)=\(event.getIntegerValueField(field))"
        }
        parts.append("continuous=\(event.getIntegerValueField(.scrollWheelEventIsContinuous))")
        parts.append("phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase))")
        parts.append("momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))")
        parts.append("count=\(event.getIntegerValueField(.scrollWheelEventScrollCount))")
        parts.append("marker=\(event.getIntegerValueField(.eventSourceUserData))")
        parts.append("flags=\(event.flags.rawValue)")
        parts.append("timestamp=\(event.timestamp)")
        return parts.joined(separator: " ")
    }

    private func deltas(_ event: CGEvent) -> [Int64] {
        Self.deltaFields.map { event.getIntegerValueField($1) }
    }

    // MARK: - Inversion

    func testInvertsVerticalAxisInPlace() {
        let event = scrollEvent(vertical: 3)
        let before = deltas(event)
        var controller = ScrollController()
        var settings = ScrollSettings()
        settings.invertVertical = true

        XCTAssertEqual(controller.handle(event, settings: settings), .rewritten)
        XCTAssertEqual(deltas(event), before.map { -$0 })
        XCTAssertGreaterThan(before[0], 0)
        XCTAssertLessThan(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0, "the other axis stays put")
    }

    func testInvertsHorizontalAxisOnlyWhenAsked() {
        let event = scrollEvent(vertical: 2, horizontal: -5)
        let verticalBefore = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let horizontalBefore = deltas(event)[1]
        var controller = ScrollController()
        var settings = ScrollSettings()
        settings.invertHorizontal = true

        XCTAssertEqual(controller.handle(event, settings: settings), .rewritten)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), verticalBefore)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), -horizontalBefore)
    }

    func testInversionKeepsContinuousScrollingPrecise() {
        let event = scrollEvent(units: .pixel, vertical: -7, horizontal: 3)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        let before = deltas(event)
        var controller = ScrollController()
        var settings = ScrollSettings()
        settings.invertVertical = true
        settings.invertHorizontal = true

        XCTAssertEqual(controller.handle(event, settings: settings), .rewritten)

        // The fixed-point fields carry the smooth deltas: exactly negated, not
        // rounded through the whole-line field.
        XCTAssertEqual(deltas(event), before.map { -$0 })
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollPhase), 2)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventMomentumPhase), 2)
    }

    func testInvertingTwiceRestoresTheOriginalEvent() {
        let event = scrollEvent(vertical: -4, horizontal: 9)
        let before = snapshot(event)
        var controller = ScrollController()
        var settings = ScrollSettings()
        settings.invertVertical = true
        settings.invertHorizontal = true

        _ = controller.handle(event, settings: settings)
        _ = controller.handle(event, settings: settings)

        XCTAssertEqual(snapshot(event), before)
    }

    // MARK: - Pass-through

    func testDisabledSettingsLeaveTheEventByteForByteUntouched() {
        let event = scrollEvent(units: .pixel, vertical: -7, horizontal: 3)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        let before = snapshot(event)
        var controller = ScrollController()

        XCTAssertEqual(controller.handle(event, settings: ScrollSettings()), .passThrough)
        XCTAssertEqual(snapshot(event), before)
    }

    func testEventTheAppPostedItselfIsNeverTouched() {
        let event = scrollEvent(vertical: 4, horizontal: 4)
        // A scroll event posted by the app (or a future re-poster) carries the
        // marker; inverting it would turn a remapped scroll into a loop.
        event.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
        let before = snapshot(event)
        var controller = ScrollController()
        var settings = ScrollSettings()
        settings.invertVertical = true
        settings.invertHorizontal = true
        settings.tiltRight = MouseAction(kind: .system, system: .forward)

        XCTAssertEqual(controller.handle(event, settings: settings), .passThrough)
        XCTAssertEqual(snapshot(event), before)
    }

    // MARK: - Tap mask

    @MainActor
    func testTapWatchesScrollWheelEvents() {
        XCTAssertTrue(EventTapService.eventTypes.contains(.scrollWheel))
    }

    // MARK: - Tilt gestures

    private func firingSettings() -> ScrollSettings {
        var settings = ScrollSettings()
        settings.tiltLeft = MouseAction(kind: .system, system: .back)
        settings.tiltRight = MouseAction(kind: .system, system: .forward)
        return settings
    }

    func testTiltFiresOncePerGesture() {
        let settings = firingSettings()
        var controller = ScrollController()
        let event = scrollEvent(horizontal: 1)

        XCTAssertEqual(controller.handle(event, settings: settings, at: 100.00), .tilt(.right, fire: true))
        // The rest of the burst: swallowed, but must not fire again.
        XCTAssertEqual(controller.handle(event, settings: settings, at: 100.02), .tilt(.right, fire: false))
        XCTAssertEqual(controller.handle(event, settings: settings, at: 100.08), .tilt(.right, fire: false))
        XCTAssertEqual(controller.handle(event, settings: settings, at: 100.20), .tilt(.right, fire: false))
        // A new flick after the wheel has been quiet for the cooldown.
        XCTAssertEqual(controller.handle(event, settings: settings, at: 100.51), .tilt(.right, fire: true))
    }

    func testTiltCooldownUsesTheEventTimestampWhenNoneIsGiven() {
        let settings = firingSettings()
        var controller = ScrollController()
        // The same event twice: same timestamp, so the second call is inside
        // the window without an explicit time.
        let event = scrollEvent(horizontal: -1)

        XCTAssertEqual(controller.handle(event, settings: settings), .tilt(.left, fire: true))
        XCTAssertEqual(controller.handle(event, settings: settings), .tilt(.left, fire: false))
    }

    func testDirectionsHaveIndependentGestures() {
        var controller = ScrollController()
        let settings = firingSettings()

        XCTAssertEqual(controller.handle(scrollEvent(horizontal: 1), settings: settings, at: 10), .tilt(.right, fire: true))
        XCTAssertEqual(controller.handle(scrollEvent(horizontal: -1), settings: settings, at: 10), .tilt(.left, fire: true))
        XCTAssertEqual(controller.handle(scrollEvent(horizontal: 1), settings: settings, at: 10.1), .tilt(.right, fire: false))
    }

    func testTiltDirectionFollowsTheHorizontalSign() {
        XCTAssertEqual(TiltDirection.direction(forHorizontalDelta: 3), .right)
        XCTAssertEqual(TiltDirection.direction(forHorizontalDelta: -3), .left)
        XCTAssertNil(TiltDirection.direction(forHorizontalDelta: 0))
    }

    func testTrackpadHorizontalPanIsNotATilt() {
        var settings = firingSettings()
        settings.invertHorizontal = true
        var controller = ScrollController()

        let pan = scrollEvent(units: .pixel, horizontal: 12)
        pan.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        pan.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)

        // It is an honest scroll: inverted like any other, never mistaken for a
        // side-wheel flick.
        XCTAssertEqual(controller.handle(pan, settings: settings, at: 5), .rewritten)
        XCTAssertEqual(pan.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -12)
        XCTAssertEqual(pan.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
    }

    func testShiftWheelIsNotATilt() {
        var settings = firingSettings()
        settings.invertVertical = true
        var controller = ScrollController()

        // Some drivers turn shift+wheel into the horizontal axis before the
        // tap sees it. The shift is what keeps that an honest scroll.
        let shifted = scrollEvent(horizontal: 2)
        shifted.flags = .maskShift

        XCTAssertEqual(controller.handle(shifted, settings: settings, at: 5), .passThrough)
        XCTAssertEqual(shifted.getIntegerValueField(.scrollWheelEventDeltaAxis2), 2)
    }

    func testVerticalScrollDoesNotTriggerATilt() {
        var controller = ScrollController()
        let event = scrollEvent(vertical: 3)

        XCTAssertEqual(controller.handle(event, settings: firingSettings(), at: 5), .passThrough)
    }

    func testTiltWithASmallVerticalComponentStillFires() {
        var controller = ScrollController()
        // The wheel can report a little movement on axis 1 with a flick; the
        // horizontal delta dominates, so it is still a tilt.
        let event = scrollEvent(vertical: 1, horizontal: 4)

        XCTAssertEqual(controller.handle(event, settings: firingSettings(), at: 5), .tilt(.right, fire: true))
    }

    func testDiagonalScrollIsNotATilt() {
        var controller = ScrollController()
        // A diagonal four-way wheel scroll: vertical dominates, so it is just a
        // scroll and must not fire a side-wheel action.
        let event = scrollEvent(vertical: 5, horizontal: 2)

        XCTAssertEqual(controller.handle(event, settings: firingSettings(), at: 5), .passThrough)
    }

    func testUnboundTiltStillScrollsHorizontally() {
        var settings = ScrollSettings()
        settings.invertHorizontal = true
        var controller = ScrollController()
        let event = scrollEvent(horizontal: 4)

        XCTAssertEqual(controller.handle(event, settings: settings, at: 5), .rewritten)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), -4)
    }

    func testTiltInTheUnboundDirectionStillScrolls() {
        var settings = ScrollSettings()
        settings.tiltRight = MouseAction(kind: .system, system: .forward)
        var controller = ScrollController()
        let leftwards = scrollEvent(horizontal: -4)

        // Only the right tilt is remapped, so a left tilt keeps scrolling.
        XCTAssertEqual(controller.handle(leftwards, settings: settings, at: 5), .passThrough)
    }
}

// MARK: - Macro editor

/// The editor's model logic: chord toggles, step list edits, caps, presets and
/// the preview string. No UI is instantiated, so these run headless.
final class MacroEditorTests: XCTestCase {
    private let command = NSEvent.ModifierFlags.command.rawValue
    private let control = NSEvent.ModifierFlags.control.rawValue
    private let shift = NSEvent.ModifierFlags.shift.rawValue

    private func preset(_ id: String) throws -> ActionPreset {
        try XCTUnwrap(ActionPreset.all.first { $0.id == id }, "missing preset \(id)")
    }

    // MARK: Chords

    func testChordToggleSetsAndClearsOneFlag() {
        var mask: UInt = 0
        mask = ChordModifier.setting(.command, on: true, in: mask)
        XCTAssertEqual(mask, command)
        XCTAssertTrue(ChordModifier.isOn(.command, in: mask))
        XCTAssertFalse(ChordModifier.isOn(.shift, in: mask))

        mask = ChordModifier.setting(.shift, on: true, in: mask)
        XCTAssertEqual(ChordModifier.modifiers(in: mask), [.shift, .command])

        mask = ChordModifier.setting(.command, on: false, in: mask)
        XCTAssertEqual(mask, shift)
        XCTAssertEqual(ChordModifier.modifiers(in: mask), [.shift])
        XCTAssertEqual(ChordModifier.mask(of: [.shift]), shift)
    }

    func testChordMaskReadsAsTheEditorPreview() {
        let mask = ChordModifier.mask(of: [.control, .shift, .command])
        let action = MouseAction(kind: .mouseClick, click: .left, clickModifiers: mask)

        XCTAssertEqual(action.summary, "⌃⇧⌘ Left Click")
        XCTAssertEqual(MouseAction.describe(click: .right, modifiers: shift), "⇧ Right Click")
    }

    // MARK: Step list

    func testAddStepUsesThePlanDefaultsAndStopsAtTheCap() {
        var steps: [ActionStep] = []

        XCTAssertTrue(steps.addStep())
        XCTAssertEqual(steps.first?.kind, .keyboardShortcut)
        XCTAssertEqual(steps.first?.delayMilliseconds, 0, "the first step has nothing to wait for")

        XCTAssertTrue(steps.addStep())
        XCTAssertEqual(steps.last?.delayMilliseconds, SequenceLimits.defaultStepDelayMilliseconds)

        steps.append(ActionStep(kind: .keyboardShortcut))
        steps[steps.count - 1].kind = .openApp
        XCTAssertTrue(steps.addStep())
        XCTAssertEqual(
            steps.last?.delayMilliseconds,
            SequenceLimits.defaultDelayAfterOpenAppMilliseconds,
            "an Open App step gets the longer wait before the next step"
        )

        while steps.count < SequenceLimits.maxSteps {
            XCTAssertTrue(steps.addStep())
        }
        XCTAssertEqual(steps.count, SequenceLimits.maxSteps)
        XCTAssertFalse(steps.addStep(), "the add button must stop at the cap")
        XCTAssertEqual(steps.count, SequenceLimits.maxSteps)
    }

    func testDuplicateStepInsertsACopyDirectlyAfterTheOriginal() {
        var steps = [
            ActionStep(kind: .system, system: .back),
            ActionStep(kind: .system, system: .forward)
        ]

        XCTAssertTrue(steps.duplicateStep(at: 0))
        XCTAssertEqual(steps.map(\.system), [.back, .back, .forward])
        XCTAssertFalse(steps.duplicateStep(at: 9), "out-of-range duplicate is a no-op")

        while steps.count < SequenceLimits.maxSteps {
            steps.duplicateStep(at: 0)
        }
        XCTAssertEqual(steps.count, SequenceLimits.maxSteps)
        XCTAssertFalse(steps.duplicateStep(at: 0), "duplicate must respect the cap")
    }

    func testDeleteStepAndBounds() {
        var steps = [
            ActionStep(kind: .system, system: .back),
            ActionStep(kind: .system, system: .missionControl),
            ActionStep(kind: .system, system: .forward)
        ]

        XCTAssertTrue(steps.deleteStep(at: 1))
        XCTAssertEqual(steps.map(\.system), [.back, .forward])
        XCTAssertFalse(steps.deleteStep(at: 7))
        XCTAssertFalse(steps.deleteStep(at: -1))
        XCTAssertEqual(steps.count, 2)
    }

    func testMoveStepReordersInBothDirections() {
        var steps = [
            ActionStep(kind: .system, system: .back),
            ActionStep(kind: .system, system: .missionControl),
            ActionStep(kind: .system, system: .forward)
        ]

        XCTAssertTrue(steps.moveStep(from: 0, to: 2))
        XCTAssertEqual(steps.map(\.system), [.missionControl, .forward, .back])

        XCTAssertTrue(steps.moveStep(from: 2, to: 0))
        XCTAssertEqual(steps.map(\.system), [.back, .missionControl, .forward])

        XCTAssertFalse(steps.moveStep(from: 1, to: 1))
        XCTAssertFalse(steps.moveStep(from: 0, to: 3))
        XCTAssertFalse(steps.moveStep(from: -1, to: 0))
        XCTAssertEqual(steps.count, 3)
    }

    // MARK: Preview

    func testPreviewPrintsDelaysInFiringOrder() {
        let steps = [
            ActionStep(kind: .keyboardShortcut, keyCode: 8, modifiers: command, hasShortcut: true),
            ActionStep(
                kind: .keyboardShortcut,
                keyCode: 9,
                modifiers: command,
                hasShortcut: true,
                delayMilliseconds: 100
            ),
            ActionStep(kind: .keyboardShortcut, keyCode: 36, hasShortcut: true, delayMilliseconds: 40)
        ]

        XCTAssertEqual(
            SequencePreview.text(for: steps),
            "⌘C → 100 ms → ⌘V → 40 ms → Return"
        )
        XCTAssertEqual(SequencePreview.totalDelay(of: steps), 140)
        // The legend/rows keep using the compact, delay-free summary.
        XCTAssertEqual(MouseAction(kind: .sequence, steps: steps).summary, "⌘C → ⌘V → Return")
    }

    func testPreviewIsEmptySafeAndClampsDelays() {
        XCTAssertEqual(SequencePreview.text(for: []), "No steps")
        XCTAssertEqual(SequencePreview.totalDelay(of: [
            ActionStep(kind: .system, system: .back, delayMilliseconds: 9_999)
        ]), SequenceLimits.maxStepDelayMilliseconds)
    }

    // MARK: Presets

    func testPresetCatalogHasUniqueIdentifiers() {
        let presets = ActionPreset.all

        XCTAssertEqual(presets.count, 6)
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
        XCTAssertTrue(presets.allSatisfy { !$0.name.isEmpty && !$0.detail.isEmpty })
    }

    func testCopyPastePresetIsASequenceWithAWait() throws {
        let action = try preset("copy-paste").make()

        XCTAssertEqual(action.kind, .sequence)
        XCTAssertEqual(action.steps.map(\.summary), ["⌘C", "⌘V"])
        XCTAssertEqual(action.steps[1].delayMilliseconds, 100)
        XCTAssertTrue(action.isBound)
    }

    func testScreenshotPresetSendsControlShiftCommand4() throws {
        let action = try preset("screenshot-area").make()

        XCTAssertEqual(action.kind, .keyboardShortcut)
        XCTAssertEqual(action.keyCode, 21)
        XCTAssertEqual(action.modifiers, NSEvent.ModifierFlags([.control, .shift, .command]).rawValue)
        XCTAssertTrue(action.hasShortcut)
        XCTAssertEqual(action.summary, "⌃⇧⌘4")
    }

    func testFinderNewFolderPresetSendsShiftCommandN() throws {
        let action = try preset("finder-new-folder").make()

        XCTAssertEqual(action.kind, .keyboardShortcut)
        XCTAssertEqual(action.keyCode, 45)
        XCTAssertEqual(action.modifiers, shift | command)
        XCTAssertEqual(action.summary, "⇧⌘N")
    }

    func testSafariPresetActivatesThenSendsCommandT() throws {
        let action = try preset("safari-new-tab").make()

        XCTAssertEqual(action.kind, .sequence)
        XCTAssertEqual(action.steps.map(\.kind), [.openApp, .keyboardShortcut])
        XCTAssertEqual(action.steps[0].text, "/Applications/Safari.app")
        XCTAssertEqual(action.steps[1].summary, "⌘T")
        XCTAssertEqual(
            action.steps[1].delayMilliseconds,
            SequenceLimits.defaultDelayAfterOpenAppMilliseconds,
            "the app needs a moment to take focus before ⌘T lands"
        )
    }

    func testOpenAppPresetWaitsThenSendsCommandN() throws {
        let action = try preset("open-app-new-window").make()

        XCTAssertEqual(action.steps.first?.kind, .openApp)
        XCTAssertEqual(action.steps.last?.summary, "⌘N")
        XCTAssertEqual(
            action.steps.last?.delayMilliseconds,
            SequenceLimits.defaultDelayAfterOpenAppMilliseconds
        )
    }

    func testCommandClickPresetProducesAChord() throws {
        let action = try preset("command-click").make()

        XCTAssertEqual(action.kind, .mouseClick)
        XCTAssertEqual(action.click, .left)
        XCTAssertEqual(action.clickModifiers, command)
        XCTAssertEqual(action.summary, "⌘ Left Click")
    }

    func testPresetSequencesFitTheCaps() {
        for preset in ActionPreset.all {
            let action = preset.make()
            XCTAssertLessThanOrEqual(action.steps.count, SequenceLimits.maxSteps, preset.id)
            XCTAssertLessThanOrEqual(
                SequencePreview.totalDelay(of: action.steps),
                SequenceLimits.maxTotalMilliseconds,
                preset.id
            )
            XCTAssertFalse(action.steps.contains { $0.kind == .sequence }, preset.id)
            XCTAssertTrue(action.isBound, preset.id)
        }
    }

    // MARK: Tester progress model

    func testSequenceProgressCountsStepsAndMarksTheLastOne() {
        var progress = SequenceProgress(
            label: "Middle Click",
            steps: (0..<3).map { _ in ActionStep(kind: .system, system: .back) }
        )

        XCTAssertNil(progress.currentNumber)
        progress.current = 1
        XCTAssertEqual(progress.currentNumber, 2)
        XCTAssertFalse(progress.finished)

        progress.current = 2
        progress.finished = true
        XCTAssertEqual(progress.currentNumber, 3)
        XCTAssertEqual(progress.total, 3)
    }
}

// MARK: - Profiles

/// Precedence for per-app overrides: an enabled profile wins for a control it
/// overrides, every other control falls back to the global map, and nothing a
/// profile does can switch a global action off by accident.
final class AppProfileTests: XCTestCase {
    private let chrome = "com.google.Chrome"
    private let control = NSEvent.ModifierFlags.control.rawValue

    /// A small global map with a bound button (3), a bound second button (2),
    /// a bound keyboard control (⌃←) and a bound consumer key (volume up), plus
    /// a Chrome profile that overrides three of the four.
    private func chromeConfig() -> AppConfig {
        var config = AppConfig()
        config.setAction(MouseAction(kind: .system, system: .back), for: 3)
        config.setAction(MouseAction(kind: .system, system: .forward), for: 2)
        config.setAction(
            MouseAction(kind: .system, system: .missionControl),
            forShortcut: ShortcutBinding.defaults[0].id
        )
        let consumer = config.learnConsumerKey(0)
        config.setAction(MouseAction(kind: .system, system: .mute), forShortcut: consumer)

        config.setProfile(AppProfile(
            id: chrome,
            name: "Google Chrome",
            buttonActions: [3: MouseAction(kind: .system, system: .appExpose)],
            shortcutActions: [
                ShortcutBinding.defaults[0].id: MouseAction(kind: .system, system: .showDesktop),
                consumer: MouseAction(kind: .system, system: .playPause)
            ]
        ))
        return config
    }

    // MARK: Precedence

    func testProfileOverrideWinsForAButton() {
        let config = chromeConfig()

        XCTAssertEqual(config.action(for: 3, frontmostBundleID: chrome)?.system, .appExpose)
        XCTAssertEqual(config.action(for: 3)?.system, .back, "the global map must be untouched")
    }

    func testProfileOverrideWinsForAKeyboardShortcut() {
        let config = chromeConfig()

        let overridden = config.action(
            forKeyboardKeyCode: 123,
            modifiers: control,
            frontmostBundleID: chrome
        )
        XCTAssertEqual(overridden?.1.system, .showDesktop)
        XCTAssertEqual(overridden?.0.id, ShortcutBinding.defaults[0].id)

        let global = config.action(forKeyboardKeyCode: 123, modifiers: control)
        XCTAssertEqual(global?.1.system, .missionControl)
    }

    func testProfileOverrideWinsForAConsumerKey() {
        let config = chromeConfig()

        XCTAssertEqual(
            config.action(forConsumerKey: 0, frontmostBundleID: chrome)?.1.system,
            .playPause
        )
        XCTAssertEqual(config.action(forConsumerKey: 0)?.1.system, .mute)
    }

    func testControlTheProfileDoesNotOverrideFallsBackToGlobal() {
        let config = chromeConfig()

        XCTAssertEqual(config.action(for: 2, frontmostBundleID: chrome)?.system, .forward)
        XCTAssertEqual(
            config.action(forKeyboardKeyCode: 124, modifiers: control, frontmostBundleID: chrome)?.1.system,
            .forward
        )
    }

    func testProfileCanBindAControlThatIsUnboundGlobally() {
        // The ninth control ships unbound so the factory ⌃⌘F keeps working. A
        // profile may still give it a job without changing the global map.
        var config = AppConfig()
        let fullScreen = NSEvent.ModifierFlags([.control, .command]).rawValue
        let ninth = ShortcutBinding(keyCode: 3, modifiers: fullScreen)
        config.setProfile(AppProfile(
            id: chrome,
            name: "Google Chrome",
            shortcutActions: [ninth.id: MouseAction(kind: .system, system: .spotlight)]
        ))

        XCTAssertEqual(
            config.action(forKeyboardKeyCode: 3, modifiers: fullScreen, frontmostBundleID: chrome)?.1.system,
            .spotlight
        )
        XCTAssertFalse(
            config.action(forKeyboardKeyCode: 3, modifiers: fullScreen)?.1.isBound ?? true,
            "the global ninth control stays unbound"
        )
    }

    // MARK: Ignored profiles

    func testDisabledProfileIsIgnoredEntirely() {
        var config = chromeConfig()
        config.profiles[0].enabled = false

        XCTAssertNil(config.profile(forBundleIdentifier: chrome))
        XCTAssertEqual(config.action(for: 3, frontmostBundleID: chrome)?.system, .back)
        XCTAssertEqual(
            config.action(forKeyboardKeyCode: 123, modifiers: control, frontmostBundleID: chrome)?.1.system,
            .missionControl
        )
        XCTAssertEqual(config.action(forConsumerKey: 0, frontmostBundleID: chrome)?.1.system, .mute)
    }

    func testProfileForTheAppsOwnBundleIsNeverApplied() {
        var config = chromeConfig()
        config.setProfile(AppProfile(
            id: AppConfig.ownBundleIdentifier,
            name: "Citlla E510",
            buttonActions: [3: MouseAction(kind: .system, system: .appExpose)]
        ))

        XCTAssertNil(config.profile(forBundleIdentifier: AppConfig.ownBundleIdentifier))
        XCTAssertEqual(config.action(for: 3, frontmostBundleID: AppConfig.ownBundleIdentifier)?.system, .back)
    }

    func testUnknownOrAbsentBundleUsesTheGlobalMap() {
        let config = chromeConfig()
        let bundles: [String?] = [nil, "", "com.example.notinstalled"]

        for bundle in bundles {
            XCTAssertEqual(config.action(for: 3, frontmostBundleID: bundle)?.system, .back)
            XCTAssertEqual(
                config.action(forKeyboardKeyCode: 123, modifiers: control, frontmostBundleID: bundle)?.1.system,
                .missionControl
            )
        }
    }

    func testUnboundOverrideEntryFallsThroughToGlobal() {
        var config = chromeConfig()
        // A hand-edited file (or an older editor) can store an action that does
        // nothing. That must not silently disable the global binding.
        config.profiles[0].buttonActions[3] = MouseAction()
        config.profiles[0].shortcutActions[ShortcutBinding.defaults[0].id] = MouseAction()

        XCTAssertEqual(config.action(for: 3, frontmostBundleID: chrome)?.system, .back)
        XCTAssertEqual(
            config.action(forKeyboardKeyCode: 123, modifiers: control, frontmostBundleID: chrome)?.1.system,
            .missionControl
        )
    }

    // MARK: Storage

    func testOverrideCountIgnoresUnboundEntries() {
        var profile = AppProfile(id: chrome, name: "Google Chrome")
        XCTAssertEqual(profile.overrideCount, 0)

        profile.setButtonAction(MouseAction(kind: .system, system: .back), for: 3)
        profile.setShortcutAction(MouseAction(kind: .system, system: .mute), for: "consumer-0")
        XCTAssertEqual(profile.overrideCount, 2)

        // "Use Global" / an empty action removes the override.
        profile.setButtonAction(nil, for: 3)
        profile.setShortcutAction(MouseAction(), for: "consumer-0")
        XCTAssertEqual(profile.overrideCount, 0)
        XCTAssertTrue(profile.buttonActions.isEmpty)
        XCTAssertTrue(profile.shortcutActions.isEmpty)
    }

    func testConfigRoundTripWithProfiles() throws {
        var config = chromeConfig()
        config.profiles[0].enabled = false

        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))

        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.profiles.first?.enabled, false)
        XCTAssertEqual(decoded.profiles.first?.buttonActions[3]?.system, .appExpose)
    }

    func testOldConfigWithoutProfilesKeyStillDecodes() throws {
        let json = Data(#"""
        {
          "enabled": true,
          "bindings": [
            {"button": 3, "action": {"kind": "system", "system": "missionControl"}}
          ]
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertTrue(config.profiles.isEmpty)
        XCTAssertEqual(config.action(for: 3)?.system, .missionControl, "an absent profiles key must not reset the file")
        XCTAssertEqual(config.bindings.map(\.button), [1, 2, 3])
    }

    func testOneMalformedProfileDoesNotResetTheConfig() throws {
        // A single bad entry is dropped; the valid profile and the global map
        // survive. Failing the whole decode would silently reset every binding.
        let json = Data(#"""
        {
          "bindings": [
            {"button": 3, "action": {"kind": "system", "system": "missionControl"}}
          ],
          "profiles": [
            42,
            {"id": "com.example.app", "name": "Example"}
          ]
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: json)

        XCTAssertEqual(config.profiles.map(\.id), ["com.example.app"])
        XCTAssertEqual(config.profiles.first?.enabled, true)
        XCTAssertEqual(config.action(for: 3)?.system, .missionControl)
    }

    func testResetToDefaultsKeepsProfiles() {
        var config = chromeConfig()
        let before = config.profiles

        config.resetToDefaults()

        XCTAssertEqual(config.profiles, before)
        XCTAssertEqual(config.action(for: 3, frontmostBundleID: chrome)?.system, .appExpose)
        XCTAssertFalse(config.action(for: 3)?.isBound ?? true)
    }

    func testRemoveProfileDropsOnlyThatRule() {
        var config = chromeConfig()
        config.setProfile(AppProfile(id: "com.example.other", name: "Other"))

        config.removeProfile(id: chrome)

        XCTAssertEqual(config.profiles.map(\.id), ["com.example.other"])
        XCTAssertEqual(config.action(for: 3, frontmostBundleID: chrome)?.system, .back)
    }
}

@MainActor
final class ActiveAppMonitorTests: XCTestCase {
    func testStartAndStopAreIdempotent() {
        let monitor = ActiveAppMonitor()

        monitor.start()
        monitor.start()
        monitor.stop()
        monitor.stop()
    }
}


final class MouseBatteryTests: XCTestCase {
    private func device(
        _ name: String = "BT Mouse",
        transport: String = "Bluetooth Low Energy",
        percent: Int?,
        vendorID: Int = 0x32C2,
        productID: Int = 0x12
    ) -> HIDBatteryDevice {
        HIDBatteryDevice(
            name: name,
            vendorID: vendorID,
            productID: productID,
            transport: transport,
            batteryPercent: percent
        )
    }

    private func receiver(percent: Int? = nil) -> HIDBatteryDevice {
        device("2.4G Mouse", transport: "USB", percent: percent, vendorID: 0x1EA7, productID: 0x66)
    }

    func testBluetoothLevelIsReported() {
        let reading = MouseBattery.reading(from: [device(percent: 82)])

        XCTAssertEqual(reading.kind, .reported(82))
        XCTAssertEqual(reading.percent, 82)
        XCTAssertEqual(reading.source, .bluetooth)
        XCTAssertEqual(reading.deviceName, "BT Mouse")
        XCTAssertTrue(reading.isConnected)
        XCTAssertFalse(reading.isLow)
        XCTAssertEqual(reading.valueText, "82%")
    }

    func testReceiverWithNoLevelIsNotReported() {
        let reading = MouseBattery.reading(from: [receiver()])

        XCTAssertEqual(reading.kind, .notReported)
        XCTAssertEqual(reading.source, .receiver)
        XCTAssertNil(reading.percent)
        XCTAssertTrue(reading.isConnected)
        XCTAssertEqual(reading.valueText, "Not reported")
    }

    func testBluetoothWithoutALevelIsNotReported() {
        let reading = MouseBattery.reading(from: [device(percent: nil)])

        XCTAssertEqual(reading.kind, .notReported)
        XCTAssertEqual(reading.source, .bluetooth)
    }

    func testNoDevicesMeansUnreachable() {
        let reading = MouseBattery.reading(from: [])

        XCTAssertEqual(reading.kind, .unreachable)
        XCTAssertFalse(reading.isConnected)
        XCTAssertNil(reading.source)
        XCTAssertEqual(reading.valueText, "Not connected")
    }

    func testAReportedLevelWinsOverSilentNodes() {
        let reading = MouseBattery.reading(from: [
            receiver(),
            device(percent: 64)
        ])

        XCTAssertEqual(reading.kind, .reported(64))
        XCTAssertEqual(reading.source, .bluetooth)
    }

    func testAReportedReceiverLevelWinsToo() {
        // Not seen on the E510, but a future receiver revision could report one.
        let reading = MouseBattery.reading(from: [
            device(percent: nil),
            receiver(percent: 55)
        ])

        XCTAssertEqual(reading.kind, .reported(55))
        XCTAssertEqual(reading.source, .receiver)
    }

    func testTheReceiverWinsWhenNeitherConnectionReports() {
        // macOS keeps a remembered Bluetooth node registered while the mouse is
        // on 2.4 GHz; a plugged-in receiver is the stronger signal.
        let reading = MouseBattery.reading(from: [
            device("BT Mouse", percent: nil),
            receiver()
        ])

        XCTAssertEqual(reading.kind, .notReported)
        XCTAssertEqual(reading.source, .receiver)
    }

    func testUnrelatedDevicesAreIgnored() {
        let logitech = device(
            "MX MCHNCL M",
            transport: "Bluetooth Low Energy",
            percent: 90,
            vendorID: 0x046D,
            productID: 0xB037
        )

        XCTAssertEqual(MouseBattery.reading(from: [logitech]).kind, .unreachable)
    }

    func testPercentIsClamped() {
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: 140)]).percent, 100)
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: -5)]).percent, 0)
    }

    func testLowAndCriticalThresholds() {
        XCTAssertFalse(MouseBattery.reading(from: [device(percent: 21)]).isLow)
        XCTAssertTrue(MouseBattery.reading(from: [device(percent: 20)]).isLow)
        XCTAssertFalse(MouseBattery.reading(from: [device(percent: 20)]).isCritical)
        XCTAssertTrue(MouseBattery.reading(from: [device(percent: 10)]).isCritical)
    }

    func testSymbolsNeverLookLikeAnEmptyBatteryUnlessItIsEmpty() {
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: 100)]).symbolName, "battery.100percent")
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: 75)]).symbolName, "battery.75percent")
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: 50)]).symbolName, "battery.50percent")
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: 25)]).symbolName, "battery.25percent")
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: 10)]).symbolName, "battery.0percent")
        XCTAssertEqual(MouseBattery.reading(from: [device(percent: nil)]).symbolName, "bolt.horizontal.circle")
        XCTAssertEqual(MouseBattery.reading(from: []).symbolName, "computermouse")
        XCTAssertEqual(MouseBatteryReading.notYetRead.symbolName, "ellipsis.circle")
    }

    func testTheExplanationSaysWhyTheReceiverCannotShowALevel() {
        let reading = MouseBattery.reading(from: [receiver()])

        XCTAssertTrue(reading.explanation.contains("does not send a battery level"))
        XCTAssertTrue(reading.explanation.contains("Bluetooth"))
    }

    func testMenuBarSummaryNamesTheSource() {
        XCTAssertEqual(
            MouseBattery.reading(from: [device(percent: 82)]).summaryText,
            "Battery · 82% (Bluetooth)"
        )
        XCTAssertEqual(
            MouseBattery.reading(from: [receiver()]).summaryText,
            "Battery · not reported over 2.4 GHz"
        )
        XCTAssertEqual(
            MouseBattery.reading(from: []).summaryText,
            "Battery · mouse not connected"
        )
    }

    func testNotYetReadIsNeitherConnectedNorReported() {
        let reading = MouseBatteryReading.notYetRead

        XCTAssertEqual(reading.kind, .unknown)
        XCTAssertNil(reading.percent)
        XCTAssertFalse(reading.isConnected)
        XCTAssertEqual(reading.explanation, "The level is read from macOS when the app starts.")
    }

    // MARK: Merging the registry with the Bluetooth stack

    func testTheBluetoothStackFillsInTheRegistryNodesLevel() {
        // The registry node has the transport but no level; the stack has the
        // level but no transport. The merge is one device with both.
        let merged = MouseBattery.mergedDevices(
            registry: [device(percent: nil)],
            bluetooth: [device(transport: "Bluetooth", percent: 73)]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].transport, "Bluetooth Low Energy")
        XCTAssertEqual(merged[0].batteryPercent, 73)
        XCTAssertEqual(MouseBattery.reading(from: merged).kind, .reported(73))
        XCTAssertEqual(MouseBattery.reading(from: merged).source, .bluetooth)
    }

    func testABluetoothMouseMissingFromTheRegistryIsStillShown() {
        let merged = MouseBattery.mergedDevices(
            registry: [],
            bluetooth: [device(transport: "Bluetooth", percent: 41)]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(MouseBattery.reading(from: merged).kind, .reported(41))
        XCTAssertEqual(MouseBattery.reading(from: merged).source, .bluetooth)
    }

    func testTheMergeKeepsTheReceiverAndAddsTheBluetoothLevel() {
        let merged = MouseBattery.mergedDevices(
            registry: [receiver()],
            bluetooth: [device(transport: "Bluetooth", percent: 88)]
        )

        // The receiver's USB node and the Bluetooth mouse are different
        // transports, so both survive; the reported level wins.
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(MouseBattery.reading(from: merged).kind, .reported(88))
        XCTAssertEqual(MouseBattery.reading(from: merged).source, .bluetooth)
    }

    func testTheMergeDropsUnrelatedBluetoothDevices() {
        let logitech = device(
            "MX MCHNCL M",
            transport: "Bluetooth",
            percent: 90,
            vendorID: 0x046D,
            productID: 0xB367
        )

        XCTAssertTrue(MouseBattery.mergedDevices(registry: [], bluetooth: [logitech]).isEmpty)
    }
}

final class BluetoothBatteryTests: XCTestCase {
    private let sample = Data("""
    {
      "SPBluetoothDataType": [
        {
          "controller_properties": { "controller_vendorID": "0x004C (Apple)" },
          "device_connected": [
            { "BT Mouse": {
                "device_address": "FA:22:02:2A:EE:88",
                "device_batteryLevelMain": "100%",
                "device_vendorID": "0x32C2",
                "device_productID": "0x0012",
                "device_minorType": "Mouse"
            } },
            { "Eric’s Magic Keyboard": {
                "device_batteryLevelMain": "76%",
                "device_vendorID": "0x004C",
                "device_productID": "0x029A"
            } },
            { "wAPM": {
                "device_batteryLevelLeft": "81%",
                "device_batteryLevelRight": "80%",
                "device_vendorID": "0x004C",
                "device_productID": "0x200A"
            } }
          ],
          "device_not_connected": [
            { "Old Mouse": {
                "device_batteryLevelMain": "50%",
                "device_vendorID": "0x32C2",
                "device_productID": "0x0012"
            } }
          ]
        }
      ]
    }
    """.utf8)

    func testParsesTheConnectedDevicesThatCarryALevel() throws {
        let devices = BluetoothBattery.devices(fromJSON: sample)

        XCTAssertEqual(devices.count, 2)
        let mouse = try XCTUnwrap(devices.first { $0.name == "BT Mouse" })
        XCTAssertEqual(mouse.vendorID, 0x32C2)
        XCTAssertEqual(mouse.productID, 0x0012)
        XCTAssertEqual(mouse.batteryPercent, 100)
        XCTAssertEqual(mouse.transport, "Bluetooth")
        XCTAssertEqual(mouse.source, .bluetooth)
        XCTAssertTrue(mouse.isBluetooth)
    }

    func testADeviceWithoutAMainLevelIsSkipped() {
        // The AirPods report only Left/Right/Case, so there is no single number
        // the row could show.
        let devices = BluetoothBattery.devices(fromJSON: sample)

        XCTAssertFalse(devices.contains { $0.name == "wAPM" })
    }

    func testTheDisconnectedListIsIgnored() {
        let devices = BluetoothBattery.devices(fromJSON: sample)

        XCTAssertFalse(devices.contains { $0.name == "Old Mouse" })
    }

    func testHexIdentifiersAreParsed() {
        let devices = BluetoothBattery.devices(fromJSON: sample)

        XCTAssertEqual(devices.first { $0.name == "Eric’s Magic Keyboard" }?.productID, 0x029A)
        XCTAssertEqual(devices.first { $0.name == "Eric’s Magic Keyboard" }?.vendorID, 0x004C)
    }

    func testMalformedJSONYieldsNothing() {
        XCTAssertTrue(BluetoothBattery.devices(fromJSON: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(BluetoothBattery.devices(fromJSON: Data()).isEmpty)
    }

    func testAnEmptyConnectedListYieldsNothing() {
        let json = Data(#"{"SPBluetoothDataType":[{"device_connected":[]}]}"#.utf8)

        XCTAssertTrue(BluetoothBattery.devices(fromJSON: json).isEmpty)
    }
}

@MainActor
final class MouseBatteryMonitorTests: XCTestCase {
    func testStartReadsOnceAndIsIdempotent() {
        let monitor = MouseBatteryMonitor()

        monitor.start()
        monitor.start()

        // Whatever this machine is connected to, the monitor must have looked.
        // `updated` is set on every read, including the not-connected answer.
        XCTAssertNotNil(monitor.reading.updated)
        XCTAssertNotEqual(monitor.reading.kind, .unknown)

        monitor.stop()
        monitor.stop()
    }

    func testRefreshUpdatesTheReading() {
        let monitor = MouseBatteryMonitor()

        monitor.refresh()

        XCTAssertNotNil(monitor.reading.updated)
    }
}

final class VendorReportAssemblerTests: XCTestCase {
    func testSevenValuesMakeOneReport() {
        var assembler = VendorReportAssembler()

        for value in 1...6 {
            XCTAssertNil(assembler.append(value), "a partial report must not be published")
        }

        XCTAssertEqual(assembler.append(7), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(assembler.bytes, [])
    }

    func testValuesAreMaskedToOneByte() {
        var assembler = VendorReportAssembler()
        var report: [UInt8]?

        for value in 0x101...0x107 {
            report = assembler.append(value)
        }

        XCTAssertEqual(report, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(assembler.bytes, [])
    }

    func testAnEighthValueStartsTheNextReport() {
        var assembler = VendorReportAssembler()
        var reports: [[UInt8]] = []

        for value in 1...8 {
            if let payload = assembler.append(value) {
                reports.append(payload)
            }
        }

        XCTAssertEqual(reports, [[1, 2, 3, 4, 5, 6, 7]])
        XCTAssertEqual(assembler.bytes, [8])
    }

    func testResetDropsAPartialReport() {
        var assembler = VendorReportAssembler()

        _ = assembler.append(1)
        _ = assembler.append(2)
        assembler.reset()

        XCTAssertEqual(assembler.bytes, [])
        XCTAssertNil(assembler.append(3))
    }

    func testTheHexDumpStartsWithTheReportID() {
        let entry = VendorReportEntry(device: "2.4G Mouse", payload: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])

        XCTAssertEqual(entry.reportHex, "B5 01 02 03 04 05 06 07")
    }
}
