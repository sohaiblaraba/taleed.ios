import Foundation
import Observation

/// Search by photo (slice B, screens.md §2 G3 screen 5): the picked photo goes out as a JPEG scaled
/// like a listing photo, in the `photo` part of `POST /visual-searches`, while the sheet shows the
/// photo and the website's rotating steps. Retrying sends the same photo again (a failed search is not
/// kept).
@MainActor
@Observable
final class VisualSearchModel {
    enum Phase: Equatable {
        /// Choose a photo (camera or library).
        case pick
        case searching
        /// The search failed; `canRetry` when sending the same photo again may work.
        case failed(ApiError, canRetry: Bool)
    }

    /// How a search ended.
    enum Outcome: Equatable {
        /// The results screen of this search.
        case found(id: String)
        /// `503 feature_disabled`: Taleed turned photo search off meanwhile.
        case disabled
        /// The sheet shows the error.
        case failed
    }

    private(set) var phase: Phase = .pick
    /// The photo being searched, for the preview.
    private(set) var photo: Data?

    @ObservationIgnored private let api: ExploreApi

    init(api: ExploreApi) {
        self.api = api
    }

    var isSearching: Bool { phase == .searching }

    /// Searches `data` (picked or taken; HEIC included).
    func search(_ data: Data) async -> Outcome {
        photo = data
        return await run(data)
    }

    /// Sends the same photo again.
    func retry() async -> Outcome {
        guard let photo else { return .failed }
        return await run(photo)
    }

    /// The picked or taken photo could not be read before any search: an iCloud photo that cannot
    /// download (offline) says so with the network message; a photo the device cannot hand over says it
    /// is not supported (as the API's `415`). The member picks a photo again (the sheet keeps its
    /// buttons).
    func photoUnreadable(downloadFailed: Bool) {
        guard !isSearching else { return }
        photo = nil
        let error: ApiError = downloadFailed ? .network : .failed(ApiFailure(status: 415, code: .unsupportedMediaType))
        phase = .failed(error, canRetry: false)
    }

    /// Back to choosing a photo (the sheet closed).
    func reset() {
        guard !isSearching else { return }
        phase = .pick
        photo = nil
    }

    private func run(_ data: Data) async -> Outcome {
        phase = .searching
        do {
            let file = try await Self.prepare(data)
            defer { try? FileManager.default.removeItem(at: file) }
            let search = try await api.createVisualSearch(photo: file)
            phase = .pick
            return .found(id: search.id)
        } catch {
            return fail(error)
        }
    }

    private func fail(_ error: ApiError) -> Outcome {
        if error.code == .featureDisabled {
            phase = .pick
            return .disabled
        }
        phase = .failed(error, canRetry: Self.canRetry(error))
        return .failed
    }

    /// No answer, or the server could not analyze the photo: the same photo may work on a retry. A photo
    /// too large or in a format the API refuses needs another photo.
    static func canRetry(_ error: ApiError) -> Bool {
        switch error.code {
        case .fileTooLarge, .unsupportedMediaType, .invalidRequest: false
        default: error.isTransient || (error.status ?? 0) >= 500 || error.code == .rateLimited
        }
    }

    /// Upright JPEG at 85 %, within 1200 × 1600 like a listing photo, in a temporary file the caller
    /// deletes. A photo the device cannot read fails like the API would (`415`, `413`).
    private static func prepare(_ data: Data) async throws(ApiError) -> URL {
        let prepared = await Task.detached(priority: .userInitiated) {
            Result { () throws(PhotoPreparer.Failure) -> Data in try PhotoPreparer.jpegData(from: data, purpose: .listingPhoto) }
        }.value
        switch prepared {
        case let .success(jpeg):
            do {
                return try PhotoPreparer.temporaryFile(for: jpeg)
            } catch {
                throw .unknown(status: 0, code: nil)
            }
        case .failure(.notAnImage):
            throw .failed(ApiFailure(status: 415, code: .unsupportedMediaType))
        case .failure(.tooLarge):
            throw .failed(ApiFailure(status: 413, code: .fileTooLarge))
        }
    }
}

/// The results of a photo search (`GET /visual-searches/{id}`): the analyzed photo, whether the matches
/// are weak, and the items, 24 a page, 48 at most. After 24 hours the API answers `404`: the screen
/// offers a new search.
@MainActor
@Observable
final class VisualSearchResultsViewModel {
    let id: String
    let results: PagedList<ListingSummary>
    /// From the last page received.
    var photoURL: URL? { details.photoURL }
    var weakMatch: Bool { details.weakMatch }

    @ObservationIgnored private let details: VisualSearchDetails

    init(id: String, api: ExploreApi) {
        self.id = id
        let details = VisualSearchDetails()
        self.details = details
        results = PagedList { [api, details] cursor throws(ApiError) in
            let search = try await api.visualSearch(id: id, cursor: cursor)
            details.photoURL = search.photoURL
            details.weakMatch = search.weakMatch
            return search.page
        }
    }

    /// The search expired (or never existed): start a new one.
    var hasExpired: Bool { results.error?.isNotFound ?? false }
}

@MainActor
@Observable
private final class VisualSearchDetails {
    var photoURL: URL?
    var weakMatch = false
}
