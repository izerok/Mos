//
//  ButtonScopePopoverViewController.swift
//  Mos
//  Per-binding 应用作用域 (白名单/黑名单) 编辑 popover.
//  程序化 UI, 不依赖 storyboard. 直接读写指定 binding 的 scope 字段.
//

import Cocoa

class ButtonScopePopoverViewController: NSViewController,
    NSTableViewDelegate, NSTableViewDataSource {

    // MARK: - Subject

    /// 编辑目标 binding 的 ID. popover 通过 ID 查 Options.shared.buttons.binding,
    /// 避免持有可能被替换 (struct copy) 的旧版本.
    private let bindingID: UUID

    init(bindingID: UUID) {
        self.bindingID = bindingID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported, use init(bindingID:)")
    }

    // MARK: - Subviews

    private let titleLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let emptyHintLabel = NSTextField(labelWithString: "")

    // MARK: - 当前 binding 访问辅助

    private func currentBinding() -> ButtonBinding? {
        return Options.shared.buttons.binding.first(where: { $0.id == bindingID })
    }

    private func currentBindingIndex() -> Int? {
        return Options.shared.buttons.binding.firstIndex(where: { $0.id == bindingID })
    }

    private func mutate(_ block: (inout ButtonBinding) -> Void) {
        guard let idx = currentBindingIndex() else { return }
        // struct 数组中修改单个元素: 必须先取出 → 改 → 整体写回, 才能触发 didSet 保存
        var bindings = Options.shared.buttons.binding
        block(&bindings[idx])
        Options.shared.buttons.binding = bindings
        ButtonUtils.shared.invalidateCache()
    }

    // MARK: - Lifecycle

    override func loadView() {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        view = v

        configureTitle()
        configureMode()
        configureTable()
        configureBottomBar()
        configureEmptyHint()
        layoutSubviews()

        syncFromBinding()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        tableView.reloadData()
        updateRemoveButtonState()
        updateEmptyHintVisibility()
    }

    // MARK: - Build subviews

    private func configureTitle() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        view.addSubview(titleLabel)
    }

    private func configureMode() {
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.segmentStyle = .rounded
        modeControl.segmentCount = 2
        modeControl.setLabel(NSLocalizedString("Whitelist", comment: "Only fire in listed apps"), forSegment: 0)
        modeControl.setLabel(NSLocalizedString("Blacklist", comment: "Disable in listed apps"), forSegment: 1)
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        view.addSubview(modeControl)
    }

    private func configureTable() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("appCell"))
        column.title = ""
        column.minWidth = 240
        column.resizingMask = [.autoresizingMask]
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        scrollView.documentView = tableView
    }

    private func configureBottomBar() {
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .smallSquare
        addButton.controlSize = .small
        addButton.title = "+"
        addButton.target = self
        addButton.action = #selector(addApplication(_:))
        view.addSubview(addButton)

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .smallSquare
        removeButton.controlSize = .small
        removeButton.title = "−"
        removeButton.target = self
        removeButton.action = #selector(removeApplication(_:))
        view.addSubview(removeButton)
    }

    private func configureEmptyHint() {
        emptyHintLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyHintLabel.stringValue = NSLocalizedString(
            "Whitelist + no apps — this binding will not fire anywhere",
            comment: "Hint when whitelist mode is on but the per-binding app list is empty"
        )
        emptyHintLabel.font = .systemFont(ofSize: 11)
        emptyHintLabel.textColor = .secondaryLabelColor
        emptyHintLabel.alignment = .center
        emptyHintLabel.lineBreakMode = .byWordWrapping
        emptyHintLabel.maximumNumberOfLines = 2
        view.addSubview(emptyHintLabel)
    }

    private func layoutSubviews() {
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 340),
            view.heightAnchor.constraint(equalToConstant: 300),

            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            modeControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            modeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            addButton.widthAnchor.constraint(equalToConstant: 30),
            addButton.heightAnchor.constraint(equalToConstant: 22),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 4),
            removeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            removeButton.widthAnchor.constraint(equalToConstant: 30),
            removeButton.heightAnchor.constraint(equalToConstant: 22),

            emptyHintLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyHintLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyHintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 16),
            emptyHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - State sync

    private func syncFromBinding() {
        guard let binding = currentBinding() else {
            titleLabel.stringValue = NSLocalizedString("Binding no longer exists", comment: "Title when binding was deleted")
            modeControl.selectedSegment = 1
            updateEmptyHintVisibility()
            return
        }
        let trigger = binding.triggerEvent.displayComponents.joined(separator: " ")
        let action = binding.systemShortcut?.localizedName ?? binding.systemShortcutName
        let fmt = NSLocalizedString("Scope for %@ → %@", comment: "Title: trigger → action")
        titleLabel.stringValue = String(format: fmt, trigger, action)
        modeControl.selectedSegment = binding.allowlist ? 0 : 1
        updateEmptyHintVisibility()
        updateRemoveButtonState()
    }

    private func updateEmptyHintVisibility() {
        guard let binding = currentBinding() else {
            emptyHintLabel.isHidden = true
            return
        }
        emptyHintLabel.isHidden = !(binding.applications.isEmpty && binding.allowlist)
    }

    private func updateRemoveButtonState() {
        removeButton.isEnabled = tableView.selectedRow >= 0
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        mutate { $0.allowlist = (sender.selectedSegment == 0) }
        updateEmptyHintVisibility()
    }

    @objc private func addApplication(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self,
                  response == .OK,
                  let url = panel.url else { return }
            let path = url.path
            self.mutate { binding in
                if !binding.applications.contains(path) {
                    binding.applications.append(path)
                }
            }
            self.tableView.reloadData()
            self.updateEmptyHintVisibility()
            self.updateRemoveButtonState()
        }
    }

    @objc private func removeApplication(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row >= 0,
              let binding = currentBinding(),
              row < binding.applications.count else { return }
        mutate { binding in
            binding.applications.remove(at: row)
        }
        tableView.reloadData()
        updateEmptyHintVisibility()
        updateRemoveButtonState()
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return currentBinding()?.applications.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let binding = currentBinding(), row < binding.applications.count else { return nil }
        let path = binding.applications[row]

        let cell = NSTableCellView()
        let imageView = NSImageView()
        let textField = NSTextField(labelWithString: Utils.getApplicationName(fromPath: path))

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = Utils.getApplicationIcon(fromPath: path)
        imageView.imageScaling = .scaleProportionallyDown

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 12)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.toolTip = path

        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButtonState()
    }
}
