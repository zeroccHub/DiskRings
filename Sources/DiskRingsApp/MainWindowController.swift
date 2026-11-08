#if canImport(AppKit)
import AppKit
import Quartz
#if !SINGLE_MODULE  // SwiftPM: separate modules. build.sh compiles one module with -D SINGLE_MODULE.
import DiskScanCore
import SunburstGeometry
#endif

/// One mounted volume as shown on the home cards.
struct VolumeRow {
    let url: URL
    let name: String
    let total: Int64?
    let available: Int64?
    let isRoot: Bool

    var capacityText: String {
        guard let total = total else { return "" }
        let free = available.map { SizeText.format(UInt64(max(0, $0))) } ?? "?"
        return tr("volume.capacity", free, SizeText.format(UInt64(max(0, total))))
    }
}

/// Main window — simplify-v2 variant 1 「访达式」: unified toolbar (‹ › · path ·
/// rescan · reveal · search) | sunburst on windowBackground + outline (436) |
/// delete zone (56) | status bar (24). Built in code, no nibs. Delete core unchanged.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    // Model
    private var scanRoot: FileNode?
    private var current: FileNode? { didSet { if current !== oldValue { currentChanged() } } }
    private var history: [FileNode] = []
    private var forwardStack: [FileNode] = []
    private let deletionList = DeletionList(deletionGuard: DeletionGuard.live())
    private var scanTask: Task<Void, Never>?
    /// Background TreeAnalysis (high-risk flags + hidden counts); nil until ready.
    private var analysis: TreeAnalysis?
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration = 0
    /// Incremented per scan so a superseded scan task can't touch newer UI state.
    private var scanGeneration = 0
    /// Bumped whenever the tree changes (deletion) — part of the chart cache key.
    private var treeGeneration = 0
    private var chartKey: (ObjectIdentifier, Int, Bool, Int)?
    private var lastScannedURL: URL?
    private var scanDate: Date?
    private let privileged: PrivilegedDeleting = UnimplementedPrivilegedDeleter()
    private var volumes: [VolumeRow] = []
    private var volumeTimer: Timer?
    /// Guard verdicts per node (`.some(nil)` = deletable). Cleared on every scan / deletion.
    private var protectionCache: [ObjectIdentifier: DeletionGuard.Reason?] = [:]
    /// Items shown by Quick Look (outline selection or the last clicked sector).
    private var previewNodes: [FileNode] = []
    private var deletionSheet: DeletionProgressSheet?
    private var deleteConfirmSheet: DeleteConfirmSheet?
    private let undoToast = UndoToastController()
    private var lastTrashUndoLog: TrashUndoLog?
    /// Scan/delete state; drives menu validation, buttons and quit handling.
    let activity = AppActivity()
    /// 「搜索文件和文件夹」 whole-tree search (pure parts: Sources/SunburstGeometry/TreeSearch.swift).
    private var search = SearchState<FileNode>()
    private var searchWork: DispatchWorkItem?
    private var searchToken: TreeSearch.Token?
    private var lastSearch: TreeSearch.Result?
    /// Background tree readers (search, TreeAnalysis) vs. deletion's in-place tree edits:
    /// deletion cancels + awaits every reader before mutating; readers re-run afterwards.
    private let treeGate = TreeAccessGate()
    /// Magnifier-menu choices (正则表达式 toggle, match relative path) — per session only:
    /// every launch starts in Contains (regex is opt-in; no UserDefaults).
    private var searchSettings = TreeSearch.Settings.launch
    /// Invalid regex message (red field border + list notice), nil when fine.
    private var searchError: String?
    /// The last search was aborted by the regex time guard.
    private var searchTimedOut = false
    private var escMonitor: Any?
    private var homeDirectory: String { NSHomeDirectory() }
    /// Volume facts read once per scan (status-bar capacity line).
    private var scanVolumeName: String?
    private var scanVolumeTotal: Int64?
    private var scanVolumeAvailable: Int64?

    // Views
    private let homePage = HomePageView()
    private let resultsPage = NSView()
    private let split = NSSplitView()
    private weak var listPane: NSView?
    private var didApplyInitialSplit = false
    private let sunburst = SunburstView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    private let outline = ResultsOutline()
    private let hiddenLabel = NSTextField.label("", size: 11, color: .drTextSecondary)
    /// 「显示」/「隐藏」 link after the hidden-items count (P2-10); per window, not persisted.
    private let showHiddenLink = NSButton(title: tr("outline.show"), target: nil, action: nil)
    /// 「此文件夹中没有名称包含“xx”的项目」 (P2-9).
    private let noResultsLabel = NSTextField.label("", size: 13, color: .drTextSecondary)
    /// Why an item could not be added (row tooltip; P2-5 retention).
    private var refusedReasons: [ObjectIdentifier: String] = [:]
    private let addButton = NSButton(title: tr("button.addToBasket"), target: nil, action: nil)
    private let deleteBar = DeleteBarView()
    private let capacityBar = CapacityBarView()
    private var rescanItem: NSToolbarItem?
    /// Root-level chart model cache for the capacity bar (scan root + tree generation + metric + analysis).
    private var rootChartKey: (ObjectIdentifier, Int, Bool, Int)?
    private var rootChartModel: ChartModel<FileNode>?
    private var scanNotes = ""
    private let pathControl = NSPathControl()
    private var pathNodes: [FileNode] = []
    private let navControl = NSSegmentedControl()
    private let searchItem = NSSearchToolbarItem(itemIdentifier: .init("search"))

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = tr("window.title")
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: SplitLayout.windowMinWidth, height: SplitLayout.windowMinHeight)
        // v4: frames saved by builds that showed the collapsed list are ignored.
        window.setFrameAutosaveName(SplitLayout.windowAutosaveName)
        window.center()
        self.init(window: window)
        window.delegate = self
        buildToolbar(window)
        installEscMonitor()
        buildUI(in: window)
        observeAppearanceChanges()
        currentChanged()
        refreshVolumes(nil)
        startVolumeMonitoring()
        showHome()
    }

    private func observeAppearanceChanges() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceDidChange(_:)),
            name: AppDelegate.appearanceDidChangeNotification, object: nil)
    }

    @objc private func appearanceDidChange(_ note: Notification) {
        homePage.refreshAppearance()
    }

    // MARK: UI construction

    private func buildUI(in window: NSWindow) {
        let content = NSView()
        window.contentView = content
        homePage.onSelectVolume = { [weak self] v in self?.selectVolume(v) }
        homePage.onScanFolder = { [weak self] in self?.openFolder(nil) }
        homePage.onOpenFDA = { [weak self] in self?.openFullDiskAccessSettings(nil) }
        resultsPage.translatesAutoresizingMaskIntoConstraints = false

        // Chart (left, ≥520) | outline (436, 360–480)
        sunburst.delegate = self
        split.isVertical = true
        split.dividerStyle = .thin
        // No NSSplitViewDelegate on purpose: implementing shouldAdjustSizeOfSubview (as the
        // previous build did) switches NSSplitView to its legacy frame-based resizing, which
        // ignores the arranged subviews' width constraints — the likely cause of the list
        // staying at its initial width 0. Without a delegate panes can't collapse either.
        split.autosaveName = nil
        split.translatesAutoresizingMaskIntoConstraints = false
        let right = NSView()
        right.wantsLayer = true
        let scroll = NSScrollView()
        scroll.documentView = outline.view
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false      // name column absorbs width; nothing scrolls sideways
        scroll.autohidesScrollers = true
        scroll.contentView.autoresizesSubviews = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        outline.isHighRisk = { [weak self] n in self?.analysis?.isHighRisk(n) ?? false }
        outline.isProtected = { [weak self] n in self?.displayProtection(n) != ProtectionKind.none }
        outline.isInBasket = { [weak self] n in self?.deletionList.contains(n) ?? false }
        outline.onSelectionChanged = { [weak self] in self?.outlineSelectionChanged() }
        outline.onDoubleClick = { [weak self] it in
            if let n = it.node, n.isDirectory, !n.children.isEmpty { self?.navigate(to: n) }
        }
        outline.view.onHoverRow = { [weak self] r in
            guard let self else { return }
            self.sunburst.setHover(self.outline.hoveredItem(row: r)?.sector)
        }
        outline.view.onSpace = { [weak self] in self?.collectSelected(nil) }
        outline.view.menu = outlineMenu()
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .rounded
        addButton.target = self; addButton.action = #selector(collectSelected(_:))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        let footerLine = TintedView(color: .drSeparator)
        showHiddenLink.isBordered = false
        showHiddenLink.target = self
        showHiddenLink.action = #selector(toggleShowHidden(_:))
        showHiddenLink.translatesAutoresizingMaskIntoConstraints = false
        showHiddenLink.isHidden = true
        setLinkTitle(tr("outline.show"))
        noResultsLabel.alignment = .center
        noResultsLabel.lineBreakMode = .byWordWrapping
        noResultsLabel.maximumNumberOfLines = 3
        noResultsLabel.isHidden = true
        right.addSubview(noResultsLabel)
        outline.extraToolTip = { [weak self] n in self?.refusedReasons[ObjectIdentifier(n)] }
        for v in [footerLine, hiddenLabel, showHiddenLink, addButton] as [NSView] { footer.addSubview(v) }
        hiddenLabel.lineBreakMode = .byTruncatingTail
        hiddenLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        right.addSubview(scroll); right.addSubview(footer)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: right.topAnchor), scroll.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: right.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: right.leadingAnchor), footer.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: right.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 40),
            footerLine.topAnchor.constraint(equalTo: footer.topAnchor), footerLine.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: footer.trailingAnchor), footerLine.heightAnchor.constraint(equalToConstant: 1),
            hiddenLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            hiddenLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            showHiddenLink.leadingAnchor.constraint(equalTo: hiddenLabel.trailingAnchor, constant: 6),
            showHiddenLink.firstBaselineAnchor.constraint(equalTo: hiddenLabel.firstBaselineAnchor),
            showHiddenLink.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -8),
            noResultsLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            noResultsLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            noResultsLabel.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -48),
            addButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            addButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        // Give both panes a non-zero starting frame (NSSplitView starts from the subviews' frames).
        sunburst.setFrameSize(NSSize(width: CGFloat(SplitLayout.chartMin), height: 400))
        right.setFrameSize(NSSize(width: CGFloat(SplitLayout.listPreferred), height: 400))
        split.addArrangedSubview(sunburst)
        split.addArrangedSubview(right)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        right.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(SplitLayout.listMin)).isActive = true
        right.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(SplitLayout.listMax)).isActive = true
        let pref = right.widthAnchor.constraint(equalToConstant: CGFloat(SplitLayout.listPreferred))
        pref.priority = .defaultLow + 10
        pref.isActive = true
        sunburst.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(SplitLayout.chartMin)).isActive = true
        listPane = right

        deleteBar.onRemove = { [weak self] p in self?.removeFromBasket(path: p) }
        deleteBar.onTrash = { [weak self] in self?.trashCollected(nil) }
        deleteBar.onPermanent = { [weak self] in self?.deleteCollectedPermanently(nil) }
        deleteBar.onEvaluateDrop = { [weak self] paths in self?.evaluateBasketDrop(paths: paths) ?? .init(paths: paths, accepted: [], refused: paths) }
        deleteBar.onAcceptDrop = { [weak self] paths in self?.acceptBasketDrop(paths: paths) ?? false }
        capacityBar.stopButton.target = self
        capacityBar.stopButton.action = #selector(cancelScan(_:))
        capacityBar.onNavigate = { [weak self] n in self?.navigate(to: n) }

        resultsPage.addSubview(capacityBar)
        resultsPage.addSubview(split)
        resultsPage.addSubview(deleteBar)
        for v in [homePage, resultsPage] as [NSView] { content.addSubview(v) }
        let guide = content.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            homePage.topAnchor.constraint(equalTo: guide.topAnchor), homePage.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            homePage.trailingAnchor.constraint(equalTo: content.trailingAnchor), homePage.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            resultsPage.topAnchor.constraint(equalTo: guide.topAnchor), resultsPage.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            resultsPage.trailingAnchor.constraint(equalTo: content.trailingAnchor), resultsPage.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            capacityBar.topAnchor.constraint(equalTo: resultsPage.topAnchor), capacityBar.leadingAnchor.constraint(equalTo: resultsPage.leadingAnchor),
            capacityBar.trailingAnchor.constraint(equalTo: resultsPage.trailingAnchor),
            split.topAnchor.constraint(equalTo: capacityBar.bottomAnchor), split.leadingAnchor.constraint(equalTo: resultsPage.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: resultsPage.trailingAnchor), split.bottomAnchor.constraint(equalTo: deleteBar.topAnchor),
            deleteBar.leadingAnchor.constraint(equalTo: resultsPage.leadingAnchor), deleteBar.trailingAnchor.constraint(equalTo: resultsPage.trailingAnchor),
            deleteBar.bottomAnchor.constraint(equalTo: resultsPage.bottomAnchor),
        ])
    }

    private func outlineMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        for (key, sel) in [("button.addToBasket", #selector(collectSelected(_:))), ("menu.reveal", #selector(revealSelected(_:))),
                           ("menu.quickLook", #selector(toggleQuickLook(_:)))] {
            m.addItem(withTitle: tr(key), action: sel, keyEquivalent: "").target = self
        }
        return m
    }

    // MARK: Pages

    @objc func goHome(_ sender: Any?) {
        guard activity.isAllowed(.scan) || scanRoot != nil else { NSSound.beep(); return }
        // Returning home cancels an in-flight scan but never a deletion.
        if activity.isAllowed(.stopScan) { scanTask?.cancel() }
        showHome()
    }

    private func showHome() {
        homePage.isHidden = false
        resultsPage.isHidden = true
        homePage.reload(volumes: volumes)
        window?.title = tr("window.title")
        updateToolbar()
    }

    private func showResults() {
        homePage.isHidden = true
        resultsPage.isHidden = false
        updateCompactMode()
        updateToolbar()
        // After this run-loop turn the results page has a real size: apply the spec split
        // once, then log (and in DEBUG assert) the measured pane frames.
        DispatchQueue.main.async { [weak self] in self?.applyInitialSplitAndLog(); self?.verifySearchWiring() }
    }

    private func applyInitialSplitAndLog() {
        guard let window, let list = listPane else { return }
        resultsPage.layoutSubtreeIfNeeded()
        let total = Double(split.bounds.width)
        if !didApplyInitialSplit, total > 0 {
            didApplyInitialSplit = true
            let w = SplitLayout.initialListWidth(total: total)
            split.setPosition(CGFloat(SplitLayout.dividerPosition(total: total, listWidth: w)), ofDividerAt: 0)
            resultsPage.layoutSubtreeIfNeeded()
        }
        let collapsed = split.isSubviewCollapsed(list) || list.isHidden
        let msg = String(format: "layout window=%.0fx%.0f split=%.0f chart=%@ list=%@ collapsed=%@ hit(12,12)=%@",
                         window.frame.width, window.frame.height, split.bounds.width,
                         NSStringFromRect(sunburst.frame), NSStringFromRect(list.frame),
                         collapsed ? "yes" : "no", Self.viewClass(at: NSPoint(x: 12, y: 12), in: window))
        LayoutLog.write(msg, problem: SplitLayout.isListTooNarrow(listWidth: Double(list.frame.width), collapsed: collapsed))
        #if DEBUG
        assert(!SplitLayout.isListTooNarrow(listWidth: Double(list.frame.width), collapsed: collapsed),
               "list pane narrower than \(SplitLayout.listMin): \(msg)")
        #endif
    }

    /// Class chain of the view under a window point (bottom-left by default) — identifies
    /// stray controls such as the reported '«' without a screenshot.
    private static func viewClass(at p: NSPoint, in window: NSWindow) -> String {
        guard let root = window.contentView?.superview ?? window.contentView,
              var v = root.hitTest(p) else { return "none" }
        var chain = [String(describing: type(of: v))]
        while let s = v.superview, chain.count < 6 { chain.append(String(describing: type(of: s))); v = s }
        return chain.joined(separator: "<")
    }

    private func selectVolume(_ row: VolumeRow) {
        guard activity.isAllowed(.scan) else { NSSound.beep(); return }
        let match = volumes.first(where: { $0.url.path == row.url.path }) ?? row
        let target = VolumeScanTarget.path(forVolumeAt: match.url.path, isRootFileSystem: match.isRoot)
        startScan(URL(fileURLWithPath: target))
    }

    /// Search field action (Return, the ⓧ clear button) — and typing via `controlTextDidChange`.
    /// Both go through the 200 ms debounce; an emptied field applies at once.
    @objc private func searchChanged(_ sender: Any?) {
        scheduleSearch(searchItem.searchField.stringValue, source: "action")
    }

    private func scheduleSearch(_ text: String, source: String) {
        searchWork?.cancel()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { applySearchText(text, source: source); return }
        let work = DispatchWorkItem { [weak self] in self?.applySearchText(text, source: source) }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TreeSearch.debounce, execute: work)
    }

    /// Starts (cancelling any running search) or clears the whole-tree search.
    private func applySearchText(_ text: String, source: String) {
        switch search.typed(text, current: current) {
        case .none:
            return
        case .clear:
            searchToken?.cancel(); searchToken = nil; lastSearch = nil
            setSearchError(nil); searchTimedOut = false
            FilterLog.write("event=clear source=\(source)")
            reloadOutline()
        case let .start(gen, q):
            searchToken?.cancel()
            guard let root = scanRoot else { FilterLog.write("event=start source=\(source) skipped=noTree"); return }
            FilterLog.write("event=start source=\(source) gen=\(gen) queryLen=\(q.count)")
            runSearch(gen: gen, text: q, root: root)
        }
    }

    /// Parses (/pattern/ forces regex) + compiles once, then starts the job; an invalid regex
    /// shows the error (red border + list notice) and runs nothing.
    private func runSearch(gen: Int, text: String, root: FileNode) {
        lastSearch = nil
        searchTimedOut = false
        let q = TreeSearch.Query.parse(text, mode: searchSettings.mode, scope: searchSettings.scope)
        switch TreeSearch.compile(q) {
        case .failure(let e):
            searchToken?.cancel(); searchToken = nil
            if case let .invalidRegex(msg) = e { setSearchError(msg) } else { setSearchError(nil) }
            FilterLog.write("event=invalidPattern gen=\(gen) mode=\(q.mode.rawValue)")
            outline.reload(model: nil, focus: nil)
            updateListFooter()
        case .success(let compiled):
            setSearchError(nil)
            // Leave the tree view at once: an empty result list + visible "searching…" message,
            // so a slow (regex) run can never look like "nothing happened".
            outline.showSearching()
            updateListFooter()
            FilterLog.write("event=compiled gen=\(gen) mode=\(q.mode.rawValue) fast=\(compiled.usesLiteralMatcher)")
            startSearchJob(gen: gen, compiled: compiled, root: root)
        }
    }

    /// Regex state indicator WITHOUT any subview in the NSSearchField (the old ".*" label
    /// subview could be left drawn by the toolbar field): placeholder gets「（正则）」, the
    /// field tooltip names the mode, and the list footer is prefixed「正则 ·」. All from the
    /// pure `SearchFieldConfig`.
    private func updateRegexBadge() {
        let c = SearchFieldConfig.make(text: searchItem.searchField.stringValue, settings: searchSettings)
        searchItem.searchField.placeholderString = Self.searchFieldText(c.placeholderKey)
        if searchError == nil { searchItem.searchField.toolTip = Self.searchFieldText(c.toolTipKey) }
        FilterLog.write("event=regexIndicator active=\(c.regexActive) mode=\(searchSettings.mode.rawValue)")
    }

    /// SearchFieldConfig key → localized text (literal tr() calls, so the l10n key check sees them).
    static func searchFieldText(_ key: String) -> String {
        switch key {
        case "search.placeholder.regex": return tr("search.placeholder.regex")
        case "search.tip.contains": return tr("search.tip.contains")
        case "search.tip.regex": return tr("search.tip.regex")
        case "search.footer.regexPrefix": return tr("search.footer.regexPrefix")
        default: return tr("search.placeholder")
        }
    }

    private func setSearchError(_ msg: String?) {
        searchError = msg
        let f = searchItem.searchField
        f.wantsLayer = true
        f.layer?.borderColor = msg == nil ? nil : NSColor.systemRed.cgColor
        f.layer?.borderWidth = msg == nil ? 0 : 1.5
        f.layer?.cornerRadius = 6
        f.toolTip = msg.map { tr("search.invalidRegex", $0) }
            ?? Self.searchFieldText(SearchFieldConfig.make(text: f.stringValue, settings: searchSettings).toolTipKey)
    }

    // MARK: Search menu (magnifier)

    private func searchMenu() -> NSMenu {
        // Default (unchecked) = 包含 / Contains; the checkable item opts into regex for this session.
        let m = NSMenu(title: tr("search.menu.title"))
        let regex = NSMenuItem(title: tr("search.mode.regex"), action: #selector(toggleSearchRegex(_:)), keyEquivalent: "")
        let path = NSMenuItem(title: tr("search.scope.path"), action: #selector(toggleSearchScope(_:)), keyEquivalent: "")
        regex.state = searchSettings.regexEnabled ? .on : .off
        path.state = searchSettings.scope == .path ? .on : .off
        for i in [regex, path] { i.target = self }
        m.addItem(regex); m.addItem(.separator()); m.addItem(path)
        return m
    }
    @objc private func toggleSearchRegex(_ sender: Any?) { updateSearchSettings { $0.mode = $0.regexEnabled ? .contains : .regex } }
    @objc private func toggleSearchScope(_ sender: Any?) { updateSearchSettings { $0.scope = $0.scope == .name ? .path : .name } }
    private func updateSearchSettings(_ change: (inout TreeSearch.Settings) -> Void) {
        change(&searchSettings)
        updateRegexBadge()
        searchItem.searchField.searchMenuTemplate = searchMenu()   // template is copied: rebuild for the checkmarks
        FilterLog.write("event=settings mode=\(searchSettings.mode.rawValue) scope=\(searchSettings.scope.rawValue)")
        if case let .start(gen, q) = search.refresh(), let root = scanRoot { runSearch(gen: gen, text: q, root: root) }
    }

    /// Runs one search on a background queue under a TreeAccessGate ticket. While a deletion
    /// is mutating the tree no ticket is granted; `afterDeletion` re-runs the query.
    private func startSearchJob(gen: Int, compiled: TreeSearch.Compiled, root: FileNode) {
        let token = TreeSearch.Token()
        searchToken = token
        guard let ticket = treeGate.beginRead(cancel: { token.cancel() }) else {
            FilterLog.write("event=deferred gen=\(gen) reason=treeMutation")
            return
        }
        let gate = treeGate
        let t0 = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = TreeSearch.run(root: root, compiled: compiled, token: token)
            gate.endRead(ticket)                       // done touching the tree
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            DispatchQueue.main.async { [weak self] in self?.searchFinished(r, gen: gen, root: root, ms: ms) }
        }
    }

    private func searchFinished(_ r: TreeSearch.Result, gen: Int, root: FileNode, ms: Double) {
        guard !r.cancelled, search.accepts(generation: gen), root === scanRoot else {
            FilterLog.write("event=discard gen=\(gen) cancelled=\(r.cancelled) visited=\(r.visited)")
            return
        }
        lastSearch = r
        searchTimedOut = r.timedOut
        if r.timedOut { capacityBar.showNotice(tr("search.timeout", Int(TreeSearch.regexTimeout))) }
        outline.showSearch(r, root: root)
        updateListFooter()
        let listW = Int(outline.view.enclosingScrollView?.frame.width ?? -1)
        FilterLog.write(String(format: "event=done gen=%d total=%d shown=%d visited=%d ms=%.1f listWidth=%d",
                               gen, r.total, r.hits.count, r.visited, ms, listW),
                        problem: listW < Int(SplitLayout.listMin))
    }

    /// After a deletion the tree changed: re-run the active query (hits may be gone).
    private func rerunSearchAfterTreeChange() {
        guard case let .start(gen, q) = search.refresh(), let root = scanRoot else { return }
        searchToken?.cancel()
        FilterLog.write("event=refresh gen=\(gen)")
        runSearch(gen: gen, text: q, root: root)
    }

    /// Esc (restore the view the search started from) or a new scan (no restore).
    private func clearSearch(escape: Bool, source: String) {
        searchWork?.cancel(); searchWork = nil
        searchToken?.cancel(); searchToken = nil
        if !searchItem.searchField.stringValue.isEmpty { searchItem.searchField.stringValue = "" }
        setSearchError(nil); searchTimedOut = false
        updateRegexBadge()
        let wasActive = search.isActive
        var restore: FileNode?
        if escape { restore = search.escape() } else { search.rescan() }
        lastSearch = nil
        guard wasActive else { return }
        FilterLog.write("event=\(escape ? "escape" : "rescan") source=\(source) restore=\(restore != nil)")
        if let r = restore, r !== current, scanRoot != nil {
            navigate(to: r)
            currentChanged()
        } else {
            reloadOutline()
        }
    }

    /// Clicking a search result: drill the chart to the hit's parent and select it there.
    private func locateSearchHit(_ node: FileNode) {
        guard let root = scanRoot else { return }
        let (focus, sel) = TreeSearch.locate(node, root: root)
        if focus !== current { navigate(to: focus); currentChanged() }
        let idx = sunburst.model?.sectors.firstIndex { $0.node === sel }
        sunburst.setSelected(idx)
        FilterLog.write("event=locate depth=\(TreeSearch.relativeParentPath(node, root: root).split(separator: "/").count) sector=\(idx != nil)")
    }

    /// Debug + log check that the search field installed in the toolbar is the instance we wired.
    private func verifySearchWiring() {
        let installed = window?.toolbar?.items.first { $0.itemIdentifier == searchItem.itemIdentifier } as? NSSearchToolbarItem
        let sameItem = installed === searchItem
        let field = installed?.searchField
        let ok = sameItem && field?.delegate === self && field?.target === self && field?.action != nil
        FilterLog.write("wiring installed=\(installed != nil) sameItem=\(sameItem) delegate=\(field?.delegate === self) " +
                        "target=\(field?.target === self) action=\(field?.action != nil)", problem: !ok)
        assert(installed == nil || ok, "toolbar search field is not wired")
    }

    private func removeFromBasket(path: String) {
        guard activity.isAllowed(.editDeletionList) else { NSSound.beep(); return }
        if let n = deletionList.items.first(where: { $0.path == path }) {
            deletionList.remove(n)
            reloadDeletionList()
            outline.refreshVisibleRows()
        }
    }

    // MARK: Volumes

    private static let volumeKeys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsRootFileSystemKey,
    ]

    private func startVolumeMonitoring() {
        volumeTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(refreshVolumes(_:)),
                                           userInfo: nil, repeats: true)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(self, selector: #selector(refreshVolumes(_:)), name: name, object: nil)
        }
    }

    @objc func refreshVolumes(_ sender: Any?) {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.volumeKeys,
                                                          options: [.skipHiddenVolumes]) ?? []
        volumes = urls.map { original in
            var url = original
            url.removeAllCachedResourceValues()   // capacity must be fresh on every refresh
            let v = try? url.resourceValues(forKeys: Set(Self.volumeKeys))
            let available: Int64?
            if let important = v?.volumeAvailableCapacityForImportantUsage, important > 0 {
                available = important
            } else {
                available = v?.volumeAvailableCapacity.map { Int64($0) }
            }
            return VolumeRow(url: url,
                             name: v?.volumeLocalizedName ?? v?.volumeName ?? url.lastPathComponent,
                             total: v?.volumeTotalCapacity.map { Int64($0) },
                             available: available,
                             isRoot: v?.volumeIsRootFileSystem ?? (url.path == "/"))
        }
        if !homePage.isHidden { homePage.reload(volumes: volumes) }
    }

    // MARK: Scanning

    @objc func openFolder(_ sender: Any?) {
        guard activity.isAllowed(.scan) else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = tr("panel.prompt")
        panel.message = tr("panel.message")
        guard let window = window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, self?.activity.isAllowed(.scan) == true else { return }
            self?.startScan(url)
        }
    }

    @objc func rescan(_ sender: Any?) {
        guard activity.isAllowed(.rescan) else { NSSound.beep(); return }
        if let url = lastScannedURL { startScan(url) } else { openFolder(sender) }
    }

    @objc func cancelScan(_ sender: Any?) {
        scanTask?.cancel()        // also cancels the post-scan pass (task cancellation handler)
        analysisTask?.cancel()
    }

    private func startScan(_ url: URL) {
        // Single choke point for every scan request (menu, toolbar, home cards).
        guard activity.isAllowed(.scan) else { NSSound.beep(); return }
        scanTask?.cancel()
        lastScannedURL = url
        deletionList.removeAll()
        protectionCache.removeAll()
        refusedReasons.removeAll()
        previewNodes = []
        history = []; forwardStack = []
        clearSearch(escape: false, source: "scan")
        scanRoot = nil
        current = nil
        chartKey = nil
        rootChartKey = nil; rootChartModel = nil; scanNotes = ""
        // Volume facts for the status line, read once per scan.
        let v = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                                  .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        scanVolumeName = v?.volumeLocalizedName
        scanVolumeTotal = v?.volumeTotalCapacity.map { Int64($0) }
        scanVolumeAvailable = (v?.volumeAvailableCapacityForImportantUsage).flatMap { $0 > 0 ? $0 : nil }
            ?? v?.volumeAvailableCapacity.map { Int64($0) }
        reloadDeletionList()
        showResults()
        setScanning(true)
        sunburst.setEmpty(tr("chart.scanning"))
        outline.reload(model: nil, focus: nil)
        hiddenLabel.stringValue = ""
        setStatus(tr("status.starting"))
        let engine = ScanEngine()
        let path = url.path
        scanGeneration += 1
        let generation = scanGeneration
        analysisTask?.cancel()
        analysis = nil
        let home = homeDirectory
        // ≤10 Hz from the engine, plus coalescing: at most one pending main-thread hop,
        // and the hop only formats one status string (O(1) per tick).
        let coalescer = ProgressCoalescer<ScanProgress>()
        scanTask = Task { [weak self] in
            do {
                let result = try await engine.scan(path: path) { [weak self] p in
                    guard coalescer.offer(p) else { return }
                    Task { @MainActor [weak self] in
                        guard let self = self, self.scanGeneration == generation, let p = coalescer.take() else { return }
                        self.showProgress(p)
                    }
                }
                guard let self = self, self.scanGeneration == generation else { return }
                // Finishing: heavy post-processing runs off the main thread; Stop stays live.
                self.setStatus(tr("status.finishing", result.progress.filesSeen))
                let analysis = await Self.buildAnalysis(root: result.root, homeDirectory: home, gate: self.treeGate)
                guard self.scanGeneration == generation else { return }
                self.analysis = analysis           // nil if Stop was pressed while finishing
                self.finishScan(result, analysisCancelled: analysis == nil)
                self.scanTask = nil
            } catch {
                guard let self = self, self.scanGeneration == generation else { return }
                self.scanTask = nil
                self.setScanning(false)
                if case ScanError.cancelled = error {
                    self.setStatus(tr("status.scanStopped"))
                    self.sunburst.setEmpty(tr("status.scanStopped"))
                } else {
                    self.setStatus(tr("status.scanFailed"))
                    self.sunburst.setEmpty(tr("status.scanFailed"))
                    self.showErrorAlert(message: tr("alert.scanFailed.title", DisplayPath.forUser(path)), detail: tr("alert.scanFailed.detail", "\(error)"))
                }
            }
        }
    }

    /// Runs TreeAnalysis on a background thread; cancelling the calling task makes
    /// it return nil within ~4096 nodes. Holds a TreeAccessGate ticket while it reads the tree
    /// (nil without reading when a deletion is mutating it; refreshAnalysis re-runs afterwards).
    nonisolated private static func buildAnalysis(root: FileNode, homeDirectory: String, gate: TreeAccessGate) async -> TreeAnalysis? {
        let token = ScanCancellation()
        guard let ticket = gate.beginRead(cancel: { token.cancel() }) else { return nil }
        defer { gate.endRead(ticket) }    // after the thread resumed us, i.e. finished reading
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<TreeAnalysis?, Never>) in
                let th = Thread {
                    // Protection display flags: mounts + canonical home read once, here, off the main thread.
                    let g = ProtectionMap.snapshotGuard(homeDirectory: homeDirectory)
                    cont.resume(returning: TreeAnalysis.build(root: root, homeDirectory: homeDirectory, protectionGuard: g,
                                                              isCancelled: { token.isCancelled }))
                }
                th.name = "DiskRings.analysis"
                th.stackSize = 1 << 20
                th.start()
            }
        } onCancel: { token.cancel() }
    }

    /// Rebuild the analysis after deletions, in the background.
    private func refreshAnalysis() {
        guard let root = scanRoot else { return }
        analysisTask?.cancel()
        analysisGeneration += 1
        let gen = analysisGeneration
        let home = homeDirectory
        let gate = treeGate
        analysisTask = Task { [weak self] in
            let a = await Self.buildAnalysis(root: root, homeDirectory: home, gate: gate)
            guard let self, gen == self.analysisGeneration, let a, self.scanRoot === root else { return }
            self.analysis = a
            self.rebuildChart(force: true)
        }
    }

    private func setScanning(_ scanning: Bool) {
        if scanning { activity.beginScan() } else { activity.endScan() }
        capacityBar.setScanning(scanning)
        updateButtons()
        updateToolbar()
    }

    private func showProgress(_ p: ScanProgress) {
        guard !p.isFinished, !capacityBar.stopButton.isHidden else { return }
        capacityBar.setProgress(tr("status.scanProgress", p.filesSeen, SizeText.format(p.allocatedBytesSeen), p.lastPath))
    }

    private func finishScan(_ result: ScanResult, analysisCancelled: Bool = false) {
        setScanning(false)
        scanDate = Date()
        scanRoot = result.root
        current = result.root
        var extra = ""
        if !result.restrictedPaths.isEmpty { extra += tr("status.unreadable", result.restrictedPaths.count) }
        if result.hardLinkDuplicates > 0 { extra += tr("status.hardLinks", result.hardLinkDuplicates) }
        if result.cloneDuplicates > 0 { extra += tr("status.clones", result.cloneDuplicates, SizeText.format(result.cloneSharedBytes)) }
        if analysisCancelled { extra += tr("status.analysisSkipped") }
        scanNotes = extra.hasPrefix(" · ") ? String(extra.dropFirst(3)) : extra
        capacityBar.setVolumeTitle(scanVolumeName ?? result.root.sunburstName)
        updateRescanTip()
        if !scanNotes.isEmpty { capacityBar.showNotice(scanNotes) }
    }

    /// The bottom status bar is gone (capacity-bar spec): the scan time (and scan
    /// notes) live in the 「重新扫描」 tooltip.
    private func updateRescanTip() {
        var tip = tr("toolbar.rescan")
        if let d = scanDate {
            let f = DateFormatter()
            f.dateStyle = .short; f.timeStyle = .short; f.doesRelativeDateFormatting = true
            tip = tr("toolbar.rescan.lastScan", f.string(from: d))
        }
        if !scanNotes.isEmpty { tip += "\n" + scanNotes }
        rescanItem?.toolTip = tip
    }

    /// Transient status: progress while scanning, otherwise a notice in the capacity bar.
    private func setStatus(_ s: String) {
        if activity.isAllowed(.stopScan) { capacityBar.setProgress(s) } else { capacityBar.showNotice(s) }
    }

    /// Display name for the capacity bar: the two Libraries become ~/Library and /Library.
    private func capacityName(_ s: ChartModel<FileNode>.Sector) -> String {
        guard let n = s.node else { return s.name }
        if n.path == homeDirectory + "/Library" { return "~/Library" }
        if n.name == "Library", n.parent === scanRoot { return "/Library" }
        return s.name
    }

    /// Capacity bar: root-level model from the cache (rebuilt only when the scan root,
    /// tree generation, metric or analysis changes); drilling only updates the scope.
    private func refreshCapacityBar(focusModel: ChartModel<FileNode>, key: (ObjectIdentifier, Int, Bool, Int)) {
        guard let root = scanRoot, let focus = current else { capacityBar.setModel(nil); return }
        let rkey = (ObjectIdentifier(root), key.1, key.2, key.3)
        if rootChartKey.map({ $0 != rkey }) ?? true {
            rootChartKey = rkey
            let rm = focus === root ? focusModel : makeChartModel(focus: root)
            rootChartModel = rm
            let total = scanVolumeTotal.map(Double.init), avail = scanVolumeAvailable.map(Double.init)
            capacityBar.setModel(CapacityBarModel(root: rm, volumeTotal: total, volumeAvailable: avail, name: { [unowned self] in self.capacityName($0) }))
        }
        guard let bar = capacityBar.model else { return }
        let isRoot = focus === root
        let scope = bar.scope(focus: focus, isRoot: isRoot, isAncestorOrSelf: { a, n in
            var c: FileNode? = n
            while let x = c { if x === a { return true }; c = x.parent }
            return false
        })
        var text: String?
        if !isRoot {
            let share = NumberFormatter.localizedString(from: NSNumber(value: focus.sunburstSize / max(bar.used, 1)), number: .percent)
            text = tr("capacity.current", focusDisplayName(focus), SizeText.format(UInt64(max(0, focus.sunburstSize))), share)
        }
        capacityBar.setScope(scope, currentText: text)
    }

    private func focusDisplayName(_ n: FileNode) -> String {
        if let s = rootChartModel?.sectors.first(where: { $0.node === n }) { return capacityName(s) }
        return n.sunburstName
    }

    /// Compact capacity bar when the window content is shorter than 720 pt.
    func windowDidResize(_ notification: Notification) {
        updateCompactMode()
    }
    private func updateCompactMode() {
        guard let h = window?.contentLayoutRect.height else { return }
        capacityBar.compact = h < 720
    }

    // MARK: Navigation

    private func navigate(to node: FileNode) {
        guard node !== current else { return }
        if let c = current { history.append(c) }
        forwardStack.removeAll()
        current = node
    }

    private func currentChanged() {
        rebuildChart(force: false)
        updateButtons()
        updateToolbar()
    }

    /// Chart rebuild: (focus, metric, tree generation, analysis-ready) is the cache
    /// key; window drags / resizes never come here (they only change the transform).
    private func rebuildChart(force: Bool) {
        guard let focus = current else {
            chartKey = nil
            if scanRoot == nil && !activity.isAllowed(.stopScan) { sunburst.setEmpty(tr("chart.empty")) }
            reloadOutline()
            return
        }
        let key = (ObjectIdentifier(focus), treeGeneration, SunburstSizing.metric == .logical, analysis == nil ? 0 : analysisGeneration + 1)
        if !force, let k = chartKey, k == key { return }
        chartKey = key
        let a = analysis
        let model = makeChartModel(focus: focus)
        refreshCapacityBar(focusModel: model, key: key)
        let items = NumberFormatter.localizedString(from: NSNumber(value: focus.itemCount), number: .decimal)
        sunburst.setModel(model, focusName: focus.sunburstName, focusSize: SizeText.format(UInt64(focus.sunburstSize)),
                          focusSub: tr("chart.itemCount", items))
        reloadOutline()
        _ = a
    }

    /// List footer: 「N 项匹配」 while filtering, else the hidden count + 「显示」/「隐藏」.
    private func updateListFooter() {
        if search.isActive {
            showHiddenLink.isHidden = true
            if let e = searchError {
                hiddenLabel.stringValue = tr("search.invalidRegex", e)
                noResultsLabel.stringValue = tr("search.invalidRegex", e); noResultsLabel.isHidden = false
                return
            }
            if searchTimedOut {
                hiddenLabel.stringValue = tr("search.timeout", Int(TreeSearch.regexTimeout))
                noResultsLabel.stringValue = tr("search.timeout", Int(TreeSearch.regexTimeout)); noResultsLabel.isHidden = false
                return
            }
            guard outline.isSearchMode, let n = outline.filterMatches else {
                hiddenLabel.stringValue = tr("search.searching")
                noResultsLabel.stringValue = tr("search.searching"); noResultsLabel.isHidden = false; return
            }
            let footer = n > outline.searchShown ? tr("search.top", outline.searchShown, n) : tr("filter.matches", n)
            let prefix = SearchFieldConfig.make(text: search.query, settings: searchSettings).footerPrefixKey
            hiddenLabel.stringValue = prefix.map { Self.searchFieldText($0) + footer } ?? footer
            noResultsLabel.stringValue = tr("search.noResults", search.query)
            noResultsLabel.isHidden = n > 0
            return
        }
        noResultsLabel.isHidden = true
        let hidden = current.map { analysis?.hiddenCount($0) ?? 0 } ?? 0
        hiddenLabel.stringValue = hidden > 0 ? tr("outline.hidden", NumberFormatter.localizedString(from: NSNumber(value: hidden), number: .decimal)) : ""
        showHiddenLink.isHidden = hidden == 0
        setLinkTitle(outline.showHidden ? tr("outline.hide") : tr("outline.show"))
    }

    private func setLinkTitle(_ t: String) {
        showHiddenLink.attributedTitle = NSAttributedString(string: t, attributes: [
            .foregroundColor: NSColor.drBrandText, .font: NSFont.systemFont(ofSize: 11)])
    }

    @objc private func toggleShowHidden(_ sender: Any?) {
        outline.showHidden.toggle()
        reloadOutline()
    }

    private func makeChartModel(focus: FileNode) -> ChartModel<FileNode> {
        let a = analysis
        return ChartModel(focus: focus, labelScale: Double(sunburst.scale),
                          isProtected: { n in a?.protectionKind(n) == .subtree },
                          isHighRisk: { n in a?.isHighRisk(n) ?? false },
                          sizeText: { SizeText.format(UInt64(max(0, $0))) },
                          otherName: { tr("chart.otherItems", $0) })
    }

    private func reloadOutline() {
        // While a search is active the list keeps its results (locating a hit drills the chart
        // without replacing the list); otherwise the focus's children.
        if search.isActive {
            if !outline.isSearchMode, let r = lastSearch, let root = scanRoot { outline.showSearch(r, root: root) }
        } else {
            outline.reload(model: sunburst.model, focus: current)
        }
        updateListFooter()
    }

    /// ⌘↓ (P2-11): enter the selected folder (list or chart selection; directories only).
    @objc func enterSelected(_ sender: Any?) {
        guard let n = drillTarget() else { NSSound.beep(); return }
        navigate(to: n)
    }
    private func drillTarget() -> FileNode? {
        let fromList = selectedNodes.count == 1 ? selectedNodes.first : nil
        let fromChart = sunburst.selectedIndex.flatMap { sunburst.model?.sectors[$0].node }
        guard let n = fromList ?? fromChart, n.isDirectory, n.children.contains(where: { $0.sunburstSize > 0 }), n !== current else { return nil }
        return n
    }

    @objc func goUp(_ sender: Any?) {
        if let p = current?.parent { navigate(to: p) }
    }

    @objc func goToRoot(_ sender: Any?) {
        if let r = scanRoot { navigate(to: r) }
    }

    @objc func goBack(_ sender: Any?) {
        if let prev = history.popLast() {
            if let c = current { forwardStack.append(c) }
            current = prev
        } else if !resultsPage.isHidden {
            goHome(sender)
        }
    }

    @objc func goForward(_ sender: Any?) {
        guard let next = forwardStack.popLast() else { return }
        if let c = current { history.append(c) }
        current = next
    }

    private var selectedNodes: [FileNode] { outline.selectedNodes }

    @objc func revealSelected(_ sender: Any?) {
        if outline.promoteClickedRowIntoSelectionIfNeeded() { outlineSelectionChanged() }
        let picked = outline.actionNodes
        let nodes = picked.isEmpty ? (current.map { [$0] } ?? []) : picked
        NSWorkspace.shared.activateFileViewerSelecting(nodes.map { URL(fileURLWithPath: $0.path) })
    }

    @objc func openFullDiskAccessSettings(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func toggleSunburstMetric(_ sender: Any?) {
        SunburstSizing.metric = SunburstSizing.metric == .logical ? .actual : .logical
        (sender as? NSMenuItem)?.state = SunburstSizing.metric == .logical ? .on : .off
        rebuildChart(force: true)
    }

    private func outlineSelectionChanged() {
        let items = outline.selectedItems
        if outline.isSearchMode {
            if items.count == 1, let n = items[0].node { locateSearchHit(n) }
            previewSelectionChanged(items.compactMap(\.node))
            updateButtons()
            return
        }
        sunburst.setSelected(items.count == 1 ? items[0].sector : nil)
        previewSelectionChanged(items.compactMap(\.node))
        updateButtons()
    }

    // MARK: Protection

    /// Precomputed (background) protection for display; `.none` before the analysis lands.
    private func displayProtection(_ node: FileNode) -> ProtectionKind {
        analysis?.protectionKind(node) ?? .none
    }

    /// LIVE guard verdict — only for adding to the delete zone and the delete pipeline.
    private func protectionReason(_ node: FileNode) -> DeletionGuard.Reason? {
        let id = ObjectIdentifier(node)
        if let cached = protectionCache[id] { return cached }
        let reason = deletionList.blockedReason(for: node)
        protectionCache[id] = .some(reason)   // store nil verdicts too
        return reason
    }

    private func updateButtons() {
        let canEdit = activity.isAllowed(.editDeletionList)
        let canDelete = activity.isAllowed(.delete)
        // Display flags only (precomputed); the live guard runs on add and before deleting.
        addButton.isEnabled = canEdit && selectedNodes.contains { displayProtection($0) == .none && !deletionList.contains($0) }
        let deletable = deletionList.items.contains { displayProtection($0) == .none }
        deleteBar.setEnabled(canDelete && deletable)
    }

    // MARK: Menu validation / quit

    func validate(action: Selector?) -> Bool {
        let cmd = Self.command(for: action)
        if cmd == .delete && deletionList.items.isEmpty { return false }
        if action == #selector(goBack(_:)) { return !history.isEmpty || !resultsPage.isHidden }
        if action == #selector(goForward(_:)) { return !forwardStack.isEmpty }
        if action == #selector(enterSelected(_:)) { return drillTarget() != nil }
        return activity.validate(cmd)
    }

    /// Maps menu/button actions to core commands (policy lives in AppActivity).
    static func command(for action: Selector?) -> AppActivity.Command? {
        switch action {
        case #selector(NSApplication.terminate(_:)): return .quit
        case #selector(openFolder(_:)): return .scan
        case #selector(rescan(_:)): return .rescan
        case #selector(cancelScan(_:)): return .stopScan
        case #selector(collectSelected(_:)), #selector(uncollectSelected(_:)), #selector(clearDeletionList(_:)):
            return .editDeletionList
        case #selector(trashCollected(_:)), #selector(deleteCollectedPermanently(_:)):
            return .delete
        default: return nil
        }
    }

    /// Called from `applicationShouldTerminate`. While a deletion runs, it is
    /// asked to stop after the current top-level item and the app replies once
    /// it has (never mid-item).
    func shouldTerminate() -> NSApplication.TerminateReply {
        switch activity.requestTermination() {
        case .now:
            scanTask?.cancel()
            return .terminateNow
        case .later:
            deletionSheet?.cancellation.cancel()
            deletionSheet?.showQuitPending()
            return .terminateLater
        }
    }

    // MARK: Delete zone

    @objc func collectSelected(_ sender: Any?) {
        // Context menu: first right-click may not have selected the row yet — promote clickedRow,
        // then use the same node list as the bottom button / drag drop.
        if outline.promoteClickedRowIntoSelectionIfNeeded() { outlineSelectionChanged() }
        addNodesToBasket(outline.actionNodes)
    }

    /// Shared entry for button, menu, Space, sunburst collect, and drag-drop.
    @discardableResult
    func addNodesToBasket(_ nodes: [FileNode]) -> Int {
        guard activity.isAllowed(.editDeletionList) else { NSSound.beep(); return 0 }
        var refused: [String] = []
        var added = 0
        for n in nodes {
            if let reason = protectionReason(n) {
                let text = tr("status.notAddedItem", n.name, DisplayPath.inText(AppL10n.reason(reason)))
                refused.append(text)
                refusedReasons[ObjectIdentifier(n)] = tr("status.notAdded", text)
                continue
            }
            if deletionList.add(n) { added += 1 }
        }
        reloadDeletionList()
        outline.refreshVisibleRows()
        if !refused.isEmpty { setStatus(tr("status.notAdded", refused.joined(separator: tr("list.joiner")))) }
        return added
    }

    func evaluateBasketDrop(paths: [String]) -> BasketDrag.Evaluation {
        BasketDrag.Evaluation.evaluate(paths: paths) { [weak self] path in
            guard let self, let root = self.scanRoot else { return true }
            let nodes = BasketDrag.resolve(paths: [path], under: root)
            guard let n = nodes.first else { return true }
            return self.protectionReason(n) != nil
        }
    }

    @discardableResult
    func acceptBasketDrop(paths: [String]) -> Bool {
        guard let root = scanRoot else { return false }
        let nodes = BasketDrag.resolve(paths: paths, under: root)
        return addNodesToBasket(nodes) > 0 || nodes.contains { deletionList.contains($0) }
    }

    @objc func uncollectSelected(_ sender: Any?) {
        if outline.promoteClickedRowIntoSelectionIfNeeded() { outlineSelectionChanged() }
        for n in outline.actionNodes where deletionList.contains(n) { deletionList.remove(n) }
        reloadDeletionList()
        outline.refreshVisibleRows()
    }

    @objc func clearDeletionList(_ sender: Any?) {
        deletionList.removeAll()
        reloadDeletionList()
        outline.refreshVisibleRows()
    }

    private func reloadDeletionList() {
        let snap = BasketSnapshot.from(nodes: deletionList.items, homeDirectory: homeDirectory)
        deleteBar.apply(snapshot: snap)
        updateButtons()
    }

    /// ⌘⌫ and the delete zone's primary button: the confirm sheet, Trash preselected.
    @objc func trashCollected(_ sender: Any?) {
        presentDeleteConfirm(preferred: .trash)
    }

    @objc func deleteCollectedPermanently(_ sender: Any?) {
        presentDeleteConfirm(preferred: .permanent)
    }

    /// Confirm sheet: groups / checkboxes / method / typed 「永久删除」, then the existing pipelines.
    private func presentDeleteConfirm(preferred: DeleteConfirmPolicy.Method) {
        guard let window = window, activity.isAllowed(.delete), deleteConfirmSheet == nil, deletionSheet == nil else { NSSound.beep(); return }
        let home = homeDirectory
        var deletable: [FileNode] = []
        var excluded: [(node: FileNode, reasonCode: String)] = []
        for n in deletionList.items {
            if let reason = protectionReason(n) {
                if case .sipProtected = reason {
                    excluded.append((n, "sipProtected"))
                } else {
                    excluded.append((n, DisplayPath.inText(AppL10n.reason(reason))))
                }
            } else {
                deletable.append(n)
            }
        }
        guard !deletable.isEmpty || !excluded.isEmpty else { return }
        let langZh = AppLanguage.pick(preferred: Locale.preferredLanguages, available: ["en", "zh-Hans"]) == "zh-Hans"
        let snap = DeleteConfirmPolicy.build(nodes: deletable, excluded: excluded,
                                             homeDirectory: home, preferredMethod: preferred)
        let sheet = DeleteConfirmSheet(snapshot: snap, languageIsChinese: langZh, homeDirectory: home,
            onConfirm: { [weak self] method, paths in
                guard let self else { return }
                self.deleteConfirmSheet = nil
                // Keep only checked paths in the deletion list for this run.
                let keep = Set(paths)
                for n in self.deletionList.items where !keep.contains(n.path) {
                    self.deletionList.remove(n)
                }
                self.reloadDeletionList()
                guard !self.deletionList.items.isEmpty else { return }
                self.confirmCautionsThenDelete(permanent: method == .permanent)
            },
            onCancel: { [weak self] in self?.deleteConfirmSheet = nil })
        deleteConfirmSheet = sheet
        (sheet.window as? QuitForwardingSheetWindow)?.onQuitKey = { [weak self] in
            guard let self else { return }
            switch self.activity.quitKeyAction() {
            case .terminate: NSApp.terminate(nil)
            case .alreadyQuitting: break
            }
        }
        window.beginSheet(sheet.window, completionHandler: nil)
    }

    /// Second, explicit confirmation for launchd jobs, /Applications bundles
    /// and /private/var/folders items (see DeletionGuard.Caution).
    private func confirmCautionsThenDelete(permanent: Bool) {
        let cautions = deletionList.cautionItems.filter { protectionReason($0.node) == nil }
        guard !cautions.isEmpty, let window = window else {
            performDeletion(permanent: permanent, confirmedCautions: false)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = tr("caution.title", cautions.count)
        alert.informativeText = cautions.prefix(6).map { "• " + DisplayPath.inText(AppL10n.caution($0.caution)) }.joined(separator: "\n\n")
            + (cautions.count > 6 ? "\n\n" + tr("caution.more", cautions.count - 6) : "")
            + "\n\n" + tr("caution.onlyIfSure")
        alert.addButton(withTitle: tr("button.skipThese"))          // default = safe choice
        alert.addButton(withTitle: tr("button.includeThem"))
        alert.addButton(withTitle: tr("button.cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.performDeletion(permanent: permanent, confirmedCautions: false)
            case .alertSecondButtonReturn: self?.performDeletion(permanent: permanent, confirmedCautions: true)
            default: break
            }
        }
    }

    private func performDeletion(permanent: Bool, confirmedCautions: Bool) {
        guard let window = window, deletionSheet == nil, activity.beginDeletion() else { NSSound.beep(); return }
        let undoLog: TrashUndoLog? = permanent ? nil : TrashUndoLog()
        lastTrashUndoLog = undoLog
        let deleter: ItemDeleting = permanent ? PosixRecursiveDeleter() : TrashDeleter(undoLog: undoLog)
        protectionCache.removeAll()   // the executor re-checks the guard live anyway
        let sheet = DeletionProgressSheet(itemCount: deletionList.items.count, permanent: permanent)
        deletionSheet = sheet
        setDeletionControlsEnabled(false)
        // Window-modal sheet (never NSApp.runModal): the menu bar, incl. Quit, stays live.
        (sheet.window as? QuitForwardingSheetWindow)?.onQuitKey = { [weak self] in
            guard let self else { return }
            switch self.activity.quitKeyAction() {
            case .terminate: NSApp.terminate(nil)
            case .alreadyQuitting: break          // swallow: no beep, no second request
            }
        }
        window.beginSheet(sheet.window, completionHandler: nil)
        // Progress: the background callback only yields into ONE AsyncStream;
        // a single main-actor consumer applies events in order and drops stale
        // ones by sequence number (events are stamped in DeletionList).
        var continuation: AsyncStream<DeletionProgress>.Continuation!
        let stream = AsyncStream<DeletionProgress>(bufferingPolicy: .bufferingNewest(256)) { continuation = $0 }
        let cont = continuation!
        let consumer = Task { @MainActor in
            var sequencer = ProgressSequencer()
            for await p in stream where sequencer.accept(p) { sheet.update(p) }
        }
        Task { [weak self] in
            guard let self = self else { return }
            // No background reader may walk the tree while deleteAll edits it in place:
            // cancel + await search/analysis first (re-run in afterDeletion).
            let readers = self.treeGate.activeReaders
            await self.treeGate.beginMutation()
            FilterLog.write("event=treeMutationBegin cancelledReaders=\(readers)")
            let outcome = await self.deletionList.deleteAll(
                using: deleter, privileged: self.privileged, confirmedCautions: confirmedCautions,
                cancellation: sheet.cancellation,
                progress: { p in cont.yield(p) })
            cont.finish()
            self.treeGate.endMutation()
            await consumer.value
            window.endSheet(sheet.window)
            self.deletionSheet = nil
            self.setDeletionControlsEnabled(true)
            self.afterDeletion(outcome)
            if self.activity.endDeletion() == .replyTerminate {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            self.updateButtons()
        }
    }

    private func setDeletionControlsEnabled(_ on: Bool) {
        deleteBar.setEnabled(on)
        addButton.isEnabled = on
        if on { updateButtons() }
    }

    private func afterDeletion(_ outcome: DeletionList.Outcome) {
        protectionCache.removeAll()
        treeGeneration += 1                // invalidates the chart cache key
        rerunSearchAfterTreeChange()
        if let root = scanRoot {
            history.removeAll { !$0.isAttached(to: root) }
            forwardStack.removeAll { !$0.isAttached(to: root) }
            var c = current
            while let n = c, !n.isAttached(to: root) { c = n.parent }
            current = c ?? root
        }
        rebuildChart(force: false)         // no-op if `current` changed (already rebuilt); flags refresh when the analysis lands
        refreshAnalysis()
        reloadDeletionList()
        let skipped = outcome.failed.filter { if case DeletionError.needsConfirmation? = $0.error as? DeletionError { return true }; return false }
        let failed = outcome.failed.filter { f in !skipped.contains { $0.node === f.node } }
        let freed = SizeText.format(outcome.freedBytes)
        setStatus(outcome.cancelled
            ? tr("summary.statusCancelled", freed, outcome.deleted.count, failed.count, skipped.count, outcome.notAttempted.count)
            : tr("summary.status", freed, outcome.deleted.count, failed.count, skipped.count))
        // Skipped items (needed extra confirmation) must stay findable (P2-5): a link in the
        // undo toast, the failure alert, or — if neither shows — their own alert.
        let skippedDetail = skipped.prefix(20).map { "  • " + DisplayPath.inText(AppL10n.error($0.error)) }.joined(separator: "\n")
            + (skipped.count > 20 ? tr("summary.more", skipped.count - 20) : "")
        let showSkipped: () -> Void = { [weak self] in
            self?.showErrorAlert(message: tr("summary.skipped", skipped.count), detail: skippedDetail)
        }
        // Batch-3: trash success toast with 8s Undo (permanent has no undo).
        var toastShown = false
        if !outcome.cancelled, failed.isEmpty, let log = lastTrashUndoLog, !log.pairs.isEmpty,
           let host = window?.contentView {
            undoToast.show(in: host, pairs: log.pairs, freedLabel: freed,
                           skippedCount: skipped.count, onShowSkipped: skipped.isEmpty ? nil : showSkipped)
            toastShown = true
        }
        lastTrashUndoLog = nil
        guard outcome.cancelled || !failed.isEmpty else {
            if !skipped.isEmpty && !toastShown { showSkipped() }
            return
        }
        func list(_ nodes: [FileNode]) -> String {
            nodes.prefix(10).map { "  • " + $0.displayPath }.joined(separator: "\n") + (nodes.count > 10 ? tr("summary.more", nodes.count - 10) : "")
        }
        var detail = ""
        if !outcome.deleted.isEmpty { detail += tr("summary.deleted", outcome.deleted.count) + "\n" + list(outcome.deleted) + "\n\n" }
        if !failed.isEmpty {
            detail += tr("summary.notDeleted", failed.count) + "\n" + failed.prefix(10).map { "  • " + DisplayPath.inText(AppL10n.error($0.error)) }.joined(separator: "\n") + "\n\n"
        }
        if !outcome.partial.isEmpty {
            detail += tr("summary.partial") + "\n" + list(outcome.partial) + "\n\n"
        }
        if outcome.cancelled { detail += tr("summary.notAttempted", outcome.notAttempted.count) + "\n" + list(outcome.notAttempted) + "\n\n" }
        if !skipped.isEmpty { detail += tr("summary.skipped", skipped.count) + "\n" + skippedDetail + "\n\n" }
        if !failed.isEmpty { detail += tr("summary.noAdmin") }
        showErrorAlert(message: outcome.cancelled ? tr("summary.cancelledTitle") : tr("summary.failedTitle", failed.count),
                       detail: detail)
    }

    private func showErrorAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        if let w = window { alert.beginSheetModal(for: w, completionHandler: nil) } else { alert.runModal() }
    }

    func windowWillClose(_ notification: Notification) {
        scanTask?.cancel()
        deletionSheet?.cancellation.cancel()   // stops before the next item; never mid-item
        volumeTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: Quick Look

    @objc func toggleQuickLook(_ sender: Any?) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            if previewNodes.isEmpty {
                if outline.promoteClickedRowIntoSelectionIfNeeded() { outlineSelectionChanged() }
                previewNodes = outline.actionNodes
            }
            guard !previewNodes.isEmpty else { NSSound.beep(); return }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func previewSelectionChanged(_ nodes: [FileNode]) {
        previewNodes = nodes
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

// MARK: - Menu validation

/// Menu items targeting this controller are enabled only when the command is
/// allowed right now (see AppActivity): no scan/rescan/open or deletion-list
/// changes while a deletion runs.

extension MainWindowController: NSMenuDelegate {
    /// Right-click on an unselected row: select it when the menu opens so 「加入删除区」
    /// shares the same selection path as the bottom button (and validateMenuItem sees it).
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === outline.view.menu else { return }
        if outline.promoteClickedRowIntoSelectionIfNeeded() { outlineSelectionChanged() }
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        validate(action: menuItem.action)
    }
}

// MARK: - Quick Look data source / delegate

// Swift 6: whether the SDK marks these protocols @MainActor varies, so the
// witnesses are `nonisolated` (valid either way) and hop onto the main actor
// with `assumeIsolated` — Quick Look always calls its data source on the main
// thread. Only Sendable values (Int, URL) leave the isolated closure.
extension MainWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        // Never trap: off the main thread, answer "nothing to preview".
        guard Thread.isMainThread else { return 0 }
        return MainActor.assumeIsolated { previewNodes.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard Thread.isMainThread else { return nil }
        let url: URL? = MainActor.assumeIsolated {
            guard index >= 0, index < previewNodes.count else { return nil }
            return URL(fileURLWithPath: previewNodes[index].path)
        }
        return url.map { $0 as NSURL }
    }
}

// MARK: - Sunburst delegate

extension MainWindowController: SunburstViewDelegate {
    func sunburstView(_ view: SunburstView, didSelect node: FileNode?, sector: Int?) {
        outline.select(sector: sector)
        if let n = node { previewSelectionChanged([n]) }
    }

    func sunburstView(_ view: SunburstView, drillInto node: FileNode) { navigate(to: node) }

    func sunburstViewRequestsParent(_ view: SunburstView) { goUp(nil) }

    func sunburstView(_ view: SunburstView, didHover sector: Int?) {
        outline.hover(sector: sector)
    }

    func sunburstView(_ view: SunburstView, collect node: FileNode) {
        addNodesToBasket([node])
    }

    func sunburstView(_ view: SunburstView, dragNodes nodes: [FileNode]) {
        // Drag session already writing pasteboard; drop goes through acceptBasketDrop.
        _ = nodes
    }
}

// MARK: - Split view: chart ≥ 520 | list 436 (360–480); numbers in SplitLayout. No delegate.

// MARK: - Toolbar

extension MainWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchItem.searchField else { return }
        updateRegexBadge()
        scheduleSearch(searchItem.searchField.stringValue, source: "typing")
    }
    /// Esc inside the field: clear the search and restore the previous view.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchItem.searchField, commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        clearSearch(escape: true, source: "esc-field")
        return true
    }

    /// Esc anywhere in this window (no sheet open) clears an active search.
    fileprivate func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, ev.keyCode == 53, self.search.isActive, ev.window === self.window,
                  self.window?.attachedSheet == nil else { return ev }
            // Inside the search field, doCommandBy handles it.
            if let ed = self.searchItem.searchField.currentEditor(), self.window?.firstResponder === ed { return ev }
            self.clearSearch(escape: true, source: "esc-window")
            return nil
        }
    }
}

