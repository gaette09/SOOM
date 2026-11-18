import Foundation
import Combine
import ImageIO
import Supabase
import SwiftUI
import UIKit

enum ProfileAvatarError: LocalizedError {
    case invalidImage, unavailable, accountChanged
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "사진을 읽지 못했어요. 다른 사진을 선택해 주세요."
        case .unavailable: return "프로필 사진을 저장하지 못했어요. 네트워크와 서버 사진 설정을 확인한 뒤 다시 시도해 주세요."
        case .accountChanged: return "계정이 변경됐어요. 프로필을 다시 열어 주세요."
        }
    }
}

enum ProfileAvatarPolicy {
    static let bucket = "profile-avatars"
    static let maximumBytes = 2 * 1_024 * 1_024

    static func isOwnedPath(_ path: String, by userID: UUID) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == userID.uuidString.lowercased(),
              parts[1].hasSuffix(".jpg") else { return false }
        let name = String(parts[1].dropLast(4))
        return UUID(uuidString: name)?.uuidString.lowercased() == name
    }

    /// Decode a bounded thumbnail, then re-encode its pixels. EXIF/GPS, source
    /// filename and embedded metadata never leave the selected Photos asset.
    static func sanitizedJPEG(from data: Data) throws -> Data {
        guard data.count <= 30 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ProfileAvatarError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw ProfileAvatarError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= maximumBytes else {
            throw ProfileAvatarError.invalidImage
        }
        return output as Data
    }
}

/// Disposable demo media never reaches Storage, a shared cache, or UserDefaults.
@MainActor
final class ReviewDemoAvatarStore {
    static let shared = ReviewDemoAvatarStore()
    private(set) var currentPath: String?
    private var imageData: Data?

    func save(imageData: Data?, userID: UUID) throws -> String? {
        guard ReviewDemoMode.isActive, userID == ReviewDemoMode.userID else {
            throw ProfileAvatarError.accountChanged
        }
        guard let imageData else {
            reset()
            return nil
        }
        let sanitized = try ProfileAvatarPolicy.sanitizedJPEG(from: imageData)
        let path = userID.uuidString.lowercased() + "/" + UUID().uuidString.lowercased() + ".jpg"
        self.imageData = sanitized
        currentPath = path
        return path
    }

    func data(path: String, for userID: UUID) -> Data? {
        guard ReviewDemoMode.isActive, userID == ReviewDemoMode.userID,
              path == currentPath, ProfileAvatarPolicy.isOwnedPath(path, by: userID) else { return nil }
        return imageData
    }

    func reset() {
        currentPath = nil
        imageData = nil
    }

    /// A built-in image lets a fresh review device exercise photo changes too.
    static func sampleImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor(red: 0.12, green: 0.43, blue: 0.39, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIImage(systemName: "figure.run.circle.fill")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 32, y: 32, width: 192, height: 192))
        }
    }
}

