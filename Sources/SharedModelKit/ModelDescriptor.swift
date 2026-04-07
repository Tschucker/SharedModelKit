import Foundation

/// Describes an AI model that can be shared across apps.
public struct ModelDescriptor: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let family: String
    public let parameterCount: String
    public let quantization: String
    public let format: ModelFormat
    public let expectedSizeBytes: Int64?
    public let sha256: String?
    public let remoteURL: URL?
    
    /// The name of this model's enclosing folder on disk.
    /// e.g. "Llama-3.2-3B-Instruct-Q4_K_M" or "Llama-3.2-3B-Instruct-4bit"
    public let filename: String
    
    /// Optional metadata. Common keys:
    /// - `"huggingface"`: URL to the HuggingFace model page
    /// - `"license"`: License name
    /// - `"mlxModelID"`: HuggingFace repo ID for MLX models
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
        self.filename = filename ?? id
        self.metadata = metadata
    }
    
    /// The HuggingFace repo ID for MLX models, if available.
    public var mlxModelID: String? {
        metadata["mlxModelID"]
    }
    
    /// The name of the actual weights file inside the model folder (GGUF only).
    public var weightsFilename: String {
        "\(filename).\(format.fileExtension)"
    }
}

/// Supported model file formats.
public enum ModelFormat: String, Codable, Hashable, Sendable {
    case gguf
    case mlx
    case coreml
    case mlpackage
    case mlmodelc
    case bin
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
    
    /// Whether this format stores model weights as a directory of files.
    public var isDirectory: Bool {
        switch self {
        case .mlx, .mlpackage, .mlmodelc, .coreml:
            return true
        default:
            return false
        }
    }
    
    /// The top-level folder name used to group models of this type.
    ///
    /// On-disk layout:
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
    public var typeDirectory: String {
        rawValue
    }
}
