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

// MARK: - Per-binding application-scope tests (whitelist / blacklist)
final class ButtonBindingScopeTests: XCTestCase {

    // MARK: - Pure-function logic (computeAllowsApp)

    func testWhitelist_BundlePathInList_returnsTrue() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: true,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Safari.app",
            executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        XCTAssertTrue(r)
    }

    func testWhitelist_ExecutablePathInList_returnsTrue() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: true,
            applications: ["/Applications/Safari.app/Contents/MacOS/Safari"],
            bundlePath: "/Applications/Safari.app",
            executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        XCTAssertTrue(r)
    }

    func testWhitelist_AppNotInList_returnsFalse() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: true,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Other.app",
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testWhitelist_NilPaths_returnsFalse() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: true,
            applications: ["/anything.app"],
            bundlePath: nil,
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testWhitelist_EmptyList_returnsFalse() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: true,
            applications: [],
            bundlePath: "/Applications/Safari.app",
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testBlacklist_AppInList_returnsFalse() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: false,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Safari.app",
            executablePath: nil
        )
        XCTAssertFalse(r)
    }

    func testBlacklist_AppNotInList_returnsTrue() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: false,
            applications: ["/Applications/Safari.app"],
            bundlePath: "/Applications/Other.app",
            executablePath: nil
        )
        XCTAssertTrue(r)
    }

    func testBlacklist_NilPaths_returnsTrue() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: false,
            applications: ["/anything.app"],
            bundlePath: nil,
            executablePath: nil
        )
        XCTAssertTrue(r)
    }

    func testBlacklist_EmptyList_returnsTrue() {
        let r = ButtonBinding.computeAllowsApp(
            allowlist: false,
            applications: [],
            bundlePath: "/Applications/Safari.app",
            executablePath: nil
        )
        XCTAssertTrue(r)
    }

    // MARK: - Initializer defaults (new bindings default to blacklist + empty = applies everywhere)

    func testNewBinding_DefaultsToBlacklistEmpty_appliesEverywhere() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy")
        XCTAssertFalse(binding.allowlist, "New bindings should default to blacklist mode")
        XCTAssertEqual(binding.applications, [], "New bindings should default to empty applications list")
        // Sanity: with these defaults, every app should be allowed
        XCTAssertTrue(ButtonBinding.computeAllowsApp(
            allowlist: binding.allowlist,
            applications: binding.applications,
            bundlePath: "/some/random.app",
            executablePath: nil
        ))
    }

    // MARK: - Codable backward-compat: legacy JSON without scope fields decodes to whitelist + empty

    func testCodable_OldJSONWithoutScope_decodesToWhitelistEmpty() throws {
        // 旧版 binding JSON: 只有 id/triggerEvent/systemShortcutName/isEnabled/createdAt 字段
        let oldJSON = #"""
        {
          "id": "01234567-89AB-CDEF-0123-456789ABCDEF",
          "triggerEvent": {
            "type": "mouse",
            "code": 3,
            "modifiers": 0,
            "displayComponents": ["🖱4"]
          },
          "systemShortcutName": "copy",
          "isEnabled": true,
          "createdAt": 750000000.0
        }
        """#
        let data = oldJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        let binding = try decoder.decode(ButtonBinding.self, from: data)
        XCTAssertTrue(binding.allowlist, "Decoded old JSON should default to whitelist mode (forces manual scope config)")
        XCTAssertEqual(binding.applications, [])
        // Sanity: whitelist + empty = doesn't fire in any app
        XCTAssertFalse(binding.allowsApp(nil))
    }

    func testCodable_NewJSONWithScope_roundTrips() throws {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        var binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy", allowlist: true,
                                    applications: ["/Applications/Safari.app", "/Applications/Notes.app"])
        binding.isEnabled = true
        let encoder = JSONEncoder()
        let data = try encoder.encode(binding)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.allowlist, true)
        XCTAssertEqual(decoded.applications, ["/Applications/Safari.app", "/Applications/Notes.app"])
    }
}
