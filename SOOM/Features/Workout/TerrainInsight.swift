import Foundation

struct TerrainInsight: Equatable {
    let terrainType: TerrainType
    let terrainDescription: String
    let interpretation: String

    var isVisible: Bool {
        terrainType.terrainType != .insufficientData
    }
}
