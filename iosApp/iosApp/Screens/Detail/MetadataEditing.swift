import Foundation

/// Server permission exposed by `/api/v1/auth/me` for delegated metadata edits.
enum MetadataEditAuthorization {
    static let permission = "metadata_curation"

    /// Admins may curate only while acting through the primary profile. A
    /// non-admin may curate when the account has the delegated permission; the
    /// server remains authoritative for library and access-group restrictions.
    static func canEdit(
        isAdmin: Bool,
        permissions: [String],
        activeProfileIsPrimary: Bool
    ) -> Bool {
        if isAdmin {
            return activeProfileIsPrimary
        }
        return permissions.contains(permission)
    }
}

/// The subset of item detail needed to seed the first iOS metadata editor.
/// Keeping this independent of SwiftUI makes its diff/validation logic easy to
/// exercise without a view hierarchy.
struct MetadataEditableItem: Equatable {
    let type: String
    let title: String
    let sortTitle: String?
    let originalTitle: String?
    let overview: String?
    let tagline: String?
    let contentRating: String?
    let year: Int?
    let runtime: Int?
    let genres: [String]
    let studios: [String]
    let networks: [String]
    let countries: [String]
    let lockedFields: [Int]
    let tracksLocks: Bool

    init(
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
        lockedFields: [Int] = [],
        tracksLocks: Bool = true
    ) {
        self.type = type
        self.title = title
        self.sortTitle = sortTitle
        self.originalTitle = originalTitle
        self.overview = overview
        self.tagline = tagline
        self.contentRating = contentRating
        self.year = year
        self.runtime = runtime
        self.genres = genres
        self.studios = studios
        self.networks = networks
        self.countries = countries
        self.lockedFields = lockedFields
        self.tracksLocks = tracksLocks
    }

    static func supports(_ type: String) -> Bool {
        ["movie", "series", "season", "episode"].contains(type)
    }
}

/// PATCH body accepted by `/api/v1/admin/items/{id}/metadata`.
struct UpdateItemMetadataRequest: Encodable, Equatable {
    var title: String?
    var sortTitle: String?
    var originalTitle: String?
    var overview: String?
    var tagline: String?
    var contentRating: String?
    var year: Int?
    var runtime: Int?
    var genres: [String]?
    var studios: [String]?
    var networks: [String]?
    var countries: [String]?
    var lockedFields: [Int]?

    var isEmpty: Bool {
        title == nil
            && sortTitle == nil
            && originalTitle == nil
            && overview == nil
            && tagline == nil
            && contentRating == nil
            && year == nil
            && runtime == nil
            && genres == nil
            && studios == nil
            && networks == nil
            && countries == nil
            && lockedFields == nil
    }
}

enum MetadataEditValidationError: LocalizedError, Equatable {
    case titleRequired
    case invalidYear
    case invalidRuntime

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            return "Title is required."
        case .invalidYear:
            return "Enter a year from 1800 through 2200, or leave it blank to clear it."
        case .invalidRuntime:
            return "Enter a runtime from 1 through 10,000 minutes, or leave it blank to clear it."
        }
    }
}

/// Editable text plus deterministic diffing against the detail payload that
/// opened the sheet. Only changed fields are sent. Provider-backed fields on
/// movies and series are automatically locked when first edited, matching the
/// web editor so a future metadata refresh does not overwrite manual changes.
struct MetadataEditDraft {
    private enum Lock: Int {
        case name = 0
        case overview = 1
        case genres = 2
        case studios = 3
        case runtime = 7
        case tags = 8
        case contentRating = 9
        case releaseDates = 13
    }

    private let original: MetadataEditableItem

    var title: String
    var sortTitle: String
    var originalTitle: String
    var overview: String
    var tagline: String
    var contentRating: String
    var year: String
    var runtime: String
    var genres: String
    var studios: String
    var networks: String
    var countries: String

    init(item: MetadataEditableItem) {
        original = item
        title = item.title
        sortTitle = item.sortTitle ?? ""
        originalTitle = item.originalTitle ?? ""
        overview = item.overview ?? ""
        tagline = item.tagline ?? ""
        contentRating = item.contentRating ?? ""
        year = item.year.map(String.init) ?? ""
        runtime = item.runtime.map(String.init) ?? ""
        genres = item.genres.joined(separator: ", ")
        studios = item.studios.joined(separator: ", ")
        networks = item.networks.joined(separator: ", ")
        countries = item.countries.joined(separator: ", ")
    }

