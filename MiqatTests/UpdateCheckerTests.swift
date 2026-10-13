import XCTest
@testable import Miqat

final class UpdateCheckerTests: XCTestCase {

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "1.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1.0", than: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1", than: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.1", than: "1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0-beta", than: "1.2.0"))
    }

    func testParsesGitHubRelease() throws {
        let json = #"{"tag_name":"v1.2.0","html_url":"https://github.com/HamzaSamirAmmar/miqat/releases/tag/v1.2.0"}"#
        let release = try XCTUnwrap(UpdateChecker.parseRelease(Data(json.utf8)))
        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertEqual(
            UpdateChecker.status(for: release, current: "1.1.0"),
            .available(version: "1.2.0", url: release.url)
        )
        XCTAssertEqual(UpdateChecker.status(for: release, current: "1.2.0"), .upToDate)
    }

    func testRejectsMalformedOrNonHTTPSReleases() {
        XCTAssertNil(UpdateChecker.parseRelease(Data("{}".utf8)))
        XCTAssertNil(UpdateChecker.parseRelease(Data("nope".utf8)))
        let insecure = #"{"tag_name":"v9.0.0","html_url":"http://example.com"}"#
        XCTAssertNil(UpdateChecker.parseRelease(Data(insecure.utf8)))
    }
}
