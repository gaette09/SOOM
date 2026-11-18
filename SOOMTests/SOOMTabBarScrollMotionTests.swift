import XCTest
import Combine
@testable import SOOM

final class SOOMTabBarScrollMotionTests: XCTestCase {
    private func sample(_ position: CGFloat, contentHeight: CGFloat = 2400, viewport: CGFloat = 700) -> SOOMTabBarScrollSample {
        .init(offset: position - 20, contentHeight: contentHeight, viewportHeight: viewport, topInset: 20, bottomInset: 30)
    }

    func testReadingDirectionAndHysteresis() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        state.consume(sample(100))
        state.consume(sample(123))
        XCTAssertFalse(state.isCompact)
        state.consume(sample(124))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(109))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(108))
        XCTAssertFalse(state.isCompact)
    }

    func testSmallOscillationsNeverToggle() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        for offset in [100, 104, 101, 106, 100, 108, 104, 111, 105] {
            state.consume(sample(CGFloat(offset)))
        }
        XCTAssertFalse(state.isCompact)
        state.consume(sample(140))
        XCTAssertTrue(state.isCompact)
        for offset in [138, 141, 135, 139, 133, 138] {
            state.consume(sample(CGFloat(offset)))
        }
        XCTAssertTrue(state.isCompact)
    }

    func testProgrammaticJumpIdleAndLayoutChanges() {
        var state = SOOMTabBarScrollReducer()
        state.consume(sample(100))
        state.consume(sample(400))
        XCTAssertFalse(state.isCompact)
        state.beginGesture()
        state.consume(sample(100))
        state.consume(sample(140))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(600))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(650))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(660, viewport: 450))
        XCTAssertFalse(state.isCompact)
        state.consume(sample(690, viewport: 450))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(690, contentHeight: 2800, viewport: 450))
        XCTAssertTrue(state.isCompact)
    }

    func testLazyContentSizeEstimatesDoNotInterruptDirection() {
        var state = SOOMTabBarScrollReducer()
        state.interact()
        state.consume(sample(100))
        state.consume(sample(112, contentHeight: 2500))
        state.consume(sample(125, contentHeight: 2600))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(108, contentHeight: 2800))
        XCTAssertFalse(state.isCompact)
    }

    func testTopBounceShortContentAndBottomRecoil() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        state.consume(sample(100))
        state.consume(sample(140))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(-40))
        XCTAssertFalse(state.isCompact)
        state.consume(sample(0))
        state.consume(sample(8))
        XCTAssertFalse(state.isCompact)
        state.consume(sample(60))
        XCTAssertTrue(state.isCompact)
        state.consume(sample(0, contentHeight: 300))
        XCTAssertFalse(state.isCompact)

        state.reset()
        state.beginGesture()
        state.consume(sample(1600))
        state.consume(sample(1630))
        XCTAssertTrue(state.isCompact)
        state.decelerate()
        state.consume(sample(1790)) // beyond maximum 1750
        state.consume(sample(1749)) // bounce re-entry establishes baseline
        state.consume(sample(1700)) // recoil must not expand
        XCTAssertTrue(state.isCompact)
        state.endGesture()
        state.beginGesture()
        state.consume(sample(1700))
        state.consume(sample(1680)) // explicit new reverse gesture does expand
        XCTAssertFalse(state.isCompact)
    }

    @MainActor
    func testLifecycleSuspensionAndAccessibilityDisable() {
        let motion = SOOMTabBarScrollMotion()
        let source = UUID(), modal = UUID(), stale = UUID()
        motion.activate(source)
        motion.phaseChanged(.interacting, source: source)
        motion.consume(sample(100), source: source)
        motion.consume(sample(130), source: source)
        XCTAssertTrue(motion.isCompact)
        motion.phaseChanged(.animating, source: source)
        motion.consume(sample(800), source: source)
        XCTAssertTrue(motion.isCompact)
        motion.suspend(true, source: modal)
        XCTAssertFalse(motion.isCompact)
        motion.phaseChanged(.tracking, source: source)
        motion.consume(sample(100), source: source)
        motion.consume(sample(130), source: source)
        XCTAssertFalse(motion.isCompact)
        motion.suspend(false, source: modal)
        motion.phaseChanged(.tracking, source: source)
        motion.consume(sample(100), source: source)
        motion.consume(sample(130), source: source)
        XCTAssertTrue(motion.isCompact)
        motion.isEnabled = false // Reduce Motion / VoiceOver / keyboard / inactive scene
        XCTAssertFalse(motion.isCompact)
        motion.isEnabled = true
        motion.activate(stale)
        motion.deactivate(source)
        motion.phaseChanged(.tracking, source: stale)
        motion.consume(sample(100), source: stale)
        motion.consume(sample(130), source: stale)
        XCTAssertTrue(motion.isCompact)
        motion.deactivate(stale)
        XCTAssertFalse(motion.isCompact)
    }

    func testCompactScaleMatches76PercentRequest() {
        XCTAssertEqual(SOOMTabBarScrollReducer.compactScale, 0.76)
    }

    func testUnscaledTargetsAndVisualBoundsAcrossSupportedWidths() {
        // Touch frames are applied after compact AND pressed visual transforms.
        // Slots remain separate even on the smallest supported 320pt phone.
        for screenWidth: CGFloat in [320, 375, 390, 402, 430, 768] {
            for scale: CGFloat in [SOOMTabBarScrollReducer.compactScale, 0.8, 0.9, 1] {
                let layout = SOOMTabBarTouchLayout(
                    containerWidth: screenWidth - 2 * SOOMLayout.TabBar.outerHorizontalPadding,
                    visualScale: scale, tabCount: 5,
                    horizontalPadding: SOOMLayout.TabBar.containerHorizontalPadding
                )
                XCTAssertGreaterThanOrEqual(layout.targetItemWidth, 44)
                XCTAssertGreaterThanOrEqual(SOOMLayout.TabBar.itemHeight, 44)
                XCTAssertLessThanOrEqual(layout.targetRowWidth, layout.containerWidth)
                XCTAssertLessThanOrEqual(layout.visualItemWidth * scale, layout.targetItemWidth + 0.001)
                XCTAssertGreaterThanOrEqual(layout.visualItemWidth, SOOMLayout.TabBar.defaultIconSize)
                let visualExtent = layout.targetRowWidth - layout.targetItemWidth + layout.visualItemWidth * scale
                XCTAssertLessThanOrEqual(visualExtent, layout.visualContainerWidth + 0.001)
                // Press affects the artwork only; the same target dimensions stay in force.
                XCTAssertLessThanOrEqual(layout.visualItemWidth * scale * SOOMLayout.TabBar.pressScale, layout.targetItemWidth)
            }
        }
    }

    func testNewDragInterruptsDecelerationWithoutTrackingPhase() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        state.consume(sample(100)); state.consume(sample(130))
        XCTAssertTrue(state.isCompact)
        state.decelerate(); state.interact()
        state.consume(sample(120)); state.consume(sample(110)); state.consume(sample(100))
        XCTAssertFalse(state.isCompact)
    }
    func testSmallReverseSamplesDoNotEraseForwardIntent() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        for value in [100, 108, 107, 115, 114, 122, 121, 129] {
            state.consume(sample(CGFloat(value)))
        }
        XCTAssertTrue(state.isCompact)
    }
    func testOnePointViewportNoiseDoesNotResetDirection() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        state.consume(sample(100, viewport: 700))
        state.consume(sample(108, viewport: 701))
        state.consume(sample(116, viewport: 700))
        state.consume(sample(125, viewport: 701))
        XCTAssertTrue(state.isCompact)
    }
    func testFirstReverseSampleUsesStationaryBaseline() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        state.consume(sample(100)); state.consume(sample(130))
        state.endGesture()
        state.consume(sample(130))
        state.beginGesture()
        state.consume(sample(112))
        XCTAssertFalse(state.isCompact)
    }

    func testShortReverseRetainsCompactUntilNetRestoreDistance() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture(at: sample(100))
        state.consume(sample(124))
        for value in [119, 122, 114, 110] {
            state.consume(sample(CGFloat(value)))
            XCTAssertTrue(state.isCompact)
        }
        state.consume(sample(108))
        XCTAssertFalse(state.isCompact)
    }

    func testTopBounceReentryNeverCollapsesDuringDeceleration() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture(at: sample(100))
        state.consume(sample(130))
        state.decelerate()
        for value in [-30, 0, 12, 35, 65] {
            state.consume(sample(CGFloat(value)))
            XCTAssertFalse(state.isCompact)
        }
        state.endGesture()
        state.beginGesture(at: sample(65))
        state.consume(sample(89))
        XCTAssertTrue(state.isCompact)
    }

    func testContinuousSameDirectionStopAndProgrammaticOffset() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture(at: sample(100))
        var transitions = 0
        for value in 101...300 {
            let old = state.isCompact
            state.consume(sample(CGFloat(value)))
            if old != state.isCompact { transitions += 1 }
        }
        XCTAssertEqual(transitions, 1)
        state.endGesture()
        for value in [300, 900, 1300] { state.consume(sample(CGFloat(value))) }
        XCTAssertTrue(state.isCompact)
        state.beginGesture(at: sample(1300))
        state.consume(sample(1284))
        XCTAssertFalse(state.isCompact)
    }

    func testResetClearsCompactAndOldGestureIntent() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture(at: sample(100))
        state.consume(sample(130))
        XCTAssertTrue(state.isCompact)
        state.reset() // tab/source/scene reset
        state.consume(sample(200))
        state.consume(sample(230))
        XCTAssertFalse(state.isCompact)
        state.beginGesture(at: sample(230))
        state.consume(sample(240))
        XCTAssertFalse(state.isCompact)
        state.consume(sample(254))
        XCTAssertTrue(state.isCompact)
    }

    func testNonFiniteGeometryPreservesValidBaseline() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture(at: sample(100))
        state.consume(sample(120, contentHeight: .nan))
        state.consume(sample(124))
        XCTAssertTrue(state.isCompact)
    }

    @MainActor
    func testRepeatedLifecycleSignalsDoNotEraseActiveDrag() {
        let motion = SOOMTabBarScrollMotion()
        let source = UUID(), modal = UUID()
        motion.activate(source)
        motion.phaseChanged(.interacting, source: source, sample: sample(100))
        motion.consume(sample(110), source: source)
        motion.activate(source)
        motion.suspend(false, source: modal)
        motion.consume(sample(125), source: source)
        XCTAssertTrue(motion.isCompact)
    }

    @MainActor
    func testPhaseContextSeedsFirstMovementAndInterruptedDeceleration() {
        let motion = SOOMTabBarScrollMotion()
        let source = UUID()
        motion.activate(source)
        motion.phaseChanged(.interacting, source: source, sample: sample(100))
        motion.consume(sample(124), source: source)
        XCTAssertTrue(motion.isCompact)
        motion.phaseChanged(.decelerating, source: source)
        motion.phaseChanged(.interacting, source: source, sample: sample(124))
        motion.consume(sample(108), source: source)
        XCTAssertFalse(motion.isCompact)
    }

    @MainActor
    func testGeometryPublishesOnlyActualTransitionsAndTabReset() {
        let motion = SOOMTabBarScrollMotion()
        let source = UUID(), nextTab = UUID()
        var publishes = 0
        let subscription = motion.$isCompact.dropFirst().sink { _ in publishes += 1 }
        defer { subscription.cancel() }
        motion.activate(source)
        motion.phaseChanged(.interacting, source: source, sample: sample(100))
        for value in 101...300 { motion.consume(sample(CGFloat(value)), source: source) }
        XCTAssertEqual(publishes, 1)
        for height in 2401...2500 { motion.consume(sample(300, contentHeight: CGFloat(height)), source: source) }
        XCTAssertEqual(publishes, 1)
        motion.activate(nextTab)
        XCTAssertEqual(publishes, 2)
        XCTAssertFalse(motion.isCompact)
        motion.consume(sample(400), source: source) // stale callback from old tab
        motion.consume(sample(500), source: nextTab) // idle callback
        XCTAssertEqual(publishes, 2)
        motion.phaseChanged(.interacting, source: nextTab, sample: sample(500))
        motion.consume(sample(524), source: nextTab)
        XCTAssertEqual(publishes, 3)
        motion.isEnabled = false // Reduce Motion / VoiceOver / keyboard / inactive scene
        XCTAssertFalse(motion.isCompact)
        XCTAssertEqual(publishes, 4)
        motion.consume(sample(600), source: nextTab)
        XCTAssertEqual(publishes, 4)
    }

    func testDecelerationFollowsTravelAfterOnePointCounterSample() {
        var state = SOOMTabBarScrollReducer()
        state.beginGesture()
        for value in [100, 112, 111] { state.consume(sample(CGFloat(value))) }
        state.decelerate()
        state.consume(sample(120))
        state.consume(sample(125))
        XCTAssertTrue(state.isCompact)
    }

    @MainActor
    func testDecelerationPhaseContextSuppressesBoundaryRecoil() {
        let motion = SOOMTabBarScrollMotion()
        let source = UUID()
        motion.activate(source)
        motion.phaseChanged(.interacting, source: source, sample: sample(100))
        motion.consume(sample(130), source: source)
        XCTAssertTrue(motion.isCompact)
        // Phase context reaches the bottom before its geometry action is delivered.
        motion.phaseChanged(.decelerating, source: source, sample: sample(1750))
        motion.consume(sample(1740), source: source)
        motion.consume(sample(1600), source: source)
        XCTAssertTrue(motion.isCompact)
        motion.phaseChanged(.interacting, source: source, sample: sample(1600))
        motion.consume(sample(1584), source: source)
        XCTAssertFalse(motion.isCompact)
    }
    func testRecordCharacterChangesOnlyAtCompletedClipBoundaries() {
        var clock = SOOMRecordCharacterTimeline()
        clock.setActive(true)
        clock.advance(to: 0)
        clock.advance(to: 3.2 - 1.0 / 30)
        XCTAssertEqual(clock.frameIndex, 95)
        XCTAssertTrue(clock.isRunningClip)
        clock.advance(to: 3.2)
        XCTAssertEqual(clock.frameIndex, 96)
        XCTAssertFalse(clock.isRunningClip)
        clock.advance(to: 7.2 - 1.0 / 30)
        XCTAssertEqual(clock.frameIndex, 215)
        clock.advance(to: 7.2)
        XCTAssertEqual(clock.frameIndex, 0)
        XCTAssertTrue(clock.isRunningClip)
    }

    func testRecordCharacterRepeatsHundredFullAlternationsWithoutDrift() {
        var clock = SOOMRecordCharacterTimeline()
        clock.setActive(true); clock.advance(to: 0)
        for tick in 1...21_600 {
            clock.advance(to: Double(tick) / 30)
            XCTAssertEqual(clock.frameIndex, tick % 216)
        }
        XCTAssertEqual(clock.elapsed, 0, accuracy: 0.0000001)
    }

    func testRecordCharacterPauseExcludesBackgroundAndInactiveTime() {
        var clock = SOOMRecordCharacterTimeline()
        clock.setActive(true); clock.advance(to: 10); clock.advance(to: 11)
        XCTAssertEqual(clock.frameIndex, 30)
        clock.setActive(false); clock.advance(to: 400)
        XCTAssertEqual(clock.frameIndex, 30)
        clock.setActive(true); clock.advance(to: 900)
        XCTAssertEqual(clock.frameIndex, 30)
        clock.advance(to: 901)
        XCTAssertEqual(clock.frameIndex, 60)
        clock.setActive(true); clock.advance(to: 902)
        XCTAssertEqual(clock.frameIndex, 90)
    }

    func testRecordCharacterInvalidClockCannotChangeFrame() {
        var clock = SOOMRecordCharacterTimeline()
        clock.advance(to: 100)
        XCTAssertEqual(clock.frameIndex, 0)
        clock.setActive(true); clock.advance(to: 10); clock.advance(to: 11)
        clock.advance(to: .nan); clock.advance(to: .infinity)
        XCTAssertEqual(clock.frameIndex, 30)
        clock.advance(to: 9)
        XCTAssertEqual(clock.frameIndex, 30)
        clock.advance(to: 10)
        XCTAssertEqual(clock.frameIndex, 60)
    }

    func testRecordCharacterAtlasRectsKeepEveryFrameInsideTransparentGutters() {
        for frame in 0..<216 {
            let rect = SOOMRecordCharacterTimeline.contentsRect(for: frame)
            XCTAssertGreaterThan(rect.minX, 0); XCTAssertGreaterThan(rect.minY, 0)
            XCTAssertLessThan(rect.maxX, 1); XCTAssertLessThan(rect.maxY, 1)
            XCTAssertEqual(rect.width * 1488, 120, accuracy: 0.00001)
            XCTAssertEqual(rect.height * 2232, 120, accuracy: 0.00001)
        }
        XCTAssertEqual(SOOMRecordCharacterTimeline.contentsRect(for: -1), SOOMRecordCharacterTimeline.contentsRect(for: 0))
        XCTAssertEqual(SOOMRecordCharacterTimeline.contentsRect(for: 999), SOOMRecordCharacterTimeline.contentsRect(for: 215))
    }

}


extension SOOMTabBarScrollMotionTests {
    func testReferenceCapsuleBottomDoesNotDoubleCountSystemInset() {
        for inset: CGFloat in [20, 21, 34] {
            XCTAssertEqual(inset + SOOMLayout.TabBar.bottomPadding - SOOMLayout.TabBar.safeAreaLowering(inset), 20)
        }
        XCTAssertEqual(SOOMLayout.TabBar.safeAreaLowering(0), 0)
        XCTAssertEqual(SOOMLayout.TabBar.safeAreaLowering(.nan), 0)
        XCTAssertGreaterThanOrEqual(SOOMLayout.TabBar.itemHeight, 44)
    }
}
