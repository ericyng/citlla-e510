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
