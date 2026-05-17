# Mos (izerok fork)

Fork of [Caldis/Mos](https://github.com/Caldis/Mos) — the macOS scroll-smoothing menu-bar utility — with one feature added on top.

[中文](#中文) · [English](#english)

---

## 中文

### 新增功能：按 binding 单独配置生效 App（白名单 / 黑名单）

上游 Mos 的按键 binding 是全局生效的：一个鼠标侧键绑了 "后退"，所有 App 里都是 "后退"。这个 fork 让 **每个 binding 独立** 配置自己的"作用 App 名单"。

**怎么用**

1. 偏好设置 → 按键 (Buttons)
2. 选中你要改的那条 binding（点一下那一行）
3. **右下角**会出现 `App 作用域: ✗ 0`（默认值, 黑名单 + 空 = 在所有 App 里生效）
4. 点该按钮 → popover 弹出：
   - 顶部 `Whitelist | Blacklist` 切换
   - 中间表格：当前作用域里的 App 列表（带图标 + 名字）
   - 底部 `+` 从 `/Applications` 选 app；`−` 删选中项

按钮标题会**实时反映**该 binding 的状态：
- `App 作用域: ✓ 3` = 白名单 + 3 个 App（只在这 3 个里生效）
- `App 作用域: ✗ 2` = 黑名单 + 2 个 App（除了这 2 个其他都生效）
- `App 作用域: ✓ 0` = 白名单 + 空 = **不会触发**（一般是从上游升级来的旧 binding 的默认状态，用户必须显式加 App）

**默认值**

| 来源 | 默认 scope |
|---|---|
| 在 UI 里新录的 binding | 黑名单 + 空 = 所有 App 都生效（即装即用） |
| 从上游 JSON 解码出来的旧 binding | 白名单 + 空 = 不生效（强制用户上来确认作用域） |

**作用范围**

scope 判定在 binding 选中时执行（不是事件分发时）：
- `InputProcessor.process(_:)` 在 Down 分支按 `binding.allowsApp(targetApp)` 过滤候选 binding
- `LogiIntegrationBridge` 探测 `logi*` binding 时也走同一个 predicate
- `ScrollCore` 的 `mosScroll` defer 探测也走同一个 predicate

所以鼠标按键、Logitech HID++ 设备按键、`mosScroll` 滚动延迟判断 — 三处都遵守每个 binding 的 scope 配置。

### 改动文件清单

```
Mos/
  Windows/PreferencesWindow/ButtonsView/
    RecordedEvent.swift                            # ButtonBinding 加 allowlist + applications + allowsApp(_:)
    PreferencesButtonsViewController.swift         # 底部工具栏 App 作用域按钮 + scope 保留的 binding 更新
    ButtonScopePopoverViewController.swift  (新)   # popover, callback 回写, 不直接动 Options
  InputEvent/InputProcessor.swift                  # binding 匹配时 scope 过滤 + resolveTargetApp(_:)
  Integration/LogiIntegrationBridge.swift          # logi 探测加 scope predicate
  ScrollCore/ScrollCore.swift                      # mosScroll-defer 探测加 scope predicate
MosTests/ButtonUtilsCacheTests.swift               # ButtonBindingScopeTests (12 case + JSON 兼容回归)
docs/superpowers/specs/2026-05-17-button-per-app-scope-design.md
.github/workflows/build.yml                        # macOS CI: 测试 + Release 构建 + 深度 ad-hoc 签名
CHANGELOG.md
```

### 构建

本地（需要 Xcode）：

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test
```

CI（GitHub Actions）每次 push 到 `master` 自动跑：
1. Debug 配置跑 `MosTests`
2. Release 配置出 Universal `Mos.app`
3. 深度优先 ad-hoc 签名 Sparkle 嵌套的 XPC + Updater.app + 主 bundle
4. 上传 `Mos-Release-app` artifact

预构建版本在 [Releases](https://github.com/izerok/Mos/releases)。

### 与上游的关系

这里没列出的文件都跟 [Caldis/Mos](https://github.com/Caldis/Mos) 同步。Fresh clone 的 `upstream` remote 直接指向上游仓库；要拉新功能用 `git fetch upstream && git merge upstream/master`。

签名是 ad-hoc 的（没 Apple Developer ID），首次启动 Gatekeeper 会拦：右键 → 打开，或系统设置 → 隐私与安全性 → "仍要打开"。如果电脑上以前装过 Caldis 官方签名的 Mos 还需要清一次 TCC pinning：

```bash
sudo tccutil reset Accessibility com.caldis.Mos
```

---

## English

### What's added: per-binding application scope (whitelist / blacklist)

Upstream Mos's button bindings are global — bind a mouse side button to "Back" and it does "Back" in every app. This fork lets **each binding** declare its own scope of apps where it applies.

**How to use**

1. Preferences → Buttons
2. Select the binding row you want to configure
3. The bottom-right **`Application Scope: ✗ 0`** button enables (default = blacklist + empty = fires everywhere)
4. Click it to open a popover with:
   - `Whitelist | Blacklist` segmented control
   - The list of apps currently in this binding's scope (icon + name)
   - `+` to pick an app from `/Applications`; `−` to remove the selected row

The button's title reflects the selected binding's live state:
- `Application Scope: ✓ 3` = whitelist + 3 apps (fires only in those three)
- `Application Scope: ✗ 2` = blacklist + 2 apps (fires everywhere except those two)
- `Application Scope: ✓ 0` = whitelist + empty = **never fires** (the default for upgraded bindings from the upstream JSON — you must explicitly opt apps in)

**Defaults**

| Source | Default scope |
|---|---|
| Newly recorded binding (via UI) | Blacklist + empty → fires everywhere |
| Binding decoded from upstream pre-fork JSON | Whitelist + empty → does not fire (forces explicit scope confirmation after upgrade) |

**Where the scope check runs**

Scope is evaluated at binding-selection time, not at event-dispatch time:
- `InputProcessor.process(_:)` filters Down-phase candidate bindings by `binding.allowsApp(targetApp)`
- `LogiIntegrationBridge` applies the same predicate when probing for `logi*` bindings on HID++ events
- `ScrollCore`'s `mosScroll`-defer probe applies the same predicate

So mouse-button events, Logitech HID++ device events, and the scroll-defer routing decision all respect each binding's scope.

### Files touched

```
Mos/
  Windows/PreferencesWindow/ButtonsView/
    RecordedEvent.swift                            # ButtonBinding gains allowlist + applications + allowsApp(_:)
    PreferencesButtonsViewController.swift         # bottom-toolbar Application Scope button + scope-preserving binding edits
    ButtonScopePopoverViewController.swift  (new)  # popover, callback-driven, no direct Options writes
  InputEvent/InputProcessor.swift                  # scope predicate at binding match + resolveTargetApp(_:)
  Integration/LogiIntegrationBridge.swift          # logi-prefix probe ANDs allowsApp
  ScrollCore/ScrollCore.swift                      # mosScroll-defer probe ANDs allowsApp
MosTests/ButtonUtilsCacheTests.swift               # ButtonBindingScopeTests (12 cases + JSON compat regression)
docs/superpowers/specs/2026-05-17-button-per-app-scope-design.md
.github/workflows/build.yml                        # macOS CI: tests + Release build + deep ad-hoc sign
CHANGELOG.md
```

### Building

Local (requires Xcode):

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test
```

CI (GitHub Actions, runs on every push to `master`):
1. Tests on Debug configuration via `MosTests`
2. Builds Release configuration into a Universal `Mos.app`
3. Depth-first ad-hoc signs Sparkle's nested XPCs + Updater.app + the main bundle
4. Uploads the `Mos-Release-app` artifact

Prebuilt downloads on the [Releases page](https://github.com/izerok/Mos/releases).

### Relationship to upstream

Everything not listed above tracks [Caldis/Mos](https://github.com/Caldis/Mos) upstream. A fresh clone gets `upstream` pointing at the original repo; pull new upstream work with `git fetch upstream && git merge upstream/master`.

Releases are ad-hoc signed (no Apple Developer ID), so first launch is blocked by Gatekeeper — right-click → Open, or *System Settings → Privacy & Security → Open Anyway*. If you previously installed Caldis-signed Mos on the same Mac, you'll also need to clear stale TCC pinning once:

```bash
sudo tccutil reset Accessibility com.caldis.Mos
```
