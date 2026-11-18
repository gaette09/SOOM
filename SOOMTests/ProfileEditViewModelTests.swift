import XCTest
import UIKit
import ImageIO
@testable import SOOM

@MainActor
final class ProfileEditViewModelTests: XCTestCase {
    func testDraftChangesDoNotChangeProfileOrPersistBeforeSave() {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "기존 이름")
        let auth = AuthViewModel(store: store)
        let editor = ProfileEditViewModel(auth: auth)
        editor.name = "저장하지 않은 이름"
        XCTAssertTrue(editor.hasChanges)
        XCTAssertEqual(auth.session.currentUser?.displayName, "기존 이름")
        XCTAssertEqual(store.loadSession().currentUser?.displayName, "기존 이름")
        XCTAssertEqual(ProfileEditViewModel(auth: auth).name, "기존 이름")
    }

    func testLocalSavePersistsAndReopeningUsesSavedName() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "기존 이름")
        let auth = AuthViewModel(store: store)
        let editor = ProfileEditViewModel(auth: auth)
        editor.name = "  새 이름  "
        let saved = await editor.save(using: auth)
        XCTAssertTrue(saved)
        XCTAssertFalse(editor.hasChanges)
        XCTAssertEqual(store.loadSession().currentUser?.displayName, "새 이름")
        XCTAssertEqual(ProfileEditViewModel(auth: AuthViewModel(store: store)).name, "새 이름")
    }

    func testRemoteSaveUsesExistingRPCHandlerAndPreservesGuestProfile() async {
        let store = makeStore()
        let guest = store.continueAsLocalUser(displayName: "기기 이름")
        let user = AppUser(displayName: "원격 이름", authProvider: .supabase)
        var savedOwner: UUID?
        let auth = AuthViewModel(repository: LocalAuthRepository(store: store),
            remoteDisplayNameHandler: { owner, name in savedOwner = owner; return name })
        auth.applyRemoteSession(.signedIn(user: user))
        let editor = ProfileEditViewModel(auth: auth)
        editor.name = "변경한 원격 이름"
        let saved = await editor.save(using: auth)
        XCTAssertTrue(saved)
        XCTAssertEqual(savedOwner, user.id)
        XCTAssertEqual(auth.session.currentUser?.displayName, "변경한 원격 이름")
        XCTAssertEqual(store.loadSession(), guest)
    }

    func testFailureKeepsDraftAndProfileAndCanRetry() async {
        var shouldFail = true
        let auth = AuthViewModel(repository: LocalAuthRepository(store: makeStore()),
            remoteDisplayNameHandler: { _, name in
                if shouldFail { throw URLError(.notConnectedToInternet) }
                return name
            })
        auth.applyRemoteSession(.signedIn(user: AppUser(displayName: "원래 이름", authProvider: .supabase)))
        let editor = ProfileEditViewModel(auth: auth)
        editor.name = "다시 저장할 이름"
        let failed = await editor.save(using: auth)
        XCTAssertFalse(failed)
        XCTAssertNotNil(editor.errorMessage)
        XCTAssertEqual(editor.name, "다시 저장할 이름")
        XCTAssertEqual(auth.session.currentUser?.displayName, "원래 이름")
        XCTAssertTrue(editor.canSave)
        shouldFail = false
        let saved = await editor.save(using: auth)
        XCTAssertTrue(saved)
        XCTAssertNil(editor.errorMessage)
        XCTAssertFalse(editor.hasChanges)
    }

    func testEditorFromAnEarlierSessionCannotRenameSameUUIDAfterReauthentication() async {
        var calls = 0
        let user = AppUser(displayName: "같은 계정", authProvider: .supabase)
        let auth = AuthViewModel(repository: LocalAuthRepository(store: makeStore()),
            remoteDisplayNameHandler: { _, name in calls += 1; return name })
        auth.applyRemoteSession(.signedIn(user: user))
        let editor = ProfileEditViewModel(auth: auth)
        editor.name = "이전 세션의 변경"
        auth.applyRemoteSession(.signedIn(user: user))
        let saved = await editor.save(using: auth)
        XCTAssertFalse(saved)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(auth.session.currentUser, user)
    }

    func testAwaitingSaveCannotApplyToReplacementAccountOrClaimSuccess() async {
        let started = expectation(description: "name save started")
        var continuation: CheckedContinuation<String, Error>?
        let auth = AuthViewModel(repository: LocalAuthRepository(store: makeStore()),
            remoteDisplayNameHandler: { _, _ in
                try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
            })
        auth.applyRemoteSession(.signedIn(user: AppUser(displayName: "A", authProvider: .supabase)))
        let editor = ProfileEditViewModel(auth: auth)
        editor.name = "A 변경"
        let task = Task { await editor.save(using: auth) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(editor.isSaving)
        XCTAssertFalse(editor.canSave)
        let replacement = AppUser(displayName: "B", authProvider: .supabase)
        auth.applyRemoteSession(.signedIn(user: replacement))
        continuation?.resume(returning: "A 변경")
        let saved = await task.value
        XCTAssertFalse(saved)
        XCTAssertEqual(auth.session.currentUser, replacement)
        XCTAssertNotNil(editor.errorMessage)
    }

    func testNameBoundsRejectInvalidInputWithoutChangingSavedProfile() async {
        let store = makeStore()
        _ = store.continueAsLocalUser(displayName: "기존 이름")
        let auth = AuthViewModel(store: store)
        for value in ["  ", String(repeating: "가", count: 81)] {
            let editor = ProfileEditViewModel(auth: auth)
            editor.name = value
            XCTAssertFalse(editor.canSave)
            let saved = await editor.save(using: auth)
            XCTAssertFalse(saved)
            XCTAssertEqual(store.loadSession().currentUser?.displayName, "기존 이름")
        }
    }

    private func makeStore() -> AuthSessionStore {
        let name = "ProfileEditViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return AuthSessionStore(userDefaults: defaults)
    }

    func testAvatarSelectionIsDraftUntilSavedAndRemovesExplicitly() async {
        let user = AppUser(displayName: "사진 계정", authProvider: .supabase)
        let path = user.id.uuidString.lowercased() + "/10000000-0000-0000-0000-000000000001.jpg"
        var calls = 0
        let auth = AuthViewModel(repository: LocalAuthRepository(store: makeStore()), remoteAvatarHandler: { owner, data in
            XCTAssertEqual(owner, user.id)
            calls += 1
            return data == nil ? nil : path
        })
        auth.applyRemoteSession(.signedIn(user: user))
        let editor = ProfileEditViewModel(auth: auth)
        editor.selectAvatar(sampleImageData())
        XCTAssertTrue(editor.hasChanges)
        XCTAssertEqual(calls, 0)
        XCTAssertNil(auth.session.currentUser?.avatarPath)
        let saved = await editor.save(using: auth)
        XCTAssertTrue(saved)
        XCTAssertEqual(auth.session.currentUser?.avatarPath, path)
        XCTAssertFalse(editor.hasChanges)
        editor.removeAvatar()
        let removed = await editor.save(using: auth)
        XCTAssertTrue(removed)
        XCTAssertNil(auth.session.currentUser?.avatarPath)
        XCTAssertEqual(calls, 2)
    }

    func testAvatarFailureKeepsDraftAndRetriesAfterPartialNameSave() async {
        let user = AppUser(displayName: "기존 이름", authProvider: .supabase)
        var shouldFail = true
        var nameCalls = 0
        let auth = AuthViewModel(repository: LocalAuthRepository(store: makeStore()),
            remoteDisplayNameHandler: { _, name in nameCalls += 1; return name },
            remoteAvatarHandler: { owner, _ in
                if shouldFail { throw ProfileAvatarError.unavailable }
                return owner.uuidString.lowercased() + "/10000000-0000-0000-0000-000000000001.jpg"
            })
        auth.applyRemoteSession(.signedIn(user: user))
        let editor = ProfileEditViewModel(auth: auth)
        editor.name = "변경한 이름"
        editor.selectAvatar(sampleImageData())
        let failed = await editor.save(using: auth)
        XCTAssertFalse(failed)
        XCTAssertEqual(auth.session.currentUser?.displayName, "변경한 이름")
        XCTAssertNotNil(editor.avatarData)
        XCTAssertTrue(editor.canSave)
        shouldFail = false
        let saved = await editor.save(using: auth)
        XCTAssertTrue(saved)
        XCTAssertEqual(nameCalls, 1)
        XCTAssertNil(editor.errorMessage)
        XCTAssertFalse(editor.hasChanges)
    }

    func testAvatarCompletionCannotChangeReplacementAccount() async {
        let started = expectation(description: "avatar save started")
        var continuation: CheckedContinuation<String?, Error>?
        let user = AppUser(displayName: "A", authProvider: .supabase)
        let auth = AuthViewModel(repository: LocalAuthRepository(store: makeStore()), remoteAvatarHandler: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        auth.applyRemoteSession(.signedIn(user: user))
        let editor = ProfileEditViewModel(auth: auth)
        editor.selectAvatar(sampleImageData())
        let task = Task { await editor.save(using: auth) }
        await fulfillment(of: [started], timeout: 2)
        let replacement = AppUser(displayName: "B", authProvider: .supabase)
        auth.applyRemoteSession(.signedIn(user: replacement))
        continuation?.resume(returning: user.id.uuidString.lowercased() + "/10000000-0000-0000-0000-000000000001.jpg")
        let saved = await task.value
        XCTAssertFalse(saved)
        XCTAssertEqual(auth.session.currentUser, replacement)
    }

    func testOldEditorCannotUploadPhotoAfterSameAccountReauthentication() async {
        var calls = 0
        let user = AppUser(displayName: "계정", authProvider: .supabase)
        let auth = AuthViewModel(repository: LocalAuthRepository(store: makeStore()), remoteAvatarHandler: { _, _ in calls += 1; return nil })
        auth.applyRemoteSession(.signedIn(user: user))
        let editor = ProfileEditViewModel(auth: auth)
        editor.selectAvatar(sampleImageData())
        auth.applyRemoteSession(.signedIn(user: user))
        let saved = await editor.save(using: auth)
        XCTAssertFalse(saved)
        XCTAssertEqual(calls, 0)
    }

    func testAvatarInvalidDataAndForeignPathsRejected() {
        let userID = UUID()
        let valid = userID.uuidString.lowercased() + "/10000000-0000-0000-0000-000000000001.jpg"
        XCTAssertTrue(ProfileAvatarPolicy.isOwnedPath(valid, by: userID))
        XCTAssertFalse(ProfileAvatarPolicy.isOwnedPath(valid, by: UUID()))
        XCTAssertFalse(ProfileAvatarPolicy.isOwnedPath("https://example.test/" + valid, by: userID))
        XCTAssertFalse(ProfileAvatarPolicy.isOwnedPath(userID.uuidString.lowercased() + "/../x.jpg", by: userID))
        XCTAssertThrowsError(try ProfileAvatarPolicy.sanitizedJPEG(from: Data("not an image".utf8)))
    }

    func testAvatarReencodingBoundsDimensionsAndStripsGPSMetadata() throws {
        let base = sampleImageData(size: CGSize(width: 1600, height: 900))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(base as CFData, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let gpsData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(gpsData, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLongitude: 127.0]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let sanitized = try ProfileAvatarPolicy.sanitizedJPEG(from: gpsData as Data)
        let result = try XCTUnwrap(CGImageSourceCreateWithData(sanitized as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(result, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 768)
        XCTAssertLessThanOrEqual(sanitized.count, ProfileAvatarPolicy.maximumBytes)
    }

    private func sampleImageData(size: CGSize = CGSize(width: 32, height: 32)) -> Data {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.8)!
    }
}
