//
//  EmbeddedFrameworkLinkTests.swift
//  AbbayTests
//

import MachO
import XCTest

/// The app embeds `NetworkProvider.framework`, so it must link it through the runpath
/// (`@rpath/...`, resolved to `Abbay.app/Frameworks`). An absolute install name such as
/// `/Library/Frameworks/...` still runs in the simulator, which loads frameworks from the build
/// folder, but crashes a device install at launch with "Library not loaded".
///
/// The install name is recorded in the app binary when it links, in simulator builds as well, so
/// reading the host app's own load commands catches it here.
final class EmbeddedFrameworkLinkTests: XCTestCase {
    func test_appLinksEmbeddedFrameworks_throughTheRunpath() throws {
        // Debug builds put the app's code in Abbay.debug.dylib behind a stub executable, so the
        // framework is linked from whichever of the two holds it.
        let dylibs = try ["/Abbay.app/Abbay", "/Abbay.app/Abbay.debug.dylib"]
            .filter(Self.isLoaded)
            .flatMap(Self.linkedDylibs(ofImageNamed:))
        let embedded = dylibs.filter { $0.contains("NetworkProvider.framework") }

        XCTAssertEqual(embedded.count, 1, "the app should link NetworkProvider once; linked: \(dylibs)")
        for name in embedded {
            XCTAssertTrue(name.hasPrefix("@rpath/"), "\(name) is not found on a device; set DYLIB_INSTALL_NAME_BASE to @rpath")
        }
    }

    private static func isLoaded(_ suffix: String) -> Bool {
        (0..<_dyld_image_count()).contains { String(cString: _dyld_get_image_name($0)).hasSuffix(suffix) }
    }

    /// The `LC_LOAD_DYLIB` (and weak / re-export) names of the loaded image whose path ends with
    /// `suffix`.
    private static func linkedDylibs(ofImageNamed suffix: String) throws -> [String] {
        let index = try XCTUnwrap(
            (0..<_dyld_image_count()).first { String(cString: _dyld_get_image_name($0)).hasSuffix(suffix) },
            "the test host \(suffix) is not loaded"
        )
        let header = try XCTUnwrap(_dyld_get_image_header(index))
        let loadKinds = [UInt32(LC_LOAD_DYLIB), UInt32(LC_LOAD_WEAK_DYLIB), UInt32(LC_REEXPORT_DYLIB)]

        var names: [String] = []
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let load = command.load(as: load_command.self)
            if loadKinds.contains(load.cmd) {
                let dylib = command.load(as: dylib_command.self)
                let name = command.advanced(by: Int(dylib.dylib.name.offset)).assumingMemoryBound(to: CChar.self)
                names.append(String(cString: name))
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        return names
    }
}
