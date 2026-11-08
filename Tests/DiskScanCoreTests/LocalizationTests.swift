import XCTest
import Foundation
@testable import DiskScanCore

/// Minimal .strings parser ("key" = "value"; with \" \\ \n escapes, /* */ and // comments).
enum StringsFile {
    struct ParseError: Error { let line: Int; let why: String }
    static func parse(_ text: String) throws -> [String: String] {
        var out: [String: String] = [:]
        let c = Array(text.unicodeScalars)
        var i = 0, line = 1
        func skipWS() throws {
            while i < c.count {
                if c[i] == "\n" { line += 1; i += 1 }
                else if c[i] == " " || c[i] == "\t" || c[i] == "\r" { i += 1 }
                else if c[i] == "/" && i + 1 < c.count && c[i + 1] == "*" {
                    i += 2
                    while i + 1 < c.count && !(c[i] == "*" && c[i + 1] == "/") { if c[i] == "\n" { line += 1 }; i += 1 }
                    guard i + 1 < c.count else { throw ParseError(line: line, why: "unterminated comment") }
                    i += 2
                } else if c[i] == "/" && i + 1 < c.count && c[i + 1] == "/" {
                    while i < c.count && c[i] != "\n" { i += 1 }
                } else { return }
            }
        }
        func quoted() throws -> String {
            guard i < c.count, c[i] == "\"" else { throw ParseError(line: line, why: "expected \"") }
            i += 1
            var s = String.UnicodeScalarView()
            while i < c.count && c[i] != "\"" {
                if c[i] == "\\" {
                    i += 1
                    guard i < c.count else { break }
                    switch c[i] { case "n": s.append("\n"); case "t": s.append("\t"); case "\"": s.append("\""); case "\\": s.append("\\")
                    default: throw ParseError(line: line, why: "bad escape \\\(c[i])") }
                } else { if c[i] == "\n" { line += 1 }; s.append(c[i]) }
                i += 1
            }
            guard i < c.count else { throw ParseError(line: line, why: "unterminated string") }
            i += 1
            return String(s)
        }
        while true {
            try skipWS()
            if i >= c.count { break }
            let k = try quoted(); try skipWS()
            guard i < c.count, c[i] == "=" else { throw ParseError(line: line, why: "expected =") }
            i += 1; try skipWS()
            let v = try quoted(); try skipWS()
            guard i < c.count, c[i] == ";" else { throw ParseError(line: line, why: "expected ;") }
            i += 1
            if out[k] != nil { throw ParseError(line: line, why: "duplicate key \(k)") }
            out[k] = v
        }
        return out
    }

    /// Normalized printf specifiers: positional form, precision dropped, sorted.
    static func specifiers(_ s: String) -> [String] {
        let v = s.replacingOccurrences(of: "%%", with: "")
        let re = try! NSRegularExpression(pattern: "%([0-9]+\\$)?[-+ 0#]*[0-9]*(\\.[0-9]+)?(l|ll|h)?[@dDiuUxXoOfeEgGcCsSp]")
        var n = 0
        return re.matches(in: v, range: NSRange(v.startIndex..., in: v)).map { m -> String in
            var t = String(v[Range(m.range, in: v)!])
            if !t.contains("$") { n += 1; t = "%\(n)$" + t.dropFirst() }
            return t.replacingOccurrences(of: "\\.[0-9]+", with: "", options: .regularExpression)
        }.sorted()
    }
}

