// Box-only preview data dump for the simplify-v2 previews. Compiled TOGETHER with the
// real Sources/DiskScanCore + Sources/SunburstGeometry (one module), so the sectors,
// colours, labels-fit, outline levels, high-risk flags, hidden counts, basket and
// confirm-sheet groups all come from the shipping code paths. Rendering (HTML/SVG →
// PNG) is done by render.py with the real zh-Hans strings + DesignTokens.json.
// NOT an AppKit screenshot.
// Usage: swiftc -O -D SINGLE_MODULE -o /tmp/drdump Sources/DiskScanCore/*.swift \
//          Sources/SunburstGeometry/*.swift scripts/preview/chart_dump.swift && /tmp/drdump > dump.json
import Foundation

typealias S = SyntheticTree
let GB = 1_000_000_000.0
func file(_ n: String, _ gb: Double) -> FileNode { S.node(n, size: UInt64(gb * GB)) }
/// Leaf entry of `gb` (a single file node keeps ring 3 free of synthetic children).
func leaf(_ n: String, _ gb: Double) -> FileNode { file(n, gb) }
/// `count` small files totalling `gb` (merged into 其他 by the real layout rule).
func smalls(_ prefix: String, _ count: Int, _ gb: Double) -> [FileNode] {
    (0..<count).map { file("\(prefix)\($0).bin", gb / Double(count) * (1 + 0.02 * Double($0 % 3))) }
}
// Sample tree = the designer's data.py (示例数据), with real files instead of pre-merged rows.
let root = S.finish(S.node("/", [
    S.node("Users", [S.node("tester", [
        S.node("Library", [leaf("Containers", 50), leaf("Application Support", 44), leaf("Caches", 17)] + smalls("lib", 14, 9)),
        S.node("Movies", [leaf("导出成片", 21), leaf("Final Cut 资源库", 15)] + smalls("mov", 12, 10)),
        S.node("Developer", [leaf("DerivedData", 20), leaf("CoreSimulator", 16), file("misc", 1)]),
        leaf("照片图库", 36),
        S.node("Documents", [leaf("论文资料", 14)] + smalls("doc", 20, 13)),
        S.node("Downloads", [leaf("安装包 .dmg", 8.7), leaf("压缩包 .zip", 5.8)] + smalls("dl", 12, 7.5)),
        S.node("Public", [file("empty", 0), file("empty2", 0)]),
    ] + smalls("home", 30, 27))]),
    S.node("Applications", [leaf("Xcode.app", 12)] + smalls("app", 41, 18)),
    S.node("private", [S.node("var", [leaf("db", 9), leaf("vm", 8)])]),
    S.node("Library", [leaf("Apple", 9), leaf("Developer", 5)]),
    S.node("opt", [S.node("homebrew", [leaf("Cellar", 4.2), leaf("var", 1.6)])]),
] + smalls("root", 4, 5.2)))

let home = "/Users/tester"
// Same background pass as the app: display protection from the real DeletionGuard rules
// (pure snapshot guard: fixed home + mount list, no file flags).
let snapshot = DeletionGuard(homeDirectory: home, mountPoints: { ["/"] })
let analysis = TreeAnalysis.build(root: root, homeDirectory: home, protectionGuard: snapshot)!
func isProtected(_ n: FileNode) -> Bool { analysis.protectionKind(n) == .subtree }
func gbText(_ b: Double) -> String {
    let g = b / GB
    return g >= 10 ? String(format: "%.0f GB", g) : String(format: "%.1f GB", g)
}
let model = ChartModel(focus: root, isProtected: isProtected, isHighRisk: { analysis.isHighRisk($0) },
                       sizeText: gbText, otherName: { "其他 \($0) 项" })
func hex(_ c: RGB) -> String { c.hex }

