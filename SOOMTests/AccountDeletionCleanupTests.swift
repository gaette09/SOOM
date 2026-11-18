import SwiftUI
import UIKit
import Foundation
import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class AccountDeletionCleanupTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let directory: URL
        let marker: URL
        let accounts: URL
        let defaults: UserDefaults
        func scope(_ id: UUID) -> URL { accounts.appendingPathComponent(id.uuidString.lowercased()) }
        func coordinator(removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
                         writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) -> AccountDeletionCleanupCoordinator {
            AccountDeletionCleanupCoordinator(markerURL: marker, accountsDirectory: accounts,
                defaults: defaults, removeItem: removeItem, writeData: writeData)
        }
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SOOM-Cleanup-Synthetic-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "SOOM-Cleanup-Synthetic-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return Fixture(directory: directory, marker: directory.appendingPathComponent("cleanup.json"),
            accounts: directory.appendingPathComponent("HealthAccounts"), defaults: defaults)
    }

    private func writeSynthetic(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic private fixture".utf8).write(to: url)
    }

    func testIntentIsDurableBeforeDeletionAndContainsOnlyUUIDAndPhase() throws {
        let f = try fixture(), owner = UUID()
        let subject = f.coordinator()
        try subject.begin(userID: owner)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.marker)) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["userID", "phase"])
        let reopened = f.coordinator()
        XCTAssertTrue(reopened.prepareBeforeOpeningStorage())
        XCTAssertEqual(reopened.marker, .init(userID: owner, phase: .awaitingServerConfirmation))
        XCTAssertTrue(reopened.blocksAppAccess)
    }

    func testUnknownRemoteOutcomeNeverAutomaticallyErasesAndCannotComplete() throws {
        let f = try fixture(), owner = UUID()
        let healthFile = f.scope(owner).appendingPathComponent("health.store")
        try writeSynthetic(healthFile)
        let first = f.coordinator()
        try first.begin(userID: owner)
        let reopened = f.coordinator()
        XCTAssertTrue(reopened.prepareBeforeOpeningStorage())
        XCTAssertTrue(FileManager.default.fileExists(atPath: healthFile.path))
        XCTAssertThrowsError(try reopened.complete(userID: owner))
        reopened.preserveAndContinue()
        XCTAssertFalse(reopened.blocksAppAccess)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.marker.path))
        let nextLaunch = f.coordinator()
        XCTAssertTrue(nextLaunch.prepareBeforeOpeningStorage())
        XCTAssertTrue(nextLaunch.blocksAppAccess)
    }

    func testConfirmedDeletionResumesBeforeOpeningStoresAndPreservesOtherAccountAndGuest() throws {
        let f = try fixture(), a = UUID(), b = UUID()
        for name in ["health.store", "health.store-wal", "feed_share_drafts.json", "active-workout.json"] {
            try writeSynthetic(f.scope(a).appendingPathComponent(name))
        }
        let bFile = f.scope(b).appendingPathComponent("health.store")
        let guestFile = f.accounts.appendingPathComponent("guest/active-workout.json")
        try writeSynthetic(bFile)
        try writeSynthetic(guestFile)
        TrainingSettingsStore(userDefaults: f.defaults, userID: a).saveMaxHeartRate(180)
        TrainingSettingsStore(userDefaults: f.defaults, userID: b).saveMaxHeartRate(190)
        TrainingSettingsStore(userDefaults: f.defaults).saveMaxHeartRate(170)
        f.defaults.set(Data([1]), forKey: "soom.club.local.persistence.v1." + a.uuidString.lowercased())
        f.defaults.set("synthetic", forKey: "soom.morningCheckIn.skippedDate." + a.uuidString.lowercased())
        f.defaults.set("Synthetic A", forKey: "auth.profileDisplayName." + a.uuidString.lowercased())
        f.defaults.set("Synthetic B", forKey: "auth.profileDisplayName." + b.uuidString.lowercased())
        let first = f.coordinator()
        try first.begin(userID: a)
        try first.confirmServerDeletion(userID: a)
        let reopened = f.coordinator()
        XCTAssertTrue(reopened.prepareBeforeOpeningStorage())
        XCTAssertNil(reopened.marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.scope(a).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestFile.path))
        XCTAssertFalse(TrainingSettingsStore(userDefaults: f.defaults, userID: a).hasAnySavedTrainingSetting())
        XCTAssertEqual(TrainingSettingsStore(userDefaults: f.defaults, userID: b).loadZoneBaseline().maxHeartRate, 190)
        XCTAssertEqual(TrainingSettingsStore(userDefaults: f.defaults).loadZoneBaseline().maxHeartRate, 170)
        XCTAssertNil(f.defaults.object(forKey: "soom.club.local.persistence.v1." + a.uuidString.lowercased()))
        XCTAssertNil(f.defaults.object(forKey: "soom.morningCheckIn.skippedDate." + a.uuidString.lowercased()))
        XCTAssertNil(f.defaults.object(forKey: "auth.profileDisplayName." + a.uuidString.lowercased()))
        XCTAssertEqual(f.defaults.string(forKey: "auth.profileDisplayName." + b.uuidString.lowercased()), "Synthetic B")
    }

    func testFailedDiskCleanupRetainsConfirmedMarkerForAnotherLaunch() throws {
        let f = try fixture(), owner = UUID()
        try writeSynthetic(f.scope(owner).appendingPathComponent("health.store"))
        let first = f.coordinator()
        try first.begin(userID: owner)
        try first.confirmServerDeletion(userID: owner)
        let failing = f.coordinator(removeItem: { _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertFalse(failing.prepareBeforeOpeningStorage())
        XCTAssertNotNil(failing.errorMessage)
        XCTAssertEqual(failing.marker?.phase, .serverConfirmed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.marker.path))
        let retry = f.coordinator()
        XCTAssertTrue(retry.prepareBeforeOpeningStorage())
        XCTAssertNil(retry.marker)
    }

    func testIntentWriteFailurePreventsADeletionAttemptFromBeingAuthorized() throws {
        let f = try fixture()
        let subject = f.coordinator(writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertThrowsError(try subject.begin(userID: UUID()))
        XCTAssertNil(subject.marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.marker.path))
    }

    func testConfirmationWriteFailureRestartsAsUnknownAndPreservesData() throws {
        let f = try fixture(), owner = UUID()
        let file = f.scope(owner).appendingPathComponent("health.store")
        try writeSynthetic(file)
        let subject = f.coordinator(writeData: { data, url in
            if String(decoding: data, as: UTF8.self).contains("serverConfirmed") { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        })
        try subject.begin(userID: owner)
        XCTAssertThrowsError(try subject.confirmServerDeletion(userID: owner))
        let reopened = f.coordinator()
        XCTAssertTrue(reopened.prepareBeforeOpeningStorage())
        XCTAssertEqual(reopened.marker?.phase, .awaitingServerConfirmation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testExplicitLocalOnlyChoiceIsDurableWithoutClaimingRemoteSuccess() throws {
        let f = try fixture(), owner = UUID()
        try writeSynthetic(f.scope(owner).appendingPathComponent("active-workout.json"))
        let subject = f.coordinator()
        try subject.begin(userID: owner)
        try subject.approveLocalRemoval(userID: owner)
        XCTAssertEqual(subject.marker?.phase, .localRemovalApproved)
        let reopened = f.coordinator()
        XCTAssertTrue(reopened.prepareBeforeOpeningStorage())
        XCTAssertNil(reopened.marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.scope(owner).path))
    }

    func testMalformedMarkerBlocksStartupWithoutGuessingAnAccountOrDeletingData() throws {
        let f = try fixture(), owner = UUID()
        let file = f.scope(owner).appendingPathComponent("health.store")
        try writeSynthetic(file)
        try Data("{\"userID\":\"../guest\",\"phase\":\"serverConfirmed\"}".utf8).write(to: f.marker)
        let subject = f.coordinator()
        XCTAssertFalse(subject.prepareBeforeOpeningStorage())
        XCTAssertNotNil(subject.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.marker.path))
    }

    func testPendingTargetCannotBeReplacedOrConfirmedAsAnotherAccount() throws {
        let f = try fixture(), a = UUID(), b = UUID()
        let subject = f.coordinator()
        try subject.begin(userID: a)
        XCTAssertThrowsError(try subject.begin(userID: b))
        XCTAssertThrowsError(try subject.confirmServerDeletion(userID: b))
        XCTAssertThrowsError(try subject.approveLocalRemoval(userID: b))
        XCTAssertEqual(subject.marker?.userID, a)
    }

    func testOnlyConfirmedRemoteDeletionRetiresLateWritersAndCompletionKeepsFence() throws {
        let f = try fixture(), owner = UUID()
        let subject = f.coordinator()
        try subject.begin(userID: owner)
        XCTAssertFalse(AccountDeletionWriteFence.shared.isRetired(owner))
        try subject.confirmServerDeletion(userID: owner)
        XCTAssertTrue(AccountDeletionWriteFence.shared.isRetired(owner))
        try subject.complete(userID: owner)
        XCTAssertNil(subject.marker)
        XCTAssertTrue(AccountDeletionWriteFence.shared.isRetired(owner))
        let another = UUID()
        try subject.begin(userID: another)
        try subject.approveLocalRemoval(userID: another)
        XCTAssertFalse(AccountDeletionWriteFence.shared.isRetired(another))
    }

    func testFileMutationFenceSerializesRetirementAndRejectsLateWrites() async throws {
        let fence = AccountDeletionWriteFence(), owner = UUID()
        let writeStarted = expectation(description: "write is inside fence")
        let retireStarted = expectation(description: "retire requested")
        let releaseWrite = DispatchSemaphore(value: 0)
        let retireFinished = DispatchSemaphore(value: 0)
        let writer = Task.detached {
            try fence.withActiveScope(owner) {
                writeStarted.fulfill()
                _ = releaseWrite.wait(timeout: .now() + 2)
                return 42
            }
        }
        await fulfillment(of: [writeStarted], timeout: 2)
        let retirement = Task.detached {
            retireStarted.fulfill()
            fence.retire(owner)
            retireFinished.signal()
        }
        await fulfillment(of: [retireStarted], timeout: 2)
        XCTAssertEqual(retireFinished.wait(timeout: .now() + 0.02), .timedOut)
        releaseWrite.signal()
        let value = try await writer.value
        XCTAssertEqual(value, 42)
        await retirement.value
        XCTAssertThrowsError(try fence.withActiveScope(owner) { "late write" })
        XCTAssertEqual(try fence.withActiveScope(UUID()) { "other account" }, "other account")
        XCTAssertEqual(try fence.withActiveScope(nil) { "guest" }, "guest")
    }

    func testMountedCleanupErasesOnlyTargetModelsAndKeepsOpenDatabaseFiles() throws {
        let f = try fixture(), a = UUID(), b = UUID()
        let storage = try HealthAccountStorageController(baseDirectory: f.accounts, inMemory: true,
            monitorNetwork: false, automaticallySync: false)
        try storage.switchAccount(userID: a)
        storage.container.mainContext.insert(CheckInRecord(date: Date(), fatigueLevel: 2, sleepQuality: 3, muscleSoreness: 2, moodLevel: 4))
        try storage.container.mainContext.save()
        try storage.switchAccount(userID: b)
        storage.container.mainContext.insert(CheckInRecord(date: Date(), fatigueLevel: 1, sleepQuality: 4, muscleSoreness: 1, moodLevel: 4))
        try storage.container.mainContext.save()
        let placeholderDB = f.scope(a).appendingPathComponent("health.store")
        let draft = f.scope(a).appendingPathComponent("feed_share_drafts.json")
        try writeSynthetic(placeholderDB)
        try writeSynthetic(draft)
        let journals = ["native-comment-pending-v1.json", "native-photo-pending-v1.json"]
        for name in journals {
            try writeSynthetic(f.scope(a).appendingPathComponent(name))
            try writeSynthetic(f.scope(b).appendingPathComponent(name))
        }
        let subject = f.coordinator()
        try subject.begin(userID: a)
        try subject.approveLocalRemoval(userID: a)
        subject.eraseMountedScope(using: storage)
        XCTAssertNil(subject.marker)
        XCTAssertEqual(storage.userID, b)
        XCTAssertEqual(try storage.container.mainContext.fetchCount(FetchDescriptor<CheckInRecord>()), 1)
        try storage.switchAccount(userID: a)
        XCTAssertEqual(try storage.container.mainContext.fetchCount(FetchDescriptor<CheckInRecord>()), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: placeholderDB.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        for name in journals {
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.scope(a).appendingPathComponent(name).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.scope(b).appendingPathComponent(name).path))
        }
    }
    func testNativeJournalEraseFailureKeepsDeletionMarkerForRetry() throws {
        let f = try fixture(), owner = UUID()
        let journal = f.scope(owner).appendingPathComponent("native-comment-pending-v1.json")
        try writeSynthetic(journal)
        let subject = f.coordinator(removeItem: { url in
            if url.lastPathComponent == journal.lastPathComponent { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
        try subject.begin(userID: owner)
        try subject.approveLocalRemoval(userID: owner)
        XCTAssertThrowsError(try subject.complete(userID: owner))
        XCTAssertNotNil(subject.marker)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        let retry = f.coordinator()
        XCTAssertTrue(retry.prepareBeforeOpeningStorage())
        XCTAssertNil(retry.marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }
}


@MainActor
final class FullAppLocalizedVisualTests: XCTestCase {
    func testDeletionExactConfirmationRemainsStrict() {
        XCTAssertTrue(AccountDeletionConfirmationSheet.acceptsConfirmation("삭제"))
        for input in ["", "삭제 ", " 삭제", "삭제\n", "delete", "삭제삭제"] {
            XCTAssertFalse(AccountDeletionConfirmationSheet.acceptsConfirmation(input))
        }
    }

    func testNativeDeletionAndFinishedGridAtSmallAndMaximumTextLightDark() async throws {
        // Native component renders, not original-root integration or actual deletion/save proof.
        for width: CGFloat in [320, 402] {
            for large in [false, true] {
                for dark in [false, true] {
                    let size: DynamicTypeSize = large ? .accessibility5 : .large
                    let deletion = AccountDeletionConfirmationSheet(isGuestUser: false, reviewConfirmationText: "삭제 ", onConfirm: {})
                        .environment(\.dynamicTypeSize, size).environment(\.colorScheme, dark ? .dark : .light)
                    try await snapshot(deletion, width: width, height: 568,
                        name: "F native deletion trailing space DISABLED NO destructive callback \(width) max\(large) dark\(dark)")
                    let enabled = AccountDeletionConfirmationSheet(isGuestUser: false, reviewConfirmationText: "삭제", onConfirm: {})
                        .environment(\.dynamicTypeSize, size).environment(\.colorScheme, dark ? .dark : .light)
                    try await snapshot(enabled, width: width, height: 568,
                        name: "F native deletion exact match ENABLED NOT tapped \(width) max\(large) dark\(dark)")
                    let metrics = RecordFinishedSummaryMetrics(startText: "오전 9:00", endText: "오전 9:30",
                        routeText: "경로 미저장", distanceText: "0.20km")
                        .padding(18).background(SOOMColor.surfacePrimary)
                        .environment(\.dynamicTypeSize, size).environment(\.colorScheme, dark ? .dark : .light)
                    try await snapshot(metrics, width: width, height: large ? 820 : 240,
                        name: "F production finished metrics route not saved native \(width) max\(large) dark\(dark)")
                }
            }
        }
    }

    private func snapshot<V: View>(_ root: V, width: CGFloat, height: CGFloat, name: String) async throws {
        let host = UIHostingController(rootView: root); host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(150)); host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size.width, width, accuracy: 1)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        func scrolls(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
        }
        if name.contains("deletion"), let scroll = scrolls(host.view).first(where: { $0.contentSize.height > $0.bounds.height + 1 }) {
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(for: .milliseconds(100)); host.view.layoutIfNeeded()
            let bottom = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let end = XCTAttachment(image: bottom); end.name = name + " NATIVE scroll end"; end.lifetime = .keepAlways; add(end)
        }
    }
}
