import Foundation

final class MockWorkoutHarness: WorkoutHarness {
    private lazy var workouts: [Workout] = makeWorkouts()

    func loadWorkouts() -> [Workout] {
        workouts
    }

    func loadMonthlySnapshot() -> MonthlySnapshot {
        MonthlySnapshot(
            workoutCount: 27,
            trainingHours: 23.5,
            restDays: 3,
            highIntensityRatio: 37,
            conditionScore: 82,
            fatigueScore: 64,
            riskScore: 42,
            summaries: [
                MonthlySportSummary(sport: .swim, change: 12, volume: "14.2 km", sessions: 7, progress: 0.48),
                MonthlySportSummary(sport: .bike, change: 18, volume: "312 km", sessions: 9, progress: 0.82),
                MonthlySportSummary(sport: .run, change: 29, volume: "82 km", sessions: 11, progress: 0.64)
            ],
            insights: [
                AIInsight(title: "유산소 기반 상승", message: "최근 4주간 사이클과 러닝 볼륨이 안정적으로 늘었습니다.", priority: .positive),
                AIInsight(title: "러닝 증가 폭 주의", message: "러닝 거리가 빠르게 늘어 하퇴 피로 누적을 관리해야 합니다.", priority: .caution),
                AIInsight(title: "회복 세션 필요", message: "다음 7일은 고강도보다 회복과 기술 세션을 섞는 편이 좋습니다.", priority: .action)
            ],
            recommendations: [
                AIRecommendation(title: "가벼운 조깅", detail: "40분 Z2, 보폭보다 착지 안정성에 집중", targetDay: "월"),
                AIRecommendation(title: "수영 기술", detail: "풀부이 8 x 100m, 호흡 리듬 확인", targetDay: "수"),
                AIRecommendation(title: "브릭 적응", detail: "사이클 60분 뒤 15분 이지런", targetDay: "토")
            ]
        )
    }

    func loadFeedPosts() -> [FeedPost] {
        let items = loadWorkouts()
        return [
            FeedPost(
                athleteName: "정지환",
                handle: "@soom.jh",
                title: "한강 유산소 러닝",
                caption: "초반은 편하게, 마지막 2km는 리듬만 살렸습니다. 회복은 괜찮고 내일은 수영으로 풀 예정입니다.",
                sport: .run,
                distance: items[0].formattedDistance,
                duration: items[0].formattedDuration,
                likes: 128,
                comments: 18,
                linkedWorkout: items[0]
            ),
            FeedPost(
                athleteName: "김소연",
                handle: "@tri.soyeon",
                title: "남산 업힐 템포",
                caption: "업힐에서 파워가 흔들리지 않게 5분 반복을 맞췄어요. 다음 주는 FTP 테스트 전 정리 주간.",
                sport: .bike,
                distance: items[2].formattedDistance,
                duration: items[2].formattedDuration,
                likes: 96,
                comments: 9,
                linkedWorkout: items[2]
            ),
            FeedPost(
                athleteName: "박도윤",
                handle: "@openwater.dy",
                title: "오픈워터 감각 회복",
                caption: "시야 확보와 호흡 안정성 위주로 진행했습니다. 페이스보다 방향 전환 감각이 좋아졌어요.",
                sport: .swim,
                distance: items[4].formattedDistance,
                duration: items[4].formattedDuration,
                likes: 74,
                comments: 6,
                linkedWorkout: items[4]
            )
        ]
    }

    func loadClubs() -> [Club] {
        [
            Club(
                name: "SOOM 분당 트라이",
                location: "경기 성남",
                description: "수영, 사이클, 러닝을 균형 있게 쌓는 생활 철인3종 클럽입니다.",
                memberCount: 184,
                weeklyVolume: "1,260 km",
                tags: ["초보 환영", "주말 브릭", "오픈워터"],
                upcoming: ["토 07:00 탄천 브릭", "수 20:30 수영 자세반"]
            ),
            Club(
                name: "한강 새벽 라이더스",
                location: "서울 여의도",
                description: "출근 전 60-90분 사이클 훈련을 꾸준히 이어가는 그룹입니다.",
                memberCount: 96,
                weeklyVolume: "2,840 km",
                tags: ["사이클", "새벽훈련", "파워기반"],
                upcoming: ["화 06:00 Z2 팩라이드", "일 06:30 남산 반복"]
            )
        ]
    }
}

