import Foundation

/// Describes an AI model that can be shared across apps.
public struct ModelDescriptor: Codable, Hashable, Sendable, Identifiable {
    /// Unique identifier, e.g. "mistral-7b-instruct-v0.3-Q4_K_M"
    public let id: String
    
    /// Human-readable name
    public let name: String
    
    /// Model family (llama, mistral, gemma, phi, qwen, etc.)
    public let family: String
    
    /// Parameter count string, e.g. "7B", "13B"
    public let parameterCount: String
    
    /// Quantization format, e.g. "Q4_K_M", "Q8_0", "4-bit"
    public let quantization: String
    
    /// File format of the model weights
    public let format: ModelFormat
    
    /// Expected total size in bytes (for progress/validation)
    public let expectedSizeBytes: Int64?
    
    /// SHA-256 hash of the model file for integrity verification (single-file formats only)
    public let sha256: String?
    
    /// Remote URL to download the model from (e.g. Hugging Face direct link for GGUF).
    /// For directory-based formats like MLX, this is nil — use `mlxModelID` in metadata instead.
    public let remoteURL: URL?
    
    /// The filename (for single-file formats) or directory name (for MLX) on disk.
    public let filename: String
    
    /// Optional metadata. Common keys:
    /// - `"huggingface"`: URL to the HuggingFace model page
    /// - `"license"`: License name
    /// - `"mlxModelID"`: HuggingFace repo ID for MLX models (e.g. "mlx-community/Llama-3.2-3B-Instruct-4bit")
    public let metadata: [String: String]
    
    public init(
        id: String,
        name: String,
        family: String,
        parameterCount: String,
        quantization: String,
        format: ModelFormat,
        expectedSizeBytes: Int64? = nil,
        sha256: String? = nil,
        remoteURL: URL? = nil,
        filename: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.format = format
        self.expectedSizeBytes = expectedSizeBytes
        self.sha256 = sha256
        self.remoteURL = remoteURL
        self.filename = filename ?? "\(id).\(format.fileExtension)"
        self.metadata = metadata
    }
    
    /// The HuggingFace repo ID for MLX models, if available.
    public var mlxModelID: String? {
        metadata["mlxModelID"]
    }
}

/// Supported model file formats.
public enum ModelFormat: String, Codable, Hashable, Sendable {
    case gguf
    case mlx            // directory containing config.json + tokenizer.json + .safetensors
    case coreml
    case mlpackage
    case mlmodelc
    case bin            // raw weights
    case safetensors
    
    public var fileExtension: String {
        switch self {
        case .gguf: return "gguf"
        case .mlx: return "mlx"
        case .coreml: return "mlmodelc"
        case .mlpackage: return "mlpackage"
        case .mlmodelc: return "mlmodelc"
        case .bin: return "bin"
        case .safetensors: return "safetensors"
        }
    }
    
    /// Whether this format is stored as a directory rather than a single file.
    public var isDirectory: Bool {
        switch self {
        case .mlx, .mlpackage, .mlmodelc, .coreml:
            return true
        default:
            return false
        }
    }
}
