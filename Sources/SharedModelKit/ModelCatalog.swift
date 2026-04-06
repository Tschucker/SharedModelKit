import Foundation

/// A curated catalog of popular model descriptors with verified
/// download URLs, file sizes, and SHA-256 hashes.
///
/// Includes both GGUF (single-file) and MLX (directory-based) models.
/// Standardized filenames/directory names ensure different apps
/// refer to the same model files consistently.
///
/// ```swift
/// let store = ModelStore(backend: bookmark)
///
/// // GGUF model — single file, works with llama.cpp
/// let url = try await store.modelURL(for: ModelCatalog.llama3_2_3B_Q4)
///
/// // MLX model — directory, works with MLX Swift
/// if let located = await store.locate(ModelCatalog.llama3_2_3B_MLX) {
///     // located.fileURL points to the model directory
/// }
/// ```
public enum ModelCatalog {
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - GGUF Models (single-file, for llama.cpp / llama.swift)
    // ═══════════════════════════════════════════════════════════════
    
    public static let llama3_2_1B_Q4 = ModelDescriptor(
        id: "llama-3.2-1b-instruct-Q4_K_M",
        name: "Llama 3.2 1B Instruct",
        family: "llama",
        parameterCount: "1B",
        quantization: "Q4_K_M",
        format: .gguf,
        expectedSizeBytes: 808_000_000,
        sha256: "6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83",
        remoteURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"),
        filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        metadata: [
            "huggingface": "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF",
            "license": "Llama 3.2 Community License",
        ]
    )
    
    public static let llama3_2_3B_Q4 = ModelDescriptor(
        id: "llama-3.2-3b-instruct-Q4_K_M",
        name: "Llama 3.2 3B Instruct",
        family: "llama",
        parameterCount: "3B",
        quantization: "Q4_K_M",
        format: .gguf,
        expectedSizeBytes: 2_020_000_000,
        sha256: "6c1a2b41161032677be168d354123594c0e6e67d2b9227c84f296ad037c728ff",
        remoteURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"),
        filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        metadata: [
            "huggingface": "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF",
            "license": "Llama 3.2 Community License",
        ]
    )
    
    public static let gemma2_2B_Q4 = ModelDescriptor(
        id: "gemma-2-2b-it-Q4_K_M",
        name: "Gemma 2 2B Instruct",
        family: "gemma",
        parameterCount: "2B",
        quantization: "Q4_K_M",
        format: .gguf,
        expectedSizeBytes: 1_500_000_000,
        remoteURL: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf"),
        filename: "gemma-2-2b-it-Q4_K_M.gguf",
        metadata: [
            "huggingface": "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF",
            "license": "Gemma",
        ]
    )
    
    public static let phi3_mini_Q4 = ModelDescriptor(
        id: "phi-3-mini-4k-instruct-Q4_K_M",
        name: "Phi-3 Mini 4K Instruct",
        family: "phi",
        parameterCount: "3.8B",
        quantization: "Q4_K_M",
        format: .gguf,
        expectedSizeBytes: 2_390_000_000,
        remoteURL: URL(string: "https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf"),
        filename: "Phi-3-mini-4k-instruct-Q4_K_M.gguf",
        metadata: [
            "huggingface": "https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF",
            "license": "MIT",
        ]
    )
    
    public static let mistral7B_v03_Q4 = ModelDescriptor(
        id: "mistral-7b-instruct-v0.3-Q4_K_M",
        name: "Mistral 7B Instruct v0.3",
        family: "mistral",
        parameterCount: "7B",
        quantization: "Q4_K_M",
        format: .gguf,
        expectedSizeBytes: 4_370_000_000,
        remoteURL: URL(string: "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"),
        filename: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
        metadata: [
            "huggingface": "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF",
            "license": "Apache 2.0",
        ]
    )
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - MLX Models (directory-based, for MLX Swift / Metal)
    // ═══════════════════════════════════════════════════════════════
    //
    // MLX models are directories containing config.json, tokenizer.json,
    // and .safetensors weight shards. They can be:
    //
    //   1. Downloaded by LLMModelFactory using the `mlxModelID` metadata key,
    //      then moved/symlinked into the shared folder.
    //
    //   2. Manually placed in the shared folder by the user
    //      (e.g. via `huggingface-cli download`).
    //
    // SharedModelKit discovers them by matching the directory name
    // against registered catalog entries, or by detecting directories
    // containing config.json.
    
