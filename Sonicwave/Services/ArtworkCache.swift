import SwiftUI
import AppKit
import CryptoKit

/// Two-tier artwork cache: an in-memory `NSCache` over a persistent on-disk
/// store. Cover art is immutable, so a disk hit is authoritative and kept
/// indefinitely — artwork loads instantly across launches and survives network
/// blips. Keyed by coverArt id + target pixel size (list thumbnails and the
/// now-playing hero are separate, right-sized entries). See docs/05.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    /// Pixel sizes cached per coverArt id, so we can surface an already-loaded
    /// variant instantly while the exact size is fetched.
    private var sizesByID: [String: [Int]] = [:]
    private let diskDir: URL

    /// Set by AppModel so the cache can build authenticated cover-art URLs.
    /// Held strongly: the cache is a process-lifetime singleton and `ClientBox`
    /// only retains the `SubsonicClient` (no cycle). A `weak` ref here would let
    /// the inline `ClientBox(client)` deallocate immediately → no artwork.
    var clientBox: ClientBox?

    init() {
        cache.countLimit = 400
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDir = base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Sonicwave", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    func image(coverArt id: String?, size: Int) async -> NSImage? {
        guard let id, !id.isEmpty, let clientBox else { return nil }
        let key = "\(id)@\(size)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let client = clientBox.client
        let dir = diskDir
        let task = Task<NSImage?, Never> { [weak self] in
            let image = await Self.load(id: id, size: size, client: client, dir: dir)
            if let self, let image {
                self.cache.setObject(image, forKey: key as NSString)
                if !(self.sizesByID[id]?.contains(size) ?? false) {
                    self.sizesByID[id, default: []].append(size)
                }
            }
            self?.inFlight[key] = nil
            return image
        }
        inFlight[key] = task
        return await task.value
    }

    /// Any in-memory variant for `id` (largest available), used as an instant
    /// placeholder while the exact size loads — so showing the same art at a
    /// different size doesn't flash the empty placeholder.
    func cachedVariant(coverArt id: String?) -> NSImage? {
        guard let id, let sizes = sizesByID[id] else { return nil }
        for size in sizes.sorted(by: >) {
            if let image = cache.object(forKey: "\(id)@\(size)" as NSString) { return image }
        }
        return nil
    }

    /// Drop the in-memory tier (disk store persists — artwork is immutable).
    func purge() {
        cache.removeAllObjects()
    }

    // MARK: - Disk + network (off the main actor)

    private nonisolated static func load(id: String, size: Int,
                                         client: SubsonicClient, dir: URL) async -> NSImage? {
        let fileURL = dir.appendingPathComponent(filename(id: id, size: size))
        // Disk first: cover art doesn't change, so a hit is authoritative.
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            return image
        }
        // Otherwise fetch, then persist the original bytes (keeps webp/jpeg, small).
        guard let url = try? await client.coverArtURL(id: id, size: size),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        try? data.write(to: fileURL, options: .atomic)
        return image
    }

    private nonisolated static func filename(id: String, size: Int) -> String {
        let digest = SHA256.hash(data: Data("\(id)@\(size)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }
}

/// Lets the @MainActor cache hold a reference to the actor-isolated client
/// without retaining AppModel directly.
final class ClientBox {
    let client: SubsonicClient
    init(_ client: SubsonicClient) { self.client = client }
}
