import XCTest
@testable import SunburstGeometry

final class SearchFieldConfigTests: XCTestCase {
    typealias C = SearchFieldConfig
    func testLaunchStateHasNoRegexIndicator() {
        XCTAssertFalse(C.addsSubviewsToField)
        XCTAssertFalse(C.launch.regexActive)
        XCTAssertEqual(C.launch.placeholderKey, "search.placeholder")
        XCTAssertEqual(C.launch.toolTipKey, "search.tip.contains")
        XCTAssertNil(C.launch.footerPrefixKey)
        XCTAssertEqual(TreeSearch.Settings.launch.mode, .contains)
    }
    func testMenuToggleShowsRegexInPlaceholderAndFooter() {
        var on = TreeSearch.Settings.launch; on.mode = .regex
        let c = C.make(text: "", settings: on)
        XCTAssertTrue(c.regexActive)
        XCTAssertEqual(c.placeholderKey, "search.placeholder.regex")
        XCTAssertEqual(C.make(text: "abc", settings: on).footerPrefixKey, "search.footer.regexPrefix")
        on.mode = .contains
        XCTAssertEqual(C.make(text: "", settings: on), C.launch)
    }
    func testSlashPatternIsRegexForThatQueryOnly() {
        let c = C.make(text: "/x/", settings: .launch)
        XCTAssertTrue(c.regexActive); XCTAssertEqual(c.toolTipKey, "search.tip.regex")
        XCTAssertEqual(c.placeholderKey, "search.placeholder")       // menu mode unchanged
        XCTAssertEqual(C.make(text: "", settings: .launch), C.launch) // cleared
        XCTAssertFalse(C.make(text: ".*backup.*", settings: .launch).regexActive)
    }
}
