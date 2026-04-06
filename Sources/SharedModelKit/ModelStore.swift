import Foundation
import CryptoKit

/// The central interface for discovering, downloading, and accessing shared AI models.
///
/// `ModelStore` searches across one or more storage backends to find model files,
/// handles downloading for both single-file (GGUF) and directory-based (MLX) formats,
/// and avoids redundant downloads when multiple apps need the same model.
///
/// ## Quick Start
/// ```swift
/// let bookmark = BookmarkBackend()
/// let store = ModelStore(backends: [bookmark])
/// await store.register(ModelCatalog.all)
///
/// // Check if a model is already available
/// let status = await store.status(of: ModelCatalog.llama3_2_3B_Q4)
///
/// // Get the file — downloads if missing, returns instantly if present
/// let url = try await store.modelURL(for: ModelCatalog.llama3_2_3B_Q4) { received, total in
///     print("Progress: \(received)/\(total ?? 0)")
/// }
/// ```
public actor ModelStore {
    
    public let backends: [ModelStorageBackend]
    private var registry: [String: ModelDescriptor] = [:]
    private var activeDownloads: [String: Task<URL, Error>] = [:]
    
    // MARK: - Init
    
    public init(backends: [ModelStorageBackend]) {
        precondition(!backends.isEmpty, "At least one storage backend is required.")
        self.backends = backends
    }
    
    public init(backend: ModelStorageBackend) {
        self.backends = [backend]
    }
    
    // MARK: - Registry
    
    public func register(_ descriptors: [ModelDescriptor]) {
        for d in descriptors { registry[d.id] = d }
    }
    
    public func descriptor(for id: String) -> ModelDescriptor? {
        registry[id]
    }
    
    // MARK: - Status
    
    /// Check the current status of a model across all backends.
    public func status(of model: ModelDescriptor) -> ModelStatus {
        // Check if any backend is available
        let hasBackend = backends.contains { (try? $0.rootDirectory()) != nil }
        guard hasBackend else { return .unavailable }
        
        // Check if currently downloading
        if activeDownloads[model.id] != nil {
            return .downloading(progress: 0, receivedBytes: 0, totalBytes: model.expectedSizeBytes)
        }
        
        // Check if present on disk
        if let located = locate(model) {
            let size = located.fileSize
            return .ready(url: located.fileURL, sizeBytes: size)
        }
        
        return .notDownloaded
    }
    
    /// Check status of all registered models.
    public func allStatuses() -> [(ModelDescriptor, ModelStatus)] {
        registry.values.map { ($0, status(of: $0)) }
    }
    
    // MARK: - Discovery
    
    /// Search all backends for a model. Returns the first match.
    /// Works for both single files (GGUF) and directories (MLX).
    public func locate(_ model: ModelDescriptor) -> LocatedModel? {
        for backend in backends {
            guard let root = try? backend.rootDirectory() else { continue }
            let fileURL = root.appendingPathComponent(model.filename)
            
            if model.format.isDirectory {
                // For directory-based formats, check the directory contains config.json
                if Self.isMLXModelDirectory(fileURL) {
                    return LocatedModel(descriptor: model, fileURL: fileURL, backend: backend)
                }
            } else {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    return LocatedModel(descriptor: model, fileURL: fileURL, backend: backend)
                }
            }
        }
        return nil
    }
    
    /// List all models found across all backends.
    public func discoveredModels() -> [LocatedModel] {
        var results: [LocatedModel] = []
        let knownFilenames = Dictionary(uniqueKeysWithValues: registry.values.map { ($0.filename, $0) })
        
        for backend in backends {
            guard let root = try? backend.rootDirectory() else { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for url in contents {
                let filename = url.lastPathComponent
                if let desc = knownFilenames[filename] {
                    results.append(LocatedModel(descriptor: desc, fileURL: url, backend: backend))
                } else if ModelFormat.allKnownExtensions.contains(url.pathExtension.lowercased()) {
                    let generic = ModelDescriptor(
                        id: filename, name: filename,
                        family: "unknown", parameterCount: "unknown", quantization: "unknown",
                        format: ModelFormat(rawValue: url.pathExtension.lowercased()) ?? .bin,
                        filename: filename
                    )
                    results.append(LocatedModel(descriptor: generic, fileURL: url, backend: backend))
                } else if Self.isMLXModelDirectory(url) {
                    let generic = ModelDescriptor(
                        id: filename, name: filename,
                        family: "unknown", parameterCount: "unknown", quantization: "unknown",
                        format: .mlx, filename: filename
                    )
                    results.append(LocatedModel(descriptor: generic, fileURL: url, backend: backend))
                }
            }
        }
        return results
    }
    
    private static func isMLXModelDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("config.json").path
        )
    }
    
    // MARK: - Access
    
    /// Get a local URL for a model. Downloads if missing.
    /// Handles both GGUF (single-file download) and MLX (multi-file HuggingFace repo download).
    public func modelURL(
        for model: ModelDescriptor,
        downloadIfMissing: Bool = true,
        progress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws -> URL {
        if let located = locate(model) {
            return located.fileURL
        }
        
        guard downloadIfMissing else {
            throw SharedModelKitError.modelNotFound(model.id)
        }
        
        // Coalesce concurrent requests
        if let existing = activeDownloads[model.id] {
            return try await existing.value
        }
        
        let task = Task<URL, Error> {
            if model.format == .mlx {
                return try await downloadMLXModel(model, progress: progress)
            } else {
                return try await downloadSingleFile(model, progress: progress)
            }
        }
        activeDownloads[model.id] = task
        
        do {
            let url = try await task.value
            activeDownloads[model.id] = nil
            return url
        } catch {
            activeDownloads[model.id] = nil
            throw error
        }
    }
    
    /// Delete a model from all backends.
    public func delete(_ model: ModelDescriptor) throws {
        var deleted = false
        for backend in backends {
            guard let root = try? backend.rootDirectory() else { continue }
            let fileURL = root.appendingPathComponent(model.filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                deleted = true
            }
            // Also remove sidecar manifest if present
            let manifestURL = fileURL.appendingPathExtension("json")
            try? FileManager.default.removeItem(at: manifestURL)
        }
        if !deleted {
            throw SharedModelKitError.modelNotFound(model.id)
        }
    }
    
    // MARK: - Single-File Download (GGUF, safetensors, etc.)
    
    private func downloadSingleFile(
        _ model: ModelDescriptor,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> URL {
        guard let remoteURL = model.remoteURL else {
            throw SharedModelKitError.noRemoteURL
        }
        
        guard let root = (try? backends.first?.rootDirectory()) else {
            throw SharedModelKitError.backendUnavailable("No writable backend available.")
        }
        
        let destinationURL = root.appendingPathComponent(model.filename)
        let tempURL = destinationURL.appendingPathExtension("download")
        
        // Stream download
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: remoteURL)
        
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode >= 400 {
            throw SharedModelKitError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let totalBytes = (response as? HTTPURLResponse)
            .flatMap { Int64($0.value(forHTTPHeaderField: "Content-Length") ?? "") }
            ?? model.expectedSizeBytes
        
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }
        
        var received: Int64 = 0
        let bufferSize = 1024 * 1024
        var buffer = Data()
        buffer.reserveCapacity(bufferSize)
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= bufferSize {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                progress?(received, totalBytes)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
            progress?(received, totalBytes)
        }
        
        try handle.close()
        
        // Verify integrity
        if let expectedHash = model.sha256 {
            let actualHash = try sha256(of: tempURL)
            guard actualHash == expectedHash.lowercased() else {
                try? FileManager.default.removeItem(at: tempURL)
                throw SharedModelKitError.integrityCheckFailed(expected: expectedHash, actual: actualHash)
            }
        }
        
        // Move to final location
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        // Sidecar manifest
        let manifestData = try JSONEncoder().encode(model)
        try manifestData.write(to: destinationURL.appendingPathExtension("json"))
        
        return destinationURL
    }
    
    // MARK: - MLX Directory Download (HuggingFace repo)
    
    /// Downloads an MLX model from HuggingFace by fetching the file listing
    /// via the HF API, then downloading each file into a local directory.
    private func downloadMLXModel(
        _ model: ModelDescriptor,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> URL {
        guard let mlxModelID = model.mlxModelID else {
            throw SharedModelKitError.noRemoteURL
        }
        
        guard let root = (try? backends.first?.rootDirectory()) else {
            throw SharedModelKitError.backendUnavailable("No writable backend available.")
        }
        
        let destinationDir = root.appendingPathComponent(model.filename, isDirectory: true)
        let tempDir = root.appendingPathComponent(model.filename + ".downloading", isDirectory: true)
        
        // Clean up any previous partial download
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 1. Fetch file listing from HuggingFace API
        let apiURL = URL(string: "https://huggingface.co/api/models/\(mlxModelID)")!
        let (apiData, apiResponse) = try await URLSession.shared.data(from: apiURL)
        
        if let httpResponse = apiResponse as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw SharedModelKitError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let repoInfo = try JSONDecoder().decode(HFRepoInfo.self, from: apiData)
        
        // Filter to model-relevant files
        let modelFiles = repoInfo.siblings.filter { sibling in
            let name = sibling.rfilename
            // Include essential model files, skip READMEs/licenses/etc.
            return name.hasSuffix(".safetensors")
                || name.hasSuffix(".json")
                || name.hasSuffix(".txt")      // tokenizer vocab files
                || name.hasSuffix(".model")    // sentencepiece
                || name.hasSuffix(".tiktoken") // tiktoken vocab
        }
        
        guard !modelFiles.isEmpty else {
            throw SharedModelKitError.mlxMetadataError(
                "No model files found in repo \(mlxModelID)"
            )
        }
        
        // 2. Calculate total size for progress
        let totalBytes: Int64 = modelFiles.reduce(0) { $0 + ($1.size ?? 0) }
        var cumulativeReceived: Int64 = 0
        
        // 3. Download each file
        for fileInfo in modelFiles {
            let filename = fileInfo.rfilename
            
            // Create subdirectories if needed (e.g. "model-00001-of-00002.safetensors")
            let fileDestination = tempDir.appendingPathComponent(filename)
            let fileDir = fileDestination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: fileDir.path) {
                try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
            }
            
            let downloadURL = URL(string: "https://huggingface.co/\(mlxModelID)/resolve/main/\(filename)")!
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(from: downloadURL)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                throw SharedModelKitError.httpError(statusCode: httpResponse.statusCode)
            }
            
            FileManager.default.createFile(atPath: fileDestination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: fileDestination)
            
            let bufferSize = 1024 * 1024
            var buffer = Data()
            buffer.reserveCapacity(bufferSize)
            
            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= bufferSize {
                    try handle.write(contentsOf: buffer)
                    cumulativeReceived += Int64(buffer.count)
                    progress?(cumulativeReceived, totalBytes > 0 ? totalBytes : nil)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                cumulativeReceived += Int64(buffer.count)
                progress?(cumulativeReceived, totalBytes > 0 ? totalBytes : nil)
            }
            
            try handle.close()
        }
        
        // 4. Move temp directory to final location
        if FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.removeItem(at: destinationDir)
        }
        try FileManager.default.moveItem(at: tempDir, to: destinationDir)
        
        // Sidecar manifest
        let manifestData = try JSONEncoder().encode(model)
        try manifestData.write(to: destinationDir.appendingPathExtension("json"))
        
        return destinationDir
    }
    
    // MARK: - Integrity
    
    public func verify(_ model: ModelDescriptor) throws -> Bool {
        guard let located = locate(model) else {
            throw SharedModelKitError.modelNotFound(model.id)
        }
        guard let expected = model.sha256 else { return true }
        let actual = try sha256(of: located.fileURL)
        return actual == expected.lowercased()
    }
    
    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 4 * 1024 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - HuggingFace API Models

/// Minimal representation of a HuggingFace model repo API response.
private struct HFRepoInfo: Decodable {
    let siblings: [HFSibling]
}

/// A single file entry in a HuggingFace repo.
private struct HFSibling: Decodable {
    let rfilename: String
    let size: Int64?
}

// MARK: - Located Model

/// A model that has been found on disk.
public struct LocatedModel: Sendable {
    public let descriptor: ModelDescriptor
    public let fileURL: URL
    public let backend: ModelStorageBackend
    
    /// Total size in bytes. For directories, returns the sum of all files.
    public var fileSize: Int64? {
        if descriptor.format.isDirectory {
            return Self.directorySize(fileURL)
        }
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }
    
    /// Provides scoped access to the model (required for bookmark-based backends).
    public func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let token = backend.startAccessing(url: fileURL)
        defer { backend.stopAccessing(token: token) }
        return try body(fileURL)
    }
    
    private static func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

// MARK: - Helpers

extension ModelFormat {
    static let allKnownExtensions: Set<String> = [
        "gguf", "mlmodelc", "mlpackage", "bin", "safetensors"
    ]
}
