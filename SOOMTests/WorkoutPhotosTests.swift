import ImageIO
import SwiftUI
import UIKit
import XCTest
@testable import SOOM

@MainActor
final class WorkoutPhotosTests: XCTestCase {
    func testDecodedPortraitFirstPhotoStartsAtNormalInsetWithAndWithoutMap() async throws {
        let demo = ReviewDemoController.shared
        demo.start(); defer { demo.exit() }
        let runtime = try XCTUnwrap(demo.runtime)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: runtime.storage.container.mainContext)
        let recent = try await store.fetchRecentWorkouts(days: 90)
        let workout = try XCTUnwrap(recent.first)
        let sizes = [CGSize(width: 600, height: 900), CGSize(width: 500, height: 1000), CGSize(width: 1400, height: 600)]
        let colors: [UIColor] = [.red, .green, .blue]
        let drafts = try sizes.enumerated().map { index, size in
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                colors[index].setFill(); context.fill(CGRect(origin: .zero, size: size))
            }
            return WorkoutPhotoDraft(jpegData: try XCTUnwrap(image.jpegData(compressionQuality: 0.85)))
        }
        try await ReviewDemoPhotoStore.shared.replace(workout: workout, ownerID: ReviewDemoMode.userID, photos: drafts, expectedPhotoIDs: nil)
        let references = try await ReviewDemoPhotoStore.shared.load(workoutID: workout.id, ownerID: ReviewDemoMode.userID)
        for width: CGFloat in [393, 402] {
            for hasMap in [false, true] {
                for count in [1, 3] {
                    let row = WorkoutPhotoMediaRow(workoutID: nil, photos: Array(references.prefix(count)), hasRoute: hasMap) { Color.purple }
                        .environmentObject(runtime.auth).frame(width: width, height: 260)
                    let host = UIHostingController(rootView: row); host.safeAreaRegions = []
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 260))
                    window.rootViewController = host; window.isHidden = false
                    defer { window.isHidden = true; window.rootViewController = nil }
                    host.view.frame = window.bounds; window.layoutIfNeeded()
                    func findPager(_ view: UIView) -> UIScrollView? {
                        if let scroll = view as? UIScrollView, scroll.accessibilityIdentifier == "workout.media.pager" { return scroll }
                        return view.subviews.lazy.compactMap { findPager($0) }.first
                    }
                    let scroll = try XCTUnwrap(findPager(host.view))
                    let widths: [CGFloat] = (hasMap ? [260 * 4 / 3] : []) + (count == 1 ? [CGFloat(260 * 2 / 3)] : [CGFloat(260 * 2 / 3), 145, width - 32])
                    let expected = WorkoutMediaStripGeometry(widths: widths, viewportWidth: width)
                    for _ in 0..<40 {
                        host.view.layoutIfNeeded()
                        if abs(scroll.contentSize.width - expected.contentWidth) < 2 { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    XCTAssertEqual(scroll.contentSize.width, expected.contentWidth, accuracy: 2)
                    XCTAssertEqual(scroll.contentSize.height, 260, accuracy: 1)
                    XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 1)
                    let firstTile = try XCTUnwrap(scroll.subviews.filter { $0.frame.height > 250 && $0.frame.width > 100 }.min { $0.frame.minX < $1.frame.minX })
                    XCTAssertEqual(firstTile.frame.minX - scroll.contentOffset.x, 16, accuracy: 1,
                        "Mapless portrait must not get the former (viewport-firstWidth)/2 leading padding")
                    if width == 402 && !hasMap && count == 3 {
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                        }
                        let attachment = XCTAttachment(image: image); attachment.name = "Reply QA - decoded mapless portrait normal first inset"; attachment.lifetime = .keepAlways; add(attachment)
                    }
                }
            }
        }
    }

    func testKnownPhotoReentryRestoresCachedPageAfterInitialLoadTask() async throws {
        let photos = syntheticPhotos(count: 3)
        let key = "photos:" + photos.map { $0.id.uuidString }.joined(separator: ",") + ":map"
        let generation = CommunitySafetyStore.shared.accountGeneration
        WorkoutMediaSelectionCache.shared.save(photos[1].id.uuidString,
            key: key, owner: nil, generation: generation)
        let suite = "PhotoReentry-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(store: AuthSessionStore(userDefaults: defaults))
        let row = WorkoutPhotoMediaRow(workoutID: nil, photos: photos, hasRoute: true) {
            Color.red
        }.environmentObject(auth).frame(width: 393, height: 260)
        let host = UIHostingController(rootView: row)
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 260))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; window.layoutIfNeeded()
        // Let onAppear and the production async load task both complete.
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutIfNeeded()
        func pager(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.accessibilityIdentifier == "workout.media.pager" { return scroll }
            return view.subviews.lazy.compactMap { pager(in: $0) }.first
        }
        let scroll = try XCTUnwrap(pager(in: host.view))
        XCTAssertEqual(scroll.bounds.width, 393, accuracy: 1)
        XCTAssertEqual(scroll.contentOffset.x, WorkoutMediaStripGeometry(widths: [260 * 4 / 3, 361, 361, 361], viewportWidth: 393).offset(at: 2), accuracy: 1,
            "Reentry must retain photo 2 after the first load task, not reset to the map")
        XCTAssertEqual(scroll.contentInset, .zero)
        XCTAssertEqual(scroll.contentSize.height, 260, accuracy: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let evidence = XCTAttachment(image: snapshot); evidence.name = "Known photos – cached photo 2 on reentry"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testProgrammaticPagerCompletionDoesNotEchoSwiftUISelection() throws {
        let controller = WorkoutMediaPagerController()
        let pages = (0..<3).map { WorkoutMediaPage(id: String($0), content: AnyView(Color.red)) }
        controller.update(pages: pages, selectedID: "1", animated: false)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 260)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let scroll = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIScrollView }.first)
        var callbacks: [String] = []
        controller.onSelect = { callbacks.append($0) }
        controller.scrollViewDidEndScrollingAnimation(scroll)
        XCTAssertTrue(callbacks.isEmpty, "The SwiftUI binding already owns programmatic selections")
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertTrue(callbacks.isEmpty, "Unchanged pages must not write a binding during layout")
        scroll.contentOffset.x = 393 * 2
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(callbacks, ["2"], "A user page change is reported once")
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(callbacks, ["2"])
    }

    func testMediaPanGivesVerticalAndStationaryGesturesToOuterFeed() {
        XCTAssertFalse(WorkoutMediaScrollView.allowsHorizontalPan(velocity: CGPoint(x: 20, y: 400)))
        XCTAssertFalse(WorkoutMediaScrollView.allowsHorizontalPan(velocity: CGPoint(x: -20, y: -400)))
        XCTAssertFalse(WorkoutMediaScrollView.allowsHorizontalPan(velocity: .zero))
        XCTAssertFalse(WorkoutMediaScrollView.allowsHorizontalPan(velocity: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(WorkoutMediaScrollView.allowsHorizontalPan(velocity: CGPoint(x: -400, y: 20)))
        XCTAssertTrue(WorkoutMediaScrollView.allowsHorizontalPan(velocity: CGPoint(x: 400, y: -20)))
        XCTAssertFalse(WorkoutMediaScrollView.allowsHorizontalPan(velocity: CGPoint(x: CGFloat.infinity, y: 0)))
    }

    func testVariableStripCentersMiddleButClampsRealFirstAndLastEdges() {
        let widths: [CGFloat] = [260 * 4 / 3, 190, 145]
        let geometry = WorkoutMediaStripGeometry(widths: widths, viewportWidth: 393)
        XCTAssertEqual(geometry.frames[0].minX, 16)
        XCTAssertEqual(geometry.frames[1].minX - geometry.frames[0].maxX, 8, accuracy: 0.01)
        XCTAssertEqual(geometry.contentWidth, widths.reduce(0, +) + 32 + 16, accuracy: 0.01)
        XCTAssertEqual(geometry.offset(at: 0), 0)
        XCTAssertEqual(geometry.frames[1].midX - geometry.offset(at: 1), 393 / 2, accuracy: 0.01)
        XCTAssertEqual(geometry.offset(at: 2), geometry.maximumOffset)
        XCTAssertEqual(geometry.frames[2].maxX - geometry.offset(at: 2), 393 - 16, accuracy: 0.01,
            "Last tile ends at the normal inset, without artificial center padding")
        XCTAssertEqual(geometry.contentWidth - geometry.frames[2].maxX, 16, accuracy: 0.01)
    }

    func testVariableFastFlingMovesOneItemAtEveryStop() {
        let geometry = WorkoutMediaStripGeometry(widths: [346, 190, 145, 260, 190], viewportWidth: 393)
        for index in geometry.frames.indices {
            XCTAssertEqual(geometry.targetIndex(from: index, proposed: 99_999, velocity: 50), min(4, index + 1))
            XCTAssertEqual(geometry.targetIndex(from: index, proposed: -99_999, velocity: -50), max(0, index - 1))
            XCTAssertEqual(geometry.targetIndex(from: index, proposed: geometry.offset(at: index), velocity: 0), index)
        }
        let short = WorkoutMediaStripGeometry(widths: [145, 145], viewportWidth: 393)
        XCTAssertEqual(short.maximumOffset, 0)
        XCTAssertEqual(short.nearest(to: 0, preferred: 1), 1, "Equal edge anchors retain the logical selection")
        XCTAssertEqual(WorkoutMediaStripGeometry(widths: [], viewportWidth: 393).contentWidth, 0)
        XCTAssertEqual(WorkoutMediaStripGeometry(widths: [190], viewportWidth: 393).contentWidth, 222)
    }

    func testVariableControllerPreservesIDForLoadingWidthsRotationAndRemoval() throws {
        let controller = WorkoutMediaPagerController()
        func pages(_ widths: [CGFloat]) -> [WorkoutMediaPage] {
            widths.enumerated().map { WorkoutMediaPage(id: String($0.offset), content: AnyView(Color.blue), width: $0.element) }
        }
        controller.update(pages: pages([346, 361, 361]), selectedID: "1", animated: false, inset: 16, spacing: 8)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 260)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let scroll = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIScrollView }.first)
        var callbacks: [String] = []; controller.onSelect = { callbacks.append($0) }
        let widths: [CGFloat] = [346, 190, 145]
        controller.update(pages: pages(widths), selectedID: "1", animated: false, inset: 16, spacing: 8)
        for width: CGFloat in [320, 393, 852, 393] {
            controller.view.frame.size.width = width
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            let geometry = WorkoutMediaStripGeometry(widths: widths, viewportWidth: width)
            XCTAssertEqual(scroll.contentOffset.x, geometry.offset(at: 1), accuracy: 0.5)
            XCTAssertEqual(scroll.contentSize.height, 260)
            XCTAssertEqual(scroll.contentSize.width, geometry.contentWidth, accuracy: 0.01)
            XCTAssertEqual(scroll.isScrollEnabled, geometry.maximumOffset > 0)
        }
        XCTAssertTrue(callbacks.isEmpty, "Width changes do not publish user selection changes")
        controller.update(pages: [pages(widths)[2]], selectedID: "2", animated: false, inset: 16, spacing: 8)
        XCTAssertEqual(scroll.contentSize.width, 177)
        XCTAssertEqual(scroll.contentOffset.x, 0)
        XCTAssertFalse(scroll.isScrollEnabled)
    }

    func testRepeatedSwipesBeforeDecelerationFinishesAdvanceFromPriorTarget() throws {
        let widths: [CGFloat] = [346, 190, 145, 260]
        let geometry = WorkoutMediaStripGeometry(widths: widths, viewportWidth: 393)
        let pages = widths.enumerated().map { WorkoutMediaPage(id: String($0.offset), content: AnyView(Color.blue), width: $0.element) }
        let controller = WorkoutMediaPagerController()
        controller.update(pages: pages, selectedID: "0", animated: false, inset: 16, spacing: 8)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 260)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let scroll = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIScrollView }.first)
        var callbacks: [String] = []; controller.onSelect = { callbacks.append($0) }
        for index in 1...3 {
            controller.scrollViewWillBeginDragging(scroll)
            var target = CGPoint(x: 99_999, y: 0)
            controller.scrollViewWillEndDragging(scroll, withVelocity: CGPoint(x: 50, y: 0), targetContentOffset: &target)
            XCTAssertEqual(target.x, geometry.offset(at: index), accuracy: 0.5)
            // A second gesture interrupts deceleration before its completion delegate.
            scroll.contentOffset = target
        }
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(callbacks, ["3"])
        for index in [2, 1] {
            controller.scrollViewWillBeginDragging(scroll)
            var target = CGPoint(x: -99_999, y: 0)
            controller.scrollViewWillEndDragging(scroll, withVelocity: CGPoint(x: -50, y: 0), targetContentOffset: &target)
            XCTAssertEqual(target.x, geometry.offset(at: index), accuracy: 0.5)
            scroll.contentOffset = target
        }
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(callbacks, ["3", "1"])
    }

    func testVariableStripVisualEvidenceFirstMiddleLastAndWidthChange() throws {
        let controller = WorkoutMediaPagerController()
        let widths: [CGFloat] = [260 * 4 / 3, 190, 145]
        let colors: [Color] = [.blue, .green, .pink]
        let titles = ["MAP · 346.7pt", "PHOTO 1 · 190pt", "PHOTO 2 · 145pt"]
        let pages = widths.enumerated().map { index, width in
            WorkoutMediaPage(id: String(index), content: AnyView(ZStack {
                colors[index]
                Text(titles[index]).font(.caption.bold()).foregroundStyle(.white)
            }.clipShape(RoundedRectangle(cornerRadius: 10))), width: width)
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 260))
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        for index in pages.indices {
            controller.update(pages: pages, selectedID: String(index), animated: false, inset: 16, spacing: 8)
            window.layoutIfNeeded(); controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Variable strip – \(index == 0 ? "first" : index == 1 ? "middle" : "last") – synthetic data"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testMediaSelectionReentryIsBoundedAndAccountScoped() {
        let cache = WorkoutMediaSelectionCache(capacity: 2), owner = UUID()
        cache.save("photo", key: "one", owner: owner, generation: 1)
        XCTAssertEqual(cache.restore(key: "one", owner: owner, generation: 1,
            pages: ["map", "photo"], fallback: "map"), "photo")
        XCTAssertEqual(cache.restore(key: "one", owner: owner, generation: 1,
            pages: ["map"], fallback: "map"), "map")
        cache.save("photo", key: "two", owner: owner, generation: 1)
        cache.save("photo", key: "three", owner: owner, generation: 1)
        XCTAssertEqual(cache.restore(key: "one", owner: owner, generation: 1,
            pages: ["map", "photo"], fallback: "map"), "map")
        XCTAssertEqual(cache.restore(key: "two", owner: owner, generation: 2,
            pages: ["map", "photo"], fallback: "map"), "map")
        cache.save("photo", key: "one", owner: owner, generation: 2)
        XCTAssertEqual(cache.restore(key: "one", owner: UUID(), generation: 2,
            pages: ["map", "photo"], fallback: "map"), "map")
    }

    func testNativePagerPreservesSelectedPageOnWidthChangeAndLimitsFastFling() throws {
        let controller = WorkoutMediaPagerController()
        let pages = (0..<4).map { WorkoutMediaPage(id: String($0), content: AnyView(Color.red)) }
        controller.update(pages: pages, selectedID: "1", animated: false)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 260)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let scroll = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIScrollView }.first)
        XCTAssertFalse(scroll.isPagingEnabled, "Variable widths require content-aware snapping")
        XCTAssertTrue(scroll.isDirectionalLockEnabled)
        XCTAssertEqual(scroll.contentOffset.x, 393, accuracy: 1)
        controller.view.frame = CGRect(x: 0, y: 0, width: 852, height: 260)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertEqual(scroll.contentOffset.x, 852, accuracy: 1)
        XCTAssertEqual(scroll.contentSize, CGSize(width: 852 * 4, height: 260))
        controller.scrollViewWillBeginDragging(scroll)
        var target = CGPoint(x: 852 * 3, y: 0)
        controller.scrollViewWillEndDragging(scroll, withVelocity: CGPoint(x: 20, y: 0), targetContentOffset: &target)
        XCTAssertEqual(target.x, 852 * 2, accuracy: 1, "A fast fling advances at most one page")
        var selection: String?
        controller.onSelect = { selection = $0 }
        scroll.contentOffset = CGPoint(x: 852 * 2, y: 0)
        controller.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(selection, "2")
        controller.update(pages: [pages[2]], selectedID: "2", animated: false)
        XCTAssertFalse(scroll.isScrollEnabled)
        XCTAssertEqual(scroll.contentOffset.x, 0)
    }

    func testPagingGeometryRemainsFixedForSmallPortraitAndWideViewports() throws {
        for width: CGFloat in [320, 393, 852] {
            let rendered = try renderMediaRow(photos: syntheticPhotos(count: 3), hasRoute: true, width: width)
            XCTAssertEqual(rendered.fitting.width, width, accuracy: 1)
            XCTAssertEqual(rendered.fitting.height, 260, accuracy: 1)
            XCTAssertEqual(rendered.image.size.width, width, accuracy: 1)
            XCTAssertEqual(rendered.image.size.height, 260, accuracy: 1)
        }
    }

    func testSinglePhotoRetainsHeightWithoutMap() throws {
        let rendered = try renderMediaRow(photos: syntheticPhotos(count: 1), hasRoute: false)
        XCTAssertEqual(rendered.fitting.height, 260, accuracy: 1)
        XCTAssertEqual(try redMarkerPixelCount(rendered.image), 0)
    }

    func testMediaPagesKeepMapAndPhotosOnStableItemIdentities() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(WorkoutMediaPages.ids(hasRoute: false, photos: []), [])
        XCTAssertEqual(WorkoutMediaPages.ids(hasRoute: true, photos: []), ["map"])
        XCTAssertEqual(WorkoutMediaPages.ids(hasRoute: false, photos: [a]), [a.uuidString])
        let pages = WorkoutMediaPages.ids(hasRoute: true, photos: [a, b, c])
        XCTAssertEqual(pages, ["map", a.uuidString, b.uuidString, c.uuidString])
        XCTAssertEqual(WorkoutMediaPages.adjacent("map", in: pages, forward: true), a.uuidString)
        XCTAssertEqual(WorkoutMediaPages.adjacent(c.uuidString, in: pages, forward: true), c.uuidString)
        XCTAssertEqual(WorkoutMediaPages.adjacent("map", in: pages, forward: false), "map")
        XCTAssertEqual(WorkoutMediaPages.selection(b.uuidString, in: pages), b.uuidString)
        XCTAssertEqual(WorkoutMediaPages.selection(b.uuidString, in: ["map"]), "map")
        XCTAssertEqual(WorkoutMediaPages.selection("map", in: [a.uuidString]), a.uuidString)
        XCTAssertEqual(WorkoutMediaPages.adjacent("map", in: [], forward: true), "map")
    }

    func testPhotoDismissalShrinksAtCenterBeforeMovingDownAndArming() {
        let initial = WorkoutPhotoDismissal.state(drag: 0, height: 800)
        XCTAssertEqual(initial.scale, 1)
        XCTAssertEqual(initial.translation, 0)
        XCTAssertFalse(initial.isArmed)

        let shrinking = WorkoutPhotoDismissal.state(drag: 48, height: 800)
        XCTAssertEqual(shrinking.scale, 0.965, accuracy: 0.001)
        XCTAssertEqual(shrinking.translation, 0)
        XCTAssertFalse(shrinking.isArmed)

        let shrunken = WorkoutPhotoDismissal.state(drag: 96, height: 800)
        XCTAssertEqual(shrunken.scale, 0.93, accuracy: 0.001)
        XCTAssertEqual(shrunken.translation, 0)
        XCTAssertFalse(shrunken.isArmed, "Reaching the scale target alone must not close the layer")

        let armed = WorkoutPhotoDismissal.state(drag: 136, height: 800)
        XCTAssertEqual(armed.scale, 0.93, accuracy: 0.001)
        XCTAssertEqual(armed.translation, 40)
        XCTAssertTrue(armed.isArmed)
        XCTAssertFalse(WorkoutPhotoDismissal.state(drag: 130, height: 800).isArmed,
                       "Dragging back above the threshold must cancel dismissal, even after arming")
    }

    func testPhotoDismissalDoesNotStealPagingOrZoomPan() {
        XCTAssertTrue(WorkoutPhotoDismissal.canBegin(velocity: CGPoint(x: 5, y: 100), zoomScale: 1))
        XCTAssertFalse(WorkoutPhotoDismissal.canBegin(velocity: CGPoint(x: 100, y: 5), zoomScale: 1))
        XCTAssertFalse(WorkoutPhotoDismissal.canBegin(velocity: CGPoint(x: 5, y: -100), zoomScale: 1))
        XCTAssertFalse(WorkoutPhotoDismissal.canBegin(velocity: CGPoint(x: 0, y: 100), zoomScale: 2.5))
        XCTAssertEqual(WorkoutPhotoDismissal.state(drag: -50, height: 800).scale, 1)
        XCTAssertFalse(WorkoutPhotoDismissal.state(drag: .infinity, height: 800).isArmed)
    }

    func testDetailPhotoHeightUsesWidthForBothOrientations() {
        XCTAssertEqual(WorkoutPhotoMediaLayout.widthAnchoredHeight(imageSize: CGSize(width: 1200, height: 800), width: 393), 262)
        XCTAssertEqual(WorkoutPhotoMediaLayout.widthAnchoredHeight(imageSize: CGSize(width: 800, height: 1200), width: 393), 589.5)
    }

    func testPhotoZoomContentExcludesBlackLetterboxSpace() {
        let viewport = CGSize(width: 393, height: 852)
        let landscape = WorkoutPhotoZoomLayout.fittedImageSize(image: CGSize(width: 1200, height: 800), viewport: viewport)
        XCTAssertEqual(landscape.width, 393)
        XCTAssertEqual(landscape.height, 262)
        let initial = WorkoutPhotoZoomLayout.centeringInsets(content: landscape, viewport: viewport)
        XCTAssertEqual(initial.top, 295)
        XCTAssertEqual(initial.bottom, 295)
        XCTAssertEqual(initial.left, 0)

        let zoomed = CGSize(width: landscape.width * 2.5, height: landscape.height * 2.5)
        let centered = WorkoutPhotoZoomLayout.centeringInsets(content: zoomed, viewport: viewport)
        XCTAssertEqual(centered.top, 98.5)
        XCTAssertEqual(centered.bottom, 98.5,
                       "A zoomed landscape photo shorter than the viewport remains centered, not vertically pannable into black space")
        XCTAssertEqual(centered.left, 0)
        XCTAssertEqual(WorkoutPhotoZoomLayout.centeringInsets(
            content: CGSize(width: landscape.width * 5, height: landscape.height * 5), viewport: viewport), .zero,
                       "Once the actual photo fills both axes, pan bounds follow only the image pixels")
    }

    func testVeryTallPhotosFitHeightAndCenterHorizontally() {
        let viewport = CGSize(width: 393, height: 852)
        let portrait = WorkoutPhotoZoomLayout.fittedImageSize(image: CGSize(width: 600, height: 1800), viewport: viewport)
        XCTAssertEqual(portrait, CGSize(width: 284, height: 852))
        let inset = WorkoutPhotoZoomLayout.centeringInsets(content: portrait, viewport: viewport)
        XCTAssertEqual(inset.left, 54.5)
        XCTAssertEqual(inset.right, 54.5)
        XCTAssertEqual(inset.top, 0)
        XCTAssertEqual(WorkoutPhotoZoomLayout.fittedImageSize(image: .zero, viewport: viewport), .zero)
    }

    func testSoloRouteMediaUsesFeedHeightAt393Points() throws {
        let rendered = try renderMediaRow(photos: [], hasRoute: true)
        XCTAssertEqual(rendered.fitting.width, 393, accuracy: 0.1)
        XCTAssertEqual(rendered.fitting.height, 260, accuracy: 0.5, "UIKit rounds the fitting size to display pixels")
        XCTAssertEqual(rendered.image.size.height, 260, accuracy: 1, "Bitmap rounding may differ by one pixel")
        XCTAssertGreaterThan(try redMarkerPixelCount(rendered.image), 95_000,
            "The real route child must fill the solo map, rather than collapse to a thin row")
    }

    func testRouteAndPhotosMediaStripRetainsOriginalVariableWidthAndNeighborPeek() throws {
        let rendered = try renderMediaRow(photos: syntheticPhotos(count: 2), hasRoute: true)
        XCTAssertEqual(rendered.fitting.width, 393, accuracy: 0.1)
        XCTAssertEqual(rendered.fitting.height, 260, accuracy: 0.1)
        XCTAssertEqual(rendered.image.size.width, 393, accuracy: 1)
        XCTAssertEqual(rendered.image.size.height, 260, accuracy: 1)
        let markerPixels = try redMarkerPixelCount(rendered.image)
        XCTAssertGreaterThan(markerPixels, 85_000, "The established map tile remains 260 × 4/3 points wide")
        XCTAssertLessThan(markerPixels, 92_000, "Normal side insets leave the next photo visible")
    }

    func testPhotosWithoutRouteUse260PointHeightAndDoNotInsertMapTile() throws {
        let rendered = try renderMediaRow(photos: syntheticPhotos(count: 2), hasRoute: false)
        XCTAssertEqual(rendered.fitting.width, 393, accuracy: 0.1)
        XCTAssertEqual(rendered.fitting.height, 260, accuracy: 0.1)
        XCTAssertEqual(rendered.image.size.height, 260, accuracy: 1)
        XCTAssertEqual(try redMarkerPixelCount(rendered.image), 0,
            "A mapless workout must not render a blank or invented route tile")
    }

    func testMediaTilesKeepLandscapeWideAndPortraitPhotosNarrow() {
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: 4.0 / 3.0, maxWidth: 361), 260 * 4.0 / 3.0, accuracy: 0.1)
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: 0.5, maxWidth: 361), 145, accuracy: 0.1)
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: 0.7, maxWidth: 361), 182, accuracy: 0.1)
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: nil, maxWidth: 361), 361, accuracy: 0.1)
    }

    func testReencodingRemovesGPSAndCameraMetadataAndBoundsDimensions() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 900), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 900))
        }
        let source = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(source, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLongitude: 127.0],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Private Camera"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Private source metadata"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let output = try WorkoutPhotoPolicy.sanitizedJPEG(from: source as Data)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [String: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertNil((properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFMake as String])
        XCTAssertNil((properties[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifUserComment as String])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth as String] as? Int), 2048)
        XCTAssertLessThanOrEqual(output.count, WorkoutPhotoPolicy.maximumBytes)
    }

    func testInvalidImageAndOversizedInputAreRejected() {
        XCTAssertThrowsError(try WorkoutPhotoPolicy.sanitizedJPEG(from: Data("not an image".utf8)))
        XCTAssertThrowsError(try WorkoutPhotoPolicy.sanitizedJPEG(from: Data(repeating: 0, count: 40 * 1_024 * 1_024 + 1)))
    }

    func testOnlyCanonicalPrivateStorageReferencesBecomeFeedImages() {
        let owner = UUID(), post = UUID(), photo = UUID()
        let path = WorkoutPhotoPolicy.path(ownerID: owner, postID: post, photoID: photo)
        XCTAssertTrue(WorkoutPhotoPolicy.validPath(path))
        for bad in ["https://example.com/photo.jpg?token=secret", "../../photo.jpg", "/" + path,
                    path + "?token=secret", path.replacingOccurrences(of: ".jpg", with: ".png")] {
            XCTAssertFalse(WorkoutPhotoPolicy.validPath(bad))
            XCTAssertNil(FeedPostMediaDTO(id: photo, postId: post, mediaType: .photo, storagePath: bad, sortOrder: 0).photoReference)
        }
        let reference = FeedPostMediaDTO(id: photo, postId: post, mediaType: .photo, storagePath: path, sortOrder: 0).photoReference
        XCTAssertEqual(reference, WorkoutPhotoReference(id: photo, storagePath: path))
        XCTAssertNil(FeedPostMediaDTO(id: photo, postId: post, mediaType: .photo, previewPayload: .init(title: "Legacy placeholder"), sortOrder: 0).photoReference)
    }

    func testFeedMappingKeepsPhotosOrderedAndRouteSeparate() {
        let owner = UUID(), post = UUID(), first = UUID(), second = UUID(), map = UUID()
        let rows = [(second, FeedPostMediaType.photo, 2), (map, .route, -1), (first, .photo, 1)].map { id, type, order in
            FeedPostMediaDTO(id: id, postId: post, mediaType: type,
                storagePath: WorkoutPhotoPolicy.path(ownerID: owner, postID: post, photoID: id), sortOrder: order)
        }
        let result = FeedPostBundleDTO(post: FeedPostDTO(id: post, userId: owner, sport: .running,
            title: "운동", createdAt: Date()), media: rows).makeFeedItem()
        XCTAssertEqual(result.photos.map(\.id), [first, second])
        XCTAssertEqual(result.routePhoto?.id, map)
    }

    private func syntheticPhotos(count: Int) -> [WorkoutPhotoReference] {
        let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let post = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        return (0..<count).map { _ in
            let id = UUID()
            return WorkoutPhotoReference(id: id,
                storagePath: WorkoutPhotoPolicy.path(ownerID: owner, postID: post, photoID: id))
        }
    }

    /// Exercises the production row layout in a vertically unconstrained feed
    /// stack. Signed-out synthetic auth and a nil workout ID make both media
    /// lookup and image fetching exit before constructing a network client.
    private func renderMediaRow(photos: [WorkoutPhotoReference], hasRoute: Bool, width: CGFloat = 393) throws -> (fitting: CGSize, image: UIImage) {
        let suite = "WorkoutPhotosLayoutTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(store: AuthSessionStore(userDefaults: defaults))
        XCTAssertNil(auth.session.currentUser)
        let content = VStack(spacing: 0) {
            WorkoutPhotoMediaRow(workoutID: nil, photos: photos, hasRoute: hasRoute) {
                Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))
            }
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .environmentObject(auth)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)

        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        let fitting = host.sizeThatFits(in: CGSize(width: width, height: 1_000))
        let window = UIWindow(frame: CGRect(origin: .zero, size: fitting))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        host.view.backgroundColor = .white
        window.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // ImageRenderer omits the UIKit-backed horizontal ScrollView on
        // iOS 18. Capture the actual hosting hierarchy after its layout pass.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: fitting, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Workout media layout – map \(hasRoute), photos \(photos.count)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return (fitting, image)
    }

    private func redMarkerPixelCount(_ image: UIImage) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        let width = source.width, height = source.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: bytes.count, by: 4).reduce(into: 0) { count, index in
                if bytes[index] > 245, bytes[index + 1] < 10, bytes[index + 2] < 10, bytes[index + 3] > 245 { count += 1 }
            }
        }
    }

    func testScrollContentWidthStaysAnchoredForPortraitAndLandscape() {
        for width: CGFloat in [320, 393, 430, 852] {
            let layout = SOOMScrollContentLayout(viewportWidth: width, horizontalPadding: 16)
            XCTAssertEqual(layout.contentWidth + 2 * layout.horizontalPadding, width)
            XCTAssertEqual(layout.contentWidth, width - 32)
            // A full-bleed card's existing -16pt padding still resolves to the viewport.
            XCTAssertEqual(layout.contentWidth + 32, width)
        }
    }

    func testScrollContentWidthRejectsTransientInvalidGeometry() {
        for width: CGFloat in [0, -1, .nan, .infinity] {
            let layout = SOOMScrollContentLayout(viewportWidth: width, horizontalPadding: 16)
            XCTAssertEqual(layout.contentWidth, 0)
            XCTAssertEqual(layout.viewportWidth, 0)
        }
        XCTAssertEqual(SOOMScrollContentLayout(viewportWidth: 20, horizontalPadding: 16).contentWidth, 0)
        XCTAssertEqual(SOOMScrollContentLayout(viewportWidth: 393, horizontalPadding: .nan).contentWidth, 393)
    }

    func testRevalidationReservesVerifiedCardHeightWithoutExposingContent() {
        var reservation = SOOMContentHeightReservation()
        XCTAssertTrue(reservation.record(CGSize(width: 393, height: 620)))
        XCTAssertEqual(reservation.height(forViewportWidth: 393), 620)
        XCTAssertEqual(reservation.height(forViewportWidth: nil), 620)
        XCTAssertNil(reservation.height(forViewportWidth: 852), "Rotation must not reuse the old width's height")
        XCTAssertNil(reservation.height(forViewportWidth: .nan))
    }

    func testHeightMeasurementIgnoresSubpixelJitterAndInvalidSizes() {
        var reservation = SOOMContentHeightReservation()
        XCTAssertFalse(reservation.record(.zero))
        XCTAssertTrue(reservation.record(CGSize(width: 393, height: 620)))
        XCTAssertFalse(reservation.record(CGSize(width: 393.2, height: 620.2)))
        XCTAssertFalse(reservation.record(CGSize(width: CGFloat.infinity, height: 620)))
        XCTAssertEqual(reservation.verifiedSize, CGSize(width: 393, height: 620))
        XCTAssertTrue(reservation.record(CGSize(width: 393, height: 621)))
    }

    func testInitialLoadingSlotReservesKnownMediaHeight() {
        XCTAssertEqual(SOOMContentHeightReservation.initialHeight(hasKnownMedia: false), 224)
        XCTAssertEqual(SOOMContentHeightReservation.initialHeight(hasKnownMedia: true), 484)
    }

    func testCompletedPhotoReappearanceRetainsPortraitWidthAndMaplessHeight() {
        let key = photoLoadIdentity()
        var state = WorkoutPhotoRowLoadState()
        var loaded = [UUID()]
        var ratio: CGFloat? = 0.5
        XCTAssertTrue(state.begin(key).shouldLoad)
        XCTAssertTrue(state.complete(key))
        let decision = state.begin(key)
        if decision.resetScope { loaded = []; ratio = nil }
        XCTAssertFalse(decision.resetScope)
        XCTAssertFalse(decision.shouldLoad)
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: ratio, maxWidth: 361), 145)
        XCTAssertEqual(loaded.isEmpty ? 0 : 260, 260)
        XCTAssertTrue(state.canDisplayLoaded(for: key))
    }

    func testPhotoRevisionReloadPreservesGeometryUntilReplacementArrives() {
        let key = photoLoadIdentity()
        var state = WorkoutPhotoRowLoadState()
        _ = state.begin(key); XCTAssertTrue(state.complete(key))
        let changed = photoLoadIdentity(owner: key.ownerID!, generation: key.accountGeneration,
                                        workout: key.workoutID!, revision: 1)
        let decision = state.begin(changed)
        XCTAssertFalse(decision.resetScope)
        XCTAssertTrue(decision.shouldLoad)
        XCTAssertTrue(state.canDisplayLoaded(for: changed))
        XCTAssertFalse(state.complete(key), "The preceding revision cannot finish the new load")
        XCTAssertTrue(state.complete(changed))
    }

    func testExplicitPhotoPathChangeInvalidatesCompletedLoad() {
        let key = photoLoadIdentity()
        var state = WorkoutPhotoRowLoadState()
        _ = state.begin(key); _ = state.complete(key)
        let changed = WorkoutPhotoLoadIdentity(ownerID: key.ownerID, accountGeneration: key.accountGeneration,
            workoutID: key.workoutID, revision: key.revision, photoPaths: ["replacement.jpg"])
        XCTAssertTrue(state.begin(changed).shouldLoad)
        XCTAssertFalse(state.complete(key))
        XCTAssertTrue(state.complete(changed))
    }

    func testAccountGenerationChangeClearsMediaAndRejectsLateResults() {
        let first = photoLoadIdentity()
        var state = WorkoutPhotoRowLoadState()
        _ = state.begin(first); _ = state.complete(first)
        let switched = photoLoadIdentity(generation: 2, workout: first.workoutID!)
        XCTAssertTrue(state.begin(switched).resetScope)
        XCTAssertFalse(state.canDisplayLoaded(for: first))
        XCTAssertFalse(state.complete(first))
        let returned = photoLoadIdentity(owner: first.ownerID!, generation: 3, workout: first.workoutID!)
        XCTAssertTrue(state.begin(returned).resetScope)
        XCTAssertFalse(state.complete(switched))
        XCTAssertTrue(state.complete(returned))
        XCTAssertFalse(state.complete(returned), "A duplicate completion must not republish state")
    }

    func testCancelledPhotoLoadCanRetryWithoutResettingSameScope() {
        let key = photoLoadIdentity()
        var state = WorkoutPhotoRowLoadState()
        XCTAssertTrue(state.begin(key).shouldLoad)
        let retry = state.begin(key)
        XCTAssertFalse(retry.resetScope)
        XCTAssertTrue(retry.shouldLoad)
        let anotherWorkout = photoLoadIdentity(owner: key.ownerID!, workout: UUID())
        XCTAssertTrue(state.begin(anotherWorkout).resetScope)
        XCTAssertFalse(state.complete(key))
    }

    func testMediaWidthNeverBecomesNegativeDuringInitialLayout() {
        for width: CGFloat in [0, 20, -1, .nan, .infinity] {
            XCTAssertEqual(WorkoutPhotoMediaLayout.availableWidth(in: width), 0)
        }
        XCTAssertEqual(WorkoutPhotoMediaLayout.availableWidth(in: 393), 361)
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: 0.5, maxWidth: -32), 0)
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: nil, maxWidth: .nan), 0)
        XCTAssertEqual(WorkoutPhotoMediaLayout.tileWidth(aspectRatio: 4.0 / 3.0, maxWidth: 361), 260 * 4.0 / 3.0, accuracy: 0.1)
    }

    func testBackgroundPhotoDecoderRealizesBoundedPixels() throws {
        let bytes = try scrollStabilityJPEG(width: 3000, height: 900)
        let completion = expectation(description: "bounded ImageIO pixels")
        Task.detached {
            let image = await WorkoutPhotoImageDecoder.decode(bytes)
            XCTAssertNotNil(image)
            if let image {
                XCTAssertEqual(image.width, 2048)
                XCTAssertLessThanOrEqual(image.height, 615)
            }
            completion.fulfill()
        }
        wait(for: [completion], timeout: 10)
    }

    func testBackgroundPhotoDecoderRejectsInvalidBytes() {
        let completion = expectation(description: "invalid ImageIO source")
        Task.detached {
            let empty = await WorkoutPhotoImageDecoder.decode(Data())
            let invalid = await WorkoutPhotoImageDecoder.decode(Data("not an image".utf8))
            XCTAssertNil(empty)
            XCTAssertNil(invalid)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 10)
    }

    private func photoLoadIdentity(owner: UUID = UUID(), generation: Int = 1,
                                   workout: UUID = UUID(), revision: Int = 0) -> WorkoutPhotoLoadIdentity {
        WorkoutPhotoLoadIdentity(ownerID: owner, accountGeneration: generation,
            workoutID: workout, revision: revision, photoPaths: [])
    }

    private func scrollStabilityJPEG(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    func testPhotoCacheReentryRechecksAccessButDownloadsAndDecodesOnce() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope()
        var authorizations = 0, downloads = 0
        for _ in 0..<3 {
            let result = try await cache.value(for: "photo", scope: scope, authorize: {
                authorizations += 1; return "v1"
            }, load: { downloads += 1; return ("pixels", 20) })
            XCTAssertEqual(result, "pixels")
        }
        XCTAssertEqual(authorizations, 3, "Every reappearance must verify current permission")
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(cache.statistics.hits, 2)
        XCTAssertEqual(cache.statistics.misses, 1)
    }

    func testPhotoCacheSimultaneousRequestsShareAuthorizationAndDecode() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        var authorizations = 0, downloads = 0
        let first = Task { try await cache.value(for: "photo", scope: scope, authorize: {
            authorizations += 1; await gate.wait(); return "v1"
        }, load: { downloads += 1; return ("pixels", 20) }) }
        while !gate.started { await Task.yield() }
        let second = Task { try await cache.value(for: "photo", scope: scope,
            authorize: { authorizations += 1; return "v1" }, load: { downloads += 1; return ("pixels", 20) }) }
        while cache.statistics.joinedRequests == 0 { await Task.yield() }
        gate.resume()
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a, b)
        XCTAssertEqual(authorizations, 1)
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(cache.inFlightCount, 0)
    }

    func testPhotoCachePermissionRevocationNeverReturnsPriorPixels() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope()
        _ = try await cache.value(for: "photo", scope: scope, authorize: { "v1" }, load: { ("pixels", 20) })
        do {
            _ = try await cache.value(for: "photo", scope: scope, authorize: { throw CacheTestError.denied },
                                      load: { XCTFail("Denied access cannot download"); return ("bad", 20) })
            XCTFail("Revoked/deleted storage must not use the cache")
        } catch CacheTestError.denied { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(cache.entryCount, 0)
        XCTAssertEqual(cache.totalCost, 0)
        XCTAssertEqual(cache.statistics.hits, 0)
    }

    func testPhotoCacheChangedServerVersionRequiresNewPixels() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope()
        var loads = 0
        _ = try await cache.value(for: "photo", scope: scope, authorize: { "v1" }, load: { loads += 1; return ("old", 20) })
        let next = try await cache.value(for: "photo", scope: scope, authorize: { "v2" }, load: { loads += 1; return ("new", 25) })
        XCTAssertEqual(next, "new")
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(cache.totalCost, 25)
        XCTAssertEqual(cache.entryCount, 1)
    }

    func testPhotoCacheAccountChangeRejectsInFlightOldAccountResult() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let firstScope = cacheTestScope(), gate = CacheTestSuspension()
        let first = Task { try await cache.value(for: "photo", scope: firstScope, authorize: {
            await gate.wait(); return "v1"
        }, load: { XCTFail("Old account cannot continue to download"); return ("old", 20) }) }
        while !gate.started { await Task.yield() }
        let nextScope = cacheTestScope(generation: 2)
        let next = try await cache.value(for: "photo", scope: nextScope, authorize: { "v1" }, load: { ("new account", 20) })
        gate.resume()
        do { _ = try await first.value; XCTFail("Late old-account result accepted") } catch { }
        XCTAssertEqual(next, "new account")
        XCTAssertEqual(cache.entryCount, 1)
    }

    func testPhotoCacheSameUserAtoBtoAAndSafetyRevisionInvalidate() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let viewer = UUID()
        var loads = 0
        for scope in [cacheTestScope(viewer: viewer), cacheTestScope(generation: 2),
                      cacheTestScope(viewer: viewer, generation: 3), cacheTestScope(viewer: viewer, generation: 3, revision: 1)] {
            _ = try await cache.value(for: "photo", scope: scope, authorize: { "v1" }, load: { loads += 1; return ("pixels", 20) })
        }
        XCTAssertEqual(loads, 4)
        XCTAssertEqual(cache.statistics.hits, 0)
        XCTAssertEqual(cache.entryCount, 1)
    }

    func testPhotoCacheExplicitDeletionInvalidationAndMemoryWarningClear() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope()
        var loads = 0
        _ = try await cache.value(for: "photo", scope: scope, authorize: { "v1" }, load: { loads += 1; return ("pixels", 20) })
        cache.invalidate()
        XCTAssertEqual(cache.entryCount, 0)
        XCTAssertEqual(cache.totalCost, 0)
        _ = try await cache.value(for: "photo", scope: scope, authorize: { "v1" }, load: { loads += 1; return ("pixels", 20) })
        XCTAssertEqual(loads, 2)
    }

    func testPhotoCacheLRUEvictionKeepsBothByteAndEntryLimits() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 10, maximumCount: 2)
        let scope = cacheTestScope()
        var loads: [String: Int] = [:]
        for key in ["a", "b", "a", "c", "b"] {
            _ = try await cache.value(for: key, scope: scope, authorize: { "v1" }, load: {
                loads[key, default: 0] += 1; return (key, 4)
            })
            XCTAssertLessThanOrEqual(cache.totalCost, 10)
            XCTAssertLessThanOrEqual(cache.entryCount, 2)
        }
        XCTAssertEqual(loads["a"], 1)
        XCTAssertEqual(loads["b"], 2, "Least recently used pixels must be evicted")
        XCTAssertEqual(cache.statistics.evictions, 2)
    }

    func testPhotoCacheOversizedPixelsReturnWithoutExceedingMemoryLimit() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 10, maximumCount: 2)
        let scope = cacheTestScope()
        var loads = 0
        for _ in 0..<2 {
            _ = try await cache.value(for: "large", scope: scope, authorize: { "v1" }, load: { loads += 1; return ("large", 11) })
        }
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(cache.entryCount, 0)
        XCTAssertEqual(cache.totalCost, 0)
    }

    func testPhotoCacheFailedDecodeDoesNotCreateCachedOrInFlightEntry() async {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        do {
            _ = try await cache.value(for: "bad", scope: cacheTestScope(), authorize: { "v1" }, load: { throw CacheTestError.decode })
            XCTFail("Invalid pixels accepted")
        } catch { }
        XCTAssertEqual(cache.entryCount, 0)
        XCTAssertEqual(cache.inFlightCount, 0)
    }

    func testPhotoCacheInvalidationDuringDecodeRejectsLatePixels() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        let old = Task { try await cache.value(for: "photo", scope: scope, authorize: { "v1" }, load: {
            await gate.wait(); return ("old", 20)
        }) }
        while !gate.started { await Task.yield() }
        cache.invalidate()
        let fresh = try await cache.value(for: "photo", scope: scope, authorize: { "v2" }, load: { ("fresh", 20) })
        gate.resume()
        do { _ = try await old.value; XCTFail("Invalidated decode result accepted") } catch { }
        XCTAssertEqual(fresh, "fresh")
        XCTAssertEqual(cache.entryCount, 1)
        XCTAssertEqual(cache.totalCost, 20)
    }

    func testPhotoCacheByteAndCountLimitsIndependently() async throws {
        let bytes = SOOMValidatedMemoryCache<String, String>(maximumCost: 10, maximumCount: 12)
        let count = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 2)
        let scope = cacheTestScope()
        for key in ["a", "b", "c"] {
            _ = try await bytes.value(for: key, scope: scope, authorize: { "v1" }, load: { (key, 4) })
            _ = try await count.value(for: key, scope: scope, authorize: { "v1" }, load: { (key, 1) })
        }
        XCTAssertEqual(bytes.totalCost, 8)
        XCTAssertEqual(bytes.entryCount, 2)
        XCTAssertEqual(count.totalCost, 2)
        XCTAssertEqual(count.entryCount, 2)
    }

    func testFeedPhotoPresentationEpochReusesOnlyBoundedResidentPixels() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 10, maximumCount: 2)
        let scope = cacheTestScope()
        var checks = 0, loads = 0
        func read(_ key: String, _ epoch: String?) async throws -> String {
            try await cache.value(for: key, scope: scope, presentationEpoch: epoch,
                authorize: { checks += 1; return "v1" }, load: { loads += 1; return (key, 4) })
        }
        _ = try await read("a", "feed-visit1")
        _ = try await read("a", "feed-visit1")
        XCTAssertEqual(checks, 1); XCTAssertEqual(loads, 1)
        _ = try await read("a", "feed-visit2")
        XCTAssertEqual(checks, 2); XCTAssertEqual(loads, 1)
        _ = try await read("a", nil); _ = try await read("a", nil)
        XCTAssertEqual(checks, 4, "Unscoped galleries never bypass authorization")
        _ = try await read("b", "feed-visit2"); _ = try await read("c", "feed-visit2")
        XCTAssertEqual(cache.entryCount, 2); XCTAssertEqual(cache.totalCost, 8)
        _ = try await read("a", "feed-visit2")
        XCTAssertEqual(checks, 7); XCTAssertEqual(loads, 4)
        cache.invalidate()
        _ = try await read("a", "feed-visit2")
        XCTAssertEqual(checks, 8); XCTAssertEqual(loads, 5)
    }

    func testFeedPhotoNewEpochDenialNeverReturnsPreviousPixels() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope()
        _ = try await cache.value(for: "p", scope: scope, presentationEpoch: "old",
            authorize: { "v1" }, load: { ("pixels", 20) })
        do {
            _ = try await cache.value(for: "p", scope: scope, presentationEpoch: "new",
                authorize: { throw CacheTestError.denied }, load: { XCTFail("Denied load"); return ("bad", 20) })
            XCTFail("Old pixels reused after denied new epoch")
        } catch { }
        XCTAssertEqual(cache.entryCount, 0)
    }

    func testFeedPhotoNewEpochCannotJoinOldAuthorizationFlight() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        let old = Task { try await cache.value(for: "p", scope: scope, presentationEpoch: "old",
            authorize: { await gate.wait(); return "v1" }, load: { ("old", 20) }) }
        while !gate.started { await Task.yield() }
        let fresh = try await cache.value(for: "p", scope: scope, presentationEpoch: "new",
            authorize: { "v2" }, load: { ("new", 20) })
        gate.resume()
        do { _ = try await old.value; XCTFail("Late old epoch accepted") } catch { }
        XCTAssertEqual(fresh, "new"); XCTAssertEqual(cache.entryCount, 1)
        let cached = try await cache.value(for: "p", scope: scope, presentationEpoch: "new",
            authorize: { XCTFail("Current resident entry lost"); return "v2" }, load: { ("bad", 20) })
        XCTAssertEqual(cached, "new"); XCTAssertEqual(cache.statistics.joinedRequests, 0)
    }

    func testUnscopedPhotoEpochReauthorizesResidentAndRejectsOldFlight() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        var checks = 0
        for _ in 0..<2 {
            _ = try await cache.value(for: "p", scope: scope, presentationEpoch: "gallery-appearance1", reusePresentation: false,
                authorize: { checks += 1; return "v1" }, load: { ("resident", 20) })
        }
        XCTAssertEqual(checks, 2)
        let old = Task { try await cache.value(for: "p", scope: scope, presentationEpoch: "gallery-appearance1", reusePresentation: false,
            authorize: { await gate.wait(); return "v1" }, load: { ("old", 20) }) }
        while !gate.started { await Task.yield() }
        let fresh = try await cache.value(for: "p", scope: scope, presentationEpoch: "gallery-appearance2", reusePresentation: false,
            authorize: { checks += 1; return "v2" }, load: { ("fresh", 20) })
        gate.resume()
        do { _ = try await old.value; XCTFail("Gallery joined its old background authorization") } catch { }
        XCTAssertEqual(fresh, "fresh"); XCTAssertEqual(checks, 3)
        XCTAssertEqual(cache.entryCount, 1); XCTAssertEqual(cache.statistics.joinedRequests, 0)
    }

    func testConcurrentFeedAndGalleryRequestsDoNotCancelEachOther() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        let feed = Task { try await cache.value(for: "photo", scope: scope,
            presentationEpoch: "feed1", requestOwner: "feed",
            authorize: { await gate.wait(); return "v1" }, load: { ("pixels", 20) }) }
        while !gate.started { await Task.yield() }
        let gallery = try await cache.value(for: "photo", scope: scope,
            presentationEpoch: "gallery1", reusePresentation: false, requestOwner: "gallery",
            authorize: { "v1" }, load: { ("pixels", 20) })
        XCTAssertEqual(gallery, "pixels")
        gate.resume()
        let result = try await feed.value
        XCTAssertEqual(result, "pixels", "Opening gallery must not turn the underlying feed into a failed image")
        XCTAssertEqual(cache.entryCount, 1); XCTAssertEqual(cache.totalCost, 20)
        XCTAssertEqual(cache.statistics.joinedRequests, 0)
    }

    func testCancelingOnePhotoPresentationKeepsAnotherPresentationAlive() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), a = CacheTestSuspension(), b = CacheTestSuspension()
        let feed = Task { try await cache.value(for: "photo", scope: scope,
            presentationEpoch: "f", requestOwner: "feed", authorize: { await a.wait(); return "v1" }, load: { ("feed", 20) }) }
        let gallery = Task { try await cache.value(for: "photo", scope: scope,
            presentationEpoch: "g", reusePresentation: false, requestOwner: "gallery", authorize: { await b.wait(); return "v1" }, load: { ("gallery", 20) }) }
        while !a.started || !b.started { await Task.yield() }
        XCTAssertEqual(cache.inFlightCount, 2)
        cache.cancel(for: "photo", requestOwner: "gallery")
        XCTAssertEqual(cache.inFlightCount, 1)
        a.resume(); b.resume()
        let result = try await feed.value
        XCTAssertEqual(result, "feed")
        do { _ = try await gallery.value; XCTFail("Canceled presentation returned pixels") } catch { }
        XCTAssertEqual(cache.entryCount, 1); XCTAssertEqual(cache.inFlightCount, 0)
    }

    func testIndependentConcurrentMissesCountOneResidentCost() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), a = CacheTestSuspension(), b = CacheTestSuspension()
        let first = Task { try await cache.value(for: "p", scope: scope, requestOwner: "a",
            authorize: { "v1" }, load: { await a.wait(); return ("pixels", 20) }) }
        while !a.started { await Task.yield() }
        let second = Task { try await cache.value(for: "p", scope: scope, requestOwner: "b",
            authorize: { "v1" }, load: { await b.wait(); return ("pixels", 20) }) }
        while !b.started { await Task.yield() }
        a.resume(); let firstResult = try await first.value
        b.resume(); let secondResult = try await second.value
        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(cache.entryCount, 1); XCTAssertEqual(cache.totalCost, 20)
    }

    func testDeniedOwnerRevokesOtherOwnersLatePixelsAndPresentation() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        var revoked: [String] = []; cache.onResourceInvalidated = { revoked.append($0) }
        let old = Task { try await cache.value(for: "p", scope: scope, presentationEpoch: "feed", requestOwner: "feed",
            authorize: { "v1" }, load: { await gate.wait(); return ("forbidden", 20) }) }
        while !gate.started { await Task.yield() }
        do {
            _ = try await cache.value(for: "p", scope: scope, requestOwner: "gallery",
                authorize: { throw CacheTestError.denied }, load: { XCTFail("Denied load"); return ("bad", 20) })
            XCTFail("Denied owner accepted")
        } catch CacheTestError.denied { }
        gate.resume()
        do { _ = try await old.value; XCTFail("Revoked image resurrected") } catch { }
        XCTAssertEqual(cache.entryCount, 0); XCTAssertEqual(cache.totalCost, 0)
        XCTAssertEqual(cache.inFlightCount, 0); XCTAssertEqual(revoked, ["p"])
    }

    func testOlderSlowVersionCannotReplaceNewerResident() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        let old = Task { try await cache.value(for: "p", scope: scope, requestOwner: "a",
            authorize: { "v1" }, load: { await gate.wait(); return ("old", 20) }) }
        while !gate.started { await Task.yield() }
        let fresh = try await cache.value(for: "p", scope: scope, presentationEpoch: "current", requestOwner: "b",
            authorize: { "v2" }, load: { ("new", 30) })
        gate.resume()
        do { _ = try await old.value; XCTFail("Old version overwrote new") } catch SOOMMediaCacheError.supersededVersion { }
        let resident = try await cache.value(for: "p", scope: scope, presentationEpoch: "current", requestOwner: "c",
            authorize: { XCTFail("New resident was removed"); return "v2" }, load: { ("bad", 1) })
        XCTAssertEqual(fresh, resident); XCTAssertEqual(cache.totalCost, 30); XCTAssertEqual(cache.entryCount, 1)
    }

    func testOlderAuthorizationCannotReintroduceOutdatedVersion() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), gate = CacheTestSuspension()
        let old = Task { try await cache.value(for: "p", scope: scope, requestOwner: "a",
            authorize: { await gate.wait(); return "v1" }, load: { XCTFail("Outdated authorization downloaded"); return ("old", 20) }) }
        while !gate.started { await Task.yield() }
        _ = try await cache.value(for: "p", scope: scope, requestOwner: "b", authorize: { "v2" }, load: { ("new", 30) })
        gate.resume()
        do { _ = try await old.value; XCTFail("Older authorization won") } catch SOOMMediaCacheError.supersededVersion { }
        XCTAssertEqual(cache.totalCost, 30); XCTAssertEqual(cache.entryCount, 1)
    }

    func testGlobalInvalidationRejectsBothOwnersAndLateErrorsPreserveNewFlight() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), a = CacheTestSuspension(), b = CacheTestSuspension(), c = CacheTestSuspension()
        let first = Task { try await cache.value(for: "p", scope: scope, requestOwner: "a",
            authorize: { await a.wait(); throw CacheTestError.denied }, load: { ("bad", 20) }) }
        let second = Task { try await cache.value(for: "p", scope: scope, requestOwner: "b",
            authorize: { "v1" }, load: { await b.wait(); return ("old", 20) }) }
        while !a.started || !b.started { await Task.yield() }
        cache.invalidate()
        let current = Task { try await cache.value(for: "p", scope: scope, requestOwner: "a",
            authorize: { "v2" }, load: { await c.wait(); return ("new", 30) }) }
        while !c.started { await Task.yield() }
        a.resume(); b.resume()
        do { _ = try await first.value; XCTFail("Invalidated denied caller returned") } catch { }
        do { _ = try await second.value; XCTFail("Invalidated load returned") } catch { }
        XCTAssertEqual(cache.inFlightCount, 1, "Stale catches must not remove current flight")
        c.resume(); let value = try await current.value
        XCTAssertEqual(value, "new"); XCTAssertEqual(cache.totalCost, 30)
    }

    func testSameOwnerCanceledEpochCannotRevokeOtherOrReplacementEpoch() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), a = CacheTestSuspension(), b = CacheTestSuspension()
        var revoked = 0; cache.onResourceInvalidated = { _ in revoked += 1 }
        let old = Task { try await cache.value(for: "p", scope: scope, presentationEpoch: "old", requestOwner: "a",
            authorize: { await a.wait(); throw CacheTestError.denied }, load: { ("bad", 20) }) }
        while !a.started { await Task.yield() }
        let other = Task { try await cache.value(for: "p", scope: scope, requestOwner: "b",
            authorize: { "v2" }, load: { await b.wait(); return ("new", 30) }) }
        while !b.started { await Task.yield() }
        _ = try await cache.value(for: "p", scope: scope, presentationEpoch: "new", requestOwner: "a",
            authorize: { "v2" }, load: { ("new", 30) })
        a.resume()
        do { _ = try await old.value; XCTFail("Old epoch returned") } catch { }
        XCTAssertEqual(cache.inFlightCount, 1); XCTAssertEqual(revoked, 0)
        b.resume(); let value = try await other.value
        XCTAssertEqual(value, "new"); XCTAssertEqual(cache.totalCost, 30)
    }

    func testMissingVersionIndependentOwnersDownloadWithoutCachingOrSuperseding() async throws {
        let cache = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 4)
        let scope = cacheTestScope(), a = CacheTestSuspension(), b = CacheTestSuspension()
        let first = Task { try await cache.value(for: "p", scope: scope, presentationEpoch: "feed", requestOwner: "a",
            authorize: { nil }, load: { await a.wait(); return ("pixels-a", 20) }) }
        while !a.started { await Task.yield() }
        let second = Task { try await cache.value(for: "p", scope: scope, requestOwner: "b",
            authorize: { nil }, load: { await b.wait(); return ("pixels-b", 20) }) }
        while !b.started { await Task.yield() }
        a.resume(); let firstValue = try await first.value
        b.resume(); let secondValue = try await second.value
        XCTAssertEqual(firstValue, "pixels-a"); XCTAssertEqual(secondValue, "pixels-b")
        XCTAssertEqual(cache.entryCount, 0); XCTAssertEqual(cache.totalCost, 0); XCTAssertEqual(cache.inFlightCount, 0)
        var authorized = false, downloaded = false
        _ = try await cache.value(for: "p", scope: scope, presentationEpoch: "feed", requestOwner: "a",
            authorize: { authorized = true; return nil }, load: { downloaded = true; return ("fresh", 20) })
        XCTAssertTrue(authorized); XCTAssertTrue(downloaded); XCTAssertEqual(cache.entryCount, 0)
    }

    func testMountedPhotoClearsCallbackOnMemoryWarningAndBackground() async throws {
        let demo = ReviewDemoController.shared
        demo.start(); defer { demo.exit() }
        let runtime = try XCTUnwrap(demo.runtime), workoutID = UUID()
        ReviewDemoPhotoStore.shared.seed(workoutIDs: [workoutID])
        let references = try await ReviewDemoPhotoStore.shared.load(workoutID: workoutID, ownerID: ReviewDemoMode.userID)
        let photo = try XCTUnwrap(references.first)
        var lastImage: UIImage?, loaded = 0, cleared = 0
        let content = WorkoutPhotoImage(photo: photo, onImageLoaded: { image in
            lastImage = image
            if image == nil { cleared += 1 } else { loaded += 1 }
        }).environmentObject(runtime.auth)
            .environment(\.soomFeedPhotoPresentationID, UUID())
            .environment(\.soomFeedIsActive, false)
            .frame(width: 300, height: 200)
        let host = UIHostingController(rootView: AnyView(content))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<50 where lastImage == nil { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertNotNil(lastImage)
        let beforeMemory = cleared, revision = WorkoutPhotoImageCache.shared.invalidationRevision
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(lastImage); XCTAssertGreaterThan(cleared, beforeMemory)
        XCTAssertGreaterThan(WorkoutPhotoImageCache.shared.invalidationRevision, revision)
        for _ in 0..<50 where lastImage == nil { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertNotNil(lastImage)
        let beforeDenial = loaded
        WorkoutPhotoImageCache.shared.resourceInvalidations.send(photo.cacheKey)
        XCTAssertNil(lastImage)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(lastImage); XCTAssertEqual(loaded, beforeDenial, "Denial must not trigger an automatic reload")
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNil(lastImage)
        let backgroundLoads = loaded
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(lastImage); XCTAssertEqual(loaded, backgroundLoads)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<50 where lastImage == nil { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertNotNil(lastImage); XCTAssertGreaterThan(loaded, backgroundLoads)
        host.rootView = AnyView(Color.clear)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(lastImage, "Image callback recipient must release its copy when loader is removed")
    }

    func testResolutionVariantsKeepGallerySeparateAndReuseBoth() async throws {
        let c = SOOMValidatedMemoryCache<String, String>(maximumCost: 100, maximumCount: 12)
        let s = cacheTestScope(); var loads = 0
        for (variant, expected, cost) in [(Optional("feed"), "small", 10), (nil, "full", 40), (Optional("feed"), "small", 10), (nil, "full", 40)] {
            let value = try await c.value(for:"p", scope:s, presentationEpoch:"e", variant:variant,
                authorize:{ "v1" }, load:{ loads += 1; return (expected,cost) })
            XCTAssertEqual(value, expected)
        }
        XCTAssertEqual(loads,2); XCTAssertEqual(c.entryCount,2); XCTAssertEqual(c.totalCost,50)
    }
    func testResolutionVariantsShareOneGlobalLRUBudget() async throws {
        let c = SOOMValidatedMemoryCache<String,String>(maximumCost:30,maximumCount:2), s=cacheTestScope()
        for v in ["a","b","c"] { _ = try await c.value(for:"p",scope:s,variant:v,authorize:{"v1"},load:{(v,15)}) }
        XCTAssertEqual(c.entryCount,2); XCTAssertEqual(c.totalCost,30); XCTAssertEqual(c.statistics.evictions,1)
        c.invalidateResource("p"); XCTAssertEqual(c.entryCount,0); XCTAssertEqual(c.totalCost,0)
    }
    func testDenialRevokesEveryResolutionAndLateGallery() async throws {
        let c=SOOMValidatedMemoryCache<String,String>(maximumCost:100,maximumCount:12), s=cacheTestScope(), gate=CacheTestSuspension()
        _ = try await c.value(for:"p",scope:s,variant:"small",authorize:{"v1"},load:{("small",10)})
        let gallery=Task { try await c.value(for:"p",scope:s,requestOwner:"gallery",variant:nil,authorize:{"v1"},load:{await gate.wait();return("full",40)}) }
        while !gate.started { await Task.yield() }
        do { _ = try await c.value(for:"p",scope:s,requestOwner:"denied",variant:"medium",authorize:{throw CacheTestError.denied},load:{("bad",10)});XCTFail("Denied") } catch { }
        gate.resume(); do {_ = try await gallery.value;XCTFail("Late full pixels escaped")} catch { }
        XCTAssertEqual(c.entryCount,0);XCTAssertEqual(c.totalCost,0);XCTAssertEqual(c.inFlightCount,0)
    }
    func testChangedVersionDropsAllOldResolutions() async throws {
        let c=SOOMValidatedMemoryCache<String,String>(maximumCost:100,maximumCount:12), s=cacheTestScope()
        for v in ["small","large"] {_ = try await c.value(for:"p",scope:s,variant:v,authorize:{"v1"},load:{("old",20)})}
        let fresh=try await c.value(for:"p",scope:s,variant:"small",authorize:{"v2"},load:{("new",10)})
        XCTAssertEqual(fresh,"new");XCTAssertEqual(c.entryCount,1);XCTAssertEqual(c.totalCost,10)
        var loaded=false
        let large=try await c.value(for:"p",scope:s,variant:"large",authorize:{"v2"},load:{loaded=true;return("full-new",40)})
        XCTAssertTrue(loaded);XCTAssertEqual(large,"full-new")
    }
    func testAccountChangeRemovesEveryResolution() async throws {
        let c=SOOMValidatedMemoryCache<String,String>(maximumCost:100,maximumCount:12), first=cacheTestScope()
        for v in ["small","large"] {_ = try await c.value(for:"p",scope:first,variant:v,authorize:{"v1"},load:{("old",20)})}
        _ = try await c.value(for:"q",scope:cacheTestScope(),variant:"small",authorize:{"v1"},load:{("new",10)})
        XCTAssertEqual(c.entryCount,1);XCTAssertEqual(c.totalCost,10)
        c.invalidate();XCTAssertEqual(c.entryCount,0);XCTAssertEqual(c.totalCost,0)
    }
    func testSameOwnerDifferentResolutionCannotJoinWrongFlight() async throws {
        let c=SOOMValidatedMemoryCache<String,String>(maximumCost:100,maximumCount:12),s=cacheTestScope(),gate=CacheTestSuspension()
        let first=Task {try await c.value(for:"p",scope:s,presentationEpoch:"same",requestOwner:"owner",variant:"small",authorize:{"v1"},load:{await gate.wait();return("small",10)})}
        while !gate.started {await Task.yield()}
        let full=try await c.value(for:"p",scope:s,presentationEpoch:"same",requestOwner:"owner",variant:nil,authorize:{"v1"},load:{("full",40)})
        gate.resume();do{_ = try await first.value;XCTFail("Superseded size returned")}catch{}
        XCTAssertEqual(full,"full");XCTAssertEqual(c.totalCost,40)
    }
    func testChangedVersionRejectsOtherResolutionOldDecode() async throws {
        let c=SOOMValidatedMemoryCache<String,String>(maximumCost:100,maximumCount:12),s=cacheTestScope(),gate=CacheTestSuspension()
        let first=Task {try await c.value(for:"p",scope:s,requestOwner:"old",variant:"large",authorize:{"v1"},load:{await gate.wait();return("old",40)})}
        while !gate.started {await Task.yield()}
        _ = try await c.value(for:"p",scope:s,requestOwner:"new",variant:"small",authorize:{"v2"},load:{("new",10)})
        gate.resume();do{_ = try await first.value;XCTFail("Old variant returned")}catch{}
        XCTAssertEqual(c.totalCost,10);XCTAssertEqual(c.entryCount,1)
    }
    func testDisplayDecodeBoundsRemainSharpAndGalleryIsUnchanged() {
        let size=WorkoutPhotoDecodeSize.feed(maximumWidth:346,height:260,displayScale:3)!
        let pixels=size.maximumPixelSize(sourceWidth:2048,sourceHeight:1536,orientation:1)
        XCTAssertGreaterThanOrEqual(pixels,1040);XCTAssertLessThanOrEqual(pixels,1152)
        for n: CGFloat in [.nan,.infinity,0,-1] {XCTAssertNil(WorkoutPhotoDecodeSize.feed(maximumWidth:n,height:260,displayScale:3))}
        XCTAssertNotEqual(size.cacheVariant,WorkoutPhotoDecodeSize.feed(maximumWidth:346,height:260,displayScale:2)?.cacheVariant)
        XCTAssertLessThanOrEqual(size.maximumPixelSize(sourceWidth:50000,sourceHeight:1,orientation:1),2048)
        XCTAssertLessThanOrEqual(size.maximumPixelSize(sourceWidth:1,sourceHeight:50000,orientation:6),2048)
    }
    func testExtremePortraitDecodeMeetsExisting145PointMinimum() {
        let size=WorkoutPhotoDecodeSize.feed(maximumWidth:346,height:260,displayScale:3)!
        let pixels=size.maximumPixelSize(sourceWidth:1000,sourceHeight:4000,orientation:1)
        XCTAssertGreaterThanOrEqual(Double(pixels) / 4,145*3)
        let rotated=size.maximumPixelSize(sourceWidth:4000,sourceHeight:1000,orientation:6)
        XCTAssertEqual(pixels,rotated)
    }
    func testVersionChangeNotifiesOtherPresentationsButPreservesFreshCaller() async throws {
        let c=SOOMValidatedMemoryCache<String,String>(maximumCost:100,maximumCount:12),s=cacheTestScope()
        var changes:[String?]=[],denials=0
        c.onResourceVersionChanged = { key,owner in XCTAssertEqual(key,"p");changes.append(owner) }
        c.onResourceInvalidated = {_ in denials += 1}
        _ = try await c.value(for:"p",scope:s,requestOwner:"feed",variant:"small",authorize:{"v1"},load:{("small",10)})
        let fresh=try await c.value(for:"p",scope:s,requestOwner:"gallery",variant:nil,authorize:{"v2"},load:{("full",40)})
        XCTAssertEqual(fresh,"full");XCTAssertEqual(changes,["gallery"]);XCTAssertEqual(denials,0)
        XCTAssertEqual(c.entryCount,1)
    }
    func testFeedDecoderFourLargePhotosFitBudgetWhileGalleryStaysFullSize() async throws {
        let context = try XCTUnwrap(CGContext(data:nil,width:2048,height:1536,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red:0.2,green:0.5,blue:0.8,alpha:1));context.fill(CGRect(x:0,y:0,width:2048,height:1536))
        let bytes=NSMutableData(),destination=try XCTUnwrap(CGImageDestinationCreateWithData(bytes,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,try XCTUnwrap(context.makeImage()),nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        let size=try XCTUnwrap(WorkoutPhotoDecodeSize.feed(maximumWidth:346,height:260,displayScale:3))
        let thumbnailResult=await WorkoutPhotoImageDecoder.decode(bytes as Data,size:size)
        let galleryResult=await WorkoutPhotoImageDecoder.decode(bytes as Data)
        let thumbnail=try XCTUnwrap(thumbnailResult),gallery=try XCTUnwrap(galleryResult)
        XCTAssertEqual(gallery.width,2048);XCTAssertGreaterThanOrEqual(thumbnail.width,1040)
        XCTAssertLessThan(thumbnail.bytesPerRow*thumbnail.height*4,32*1024*1024)
        XCTAssertGreaterThan(gallery.bytesPerRow*gallery.height*4,32*1024*1024)
        print("SYNTHETIC_IMAGE_METRICS feed=\(thumbnail.width)x\(thumbnail.height) bytes=\(thumbnail.bytesPerRow*thumbnail.height) gallery=\(gallery.width)x\(gallery.height) bytes=\(gallery.bytesPerRow*gallery.height)")
    }
    func testStaleBatchFenceCancellationCannotRevokeFreshGalleryVariant() async throws {
        let c=SOOMValidatedMemoryCache<String,String>(maximumCost:100,maximumCount:12),s=cacheTestScope(),oldGate=CacheTestSuspension(),newGate=CacheTestSuspension()
        var revoked=0;c.onResourceInvalidated={_ in revoked += 1}
        let old=Task { try await c.value(for:"p",scope:s,requestOwner:"old-feed",variant:"small",authorize:{await oldGate.wait();throw CancellationError()},load:{("old",10)}) }
        while !oldGate.started {await Task.yield()}
        let fresh=Task { try await c.value(for:"p",scope:s,requestOwner:"gallery",variant:nil,authorize:{"v2"},load:{await newGate.wait();return("fresh",40)}) }
        while !newGate.started {await Task.yield()}
        oldGate.resume();do{_ = try await old.value;XCTFail("Stale receipt returned")}catch{}
        XCTAssertEqual(revoked,0);XCTAssertEqual(c.inFlightCount,1)
        newGate.resume();let value=try await fresh.value;XCTAssertEqual(value,"fresh");XCTAssertEqual(c.totalCost,40)
    }
    func testPortraitEXIFDecodeHasEnoughPixelsForUnchangedMinimumTileWidth() async throws {
        let context=try XCTUnwrap(CGContext(data:nil,width:4000,height:1000,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        let bytes=NSMutableData(),destination=try XCTUnwrap(CGImageDestinationCreateWithData(bytes,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,try XCTUnwrap(context.makeImage()),[kCGImagePropertyOrientation:6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result=await WorkoutPhotoImageDecoder.decode(bytes as Data,size:WorkoutPhotoDecodeSize.feed(maximumWidth:346,height:260,displayScale:3))
        let image=try XCTUnwrap(result)
        XCTAssertGreaterThan(image.height,image.width)
        XCTAssertGreaterThanOrEqual(image.width,435)
        XCTAssertLessThanOrEqual(image.height,2048)
    }

    private func cacheTestScope(viewer: UUID = UUID(), generation: Int = 1, revision: Int = 0) -> SOOMMediaCacheScope {
        SOOMMediaCacheScope(viewerID: viewer, accountGeneration: generation, safetyRevision: revision)
    }

}

private enum CacheTestError: Error { case denied, decode }
@MainActor
private final class CacheTestSuspension {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; started = true
        }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
final class WorkoutEmptyMediaLayoutTests: XCTestCase {
    func testConfirmedEmptyMediaCollapsesWhileActualPhotoAndRouteKeepTheirRegion() async throws {
        let controller=ReviewDemoController.shared;controller.start();defer {controller.exit()}
        let runtime=try XCTUnwrap(controller.runtime)
        for hasRoute in [false,true] {
            let row=WorkoutPhotoMediaRow(workoutID:UUID(),photos:[],hasRoute:hasRoute) { Color.purple }
                .environmentObject(runtime.auth)
            let view=VStack(spacing:0) { row; Color.green.frame(height:20).accessibilityIdentifier("media.after") }
                .frame(width:393)
            let host=UIHostingController(rootView:view);host.safeAreaRegions=[]
            let window=UIWindow(frame:CGRect(x:0,y:0,width:393,height:400));window.rootViewController=host;window.isHidden=false
            defer {window.isHidden=true;window.rootViewController=nil}
            for _ in 0..<20 {host.view.layoutIfNeeded();try await Task.sleep(for:.milliseconds(30))}
            func pager(_ view:UIView)->UIScrollView? {
                if let scroll=view as? UIScrollView,scroll.accessibilityIdentifier=="workout.media.pager" {return scroll}
                return view.subviews.lazy.compactMap {pager($0)}.first
            }
            if hasRoute {XCTAssertEqual(try XCTUnwrap(pager(host.view)).bounds.height,260,accuracy:1)}
            else {XCTAssertNil(pager(host.view));XCTAssertLessThanOrEqual(host.sizeThatFits(in:CGSize(width:393,height:400)).height,21)}
        }
    }
}


extension WorkoutPhotosTests {
    func testR2EmptyPhotoRemountHeightPerformance() async throws {
        let suite = "R2-empty-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(store: AuthSessionStore(userDefaults: defaults)), id = UUID()
        WorkoutCardPerformanceProbe.start(); defer { WorkoutCardPerformanceProbe.stop() }
        for visit in 0..<3 {
            let row = VStack(spacing: 0) {
                WorkoutPhotoMediaRow(workoutID: id, photos: [], hasRoute: false, metadataLoader: { _ in
                    WorkoutCardPerformanceProbe.hit("photoMetadata")
                    try await Task.sleep(for: .milliseconds(150)); return []
                }) { Color.clear }
                Color.red.frame(height: 10)
            }.environmentObject(auth)
            let host = UIHostingController(rootView: row); host.safeAreaRegions = []
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852)); window.rootViewController = host; window.isHidden = false
            host.view.frame = window.bounds; window.layoutIfNeeded()
            let initial = host.sizeThatFits(in: CGSize(width: 393, height: 2000)).height
            try await Task.sleep(for: .milliseconds(220)); host.view.layoutIfNeeded()
            let final = host.sizeThatFits(in: CGSize(width: 393, height: 2000)).height
            print("SOOM_R2_EMPTY visit=\(visit) initial_height=\(initial) final_height=\(final) counts=\(WorkoutCardPerformanceProbe.counts)")
            window.isHidden = true; window.rootViewController = nil
        }
    }
}


extension WorkoutPhotosTests {
    func testR2PhotoHintsRemainBoundedAndNeverCrossAccounts() {
        let hints = WorkoutPhotoLayoutHints(capacity: 2), a = UUID(), b = UUID(), workout = UUID()
        func key(_ owner: UUID, _ id: UUID, generation: Int = 1) -> WorkoutPhotoLoadIdentity {
            .init(ownerID: owner, accountGeneration: generation, workoutID: id, revision: 0, photoPaths: [])
        }
        hints.record(false, for: key(a, workout)); XCTAssertEqual(hints.hasPhotos(for: key(a, workout)), false)
        XCTAssertNil(hints.hasPhotos(for: key(b, workout)))
        hints.record(true, for: key(b, workout)); XCTAssertNil(hints.hasPhotos(for: key(b, workout, generation: 2)))
        hints.record(false, for: key(a, workout)); hints.record(true, for: key(a, UUID())); hints.record(true, for: key(a, UUID()))
        XCTAssertEqual(hints.count, 2); XCTAssertNil(hints.hasPhotos(for: key(a, workout)))
        hints.clear(); XCTAssertEqual(hints.count, 0)
    }
    func testR2MountedPhotosRefreshOnForegroundMutationAndKnownEmpty() async throws {
        let suite = "R2-fresh-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(store: AuthSessionStore(userDefaults: defaults)), id = UUID()
        let ref = WorkoutPhotoReference(id: UUID(), storagePath: WorkoutPhotoPolicy.path(ownerID: UUID(), postID: UUID(), photoID: UUID()))
        var response: [WorkoutPhotoReference] = [], reads = 0
        var failure = false
        func root(phase: ScenePhase = .active, known: Bool = false, photos: [WorkoutPhotoReference] = []) -> AnyView {
            AnyView(VStack(spacing: 0) {
                WorkoutPhotoMediaRow(workoutID: id, photos: photos, photosAreKnown: known, metadataLoader: { _ in
                    reads += 1; try await Task.sleep(for: .milliseconds(40))
                    if failure { throw WorkoutPhotoError.uploadUnavailable }
                    return response
                }) { Color.clear }
                Color.red.frame(height: 10)
            }.environmentObject(auth).environment(\.scenePhase, phase))
        }
        let host = UIHostingController(rootView: root()); host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0,y: 0,width: 393,height: 852)); window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        func settle() async throws { window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(100)); host.view.layoutIfNeeded() }
        func height() -> CGFloat { host.sizeThatFits(in: CGSize(width: 393,height: 2000)).height }
        try await settle(); XCTAssertEqual(height(), 10, accuracy: 1)
        let initial = reads
        host.rootView = root(phase: .inactive); try await settle()
        response = [ref]; host.rootView = root(phase: .active); try await settle()
        XCTAssertGreaterThan(reads, initial); XCTAssertEqual(height(), 270, accuracy: 1, "External addition must appear despite an empty layout hint")
        response = []; NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil); try await settle()
        XCTAssertEqual(height(), 10, accuracy: 1)
        failure = true; NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil); try await settle()
        XCTAssertGreaterThanOrEqual(height(), 54, "Failed metadata is retry UI, not confirmed empty")
        failure = false; response = [ref]; NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil); try await settle()
        XCTAssertEqual(height(), 270, accuracy: 1)
        let beforeKnown = reads
        host.rootView = root(known: true); try await settle(); XCTAssertEqual(height(), 10, accuracy: 1)
        host.rootView = root(known: true, photos: [ref]); try await settle(); XCTAssertEqual(height(), 270, accuracy: 1)
        host.rootView = root(known: true); try await settle(); XCTAssertEqual(height(), 10, accuracy: 1)
        XCTAssertEqual(reads, beforeKnown, "Already-authorized feed metadata, including empty, needs no duplicate own-workout request")
    }
}

@MainActor
final class ProfilePhotoReadContractTests: XCTestCase {
    private let viewer = UUID(), owner = UUID(), card = UUID(), canonical = UUID(), source = UUID(), photo = UUID()
    private func envelope(_ changes: [String: Any] = [:], rows: [[String: Any]]? = nil) throws -> AccountActivityProfilePhotoEnvelope {
        var json: [String: Any] = ["version":2,"viewer_id":viewer.uuidString,"owner_id":owner.uuidString,
            "card_id":card.uuidString,"canonical_id":canonical.uuidString,"projection_revision":7,
            "profile_revision":3,"backing":"legacy","source_id":source.uuidString,"bucket":"workout-photos",
            "release_ready":true,"rows":rows ?? [["id":photo.uuidString,"card_id":card.uuidString,
                "storage_path":WorkoutPhotoPolicy.path(ownerID:owner,postID:source,photoID:photo),"sort_order":0]]]
        json.merge(changes) { _, new in new }
        return try JSONDecoder().decode(AccountActivityProfilePhotoEnvelope.self, from:JSONSerialization.data(withJSONObject:json))
    }
    private func validate(_ value: AccountActivityProfilePhotoEnvelope) throws -> [WorkoutPhotoReference] {
        try value.validated(viewerID:viewer,cardID:card,ownerID:owner,canonicalID:canonical,revision:7)
    }
    private var projection: AccountActivityFeedRow {
        .init(cardID: card, canonicalID: canonical, ownerID: owner, sport: "running",
            activityAt: "2026-11-14T00:00:00Z", durationSeconds: 1800, distanceMeters: 5000,
            revision: 7, readPolicy: .profileOnlyV2)
    }
    func testProfilePhotoReadRejectsLateAccountContextAndCancellation() async throws {
        var current = AccountActivityInteractionContext(viewerID: viewer, generation: 1, safetyRevision: 1,
            storageScopeID: viewer.uuidString.lowercased())
        let response = try envelope()
        let adapter = AccountActivityProfilePhotoAdapter(read: { _ in
            current = .init(viewerID: self.viewer, generation: 2, safetyRevision: 1,
                storageScopeID: self.viewer.uuidString.lowercased())
            return response
        }, context: { current })
        do { _ = try await adapter.load(row: projection); XCTFail("late context must not commit") } catch {}
        var reads = 0
        let cancelled = AccountActivityProfilePhotoAdapter(read: { _ in reads += 1; return response }, context: { current })
        let task = Task { @MainActor in
            try Task.checkCancellation()
            return try await cancelled.load(row: self.projection)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled read must not commit") } catch {}
        XCTAssertEqual(reads, 0)
    }
    func testLegacyPhotosRetainOriginalIdentityWithoutDetailSnapshot() throws {
        let result = try validate(envelope())
        XCTAssertEqual(result.count,1); XCTAssertEqual(result[0].id,photo)
        XCTAssertEqual(result[0].bucket,"workout-photos"); XCTAssertNil(result[0].nativeCardID)
        XCTAssertEqual(result[0].profileAuthority?.sourceID,source)
    }
    func testProfilePhotoRejectsIdentityRevisionAndBackingMismatch() throws {
        for patch: [String:Any] in [["viewer_id":UUID().uuidString],["owner_id":UUID().uuidString],
            ["card_id":UUID().uuidString],["canonical_id":UUID().uuidString],["projection_revision":8],
            ["profile_revision":0],["release_ready":false],["backing":"unknown"],
            ["bucket":"public"],["backing":"native","bucket":"activity-photos-candidate"]] {
            XCTAssertThrowsError(try validate(envelope(patch)))
        }
    }
    func testProfilePhotoRejectsCanonicalMismatchDespiteOtherwiseMatchingAuthority() throws {
        // Batch photo envelopes use this same validator before publishing cached pixels.
        let valid = try envelope()
        XCTAssertEqual(try validate(valid).count, 1)
        let mismatched = try envelope(["canonical_id": UUID().uuidString])
        XCTAssertEqual(mismatched.card_id, valid.card_id)
        XCTAssertEqual(mismatched.owner_id, valid.owner_id)
        XCTAssertEqual(mismatched.source_id, valid.source_id)
        XCTAssertThrowsError(try validate(mismatched))
    }
    func testProfilePhotoRejectsWrongPathDuplicateOrderAndOversizedList() throws {
        let row: [String:Any] = ["id":photo.uuidString,"card_id":card.uuidString,
            "storage_path":WorkoutPhotoPolicy.path(ownerID:owner,postID:source,photoID:photo),"sort_order":0]
        for patch: [String:Any] in [["storage_path":"https://example.org/image.jpg"],
            ["card_id":UUID().uuidString],["sort_order":1]] {
            XCTAssertThrowsError(try validate(envelope(rows:[row.merging(patch){_,new in new}])))
        }
        XCTAssertThrowsError(try validate(envelope(rows:[row,row])))
        XCTAssertThrowsError(try validate(envelope(rows:Array(repeating:row,count:7))))
    }
    func testNativeProfilePhotoUsesExactCardPathAndBucket() throws {
        let value = try envelope(["backing":"native","source_id":card.uuidString,"bucket":"activity-photos-candidate"],
            rows:[["id":photo.uuidString,"card_id":card.uuidString,
                "storage_path":WorkoutPhotoPolicy.path(ownerID:owner,postID:card,photoID:photo),"sort_order":0]])
        let result = try validate(value)
        XCTAssertEqual(result.first?.nativeCardID,card)
        XCTAssertEqual(result.first?.bucket,"activity-photos-candidate")
    }
}
