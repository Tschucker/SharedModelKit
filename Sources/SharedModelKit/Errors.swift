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
    /// No storage backend is available (e.g. no folder bookmarked).
    case unavailable
    
    /// The model is not present in any backend.
    case notDownloaded
    
    /// The model is currently being downloaded.
    /// `progress` is 0.0–1.0, `receivedBytes` and `totalBytes` are raw counts.
    case downloading(progress: Double, receivedBytes: Int64, totalBytes: Int64?)
    
    /// The model is present and ready to load.
    case ready(url: URL, sizeBytes: Int64?)
    
    /// Something went wrong.
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
