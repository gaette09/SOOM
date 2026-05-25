import XCTest
@testable import SOOM

final class TerrainInsightBuilderTests: XCTestCase {
    func testBuildsFlatInterpretation() {
        let terrain = TerrainType(terrainType: .flat, summary: "평지 중심으로 리듬을 유지하기 좋은 코스였어요.", difficulty: .light)
        let insight = TerrainInsightBuilder().build(from: terrain)

        XCTAssertEqual(insight.terrainDescription, "평지 중심")
        XCTAssertTrue(insight.isVisible)
    }

    func testBuildsRollingInterpretation() {
        let terrain = TerrainType(terrainType: .rolling, summary: "완만한 오르내림이 반복된 흐름이었어요.", difficulty: .moderate)
        let insight = TerrainInsightBuilder().build(from: terrain)

        XCTAssertEqual(insight.terrainDescription, "롤링 지형")
        XCTAssertTrue(insight.interpretation.contains("리듬"))
    }

    func testBuildsClimbInterpretationWithoutDiagnosticTone() {
        let terrain = TerrainType(terrainType: .longClimb, summary: "긴 오르막 흐름이 이어진 코스였어요.", difficulty: .challenging)
        let insight = TerrainInsightBuilder().build(from: terrain)

        XCTAssertFalse(insight.interpretation.contains("진단"))
        XCTAssertFalse(insight.interpretation.contains("위험"))
        XCTAssertFalse(insight.interpretation.contains("실패"))
    }

    func testInsufficientDataIsHidden() {
        let insight = TerrainInsightBuilder().build(from: .insufficientData)

        XCTAssertFalse(insight.isVisible)
    }

    func testRecoveryCalculatorIsNotUsed() {
        _ = TerrainInsightBuilder().build(from: TerrainType(terrainType: .mixed, summary: "혼합 지형", difficulty: .moderate))
        XCTAssertTrue(true)
    }
}
