# Mos (izerok fork)

Fork of [Caldis/Mos](https://github.com/Caldis/Mos) — the macOS scroll-smoothing menu-bar utility — with one extra feature.

## What's added in this fork

**Per-binding application scope for mouse-button bindings.** Each `ButtonBinding` can be limited to (or excluded from) a specific list of apps. Old global `binding.fire-everywhere` behavior is replaced with per-binding whitelist/blacklist.

UI lives in **Preferences → Buttons** as a new "Scope" column on the right of each row. The button label is `✓ Apps (N)` (whitelist) or `✗ Apps (N)` (blacklist). Click to open a popover with the mode toggle and the app list.

Defaults:
- A binding **newly created** in the UI: `blacklist + []` → fires in all apps (just works).
- A binding **decoded from upstream's pre-scope JSON**: `whitelist + []` → does **not** fire until the user picks at least one app (forces explicit reconfiguration after upgrade).

The scope check runs at binding-match time in `InputProcessor.process(_:)`, with the same predicate threaded through `LogiIntegrationBridge` and the mosScroll-defer probe in `ScrollCore` so that HID-side and scroll-side handlers respect the same scope.

## Files touched

```
Mos/
  Windows/PreferencesWindow/ButtonsView/
    RecordedEvent.swift                            # ButtonBinding gains allowlist/applications + allowsApp(_:)
    PreferencesButtonsViewController.swift         # Scope table column + scope-preserving binding updates
    ButtonScopePopoverViewController.swift  (new)  # popover that edits one binding's scope, callback-driven
  InputEvent/InputProcessor.swift                  # scope predicate at binding match + resolveTargetApp(_:)
  Integration/LogiIntegrationBridge.swift          # scope filter on logi-prefixed binding probe
  ScrollCore/ScrollCore.swift                      # scope filter on mosScroll-defer probe
MosTests/ButtonUtilsCacheTests.swift               # ButtonBindingScopeTests (11 cases + JSON round-trip)
docs/superpowers/specs/2026-05-17-button-per-app-scope-design.md
.github/workflows/build.yml                        # macOS Xcode build + tests + .app artifact
CHANGELOG.md                                       # upgrade-behavior note
```

## Building

Local Xcode build (matches upstream):

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test
```

CI build via the workflow at `.github/workflows/build.yml` — every push to `master` produces a downloadable `Mos-Debug-app` artifact on a `macos-latest` runner (code signing disabled). Run via `gh run watch` or the GitHub UI.

## Upstream

Everything outside the files listed above tracks `Caldis/Mos` upstream. See the original repo for app-level docs, donation links, contributor list, etc. The `upstream` remote in a fresh clone points at `https://github.com/Caldis/Mos.git`.
