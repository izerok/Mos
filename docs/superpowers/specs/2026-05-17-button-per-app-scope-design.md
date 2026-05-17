# Per-Binding Application Scope for Mouse-Button Bindings

**Status:** Implemented
**Date:** 2026-05-17 (revised from an earlier global-scope design)
**Repo:** [izerok/Mos](https://github.com/izerok/Mos) (fork of [Caldis/Mos](https://github.com/Caldis/Mos))
**Branch base:** `master`

## Goal

Let each individual `ButtonBinding` declare the set of apps it applies to (or is excluded from), instead of routing every binding through one shared global scope. Per-binding scope means a user can have "Button 4 → Back" active only in browsers while "Button 5 → Mission Control" stays global.

## Design history

An earlier iteration of this spec stored scope globally on `Options.shared.buttons.{allowlist,applications}` and gated dispatch inside the `ButtonCore` event tap. That design was implemented (commits `e252fae` / `26a4530`) and then fully reverted in commit `06666c8` after the user clarified that scope must be a property of each binding, not of all bindings together. This document describes the per-binding design that shipped.

## Data model

`ButtonBinding` (struct, declared in `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift`) gains two stored fields:

| Field | Type | Meaning |
|---|---|---|
| `allowlist` | `Bool` | `true` = whitelist mode (binding fires only in listed apps); `false` = blacklist mode (binding fires everywhere except listed apps). |
| `applications` | `[String]` | List of app identifiers. Each entry is a bundle path **or** an executable path of an `NSRunningApplication`. |

Both fields are encoded via the existing `ButtonBinding` Codable conformance. `CodingKeys` includes them; the custom `init(from:)` uses `decodeIfPresent` so legacy JSON without these fields decodes successfully.

### Default split

| Path | Default | Rationale |
|---|---|---|
| New binding (any convenience `init(...)`) | `allowlist=false`, `applications=[]` | Equivalent to "all apps, no exceptions" — a freshly recorded binding works immediately without configuration. |
| Decoded legacy binding (`init(from:)` with missing fields) | `allowlist=true`, `applications=[]` | Forces post-upgrade users to explicitly opt apps in. Prevents silent global firing of bindings whose intent the user can't recall after upgrade. |

`Equatable` includes the two new fields. `replacingAction(from donor:)` and every `updateButtonBinding(id:...)` builder in `PreferencesButtonsViewController` preserves the existing binding's `allowlist`/`applications` rather than rebuilding from defaults — otherwise editing a binding's action would silently wipe its scope.

## Decision logic

```swift
extension ButtonBinding {
    func allowsApp(_ app: NSRunningApplication?) -> Bool {
        let bundlePath = app?.bundleURL?.path
        let execPath = app?.executableURL?.path
        let inList = applications.contains { $0 == bundlePath || $0 == execPath }
        return allowlist ? inList : !inList
    }
}
```

Semantics (strict mode):
- Unknown target app (`nil`) acts as "not in list" — whitelist blocks, blacklist allows.
- Whitelist + empty list ⇒ never fires.
- Blacklist + empty list ⇒ always fires.

A pure-function variant `ButtonBinding.computeAllowsApp(allowlist:applications:bundlePath:executablePath:)` exists for unit testing without `NSRunningApplication`.

## Integration points

The scope check is applied at **every site that selects a binding for execution**:

| Site | File | Predicate composition |
|---|---|---|
| Main mouse / keyboard event dispatch | `Mos/InputEvent/InputProcessor.swift:106` | `{ $0.allowsApp(targetApp) }` |
| Logi HID++ binding probe | `Mos/Integration/LogiIntegrationBridge.swift:33` | `{ $0.systemShortcutName.hasPrefix("logi") && $0.allowsApp(targetApp) }` |
| `mosScroll`-defer probe in scroll path | `Mos/ScrollCore/ScrollCore.swift:383` | `{ ShortcutExecutor.isMosScrollActionIdentifier($0.systemShortcutName) && $0.allowsApp(targetApp) }` |

All three resolve `targetApp` through `InputProcessor.resolveTargetApp(for:)`, which prefers the CGEvent's target PID (via `ScrollUtils.shared.getRunningApplication(from:)`) and falls back to `NSWorkspace.shared.frontmostApplication` for HID++ events.

Up events do **not** re-check scope. `InputProcessor.activeBindings` is keyed by `(type, code)` and stores the action selected at Down; the paired Up release retrieves the action by key and emits the `.up` phase regardless of the current frontmost app. This avoids zombie active bindings when the user switches focus mid-hold.

## UI

`Preferences → Buttons` gains a programmatic **Scope** column (`NSTableColumn`) inserted on the right of the existing storyboard-defined `Hotkey` column. The new column is fixed-width 100pt; the existing column auto-resizes to fill the rest.

Each row in the new column renders a small rounded button:

| Mode | Label |
|---|---|
| Whitelist | `✓ Apps (N)` |
| Blacklist | `✗ Apps (N)` |

`N` is the count of entries in the binding's `applications`.

Clicking the button presents `ButtonScopePopoverViewController` anchored to that row. The popover shows:
- A title summarizing the binding (`Scope for {trigger} → {action}`).
- A two-segment `NSSegmentedControl` for Whitelist / Blacklist.
- An `NSTableView` listing the apps with their icons + display names.
- `+` opens an `NSOpenPanel` filtered to `/Applications`; `−` removes the selected row.
- A centered hint label that appears only in the awkward "whitelist + empty list" state (binding fires nowhere) so the user understands why nothing is happening.

The popover **does not** write to `Options.shared.buttons.binding` directly. Every mutation flows back through an `onChange: (ButtonBinding) -> Void` callback that the parent view controller wires to `replaceButtonBinding(_:)`. This avoids the popover's writes being clobbered the next time the view controller syncs its in-memory `buttonBindings` snapshot back to `Options`.

## Test coverage

`MosTests/ButtonUtilsCacheTests.swift` adds class `ButtonBindingScopeTests`:

- Whitelist × blacklist × in-list / not-in-list / empty / nil-paths (8 cases via `computeAllowsApp`).
- New-binding initializer default: `allowlist=false`, `applications=[]`.
- Codable round-trip: encode → decode preserves scope fields exactly.
- Codable backward compat: decoding a JSON object without `allowlist`/`applications` keys yields `allowlist=true`, `applications=[]`.

CI runs `xcodebuild ... test` on macOS via `.github/workflows/build.yml`.

## Upgrade behavior

No data migration. Legacy bindings decoded without scope keys land on the safe default (whitelist + empty), surfacing the new control to the user via the now-empty `✓ Apps (0)` button. Switching the mode to `Blacklist` restores the upstream's pre-fork "fires everywhere" behavior in one click.

`CHANGELOG.md` carries the upgrade-behavior note.

## Approvals

- Original brainstorming and design approval: 2026-05-17 (global-scope iteration, later rejected).
- Per-binding redesign approval: 2026-05-17 (same day, after upstream review of the global iteration).
- Code review (Critical/Important issues from review pass folded back into this spec): 2026-05-17.
