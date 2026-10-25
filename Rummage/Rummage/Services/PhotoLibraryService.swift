import Photos
import SwiftUI
import Combine

class PhotoLibraryService: ObservableObject, PhotoSource {
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var hasAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    /// Picks up a change made in iOS Settings while the app was in the
    /// background — the only way out of the no-access screen.
    func refreshAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status == .authorized || status == .limited
    }

    // MARK: - PhotoSource

    /// Walks a shuffled index list over a lazy fetch result, so picking 50
    /// photos out of a library of 40,000 never materialises the 40,000.
    /// `@concurrent` because both walks touch every photo in the worst case,
    /// and the app is main-actor by default.
    @concurrent
    nonisolated func sessionBatch(limit: Int, excluding keptIDs: Set<String>) async -> [Photo] {
        let result = Self.fetchImages()
        guard result.count > 0, limit > 0 else { return [] }

        var photos: [Photo] = []
        for index in Array(0..<result.count).shuffled() {
            let asset = result.object(at: index)
            guard !keptIDs.contains(asset.localIdentifier) else { continue }
            photos.append(Photo(asset: asset))
            if photos.count >= limit { break }
        }
        return photos
    }

    @concurrent
    nonisolated func unreviewedCount(excluding keptIDs: Set<String>) async -> Int {
        var count = 0
        Self.fetchImages().enumerateObjects { asset, _, _ in
            if !keptIDs.contains(asset.localIdentifier) { count += 1 }
        }
        return count
    }

    func delete(_ photos: [Photo]) async throws {
        let assets = photos.compactMap { $0.asset }
        guard !assets.isEmpty else { return }
        // PhotoKit presents its own confirmation for assets the app did not
        // create, and throws if the user declines it. That prompt is the only
        // confirmation Rummage asks for.
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
    }

    // MARK: - Images

    /// The photo at display size: filled for the review card, fitted for the
    /// hold-to-peek view.
    static func image(
        for photo: Photo,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> UIImage? {
        guard let asset = photo.asset else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// The photo at full quality, for sharing. The share sheet hands on what
    /// the library actually holds, not the card's thumbnail.
    static func imageData(for photo: Photo) async -> Data? {
        guard let asset = photo.asset else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private nonisolated static func fetchImages() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return PHAsset.fetchAssets(with: options)
    }
}
