import XCTest
@testable import SOOM

final class Feed61ActivationPolicyTests: XCTestCase {
    func testProfileOnlyV2LegacyPreviewCapabilityMustNotDisableVisibleBatch() {
        // Regression was RED against build60's extracted behavior. A legacy v1
        // capability is not the current v2 presentation mode or authorization.
        XCTAssertTrue(Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: true,
            readPolicy: .profileOnlyV2, legacyPreviewEnabled: true,
            audience: .home, pageUnsupported: false))
    }

    func testProfileOnlyV2WithoutLegacyCapabilityRetainsEnabledPath() {
        XCTAssertTrue(Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: true,
            readPolicy: .profileOnlyV2, legacyPreviewEnabled: false,
            audience: .home, pageUnsupported: false))
    }

    func testDisabledReleaseCannotBeActivatedByEitherLegacyCapability() {
        for legacy in [false, true] {
            XCTAssertFalse(Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: false,
                readPolicy: .profileOnlyV2, legacyPreviewEnabled: legacy,
                audience: .home, pageUnsupported: false))
        }
    }

    func testV1NeverUsesV2BatchAcrossCapabilityAudienceAndSupportMatrix() {
        for legacy in [false, true] {
            for audience in FeedAudience.allCases {
                for unsupported in [false, true] {
                    XCTAssertFalse(Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: true,
                        readPolicy: .approvedFollowersV1, legacyPreviewEnabled: legacy,
                        audience: audience, pageUnsupported: unsupported))
                }
            }
        }
    }

    func testNonHomeAudiencesCannotUseHomeBatchWithEitherCapability() {
        for audience in [FeedAudience.all, .following] {
            for legacy in [false, true] {
                XCTAssertFalse(Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: true,
                    readPolicy: .profileOnlyV2, legacyPreviewEnabled: legacy,
                    audience: audience, pageUnsupported: false))
            }
        }
    }

    func testUnsupportedPageCannotUseBatchWithEitherCapability() {
        for legacy in [false, true] {
            XCTAssertFalse(Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: true,
                readPolicy: .profileOnlyV2, legacyPreviewEnabled: legacy,
                audience: .home, pageUnsupported: true))
        }
    }
    func testProfileOnlyV2DoesNotRequestLegacyPreviewCapabilityRPC() {
        XCTAssertFalse(Feed61ActivationPolicy.needsLegacyPreviewCapability(readPolicy: .profileOnlyV2))
    }

    func testV1RetainsItsLegacyPreviewCapabilityRPC() {
        XCTAssertTrue(Feed61ActivationPolicy.needsLegacyPreviewCapability(readPolicy: .approvedFollowersV1))
    }

    func testLegacyCapabilityCannotChangeV2ActivationAcrossReleaseAudienceAndSupportMatrix() {
        for release in [false, true] {
            for audience in FeedAudience.allCases {
                for unsupported in [false, true] {
                    let expected = release && audience == .home && !unsupported
                    for legacy in [false, true] {
                        XCTAssertEqual(Feed61ActivationPolicy.usesVisibleBatch(releaseEnabled: release,
                            readPolicy: .profileOnlyV2, legacyPreviewEnabled: legacy,
                            audience: audience, pageUnsupported: unsupported), expected)
                    }
                }
            }
        }
    }

}
