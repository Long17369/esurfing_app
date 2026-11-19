import Darwin
import XCTest

class RunnerTests: XCTestCase {
  func testBundledNativeLibraryCreatesAndDestroysClient() throws {
    let libraryURL = try XCTUnwrap(Bundle.main.privateFrameworksURL)
      .appendingPathComponent("libesurfing.dylib")
    let library = try XCTUnwrap(dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Version = @convention(c) () -> UnsafePointer<CChar>?
    typealias Create = @convention(c) (Int32) -> UnsafeMutableRawPointer?
    typealias Destroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
    let version = unsafeBitCast(try XCTUnwrap(dlsym(library, "esf_version")), to: Version.self)
    let create = unsafeBitCast(try XCTUnwrap(dlsym(library, "esf_create")), to: Create.self)
    let destroy = unsafeBitCast(try XCTUnwrap(dlsym(library, "esf_destroy")), to: Destroy.self)
    XCTAssertFalse(String(cString: try XCTUnwrap(version())).isEmpty)
    XCTAssertNotNil(dlsym(library, "esf_set_owned_event_cb"))
    let client = try XCTUnwrap(create(0))
    destroy(client)
  }
}
