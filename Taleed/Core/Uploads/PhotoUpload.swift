import Foundation
import UIKit

/// What an upload is for (`POST /uploads?purpose=`). A key only works where its purpose says.
enum UploadPurpose: String, CaseIterable, Sendable {
    /// `photos[].key` of `POST /listings` and `PATCH /listings/{id}`.
    case listingPhoto = "listing_photo"
    /// `photoKey` of `POST /conversations/{id}/messages`.
    case chatPhoto = "chat_photo"
    /// `evidenceKeys` of `POST /reports`.
    case reportEvidence = "report_evidence"
    /// `photoKeys` of `POST /orders/{id}/dispute` and `POST /disputes/{id}/messages`.
    case disputeEvidence = "dispute_evidence"
    /// `avatarKey` of `PATCH /me`.
    case avatar
    /// `documentKey` of `POST /me/verification`. Never kept on the device (app-guidelines, Identity documents).
    case idDocument = "id_document"

    /// The box the photo is scaled down to fit, width × height in pixels (api-guide.md, Uploads).
    var maxPixelSize: CGSize {
        switch self {
        case .listingPhoto: CGSize(width: 1200, height: 1600)
        case .avatar: CGSize(width: 800, height: 800)
        case .chatPhoto, .reportEvidence, .disputeEvidence, .idDocument: CGSize(width: 1600, height: 1600)
        }
    }
}

/// An uploaded file: send `key` with what uses it, show `thumbURL` while editing.
struct UploadedPhoto: Equatable, Sendable {
    let key: String
    let url: URL?
    let thumbURL: URL?
}

/// Prepares photos for upload: upright, scaled down to the purpose's box, JPEG at 85 %. HEIC and any
/// other format the system decodes come out as JPEG, which the API accepts.
enum PhotoPreparer {
    static let jpegQuality: CGFloat = 0.85
    /// The API refuses files over 10 MB (`413 file_too_large`).
    static let maxBytes = 10 * 1024 * 1024

    enum Failure: Error, Equatable {
        /// The data is not an image the system can decode.
        case notAnImage
        /// Still over 10 MB after scaling down (only a pathological image).
        case tooLarge
    }

    /// The size that fits `size` within `box`, never larger than the original.
    static func fittedSize(_ size: CGSize, within box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let scale = min(1, box.width / size.width, box.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Picked data (`PhotosPickerItem.loadTransferable(type: Data.self)`, the camera…) as upload-ready JPEG.
    static func jpegData(from data: Data, purpose: UploadPurpose) throws(Failure) -> Data {
        guard let image = UIImage(data: data) else { throw .notAnImage }
        return try jpegData(from: image, purpose: purpose)
    }

    static func jpegData(from image: UIImage, purpose: UploadPurpose) throws(Failure) -> Data {
        // `UIImage.size` is in points and already upright; with scale 1 a point is a pixel.
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let target = fittedSize(pixelSize, within: purpose.maxPixelSize)
        let format = UIGraphicsImageRendererFormat()
        // The screen's scale would double or triple the pixels.
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: jpegQuality) else { throw .notAnImage }
        guard jpeg.count <= maxBytes else { throw .tooLarge }
        return jpeg
    }

    /// Writes upload-ready JPEG to a temporary file, which the uploader deletes once sent. Excluded from
    /// backups (ID documents must never be kept).
    static func temporaryFile(for jpeg: Data) throws -> URL {
        var url = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString).jpg")
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }
}

/// Uploads photos: prepares them, sends `POST /uploads`, and deletes the temporary file whatever the
/// answer. Use one per screen; each call is independent (a retry makes a new upload, and an unused
/// one does no harm).
@MainActor
final class PhotoUploadService {
    private let api: UploadsApi

    init(api: UploadsApi) {
        self.api = api
    }

    /// Uploads picked image data (HEIC included) for `purpose`.
    func upload(_ data: Data, purpose: UploadPurpose) async throws(ApiError) -> UploadedPhoto {
        // Decoding and scaling a camera original takes a moment: off the main thread.
        let prepared = await Task.detached(priority: .userInitiated) {
            Result { () throws(PhotoPreparer.Failure) -> Data in try PhotoPreparer.jpegData(from: data, purpose: purpose) }
        }.value
        switch prepared {
        case let .success(jpeg): return try await upload(jpeg: jpeg, purpose: purpose)
        case let .failure(failure): throw Self.localError(failure)
        }
    }

    /// Uploads an image already in memory (camera capture) for `purpose`.
    func upload(_ image: UIImage, purpose: UploadPurpose) async throws(ApiError) -> UploadedPhoto {
        let jpeg: Data
        do {
            jpeg = try PhotoPreparer.jpegData(from: image, purpose: purpose)
        } catch {
            throw Self.localError(error)
        }
        return try await upload(jpeg: jpeg, purpose: purpose)
    }

    private func upload(jpeg: Data, purpose: UploadPurpose) async throws(ApiError) -> UploadedPhoto {
        let file: URL
        do {
            file = try PhotoPreparer.temporaryFile(for: jpeg)
        } catch {
            throw .unknown(status: 0, code: nil)
        }
        defer { try? FileManager.default.removeItem(at: file) }
        return try await api.upload(file: file, purpose: purpose)
    }

    /// A photo the device could not prepare reads like the API's answer for it.
    private static func localError(_ failure: PhotoPreparer.Failure) -> ApiError {
        switch failure {
        case .notAnImage: .failed(ApiFailure(status: 415, code: .unsupportedMediaType))
        case .tooLarge: .failed(ApiFailure(status: 413, code: .fileTooLarge))
        }
    }
}