/// Bounded account-scoped pixels. A stored image is never an authorization
/// grant: feed reuse requires the newly verified batch object on every return.
@MainActor final class FeedAvatarImageCache: ObservableObject {
    static let shared = FeedAvatarImageCache()
    @Published private(set) var revision = 0
    #if DEBUG && targetEnvironment(simulator)
    // QA statistics must not invalidate every observed avatar while rows appear/disappear.
    private(set) var syntheticPresentedOwners: Set<UUID> = []
    #endif
    func noteSyntheticPresentation(owner: UUID, presented: Bool) {
        #if DEBUG && targetEnvironment(simulator)
        guard ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_QA"] == "1" else { return }
        if presented, !syntheticPresentedOwners.contains(owner) { syntheticPresentedOwners.insert(owner) }
        else if !presented, syntheticPresentedOwners.contains(owner) { syntheticPresentedOwners.remove(owner) }
        #endif
    }
    let invalidatedResources = PassthroughSubject<String, Never>()
    let changedVersions = PassthroughSubject<(resource: String, owner: String?), Never>()
    let pixels = SOOMValidatedMemoryCache<String, CGImage>(maximumCost: 8 * 1_024 * 1_024, maximumCount: 32)
    private var subscriptions: Set<AnyCancellable> = []
    private init() {
        pixels.onResourceInvalidated = { [weak self] in self?.invalidatedResources.send($0) }
        pixels.onResourceVersionChanged = { [weak self] key, owner in self?.changedVersions.send((key, owner)) }
        let safety = CommunitySafetyStore.shared
        safety.$revision.dropFirst().sink { [weak self] _ in self?.invalidate() }.store(in: &subscriptions)
        // Every account-generation mutation also increments the published revision.
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in self?.invalidate() }.store(in: &subscriptions)
    }
    func invalidate() { pixels.invalidate(); revision += 1 }
    static func thumbnail(_ data: Data) -> CGImage? {
        guard !data.isEmpty, data.count <= ProfileAvatarPolicy.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

enum FeedAvatarReusePolicy {
    static func object(presentation: FeedReturnBatchPresentation?, ownerID: UUID?, path: String?, viewerID: UUID?,
                       generation: Int, safetyRevision: Int, returnEpoch: Int, active: Bool) -> FeedReturnStorageObject? {
        guard let presentation, let ownerID, let path, active,
              ProfileAvatarPolicy.isOwnedPath(path, by: ownerID),
              presentation.context.matches(viewerID: viewerID, accountGeneration: generation,
                safetyRevision: safetyRevision, returnEpoch: returnEpoch),
              case .authorized(let object) = presentation.avatarAccess(ownerID: ownerID, path: path),
              object.bucket == ProfileAvatarPolicy.bucket, object.path == path,
              object.size.map({ $0 > 0 && $0 <= ProfileAvatarPolicy.maximumBytes }) ?? true else { return nil }
        return object
    }
}

/// Other hosts keep their existing authenticated download path. Only an explicit
/// fresh feed batch may authorize reusing bounded in-memory avatar pixels.
struct SOOMAvatarView: View {
    let userID: UUID?
    let avatarPath: String?
    let size: CGFloat
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @ObservedObject private var avatarCache = FeedAvatarImageCache.shared
    @Environment(\.soomFeedReturnBatch) private var feedBatch
    @Environment(\.soomFeedBatchIsCurrent) private var feedBatchIsCurrent
    @Environment(\.soomFeedIsActive) private var feedIsActive
    @Environment(\.soomFeedRevalidationRevision) private var returnEpoch
    @State private var image: UIImage?
    @State private var loadedIdentity: LoadIdentity?
    @State private var requestOwner = UUID()
    @State private var publicationRevision = 0
    @State private var applicationIsActive = UIApplication.shared.applicationState == .active
    @State private var activationRevision = 0

    private struct LoadIdentity: Equatable {
        let authorID: UUID?
        let path: String?
        let account: AccountDeletionTarget
        let generation: Int
        let safetyRevision: Int
        let cacheRevision: Int
        let batchID: UUID?
        let object: FeedReturnStorageObject?
        let active: Bool
        let activationRevision: Int
    }
    private var batchObject: FeedReturnStorageObject? {
        guard let feedBatch, feedBatchIsCurrent?(feedBatch.id) == true else { return nil }
        return FeedAvatarReusePolicy.object(presentation: feedBatch, ownerID: userID, path: avatarPath,
            viewerID: auth.session.currentUser?.id, generation: safety.accountGeneration,
            safetyRevision: safety.revision, returnEpoch: returnEpoch, active: feedIsActive && applicationIsActive)
    }
    private var loadIdentity: LoadIdentity {
        .init(authorID: userID, path: avatarPath, account: auth.accountDeletionTarget,
              generation: safety.accountGeneration, safetyRevision: safety.revision, cacheRevision: avatarCache.revision,
              batchID: feedBatch?.id, object: batchObject,
              active: feedBatch == nil || (feedIsActive && applicationIsActive && batchObject != nil),
              activationRevision: feedBatch == nil ? 0 : activationRevision)
    }
    private var resourceKey: String { ProfileAvatarPolicy.bucket + ":" + (avatarPath ?? "") }
    /// The current batch is read through the page's reference gate, not just
    /// its captured Environment value. Rebuilt lazy rows can therefore display
    /// already-resident pixels synchronously without showing stale authority.
    private var residentImage: UIImage? {
        guard let batch = feedBatch, feedBatchIsCurrent?(batch.id) == true,
              let owner = userID, !safety.isBlocked(owner),
              let viewer = auth.session.currentUser?.id, safety.viewerID == viewer,
              !AccountDeletionWriteFence.shared.isRetired(viewer),
              applicationIsActive, UIApplication.shared.applicationState == .active,
              loadIdentity.active, let object = batchObject,
              ReviewDemoMode.isActive || SupabaseClientProvider(environment: AuthEnvironmentLoader().load())
                .makeClient()?.auth.currentSession?.user.id == viewer,
              let pixels = avatarCache.pixels.residentValue(for: resourceKey,
                scope: .init(viewerID: viewer, accountGeneration: safety.accountGeneration, safetyRevision: safety.revision),
                version: object.cacheVersionToken) else { return nil }
        return UIImage(cgImage: pixels)
    }
    private var displayedImage: UIImage? {
        if loadedIdentity == loadIdentity, loadIdentity.active, let image { return image }
        return residentImage
    }
    var body: some View {
        Group {
            if let image = displayedImage {
                Image(uiImage: image).resizable().scaledToFill()
                    .onAppear { avatarCache.noteSyntheticPresentation(owner: requestOwner, presented: true) }
                    .onDisappear { avatarCache.noteSyntheticPresentation(owner: requestOwner, presented: false) }
            } else {
                Image(soom: "person.crop.circle.fill")
                    .resizable().scaledToFit().foregroundStyle(SOOMColor.secondaryInk)
                    .padding(size * 0.05).background(SOOMColor.surfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
        .task(id: loadIdentity) { await load() }
        .onDisappear {
            if feedBatch != nil { cancel(); image = nil; loadedIdentity = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            applicationIsActive = false; activationRevision += 1
            if feedBatch != nil { cancel(); image = nil; loadedIdentity = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            applicationIsActive = true; activationRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            image = nil; loadedIdentity = nil
        }
        .onReceive(avatarCache.changedVersions) { change in
            guard feedBatch != nil, change.resource == resourceKey,
                  change.owner != requestOwner.uuidString else { return }
            publicationRevision += 1; cancel(); image = nil; loadedIdentity = nil
        }
        .onReceive(avatarCache.invalidatedResources) { resource in
            guard feedBatch != nil, resource == resourceKey else { return }
            publicationRevision += 1; image = nil; loadedIdentity = nil
        }
    }
    @MainActor private func cancel() {
        avatarCache.pixels.cancel(for: resourceKey, requestOwner: requestOwner.uuidString)
    }
    @MainActor private func load() async {
        cancel(); image = nil; loadedIdentity = nil
        guard let userID, let avatarPath, ProfileAvatarPolicy.isOwnedPath(avatarPath, by: userID),
              !safety.isBlocked(userID) else { return }
        let identity = loadIdentity
        if feedBatch != nil {
            guard identity.active, let object = identity.object, let viewer = auth.session.currentUser?.id,
                  safety.viewerID == viewer, !AccountDeletionWriteFence.shared.isRetired(viewer),
                  let batch = feedBatch else { return } // Explicit unavailable never falls back.
            let publication = publicationRevision
            let client = ReviewDemoMode.isActive ? nil : SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient()
            let scope = SOOMMediaCacheScope(viewerID: viewer, accountGeneration: safety.accountGeneration, safetyRevision: safety.revision)
            do {
                let pixels = try await avatarCache.pixels.value(for: resourceKey, scope: scope,
                    presentationEpoch: "batch:\(batch.id)", reusePresentation: false, requestOwner: requestOwner.uuidString,
                    authorize: {
                        guard !Task.isCancelled, identity == loadIdentity, publicationRevision == publication,
                              UIApplication.shared.applicationState == .active, !safety.isBlocked(userID),
                              ReviewDemoMode.isActive || client?.auth.currentSession?.user.id == viewer else { throw ProfileAvatarError.accountChanged }
                        return object.cacheVersionToken
                    }, load: {
                        let data: Data
                        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_FEED_BATCH_QA"] == "1",
                           let synthetic = ReviewDemoAvatarStore.sampleImageData() { data = synthetic }
                        else {
                            guard let client, client.auth.currentSession?.user.id == viewer else { throw ProfileAvatarError.unavailable }
                            data = try await client.storage.from(ProfileAvatarPolicy.bucket).download(path: avatarPath)
                        }
                        guard !Task.isCancelled, identity == loadIdentity, publicationRevision == publication,
                              !safety.isBlocked(userID), let pixels = FeedAvatarImageCache.thumbnail(data) else { throw ProfileAvatarError.unavailable }
                        return (pixels, pixels.bytesPerRow * pixels.height)
                    })
                guard !Task.isCancelled, identity == loadIdentity, publicationRevision == publication,
                      UIApplication.shared.applicationState == .active, !safety.isBlocked(userID),
                      ReviewDemoMode.isActive || client?.auth.currentSession?.user.id == viewer else { return }
                image = UIImage(cgImage: pixels); loadedIdentity = identity
            } catch { /* Denial/offline/cancellation never publishes cached pixels. */ }
            return
        }
        // Non-feed hosts retain authenticated downloads, without reusing a feed grant.
        if ReviewDemoMode.isActive {
            guard let data = ReviewDemoAvatarStore.shared.data(path: avatarPath, for: userID) else { return }
            image = UIImage(data: data); loadedIdentity = identity; return
        }
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              let viewer = client.auth.currentSession?.user.id else { return }
        do {
            let data = try await client.storage.from(ProfileAvatarPolicy.bucket).download(path: avatarPath)
            guard !Task.isCancelled, identity == loadIdentity, client.auth.currentSession?.user.id == viewer,
                  !safety.isBlocked(userID), data.count <= ProfileAvatarPolicy.maximumBytes else { return }
            image = UIImage(data: data); loadedIdentity = identity
        } catch { /* The placeholder remains readable offline or after access is revoked. */ }
    }
}
