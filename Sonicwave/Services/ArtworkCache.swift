import SwiftUI
import AppKit

/// Fetch-once, size-bounded artwork cache. Requests server-resized images and
/// caches by coverArt id + target pixel size so list thumbnails and the
/// now-playing hero are separate, right-sized entries.
/// See docs/05-data-and-caching.md.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    /// Set by AppModel so the cache can build authenticated cover-art URLs.
    /// Held strongly: the cache is a process-lifetime singleton and `ClientBox`
    /// only retains the `SubsonicClient` (no cycle). A `weak` ref here would let
    /// the inline `ClientBox(client)` deallocate immediately → no artwork.
    var clientBox: ClientBox?

    init() {
        cache.countLimit = 400
    }

    func image(coverArt id: String?, size: Int) async -> NSImage? {
        guard let id, !id.isEmpty, let clientBox else { return nil }
        let key = "\(id)@\(size)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await Self.fetch(id: id, size: size, client: clientBox.client)
            if let image { self.cache.setObject(image, forKey: key as NSString) }
            self.inFlight[key] = nil
            return image
        }
        inFlight[key] = task
        return await task.value
    }

    func purge() {
        cache.removeAllObjects()
    }

    private static func fetch(id: String, size: Int, client: SubsonicClient) async -> NSImage? {
        let url: URL
        do {
            url = try await client.coverArtURL(id: id, size: size)
        } catch {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}

/// Lets the @MainActor cache hold a reference to the actor-isolated client
/// without retaining AppModel directly.
final class ClientBox {
    let client: SubsonicClient
    init(_ client: SubsonicClient) { self.client = client }
}
