import XCTest
@testable import SOOM

final class Feed61OwnPhotoPolicyTests: XCTestCase {
    func testAuthorizedPhotosPreserveExactReferences() {
        let photo = WorkoutPhotoReference(id: UUID(), storagePath: "invalid-reference-is-not-authority")
        XCTAssertEqual(Feed61OwnedPhotoPresentation.authorized([photo]).photos, [photo])
        // Presentation does not forge authority or normalize untrusted paths.
        XCTAssertNil(Feed61OwnedPhotoPresentation.authorized([photo]).photos.first?.profileAuthority)
    }
    func testUnavailableSuppliesNoPhotos() {
        XCTAssertTrue(Feed61OwnedPhotoPresentation.unavailable.photos.isEmpty)
    }
    func testAuthorizedEmptyRemainsDistinctFromUnavailable() {
        XCTAssertNotEqual(Feed61OwnedPhotoPresentation.authorized([]), .unavailable)
    }
    func testExplicitUnavailableIsNotIndependentDefault() {
        let value: Feed61OwnedPhotoPresentation? = .unavailable
        XCTAssertNotNil(value)
        XCTAssertTrue(value?.photos.isEmpty == true)
    }
    func testIndependentDefaultIsNil() {
        let value: Feed61OwnedPhotoPresentation? = nil
        XCTAssertNil(value)
    }
}
