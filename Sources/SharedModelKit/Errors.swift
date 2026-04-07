import Foundation

// MARK: - Errors

public enum SharedModelKitError: LocalizedError {
    case backendUnavailable(String)
    case accessDenied(String)
    case modelNotFound(String)
    case integrityCheckFailed(expected: String, actual: String)
    case downloadFailed(underlying: Error)
    case noRemoteURL
    case cancelled
    case httpError(statusCode: Int)
    case mlxMetadataError(String)
    
    public var errorDescription: String? {
        switch self {
        case .backendUnavailable(let msg): return "Storage backend unavailable: \(msg)"
        case .accessDenied(let msg): return "Access denied: \(msg)"
        case .modelNotFound(let id): return "Model not found: \(id)"
        case .integrityCheckFailed(let expected, let actual):
            return "Integrity check failed. Expected SHA-256: \(expected), got: \(actual)"
        case .downloadFailed(let error): return "Download failed: \(error.localizedDescription)"
        case .noRemoteURL: return "No remote URL or mlxModelID configured for this model."
        case .cancelled: return "Operation cancelled."
        case .httpError(let code): return "HTTP error: \(code)"
        case .mlxMetadataError(let msg): return "MLX metadata error: \(msg)"
        }
    }
}

// MARK: - Model Status

/// The current status of a model within the store.
public enum ModelStatus: Sendable, Equatable {
    case unavailable
    case notDownloaded
    case downloading(progress: Double, receivedBytes: Int64, totalBytes: Int64?)
    case ready(url: URL, sizeBytes: Int64?)
    case error(String)
    
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    public var modelURL: URL? {
        if case .ready(let url, _) = self { return url }
        return nil
    }
}

// MARK: - Model Metadata

/// Persistent metadata stored alongside each downloaded model in `model_metadata.json`.
///
/// This file lives inside the model's enclosing folder:
/// ```
/// gguf/Llama-3.2-3B-Instruct-Q4_K_M/
/// ├── Llama-3.2-3B-Instruct-Q4_K_M.gguf
/// └── model_metadata.json   ← this
/// ```
public struct ModelDownloadMetadata: Codable, Sendable {
    /// The descriptor of the model that was downloaded.
    public let descriptor: ModelDescriptor
    
    /// When the download completed.
    public let downloadedAt: Date
    
    /// The SharedModelKit version that performed the download.
    public let sharedModelKitVersion: String
    
    /// Total size on disk in bytes at time of download.
    public let sizeOnDiskBytes: Int64?
    
    /// SHA-256 of the weights file (GGUF only, nil for directories).
    public let verifiedSHA256: String?
    
    public init(
        descriptor: ModelDescriptor,
        downloadedAt: Date = Date(),
        sharedModelKitVersion: String = "0.1.0",
        sizeOnDiskBytes: Int64? = nil,
        verifiedSHA256: String? = nil
    ) {
        self.descriptor = descriptor
        self.downloadedAt = downloadedAt
        self.sharedModelKitVersion = sharedModelKitVersion
        self.sizeOnDiskBytes = sizeOnDiskBytes
        self.verifiedSHA256 = verifiedSHA256
    }
    
    /// The standard filename for this metadata file.
    public static let filename = "model_metadata.json"
    
    /// Read metadata from a model directory.
    public static func read(from modelDirectory: URL) -> ModelDownloadMetadata? {
        let metadataURL = modelDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ModelDownloadMetadata.self, from: data)
    }
    
    /// Write metadata to a model directory.
    public func write(to modelDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        let metadataURL = modelDirectory.appendingPathComponent(Self.filename)
        try data.write(to: metadataURL, options: .atomic)
    }
}
