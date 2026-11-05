import XCTest
@testable import TenderCore

final class AccountProfileMetadataTests: XCTestCase {
    func testMemberSinceUsesAccountCreationInsteadOfLastLogin() throws {
        let metadata = AccountProfileMetadata(firebaseUser: ["displayName": "  Test Member  ", "createdAt": "1609502400000", "lastLoginAt": "1793358000000"])
        XCTAssertEqual(metadata.displayName, "Test Member")
        XCTAssertEqual(try XCTUnwrap(metadata.memberSince).timeIntervalSince1970, 1_609_502_400)
        XCTAssertNil(AccountProfileMetadata(firebaseUser: ["lastLoginAt": "1793358000000"]).memberSince)
        for raw in ["NaN", "Infinity", "-1", "invalid", "99999999999999999999"] {
            XCTAssertNil(AccountProfileMetadata(firebaseUser: ["createdAt": raw]).memberSince)
        }
    }
    func testDisplayNameAndMembershipCacheDecodeOlderSessionsSafely() throws {
        let original = AccountProfileMetadata(displayName: "Test Member", memberSince: Date(timeIntervalSince1970: 1_609_502_400))
        XCTAssertEqual(try JSONDecoder().decode(AccountProfileMetadata.self, from: JSONEncoder().encode(original)), original)
        XCTAssertNil(try JSONDecoder().decode(AccountProfileMetadata.self, from: Data("{}".utf8)).memberSince)
        XCTAssertNil(AccountProfileMetadata(firebaseUser: ["displayName": " \n "]).displayName)
        XCTAssertNil(AccountProfileMetadata(firebaseUser: ["displayName": "Test\nMember"]).displayName)
    }
    func testLocalProfileNameSurvivesBackupAndRejectsInvalidNames() throws {
        var ledger = Ledger.empty(); ledger.profileName = "Test Member"
        let backup = try LedgerArchive(ledger: ledger, attachments: [:]).validated()
        XCTAssertEqual(try JSONDecoder.tender.decode(LedgerArchive.self, from: JSONEncoder.tender.encode(backup)).ledger.profileName, "Test Member")
        for invalid in [" ", "Test\nMember", String(repeating: "a", count: 81)] {
            ledger.profileName = invalid
            XCTAssertThrowsError(try ledger.validated())
        }
    }
}
