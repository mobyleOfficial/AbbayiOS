//
//  ConstantsBundleTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Colors and spacing live in plists at the app bundle's root. With an in-app language chosen in
/// Settings, `AbbayBundle.value` is that language's `.lproj`, which doesn't hold them, so reading
/// them through it trapped on the next launch (#155): within the session that picked the
/// language, the plists were already cached.
final class ConstantsBundleTests: XCTestCase {
    override func tearDownWithError() throws {
        AbbayBundle.languageCode = nil
        try super.tearDownWithError()
    }

    func test_constants_loadOnAColdLaunch_withAnInAppLanguage() {
        for language in ["en", "pt-BR"] {
            AbbayBundle.languageCode = language
            LocalStorage.data.removeValue(forKey: ColorConstants.onyx.resource)
            LocalStorage.data.removeValue(forKey: SpaceConstants.sx8.resource)

            XCTAssertNotNil(ColorConstants.onyx.uiColor.cgColor, language)
            XCTAssertGreaterThan(SpaceConstants.sx8.value, 0, language)
        }
    }
}
