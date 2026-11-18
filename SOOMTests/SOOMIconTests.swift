import SwiftUI
import UIKit
import XCTest
@testable import SOOM

final class SOOMIconTests: XCTestCase {
    func testEveryMappedAndSelectedIconIsABundledNativeSymbol() throws {
        for key in SOOMPhosphorCatalog.aliases.keys.sorted() {
            for selected in [false, true] {
                let name = SOOMPhosphorCatalog.assetName(for: key, selected: selected)
                let image = try XCTUnwrap(UIImage(named: name), "Missing icon: \(key) → \(name)")
                XCTAssertTrue(image.isSymbolImage, "\(name) must preserve native symbol sizing")
            }
        }
    }

    func testUIKitSymbolConfigurationPreservesPointSize() throws {
        let small = try XCTUnwrap(UIImage(soom: SOOMIcon.medal, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14)))
        let large = try XCTUnwrap(UIImage(soom: SOOMIcon.medal, withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)))
        XCTAssertTrue(small.isSymbolImage)
        XCTAssertGreaterThan(large.size.width, small.size.width * 1.7)
        XCTAssertGreaterThan(large.size.height, small.size.height * 1.7)
    }

    func testSelectedStateAndStoredLegacyKeysKeepTheirMeaning() {
        XCTAssertEqual(SOOMPhosphorCatalog.assetName(for: "bookmark"), "soom-ph-bookmark-simple")
        XCTAssertEqual(SOOMPhosphorCatalog.assetName(for: "bookmark.fill"), "soom-ph-bookmark-simple-fill")
        XCTAssertEqual(SOOMPhosphorCatalog.assetName(for: "bookmark.fill", selected: true), "soom-ph-bookmark-simple-fill")
        XCTAssertEqual(SOOMPhosphorCatalog.assetName(for: SOOMIcon.home, selected: true), "soom-ph-house-fill")
        XCTAssertEqual(SOOMPhosphorCatalog.assetName(for: "remote-unknown-icon"), "soom-ph-question")
        XCTAssertTrue(SOOMPhosphorCatalog.isBrandSymbol("apple.logo"))
        XCTAssertFalse(SOOMPhosphorCatalog.isBrandSymbol("house.fill"))
    }

    func testUpstreamLicenseIsIncludedInDistributedAssetCatalog() throws {
        let data = try XCTUnwrap(NSDataAsset(name: "PhosphorLicense"))
        let text = try XCTUnwrap(String(data: data.data, encoding: .utf8))
        XCTAssertTrue(text.contains("Phosphor Icons"))
        XCTAssertTrue(text.contains("Permission is hereby granted"))
        XCTAssertTrue(text.contains("THE SOFTWARE IS PROVIDED"))
    }

    @MainActor
    func testNativeImageAndLabelInitializersKeepModifierAndGenericCompatibility() {
        // Image-specific return types and native Label/ContentUnavailableView
        // constraints must continue compiling after the source migration.
        let image: Image = Image(soom: SOOMIcon.map).renderingMode(.template).resizable()
        let label: Label<Text, Image> = Label("저장", soomIcon: SOOMIcon.bookmark)
        let dynamicTitle = String("사용자 신고")
        let dynamicLabel: Label<Text, Image> = Label(dynamicTitle, soomIcon: "flag")
        let button = Button(dynamicTitle, soomIcon: "flag", role: .destructive) { }
        let empty = ContentUnavailableView("기록 없음", soomIcon: SOOMIcon.activity, description: Text("운동 후 확인해 주세요."))
        _ = image.font(.title).imageScale(.large)
        _ = label.labelStyle(.titleAndIcon)
        _ = dynamicLabel
        _ = button
        _ = empty
    }
}