final class LocalizationTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..").standardized
    func load(_ lang: String) throws -> [String: String] {
        let t = try String(contentsOf: Self.root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8)
        return try StringsFile.parse(t)
    }

    func testBothLanguagesParseWithSameNonEmptyKeys() throws {
        let en = try load("en"), zh = try load("zh-Hans")
        XCTAssertGreaterThan(en.count, 150)
        XCTAssertEqual(Set(en.keys), Set(zh.keys), "missing: \(Set(en.keys).symmetricDifference(zh.keys).sorted())")
        for (k, v) in en { XCTAssertFalse(v.isEmpty, "en.\(k) empty") }
        for (k, v) in zh { XCTAssertFalse(v.isEmpty, "zh-Hans.\(k) empty") }
        XCTAssertThrowsError(try StringsFile.parse("\"a\" = \"b\"")); XCTAssertThrowsError(try StringsFile.parse("\"a\" = \"b\";\n\"a\" = \"c\";"))
        XCTAssertEqual(try StringsFile.parse("/* c */ \"a\\\"\" = \"x\\ny\"; // t\n"), ["a\"": "x\ny"])
    }

    func testFormatSpecifiersMatchPerKey() throws {
        let en = try load("en"), zh = try load("zh-Hans")
        for (k, e) in en {
            XCTAssertEqual(StringsFile.specifiers(e), StringsFile.specifiers(zh[k] ?? ""), k)
        }
        XCTAssertEqual(StringsFile.specifiers("%1$ld files, %2$@"), StringsFile.specifiers("%2$@ 中 %ld"), "positional == sequential")
        XCTAssertNotEqual(StringsFile.specifiers("%@"), StringsFile.specifiers("%ld"))
    }

    func testEveryKeyUsedInAppSourcesExistsInEnglish() throws {
        let en = try load("en")
        let dir = Self.root.appendingPathComponent("Sources/DiskRingsApp")
        let re = try NSRegularExpression(pattern: "(?:\\btr|NSLocalizedString)\\(\"([^\"]+)\"")
        var used = Set<String>()
        for f in try FileManager.default.contentsOfDirectory(atPath: dir.path) where f.hasSuffix(".swift") {
            let s = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) { used.insert(String(s[Range(m.range(at: 1), in: s)!])) }
        }
        used.formUnion(AppearancePreference.allCases.map(\.menuKey))   // built from the enum, not a literal
        XCTAssertGreaterThan(used.count, 100)
        XCTAssertEqual(used.subtracting(en.keys).sorted(), [], "keys used in source but missing from en.lproj")
        let coreKeys = Set(ReasonText.english.keys)
        XCTAssertEqual(Set(en.keys).subtracting(used).subtracting(coreKeys).sorted(), [], "unused keys")
    }

    static let reasons: [DeletionGuard.Reason] = [
        .filesystemRoot, .volumeRoot("/Volumes/X"), .containsVolume("/Volumes/X"), .homeFolder, .containsHomeFolder,
        .systemLocation("/System"), .containsProtected("/usr"), .essentialFolder("/Users/c/Library"), .sipProtected,
        .unsafePath(".."), .containsOtherDevice("/a/m"), .containsRestricted("/a/r"), .contentsNotVerifiable("/a/u"),
        .changedSinceCheck("/a/c"), .cannotDelete("/a/x", ReasonText.Detail.folderReadOnly), .cancelled]
    static let cautions: [DeletionGuard.Caution] = [.launchdJob("/L/x.plist"), .applicationBundle("/Applications/A.app"), .systemTempFolders("/private/var/folders/x")]
    static let errors: [DeletionError] = [
        .posix(path: "/a", operation: "unlink", code: EACCES), .posix(path: "/a", operation: "unlink", code: EPERM),
        .trashUnavailable, .refusedRoot("/"), .privilegedHelperNotImplemented, .underlying(path: "/a", description: "d"),
        .blocked(path: "/a", reason: .homeFolder), .needsConfirmation(path: "/a", caution: .launchdJob("/L")),
        .partiallyDeleted(path: "/a", removedEntries: 3, cause: "x"), .cancelled]

    func testEveryCoreCodeHasKeysAndEnglishRenderingIsUnchanged() throws {
        let en = try load("en"), zh = try load("zh-Hans")
        for (k, v) in ReasonText.english { XCTAssertEqual(en[k], v, "en.lproj must match core English for \(k)"); XCTAssertNotNil(zh[k], k) }
        for r in Self.reasons {
            let m = ReasonText.message(r)
            XCTAssertNotNil(en[m.key], m.key); XCTAssertNotNil(zh[m.key], m.key)
            XCTAssertEqual(ReasonText.text(r), r.description, "no lookup = unchanged English")
            XCTAssertEqual(ReasonText.text(r, lookup: { en[$0] }), r.description, "en.lproj = unchanged English")
            let z = ReasonText.text(r, lookup: { zh[$0] })
            XCTAssertNotEqual(z, r.description, "\(r) localized"); XCTAssertFalse(z.contains("%"), z)
        }
        for c in Self.cautions {
            XCTAssertEqual(ReasonText.text(c, lookup: { en[$0] }), c.description)
            XCTAssertNotEqual(ReasonText.text(c, lookup: { zh[$0] }), c.description)
        }
        for e in Self.errors {
            XCTAssertNotNil(en[ReasonText.message(e).key])
            XCTAssertEqual(ReasonText.text(e, lookup: { en[$0] }), e.description, "\(e)")
            XCTAssertFalse(ReasonText.text(e, lookup: { zh[$0] }).contains("%"))
        }
        XCTAssertTrue(ReasonText.text(DeletionError.posix(path: "/a", operation: "unlink", code: EPERM), lookup: { zh[$0] }).contains("完全磁盘访问权限"))
    }

    func testCheckerDetailsAreLocalized() throws {
        let zh = try load("zh-Hans")
        let details = [ReasonText.Detail.fullDiskAccess, ReasonText.Detail.folderNotWritableToMove, ReasonText.Detail.folderACLDenyChild,
                       ReasonText.Detail.folderReadOnly, ReasonText.Detail.entryACLDeny, ReasonText.Detail.stickyOtherUser,
                       "folder could not be read completely (Input/output error)",
                       "folder is " + DeletabilityChecker.flagText(DeletabilityChecker.ufImmutable | DeletabilityChecker.sfAppend) + " (entries can't be removed)",
                       DeletabilityChecker.flagText(DeletabilityChecker.ufAppend), DeletabilityChecker.flagText(0)]
        for d in details {
            let z = ReasonText.detail(d, lookup: { zh[$0] })
            XCTAssertNotEqual(z, d, d); XCTAssertEqual(ReasonText.detail(d), d, "English unchanged")
        }
        XCTAssertEqual(ReasonText.detail("folder is locked (uchg), append-only (uappnd) (entries can't be removed)", lookup: { zh[$0] }),
                       "文件夹已锁定（uchg）、仅可追加（uappnd）（无法移除其中的项目）")
        XCTAssertEqual(ReasonText.detail("something new", lookup: { zh[$0] }), "something new", "unknown text falls back to English")
        XCTAssertTrue(zh["detail.fullDiskAccess"]!.contains("系统设置 > 隐私与安全性"))
    }

    func testPermanentVersusTrashWordingIsDistinct() throws {
        let zh = try load("zh-Hans"), en = try load("en")
        XCTAssertTrue(zh["confirm.method.permanent"]!.contains("永久删除"))
        XCTAssertTrue(zh["confirm.method.trash"]!.contains("废纸篓"))
        XCTAssertTrue(zh["confirm.method.permanentDetail"]!.contains("无法撤销"))
        XCTAssertTrue(en["confirm.method.permanentDetail"]!.contains("Cannot be undone") || en["confirm.method.permanentDetail"]!.contains("cannot be undone"))
        XCTAssertEqual(zh["confirm.title.permanent"], "永久删除 %ld 个项目？")
        XCTAssertEqual(zh["confirm.title.trash"], "将 %ld 个项目移到废纸篓？")
        XCTAssertEqual(zh["confirm.type.prompt"], "输入「%@」以确认：")
        XCTAssertNil(zh["confirm.type.hint"], "no hold-to-confirm / count phrase any more")
        XCTAssertTrue(zh["toast.trashed"]!.contains("废纸篓")); XCTAssertEqual(zh["toast.undo"], "撤销")
    }

    func testSubstitutionAndLanguagePick() {
        XCTAssertEqual(ReasonText.substitute("%2$@ 中可用 %1$@", ["1 GB", "2 GB"]), "2 GB 中可用 1 GB")
        XCTAssertEqual(ReasonText.substitute("a %@ b %@ 100%%", ["x", "y"]), "a x b y 100%")
        let av = ["en", "zh-Hans"]
        for (pref, want) in [(["zh-Hans-CN"], "zh-Hans"), (["zh-CN"], "zh-Hans"), (["zh_SG"], "zh-Hans"), (["zh-Hant-TW"], "zh-Hans"),
                             (["zh-HK"], "zh-Hans"), (["en-US"], "en"), (["de-DE", "zh-Hans"], "zh-Hans"), (["fr"], "en"), ([], "en"),
                             (["en-GB", "zh-Hans"], "en")] {
            XCTAssertEqual(AppLanguage.pick(preferred: pref, available: av), want, "\(pref)")
        }
        XCTAssertEqual(AppLanguage.pick(preferred: ["zh-Hans"], available: ["en"]), "en", "no Chinese shipped -> English")
    }
}

