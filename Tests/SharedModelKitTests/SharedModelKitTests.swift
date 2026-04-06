import XCTest
@testable import SharedModelKit

final class SharedModelKitTests: XCTestCase {
    
    func testModelDescriptorInit() {
        let model = ModelDescriptor(
            id: "test-model",
            name: "Test Model",
            family: "llama",
            parameterCount: "3B",
            quantization: "Q4_K_M",
            format: .gguf
        )
        XCTAssertEqual(model.id, "test-model")
        XCTAssertEqual(model.filename, "test-model.gguf")
    }
    
    func testModelFormatExtensions() {
        XCTAssertEqual(ModelFormat.gguf.fileExtension, "gguf")
        XCTAssertEqual(ModelFormat.safetensors.fileExtension, "safetensors")
        XCTAssertEqual(ModelFormat.coreml.fileExtension, "mlmodelc")
    }
    
    func testLocalBackendIsAvailable() async {
        let backend = LocalDirectoryBackend()
        let available = await backend.isAvailable()
        XCTAssertTrue(available)
    }
    
    func testModelStoreLocateReturnsNilWhenEmpty() async {
        let backend = LocalDirectoryBackend(subdirectory: "SharedModelKitTests/Empty")
        let store = ModelStore(backend: backend)
        
        let model = ModelDescriptor(
            id: "nonexistent",
            name: "Nonexistent",
            family: "test",
            parameterCount: "1B",
            quantization: "Q4_K_M",
            format: .gguf
        )
        let result = await store.locate(model)
        XCTAssertNil(result)
    }
    
    func testCatalogEntriesHaveFilenames() {
        for model in ModelCatalog.all {
            XCTAssertFalse(model.filename.isEmpty)
            XCTAssertTrue(model.filename.hasSuffix(".gguf"))
        }
    }
}