// Drilled sample in the shape of a home-folder drill (Documents 81 GB next to a
// deep Library): three nested levels of medium folders, so ring 2/3 have real slices.
func dir(_ n: String, _ kids: [FileNode]) -> FileNode { S.node(n, kids) }
let drillRoot = S.finish(dir("tester", [
    dir("Documents", [dir("论文资料", [leaf("数据集", 18), leaf("草稿", 6), leaf("图表", 4)]),
                      dir("项目归档", [leaf("2024", 12), leaf("2025", 9), leaf("2023", 5)]),
                      dir("扫描件", [leaf("合同", 7), leaf("发票", 3)]), leaf("Keynote", 9)] + smalls("doc", 10, 8)),
    dir("Library", [dir("Containers", [leaf("com.apple.mail", 14), leaf("com.tencent.xinWeChat", 22), leaf("com.apple.Safari", 4)]),
                    dir("Application Support", [leaf("MobileSync", 19), leaf("Google", 7), leaf("JetBrains", 6)]),
                    dir("Caches", [leaf("com.spotify.client", 5), leaf("Homebrew", 3), leaf("pip", 2)]),
                    dir("Developer", [leaf("Xcode", 11), leaf("CoreSimulator", 9)]),
                    dir("Mail", [leaf("V10", 6)])] + smalls("lib", 12, 6)),
    dir("Movies", [leaf("导出成片", 21), leaf("Final Cut 资源库", 15), leaf("录屏", 4)]),
    dir("Pictures", [dir("Photos Library.photoslibrary", [leaf("originals", 28), leaf("resources", 6)])]),
    dir("Downloads", [leaf("安装包 .dmg", 8.7), leaf("压缩包 .zip", 5.8)] + smalls("dl", 12, 7.5)),
    dir("Developer", [leaf("DerivedData", 20), dir("repos", [leaf("diskrings", 2), leaf("monorepo", 9)])]),
    dir("Music", [leaf("Music Library", 6)]),
] + smalls("home", 20, 10)))
let drillModel = ChartModel(focus: drillRoot, isProtected: { _ in false }, isHighRisk: { _ in false },
                            sizeText: gbText, otherName: { "其他 \($0) 项" })
/// Coverage at chart scale k (designer spec: per-tier metrics, ≥ 10 pt, rotatedNameFirst),
/// plus the earlier spec order with the same metrics for comparison.
func named(_ ls: [SectorLabel]) -> Int { ls.filter { $0.tier == .nameAndSize || ($0.tier == .rotated && !$0.isSizeLine) }.count }
func coverage(_ base: ChartModel<FileNode>, _ tag: String, k: Double) -> ChartModel<FileNode> {
    var m = base; m.applyLabelScale(k)
    let ls = m.sectors.map(\.label)
    var t = [0, 0, 0, 0]; for l in ls { t[l.tier.rawValue] += 1 }
    let sizeOnlyAny = ls.filter { $0.tier != .hidden && $0.isSizeLine }.count
    let spec = LabelLayout.place(m.labelCache.inputs, metrics: .forScale(k), order: .spec)
    let specText = spec.filter { $0.tier != .hidden }.count
    let line = String(format: "COVERAGE %@ k=%.2f (tier %.2f, screen name %.1fpt size %.1fpt): text %d/%d (name %d, size-only %d); a/b/c/d nameAndSize %d sizeOnly %d rotated %d hidden %d | spec order: text %d name %d\n",
                      tag, k, m.labelTier, m.sectors.first.map { _ in LabelMetrics.forScale(k).nameFont * k } ?? 0,
                      LabelMetrics.forScale(k).sizeFont * k, ls.count - t[3], ls.count, named(ls), sizeOnlyAny,
                      t[0], t[1], t[2], t[3], specText, named(spec))
    FileHandle.standardError.write(line.data(using: .utf8)!)
    return m
}
let previewScales = [1.0, 0.87, 0.76]
for k in previewScales { _ = coverage(model, "root", k: k) }
let drillByK = previewScales.map { coverage(drillModel, "drill", k: $0) }
func labelDict(_ s: ChartModel<FileNode>.Sector) -> [String: Any] {
    let l = s.label
    return ["tier": "\(l.tier)", "lines": l.lines, "cx": l.center.x, "cy": l.center.y, "rot": l.rotation,
            "w": l.width, "h": l.height, "inkLight": s.inkLight.hex, "inkDark": s.inkDark.hex,
            "nameFont": l.nameFont, "sizeFont": l.sizeFont, "nameLine": l.nameLine, "sizeLine": l.sizeLine, "isSize": l.isSizeLine]
}
var sectors: [[String: Any]] = []
for s in model.sectors {
    sectors.append(["lab": labelDict(s), "i": s.index, "d": s.depth, "a0": s.startAngle, "a1": s.endAngle, "r0": s.innerRadius, "r1": s.outerRadius,
                    "parent": s.parent ?? -1, "name": s.name, "size": s.sizeText, "lines": s.labelLines,
                    "risk": s.isHighRisk, "prot": s.isProtected, "role": "\(s.color.role)",
                    "light": hex(s.color.light), "dark": hex(s.color.dark), "bytes": s.size])
}
// Outline rows exactly as ResultsOutline builds them: roots = centre children; expand
// the dominant container (Users › tester); select Library.
var rows: [[String: Any]] = []
let total = model.layout.rootSize
func addRows(_ idx: [Int], depth: Int) {
    for i in idx {
        let s = model.sectors[i]
        let kids = model.childrenOf[i] ?? []
        let expandable = s.node.map { $0.isDirectory && $0.children.contains { $0.sunburstSize > 0 } } ?? false
        let expand = s.color.role == .container
        rows.append(["depth": depth, "sector": i, "name": s.name, "size": s.sizeText, "share": s.size / total * 100,
                     "risk": s.isHighRisk, "prot": s.node.map { analysis.protectionKind($0) != .none } ?? false,
                     "other": s.isOther, "expandable": expandable,
                     "expanded": expand, "dir": s.node?.isDirectory ?? false])
        if expand { addRows(kids, depth: depth + 1) }
    }
}
addRows(model.childrenOf[-1] ?? [], depth: 0)
let selected = model.sectors.first { $0.depth == 2 && $0.node?.name == "Library" }!.index