    public static let llama3_2_1B_MLX = ModelDescriptor(
        id: "mlx-llama-3.2-1b-instruct-4bit",
        name: "Llama 3.2 1B Instruct (MLX)",
        family: "llama",
        parameterCount: "1B",
        quantization: "4-bit",
        format: .mlx,
        expectedSizeBytes: 700_000_000,
        filename: "Llama-3.2-1B-Instruct-4bit",
        metadata: [
            "mlxModelID": "mlx-community/Llama-3.2-1B-Instruct-4bit",
            "huggingface": "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit",
            "license": "Llama 3.2 Community License",
        ]
    )
    
    public static let llama3_2_3B_MLX = ModelDescriptor(
        id: "mlx-llama-3.2-3b-instruct-4bit",
        name: "Llama 3.2 3B Instruct (MLX)",
        family: "llama",
        parameterCount: "3B",
        quantization: "4-bit",
        format: .mlx,
        expectedSizeBytes: 1_800_000_000,
        filename: "Llama-3.2-3B-Instruct-4bit",
        metadata: [
            "mlxModelID": "mlx-community/Llama-3.2-3B-Instruct-4bit",
            "huggingface": "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit",
            "license": "Llama 3.2 Community License",
        ]
    )
    
    public static let gemma3_1B_MLX = ModelDescriptor(
        id: "mlx-gemma-3-1b-it-4bit",
        name: "Gemma 3 1B Instruct (MLX)",
        family: "gemma",
        parameterCount: "1B",
        quantization: "4-bit",
        format: .mlx,
        expectedSizeBytes: 600_000_000,
        filename: "gemma-3-1b-it-4bit",
        metadata: [
            "mlxModelID": "mlx-community/gemma-3-1b-it-4bit",
            "huggingface": "https://huggingface.co/mlx-community/gemma-3-1b-it-4bit",
            "license": "Gemma",
        ]
    )
    
    public static let qwen3_4B_MLX = ModelDescriptor(
        id: "mlx-qwen3-4b-4bit",
        name: "Qwen3 4B (MLX)",
        family: "qwen",
        parameterCount: "4B",
        quantization: "4-bit",
        format: .mlx,
        expectedSizeBytes: 2_500_000_000,
        filename: "Qwen3-4B-4bit",
        metadata: [
            "mlxModelID": "mlx-community/Qwen3-4B-4bit",
            "huggingface": "https://huggingface.co/mlx-community/Qwen3-4B-4bit",
            "license": "Apache 2.0",
        ]
    )
    
    public static let mistral7B_v03_MLX = ModelDescriptor(
        id: "mlx-mistral-7b-instruct-v0.3-4bit",
        name: "Mistral 7B Instruct v0.3 (MLX)",
        family: "mistral",
        parameterCount: "7B",
        quantization: "4-bit",
        format: .mlx,
        expectedSizeBytes: 4_000_000_000,
        filename: "Mistral-7B-Instruct-v0.3-4bit",
        metadata: [
            "mlxModelID": "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            "huggingface": "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            "license": "Apache 2.0",
        ]
    )
    
    // ═══════════════════════════════════════════════════════════════
    // MARK: - Collections
    // ═══════════════════════════════════════════════════════════════
    
    /// All GGUF catalog entries.
    public static let allGGUF: [ModelDescriptor] = [
        llama3_2_1B_Q4,
        llama3_2_3B_Q4,
        gemma2_2B_Q4,
        phi3_mini_Q4,
        mistral7B_v03_Q4,
    ]
    
    /// All MLX catalog entries.
    public static let allMLX: [ModelDescriptor] = [
        llama3_2_1B_MLX,
        llama3_2_3B_MLX,
        gemma3_1B_MLX,
        qwen3_4B_MLX,
        mistral7B_v03_MLX,
    ]
    
    /// All catalog entries (GGUF + MLX).
    public static let all: [ModelDescriptor] = allGGUF + allMLX
    
    /// Look up a catalog entry by id.
    public static func find(_ id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }
}
