#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#if !SINGLE_MODULE
import DiskScanCore
import SunburstGeometry
#endif

/// One outline row: a node (maybe path-compressed) or a merged “其他 N 项” bucket.
final class OutlineItem {
    let node: FileNode?
    let name: String
    let size: Double
    let otherCount: Int
    /// Matching chart sector (1:1 for the chart's rings), nil deeper down.
    let sector: Int?
    weak var parent: OutlineItem?
    var kids: [OutlineItem]?
    /// Zero-size / unreadable entry shown via the footer's 「显示」 (P2-10).
    var isHiddenEntry = false
    /// Filter hit that the chart merged into 「其他」: neutral grey dot (P2-9).
    var mergedIntoOther = false
    /// Search hit: flat row with its relative parent path shown after the name.
    var isSearchHit = false
    var subtitle: String?
    init(node: FileNode?, name: String, size: Double, otherCount: Int, sector: Int?, parent: OutlineItem?) {
        self.node = node; self.name = name; self.size = size; self.otherCount = otherCount
        self.sector = sector; self.parent = parent
    }
    var isExpandable: Bool {
        guard let n = node, !isHiddenEntry, !isSearchHit else { return false }
        return n.isDirectory && n.children.contains { $0.sunburstSize > 0 }
    }
}

/// NSOutlineView with row hover reporting (for chart ↔ list hover sync) and
/// Space = add to the delete zone.
final class HoverOutlineView: NSOutlineView {
    var onHoverRow: ((Int) -> Void)?
    var onSpace: (() -> Void)?
    /// Pane (clip view) resized → ResultsOutline.fitColumns().
    var onResize: (() -> Void)?
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        onResize?()
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        onResize?()
    }
    private(set) var hoverRow = -1
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let r = row(at: convert(event.locationInWindow, from: nil))
        if r != hoverRow { setHoverRow(r); onHoverRow?(r) }
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoverRow(-1); onHoverRow?(-1)
    }
    func setHoverRow(_ r: Int) {
        guard r != hoverRow else { return }
        let old = hoverRow
        hoverRow = r
        for i in [old, r] where i >= 0 && i < numberOfRows {
            (rowView(atRow: i, makeIfNecessary: false) as? FinderRowView)?.isHoverRow = (i == r)
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, let onSpace {
            onSpace()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Selected row filled with the brand colour (README §5: not controlAccentColor), inset 8, radius 5.
final class FinderRowView: NSTableRowView {
    var isHoverRow = false { didSet { if oldValue != isHoverRow { needsDisplay = true } } }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.drBrand.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 0), xRadius: 5, yRadius: 5).fill()
    }
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isHoverRow, !isSelected else { return }
        NSColor.drToken.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 0), xRadius: 5, yRadius: 5).fill()
    }
}

/// Name cell: colour dot 8 · icon 16 · name · badge (⚠ 高风险 / 🔒 受保护).
final class NameCellView: NSTableCellView {
    let dot = NSView()
    let icon = NSImageView()
    let name = NSTextField.label("")
    let badge = NSTextField.label("", size: 11)
    /// Line 2 for search hits: relative path, smaller + grey, middle-truncated.
    let path = NSTextField.label("", size: CGFloat(ResultRowLayout.path.fontSize), color: .drTextSecondary)
    private var nameCenter: NSLayoutConstraint!
    private var nameTop: NSLayoutConstraint!
    static func configureSingleLine(_ f: NSTextField, _ line: ResultRowLayout.Line) {
        f.usesSingleLineMode = line.singleLineMode
        f.cell?.wraps = line.wraps
        f.cell?.isScrollable = false
        f.maximumNumberOfLines = line.maxLines
        f.lineBreakMode = line.truncation == .middle ? .byTruncatingMiddle : .byTruncatingTail
        f.cell?.lineBreakMode = f.lineBreakMode
        f.cell?.truncatesLastVisibleLine = true
        f.font = .systemFont(ofSize: CGFloat(line.fontSize))
    }
    /// Two-line layout for search hits, one line otherwise.
    var isTwoLine = false {
        didSet {
            path.isHidden = !isTwoLine
            nameCenter.isActive = !isTwoLine
            nameTop.isActive = isTwoLine
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        Self.configureSingleLine(name, ResultRowLayout.name)
        Self.configureSingleLine(path, ResultRowLayout.path)
        Self.configureSingleLine(badge, ResultRowLayout.Line(fontSize: 11, lineHeight: 14, truncation: .tail, maxLines: 1, wraps: false, singleLineMode: true))
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [dot, icon, name, path, badge] as [NSView] { addSubview(v) }
        path.isHidden = true
        nameCenter = name.centerYAnchor.constraint(equalTo: centerYAnchor)
        nameTop = name.topAnchor.constraint(equalTo: topAnchor, constant: CGFloat(ResultRowLayout.verticalPadding))
        textField = name
        imageView = icon
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8),
            icon.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            nameCenter,
            name.heightAnchor.constraint(equalToConstant: CGFloat(ResultRowLayout.name.lineHeight)),
            path.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: CGFloat(ResultRowLayout.lineGap)),
            path.heightAnchor.constraint(equalToConstant: CGFloat(ResultRowLayout.path.lineHeight)),
            path.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -CGFloat(ResultRowLayout.badgeGap)),
            // Badge: fixed trailing slot, aligned to the size column side; name/path stop before it.
            name.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -CGFloat(ResultRowLayout.badgeGap)),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CGFloat(ResultRowLayout.badgeTrailingInset)),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let sel = backgroundStyle == .emphasized
            name.textColor = sel ? .white : (isMuted ? .drTextSecondary : .labelColor)
            path.textColor = sel ? .white : .drTextSecondary
            badge.textColor = sel ? .white : badgeColor
        }
    }
    var isMuted = false
    var badgeColor: NSColor = .drWarnText
}

