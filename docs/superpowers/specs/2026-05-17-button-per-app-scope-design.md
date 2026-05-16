# Per-App Whitelist/Blacklist for Mouse Button Bindings

**Status:** Design approved (pending spec review)
**Date:** 2026-05-17
**Targets repo:** [izerok/Mos](https://github.com/izerok/Mos) (fork of [Caldis/Mos](https://github.com/Caldis/Mos))
**Branch base:** `master`

## Goal

Let users restrict mouse-button bindings (the actions defined on the Buttons preferences page) to a chosen set of frontmost apps, with a single-list + mode-toggle model identical to the existing scroll-smoothing exception list.

## Out of scope

- New action types (we keep the existing `SystemShortcut` actions verbatim)
- Per-app *per-button* mappings (button bindings remain global; the list only gates whether bindings fire)
- Sharing data with the scroll exception list (kept independent per user request)
- Migration of existing users' settings (intentionally no migration — see "Upgrade behavior")

## Behavior

### Storage (new `UserDefaults` keys, in `Options.swift`)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `OptionItem.Button.Allowlist` | `Bool` | `true` | `true` = whitelist mode (bindings only fire in listed apps); `false` = blacklist mode (bindings fire everywhere except listed apps) |
| `OptionItem.Button.Applications` | `String` (JSON-encoded `[String]`) | `"[]"` | List of app identifiers (bundle path or executable path, same scheme as scroll) |

Accessed via new properties:

```swift
extension Options {
    struct Buttons {
        var allowlist: Bool
        var applications: [String]
    }
}
```

### Runtime decision

New file `Mos/ButtonCore/ButtonUtils.swift` (replacing the existing stub at lines 98–100):

```swift
static func shouldDispatch(for app: NSRunningApplication?) -> Bool {
    let id = app.flatMap { ScrollUtils.shared.getTargetApplication(from: $0) }
    let inList = id.map { Options.shared.buttons.applications.contains($0) } ?? false
    return Options.shared.buttons.allowlist ? inList : !inList
}
```

Semantics:
- Unknown frontmost app (`nil`) is treated as "not in list" (strict mode per user choice)
- Whitelist mode + empty list ⇒ bindings disabled globally (intentional default)
- Blacklist mode + empty list ⇒ bindings enabled globally (matches old behavior)

### Plug-in point

In `ButtonCore.swift` `dispatchInterceptor` callback, before the existing `InputProcessor.shared.process(event)` call:

```swift
let frontmost = NSWorkspace.shared.frontmostApplication
guard ButtonUtils.shouldDispatch(for: frontmost) else {
    return Unmanaged.passUnretained(event)   // forward unmodified
}
// ... existing dispatch logic
```

To handle hold sequences correctly (button-down in app A, switch to app B, button-up):

- At `*MouseDown`, record the dispatch decision (allowed/not) keyed by `(buttonNumber, frontmostBundleID)`
- At the paired `*MouseUp`, look up the recorded decision; if "not allowed" was recorded at down-time, also drop the up event
- Cleared automatically on any subsequent unmatched `*MouseDown` of the same button

Modifier-only events and key events do not pass through the button-dispatch path and are not affected.

## UI

Append a new section to the existing `PreferencesButtonsViewController` view, below the current bindings table. Implemented **programmatically** (no xib).

```
┌── Buttons preferences ──────────────────────────────┐
│ [Existing bindings table — unchanged]               │
│ ┌─────────────────────────────────────────────────┐│
│ │ Button4 → navigateBack    ✓ on                  ││
│ │ Button5 → navigateForward ✓ on                  ││
│ └─────────────────────────────────────────────────┘│
│  [ + Binding ] [ − ]                                │
│                                                       │
│ ────────────────────────────────────────────────── │ ← visual separator
│                                                       │
│ Application scope                                    │
│ Mode: [ Whitelist ▌ Blacklist ]    ← NSSegmentedControl
│ ┌─────────────────────────────────────────────────┐│
│ │ 🌐 Safari.app                                   ││
│ │ 🟢 Google Chrome.app                            ││
│ │ 💻 Code.app                                     ││
│ └─────────────────────────────────────────────────┘│
│  [ + App ] [ − ]                                    │
│ (when whitelist + empty list:)                       │
│   "No apps added — button bindings will not fire"    │
└─────────────────────────────────────────────────────┘
```

Components:

- `NSSegmentedControl` for the mode toggle (whitelist / blacklist)
- `NSTableView` for the app list (single column showing icon + display name)
- Bottom toolbar: `+` opens `NSOpenPanel` filtered to `.app` bundles, default dir `/Applications`; `−` removes the selected row
- Below the table, a contextual hint label that is hidden unless `allowlist=true && applications.isEmpty`
- Row rendering reuses `Application.swift` helpers for icon/name lookup (no new helpers needed)
- Controls write directly to `Options.shared.buttons.{allowlist,applications}` on change (mirroring how the existing scroll-exception UI persists)

## Localization

`NSLocalizedString(_:comment:)` only (min deployment 10.13, per `AGENTS.md`). Add to every existing `Localizable.strings` (en, zh-Hans, zh-Hant, ja, ko, ru, de, id):

```
"BUTTONS_SCOPE_TITLE"       = "Application scope";
"BUTTONS_SCOPE_MODE_WHITE"  = "Whitelist";
"BUTTONS_SCOPE_MODE_BLACK"  = "Blacklist";
"BUTTONS_SCOPE_EMPTY_HINT"  = "No apps added — button bindings will not fire";
```

Chinese values:

```
"BUTTONS_SCOPE_TITLE"       = "作用 App";
"BUTTONS_SCOPE_MODE_WHITE"  = "白名单";
"BUTTONS_SCOPE_MODE_BLACK"  = "黑名单";
"BUTTONS_SCOPE_EMPTY_HINT"  = "未添加任何 App，按键映射当前不会生效";
```

Other languages: pending translator pass during implementation; English fallback is acceptable for v1.

## Testing

Per `AGENTS.md` quality gates: Swift logic changes require relevant `MosTests` runs.

New file `MosTests/ButtonUtilsTests.swift`:

| Test name | Scenario | Expected |
|---|---|---|
| `testShouldDispatch_Whitelist_AppInList` | `allowlist=true`, list contains `app.path` | `true` |
| `testShouldDispatch_Whitelist_AppNotInList` | `allowlist=true`, list omits `app.path` | `false` |
| `testShouldDispatch_Whitelist_NilApp` | `allowlist=true`, frontmost = nil | `false` |
| `testShouldDispatch_Whitelist_EmptyList` | `allowlist=true`, list empty | `false` |
| `testShouldDispatch_Blacklist_AppInList` | `allowlist=false`, list contains `app.path` | `false` |
| `testShouldDispatch_Blacklist_AppNotInList` | `allowlist=false`, list omits `app.path` | `true` |
| `testShouldDispatch_Blacklist_NilApp` | `allowlist=false`, frontmost = nil | `true` |
| `testShouldDispatch_Blacklist_EmptyList` | `allowlist=false`, list empty | `true` |
| `testHoldSequence_DecisionCachedAtDown` | Down in app A (allowed), switch to app B (blocked), up; up event must drop | down=pass, up=dropped |

Tests cover `ButtonUtils.shouldDispatch(for:)` by passing pre-canned `(allowlistFlag, applicationsList, frontmostPath)` triples directly. To make this possible the function is refactored to take its inputs (`allowlist`, `applications`, `frontmostPath`) as parameters in addition to the convenience overload that reads them from `Options.shared`. The hold-sequence cache is exposed via an injectable seam so tests can drive synthetic down/up sequences without a real CGEvent tap.

Run before claiming done:

```bash
xcodebuild -scheme Debug -destination 'platform=macOS' test \
  -only-testing:MosTests/ButtonUtilsTests
```

Also run the full Debug build to confirm no breakage:

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
```

## Upgrade behavior

**No migration.** Existing users who upgrade to this version will find their global button bindings stop firing until they add at least one app to the whitelist (or switch to blacklist mode).

This must be called out in release notes / `CHANGELOG.md`:

> Button bindings are now scoped to a per-app list. After upgrading, button bindings will not fire until you add target apps in **Preferences → Buttons → Application scope** (or switch the mode to Blacklist for the previous global behavior).

## Affected files

| File | Δ lines | Note |
|---|---|---|
| `Mos/Options/Options.swift` | +20 | Two new `OptionItem` keys + `Options.Buttons.{allowlist,applications}` |
| `Mos/ButtonCore/ButtonUtils.swift` | +35 | Replace nil-returning stub; add `shouldDispatch(for:)` + hold-sequence cache |
| `Mos/ButtonCore/ButtonCore.swift` | +15 | Pre-dispatch guard in `dispatchInterceptor` |
| `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift` | +160 | New `ButtonsScopeView` programmatic NSView added to existing layout |
| `Mos/Resources/{en,zh-Hans,zh-Hant,ja,ko,ru,de,id}.lproj/Localizable.strings` | +4 keys × 8 | Localization |
| `MosTests/ButtonUtilsTests.swift` | +120 (new) | Unit tests |
| `CHANGELOG.md` | +6 | Upgrade-behavior note |

Estimated total: ~420 lines Swift + 32 strings.

## Open questions

None at design time. (All clarifying points resolved during brainstorming.)

## Approvals

- Design discussed and approved interactively on 2026-05-17.
- User decisions captured:
  - Scope: side-button → action mapping with per-app gating
  - List model: one list + mode toggle (separate from scroll list)
  - Action set: reuse the existing `SystemShortcut` action catalog as-is
  - Default: whitelist mode + empty list (opt-in)
  - Unknown frontmost app: strict per-list (treated as "not in list")
  - Upgrade migration: none
  - UI: pure code (no xib)
