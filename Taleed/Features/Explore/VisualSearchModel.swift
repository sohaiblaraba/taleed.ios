import Foundation
import Observation

/// Search by photo (slice B, screens.md §2 G3 screen 5): the picked photo goes out as a JPEG scaled
/// like a listing photo, in the `photo` part of `POST /visual-searches`, while the sheet shows the
/// photo and the website's rotating steps. Retrying sends the same photo again (a failed search is not
/// kept).
///
/// The photo goes to Jina AI (slice I): before the first search of an account on this device, the
/// consent step. "Accepter" remembers it for that account, "Annuler" closes the sheet with nothing sent.
/// Every search sends `aiConsent=true`; `400 ai_consent_required` forgets the answer and asks again.
@MainActor
@Observable
final class VisualSearchModel {
    enum Phase: Equatable {
        /// The consent step (no stored consent for this account).
        case consent
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
    @ObservationIgnored private let consent: PhotoSearchConsentStore
    /// The account the sheet opened for (nil signed out: the "guest" consent).
    @ObservationIgnored private var userId: String?

    init(api: ExploreApi, consent: PhotoSearchConsentStore = PhotoSearchConsentStore()) {
        self.api = api
        self.consent = consent
    }

    var isSearching: Bool { phase == .searching }

    /// The sheet opens for this account: the consent step first unless the account agreed on this device.
    func open(userId: String?) {
        guard !isSearching else { return }
        self.userId = userId
        photo = nil
        phase = consent.hasConsent(userId: userId) ? .pick : .consent
    }

    /// "Accepter": remembered for this account, then the photo choice.
    func agreeToConsent() {
        guard phase == .consent else { return }
        consent.agree(userId: userId)
        phase = .pick
    }

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

    /// The sheet closed: the next `open` decides the first step again.
    func reset() {
        guard !isSearching else { return }
        phase = consent.hasConsent(userId: userId) ? .pick : .consent
        photo = nil
    }

    private func run(_ data: Data) async -> Outcome {
        phase = .searching
        do {
            let file = try await Self.prepare(data)
            defer { try? FileManager.default.removeItem(at: file) }
            let search = try await api.createVisualSearch(photo: file, aiConsent: true)
            phase = .pick
            return .found(id: search.id)
        } catch {
            return fail(error)
        }
    }

    private func fail(_ error: ApiError) -> Outcome {
        if error.code == .aiConsentRequired {
            // The server has no consent for this search: forget the stored one and ask again.
            consent.forget(userId: userId)
            photo = nil
            phase = .consent
            return .failed
        }
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
        error.canRetrySamePhoto
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
