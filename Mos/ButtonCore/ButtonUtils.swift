//
//  ButtonUtils.swift
//  Mos
//  按钮绑定工具类 - 获取配置和管理绑定 (带缓存)
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

struct ButtonBindingTriggerKey: Hashable {
    let type: EventType
    let code: UInt16
}

class ButtonUtils {

    // 单例
    static let shared = ButtonUtils()
    init() {}

    // MARK: - 缓存

    /// 缓存的绑定列表 (已预解析 custom:: 字段)
    private var cachedBindings: [ButtonBinding] = []
    private var cachedBindingsByTriggerKey: [ButtonBindingTriggerKey: [ButtonBinding]] = [:]
    private var isDirty = true

    // MARK: - 获取按钮绑定配置

    /// 获取当前应用的按钮绑定配置 (带缓存和预解析)
    /// - Returns: 按钮绑定列表
    func getButtonBindings() -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindings
    }

    func getButtonBindings(for type: EventType, code: UInt16) -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindingsByTriggerKey[ButtonBindingTriggerKey(type: type, code: code)] ?? []
    }

    func getBestMatchingBinding(
        for event: InputEvent,
        where predicate: ((ButtonBinding) -> Bool)? = nil
    ) -> ButtonBinding? {
        let candidates = getButtonBindings(for: event.type, code: event.code)
        var bestBinding: ButtonBinding?
        var bestPriority = Int.min

        for binding in candidates {
            guard binding.isEnabled else {
                continue
            }
            if let predicate, !predicate(binding) {
                continue
            }
            guard let priority = binding.triggerEvent.matchPriority(for: event) else {
                continue
            }
            if priority > bestPriority {
                bestBinding = binding
                bestPriority = priority
            }
        }

        return bestBinding
    }

    /// 标记缓存失效 (绑定变更后调用)
    func invalidateCache() {
        isDirty = true
    }

    private func refreshCacheIfNeeded() {
        guard isDirty else { return }

        cachedBindings = Options.shared.buttons.binding.map { binding in
            var b = binding
            b.prepareCustomCache()
            return b
        }

        cachedBindingsByTriggerKey = Dictionary(grouping: cachedBindings) { binding in
            ButtonBindingTriggerKey(
                type: binding.triggerEvent.type,
                code: binding.triggerEvent.code
            )
        }

        isDirty = false
    }

    // MARK: - 分应用支持 (预留接口)

    /// 获取当前焦点应用的配置对象 (预留)
    /// - Returns: Application 对象或 nil
    private func getTargetApplication() -> Application? {
        return nil
    }

    // MARK: - 应用作用域判定 (白名单 / 黑名单)

    /// 判定结果缓存键: 按事件类型 + code 配对 Down/Up.
    private struct DispatchDecisionKey: Hashable {
        let type: EventType
        let code: UInt16
    }

    /// Down 事件记录的判定 (true=允许执行 binding), 由 paired Up 事件取出复用.
    /// 这样在「按下时在 app A (允许), 切到 app B 再松开」的场景下,
    /// Up 会按"按下时的判定"放行, 避免 InputProcessor.activeBindings 表里出现遗留的 down 没法 release.
    private var dispatchDecisions: [DispatchDecisionKey: Bool] = [:]

    /// 判断当前目标 App 是否应该执行按键 binding.
    /// 严格模式: 未知 App (path 全为 nil) 视为 "不在列表".
    /// - Parameter app: 目标 NSRunningApplication
    /// - Returns: true = 执行 binding, false = 透传事件
    func shouldDispatch(for app: NSRunningApplication?) -> Bool {
        let bundlePath = app?.bundleURL?.path
        let execPath = app?.executableURL?.path
        let list = Options.shared.buttons.applications
        let inList = list.contains { entry in
            entry == bundlePath || entry == execPath
        }
        return Options.shared.buttons.allowlist ? inList : !inList
    }

    /// 单测用纯函数版本 (不依赖 Options.shared).
    /// 同样的语义: allowlist=true ⇒ 仅在列表中生效; allowlist=false ⇒ 列表中禁用.
    static func computeShouldDispatch(
        allowlist: Bool,
        applications: [String],
        bundlePath: String? = nil,
        executablePath: String? = nil
    ) -> Bool {
        let inList = applications.contains { entry in
            entry == bundlePath || entry == executablePath
        }
        return allowlist ? inList : !inList
    }

    /// 在 Down 事件回调里记录判定.
    func recordDispatchDecision(type: EventType, code: UInt16, allowed: Bool) {
        dispatchDecisions[DispatchDecisionKey(type: type, code: code)] = allowed
    }

    /// 在 Up 事件回调里取出并移除按下时的判定; 没记录则返回 nil.
    func consumeDispatchDecision(type: EventType, code: UInt16) -> Bool? {
        return dispatchDecisions.removeValue(forKey: DispatchDecisionKey(type: type, code: code))
    }

    /// 清空所有判定 (ButtonCore disable 或 tap 被系统重置时调用).
    func clearDispatchDecisions() {
        dispatchDecisions.removeAll()
    }
}