/// Data source / delegate for the right-hand outline. Levels covered by the
/// chart mirror the cached `ChartModel` 1:1; deeper levels use `OutlineRules`.
@MainActor
final class ResultsOutline: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let view = HoverOutlineView()
    private(set) var roots: [OutlineItem] = []
    private(set) var model: ChartModel<FileNode>?
    private var bySector: [Int: OutlineItem] = [:]
    var isHighRisk: (FileNode) -> Bool = { _ in false }
    var isProtected: (FileNode) -> Bool = { _ in false }
    var isInBasket: (FileNode) -> Bool = { _ in false }
    /// Extra row tooltip (e.g. why it could not be added to the delete zone, P2-5).
    var extraToolTip: (FileNode) -> String? = { _ in nil }
    /// Footer 「显示」: list zero-size / unreadable entries at the end of each level (P2-10).
    var showHidden = false
    /// Filter result count (nil when not filtering) for the footer / empty message.
    private(set) var filterMatches: Int?
    var onSelectionChanged: (() -> Void)?
    var onDoubleClick: ((OutlineItem) -> Void)?
    private var focusSize: Double = 1
    private static let folderIcon: NSImage = NSWorkspace.shared.icon(for: .folder)
    private static let fileIcon: NSImage = NSWorkspace.shared.icon(for: .data)
    private static let otherIcon: NSImage? = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)

    override init() {
        super.init()
        // Name absorbs every width change; size/share are fixed, right-aligned, not user-resizable.
        let w0 = OutlineColumns.widths(pane: SplitLayout.listMin, measuredSizeText: Self.measuredSizeText)
        let cols: [(String, String, CGFloat)] = [("name", tr("column.name"), CGFloat(w0.name)),
                                                 ("size", tr("column.size"), CGFloat(w0.size)),
                                                 ("share", tr("column.share"), CGFloat(w0.share))]
        for (id, title, w) in cols {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = w
            if id == "name" {
                c.minWidth = CGFloat(OutlineColumns.nameMinimum); c.maxWidth = 10_000
                c.resizingMask = .autoresizingMask
            } else {
                c.minWidth = w; c.maxWidth = w
                c.resizingMask = []
                c.headerCell.alignment = .right
            }
            c.headerCell.font = .systemFont(ofSize: 11)
            view.addTableColumn(c)
            if id == "name" { view.outlineTableColumn = c }
        }
        view.tableColumns.first { $0.identifier.rawValue == "size" }?.headerToolTip = tr("column.onDisk.tip")
        view.style = .inset
        view.rowHeight = CGFloat(ResultRowLayout.normalRowHeight)
        view.indentationPerLevel = 18
        view.usesAlternatingRowBackgroundColors = false
        view.allowsMultipleSelection = true
        view.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        view.setDraggingSourceOperationMask(.copy, forLocal: true)
        view.setDraggingSourceOperationMask([], forLocal: false)   // no Finder / external
        view.intercellSpacing = NSSize(width: CGFloat(OutlineColumns.intercellSpacing), height: view.intercellSpacing.height)
        view.autosaveName = nil                 // never restore stale column widths
        view.autosaveTableColumns = false
        view.allowsColumnReordering = false
        view.autoresizingMask = [.width]
        view.onResize = { [weak self] in self?.fitColumns() }
        view.backgroundColor = .controlBackgroundColor
        view.dataSource = self
        view.delegate = self
        view.target = self
        view.doubleAction = #selector(doubleClicked(_:))
    }

    /// Real width of "999.9 GB" in the size column font.
    static var measuredSizeText: Double {
        Double((OutlineColumns.widestSize as NSString).size(withAttributes: [.font: NSFont.drNumber(13)]).width)
    }

    /// Name column = clip width minus the fixed columns (called on every pane resize and reload).
    func fitColumns() {
        // The clip view's width already excludes a legacy (non-overlay) vertical scroller.
        guard let clip = view.enclosingScrollView?.contentView, clip.bounds.width > 0 else { return }
        let w = OutlineColumns.widths(pane: Double(clip.bounds.width), measuredSizeText: Self.measuredSizeText)
        for c in view.tableColumns {
            switch c.identifier.rawValue {
            case "name": if abs(Double(c.width) - w.name) > 0.5 { c.width = CGFloat(w.name) }
            case "size": c.minWidth = CGFloat(w.size); c.maxWidth = CGFloat(w.size); c.width = CGFloat(w.size)
            case "share": c.width = CGFloat(w.share)
            default: break
            }
        }
    }

    // MARK: Model

    func reload(model: ChartModel<FileNode>?, focus: FileNode?) {
        defer { fitColumns() }
        self.model = model
        bySector = [:]
        focusSize = max(1, focus?.sunburstSize ?? 1)
        filterMatches = nil; searchShown = 0; isSearchMode = false
        if let m = model {
            roots = items(forSectors: m.childrenOf[-1] ?? [], parent: nil) + hiddenItems(of: focus, parent: nil)
        } else if let f = focus {
            roots = items(forNode: f, parent: nil) + hiddenItems(of: f, parent: nil)
        } else {
            roots = []
        }
        view.reloadData()
    }

    /// Whole-tree search results (「搜索文件和文件夹」): flat rows, size descending, ≤ 500,
    /// each with its parent path relative to the scan root. Share is relative to the root.
    private(set) var isSearchMode = false
    private(set) var searchShown = 0
    /// Search started: empty result list (the footer shows "searching…").
    func showSearching() {
        defer { fitColumns() }
        model = nil; bySector = [:]; isSearchMode = true
        filterMatches = nil; searchShown = 0; roots = []
        view.reloadData()
    }

    func showSearch(_ r: TreeSearch.Result, root: FileNode) {
        defer { fitColumns() }
        model = nil
        bySector = [:]
        isSearchMode = true
        focusSize = max(1, root.sunburstSize)
        filterMatches = r.total
        searchShown = r.hits.count
        roots = r.hits.map { h in
            let it = OutlineItem(node: h.node, name: h.name, size: h.size, otherCount: 0, sector: nil, parent: nil)
            it.subtitle = h.relativePath.isEmpty ? "/" : h.relativePath
            it.isSearchHit = true
            return it
        }
        view.reloadData()
    }

    private func items(forSectors idx: [Int], parent: OutlineItem?) -> [OutlineItem] {
        guard let m = model else { return [] }
        return idx.map { i in
            let s = m.sectors[i]
            let it = OutlineItem(node: s.node, name: s.name, size: s.size, otherCount: s.otherCount, sector: i, parent: parent)
            bySector[i] = it
            return it
        }
    }

    private func items(forNode n: FileNode, parent: OutlineItem?) -> [OutlineItem] {
        let lvl = OutlineRules.children(of: n)
        var out = lvl.shown.map { OutlineItem(node: $0, name: $0.sunburstName, size: $0.sunburstSize, otherCount: 0, sector: nil, parent: parent) }
        if lvl.otherCount > 0 {
            out.append(OutlineItem(node: nil, name: tr("chart.otherItems", lvl.otherCount), size: lvl.otherSize,
                                   otherCount: lvl.otherCount, sector: nil, parent: parent))
        }
        return out
    }

    /// Cached data only (size + `isRestricted`); never rescans.
    private func hiddenItems(of n: FileNode?, parent: OutlineItem?) -> [OutlineItem] {
        guard showHidden, let n else { return [] }
        return n.children.filter { $0.sunburstSize == 0 || $0.sunburstIsRestricted }.prefix(500).map {
            let it = OutlineItem(node: $0, name: $0.sunburstName, size: $0.sunburstSize, otherCount: 0, sector: nil, parent: parent)
            it.isHiddenEntry = true
            return it
        }
    }

    private func children(of item: OutlineItem) -> [OutlineItem] {
        if let k = item.kids { return k }
        var k: [OutlineItem] = []
        if let s = item.sector, let idx = model?.childrenOf[s] {
            k = items(forSectors: idx, parent: item) + hiddenItems(of: item.node, parent: item)
        } else if let n = item.node {
            k = items(forNode: n, parent: item) + hiddenItems(of: n, parent: item)
        }
        item.kids = k
        return k
    }

    func item(forSector s: Int) -> OutlineItem? { bySector[s] }

    /// Expands ancestors and selects the row of a chart sector.
    func select(sector: Int?) {
        guard let s = sector, let it = bySector[s] else { view.deselectAll(nil); return }
        var chain: [OutlineItem] = []
        var p = it.parent
        while let x = p { chain.insert(x, at: 0); p = x.parent }
        for x in chain { view.expandItem(x) }
        let r = view.row(forItem: it)
        if r >= 0 {
            view.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            view.scrollRowToVisible(r)
        }
    }

    func hover(sector: Int?) {
        guard let s = sector, let it = bySector[s] else { view.setHoverRow(-1); return }
        view.setHoverRow(view.row(forItem: it))
    }

    var selectedItems: [OutlineItem] { view.selectedRowIndexes.compactMap { view.item(atRow: $0) as? OutlineItem } }
    var selectedNodes: [FileNode] { selectedItems.compactMap(\.node) }

    /// Selection, or the context-menu `clickedRow` when selection is still empty (first right-click).
    var actionItems: [OutlineItem] {
        let rows = OutlineActionTargets.rowIndexes(selected: view.selectedRowIndexes,
                                                   clickedRow: view.clickedRow,
                                                   rowCount: view.numberOfRows)
        return rows.compactMap { view.item(atRow: $0) as? OutlineItem }
    }
    var actionNodes: [FileNode] { actionItems.compactMap(\.node) }

    /// Finder-like: right-clicking an unselected row selects it before the menu action runs.
    @discardableResult
    func promoteClickedRowIntoSelectionIfNeeded() -> Bool {
        let clicked = view.clickedRow
        guard OutlineActionTargets.shouldSelectClickedRow(selected: view.selectedRowIndexes,
                                                          clickedRow: clicked,
                                                          rowCount: view.numberOfRows) else { return false }
        view.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        return true
    }
    func hoveredItem(row: Int) -> OutlineItem? { row >= 0 ? view.item(atRow: row) as? OutlineItem : nil }

    func refreshVisibleRows() {
        let rows = view.rows(in: view.visibleRect)
        guard rows.length > 0 else { return }
        view.reloadData(forRowIndexes: IndexSet(integersIn: rows.location..<(rows.location + rows.length)),
                        columnIndexes: IndexSet(integersIn: 0..<view.numberOfColumns))
    }

    @objc private func doubleClicked(_ sender: Any?) {
        guard let it = view.item(atRow: view.clickedRow) as? OutlineItem else { return }
        onDoubleClick?(it)
    }


    // MARK: Drag → delete zone (internal pasteboard only; no Finder drop)

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let it = item as? OutlineItem, let n = it.node else { return nil }
        let pb = NSPasteboardItem()
        _ = pb.setString(BasketDrag.encodePaths([n.path]), forType: NSPasteboard.PasteboardType(BasketDrag.pasteboardType))
        return pb
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        // Multi-select: if the drag started inside the selection, put ALL selected paths on the pasteboard.
        promoteClickedRowIntoSelectionIfNeeded()
        let nodes = actionNodes
        let paths = (nodes.isEmpty ? draggedItems.compactMap { ($0 as? OutlineItem)?.node?.path } : nodes.map(\.path))
        let pb = session.draggingPasteboard
        pb.clearContents()
        pb.setString(BasketDrag.encodePaths(paths), forType: NSPasteboard.PasteboardType(BasketDrag.pasteboardType))
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let it = item as? OutlineItem else { return roots.count }
        return children(of: it).count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let it = item as? OutlineItem else { return roots[index] }
        return children(of: it)[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? OutlineItem)?.isExpandable ?? false
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { FinderRowView() }

    private func color(for it: OutlineItem) -> NSColor {
        let mode = view.themeMode
        if it.mergedIntoOther || it.isHiddenEntry { return NSColor(SunburstPalette.fixed(.other, mode)) }
        var cur: OutlineItem? = it
        while let c = cur {
            if let s = c.sector, let m = model, s < m.sectors.count {
                let sec = m.sectors[s]
                return NSColor(mode == .light ? sec.color.light : sec.color.dark)
            }
            cur = c.parent
        }
        return NSColor(SunburstPalette.fixed(.other, mode))
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let it = item as? OutlineItem, let id = tableColumn?.identifier.rawValue else { return nil }
        switch id {
        case "name":
            let cell = (outlineView.makeView(withIdentifier: .init("nameCell"), owner: nil) as? NameCellView) ?? {
                let c = NameCellView(frame: .zero); c.identifier = .init("nameCell"); return c }()
            cell.dot.layer?.backgroundColor = color(for: it).cgColor
            if let n = it.node {
                cell.icon.image = n.isDirectory ? Self.folderIcon : Self.fileIcon
            } else {
                cell.icon.image = Self.otherIcon
            }
            cell.icon.contentTintColor = .drTextTertiary
            var name = it.name
            if let n = it.node, isInBasket(n) { name = "● " + name }
            // Plain strings only: an attributed string without a paragraph style resets the
            // field to word-wrapping, which is what made long search rows spill over (P1).
            cell.name.stringValue = name
            cell.name.lineBreakMode = OutlineColumns.truncation(forName: it.name) == .middle ? .byTruncatingMiddle : .byTruncatingTail
            cell.path.stringValue = it.subtitle ?? ""
            cell.isTwoLine = it.subtitle != nil
            cell.isMuted = it.isHiddenEntry
            cell.badge.stringValue = ""
            cell.badgeColor = .drTextSecondary
            if let n = it.node, it.isHiddenEntry {
                if n.sunburstIsRestricted {
                    cell.badge.stringValue = tr("badge.noAccess")
                    cell.toolTip = n.displayPath + "\n" + tr("outline.noAccessTip")
                } else {
                    cell.toolTip = n.displayPath
                }
            } else if let n = it.node {
                if isProtected(n) {
                    cell.badge.stringValue = "🔒 " + tr("badge.protected")
                    cell.badgeColor = .drTextSecondary
                    cell.isMuted = true
                } else if isHighRisk(n) {
                    cell.badge.stringValue = "⚠ " + tr("badge.highRisk")
                    cell.badgeColor = .drWarnText
                }
                cell.toolTip = n.displayPath + "\n" + n.sizeSummary + (extraToolTip(n).map { "\n" + $0 } ?? "")
            } else {
                cell.toolTip = nil
            }
            cell.backgroundStyle = cell.backgroundStyle
            return cell
        default:
            let cell = (outlineView.makeView(withIdentifier: .init(id + "Cell"), owner: nil) as? NSTableCellView) ?? {
                let c = NSTableCellView()
                c.identifier = .init(id + "Cell")
                let t = NSTextField.label("", size: id == "share" ? 11 : 13, color: id == "share" ? .drTextSecondary : .labelColor)
                t.font = .drNumber(id == "share" ? 11 : 13)
                t.alignment = .right
                c.addSubview(t); c.textField = t
                NSLayoutConstraint.activate([t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                                             t.leadingAnchor.constraint(greaterThanOrEqualTo: c.leadingAnchor),
                                             t.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
                return c }()
            if id == "size" {
                cell.textField?.stringValue = SizeText.format(UInt64(max(0, it.size)))
            } else {
                let share = it.size / focusSize * 100
                cell.textField?.stringValue = share >= 10 ? String(format: "%.0f%%", share) : String(format: "%.1f%%", share)
            }
            return cell
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        CGFloat(ResultRowLayout.rowHeight(isSearchHit: (item as? OutlineItem)?.isSearchHit ?? false))
    }

    func outlineViewSelectionDidChange(_ notification: Notification) { onSelectionChanged?() }
}
#endif
