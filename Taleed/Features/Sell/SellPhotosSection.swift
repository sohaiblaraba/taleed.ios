import PhotosUI
import SwiftUI
import UIKit

/// The photos of the sell form: the design-system uploader (variant A, decision D-6) with each photo's
/// upload, the library picker (several at once, in the order picked) and, on a device with a camera,
/// "Prendre une photo" (slice B: photos from the camera or the library).
struct SellPhotosSection: View {
    let model: SellViewModel
    @State private var choosesSource = false
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var pickedItems: [PhotosPickerItem] = []
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            PhotoUploader(
                photos: model.photos.map(uploaderItem),
                onAdd: addPhotos,
                onRemove: { id in UUID(uuidString: id).map(model.remove) },
                onMakeCover: { id in UUID(uuidString: id).map(model.makeCover) },
                onRetry: { id in
                    guard let uuid = UUID(uuidString: id) else { return }
                    Task { await model.retry(uuid) }
                }
            )
            .accessibilityIdentifier("sell.photos")
            if let text = errorText {
                FieldHelper(text: text, color: TaleedColor.feedbackError)
                    .announcesFieldError(text)
            }
        }
        .taleedSheet(isPresented: $choosesSource) { sourceSheet }
        .photosPicker(isPresented: $showsLibrary, selection: $pickedItems,
                      maxSelectionCount: max(1, model.remainingPhotoSlots), selectionBehavior: .ordered,
                      matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            pickedItems = []
            Task { await addPicked(items) }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                guard let data = image?.jpegData(compressionQuality: 0.95) else { return }
                Task { await model.addPhotos([data]) }
            }
            .ignoresSafeArea()
        }
    }

    /// The photos' error after a refused publish, or, as soon as an upload fails, why (the photo shows
    /// "Réessayer").
    private var errorText: String? {
        if let error = model.fieldErrors[.photos], error != .photoUploadFailed {
            return SellMessages.text(for: error, language: l10n.language)
        }
        return model.photos.lazy.compactMap(\.error).first.map(errorMessage)
    }

    private func uploaderItem(_ photo: SellPhoto) -> PhotoUploaderItem {
        let media: ProductMedia = if let preview = photo.preview {
            .local(Image(uiImage: preview))
        } else if case let .uploaded(uploaded) = photo.upload {
            .remote(uploaded.thumbURL ?? uploaded.url)
        } else {
            .remote(nil)
        }
        let status: PhotoUploaderItem.Status = switch photo.upload {
        case .uploading: .uploading
        case .uploaded: .ready
        case let .failed(error): .failed(message: errorMessage(error))
        }
        return PhotoUploaderItem(id: photo.id.uuidString, media: media, status: status)
    }

    /// A failed photo: the website's "upload failed" for a network or server failure, the precise reason
    /// for a photo the API refuses (too large, a format it does not take) or a rate limit.
    private func errorMessage(_ error: ApiError) -> String {
        switch error.code {
        case .fileTooLarge, .unsupportedMediaType, .rateLimited: l10n.message(for: error)
        default: l10n.string(.sellErrorUpload)
        }
    }

    /// With a camera: "Prendre une photo" or the library. Without one (the simulator): the library at once.
    private func addPhotos() {
        guard model.canAddPhotos else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            choosesSource = true
        } else {
            showsLibrary = true
        }
    }

    private var sourceSheet: some View {
        TaleedBottomSheet(title: l10n.string(.photoUploaderLabel), onClose: { choosesSource = false }, content: {
            VStack(spacing: TaleedSpacing.s12) {
                TaleedButton(title: l10n.string(.appVisualTakePhoto), kind: .secondary, size: .large, isFullWidth: true) {
                    choosesSource = false
                    showsCamera = true
                }
                TaleedButton(title: l10n.string(.appSellPhotoLibrary), kind: .outline, size: .large, isFullWidth: true) {
                    choosesSource = false
                    showsLibrary = true
                }
            }
        })
    }

    /// Reads the picked photos in the order they were picked; one that cannot be read (an iCloud photo
    /// offline) is skipped with a message.
    private func addPicked(_ items: [PhotosPickerItem]) async {
        var picked: [Data] = []
        var unreadable = false
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                picked.append(data)
            } else {
                unreadable = true
            }
        }
        if unreadable { toasts.show(l10n.string(.sellErrorUpload), kind: .error) }
        await model.addPhotos(picked)
    }
}
