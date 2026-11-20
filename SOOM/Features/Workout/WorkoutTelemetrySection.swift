import Charts
import SwiftUI

/// One measured-detail UI shared by every provider. Averages are displayed as
/// summaries only; a missing stream does not create a fabricated chart or zone.
struct WorkoutTelemetrySection: View {
    let telemetry: WorkoutTelemetry
    let workout: UnifiedWorkout
    var route: WorkoutRoute?
    var sharedMeasurementOnly = false
    var showsHeartRateZones = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workoutDetailReduceMotion) private var previewReduced
    private var motionReduced: Bool { reduceMotion || previewReduced }
    @Environment(\.workoutRevealContext) private var revealContext
    @State private var presentationCache = WorkoutTelemetryPresentationCache()
    @Environment(\.workoutDetailPresentationStore) private var presentationStore
    @State private var swimExplanation: SwimExplanation?
    private enum SwimExplanation: String, Identifiable {
        case setCalculation, poolLength, appleHeartRateZones, calculatedHeartRateZones
        var id: String { rawValue }
        var title: String {
            switch self {
            case .setCalculation: "수영 세트 계산"
            case .poolLength: "수영장 길이 출처"
            case .appleHeartRateZones, .calculatedHeartRateZones: "심박 구간 출처"
            }
        }
    }
    @ScaledMetric(relativeTo: .subheadline) private var zoneRowHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .subheadline) private var zoneMinimumWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .subheadline) private var zoneStatisticsWidth: CGFloat = 92

    private var display: WorkoutTelemetry {
        presentationCache.prepare(telemetry, workout: workout, route: route)
    }
    private var zoneMaximum: Double { sharedMeasurementOnly ? 190 : Double(TrainingSettingsStore.shared.loadZoneBaseline().maxHeartRate ?? 190) }
    private var isOwnerAppleHistory: Bool {
        !sharedMeasurementOnly && workout.source == .appleHealthKit &&
            [.running, .cycling, .swimming].contains(workout.workoutType)
    }

    private var historicalZoneInfo: SwimExplanation? {
        if telemetry.historicalFrozenOriginalZones || (isOwnerAppleHistory && !display.heartRateZones.isEmpty) {
            return .appleHeartRateZones
        }
        if isOwnerAppleHistory && !telemetry.historicalCalculatedHeartRateZones.isEmpty { return .calculatedHeartRateZones }
        return nil
    }

    private var zoneValues: [WorkoutTelemetryZone] {
        if isOwnerAppleHistory {
            return display.heartRateZones.isEmpty ? telemetry.historicalCalculatedHeartRateZones : display.heartRateZones
        }
        if sharedMeasurementOnly || telemetry.ownerExpandedCondensedHeartRate { return display.heartRateZones }
        _ = display
        return presentationCache.zones(maximum: zoneMaximum)
    }
    private var zoneRows: [WorkoutHeartRateZoneDisplay] { WorkoutHeartRateZoneDisplay.rows(zoneValues) }
    private var providerOnlyZones: [WorkoutTelemetryZone] { zoneValues.filter { WorkoutHeartRateZoneDisplay.index(for: $0.name) == nil } }
    private var splitDisplay: WorkoutSplitDisplay {
        .init(type: workout.workoutType, preferredUnit: TrainingSettingsStore.shared.loadSettings().preferredUnit,
            showsLapDuration: workout.workoutType == .swimming && !telemetry.splits.isEmpty
                && telemetry.splits.allSatisfy { $0.label.hasPrefix("랩 ") || $0.label.hasPrefix("구간 ") })
    }
    private var splits: [WorkoutTelemetrySplit] {
        if sharedMeasurementOnly { return display.splits }
        _ = display
        return presentationCache.splits
    }
    private func points(_ channel: WorkoutTelemetryChannel) -> [WorkoutTelemetryChartPoint] {
        _ = display; return presentationCache.channels[channel] ?? []
    }

    var body: some View {
        VStack(spacing: SOOMLayout.stackSpacing) {
            let metrics = telemetry.displaySummaryMetrics(for: workout)
            let pool = sharedMeasurementOnly ? nil : metrics.first { $0.key == "poolLengthMeters" }
            let generalMetrics = metrics.filter { $0.key != "poolLengthMeters" }
            if !generalMetrics.isEmpty {
                WorkoutRecordMetricsCard(metrics: generalMetrics.map {
                    WorkoutCardMetric(label: $0.label, value: "\(number($0.value)) \($0.unit)")
                })
            }
            if let pool {
                SOOMCard {
                    HStack(spacing: 4) {
                        Text(pool.label)
                        Spacer()
                        Text("\(number(pool.value)) \(pool.unit)").monospacedDigit()
                        swimInfoButton(.poolLength)
                    }
                }
            }
            if !display.samples.contains(where: { sample in
                sample.heartRateBPM != nil || sample.cadencePerMinute != nil || sample.powerWatts != nil
                    || sample.speedMetersPerSecond != nil || sample.elevationMeters != nil
            }) && telemetry.intervals.isEmpty {
                SOOMCard {
                    SOOMSectionHeader("측정 차트")
                    Text("이 화면에서 표시할 측정 차트 데이터를 읽지 못했어요. 원본에 값이 없는 것으로 단정할 수는 없습니다.")
                        .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                }.accessibilityIdentifier("workout.measurements.unavailable")
            }
            if showsHeartRateZones {
                if (!sharedMeasurementOnly && !isOwnerAppleHistory && !telemetry.ownerExpandedCondensedHeartRate) || !zoneValues.isEmpty {
                    zones
                } else if !points(.heartRate).isEmpty {
                    Text(sharedMeasurementOnly ? "심박 그래프는 볼 수 있지만, 공유된 심박 구간 시간은 없어요." : "이 기록에서 확인할 수 있는 심박 구간 시간이 없어요.")
                        .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                        .accessibilityIdentifier("detail.shared.hrZones.notAvailable")
                }
            }
            if !sharedMeasurementOnly {
                let swimSets = SOOMSwimSetDeriver.derive(telemetry, for: workout)
                if !swimSets.isEmpty { calculatedSwimSets(swimSets) }
            }
            if !splits.isEmpty { splitCard }
            if hasCharts {
                SOOMCard {
                    Text("차트").font(.headline).accessibilityIdentifier("detail.charts.heading")
                        VStack(spacing: 28) {
                            ForEach(WorkoutTelemetryChannel.allCases) { channel in
                                let points = points(channel)
                                if !points.isEmpty && workout.endDate > workout.startDate {
                                    WorkoutTelemetryChartCard(title: channel.title, unit: unit(channel), points: points,
                                        caption: caption(channel), color: channel == .speed ? SOOMColor.blue : (channel == .elevation ? SOOMColor.green : SOOMColor.accent),
                                        isHeartRate: channel == .heartRate, colorsHeartRateByZone: !sharedMeasurementOnly && !isOwnerAppleHistory && !telemetry.ownerExpandedCondensedHeartRate,
                                        maximumHeartRate: zoneMaximum,
                                        endMinutes: WorkoutChartDomainPolicy.minutes(start: workout.startDate, end: workout.endDate),
                                        allowsNegative: channel == .elevation,
                                        revealDelay: Double(WorkoutTelemetryChannel.allCases.firstIndex(of: channel) ?? 0) * 0.035,
                                        revealID: "charts." + channel.rawValue)
                                }
                            }
                        }
                }
            }
            ForEach(WorkoutTelemetryInterval.Kind.allCases.filter { $0 != .distanceMeters }, id: \.rawValue) { kind in
                let intervals = telemetry.intervals.filter { $0.kind == kind }
                if !intervals.isEmpty {
                    WorkoutTelemetryIntervalCard(kind: kind, intervals: intervals, start: workout.startDate, end: workout.endDate)
                }
            }
            if !telemetry.events.isEmpty { eventCard }
        }.onAppear { presentationCache.trace?.mark("view-appear") }
         .sheet(item: $swimExplanation) { info in swimInfoSheet(info) }
    }

    private var hasCharts: Bool {
        workout.endDate > workout.startDate && WorkoutTelemetryChannel.allCases.contains {
            !points($0).isEmpty
        }
    }

    static func zoneAccessibilityHint(sharedMeasurementOnly: Bool, hasProviderZones: Bool,
                                      maximumHeartRate: Double) -> String {
        if sharedMeasurementOnly {
            return hasProviderZones ? "공유된 원본 구간 기준" : "공유된 심박 구간 정보가 없어요"
        }
        return hasProviderZones ? "연동 서비스가 제공한 구간 기준"
            : "측정된 연속 구간과 최대심박 \(Int(maximumHeartRate)) bpm 기준"
    }

    private var zones: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 12)
            HStack(spacing: 2) {
                Text("심박수 훈련 구간").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    .accessibilityHint(historicalZoneInfo?.title ??
                        Self.zoneAccessibilityHint(sharedMeasurementOnly: sharedMeasurementOnly,
                            hasProviderZones: !telemetry.heartRateZones.isEmpty, maximumHeartRate: zoneMaximum))
                if let historicalZoneInfo { swimInfoButton(historicalZoneInfo) }
            }.padding(.bottom, 6)
            let total = zoneValues.filter { $0.durationSeconds.isFinite && $0.durationSeconds >= 0 }.reduce(0) { $0 + $1.durationSeconds }
            ForEach(zoneRows) { zone in
                let seconds = zone.durationSeconds ?? 0
                let fraction = total > 0 ? seconds / total : 0
                WorkoutCompactMeasuredBar(fraction: fraction, tint: WorkoutDetailPalette.zone(zone.index),
                    labelWidth: 24, statisticsWidth: 76, revealID: "zones.\(zone.index)", baseHeight: 28) {
                    Text("\(zone.index)").font(.subheadline.weight(.semibold))
                        .foregroundStyle(fraction >= 0.12 ? Color.white : SOOMColor.ink)
                } values: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(zone.durationSeconds.map { duration($0) } ?? "기록 없음").fontWeight(.semibold)
                        Text(zone.durationSeconds == nil ? "—" : fraction.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }.font(.caption.monospacedDigit())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(zone.durationSeconds == nil ? "Z\(zone.index), 기록 없음" : "Z\(zone.index), \(duration(seconds)), \(Int((fraction * 100).rounded())) 퍼센트")
                .accessibilityIdentifier("detail.hrZone.\(zone.index)")
            }
            if !providerOnlyZones.isEmpty {
                Text("연동 서비스 별도 구간").font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                ForEach(Array(providerOnlyZones.enumerated()), id: \.offset) { _, zone in
                    HStack { Text(zone.name); Spacer(); Text(duration(zone.durationSeconds)) }
                        .font(.subheadline.monospacedDigit())
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swimInfoButton(_ explanation: SwimExplanation) -> some View {
        Button { swimExplanation = explanation } label: {
            Text("!").font(.caption2.weight(.semibold))
                .foregroundStyle(SOOMColor.secondaryInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(explanation.title)
        .accessibilityHint("측정 출처와 계산 방법을 열어요")
        .accessibilityIdentifier("detail.swimInfo." + explanation.rawValue)
    }

    private func swimInfoSheet(_ info: SwimExplanation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(info.title).font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("닫기") { swimExplanation = nil }
                        .frame(minWidth: 44, minHeight: 44)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if info == .setCalculation {
                            Text("SOOM 계산 · Apple 건강에서 가져온 랩 시작·종료 시간과 거리를 사용했어요.")
                            Text("랩 사이가 15초 이상이거나, 사이에 기록된 일시 정지와 재개가 있으면 새 세트로 나눠요.")
                            Text("수영 시간은 랩 시간의 합이에요. 100m 페이스는 수영 시간으로 계산하고, 랩 사이 공백은 별도로 보여줘요.")
                            Text("영법은 추정하지 않아요. Apple 피트니스의 자동 세트와 다를 수 있어요.")
                        } else if info == .appleHeartRateZones {
                            Text("Apple 건강 원본 · 이 운동에 저장된 구간별 시간이에요. 현재 설정으로 다시 계산하지 않았어요.")
                        } else if info == .calculatedHeartRateZones {
                            Text("SOOM 계산 · 이 운동에 저장된 당시 심박 기준과 실제 측정 시간을 사용했어요.")
                            Text("일시 정지와 측정 공백은 빼고 계산했어요. Apple 피트니스의 구간 시간과 다를 수 있어요.")
                        } else {
                            Text("Apple 건강 원본 · 이 수영 기록에 저장된 수영장 길이예요.")
                            Text("랩 거리로 수영장 길이를 추정하지 않아요.")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding()
         .presentationDetents([.medium, .large])
    }

    private func calculatedSwimSets(_ rows: [SOOMSwimSetDeriver.SetRow]) -> some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 2) {
                    Text("수영 세트").font(.headline)
                        .accessibilityIdentifier("detail.swimSets.derived")
                    swimInfoButton(.setCalculation)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("세트 \(index + 1) · \(number(row.distanceMeters))m · \(row.lapCount)랩")
                            .font(.subheadline.weight(.semibold))
                        Text("수영 \(duration(row.swimmingSeconds)) · 경과 \(duration(row.elapsedSeconds)) · \(duration(row.pacePer100m))/100m")
                            .font(.caption.monospacedDigit())
                        if let gap = row.gapBeforeNextSet {
                            Text("다음 세트까지 \(duration(gap))").font(.caption)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var splitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 12)
            Text(splitDisplay.isLapTiming ? "랩 · 구간" : "스플릿").font(.headline).accessibilityLabel("스플릿 · " + splitDisplay.title)
                .accessibilityIdentifier("detail.splits.heading").padding(.bottom, 6)
            ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                WorkoutAnimatedSplitRow(split: split, maximumDuration: splits.map(\.durationSeconds).max() ?? 1,
                    display: splitDisplay, maximumMetric: splits.compactMap { splitDisplay.value(distance: $0.distanceMeters, seconds: $0.durationSeconds) }.max() ?? 1,
                    cadenceUnit: unit(.cadence), maximumHeartRate: zoneMaximum,
                    colorsHeartRateByZone: !sharedMeasurementOnly && !telemetry.ownerExpandedCondensedHeartRate, revealID: "splits.\(index)", showsUnit: index == 0)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventCard: some View {
        SOOMCard {
            SOOMSectionHeader("운동 타임라인")
            ForEach(Array(telemetry.events.enumerated()), id: \.offset) { _, event in
                HStack {
                    Text(event.type.lowercased().contains("pause") ? "일시 정지" :
                        event.type.lowercased().contains("resume") ? "운동 재개" : (event.type == "stop" ? "운동 종료" : event.type))
                    Spacer()
                    Text(duration(event.timestamp.timeIntervalSince(workout.startDate))).monospacedDigit()
                }.font(.subheadline)
            }
        }
    }

    private func caption(_ channel: WorkoutTelemetryChannel) -> String? {
        if channel == .heartRate, !sharedMeasurementOnly {
            return TrainingSettingsStore.shared.loadZoneBaseline().maxHeartRate == nil
                ? "점 색상: 최대심박 190 bpm 가정 기준"
                : "점 색상: 설정한 최대심박 \(Int(zoneMaximum)) bpm 기준"
        }
        if channel == .cadence, !telemetry.samples.contains(where: { $0.cadencePerMinute != nil }),
           telemetry.intervals.contains(where: { $0.kind == .steps }) {
            return "기록된 구간 걸음 수·시간에서 계산한 케이던스"
        }
        if channel == .speed, !telemetry.samples.contains(where: { $0.speedMetersPerSecond != nil }) {
            return telemetry.intervals.contains { $0.kind == .distanceMeters } ? "거리·시간 구간에서 계산한 속도" : "GPS 위치·시간에서 계산한 속도"
        }
        return nil
    }
    private func unit(_ channel: WorkoutTelemetryChannel) -> String {
        guard channel == .cadence else { return channel.unit }
        return telemetry.samples.compactMap(\.cadenceUnit).first?.symbol
            ?? (workout.workoutType == .running || workout.workoutType == .walking ? "spm" : "rpm")
    }
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
    private func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        return total >= 3_600 ? String(format: "%d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Memoizes presentation derivation without altering persisted values or formulas.
/// Disclosure, chart selection and layout updates reuse the same measured series.
final class WorkoutTelemetryPresentationCache {
    private var input: WorkoutTelemetry?
    private var workout: UnifiedWorkout?
    private var route: WorkoutRoute?
    private var output: WorkoutTelemetry?
    private(set) var channels: [WorkoutTelemetryChannel: [WorkoutTelemetryChartPoint]] = [:]
    private(set) var splits: [WorkoutTelemetrySplit] = []
    private(set) var preparationCount = 0
    private(set) var trace: LoadTrace?
    private var zoneMaximum: Double?
    private var zoneCache: [WorkoutTelemetryZone] = []
    func zones(maximum: Double) -> [WorkoutTelemetryZone] {
        guard let output, let workout else { return [] }
        if !output.heartRateZones.isEmpty { return output.heartRateZones }
        if zoneMaximum != maximum {
            zoneMaximum = maximum
            zoneCache = WorkoutTelemetryChartBuilder.heartRateZones(output, workout: workout, maximumHeartRate: maximum)
        }
        return zoneCache
    }
    func prepare(_ input: WorkoutTelemetry, workout: UnifiedWorkout, route: WorkoutRoute?) -> WorkoutTelemetry {
        if self.input == input, self.workout == workout, self.route == route, let output { return output }
        let trace = LoadTrace("detail-chart-preparation")
        self.input = input; self.workout = workout; self.route = route
        let result = WorkoutTelemetryChartBuilder.addingDerivedChannels(to: input.validated(for: workout), route: route).validated(for: workout)
        output = result
        zoneMaximum = nil; zoneCache = []
        channels = Dictionary(uniqueKeysWithValues: WorkoutTelemetryChannel.allCases.map {
            ($0, WorkoutTelemetryChartBuilder.points(result, channel: $0, start: workout.startDate, end: workout.endDate))
        })
        splits = WorkoutTelemetryChartBuilder.derivedSplits(result, workoutType: workout.workoutType)
        preparationCount += 1
        self.trace = trace
        trace.mark("prepared")
        return result
    }
}

private struct WorkoutTelemetryChartCard: View {
    let title: String
    let unit: String
    let points: [WorkoutTelemetryChartPoint]
    var caption: String?
    let color: Color
    var isHeartRate = false
    var colorsHeartRateByZone = true
    var maximumHeartRate: Double = 190
    let endMinutes: Double
    var allowsNegative = false
    var revealDelay: Double = 0
    var revealID = ""
    @Environment(\.workoutRevealContext) private var revealContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedMinutes: Double?
    @State private var reveal = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workoutDetailReduceMotion) private var previewReduced
    private var motionReduced: Bool { reduceMotion || previewReduced }
    private var baseline: Double { ((points.map(\.value).min() ?? 0) + (points.map(\.value).max() ?? 0)) / 2 }
    private func plotted(_ value: Double) -> Double { baseline + (value - baseline) * reveal }


    private var selected: WorkoutTelemetryChartPoint? {
        guard let selectedMinutes else { return nil }
        return points.min { abs($0.seconds / 60 - selectedMinutes) < abs($1.seconds / 60 - selectedMinutes) }
    }
    /// Render extrema per screen bucket, retaining the full series for selection
    /// and statistics. Persisted raw measurements are never downsampled.
    private var rendered: [WorkoutTelemetryChartPoint] {
        guard points.count > 600 else { return points }
        let size = max(1, points.count / 200)
        return stride(from: 0, to: points.count, by: size).flatMap { start -> [WorkoutTelemetryChartPoint] in
            let bucket = points[start..<min(points.count, start + size)]
            var selected = [bucket.first!, bucket.min(by: { $0.value < $1.value })!,
                bucket.max(by: { $0.value < $1.value })!, bucket.last!]
            var seen = Set<Double>()
            selected = selected.filter { seen.insert($0.seconds).inserted }
            return selected.sorted { $0.seconds < $1.seconds }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(SOOMColor.ink)
            if let caption { Text(caption).font(.caption).foregroundStyle(SOOMColor.secondaryInk) }
            Chart {
                ForEach(rendered) { point in
                    if isHeartRate {
                        PointMark(x: .value("시간", point.seconds / 60), y: .value(title, plotted(point.value)))
                            .foregroundStyle(colorsHeartRateByZone
                                ? WorkoutDetailPalette.heartRate(point.value, maximum: maximumHeartRate) : SOOMColor.red)
                            .symbol {
                                Capsule().fill(colorsHeartRateByZone
                                    ? WorkoutDetailPalette.heartRate(point.value, maximum: maximumHeartRate) : SOOMColor.red)
                                    .frame(width: 3, height: 7)
                            }
                    } else {
                        LineMark(x: .value("시간", point.seconds / 60), y: .value(title, plotted(point.value)),
                            series: .value("측정 구간", point.segment))
                            .foregroundStyle(color).interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
                if let selected {
                    RuleMark(x: .value("선택 시간", selected.seconds / 60))
                        .foregroundStyle(color.opacity(0.55))
                    PointMark(x: .value("시간", selected.seconds / 60), y: .value(title, selected.value))
                        .foregroundStyle(color)
                }
            }
            .frame(height: 230)
            .chartXScale(domain: 0...max(endMinutes, 1.0 / 60))
            .chartYScale(domain: WorkoutChartDomainPolicy.values(points.map(\.value), allowsNegative: allowsNegative))
            .chartXAxis {
                AxisMarks(values: dynamicTypeSize.isAccessibilitySize ? [0, endMinutes] : WorkoutChartDomainPolicy.ticks(endMinutes: endMinutes).filter {
                    $0 == 0 || $0 == endMinutes || endMinutes - $0 >= endMinutes * 0.25
                }) { value in
                    AxisGridLine(); AxisTick()
                    if !dynamicTypeSize.isAccessibilitySize, let minute = value.as(Double.self) {
                        AxisValueLabel(anchor: minute == 0 ? .topLeading : (minute == endMinutes ? .topTrailing : .top),
                            collisionResolution: .disabled) {
                            Text(WorkoutChartDomainPolicy.label(minutes: minute)).font(.caption)
                        }
                    }
                }
            }
            .chartXAxisLabel(dynamicTypeSize.isAccessibilitySize ? "" : "경과 시간")
            .modifier(WorkoutTelemetryAccessibleYAxis(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
            .accessibilityLabel(title + " 측정 차트")
            .accessibilityValue("0:00부터 " + WorkoutChartDomainPolicy.label(minutes: endMinutes) + "까지")
            .chartYAxisLabel(dynamicTypeSize.isAccessibilitySize ? "" : unit)
            .chartXSelection(value: $selectedMinutes)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("경과 시간 · 시작 0:00")
                    Text("종료 " + WorkoutChartDomainPolicy.label(minutes: endMinutes))
                    Text("단위 " + unit)
                }
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail.chart.axisSummary." + title)
                VStack(alignment: .leading, spacing: 8) {
                    if let selected {
                        Text(String(format: "선택 시간 %.1f분", selected.seconds / 60))
                        Text("측정값 \(selected.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    } else {
                        Text("측정 최저 \((points.map(\.value).min() ?? 0).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                        Text("측정 최고 \((points.map(\.value).max() ?? 0).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    }
                }
                .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("detail.chart.measurementSummary." + title)
            } else {
                HStack {
                    if let selected {
                        Text(String(format: "%.1f분", selected.seconds / 60))
                        Spacer()
                        Text("\(selected.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    } else {
                        Text("측정 최저 \((points.map(\.value).min() ?? 0).formatted(.number.precision(.fractionLength(0...1))))")
                        Spacer()
                        Text("측정 최고 \((points.map(\.value).max() ?? 0).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    }
                }.font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            }
        }
        .accessibilityIdentifier("detail.chart." + title)
        .onAppear {
            if motionReduced || revealContext?.contains(revealID) == true { reveal = 1 }
        }
        .onScrollVisibilityChange(threshold: 0.15) { visible in
            guard visible, reveal == 0 else { return }
            let first = revealContext?.claim(revealID) ?? true
            if first && !motionReduced {
                withAnimation(.easeInOut(duration: 0.48)) { reveal = 1 }
            } else { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { reveal = 1 } }
        }
        .onChange(of: motionReduced) { _, reduced in if reduced { reveal = 1 } }

    }
}

/// Reduce only accessibility-sized axis density; ordinary charts keep their native axis.
private struct WorkoutTelemetryAccessibleYAxis: ViewModifier {
    let isAccessibilitySize: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if isAccessibilitySize {
            content.chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
            }
        } else {
            content
        }
    }
}

private struct WorkoutTelemetryIntervalCard: View {
    let kind: WorkoutTelemetryInterval.Kind
    let intervals: [WorkoutTelemetryInterval]
    let start: Date
    let end: Date

    private var title: String {
        switch kind {
        case .distanceMeters: "구간 거리"
        case .steps: "구간 걸음 수"
        case .energyKcal: "구간 활동 칼로리"
        case .elevationGainMeters: "구간 고도 변화"
        case .activeZoneMinutes: "구간 활동 존 시간"
        case .swimStrokeCount: "수영 스트로크"
        }
    }
    private var unit: String {
        switch kind {
        case .distanceMeters, .elevationGainMeters: "m"
        case .steps: "걸음"
        case .energyKcal: "kcal"
        case .activeZoneMinutes: "분"
        case .swimStrokeCount: "회"
        }
    }
    private var buckets: [(minutes: Double, value: Double)] {
        let sorted = intervals.filter { $0.startDate >= start && $0.endDate <= end && $0.value.isFinite }.sorted { $0.startDate < $1.startDate }
        let count = max(1, Int(ceil(Double(sorted.count) / 100)))
        return stride(from: 0, to: sorted.count, by: count).map { offset in
            let range = sorted[offset..<min(sorted.count, offset + count)]
            return (range.first!.startDate.timeIntervalSince(start) / 60, range.reduce(0) { $0 + $1.value })
        }
    }
    var body: some View {
        SOOMCard {
            SOOMSectionHeader(title, caption: kind == .elevationGainMeters ? "각 구간의 상승·하강량 · 해발 고도와 다릅니다" : nil)
            Chart(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                BarMark(x: .value("시간", bucket.minutes), y: .value(title, bucket.value))
                    .foregroundStyle(SOOMColor.accent.opacity(0.7))
            }.frame(height: 200)
            .chartXScale(domain: 0...max(WorkoutChartDomainPolicy.minutes(start: start, end: end), 1.0 / 60))
            .chartYScale(domain: WorkoutChartDomainPolicy.values(buckets.map(\.value), allowsNegative: kind == .elevationGainMeters))
            .chartXAxisLabel("경과 시간 (분)").chartYAxisLabel(unit)
            Text("합계 \(intervals.reduce(0) { $0 + $1.value }.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
        }
    }
}

/// Shared palette adds meaning to measured channels without changing global theme.
enum WorkoutDetailPalette {
    static func zone(_ index: Int) -> Color {
        switch index {
        case 0: Color(red: 0.76, green: 0.84, blue: 0.88)
        case 1: Color(red: 0.53, green: 0.73, blue: 0.93)
        case 2: Color(red: 0.97, green: 0.77, blue: 0.29)
        case 3: Color(red: 0.92, green: 0.49, blue: 0.28)
        case 4: Color(red: 0.82, green: 0.28, blue: 0.29)
        default: Color(red: 0.38, green: 0.25, blue: 0.72)
        }
    }
    static func zoneLabel(name: String, fallback: Int) -> Color {
        (Int(name.filter(\.isNumber)) ?? fallback) >= 5 ? .white : .black
    }
    static func zone(name: String, fallback: Int) -> Color {
        zone(Int(name.filter(\.isNumber)) ?? fallback)
    }
    static func heartRate(_ value: Double, maximum: Double) -> Color {
        let ratio = value / max(1, maximum)
        return zone(ratio < 0.6 ? 1 : ratio < 0.7 ? 2 : ratio < 0.8 ? 3 : ratio < 0.9 ? 4 : 5)
    }
    static func heartRateInk(_ value: Double, maximum: Double) -> Color {
        // Body text remains readable on white while chart/bar hues stay distinct.
        let ratio = value / max(1, maximum)
        if ratio < 0.6 { return Color(red: 0.20, green: 0.39, blue: 0.59) }
        if ratio < 0.7 { return Color(red: 0.48, green: 0.34, blue: 0.05) }
        if ratio < 0.8 { return Color(red: 0.62, green: 0.29, blue: 0.10) }
        if ratio < 0.9 { return Color(red: 0.72, green: 0.20, blue: 0.22) }
        return zone(5)
    }
}

struct WorkoutDetailDisclosure: View {
    let title: String
    @Binding var isExpanded: Bool
    let identifier: String
    var body: some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = isExpanded
            withTransaction(transaction) { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title).font(.headline).foregroundStyle(SOOMColor.ink)
                Spacer(minLength: 12)
                Image(systemName: "chevron.down").rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(SOOMColor.secondaryInk)
            }.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title + (isExpanded ? " 접기" : " 펼치기"))
            .accessibilityValue(isExpanded ? "펼쳐짐" : "접힘").accessibilityIdentifier(identifier)
    }
}

private struct WorkoutAnimatedSplitRow: View {
    let split: WorkoutTelemetrySplit
    let maximumDuration: Double
    let display: WorkoutSplitDisplay
    let maximumMetric: Double
    let cadenceUnit: String
    let maximumHeartRate: Double
    let colorsHeartRateByZone: Bool
    let revealID: String
    var showsUnit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workoutDetailReduceMotion) private var previewReduced
    private var motionReduced: Bool { reduceMotion || previewReduced }
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .subheadline) private var statisticsWidth: CGFloat = 132
    private var ratio: Double {
        display.isCycling || display.isRunning
            ? (display.value(distance: split.distanceMeters, seconds: split.durationSeconds) ?? 0) / max(0.001, maximumMetric)
            : split.durationSeconds / max(1, maximumDuration)
    }
    var body: some View {
        WorkoutCompactMeasuredBar(fraction: ratio, tint: SOOMColor.surfaceMuted,
            labelWidth: 122, statisticsWidth: 76, revealID: revealID) {
            HStack(spacing: 10) {
                Text(split.label.replacingOccurrences(of: "랩 ", with: "").replacingOccurrences(of: "구간 ", with: "").replacingOccurrences(of: " km", with: ""))
                    .foregroundStyle(SOOMColor.secondaryInk).font(.subheadline)
                    .frame(width: 24, alignment: .leading)
                HStack(spacing: 2) {
                    Text(display.text(distance: split.distanceMeters, seconds: split.durationSeconds).replacingOccurrences(of: display.unit, with: "").trimmingCharacters(in: .whitespaces))
                        .fontWeight(.semibold).foregroundStyle(SOOMColor.ink)
                    if showsUnit { Text(display.unit).foregroundStyle(SOOMColor.secondaryInk) }
                }.font(.body.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
            }
        } values: {
            VStack(alignment: .leading, spacing: 0) {
                Text(split.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "심박 —")
                    .foregroundStyle(split.averageHeartRate.map { colorsHeartRateByZone ? WorkoutDetailPalette.heartRateInk($0, maximum: maximumHeartRate) : SOOMColor.secondaryInk } ?? SOOMColor.secondaryInk)
                if display.isLapTiming, let pace = display.poolPaceText(distance: split.distanceMeters, seconds: split.durationSeconds) {
                    Text(pace).foregroundStyle(SOOMColor.secondaryInk)
                }
                Text(display.isLapTiming ? (display.distanceText(split.distanceMeters) ?? "거리 —") : (split.elevationChangeMeters.map { String(format: "%+.0f m", $0) } ?? "고도 —"))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }.font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(split.label), \(display.title), \(display.text(distance: split.distanceMeters, seconds: split.durationSeconds))")
        .accessibilityValue(distanceAndTime + ", " + (split.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "심박 기록 없음") + ", " + (split.elevationChangeMeters.map { String(format: "%+.0f m 고도차", $0) } ?? "고도 기록 없음") + (split.averagePowerWatts.map { ", \(Int($0.rounded())) W" } ?? "") + (split.averageCadence.map { ", \(Int($0.rounded())) " + cadenceUnit } ?? ""))
        .accessibilityIdentifier("detail.split.\(split.label)")
    }
    private var distanceAndTime: String {
        let distance = display.distanceText(split.distanceMeters).map { $0 + " · " } ?? ""
        let pace = display.poolPaceText(distance: split.distanceMeters, seconds: split.durationSeconds).map { " · 페이스 " + $0 } ?? ""
        return distance + WorkoutSplitDisplay.duration(split.durationSeconds) + pace
    }
    private func duration(_ seconds: Double) -> String {
        let total=Int(max(0,seconds).rounded())
        return total >= 3600 ? String(format:"%d:%02d:%02d",total/3600,total/60%60,total%60) : String(format:"%d:%02d",total/60,total%60)
    }
}

/// A fixed label well is visually separate from the proportional data segment.
/// Reserve the SAME trailing width for every row, including 0% and 100%.
/// The bar end and trailing labels share one animated progress value.
struct WorkoutBarGeometry {
    let labelWidth: Double
    let trackWidth: Double
    let valueWidth: Double
    let valueX: Double
    init(width: Double, label: Double, statistics: Double, fraction: Double, progress: Double) {
        labelWidth = min(label, max(0, width * 0.28))
        let reserved = min(statistics, max(0, width * 0.58))
        trackWidth = max(0, width - labelWidth - reserved - 8)
        valueWidth = trackWidth * min(1, max(0, fraction.isFinite ? fraction : 0)) * min(1, max(0, progress))
        valueX = labelWidth + valueWidth + 8
    }
}

struct WorkoutTrailingValueBar<Values: View>: View {
    let label: String
    let fraction: Double
    let tint: Color
    let statisticsWidth: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    var revealID = ""
    @Environment(\.workoutRevealContext) private var revealContext
    @ViewBuilder let values: () -> Values
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workoutDetailReduceMotion) private var previewReduced
    @State private var revealed = false
    @State private var measuredValuesHeight: CGFloat = 0
    private var resolvedHeight: CGFloat { max(rowHeight, measuredValuesHeight + 8) }
    private var reduced: Bool { reduceMotion || previewReduced }
    var body: some View {
        GeometryReader { proxy in
            let geometry = WorkoutBarGeometry(width: proxy.size.width, label: labelWidth,
                statistics: statisticsWidth, fraction: fraction, progress: revealed || reduced ? 1 : 0)
            HStack(spacing: 0) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(SOOMColor.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(width: geometry.labelWidth, height: resolvedHeight)
                    .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
                RoundedRectangle(cornerRadius: 5).fill(tint)
                    .frame(width: geometry.valueWidth, height: resolvedHeight)
            }
            values()
                .frame(width: min(statisticsWidth, proxy.size.width * 0.58), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredValuesHeight = $0 }
                .frame(height: resolvedHeight, alignment: .leading)
                .offset(x: geometry.valueX)
        }.frame(height: resolvedHeight)
        .onAppear {
            if revealContext?.contains(revealID) == true || reduced {
                _ = revealContext?.claim(revealID)
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = true }
            }
        }
        .onScrollVisibilityChange(threshold: 0.15) { visible in
            guard visible, !revealed else { return }
            let first = revealContext?.claim(revealID) ?? true
            if first && !reduced {
                withAnimation(.easeInOut(duration: 0.42)) { revealed = true }
            } else {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = true }
            }
        }
        .onChange(of: reduced) { _, value in if value { revealed = true } }
    }
}

/// Numeric labels do not inflate measured bars: zero remains zero, with a neutral
/// label outside its empty track. Values follow the bar end unless labels overlap.
struct WorkoutCompactBarGeometry {
    let trackWidth: Double
    let barWidth: Double
    let valuesX: Double
    init(width: Double, label: Double, statistics: Double, fraction: Double, progress: Double) {
        trackWidth = max(0, width - statistics - 8)
        barWidth = trackWidth * min(1, max(0, fraction.isFinite ? fraction : 0)) * min(1, max(0, progress))
        valuesX = min(trackWidth, max(min(label, trackWidth), barWidth)) + 8
    }
}

struct WorkoutCompactMeasuredBar<Label: View, Values: View>: View {
    let fraction: Double
    let tint: Color
    let labelWidth: CGFloat
    let statisticsWidth: CGFloat
    let revealID: String
    var baseHeight: CGFloat = 34
    @ViewBuilder let label: () -> Label
    @ViewBuilder let values: () -> Values
    @Environment(\.workoutRevealContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workoutDetailReduceMotion) private var previewReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var heightScale: CGFloat = 1
    private var height: CGFloat { baseHeight * heightScale }
    @State private var revealed = false
    private var reduced: Bool { reduceMotion || previewReduced }
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    label(); values()
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 5).fill(tint)
                            .frame(width: max(0, proxy.size.width * min(1, max(0, fraction.isFinite ? fraction : 0))), height: 8)
                    }.frame(height: 8)
                }.padding(.vertical, 4)
            } else {
                GeometryReader { proxy in
                    let g = WorkoutCompactBarGeometry(width: proxy.size.width, label: labelWidth,
                        statistics: statisticsWidth, fraction: fraction, progress: revealed || reduced ? 1 : 0)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 11).fill(tint).frame(width: g.barWidth, height: height)
                        label().padding(.leading, 8).frame(width: max(labelWidth, g.barWidth), alignment: .leading)
                    }
                    values().frame(width: statisticsWidth, height: height, alignment: .leading).offset(x: g.valuesX)
                }.frame(height: height)
            }
        }
        .onAppear { if reduced || context?.contains(revealID) == true { revealed = true } }
        .onScrollVisibilityChange(threshold: 0.15) { visible in
            guard visible, !revealed else { return }
            let first = context?.claim(revealID) ?? true
            if first && !reduced { withAnimation(.easeInOut(duration: 0.42)) { revealed = true } }
            else { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { revealed = true } }
        }
        .onChange(of: reduced) { _, reduced in if reduced { revealed = true } }
    }
}
