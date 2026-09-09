import AppKit

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// Every view in this controller is AppKit. Calendar text is always plain text.
final class EditorViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate
{
    var onChange: (([String: Any]) -> Void)?
    var onInclude: ((String, Bool) -> Void)?
    var onExport: ((Bool) -> Void)?
    private(set) var editor: [String: Any] = [:]
    private(set) var events: [[String: Any]] = []
    private var suggestions: [[String: Any]] = []
    let preview = NSImageView()
    let tabs = NSTabView()
    let summary = NSTextField(labelWithString: "Loading calendar…")
    let warning = NSTextField(wrappingLabelWithString: "")
    private var warningScroll: NSScrollView!
    let error = NSTextField(wrappingLabelWithString: "")
    let table = NSTableView()
    let details = NSTextView()
    let mode = NSPopUpButton()
    let theme = NSPopUpButton()
    let resolution = NSPopUpButton()
    let course = NSPopUpButton()
    let name = NSTextField()
    let start = NSDatePicker()
    let end = NSDatePicker()
    let month = NSDatePicker()
    let showTitle = NSButton(checkboxWithTitle: "Show title", target: nil, action: nil)
    let rooms = NSButton(checkboxWithTitle: "Show rooms", target: nil, action: nil)
    let iconSpace = NSButton(
        checkboxWithTitle: "Leave room for desktop icons", target: nil, action: nil)
    let exportMenu = NSPopUpButton(frame: .zero, pullsDown: true)
    let appearanceToggle = NSButton(checkboxWithTitle: "Appearance", target: nil, action: nil)
    private(set) var appearanceFields: NSStackView!
    private var moduleFields: NSStackView!
    private var monthField: NSStackView!
    private let suggestionList = NSStackView()
    private var suggestionSignature = ""
    private let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 10)
        -> NSStackView
    {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        return stack
    }
    private func field(_ title: String, _ control: NSView) -> NSStackView {
        control.setAccessibilityLabel(title)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let stack = Self.stack([label, control], spacing: 5)
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }
    private func scroll(_ content: NSView) -> NSScrollView {
        let document = FlippedDocumentView()
        document.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
        ])
        return scroll
    }
    override func loadView() {
        view = NSView()
        mode.addItems(withTitles: ["Module", "Month"])
        theme.addItems(withTitles: ["Light", "Dark"])
        for control in [mode, theme, resolution, course] {
            control.target = self
            control.action = #selector(changeControl(_:))
        }
        name.delegate = self
        name.setAccessibilityIdentifier("module-name")
        for picker in [start, end, month] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = picker === month ? .yearMonth : .yearMonthDay
            picker.calendar = Calendar(identifier: .gregorian)
            picker.timeZone = TimeZone(secondsFromGMT: 0)
            picker.target = self
            picker.action = #selector(changeControl(_:))
        }
        for control in [showTitle, rooms, iconSpace] {
            control.target = self
            control.action = #selector(changeControl(_:))
        }
        moduleFields = Self.stack([
            field("Module name", name), field("First day", start), field("Last day", end),
        ])
        monthField = field("Month", month)
        exportMenu.addItem(withTitle: "Export")
        for (title, action) in [
            ("PNG · Current appearance…", #selector(exportPNG)),
            ("HEIC · Light and dark…", #selector(exportHEIC)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            exportMenu.menu?.addItem(item)
        }
        exportMenu.setAccessibilityLabel("Export wallpaper")
        appearanceFields = Self.stack(
            [
                field("Preview appearance", theme), field("Image size", resolution), showTitle,
                rooms, iconSpace,
            ], spacing: 14)
        appearanceFields.isHidden = true
        appearanceToggle.setButtonType(.onOff)
        appearanceToggle.isBordered = false
        appearanceToggle.image = NSImage(
            systemSymbolName: "chevron.right", accessibilityDescription: nil)
        appearanceToggle.imagePosition = .imageLeft
        appearanceToggle.alignment = .left
        appearanceToggle.title = "Appearance"
        appearanceToggle.font = .systemFont(ofSize: 13, weight: .semibold)
        appearanceToggle.target = self
        appearanceToggle.action = #selector(toggleAppearance)
        appearanceToggle.setAccessibilityLabel("Show appearance options")
        let heading = NSTextField(labelWithString: "Schedule")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let separator = NSBox()
        separator.boxType = .separator
        let settings = Self.stack(
            [
                heading, field("View", mode), moduleFields, monthField,
                field("Include", course), separator, appearanceToggle, appearanceFields!,
            ], spacing: 18)
        for child in settings.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true
        }
        for group in [moduleFields!, appearanceFields!] {
            for child in group.arrangedSubviews {
                child.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
            }
        }
        let sidebar = scroll(settings)
        sidebar.widthAnchor.constraint(equalToConstant: 255).isActive = true

        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel(
            "Wallpaper preview. Full event information is available in Choose events.")
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let previewTab = NSTabViewItem(identifier: "preview")
        previewTab.label = "Preview"
        previewTab.view = preview
        tabs.addTabViewItem(previewTab)

        let instruction = NSTextField(
            wrappingLabelWithString:
                "Uncheck an event to leave it out of the wallpaper and exports. Select a row to read its full details."
        )
        instruction.font = .systemFont(ofSize: 12)
        for (id, title, width) in [
            ("included", "Include", 65.0), ("date", "Date and time", 175.0),
            ("title", "Session", 280.0), ("source", "Calendar", 120.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "included" ? 65 : 80
            table.addTableColumn(column)
        }
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.setAccessibilityLabel("Calendar events")
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
        details.isEditable = false
        details.isSelectable = true
        details.isRichText = false
        details.font = .systemFont(ofSize: 13)
        details.textContainerInset = NSSize(width: 12, height: 12)
        details.autoresizingMask = [.width]
        details.isHorizontallyResizable = false
        details.textContainer?.widthTracksTextView = true
        details.setAccessibilityLabel("Full event details")
        details.string = "Select an event to see its full title, location, description, and source."
        let detailScroll = NSScrollView()
        detailScroll.documentView = details
        detailScroll.hasVerticalScroller = true
        let eventSplit = NSSplitView()
        eventSplit.isVertical = false
        eventSplit.dividerStyle = .thin
        eventSplit.addArrangedSubview(tableScroll)
        eventSplit.addArrangedSubview(detailScroll)
        tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        detailScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        let eventView = NSView()
        eventView.autoresizingMask = [.width, .height]
        for child in [instruction, eventSplit] {
            eventView.addSubview(child)
            child.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            instruction.topAnchor.constraint(equalTo: eventView.topAnchor),
            instruction.leadingAnchor.constraint(equalTo: eventView.leadingAnchor),
            instruction.trailingAnchor.constraint(equalTo: eventView.trailingAnchor),
            eventSplit.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 10),
            eventSplit.bottomAnchor.constraint(equalTo: eventView.bottomAnchor),
            eventSplit.leadingAnchor.constraint(equalTo: eventView.leadingAnchor),
            eventSplit.trailingAnchor.constraint(equalTo: eventView.trailingAnchor),
        ])
        let eventTab = NSTabViewItem(identifier: "events")
        eventTab.label = "Choose events"
        eventTab.view = eventView
        tabs.addTabViewItem(eventTab)

        suggestionList.orientation = .vertical
        suggestionList.alignment = .leading
        suggestionList.spacing = 18
        let suggestionTab = NSTabViewItem(identifier: "suggestions")
        suggestionTab.label = "Suggested modules"
        suggestionTab.view = scroll(suggestionList)
        tabs.addTabViewItem(suggestionTab)
        summary.font = .systemFont(ofSize: 12)
        summary.textColor = .secondaryLabelColor
        warning.font = .systemFont(ofSize: 12)
        warning.textColor = .secondaryLabelColor
        error.font = .systemFont(ofSize: 12)
        error.textColor = .systemRed
        error.isHidden = true
        warningScroll = scroll(warning)
        warningScroll.heightAnchor.constraint(equalToConstant: 80).isActive = true
        warningScroll.isHidden = true
        let main = Self.stack([error, tabs, summary, warningScroll!])
        main.distribution = .fill
        tabs.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        for child in main.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true
        }
        let body = Self.stack([sidebar, main], vertical: false, spacing: 16)
        body.alignment = .top
        view.addSubview(body)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.topAnchor.constraint(equalTo: view.topAnchor),
            body.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.heightAnchor.constraint(equalTo: body.heightAnchor),
            main.heightAnchor.constraint(equalTo: body.heightAnchor),
            main.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -271),
        ])
        setReady(false)
    }

    func setReady(_ ready: Bool) {
        for control: NSControl in [
            mode, theme, resolution, course, name, start, end, month, showTitle, rooms, iconSpace,
            exportMenu,
        ] { control.isEnabled = ready }
    }
    func showError(_ message: String) {
        error.stringValue = message
        error.isHidden = message.isEmpty
        if !message.isEmpty { NSAccessibility.post(element: error, notification: .valueChanged) }
    }
    func display(_ snapshot: [String: Any]) {
        let selected =
            events.indices.contains(table.selectedRow)
            ? events[table.selectedRow]["uid"] as? String : nil
        editor = snapshot["editor"] as? [String: Any] ?? [:]
        events = snapshot["events"] as? [[String: Any]] ?? []
        mode.selectItem(at: editor["mode"] as? String == "month" ? 1 : 0)
        theme.selectItem(at: editor["theme"] as? String == "dark" ? 1 : 0)
        // Keep text being edited intact when a background refresh arrives.
        if name.currentEditor() == nil { name.stringValue = editor["name"] as? String ?? "" }
        for (picker, key) in [(start, "start"), (end, "end"), (month, "month")] {
            let value = editor[key] as? String ?? ""
            if let date = dateFormat.date(from: key == "month" ? value + "-01" : value) {
                picker.dateValue = date
            }
        }
        moduleFields.isHidden = mode.indexOfSelectedItem != 0
        monthField.isHidden = mode.indexOfSelectedItem != 1
        showTitle.state = editor["showTitle"] as? Bool == true ? .on : .off
        rooms.state = editor["rooms"] as? Bool == true ? .on : .off
        iconSpace.state = editor["iconSpace"] as? Bool == true ? .on : .off
        let size = "\(editor["width"] as? Int ?? 3024) × \(editor["height"] as? Int ?? 1964)"
        resolution.removeAllItems()
        for value in [
            size, "3024 × 1964", "3456 × 2234", "2560 × 1440", "3840 × 2160", "1920 × 1080",
        ] where resolution.item(withTitle: value) == nil { resolution.addItem(withTitle: value) }
        resolution.selectItem(withTitle: size)
        let filter = editor["course"] as? String ?? ""
        let configured = snapshot["courseCode"] as? String ?? ""
        course.removeAllItems()
        course.addItem(withTitle: "All calendar events")
        course.lastItem?.representedObject = ""
        for code in [configured, filter]
        where !code.isEmpty
            && !course.itemArray.contains(where: { $0.representedObject as? String == code })
        {
            course.addItem(withTitle: "Course only · \(code)")
            course.lastItem?.representedObject = code
        }
        course.selectItem(
            at: course.itemArray.firstIndex(where: { $0.representedObject as? String == filter })
                ?? 0)
        let included = snapshot["includedCount"] as? Int ?? 0
        summary.stringValue = "\(included) events included · \(events.count - included) excluded"
        summary.toolTip = "Snapshot \(editor["snapshotDate"] as? String ?? "none") · \(size)"
        warning.stringValue = (snapshot["warnings"] as? [String] ?? []).joined(separator: "\n")
        warningScroll.isHidden = warning.stringValue.isEmpty
        table.reloadData()
        if let selected, let index = events.firstIndex(where: { $0["uid"] as? String == selected })
        {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        showDetails()
        suggestions = snapshot["suggestions"] as? [[String: Any]] ?? []
        let signature =
            (try? JSONSerialization.data(withJSONObject: suggestions, options: [.sortedKeys])
                .base64EncodedString()) ?? ""
        if signature != suggestionSignature {
            suggestionSignature = signature
            reloadSuggestions()
        }
    }
    @objc func changeControl(_ sender: NSControl) {
        var patch: [String: Any] = [:]
        switch sender {
        case mode: patch["mode"] = mode.indexOfSelectedItem == 1 ? "month" : "module"
        case theme: patch["theme"] = theme.indexOfSelectedItem == 1 ? "dark" : "light"
        case course: patch["course"] = course.selectedItem?.representedObject as? String ?? ""
        case resolution:
            let values =
                resolution.titleOfSelectedItem?.components(separatedBy: " × ").compactMap(Int.init)
                ?? []
            if values.count == 2 {
                patch["width"] = values[0]
                patch["height"] = values[1]
            }
        case start, end:
            // Submit the whole range so the second edit can repair an invalid first edit.
            patch["start"] = dateFormat.string(from: start.dateValue)
            patch["end"] = dateFormat.string(from: end.dateValue)
        case month: patch["month"] = String(dateFormat.string(from: month.dateValue).prefix(7))
        case showTitle: patch["showTitle"] = showTitle.state == .on
        case rooms: patch["rooms"] = rooms.state == .on
        case iconSpace: patch["iconSpace"] = iconSpace.state == .on
        default: break
        }
        if !patch.isEmpty { onChange?(patch) }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === name else { return }
        onChange?(["name": name.stringValue])
    }
    @objc func toggleAppearance() {
        appearanceFields.isHidden = appearanceToggle.state != .on
        appearanceToggle.image = NSImage(
            systemSymbolName: appearanceToggle.state == .on ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil)
        appearanceToggle.setAccessibilityLabel(
            appearanceToggle.state == .on ? "Hide appearance options" : "Show appearance options")
    }
    @objc func exportPNG() {
        view.window?.makeFirstResponder(nil)
        onExport?(false)
    }
    @objc func exportHEIC() {
        view.window?.makeFirstResponder(nil)
        onExport?(true)
    }
    @objc func showSuggestions() { tabs.selectTabViewItem(withIdentifier: "suggestions") }
    func closeDetails() { tabs.selectTabViewItem(withIdentifier: "preview") }
    func numberOfRows(in tableView: NSTableView) -> Int { events.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard events.indices.contains(row) else { return nil }
        let event = events[row]
        if column?.identifier.rawValue == "included" {
            let checkbox = NSButton(
                checkboxWithTitle: "", target: self, action: #selector(includeEvent(_:)))
            checkbox.tag = row
            checkbox.state = event["included"] as? Bool == true ? .on : .off
            checkbox.setAccessibilityLabel(
                "Include \(event["title"] as? String ?? "event"), \(event["date"] as? String ?? "")"
            )
            return checkbox
        }
        let text: String
        switch column?.identifier.rawValue {
        case "date":
            text =
                "\(event["date"] as? String ?? "") · \(event["allDay"] as? Bool == true ? "All day" : event["startTime"] as? String ?? "")"
        case "source": text = event["sourceName"] as? String ?? ""
        default: text = event["title"] as? String ?? ""
        }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        return label
    }
    @objc func includeEvent(_ sender: NSButton) {
        guard events.indices.contains(sender.tag), let uid = events[sender.tag]["uid"] as? String
        else { return }
        onInclude?(uid, sender.state == .on)
    }
    func tableViewSelectionDidChange(_ notification: Notification) { showDetails() }
    private func showDetails() {
        guard events.indices.contains(table.selectedRow) else {
            details.string =
                events.isEmpty
                ? "No events in this range and course filter."
                : "Select an event to see its full details."
            return
        }
        let event = events[table.selectedRow]
        var lines = [
            event["title"] as? String ?? "",
            "\(event["date"] as? String ?? "") · \(event["allDay"] as? Bool == true ? "All day" : "\(event["startTime"] as? String ?? "") – \(event["endTime"] as? String ?? "")")",
        ]
        for key in ["location", "description"] {
            if let value = event[key] as? String, !value.isEmpty { lines.append(value) }
        }
        if event["roomConflict"] as? Bool == true {
            lines.append(
                "The description mentions another room. Check the source before attending.")
        }
        lines.append(
            [event["sourceName"] as? String, event["summary"] as? String].compactMap { $0 }.joined(
                separator: " · "))
        details.string = lines.joined(separator: "\n\n")
    }
    private func reloadSuggestions() {
        for child in suggestionList.arrangedSubviews {
            suggestionList.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        let note = NSTextField(
            wrappingLabelWithString:
                "Estimates from TimeEdit course events, excluding unchecked events. Edit a name and dates, then choose Use module. Automatic wallpaper updates also apply accepted changes."
        )
        suggestionList.addArrangedSubview(note)
        if suggestions.isEmpty {
            suggestionList.addArrangedSubview(
                NSTextField(
                    wrappingLabelWithString:
                        "Not enough matching sessions to suggest a module. You can still enter a name and dates manually."
                ))
        }
        for suggestion in suggestions {
            let card = ModuleSuggestionView(suggestion: suggestion)
            card.onUse = { [weak self] patch in self?.onChange?(patch) }
            suggestionList.addArrangedSubview(card)
        }
        for child in suggestionList.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: suggestionList.widthAnchor).isActive = true
        }
    }
}