extension MainWindowController: NSToolbarDelegate {
    private static let navID = NSToolbarItem.Identifier("nav")
    private static let pathID = NSToolbarItem.Identifier("path")
    private static let rescanID = NSToolbarItem.Identifier("rescan")
    private static let revealID = NSToolbarItem.Identifier("reveal")

    fileprivate func buildToolbar(_ window: NSWindow) {
        let tb = NSToolbar(identifier: "DiskRings.Main")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        window.toolbar = tb
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navID, Self.pathID, .flexibleSpace, Self.rescanID, Self.revealID, searchItem.itemIdentifier]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.navID:
            navControl.segmentCount = 2
            navControl.trackingMode = .momentary
            navControl.segmentStyle = .separated
            navControl.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: tr("toolbar.back")), forSegment: 0)
            navControl.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: tr("toolbar.forward")), forSegment: 1)
            navControl.setToolTip(tr("toolbar.back"), forSegment: 0)
            navControl.setToolTip(tr("toolbar.forward"), forSegment: 1)
            navControl.target = self
            navControl.action = #selector(navClicked(_:))
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = navControl
            item.label = tr("toolbar.back")
            return item
        case Self.pathID:
            pathControl.pathStyle = .standard
            pathControl.font = .systemFont(ofSize: 13)
            pathControl.target = self
            pathControl.action = #selector(pathClicked(_:))
            pathControl.translatesAutoresizingMaskIntoConstraints = false
            pathControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            pathControl.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = pathControl
            return item
        case Self.rescanID:
            let item = button(id, "arrow.clockwise", tr("toolbar.rescan"), #selector(rescan(_:)))
            rescanItem = item
            updateRescanTip()
            return item
        case Self.revealID:
            return button(id, "folder", tr("menu.reveal"), #selector(revealSelected(_:)))
        case searchItem.itemIdentifier:
            searchItem.searchField.target = self
            searchItem.searchField.action = #selector(searchChanged(_:))
            searchItem.searchField.delegate = self                 // controlTextDidChange → debounce
            searchItem.searchField.sendsSearchStringImmediately = false
            searchItem.searchField.sendsWholeSearchString = false
            searchItem.searchField.searchMenuTemplate = searchMenu()
            updateRegexBadge()                                     // placeholder/tooltip for the launch mode (Contains)
            searchItem.preferredWidthForSearchField = 196
            return searchItem
        default:
            return nil
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    @objc private func navClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { goBack(sender) } else { goForward(sender) }
    }

    @objc private func pathClicked(_ sender: NSPathControl) {
        guard let clicked = sender.clickedPathItem, let i = sender.pathItems.firstIndex(of: clicked) else { return }
        let nodeIndex = max(0, i - 1)           // item 0 is the volume → scan root
        if nodeIndex < pathNodes.count { navigate(to: pathNodes[nodeIndex]) }
    }

    /// Back/forward enablement + breadcrumb 「Macintosh HD › Data › …」 (NSPathControl).
    fileprivate func updateToolbar() {
        navControl.setEnabled(!history.isEmpty || !resultsPage.isHidden, forSegment: 0)
        navControl.setEnabled(!forwardStack.isEmpty, forSegment: 1)
        var nodes: [FileNode] = []
        var n = current
        while let x = n { nodes.insert(x, at: 0); if x === scanRoot { break }; n = x.parent }
        pathNodes = nodes
        var items: [NSPathControlItem] = []
        if !resultsPage.isHidden {
            let vol = NSPathControlItem()
            vol.title = scanVolumeName ?? tr("window.title")
            vol.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)
            items.append(vol)
            for (i, x) in nodes.enumerated() {
                let it = NSPathControlItem()
                it.attributedTitle = NSAttributedString(string: x.sunburstName, attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: i == nodes.count - 1 ? .semibold : .regular)])
                items.append(it)
            }
        }
        pathControl.pathItems = items
    }
}
#endif
