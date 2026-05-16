//
//  ButtonScopePopoverViewController.swift
//  Mos
//  按键 binding 的应用作用域 (白名单/黑名单) 配置 popover.
//  程序化 UI, 不依赖 storyboard.
//

import Cocoa

class ButtonScopePopoverViewController: NSViewController,
    NSTableViewDelegate, NSTableViewDataSource {

    // MARK: - Subviews

    private let modeControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let emptyHintLabel = NSTextField(labelWithString: "")

    // MARK: - Lifecycle

    override func loadView() {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        view = v

        configureMode()
        configureTable()
        configureBottomBar()
        configureEmptyHint()
        layoutSubviews()

        syncFromOptions()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        tableView.reloadData()
        updateRemoveButtonState()
        updateEmptyHintVisibility()
    }

    // MARK: - Layout

    private func configureMode() {
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.segmentStyle = .rounded
        modeControl.segmentCount = 2
        modeControl.setLabel(NSLocalizedString("Whitelist", comment: "Mode toggle: only apply bindings in listed apps"), forSegment: 0)
        modeControl.setLabel(NSLocalizedString("Blacklist", comment: "Mode toggle: disable bindings in listed apps"), forSegment: 1)
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        view.addSubview(modeControl)
    }

    private func configureTable() {
        // Scroll container
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        // Table
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
            "No apps added — button bindings will not fire",
            comment: "Hint when whitelist mode is on but the list is empty"
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
            view.heightAnchor.constraint(equalToConstant: 280),

            modeControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
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

    private func syncFromOptions() {
        modeControl.selectedSegment = Options.shared.buttons.allowlist ? 0 : 1
        updateEmptyHintVisibility()
        updateRemoveButtonState()
    }

    private func updateEmptyHintVisibility() {
        let isEmpty = Options.shared.buttons.applications.isEmpty
        let isWhitelist = Options.shared.buttons.allowlist
        // 只在"白名单+空列表"时显示提示 (这时 binding 完全不生效, 容易让用户困惑).
        emptyHintLabel.isHidden = !(isEmpty && isWhitelist)
    }

    private func updateRemoveButtonState() {
        removeButton.isEnabled = tableView.selectedRow >= 0
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        Options.shared.buttons.allowlist = (sender.selectedSegment == 0)
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
            guard let self = self, response == .OK, let url = panel.url else { return }
            let path = url.path
            var list = Options.shared.buttons.applications
            if !list.contains(path) {
                list.append(path)
                Options.shared.buttons.applications = list   // 显式赋值, 确保 didSet 触发保存
                self.tableView.reloadData()
            }
            self.updateEmptyHintVisibility()
            self.updateRemoveButtonState()
        }
    }

    @objc private func removeApplication(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row >= 0, row < Options.shared.buttons.applications.count else { return }
        var list = Options.shared.buttons.applications
        list.remove(at: row)
        Options.shared.buttons.applications = list   // 显式赋值, 确保 didSet 触发保存
        tableView.reloadData()
        updateEmptyHintVisibility()
        updateRemoveButtonState()
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return Options.shared.buttons.applications.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < Options.shared.buttons.applications.count else { return nil }
        let path = Options.shared.buttons.applications[row]

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