private final class ModuleSuggestionView: NSView {
    var onUse: (([String: Any]) -> Void)?
    private let name = NSTextField()
    private let start = NSDatePicker()
    private let end = NSDatePicker()
    private let formatter = DateFormatter()
    init(suggestion: [String: Any]) {
        super.init(frame: .zero)
        let title = NSTextField(
            labelWithString: suggestion["name"] as? String ?? "Suggested module")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        name.stringValue = suggestion["name"] as? String ?? ""
        name.setAccessibilityLabel("Suggested module name")
        for (picker, key, label) in [
            (start, "start", "Suggested first day"), (end, "end", "Suggested last day"),
        ] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .yearMonthDay
            picker.calendar = Calendar(identifier: .gregorian)
            picker.timeZone = TimeZone(secondsFromGMT: 0)
            picker.dateValue = formatter.date(from: suggestion[key] as? String ?? "") ?? Date()
            picker.setAccessibilityLabel(label)
        }
        let reason = NSTextField(
            wrappingLabelWithString:
                "\(suggestion["confidence"] as? String ?? "") · \(suggestion["count"] as? Int ?? 0) sessions\n"
                + (suggestion["reasons"] as? [String] ?? []).joined(separator: "\n"))
        reason.font = .systemFont(ofSize: 12)
        let dates = EditorViewController.stack(
            [
                NSTextField(labelWithString: "First day"), start,
                NSTextField(labelWithString: "Last day"), end,
            ], vertical: false)
        let content = EditorViewController.stack([
            title, reason, name, dates,
            NSButton(title: "Use module", target: self, action: #selector(useModule)),
        ])
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
        for child in [title, reason, name] {
            child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func useModule() {
        window?.makeFirstResponder(nil)
        onUse?([
            "mode": "module",
            "name": name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            "start": formatter.string(from: start.dateValue),
            "end": formatter.string(from: end.dateValue), "proposed": false,
        ])
    }
}
