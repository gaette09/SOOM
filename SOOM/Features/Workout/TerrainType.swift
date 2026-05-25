import Foundation

struct TerrainType: Equatable {
    let terrainType: Kind
    let summary: String
    let difficulty: Difficulty?

    enum Kind: String, Equatable {
        case flat
        case rolling
        case steadyClimb
        case longClimb
        case urbanStopGo
        case trail
        case mixed
        case insufficientData
    }

    enum Difficulty: String, Equatable {
        case light
        case moderate
        case challenging
    }

    static let insufficientData = TerrainType(
        terrainType: .insufficientData,
        summary: "지형을 판단할 만큼의 경로 정보가 아직 부족해요.",
        difficulty: nil
    )
}
