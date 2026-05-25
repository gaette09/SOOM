import Foundation

struct TerrainInsightBuilder {
    func build(from terrain: TerrainType) -> TerrainInsight {
        switch terrain.terrainType {
        case .flat:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "평지 중심",
                interpretation: "속도나 페이스 리듬을 차분히 확인하기 좋은 운동 맥락이에요."
            )
        case .rolling:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "롤링 지형",
                interpretation: "완만한 오르내림 속에서 리듬을 이어간 흐름으로 볼 수 있어요."
            )
        case .steadyClimb:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "꾸준한 오르막",
                interpretation: "오르막 비중이 있어 속도보다 호흡과 리듬 조절이 중요했던 코스예요."
            )
        case .longClimb:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "긴 오르막",
                interpretation: "긴 상승 흐름이 있어 후반 리듬과 에너지 배분을 함께 보면 좋아요."
            )
        case .urbanStopGo:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "도시형 리듬",
                interpretation: "멈춤과 재가속이 섞여 평균 속도보다 흐름 유지가 더 중요한 운동이에요."
            )
        case .trail:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "트레일/하이킹",
                interpretation: "지형 변화가 있어 거리보다 안정적인 움직임과 리듬이 더 잘 드러나요."
            )
        case .mixed:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "혼합 지형",
                interpretation: "평지와 완만한 변화가 섞여 전체 리듬을 함께 보는 게 좋아요."
            )
        case .insufficientData:
            return TerrainInsight(
                terrainType: terrain,
                terrainDescription: "지형 정보 부족",
                interpretation: "경로와 상승 데이터가 더 쌓이면 지형 흐름도 함께 보여줄게요."
            )
        }
    }

    func build(
        current: WorkoutGrowthInput,
        route: WorkoutRoute? = nil,
        splitMetrics: [WorkoutSplitMetric]? = nil
    ) -> TerrainInsight {
        build(from: TerrainTypeBuilder().build(current: current, route: route, splitMetrics: splitMetrics))
    }
}