/// R10: Chinese UI review — string length budgets for constrained labels and terminology.
final class LocalizationLayoutBudgetTests: XCTestCase {
    func load(_ l: String) throws -> [String: String] {
        try StringsFile.parse(String(contentsOf: LocalizationTests.root.appendingPathComponent("Resources/\(l).lproj/Localizable.strings"), encoding: .utf8))
    }
    /// Display width: CJK/fullwidth = 2 columns, others = 1 (rough, font-independent).
    static func width(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { $0 + (($1.value >= 0x2E80 && $1.value <= 0xFFEF) ? 2 : 1) }
    }
    func testColumnHeadersButtonsAndMenusFitTheirBudgets() throws {
        for lang in ["en", "zh-Hans"] {
            let t = try load(lang)
            for (k, v) in t {
                let w = Self.width(v)
                if k.hasPrefix("column.") && !k.hasSuffix(".tip") { XCTAssertLessThanOrEqual(w, 14, "\(lang) \(k)=\(v): column header too wide") }
                if k.hasPrefix("button.") { XCTAssertLessThanOrEqual(w, 28, "\(lang) \(k)=\(v): button title too long") }
                if k.hasPrefix("menu.") { XCTAssertLessThanOrEqual(w, 40, "\(lang) \(k)=\(v): menu title too long") }
                if k.hasPrefix("progress.title") || k == "window.title" { XCTAssertLessThanOrEqual(w, 24, "\(lang) \(k)") }
            }
            XCTAssertLessThanOrEqual(Self.width(t["chart.empty"]!), 34, "\(lang) empty-state title fits one or two lines")
            XCTAssertLessThanOrEqual(Self.width(t["volume.hint"]!), 80, "\(lang) sidebar hint stays short")
        }
        XCTAssertEqual(Self.width("占用空间"), 8); XCTAssertEqual(Self.width("On Disk"), 7)
    }
    func testVolumeIsTranslatedAsDiskEverywhere() throws {
        let zh = try load("zh-Hans")
        for (k, v) in zh { XCTAssertFalse(v.contains("宗卷"), "\(k): use 磁盘 for Volume (R10 terminology)") }
        XCTAssertTrue(zh["volume.hint"]!.contains("点按磁盘")); XCTAssertEqual(zh["home.internalDisk"], "内置磁盘")
        XCTAssertEqual(zh["home.externalDisk"], "外置磁盘"); XCTAssertNotNil(zh["column.onDisk.tip"])
        XCTAssertEqual(zh["chart.empty"], "选择一个磁盘或文件夹开始扫描")
    }
    /// simplify-v2: delete zone never says “drag here”; badge text is unified as 高风险.
    func testDeleteZoneCopyAndBadges() throws {
        let zh = try load("zh-Hans"), en = try load("en")
        for (k, v) in zh { XCTAssertFalse(v.contains("拖"), "\(k)=\(v): no drag wording") }
        for (k, v) in en { XCTAssertFalse(v.lowercased().contains("drag"), "\(k)=\(v): no drag wording") }
        XCTAssertEqual(zh["basket.empty"], "删除区为空 · 在列表中选中项目，按空格或点「加入删除区」")
        XCTAssertEqual(zh["badge.highRisk"], "高风险"); XCTAssertEqual(en["badge.highRisk"], "High Risk")
        XCTAssertEqual(zh["button.addToBasket"], "加入删除区")
        XCTAssertEqual(zh["button.moveToTrash"], "移到废纸篓…"); XCTAssertEqual(zh["button.deletePermanently"], "永久删除…")
        for k in ["chart.caution", "mode.reclaimable", "dash.reclaimable", "danger.empty"] { XCTAssertNil(zh[k], "\(k) removed") }
    }
}