    var hasChanges: Bool {
        do {
            return try makeUpdateRequest() != nil
        } catch {
            return true
        }
    }

    func makeUpdateRequest() throws -> UpdateItemMetadataRequest? {
        let normalizedTitle = normalizedText(title)
        guard !normalizedTitle.isEmpty else {
            throw MetadataEditValidationError.titleRequired
        }

        let parsedYear = try parseOptionalYear(year)
        let parsedRuntime = try parseOptionalRuntime(runtime)
        let parsedGenres = normalizedList(genres)
        let parsedStudios = normalizedList(studios)
        let parsedNetworks = normalizedList(networks)
        let parsedCountries = normalizedList(countries)

        var request = UpdateItemMetadataRequest()
        var editedLocks = Set<Int>()

        assignText(
            normalizedTitle,
            original: original.title,
            to: &request.title,
            lock: .name,
            editedLocks: &editedLocks
        )
        assignText(
            normalizedText(sortTitle),
            original: original.sortTitle,
            to: &request.sortTitle,
            lock: .name,
            editedLocks: &editedLocks
        )
        assignText(
            normalizedText(originalTitle),
            original: original.originalTitle,
            to: &request.originalTitle,
            lock: .name,
            editedLocks: &editedLocks
        )
        assignText(
            normalizedText(overview),
            original: original.overview,
            to: &request.overview,
            lock: .overview,
            editedLocks: &editedLocks
        )
        assignText(
            normalizedText(tagline),
            original: original.tagline,
            to: &request.tagline,
            lock: .name,
            editedLocks: &editedLocks
        )
        assignText(
            normalizedText(contentRating),
            original: original.contentRating,
            to: &request.contentRating,
            lock: .contentRating,
            editedLocks: &editedLocks
        )

        if parsedYear != (original.year ?? 0) {
            request.year = parsedYear
            editedLocks.insert(Lock.releaseDates.rawValue)
        }
        if parsedRuntime != (original.runtime ?? 0) {
            request.runtime = parsedRuntime
            editedLocks.insert(Lock.runtime.rawValue)
        }
        assignList(
            parsedGenres,
            original: original.genres,
            to: &request.genres,
            lock: .genres,
            editedLocks: &editedLocks
        )
        assignList(
            parsedStudios,
            original: original.studios,
            to: &request.studios,
            lock: .studios,
            editedLocks: &editedLocks
        )
        assignList(
            parsedNetworks,
            original: original.networks,
            to: &request.networks,
            lock: .studios,
            editedLocks: &editedLocks
        )
        assignList(
            parsedCountries,
            original: original.countries,
            to: &request.countries,
            lock: .tags,
            editedLocks: &editedLocks
        )

        if original.tracksLocks {
            let originalLocks = Set(original.lockedFields)
            let resultingLocks = originalLocks.union(editedLocks)
            if resultingLocks != originalLocks {
                request.lockedFields = resultingLocks.sorted()
            }
        }

        return request.isEmpty ? nil : request
    }

    private func assignText(
        _ current: String,
        original originalValue: String?,
        to target: inout String?,
        lock: Lock,
        editedLocks: inout Set<Int>
    ) {
        guard current != normalizedText(originalValue ?? "") else { return }
        target = current
        editedLocks.insert(lock.rawValue)
    }

    private func assignList(
        _ current: [String],
        original originalValue: [String],
        to target: inout [String]?,
        lock: Lock,
        editedLocks: inout Set<Int>
    ) {
        guard current != originalValue else { return }
        target = current
        editedLocks.insert(lock.rawValue)
    }

    private func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedList(_ value: String) -> [String] {
        var seen = Set<String>()
        return value
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { normalizedText(String($0)) }
            .filter { entry in
                guard !entry.isEmpty else { return false }
                return seen.insert(entry.lowercased()).inserted
            }
    }

    private func parseOptionalYear(_ value: String) throws -> Int {
        let value = normalizedText(value)
        if value.isEmpty { return 0 }
        guard let year = Int(value), (1800...2200).contains(year) else {
            throw MetadataEditValidationError.invalidYear
        }
        return year
    }

    private func parseOptionalRuntime(_ value: String) throws -> Int {
        let value = normalizedText(value)
        if value.isEmpty { return 0 }
        guard let runtime = Int(value), (1...10_000).contains(runtime) else {
            throw MetadataEditValidationError.invalidRuntime
        }
        return runtime
    }
}
