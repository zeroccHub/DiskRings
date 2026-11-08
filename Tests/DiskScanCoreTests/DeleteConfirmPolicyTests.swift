import XCTest
@testable import DiskScanCore

final class DeleteConfirmPolicyTests: XCTestCase {
    func makeItems(highRisk: Int, normal: Int) -> [DeleteConfirmPolicy.Item] {
        var items: [DeleteConfirmPolicy.Item] = []
        for i in 0..<highRisk {
            items.append(.init(id: "/hr\(i)", name: "H\(i)", path: "/hr\(i)", bytes: 100,
                               isHighRisk: true, riskReasons: ["appBundle"]))
        }
        for i in 0..<normal {
            items.append(.init(id: "/n\(i)", name: "N\(i)", path: "/n\(i)", bytes: 50,
                               isHighRisk: false, riskReasons: []))
        }
        return items
    }

    func testPhraseIsFixedAndCountIndependent() {
        XCTAssertEqual(DeleteConfirmPolicy.typeConfirmPhrase(languageIsChinese: true), "永久删除")
        XCTAssertEqual(DeleteConfirmPolicy.typeConfirmPhrase(languageIsChinese: false), "Delete Permanently")
    }

    func testPermanentAlwaysRequiresTypingEvenWithoutHighRisk() {
        var snap = DeleteConfirmPolicy.Snapshot(items: makeItems(highRisk: 2, normal: 3), method: .trash)
        XCTAssertEqual(DeleteConfirmPolicy.secondaryConfirm(for: snap, languageIsChinese: true), .none)
        snap.method = .permanent
        XCTAssertEqual(DeleteConfirmPolicy.secondaryConfirm(for: snap, languageIsChinese: true), .typePhrase("永久删除"))
        snap = DeleteConfirmPolicy.Snapshot(items: makeItems(highRisk: 0, normal: 2), method: .permanent)
        XCTAssertEqual(DeleteConfirmPolicy.secondaryConfirm(for: snap, languageIsChinese: false), .typePhrase("Delete Permanently"))
    }

    func testReturnKeyDisabledWhenPermanent() {
        XCTAssertTrue(DeleteConfirmPolicy.returnKeyTriggersPrimary(method: .trash))
        XCTAssertFalse(DeleteConfirmPolicy.returnKeyTriggersPrimary(method: .permanent))
    }

    func testPrimaryEnabledOnlyOnExactMatch() {
        for hr in [0, 1] {
            var snap = DeleteConfirmPolicy.Snapshot(items: makeItems(highRisk: hr, normal: 1 - hr), method: .permanent)
            for wrong in ["", "永久", "永久删除 ", " 永久删除", "delete permanently", "删除 1 项"] {
                XCTAssertFalse(DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: wrong, languageIsChinese: true), wrong)
            }
            XCTAssertTrue(DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: "永久删除", languageIsChinese: true))
            XCTAssertTrue(DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: "Delete Permanently", languageIsChinese: false))
            snap.method = .trash
            XCTAssertTrue(DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: "", languageIsChinese: false))
        }
    }

    func testCheckboxFilteringAndMethodSwitch() {
        var snap = DeleteConfirmPolicy.Snapshot(items: makeItems(highRisk: 1, normal: 2), method: .trash)
        XCTAssertEqual(snap.checkedCount, 3)
        snap = DeleteConfirmPolicy.settingChecked(id: "/hr0", checked: false, in: snap)
        XCTAssertEqual(snap.checkedCount, 2)
        XCTAssertEqual(snap.checkedHighRiskCount, 0)
        snap = DeleteConfirmPolicy.settingMethod(.permanent, in: snap)
        XCTAssertEqual(DeleteConfirmPolicy.secondaryConfirm(for: snap, languageIsChinese: true), .typePhrase("永久删除"))
        XCTAssertEqual(snap.checkedBytes, 100)
    }

    func testHighRiskGroupingAndBuild() {
        let app = FileNode(name: "/Applications/Xcode.app", kind: .directory, logicalSize: 10, allocatedSize: 10, actualSize: 10)
        let caches = FileNode(name: "/Users/tester/Library/Caches", kind: .directory, logicalSize: 5, allocatedSize: 5, actualSize: 5)
        let prefs = FileNode(name: "/Users/tester/Library/Preferences", kind: .directory, logicalSize: 2, allocatedSize: 2, actualSize: 2)
        let snap = DeleteConfirmPolicy.build(
            nodes: [app, caches, prefs],
            excluded: [],
            homeDirectory: "/Users/tester",
            preferredMethod: .trash)
        XCTAssertEqual(snap.highRiskItems.count, 2) // app + prefs
        XCTAssertEqual(snap.normalItems.count, 1)   // caches NOT high-risk
        XCTAssertTrue(snap.items.first { $0.path.contains("Xcode.app") }?.isHighRisk == true)
        XCTAssertTrue(snap.items.first { $0.path.hasSuffix("Preferences") }?.isHighRisk == true)
        XCTAssertFalse(snap.items.first { $0.path.hasSuffix("Caches") }?.isHighRisk == true)
        XCTAssertEqual(DeleteConfirmPolicy.consequenceKey(for: ["appBundle"]), "confirm.consequence.app")
        XCTAssertEqual(DeleteConfirmPolicy.consequenceKey(for: ["library"]), "confirm.consequence.library")
        XCTAssertEqual(DeleteConfirmPolicy.consequenceKey(for: ["hidden"]), "confirm.consequence.hidden")
        XCTAssertEqual(DeleteConfirmPolicy.consequenceKey(for: ["over50GB"]), "confirm.consequence.large")
    }

    func testEmptyCheckedDisablesPrimary() {
        var snap = DeleteConfirmPolicy.Snapshot(items: makeItems(highRisk: 0, normal: 1), method: .trash)
        snap = DeleteConfirmPolicy.settingChecked(id: "/n0", checked: false, in: snap)
        XCTAssertFalse(DeleteConfirmPolicy.primaryEnabled(snapshot: snap, typedText: "", languageIsChinese: false))
    }
}