private extension MockWorkoutHarness {
    func makeWorkouts() -> [Workout] {
        [
            Workout(
                id: UUID(),
                sport: .run,
                title: "유산소 러닝",
                date: date(2026, 5, 15, 6, 40),
                distanceMeters: 10_400,
                duration: 3_120,
                activeCalories: 676,
                avgHeartRate: 151,
                maxHeartRate: 175,
                avgPower: nil,
                elevationGain: 78,
                cadence: 174,
                effort: 6,
                source: "Apple Watch Ultra",
                route: yeouidoRoute,
                splits: runSplits,
                samples: samples(durationMinutes: 52, heartBase: 148, paceBase: 300, powerBase: nil),
                zones: zones,
                achievements: ["이번 달 가장 안정적인 Z2 러닝", "후반 2km 페이스 유지"],
                aiSummary: "심박 상승 폭이 완만하고 후반 페이스 유지가 좋습니다. 다음 러닝은 강도보다 회복 리듬을 우선하세요."
            ),
            Workout(
                id: UUID(),
                sport: .swim,
                title: "기준 페이스 자세 세트",
                date: date(2026, 5, 14, 20, 15),
                distanceMeters: 2_300,
                duration: 2_700,
                activeCalories: 418,
                avgHeartRate: 132,
                maxHeartRate: 154,
                avgPower: nil,
                elevationGain: 0,
                cadence: nil,
                effort: 5,
                source: "SOOM 더미 하네스",
                route: [],
                splits: swimSplits,
                samples: samples(durationMinutes: 45, heartBase: 130, paceBase: 118, powerBase: nil),
                zones: zones,
                achievements: ["100m 반복 페이스 편차 3초", "호흡 리듬 개선"],
                aiSummary: "페이스 편차가 줄고 기술 집중도가 좋습니다. 다음 수영은 200m 지속주로 연결해도 좋습니다."
            ),
            Workout(
                id: UUID(),
                sport: .bike,
                title: "템포 인터벌",
                date: date(2026, 5, 13, 6, 20),
                distanceMeters: 46_200,
                duration: 5_400,
                activeCalories: 1_120,
                avgHeartRate: 148,
                maxHeartRate: 171,
                avgPower: 214,
                elevationGain: 420,
                cadence: 88,
                effort: 7,
                source: "Garmin Edge",
                route: bikeRoute,
                splits: bikeSplits,
                samples: samples(durationMinutes: 90, heartBase: 146, paceBase: 118, powerBase: 214),
                zones: zones,
                achievements: ["20분 파워 안정", "업힐 케이던스 유지"],
                aiSummary: "템포 구간 파워가 안정적입니다. 러닝 전환을 고려하면 다음 세션은 짧은 브릭이 좋습니다."
            ),
            Workout(
                id: UUID(),
                sport: .run,
                title: "빌드업 러닝",
                date: date(2026, 5, 11, 19, 10),
                distanceMeters: 8_800,
                duration: 2_640,
                activeCalories: 590,
                avgHeartRate: 158,
                maxHeartRate: 181,
                avgPower: nil,
                elevationGain: 64,
                cadence: 178,
                effort: 8,
                source: "Apple Watch Ultra",
                route: yeouidoRoute.reversed(),
                splits: runSplits,
                samples: samples(durationMinutes: 44, heartBase: 156, paceBase: 292, powerBase: nil),
                zones: zones,
                achievements: ["마지막 1km 최고 페이스", "강도 적응 확인"],
                aiSummary: "강도는 좋았지만 회복 여유가 크지 않습니다. 다음날 하체 피로를 반드시 체크하세요."
            ),
            Workout(
                id: UUID(),
                sport: .swim,
                title: "오픈워터 감각 회복",
                date: date(2026, 5, 10, 8, 0),
                distanceMeters: 1_850,
                duration: 2_160,
                activeCalories: 370,
                avgHeartRate: 126,
                maxHeartRate: 146,
                avgPower: nil,
                elevationGain: 0,
                cadence: nil,
                effort: 4,
                source: "SOOM 더미 하네스",
                route: openWaterRoute,
                splits: swimSplits,
                samples: samples(durationMinutes: 36, heartBase: 126, paceBase: 116, powerBase: nil),
                zones: zones,
                achievements: ["방향 전환 안정", "호흡 패턴 회복"],
                aiSummary: "오픈워터 적응 목적에 맞는 낮은 강도입니다. 다음은 부이 기준 sighting 빈도를 줄여보세요."
            )
        ]
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    func samples(durationMinutes: Int, heartBase: Int, paceBase: Double, powerBase: Int?) -> [WorkoutSample] {
        (0..<24).map { index in
            let progress = Double(index) / 23.0
            let wave = sin(progress * .pi * 2.0)
            return WorkoutSample(
                minute: progress * Double(durationMinutes),
                heartRate: heartBase + Int(wave * 8) + Int(progress * 10),
                paceSeconds: paceBase - wave * 8 - progress * 6,
                power: powerBase.map { $0 + Int(wave * 18) + Int(progress * 12) }
            )
        }
    }

    var zones: [HeartRateZone] {
        [
            HeartRateZone(name: "Z1 회복", minutes: 8, tint: SOOMColor.recovery),
            HeartRateZone(name: "Z2 유산소", minutes: 28, tint: SOOMColor.bike),
            HeartRateZone(name: "Z3 템포", minutes: 12, tint: SOOMColor.warning),
            HeartRateZone(name: "Z4 역치", minutes: 4, tint: SOOMColor.run)
        ]
    }

    var runSplits: [WorkoutSplit] {
        (1...10).map { index in
            WorkoutSplit(label: "\(index) km", distance: "1.0 km", time: index < 8 ? "5:02" : "4:48", pace: index < 8 ? "5:02/km" : "4:48/km", heartRate: 142 + index * 3, power: nil)
        }
    }

    var swimSplits: [WorkoutSplit] {
        (1...5).map { index in
            WorkoutSplit(label: "\(index)", distance: "400 m", time: index < 4 ? "7:45" : "7:32", pace: index < 4 ? "1:56/100m" : "1:53/100m", heartRate: 124 + index * 3, power: nil)
        }
    }

    var bikeSplits: [WorkoutSplit] {
        (1...6).map { index in
            WorkoutSplit(label: "\(index)", distance: "7.7 km", time: "15:00", pace: "30.8 km/h", heartRate: 136 + index * 4, power: 196 + index * 8)
        }
    }

    var yeouidoRoute: [RoutePoint] {
        [
            RoutePoint(latitude: 37.5280, longitude: 126.9210),
            RoutePoint(latitude: 37.5274, longitude: 126.9258),
            RoutePoint(latitude: 37.5255, longitude: 126.9314),
            RoutePoint(latitude: 37.5228, longitude: 126.9355),
            RoutePoint(latitude: 37.5198, longitude: 126.9302),
            RoutePoint(latitude: 37.5211, longitude: 126.9241),
            RoutePoint(latitude: 37.5244, longitude: 126.9208),
            RoutePoint(latitude: 37.5280, longitude: 126.9210)
        ]
    }

    var bikeRoute: [RoutePoint] {
        [
            RoutePoint(latitude: 37.5382, longitude: 126.9966),
            RoutePoint(latitude: 37.5427, longitude: 127.0022),
            RoutePoint(latitude: 37.5484, longitude: 127.0069),
            RoutePoint(latitude: 37.5528, longitude: 127.0008),
            RoutePoint(latitude: 37.5489, longitude: 126.9914),
            RoutePoint(latitude: 37.5425, longitude: 126.9892),
            RoutePoint(latitude: 37.5382, longitude: 126.9966)
        ]
    }

    var openWaterRoute: [RoutePoint] {
        [
            RoutePoint(latitude: 37.5038, longitude: 127.0981),
            RoutePoint(latitude: 37.5048, longitude: 127.1002),
            RoutePoint(latitude: 37.5034, longitude: 127.1028),
            RoutePoint(latitude: 37.5016, longitude: 127.1014),
            RoutePoint(latitude: 37.5023, longitude: 127.0989),
            RoutePoint(latitude: 37.5038, longitude: 127.0981)
        ]
    }
}
