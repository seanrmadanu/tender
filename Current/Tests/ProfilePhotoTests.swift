import XCTest
@testable import TenderCore

final class ProfilePhotoTests: XCTestCase {
    func testAspectFillCropsPortraitAndLandscapeWithoutBlankEdges() throws {
        let landscape = try XCTUnwrap(ProfilePhotoCrop().sourceRectangle(width: 900, height: 600))
        XCTAssertEqual(landscape.x, 150); XCTAssertEqual(landscape.y, 0); XCTAssertEqual(landscape.side, 600)
        let portrait = try XCTUnwrap(ProfilePhotoCrop().sourceRectangle(width: 600, height: 900))
        XCTAssertEqual(portrait.x, 0); XCTAssertEqual(portrait.y, 150); XCTAssertEqual(portrait.side, 600)
        for (width, height) in [(900.0, 600.0), (600.0, 900.0)] {
            for zoom in [1.0, 2.5, 5.0] {
                for center in [0.0, 0.5, 1.0] {
                    let rect = try XCTUnwrap(ProfilePhotoCrop(zoom: zoom, centerX: center, centerY: center).sourceRectangle(width: width, height: height))
                    XCTAssertGreaterThanOrEqual(rect.x, -0.0001); XCTAssertGreaterThanOrEqual(rect.y, -0.0001)
                    XCTAssertLessThanOrEqual(rect.x + rect.side, width + 0.0001)
                    XCTAssertLessThanOrEqual(rect.y + rect.side, height + 0.0001)
                    XCTAssertEqual(rect.side, min(width, height) / zoom)
                }
            }
        }
    }
    func testZoomAndPositionStayInBoundsAndInvalidGeometryIsRejected() {
        let crop = ProfilePhotoCrop(zoom: 50, centerX: -100, centerY: 100).constrained(width: 900, height: 600)
        XCTAssertTrue(crop.isValid); XCTAssertEqual(crop.zoom, 5)
        XCTAssertEqual(crop.centerX, 60.0 / 900.0); XCTAssertEqual(crop.centerY, 0.9)
        XCTAssertNil(ProfilePhotoCrop(zoom: .nan).sourceRectangle(width: 100, height: 100))
        XCTAssertNil(ProfilePhotoCrop().sourceRectangle(width: 0, height: 100))
    }
    func testBothImagesAndCropSurviveBackupAndRestoreFileRenaming() throws {
        var ledger = Ledger.empty()
        let crop = ProfilePhotoCrop(zoom: 2, centerX: 0.6, centerY: 0.4)
        ledger.profilePhoto = ProfilePhoto(originalImage: "original.jpg", croppedImage: "avatar.jpg", crop: crop)
        XCTAssertEqual(ledger.attachmentNames, ["original.jpg", "avatar.jpg"])
        let backup = try LedgerArchive(ledger: ledger, attachments: ["original.jpg": Data([1]), "avatar.jpg": Data([2])]).validated()
        let restored = try JSONDecoder.tender.decode(LedgerArchive.self, from: JSONEncoder.tender.encode(backup))
        ledger = restored.ledger
        ledger.renameAttachments(["original.jpg": "restored-original.jpg", "avatar.jpg": "restored-avatar.jpg"])
        XCTAssertEqual(ledger.profilePhoto?.crop, crop)
        XCTAssertEqual(ledger.attachmentNames, ["restored-original.jpg", "restored-avatar.jpg"])
        ledger.profilePhoto = nil
        XCTAssertTrue(ledger.attachmentNames.isEmpty)
    }
    func testUnsafeNamesInvalidCropsAndIncompletePhotoBackupsAreRejected() throws {
        var ledger = Ledger.empty()
        ledger.profilePhoto = ProfilePhoto(originalImage: "../original.jpg", croppedImage: "avatar.jpg", crop: ProfilePhotoCrop())
        XCTAssertThrowsError(try ledger.validated())
        ledger.profilePhoto?.originalImage = "original.jpg"; ledger.profilePhoto?.crop.zoom = 0
        XCTAssertThrowsError(try ledger.validated())
        ledger.profilePhoto?.crop = ProfilePhotoCrop()
        XCTAssertThrowsError(try LedgerArchive(ledger: ledger, attachments: ["avatar.jpg": Data([2])]).validated())
    }
    func testExistingLedgersWithoutAProfileStillDecode() throws {
        let decoded = try JSONDecoder.tender.decode(Ledger.self, from: JSONEncoder.tender.encode(Ledger.empty()))
        XCTAssertNil(decoded.profilePhoto)
    }
}