// Basket + confirm sheet from the real policy code.
func find(_ comps: [String]) -> FileNode { root.descendant(atRelativePath: comps)! }
let basketNodes = [find(["Users", "tester", "Library", "Caches"]), find(["Users", "tester", "Developer", "DerivedData"]),
                   find(["Applications", "Xcode.app"])]
let snap = BasketSnapshot.from(nodes: basketNodes, homeDirectory: home)
let chips = snap.chips.map { ["name": $0.name, "size": gbText(Double($0.bytes)), "risk": $0.isHighRisk] as [String: Any] }
let policy = DeleteConfirmPolicy.build(nodes: basketNodes, excluded: [],
                                       homeDirectory: home, preferredMethod: .trash)
func item(_ it: DeleteConfirmPolicy.Item) -> [String: Any] {
    ["name": it.name, "path": (it.path as NSString).deletingLastPathComponent, "size": gbText(Double(it.bytes)),
     "risk": it.isHighRisk, "consequence": DeleteConfirmPolicy.consequenceKey(for: it.riskReasons),
     "cache": BasketRisk.libraryState(path: it.path, homeDirectory: home) == .caches]
}
let sheet: [String: Any] = [
    "high": policy.highRiskItems.map(item), "normal": policy.normalItems.map(item),
    "excluded": policy.excluded.map { ["name": $0.name, "path": ($0.path as NSString).deletingLastPathComponent, "size": gbText(Double($0.bytes))] },
    "count": policy.checkedCount, "bytes": gbText(Double(policy.checkedBytes)), "highCount": policy.checkedHighRiskCount,
    "phrase": DeleteConfirmPolicy.typeConfirmPhrase(languageIsChinese: true),
    "permEnabledWhenTyped": DeleteConfirmPolicy.primaryEnabled(snapshot: DeleteConfirmPolicy.settingMethod(.permanent, in: policy),
                                                                typedText: "永久删除", languageIsChinese: true),
]
// Capacity bar from the real CapacityBarModel (root-level model; ~/Library vs /Library).
func capName(_ s: ChartModel<FileNode>.Sector) -> String {
    guard let n = s.node else { return s.name }
    if n.path == home + "/Library" { return "~/Library" }
    if n.name == "Library", n.parent === root { return "/Library" }
    return s.name
}
let bar = CapacityBarModel(root: model, volumeTotal: 494 * GB, volumeAvailable: 100 * GB, name: capName)
func anc(_ a: FileNode, _ n: FileNode) -> Bool { var c: FileNode? = n; while let x = c { if x === a { return true }; c = x.parent }; return false }
let homeUser = find(["Users", "tester"])
let drill = bar.scope(focus: homeUser, isRoot: false, isAncestorOrSelf: anc)
func legendJSON(_ items: [CapacityBarModel<FileNode>.LegendItem]) -> [[String: Any]] {
    items.map { it in
        switch it.kind {
        case let .branch(i): return ["kind": "branch", "seg": i, "size": gbText(it.bytes)]
        case let .folded(l): return ["kind": "folded", "n": l.count, "size": gbText(it.bytes)]
        case .protected: return ["kind": "protected", "size": gbText(it.bytes)]
        case .other: return ["kind": "other", "size": gbText(it.bytes)]
        case .systemGap: return ["kind": "system", "size": gbText(it.bytes)]
        case .free: return ["kind": "free", "size": gbText(it.bytes)]
        }
    }
}
let capacity: [String: Any] = [
    "segments": bar.segments.map { ["kind": "\($0.kind)", "name": $0.name, "start": $0.start, "end": $0.end,
                                    "light": $0.light.hex, "dark": $0.dark.hex, "size": gbText($0.bytes)] as [String: Any] },
    "legend": legendJSON(bar.legend),
    // Width fitting with a CJK-aware estimate of the 11 pt legend text (view uses NSString metrics).
    "legendFitted": legendJSON(bar.fittedLegend(width: 1232, itemWidth: { it in
        let (n, v): (String, String) = {
            switch it.kind {
            case let .branch(i): return (bar.segments[i].name, gbText(it.bytes))
            case let .folded(l): return ("+\(l.count) 项", gbText(it.bytes))
            case .protected: return ("系统保护", gbText(it.bytes))
            case .other: return ("其他", gbText(it.bytes))
            case .systemGap: return ("系统与快照", gbText(it.bytes))
            case .free: return ("可用", gbText(it.bytes))
            }
        }()
        return TextWidth.estimate(n, fontSize: 11) + TextWidth.estimate(v, fontSize: 11) + 17
    })),
    "used": gbText(bar.used), "total": gbText(bar.total),
    "drill": ["inScope": drill.inScope, "lo": drill.bracket?.lowerBound ?? 0, "hi": drill.bracket?.upperBound ?? 0,
              "name": "Users › tester", "size": gbText(homeUser.sunburstSize),
              "share": String(format: "%.0f%%", homeUser.sunburstSize / bar.used * 100)],
]
let out: [String: Any] = [
    "capacity": capacity,
    "sectors": sectors, "rows": rows, "selected": selected,
    "center": ["name": "Data", "size": gbText(root.sunburstSize), "items": root.itemCount],
    "hidden": analysis.hiddenCount(root),
    "basket": ["chips": chips, "count": snap.count, "total": gbText(Double(snap.totalBytes)), "high": snap.highRiskCount],
    "sheet": sheet,
    "drillCharts": zip(previewScales, drillByK).map { k, dm -> [String: Any] in [
        "k": k, "tier": dm.labelTier,
        "sectors": dm.sectors.map { s -> [String: Any] in
            ["lab": labelDict(s), "i": s.index, "d": s.depth, "a0": s.startAngle, "a1": s.endAngle, "r0": s.innerRadius,
             "r1": s.outerRadius, "name": s.name, "size": s.sizeText, "prot": s.isProtected, "role": "\(s.color.role)",
             "light": hex(s.color.light), "dark": hex(s.color.dark),
             "tip": dm.hoverTooltip(s.index, path: { "~/" + $0.sunburstPath.split(separator: "/").dropFirst().joined(separator: "/") }) ?? ""]
        },
        "center": ["name": "tester", "size": gbText(drillRoot.sunburstSize), "items": drillRoot.itemCount],
    ] },
]
let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