final class AppearancePreferenceTests: XCTestCase {
    func suite() -> UserDefaults {
        let name = "DiskRingsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    func testRawValueRoundTripAndMenuKeys() throws {
        for p in AppearancePreference.allCases { XCTAssertEqual(AppearancePreference(rawValue: p.rawValue), p) }
        XCTAssertEqual(AppearancePreference.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertEqual(AppearancePreference.defaultsKey, "DiskRingsAppearance")
        for lang in ["en", "zh-Hans"] {
            let t = try StringsFile.parse(String(contentsOf: LocalizationTests.root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8))
            XCTAssertNotNil(t["menu.appearance"], lang)
            for p in AppearancePreference.allCases { XCTAssertNotNil(t[p.menuKey], "\(lang) \(p.menuKey)") }
        }
        let zh = try StringsFile.parse(String(contentsOf: LocalizationTests.root.appendingPathComponent("Resources/zh-Hans.lproj/Localizable.strings"), encoding: .utf8))
        XCTAssertEqual([zh["menu.appearance"], zh["menu.appearance.system"], zh["menu.appearance.light"], zh["menu.appearance.dark"]],
                       ["外观", "跟随系统", "浅色", "深色"])
    }
    func testResolvedAppearanceThreeModes() {
        // Follow system → nil (NSApp.appearance = nil); light/dark → fixed Aqua names.
        XCTAssertNil(AppearancePreference.system.resolvedAppearance)
        XCTAssertEqual(AppearancePreference.light.resolvedAppearance, .aqua)
        XCTAssertEqual(AppearancePreference.dark.resolvedAppearance, .darkAqua)
        XCTAssertEqual(
            AppearancePreference.allCases.map { $0.resolvedAppearance?.rawValue },
            [nil, "aqua", "darkAqua"])
    }
    func testPersistenceAndFallback() {
        let d = suite()
        XCTAssertEqual(AppearancePreference.load(from: d), .system, "nothing stored -> system")
        AppearancePreference.dark.save(to: d)
        XCTAssertEqual(AppearancePreference.load(from: d), .dark)
        XCTAssertEqual(d.string(forKey: "DiskRingsAppearance"), "dark")
        AppearancePreference.light.save(to: d)
        XCTAssertEqual(AppearancePreference.load(from: d), .light)
        d.set("sepia", forKey: AppearancePreference.defaultsKey)
        XCTAssertEqual(AppearancePreference.load(from: d), .system, "unknown stored value -> system")
        d.set(42, forKey: AppearancePreference.defaultsKey)
        XCTAssertEqual(AppearancePreference.load(from: d), .system, "wrong type -> system")
    }
}
