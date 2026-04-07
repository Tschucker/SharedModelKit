import Foundation
import CryptoKit

/// The central interface for discovering, downloading, and accessing shared AI models.
///
/// Models are organized on disk by format type, each in its own enclosing folder
/// with a `model_metadata.json` file recording the download date:
///
/// ```
/// <shared_folder>/
/// ├── gguf/
/// │   └── Llama-3.2-3B-Instruct-Q4_K_M/
/// │       ├── Llama-3.2-3B-Instruct-Q4_K_M.gguf
/// │       └── model_metadata.json
/// ├── mlx/
/// │   └── Llama-3.2-3B-Instruct-4bit/
/// │       ├── config.json
/// │       ├── tokenizer.json
/// │       ├── *.safetensors
/// │       └── model_metadata.json
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
    
    // MARK: - Path Resolution
    
    /// Returns the expected path for a model's enclosing directory:
    ///   `<backend_root>/<format.typeDirectory>/<model.filename>/`
    private func modelDirectory(for model: ModelDescriptor, in root: URL) -> URL {
        root
            .appendingPathComponent(model.format.typeDirectory, isDirectory: true)
            .appendingPathComponent(model.filename, isDirectory: true)
    }
    
    /// Returns the URL that should be passed to an inference engine:
    /// - GGUF: the `.gguf` file inside the model directory
    /// - MLX: the model directory itself (contains config.json + safetensors)
    private func inferenceURL(for model: ModelDescriptor, in modelDir: URL) -> URL {
        if model.format.isDirectory {
            return modelDir
        } else {
            return modelDir.appendingPathComponent(model.weightsFilename)
        }
    }
    
    // MARK: - Status
    
    /// Check the current status of a model across all backends.
    public func status(of model: ModelDescriptor) -> ModelStatus {
        let hasBackend = backends.contains { (try? $0.rootDirectory()) != nil }
        guard hasBackend else { return .unavailable }
        
        if activeDownloads[model.id] != nil {
            return .downloading(progress: 0, receivedBytes: 0, totalBytes: model.expectedSizeBytes)
        }
        
        if let located = locate(model) {
            return .ready(url: located.fileURL, sizeBytes: located.fileSize)
        }
        
        return .notDownloaded
    }
    
    /// Check status of all registered models.
    public func allStatuses() -> [(ModelDescriptor, ModelStatus)] {
        registry.values.map { ($0, status(of: $0)) }
    }
    
    // MARK: - Discovery
    
    /// Search all backends for a model. Returns the first match.
    public func locate(_ model: ModelDescriptor) -> LocatedModel? {
        for backend in backends {
            guard let root = try? backend.rootDirectory() else { continue }
            let modelDir = modelDirectory(for: model, in: root)
            let engineURL = inferenceURL(for: model, in: modelDir)
            
            let exists: Bool
            if model.format.isDirectory {
                exists = Self.isMLXModelDirectory(engineURL)
            } else {
                exists = FileManager.default.fileExists(atPath: engineURL.path)
            }
            
            if exists {
                let metadata = ModelDownloadMetadata.read(from: modelDir)
                return LocatedModel(
                    descriptor: model,
                    fileURL: engineURL,
                    modelDirectory: modelDir,
                    backend: backend,
                    downloadMetadata: metadata
                )
            }
        }
        return nil
    }
    
    /// Discover all models across all backends by scanning type directories.
    public func discoveredModels() -> [LocatedModel] {
        var results: [LocatedModel] = []
        let knownFilenames = Dictionary(
            uniqueKeysWithValues: registry.values.map { ($0.filename, $0) }
        )
        
        for backend in backends {
            guard let root = try? backend.rootDirectory() else { continue }
            
            // Scan each type directory (gguf/, mlx/, etc.)
            for format in [ModelFormat.gguf, .mlx, .coreml, .safetensors, .bin] {
                let typeDir = root.appendingPathComponent(format.typeDirectory, isDirectory: true)
                guard let modelDirs = try? FileManager.default.contentsOfDirectory(
                    at: typeDir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                
                for modelDir in modelDirs {
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir),
                          isDir.boolValue else { continue }
                    
                    let folderName = modelDir.lastPathComponent
                    let metadata = ModelDownloadMetadata.read(from: modelDir)
                    
                    // Try to match against the registry
                    if let desc = knownFilenames[folderName] {
                        let engineURL = inferenceURL(for: desc, in: modelDir)
                        results.append(LocatedModel(
                            descriptor: desc,
                            fileURL: engineURL,
                            modelDirectory: modelDir,
                            backend: backend,
                            downloadMetadata: metadata
                        ))
                    } else if let desc = metadata?.descriptor {
                        // Use the descriptor stored in the metadata
                        let engineURL = inferenceURL(for: desc, in: modelDir)
                        results.append(LocatedModel(
                            descriptor: desc,
                            fileURL: engineURL,
                            modelDirectory: modelDir,
                            backend: backend,
                            downloadMetadata: metadata
                        ))
                    } else {
                        // Unknown model — create a generic descriptor
                        let generic = ModelDescriptor(
                            id: folderName, name: folderName,
                            family: "unknown", parameterCount: "unknown",
                            quantization: "unknown", format: format,
                            filename: folderName
                        )
                        let engineURL = inferenceURL(for: generic, in: modelDir)
                        results.append(LocatedModel(
                            descriptor: generic,
                            fileURL: engineURL,
                            modelDirectory: modelDir,
                            backend: backend,
                            downloadMetadata: metadata
                        ))
                    }
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
    
    /// Get an inference-ready URL for a model. Downloads if missing.
    ///
    /// Returns:
    /// - GGUF: path to the `.gguf` file
    /// - MLX: path to the model directory
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
    
    /// Read the download metadata for a model.
    public func metadata(for model: ModelDescriptor) -> ModelDownloadMetadata? {
        locate(model)?.downloadMetadata
    }
    
    /// Delete a model from all backends.
    public func delete(_ model: ModelDescriptor) throws {
        var deleted = false
        for backend in backends {
            guard let root = try? backend.rootDirectory() else { continue }
            let modelDir = modelDirectory(for: model, in: root)
            if FileManager.default.fileExists(atPath: modelDir.path) {
                try FileManager.default.removeItem(at: modelDir)
                deleted = true
            }
        }
        if !deleted {
            throw SharedModelKitError.modelNotFound(model.id)
        }
    }
    
    // MARK: - Single-File Download (GGUF, etc.)
    
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
        
        let modelDir = modelDirectory(for: model, in: root)
        let tempDir = modelDir.deletingLastPathComponent()
            .appendingPathComponent(model.filename + ".downloading", isDirectory: true)
        
        // Clean up partial downloads
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let weightsFile = tempDir.appendingPathComponent(model.weightsFilename)
        
        // Stream download
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: remoteURL)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            try? FileManager.default.removeItem(at: tempDir)
            throw SharedModelKitError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let totalBytes = (response as? HTTPURLResponse)
            .flatMap { Int64($0.value(forHTTPHeaderField: "Content-Length") ?? "") }
            ?? model.expectedSizeBytes
        
        FileManager.default.createFile(atPath: weightsFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: weightsFile)
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
        var verifiedHash: String? = nil
        if let expectedHash = model.sha256 {
            let actualHash = try sha256(of: weightsFile)
            guard actualHash == expectedHash.lowercased() else {
                try? FileManager.default.removeItem(at: tempDir)
                throw SharedModelKitError.integrityCheckFailed(expected: expectedHash, actual: actualHash)
            }
            verifiedHash = actualHash
        }
        
        // Write metadata
        let meta = ModelDownloadMetadata(
            descriptor: model,
            downloadedAt: Date(),
            sizeOnDiskBytes: received,
            verifiedSHA256: verifiedHash
        )
        try meta.write(to: tempDir)
        
        // Atomic move to final location
        let typeDir = modelDir.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: typeDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        try FileManager.default.moveItem(at: tempDir, to: modelDir)
        
        return inferenceURL(for: model, in: modelDir)
    }
    
    // MARK: - MLX Directory Download
    
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
        
        let modelDir = modelDirectory(for: model, in: root)
        let tempDir = modelDir.deletingLastPathComponent()
            .appendingPathComponent(model.filename + ".downloading", isDirectory: true)
        
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Fetch file listing from HuggingFace API
        let apiURL = URL(string: "https://huggingface.co/api/models/\(mlxModelID)")!
        let (apiData, apiResponse) = try await URLSession.shared.data(from: apiURL)
        
        if let httpResponse = apiResponse as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            try? FileManager.default.removeItem(at: tempDir)
            throw SharedModelKitError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let repoInfo = try JSONDecoder().decode(HFRepoInfo.self, from: apiData)
        
        let modelFiles = repoInfo.siblings.filter { sibling in
            let name = sibling.rfilename
            return name.hasSuffix(".safetensors")
                || name.hasSuffix(".json")
                || name.hasSuffix(".txt")
                || name.hasSuffix(".model")
                || name.hasSuffix(".tiktoken")
        }
        
        guard !modelFiles.isEmpty else {
            try? FileManager.default.removeItem(at: tempDir)
            throw SharedModelKitError.mlxMetadataError("No model files found in repo \(mlxModelID)")
        }
        
        let totalBytes: Int64 = modelFiles.reduce(0) { $0 + ($1.size ?? 0) }
        var cumulativeReceived: Int64 = 0
        
        for fileInfo in modelFiles {
            let filename = fileInfo.rfilename
            let fileDestination = tempDir.appendingPathComponent(filename)
            let fileDir = fileDestination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: fileDir.path) {
                try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
            }
            
            let downloadURL = URL(string: "https://huggingface.co/\(mlxModelID)/resolve/main/\(filename)")!
            let (asyncBytes, response) = try await URLSession.shared.bytes(from: downloadURL)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                try? FileManager.default.removeItem(at: tempDir)
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
                    progress?(cumulativeReceived, totalBytes > 0 ? totalBytes : model.expectedSizeBytes)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                cumulativeReceived += Int64(buffer.count)
                progress?(cumulativeReceived, totalBytes > 0 ? totalBytes : model.expectedSizeBytes)
            }
            try handle.close()
        }
        
        // Write metadata
        let meta = ModelDownloadMetadata(
            descriptor: model,
            downloadedAt: Date(),
            sizeOnDiskBytes: cumulativeReceived,
            verifiedSHA256: nil
        )
        try meta.write(to: tempDir)
        
        // Atomic move
        let typeDir = modelDir.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: typeDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        try FileManager.default.moveItem(at: tempDir, to: modelDir)
        
        return inferenceURL(for: model, in: modelDir)
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

private struct HFRepoInfo: Decodable {
    let siblings: [HFSibling]
}

private struct HFSibling: Decodable {
    let rfilename: String
    let size: Int64?
}

// MARK: - Located Model

/// A model that has been found on disk.
public struct LocatedModel: Sendable {
    /// The descriptor of the model.
    public let descriptor: ModelDescriptor
    
    /// The URL to pass to an inference engine.
    /// - GGUF: path to the `.gguf` file
    /// - MLX: path to the model directory (containing config.json + safetensors)
    public let fileURL: URL
    
    /// The enclosing directory containing the model files and `model_metadata.json`.
    public let modelDirectory: URL
    
    /// The storage backend where this model was found.
    public let backend: ModelStorageBackend
    
    /// The download metadata, if a `model_metadata.json` file is present.
    public let downloadMetadata: ModelDownloadMetadata?
    
    /// When this model was downloaded, if metadata is available.
    public var downloadedAt: Date? {
        downloadMetadata?.downloadedAt
    }
    
    /// Total size in bytes. For directories, sums all files.
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
            at: url, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize { total += Int64(size) }
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
