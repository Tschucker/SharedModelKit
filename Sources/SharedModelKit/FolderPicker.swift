#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers

/// A SwiftUI view modifier that presents a folder picker and saves
/// a security-scoped bookmark for cross-app model sharing.
///
/// ```swift
/// @State private var showPicker = false
/// let backend = BookmarkBackend()
///
/// Button("Choose Model Folder") { showPicker = true }
///     .sharedModelFolderPicker(isPresented: $showPicker, backend: backend) { result in
///         switch result {
///         case .success(let url): print("Folder set: \(url)")
///         case .failure(let error): print("Error: \(error)")
///         }
///     }
/// ```
public struct SharedModelFolderPicker: ViewModifier {
    @Binding var isPresented: Bool
    let backend: BookmarkBackend
    let onResult: (Result<URL, Error>) -> Void
    
    public func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try backend.saveBookmark(for: url)
                    onResult(.success(url))
                } catch {
                    onResult(.failure(error))
                }
            case .failure(let error):
                onResult(.failure(error))
            }
        }
    }
}

extension View {
    /// Present a folder picker to select the shared model storage directory.
    public func sharedModelFolderPicker(
        isPresented: Binding<Bool>,
        backend: BookmarkBackend,
        onResult: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        modifier(SharedModelFolderPicker(
            isPresented: isPresented,
            backend: backend,
            onResult: onResult
        ))
    }
}
#endif
