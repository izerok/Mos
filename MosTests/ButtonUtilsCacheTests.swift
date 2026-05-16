import XCTest
@testable import Mos_Debug

final class ButtonUtilsCacheTests: XCTestCase {

    func testInvalidateCache_causesFreshLoad() {
        ButtonUtils.shared.invalidateCache()
        let bindings = ButtonUtils.shared.getButtonBindings()
        XCTAssertNotNil(bindings)
    }

    func testGetButtonBindings_preparesCustomCache() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let loaded = ButtonUtils.shared.getButtonBindings()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].cachedCustomCode, 56)
        XCTAssertEqual(loaded[0].cachedCustomModifiers, 0)

        // Cleanup
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
    }
}

// MARK: - Application-scope tests (whitelist / blacklist + hold-sequence cache)
final class ButtonUtilsScopeTests: XCTestCase {

    // computeShouldDispatch (pure function, no Options.shared dependency)

    func testWhitelist_AppInList_byBundlePath_returnsTrue() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: true,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Safari.app",
            executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        XCTAssertTrue(r)
    }

    func testWhitelist_AppInList_byExecutablePath_returnsTrue() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: true,
            applications: ["/Applications/Safari.app/Contents/MacOS/Safari"],
            bundlePath: "/Applications/Safari.app",
            executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        XCTAssertTrue(r)
    }

    func testWhitelist_AppNotInList_returnsFalse() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: true,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Other.app",
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testWhitelist_NilPaths_returnsFalse() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: true,
            applications: ["/anything.app"],
            bundlePath: nil,
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testWhitelist_EmptyList_returnsFalse() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: true,
            applications: [],
            bundlePath: "/Applications/Safari.app",
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testBlacklist_AppInList_returnsFalse() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: false,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Safari.app",
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testBlacklist_AppNotInList_returnsTrue() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: false,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Other.app",
            executablePath: nil
        )
        XCTAssertTrue(r)
    }

    func testBlacklist_NilPaths_returnsTrue() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: false,
            applications: ["/anything.app"],
            bundlePath: nil,
            executablePath: nil
        )
        XCTAssertTrue(r)
    }

    func testBlacklist_EmptyList_returnsTrue() {
        let r = ButtonUtils.computeShouldDispatch(
            allowlist: false,
            applications: [],
            bundlePath: "/Applications/Safari.app",
            executablePath: nil
        )
        XCTAssertTrue(r)
    }

    // Hold-sequence cache: Down records, Up consumes

    func testDispatchDecisionCache_RecordThenConsume() {
        ButtonUtils.shared.clearDispatchDecisions()
        ButtonUtils.shared.recordDispatchDecision(type: .mouse, code: 3, allowed: true)
        XCTAssertEqual(ButtonUtils.shared.consumeDispatchDecision(type: .mouse, code: 3), true)
        // Second consume returns nil (entry already removed)
        XCTAssertNil(ButtonUtils.shared.consumeDispatchDecision(type: .mouse, code: 3))
    }

    func testDispatchDecisionCache_BlockedRecorded() {
        ButtonUtils.shared.clearDispatchDecisions()
        ButtonUtils.shared.recordDispatchDecision(type: .mouse, code: 4, allowed: false)
        XCTAssertEqual(ButtonUtils.shared.consumeDispatchDecision(type: .mouse, code: 4), false)
    }

    func testDispatchDecisionCache_DifferentKeysIndependent() {
        ButtonUtils.shared.clearDispatchDecisions()
        ButtonUtils.shared.recordDispatchDecision(type: .mouse, code: 3, allowed: true)
        ButtonUtils.shared.recordDispatchDecision(type: .keyboard, code: 3, allowed: false)
        XCTAssertEqual(ButtonUtils.shared.consumeDispatchDecision(type: .mouse, code: 3), true)
        XCTAssertEqual(ButtonUtils.shared.consumeDispatchDecision(type: .keyboard, code: 3), false)
    }

    func testDispatchDecisionCache_ClearRemovesAll() {
        ButtonUtils.shared.recordDispatchDecision(type: .mouse, code: 3, allowed: true)
        ButtonUtils.shared.recordDispatchDecision(type: .keyboard, code: 5, allowed: false)
        ButtonUtils.shared.clearDispatchDecisions()
        XCTAssertNil(ButtonUtils.shared.consumeDispatchDecision(type: .mouse, code: 3))
        XCTAssertNil(ButtonUtils.shared.consumeDispatchDecision(type: .keyboard, code: 5))
    }
}
