import XCTest
@testable import Silo

final class MetadataEditingTests: XCTestCase {
    func testEditorIsAvailableToPrimaryProfileAdmins() {
        XCTAssertTrue(MetadataEditAuthorization.canEdit(
            isAdmin: true,
            permissions: [],
            activeProfileIsPrimary: true
        ))
        XCTAssertFalse(MetadataEditAuthorization.canEdit(
            isAdmin: true,
            permissions: ["metadata_curation"],
            activeProfileIsPrimary: false
        ))
    }

    func testEditorIsAvailableToDelegatedCurators() {
        XCTAssertTrue(MetadataEditAuthorization.canEdit(
            isAdmin: false,
            permissions: ["marker_edit", "metadata_curation"],
            activeProfileIsPrimary: false
        ))
        XCTAssertFalse(MetadataEditAuthorization.canEdit(
            isAdmin: false,
            permissions: ["marker_edit"],
            activeProfileIsPrimary: true
        ))
    }

    func testChangingMovieTitleBuildsMinimalPatchAndLocksName() throws {
        var draft = MetadataEditDraft(item: .fixture(
            type: "movie",
            title: "Old Title",
            lockedFields: [1]
        ))
        draft.title = "New Title"

        let request = try XCTUnwrap(draft.makeUpdateRequest())

        XCTAssertEqual(request.title, "New Title")
        XCTAssertEqual(request.lockedFields, [0, 1])
        XCTAssertNil(request.overview)
        XCTAssertNil(request.year)
        XCTAssertNil(request.genres)
    }

    func testEpisodeOverviewDoesNotSendUnsupportedLocks() throws {
        var draft = MetadataEditDraft(item: .fixture(
            type: "episode",
            title: "Episode",
            overview: "Old overview",
            lockedFields: [1]
        ))
        draft.overview = "New overview"

        let request = try XCTUnwrap(draft.makeUpdateRequest())

        XCTAssertEqual(request.overview, "New overview")
        XCTAssertNil(request.lockedFields)
    }

    func testCommaSeparatedFieldsAreTrimmedDeduplicatedAndLocked() throws {
        var draft = MetadataEditDraft(item: .fixture(
            type: "series",
            title: "Series",
            genres: ["Drama"]
        ))
        draft.genres = "Drama, Mystery, Drama,  Mystery "

        let request = try XCTUnwrap(draft.makeUpdateRequest())

        XCTAssertEqual(request.genres, ["Drama", "Mystery"])
        XCTAssertEqual(request.lockedFields, [2])
    }

    func testBlankTitleIsRejected() {
        var draft = MetadataEditDraft(item: .fixture(type: "movie", title: "Movie"))
        draft.title = "   \n"

        XCTAssertThrowsError(try draft.makeUpdateRequest()) { error in
            XCTAssertEqual(error as? MetadataEditValidationError, .titleRequired)
        }
    }

    func testInvalidNumericValuesAreRejected() {
        var draft = MetadataEditDraft(item: .fixture(type: "movie", title: "Movie", year: 2024))
        draft.year = "twenty twenty-five"

        XCTAssertThrowsError(try draft.makeUpdateRequest()) { error in
            XCTAssertEqual(error as? MetadataEditValidationError, .invalidYear)
        }

        draft.year = "2024"
        draft.runtime = "0"
        XCTAssertThrowsError(try draft.makeUpdateRequest()) { error in
            XCTAssertEqual(error as? MetadataEditValidationError, .invalidRuntime)
        }
    }

    func testUnchangedDraftProducesNoPatch() throws {
        let draft = MetadataEditDraft(item: .fixture(
            type: "movie",
            title: "Movie",
            overview: "Overview",
            year: 2024,
            runtime: 125,
            genres: ["Drama"],
            lockedFields: [0, 1]
        ))

        XCTAssertNil(try draft.makeUpdateRequest())
    }
}

private extension MetadataEditableItem {
    static func fixture(
        type: String,
        title: String,
        sortTitle: String? = nil,
        originalTitle: String? = nil,
        overview: String? = nil,
        tagline: String? = nil,
        contentRating: String? = nil,
        year: Int? = nil,
        runtime: Int? = nil,
        genres: [String] = [],
        studios: [String] = [],
        networks: [String] = [],
        countries: [String] = [],
        lockedFields: [Int] = []
    ) -> MetadataEditableItem {
        MetadataEditableItem(
            type: type,
            title: title,
            sortTitle: sortTitle,
            originalTitle: originalTitle,
            overview: overview,
            tagline: tagline,
            contentRating: contentRating,
            year: year,
            runtime: runtime,
            genres: genres,
            studios: studios,
            networks: networks,
            countries: countries,
            lockedFields: lockedFields,
            tracksLocks: type == "movie" || type == "series"
        )
    }
}
