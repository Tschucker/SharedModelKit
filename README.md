# SharedModelKit

A Swift framework that lets iOS and macOS apps share local AI model files instead of each app downloading its own multi-gigabyte copy.

## The Problem

Every on-device AI app downloads its own copy of the same model. Three apps using Llama 3.2 3B? That's **~6 GB × 3 = 18 GB** of redundant data on one device.

## The Solution

SharedModelKit provides a common storage layer. Apps point at a shared folder (via the Files app, iCloud Drive, or an App Group), and the first app to need a model downloads it — every subsequent app finds it instantly.

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│  App A   │  │  App B   │  │  App C   │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │
     └─────────────┼─────────────┘
                   │
          ┌────────▼────────┐
          │ SharedModelKit  │
          └────────┬────────┘
                   │
          ┌────────▼────────┐
          │  Shared Folder  │
          │  (iCloud Drive  │
          │   / Files app)  │
          └─────────────────┘
```

## Quick Start

### 1. Add the Package

```swift
// Package.swift
.package(url: "https://github.com/yourname/SharedModelKit.git", from: "0.1.0")
```

### 2. Let the User Pick a Shared Folder

```swift
import SharedModelKit
import SwiftUI

struct SettingsView: View {
    @State private var showPicker = false
    let backend = BookmarkBackend()

    var body: some View {
        Button("Choose Model Folder") { showPicker = true }
            .sharedModelFolderPicker(isPresented: $showPicker, backend: backend) { result in
                if case .success(let url) = result {
                    print("Models will be stored in: \(url.path)")
                }
            }
    }
}
```

The user picks a folder once (e.g. "AI Models" in iCloud Drive). The bookmark persists across launches.

### 3. Get a Model

```swift
let store = ModelStore(backend: BookmarkBackend())

// Use a catalog entry or define your own
let url = try await store.modelURL(for: ModelCatalog.llama3_2_3B_Q4) { received, total in
    let pct = total.map { Double(received) / Double($0) * 100 } ?? 0
    print("Downloading: \(Int(pct))%")
}

// url is a file path — pass it to llama.cpp, MLX, Core ML, etc.
```

If another app already downloaded the model to the shared folder, this returns instantly.

## Storage Backends

| Backend | Use Case | Cross-App? |
|---|---|---|
| `BookmarkBackend` | User picks a folder in Files/iCloud Drive | ✅ Any developer |
| `AppGroupBackend` | Shared App Group container | Same team only |
| `LocalDirectoryBackend` | App sandbox fallback / dev | ❌ Single app |

You can chain multiple backends — the store searches them in order:

```swift
let store = ModelStore(backends: [
    BookmarkBackend(),          // check shared folder first
    AppGroupBackend(groupIdentifier: "group.com.yourteam.models"),
    LocalDirectoryBackend(),    // fallback to local cache
])
```

## Defining Custom Models

```swift
let myModel = ModelDescriptor(
    id: "my-custom-model-Q8_0",
    name: "My Fine-Tuned Model",
    family: "llama",
    parameterCount: "3B",
    quantization: "Q8_0",
    format: .gguf,
    expectedSizeBytes: 3_500_000_000,
    sha256: "abc123...",
    remoteURL: URL(string: "https://huggingface.co/..."),
    filename: "my-custom-model.Q8_0.gguf"
)
```

## Model Discovery

Find all models that exist across backends:

```swift
let models = await store.discoveredModels()
for model in models {
    print("\(model.descriptor.name) — \(model.fileSize ?? 0) bytes via \(model.backend.name)")
}
```

## Security-Scoped Access

For bookmark-based backends, use `withAccess` to properly scope file access:

```swift
if let located = await store.locate(ModelCatalog.mistral7B_v03_Q4) {
    located.withAccess { url in
        // Safe to read the file here
        let data = try Data(contentsOf: url)
    }
}
```

## Integrity Verification

```swift
let valid = try await store.verify(ModelCatalog.llama3_2_3B_Q4)
```

SHA-256 is checked automatically on download if the descriptor includes a hash.

## Requirements

- iOS 16+ / macOS 13+
- Swift 5.9+

## How It Works

1. **Standardized filenames** — The catalog and descriptors ensure every app looks for `Llama-3.2-3B-Instruct-Q4_K_M.gguf`, not a custom name.
2. **Security-scoped bookmarks** — The user grants folder access once; the bookmark persists across launches without re-prompting.
3. **Sidecar manifests** — When a model is downloaded, a `.json` sidecar is written alongside it so other apps can identify the model metadata.
4. **Download coalescing** — Multiple concurrent requests for the same model within an app share a single download task.

## Contributing

PRs welcome. Key areas of interest:

- Additional `ModelCatalog` entries with verified hashes and URLs
- Background download support via `URLSessionDownloadTask`
- Resumable downloads
- iCloud Drive conflict resolution
- Model format converters

## License

MIT
