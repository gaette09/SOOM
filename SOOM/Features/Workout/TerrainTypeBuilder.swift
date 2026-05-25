import Foundation

struct TerrainTypeBuilder {
    func build(
        current: WorkoutGrowthInput,
        route: WorkoutRoute? = nil,
        splitMetrics: [WorkoutSplitMetric]? = nil
    ) -> TerrainType {
        guard let distanceKm = distanceKm(for: current, route: route),
              distanceKm >= 0.5 else {
            return .insufficientData
        }

        guard let elevationGain = elevationGain(for: current, route: route) else {
            return .insufficientData
        }

        let grade = elevationGain / (distanceKm * 1_000) * 100

        if isUrbanStopGo(splitMetrics: splitMetrics ?? [], grade: grade) {
            return TerrainType(
                terrainType: .urbanStopGo,
                summary: "멈춤과 재가속이 섞인 도시형 리듬에 가까워요.",
                difficulty: .moderate
            )
        }

        if isTrailLike(current: current, elevationGain: elevationGain, grade: grade, distanceKm: distanceKm) {
            return TerrainType(
                terrainType: .trail,
                summary: "지형 변화가 있는 트레일/하이킹 흐름에 가까워요.",
                difficulty: elevationGain >= 450 || grade >= 6 ? .challenging : .moderate
            )
        }

        if elevationGain >= 500 || (current.durationMinutes >= 120 && grade >= 3.5) {
            return TerrainType(
                terrainType: .longClimb,
                summary: "긴 오르막 흐름이 이어진 코스였어요.",
                difficulty: .challenging
            )
        }

        if grade >= 2.5 || elevationGain >= 220 {
            return TerrainType(
                terrainType: .steadyClimb,
                summary: "오르막 비중이 꾸준히 느껴지는 코스였어요.",
                difficulty: grade >= 4.5 || elevationGain >= 350 ? .challenging : .moderate
            )
        }

        if isRolling(route: route, elevationGain: elevationGain, grade: grade, distanceKm: distanceKm) {
            return TerrainType(
                terrainType: .rolling,
                summary: "완만한 오르내림이 반복된 흐름이었어요.",
                difficulty: .moderate
            )
        }

        if elevationGain <= 35 || grade < 0.6 {
            return TerrainType(
                terrainType: .flat,
                summary: "평지 중심으로 리듬을 유지하기 좋은 코스였어요.",
                difficulty: .light
            )
        }

        return TerrainType(
            terrainType: .mixed,
            summary: "평지와 완만한 지형 변화가 섞인 코스였어요.",
            difficulty: .moderate
        )
    }

    private func elevationGain(for input: WorkoutGrowthInput, route: WorkoutRoute?) -> Double? {
        if let routeElevation = route?.totalElevationGain {
            return routeElevation
        }
        return input.elevationGainMeters
    }

    private func distanceKm(for input: WorkoutGrowthInput, route: WorkoutRoute?) -> Double? {
        if let route, route.totalDistanceMeters > 0 {
            return route.totalDistanceMeters / 1_000
        }
        return input.distanceKm
    }

    private func isTrailLike(
        current: WorkoutGrowthInput,
        elevationGain: Double,
        grade: Double,
        distanceKm: Double
    ) -> Bool {
        guard current.workoutType == .hiking else {
            return false
        }

        let speedKmh = current.averageSpeedKmh ?? speedFromDuration(distanceKm: distanceKm, durationMinutes: current.durationMinutes)
        return elevationGain >= 120 || grade >= 2.5 || speedKmh <= 6
    }

    private func isRolling(
        route: WorkoutRoute?,
        elevationGain: Double,
        grade: Double,
        distanceKm: Double
    ) -> Bool {
        guard elevationGain >= 45, grade < 2.5, distanceKm >= 3 else {
            return false
        }

        guard let route else {
            return true
        }

        let directionChanges = altitudeDirectionChanges(in: route.coordinates)
        return directionChanges >= 2 || elevationGain >= 80
    }

    private func isUrbanStopGo(splitMetrics: [WorkoutSplitMetric], grade: Double) -> Bool {
        guard splitMetrics.count >= 4, grade < 1.2 else {
            return false
        }

        let speeds = splitMetrics.compactMap(\.averageSpeed).filter { $0 > 0 }
        guard speeds.count >= 4,
              let minSpeed = speeds.min(),
              let maxSpeed = speeds.max(),
              maxSpeed > 0 else {
            return false
        }

        return minSpeed / maxSpeed < 0.55
    }

    private func altitudeDirectionChanges(in coordinates: [WorkoutRouteCoordinate]) -> Int {
        let altitudes = coordinates.compactMap(\.altitude)
        guard altitudes.count >= 4 else {
            return 0
        }

        var changes = 0
        var previousDirection = 0

        for index in 1..<altitudes.count {
            let delta = altitudes[index] - altitudes[index - 1]
            guard abs(delta) >= 2 else { continue }
            let direction = delta > 0 ? 1 : -1
            if previousDirection != 0 && direction != previousDirection {
                changes += 1
            }
            previousDirection = direction
        }

        return changes
    }

    private func speedFromDuration(distanceKm: Double, durationMinutes: Int) -> Double {
        guard durationMinutes > 0 else { return 0 }
        return distanceKm / (Double(durationMinutes) / 60)
    }
}
