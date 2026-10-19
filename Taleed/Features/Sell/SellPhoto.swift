import Foundation
import UIKit

/// Where a photo's upload stands.
enum SellPhotoUpload {
    case uploading
    case uploaded(UploadedPhoto)
    case failed(ApiError)
    /// Edit form: a photo the listing already has (sent back as `{id}`).
    case kept(ListingPhoto)
}

/// A photo of the sell form: a picked one (its preview, what was picked to send it again, and its
/// upload) or, on the edit form, one the listing has.
struct SellPhoto: Identifiable {
    let id = UUID()
    var preview: UIImage?
    /// The picked data, kept to upload the photo again (a failure, or a key the API refused). Nil for a
    /// photo the listing has.
    let data: Data?
    var upload: SellPhotoUpload

    init(data: Data) {
        self.data = data
        upload = .uploading
    }

    init(kept photo: ListingPhoto) {
        data = nil
        upload = .kept(photo)
    }

    var key: String? {
        if case let .uploaded(photo) = upload { return photo.key }
        return nil
    }

    /// The photo as the request sends it: a new upload's key, or the id of a photo the listing has.
    /// Nil while it uploads or after its upload failed.
    var reference: ListingPhotoRef? {
        switch upload {
        case let .uploaded(photo): .added(key: photo.key)
        case let .kept(photo): .kept(id: photo.id)
        case .uploading, .failed: nil
        }
    }

    var isUploading: Bool {
        if case .uploading = upload { return true }
        return false
    }

    var error: ApiError? {
        if case let .failed(error) = upload { return error }
        return nil
    }

    /// Failed, and sending the same photo again may work (no answer, a server failure, a rate limit).
    /// Too large, a format the API refuses, unreadable: only removing it helps.
    var canRetry: Bool { data != nil && (error?.canRetrySamePhoto ?? false) }
}

/// What Save on the edit form ended with (screens.md §2 G8).
enum ListingSaveOutcome: Equatable {
    /// Saved: the listing as the API answered.
    case saved(ListingDetail)
    /// A field or the API refused it: the errors are on screen (or above the button).
    case refused
    /// `body.photos.<n>.id`: the listing was edited somewhere else. Reload it into the form.
    case listingChanged
    /// The listing cannot change anymore (`listing_locked`), or is not the member's (`forbidden`): show
    /// the message and leave the form.
    case cannotEdit(ApiError)
    /// The listing is gone (`404`).
    case gone
}
