import Foundation

// MARK: - Storage Backend Protocol

/// A backend that knows how to locate and access shared model files.
public protocol ModelStorageBackend: Sendable {
    /// A human-readable name for this backend.
    var name: String { get }
    
    /// The root directory where models are stored.
    func rootDirectory() throws -> URL
    
    /// Whether this backend is currently available.
    func isAvailable() async -> Bool
    
    /// Begin accessing a security-scoped resource if needed. Returns a token
    /// that must be passed to `stopAccessing` when done.
    func startAccessing(url: URL) -> Any?
    
    /// Stop accessing a security-scoped resource.
    func stopAccessing(token: Any?)
}

extension ModelStorageBackend {
    public func startAccessing(url: URL) -> Any? { nil }
    public func stopAccessing(token: Any?) {}
}

// MARK: - App Group Backend

/// Stores models in a shared App Group container.
/// Best for apps from the same developer team.
public struct AppGroupBackend: ModelStorageBackend {
    public let name: String = "App Group"
    public let groupIdentifier: String
    public let subdirectory: String
    
    public init(groupIdentifier: String, subdirectory: String = "SharedModels") {
        self.groupIdentifier = groupIdentifier
        self.subdirectory = subdirectory
    }
    
    public func rootDirectory() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw SharedModelKitError.backendUnavailable(
                "App Group '\(groupIdentifier)' not configured. Add it in Signing & Capabilities."
            )
        }
        let url = containerURL.appendingPathComponent(subdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    public func isAvailable() async -> Bool {
        (try? rootDirectory()) != nil
    }
}

// MARK: - Bookmark Backend (Files app / user-chosen directory)

/// Stores models in a user-chosen directory via security-scoped bookmarks.
/// This is the primary mechanism for cross-developer model sharing — the user
/// picks a folder once (e.g. "AI Models" in iCloud Drive or On My iPhone),
/// and the bookmark persists across launches.
public final class BookmarkBackend: ModelStorageBackend, @unchecked Sendable {
    public let name: String = "Bookmarked Directory"
    
    private let bookmarkKey: String
    private let defaults: UserDefaults
    
    /// Create a bookmark backend.
    /// - Parameters:
    ///   - bookmarkKey: The UserDefaults key used to persist the bookmark data.
    ///   - defaults: The UserDefaults suite to use (default: `.standard`).
    public init(bookmarkKey: String = "SharedModelKit_BookmarkData", defaults: UserDefaults = .standard) {
        self.bookmarkKey = bookmarkKey
        self.defaults = defaults
    }
    
    /// Call this from your UIDocumentPickerDelegate after the user selects a folder.
    /// Persists a security-scoped bookmark so the app can re-access the folder later.
    public func saveBookmark(for folderURL: URL) throws {
        guard folderURL.startAccessingSecurityScopedResource() else {
            throw SharedModelKitError.accessDenied("Cannot access the selected folder.")
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }
        
        let bookmarkData = try folderURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: bookmarkKey)
    }
    
    public func rootDirectory() throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            throw SharedModelKitError.backendUnavailable(
                "No folder bookmarked. Present a UIDocumentPickerViewController and call saveBookmark(for:)."
            )
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            // Re-save the bookmark to refresh it
            try saveBookmark(for: url)
        }
        return url
    }
    
    public func isAvailable() async -> Bool {
        (try? rootDirectory()) != nil
    }
    
    public func startAccessing(url: URL) -> Any? {
        url.startAccessingSecurityScopedResource() ? url : nil
    }
    
    public func stopAccessing(token: Any?) {
        (token as? URL)?.stopAccessingSecurityScopedResource()
    }
}

// MARK: - Local Directory Backend

/// Stores models in a local directory within the app's sandbox.
/// Useful for development/testing or as a fallback cache.
public struct LocalDirectoryBackend: ModelStorageBackend {
    public let name: String = "Local"
    public let directory: URL
    
    /// Creates a backend in the app's Application Support directory.
    public init(subdirectory: String = "SharedModelKit/Models") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = appSupport.appendingPathComponent(subdirectory, isDirectory: true)
    }
    
    /// Creates a backend at a specific local path.
    public init(directory: URL) {
        self.directory = directory
    }
    
    public func rootDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    
    public func isAvailable() async -> Bool { true }
}
