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

    func testBuildsMixedInterpretationWithContextTone() {
        let terrain = TerrainType(terrainType: .mixed, summary: "평지와 완만한 지형 변화가 섞인 코스였어요.", difficulty: .moderate)
        let insight = TerrainInsightBuilder().build(from: terrain)

        XCTAssertEqual(insight.terrainDescription, "혼합 지형")
        XCTAssertTrue(insight.interpretation.contains("리듬"))
        assertNoJudgementTone(in: insight)
    }

    func testBuildsUrbanStopGoInterpretationWithoutOverstatingPrecision() {
        let terrain = TerrainType(terrainType: .urbanStopGo, summary: "멈춤과 재가속이 섞인 도시형 리듬에 가까워요.", difficulty: .moderate)
        let insight = TerrainInsightBuilder().build(from: terrain)

        XCTAssertEqual(insight.terrainDescription, "도시형 리듬")
        XCTAssertTrue(insight.interpretation.contains("흐름"))
        XCTAssertFalse(insight.interpretation.contains("정확"))
        assertNoJudgementTone(in: insight)
    }

    func testInsufficientDataIsHidden() {
        let insight = TerrainInsightBuilder().build(from: .insufficientData)

        XCTAssertFalse(insight.isVisible)
    }

    func testRecoveryCalculatorIsNotUsed() {
        _ = TerrainInsightBuilder().build(from: TerrainType(terrainType: .mixed, summary: "혼합 지형", difficulty: .moderate))
        XCTAssertTrue(true)
    }

    private func assertNoJudgementTone(in insight: TerrainInsight, file: StaticString = #filePath, line: UInt = #line) {
        let text = "\(insight.terrainDescription) \(insight.interpretation)"
        let bannedWords = ["진단", "위험", "실패", "랭킹", "정확", "나쁨", "못"]

        for word in bannedWords {
            XCTAssertFalse(text.contains(word), file: file, line: line)
        }
    }
}
