import XCTest
import AppKit
@testable import PicaMD

final class KeybindingMapTests: XCTestCase {

    // MARK: - KeyCombo.parse

    func testParseSimpleCombo() {
        XCTAssertEqual(KeyCombo.parse("cmd+1"),
                        KeyCombo(key: "1", modifiers: .command))
    }

    func testParseMultiModifier() {
        XCTAssertEqual(KeyCombo.parse("cmd+shift+d"),
                        KeyCombo(key: "d", modifiers: [.command, .shift]))
    }

    func testParseAcceptsAliases() {
        XCTAssertEqual(KeyCombo.parse("command+option+up"),
                        KeyCombo.parse("cmd+opt+up"))
        XCTAssertEqual(KeyCombo.parse("ctrl+shift+escape"),
                        KeyCombo.parse("control+shift+escape"))
    }

    func testParseRejectsUnknownToken() {
        XCTAssertNil(KeyCombo.parse("hyper+x"))
        XCTAssertNil(KeyCombo.parse(""))
        XCTAssertNil(KeyCombo.parse("cmd"))   // no key part
    }

    // MARK: - KeyCombo.matches

    func testComboMatchesEvent() {
        // ⌘1
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil,
            characters: "1", charactersIgnoringModifiers: "1",
            isARepeat: false, keyCode: 0x12
        )!
        XCTAssertTrue(KeyCombo(key: "1", modifiers: .command).matches(event))
    }

    func testComboRequiresExactModifierMatch() {
        // ⌘⇧1 should NOT trigger a binding for ⌘1 — exact modifier match.
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: 0, context: nil,
            characters: "!", charactersIgnoringModifiers: "1",
            isARepeat: false, keyCode: 0x12
        )!
        XCTAssertFalse(KeyCombo(key: "1", modifiers: .command).matches(event))
    }

    func testNamedKeyMatchesArrow() {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [.command, .option], timestamp: 0,
            windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 0x7E   // up arrow
        )!
        let combo = KeyCombo(key: "up", modifiers: [.command, .option])
        XCTAssertTrue(combo.matches(event))
    }

    // MARK: - KeybindingMap

    func testDefaultMapResolvesH1() {
        let event = makeEvent(modifiers: .command, characters: "1", keyCode: 0x12)
        XCTAssertEqual(KeybindingMap.default.action(for: event), .headingH1)
    }

    func testDefaultMapResolvesMoveLineUp() {
        let event = makeEvent(modifiers: [.command, .option], keyCode: 0x7E)
        XCTAssertEqual(KeybindingMap.default.action(for: event), .moveLineUp)
    }

    func testMergingOverridesDefault() {
        let userJSON = ["headingH1": "cmd+ctrl+1"]
        let merged = KeybindingMap.merging(userJSON: userJSON)
        // Old default (cmd+1) no longer fires:
        let cmdOnly = makeEvent(modifiers: .command, characters: "1", keyCode: 0x12)
        XCTAssertNotEqual(merged.action(for: cmdOnly), .headingH1)
        // New combo (cmd+ctrl+1) does fire:
        let ctrlPlus = makeEvent(modifiers: [.command, .control], characters: "1", keyCode: 0x12)
        XCTAssertEqual(merged.action(for: ctrlPlus), .headingH1)
    }

    func testMergingIgnoresMalformedEntries() {
        let userJSON: [String: String] = [
            "duplicateLine": "lol+x",      // bogus modifier
            "notAnAction": "cmd+z"         // unknown action
        ]
        let merged = KeybindingMap.merging(userJSON: userJSON)
        // Default for duplicateLine still active (⌘⇧D).
        let dup = makeEvent(modifiers: [.command, .shift], characters: "d", keyCode: 0x02)
        XCTAssertEqual(merged.action(for: dup), .duplicateLine)
    }

    // MARK: - Helpers

    private func makeEvent(modifiers: NSEvent.ModifierFlags,
                            characters: String = "",
                            keyCode: UInt16) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }
}
