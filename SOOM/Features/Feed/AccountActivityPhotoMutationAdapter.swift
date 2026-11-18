import Foundation
import Supabase
import CryptoKit
import ImageIO

struct AccountActivityPhotoReference: Codable, Equatable {
    let id: UUID
    let storage_path: String
}
struct AccountActivityPhotoUpload: Codable, Equatable {
    let reference: AccountActivityPhotoReference
    let jpeg: Data
}
struct AccountActivityPhotoEdit: Codable, Equatable {
    let id: UUID
    let ownerID: UUID
    let cardID: UUID
    let expectedIDs: [UUID]
    let desired: [AccountActivityPhotoReference]
    let uploads: [AccountActivityPhotoUpload]
}
enum AccountActivityPhotoProbe { case matches, absent, unknown }
enum AccountActivityPhotoEditError: Error { case invalid, blocked, uncertain, conflict, contextChanged }
@MainActor
protocol AccountActivityPhotoStorageTransport {
    func uploadImmutable(_ upload: AccountActivityPhotoUpload) async throws
    func probe(_ upload: AccountActivityPhotoUpload) async throws -> AccountActivityPhotoProbe
}
@MainActor
struct SupabaseAccountActivityPhotoStorageTransport: AccountActivityPhotoStorageTransport {
    let client: SupabaseClient
    func uploadImmutable(_ upload: AccountActivityPhotoUpload) async throws {
        guard AccountActivityInteractionReleaseGate.productionReady else { throw AccountActivityInteractionError.disabled }
        _ = try await client.storage.from("activity-photos-candidate").upload(upload.reference.storage_path,
            data:upload.jpeg,options:FileOptions(contentType:"image/jpeg",upsert:false))
    }
    func probe(_ upload: AccountActivityPhotoUpload) async throws -> AccountActivityPhotoProbe {
        guard AccountActivityInteractionReleaseGate.productionReady else { throw AccountActivityInteractionError.disabled }
        // A failed download does not prove absence. Never overwrite or delete an uncertain object.
        guard let data = try? await client.storage.from("activity-photos-candidate").download(path:upload.reference.storage_path) else { return .unknown }
        return SHA256.hash(data:data) == SHA256.hash(data:upload.jpeg) ? .matches : .unknown
    }
}
struct AccountActivityPhotoEditState: Codable {
    let edit: AccountActivityPhotoEdit
    var attempted: Set<UUID> = []
    var uploaded: Set<UUID> = []
    var metadataAttempted = false
}
@MainActor
protocol AccountActivityPhotoEditJournal {
    func read() throws -> [AccountActivityPhotoEditState]
    func write(_ states: [AccountActivityPhotoEditState]) throws
}
@MainActor
final class FileAccountActivityPhotoEditJournal: AccountActivityPhotoEditJournal {
    private let url: URL
    private let ownerID: UUID?
    init(ownerID: UUID?, url: URL? = nil) {
        self.ownerID=ownerID
        self.url=url ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("HealthAccounts/\(ownerID?.uuidString.lowercased() ?? "unavailable")/native-photo-pending-v1.json")
    }
    func read() throws -> [AccountActivityPhotoEditState] {
        guard let ownerID else { throw AccountActivityPhotoEditError.contextChanged }
        return try AccountDeletionWriteFence.shared.withActiveScope(ownerID) {
            guard FileManager.default.fileExists(atPath:url.path) else { return [] }
            let rows=try JSONDecoder().decode([AccountActivityPhotoEditState].self,from:Data(contentsOf:url))
            guard rows.allSatisfy({$0.edit.ownerID==ownerID}) else { throw AccountActivityPhotoEditError.contextChanged }
            return rows
        }
    }
    func write(_ states: [AccountActivityPhotoEditState]) throws {
        guard let ownerID,states.allSatisfy({$0.edit.ownerID==ownerID}) else { throw AccountActivityPhotoEditError.contextChanged }
        try AccountDeletionWriteFence.shared.withActiveScope(ownerID) {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(states).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            var values=URLResourceValues();values.isExcludedFromBackup=true;var file=url
            try file.setResourceValues(values)
        }
    }
}
@MainActor
final class MemoryAccountActivityPhotoEditJournal: AccountActivityPhotoEditJournal {
    var states: [AccountActivityPhotoEditState] = []
    func read() throws -> [AccountActivityPhotoEditState] { states }
    func write(_ states: [AccountActivityPhotoEditState]) throws { self.states = states }
}
@MainActor
final class AccountActivityPhotoMutationAdapter {
    let reader: AccountActivityInteractionAdapter
    private let transport: any AccountActivityInteractionTransport
    private let storage: any AccountActivityPhotoStorageTransport
    private let journal: any AccountActivityPhotoEditJournal
    private let context: () -> AccountActivityInteractionContext
    private let fixture: Bool
    private var busy = false
    init(reader: AccountActivityInteractionAdapter, transport: any AccountActivityInteractionTransport,
         storage: any AccountActivityPhotoStorageTransport, context: @escaping () -> AccountActivityInteractionContext,
         journal: (any AccountActivityPhotoEditJournal)? = nil) {
        self.reader=reader;self.transport=transport;self.storage=storage;self.context=context
        self.journal=journal ?? FileAccountActivityPhotoEditJournal(ownerID:context().viewerID);fixture=false
    }
    #if DEBUG
    private init(reader:AccountActivityInteractionAdapter,transport:any AccountActivityInteractionTransport,
                 storage:any AccountActivityPhotoStorageTransport,context:@escaping()->AccountActivityInteractionContext,
                 fixtureJournal:any AccountActivityPhotoEditJournal) {
        self.reader=reader;self.transport=transport;self.storage=storage;self.context=context;journal=fixtureJournal;fixture=true
    }
    static func localFixture(reader:AccountActivityInteractionAdapter,transport:any AccountActivityInteractionTransport,
                             storage:any AccountActivityPhotoStorageTransport,context:@escaping()->AccountActivityInteractionContext,
                             journal:any AccountActivityPhotoEditJournal) -> AccountActivityPhotoMutationAdapter {
        .init(reader:reader,transport:transport,storage:storage,context:context,fixtureJournal:journal)
    }
    #endif
    func pending(cardID: UUID) throws -> [AccountActivityPhotoEdit] {
        guard fixture || AccountActivityInteractionReleaseGate.productionReady else { throw AccountActivityInteractionError.disabled }
        return try journal.read().filter{$0.edit.ownerID==context().viewerID && $0.edit.cardID==cardID}.map(\.edit)
    }
    private func save(_ state: AccountActivityPhotoEditState) throws {
        var states=try journal.read();states.removeAll{$0.edit.id==state.edit.id};states.append(state);try journal.write(states)
    }
    func apply(_ edit:AccountActivityPhotoEdit) async throws {
        guard fixture || AccountActivityInteractionReleaseGate.productionReady else { throw AccountActivityInteractionError.disabled }
        guard !busy else { throw AccountActivityPhotoEditError.blocked };busy=true;defer{busy=false}
        let c=context()
        func check() throws { guard context()==c,!AccountDeletionWriteFence.shared.isRetired(edit.ownerID),!Task.isCancelled else { throw AccountActivityPhotoEditError.contextChanged } }
        guard !AccountDeletionWriteFence.shared.isRetired(edit.ownerID),c.viewerID==edit.ownerID,c.storageScopeID==edit.ownerID.uuidString.lowercased(),c.generation>=0,
              edit.desired.count<=6,Set(edit.desired.map(\.id)).count==edit.desired.count,
              Set(edit.expectedIDs).count==edit.expectedIDs.count,Set(edit.uploads.map{$0.reference.id}).count==edit.uploads.count,
              edit.uploads.count<=6 else { throw AccountActivityPhotoEditError.invalid }
        for ref in edit.desired {
            guard ref.storage_path=="\(edit.ownerID.uuidString.lowercased())/\(edit.cardID.uuidString.lowercased())/\(ref.id.uuidString.lowercased()).jpg" else { throw AccountActivityPhotoEditError.invalid }
        }
        for upload in edit.uploads {
            guard edit.desired.contains(upload.reference),!edit.expectedIDs.contains(upload.reference.id),
                  upload.jpeg.count<=5_242_880,!upload.jpeg.isEmpty,
                  let image=CGImageSourceCreateWithData(upload.jpeg as CFData,nil),
                  CGImageSourceGetType(image) as String? == "public.jpeg", CGImageSourceGetCount(image)==1,
                  let properties=CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [String:Any],
                  properties[kCGImagePropertyGPSDictionary as String]==nil,
                  properties[kCGImagePropertyExifDictionary as String]==nil,
                  properties[kCGImagePropertyTIFFDictionary as String]==nil,
                  let width=properties[kCGImagePropertyPixelWidth as String] as? Int,
                  let height=properties[kCGImagePropertyPixelHeight as String] as? Int,
                  (1...2048).contains(width),(1...2048).contains(height) else { throw AccountActivityPhotoEditError.invalid }
        }
        let stored=try journal.read()
        guard !stored.contains(where:{$0.edit.ownerID==edit.ownerID && $0.edit.cardID==edit.cardID && $0.edit.id != edit.id}) else { throw AccountActivityPhotoEditError.blocked }
        if let existing=stored.first(where:{$0.edit.id==edit.id}),existing.edit != edit { throw AccountActivityPhotoEditError.invalid }
        var state=stored.first(where:{$0.edit.id==edit.id}) ?? .init(edit:edit)
        try save(state)
        let target=AccountActivityInteractionTarget.native(cardID:edit.cardID,ownerID:edit.ownerID)
        let current=try await reader.loadPhotos(target);try check()
        let refs=current.map{AccountActivityPhotoReference(id:$0.id,storage_path:$0.storage_path)}
        if refs==edit.desired {
            try journal.write(journal.read().filter{$0.edit.id != edit.id});return
        }
        guard Set(current.map(\.id))==Set(edit.expectedIDs) else { throw AccountActivityPhotoEditError.conflict }
        // An uncertain metadata commit requires lookup only. Exact desired state above resolves success.
        guard !state.metadataAttempted else { throw AccountActivityPhotoEditError.uncertain }
        let supplied=Set(edit.uploads.map{$0.reference.id})
        guard edit.desired.allSatisfy({ ref in current.contains{$0.id==ref.id && $0.storage_path==ref.storage_path} || supplied.contains(ref.id) }) else { throw AccountActivityPhotoEditError.invalid }
        for upload in edit.uploads where !state.uploaded.contains(upload.reference.id) {
            if state.attempted.contains(upload.reference.id) {
                let result=try await storage.probe(upload);try check()
                guard case .matches=result else { throw AccountActivityPhotoEditError.uncertain }
            } else {
                state.attempted.insert(upload.reference.id);try save(state)
                do { try await storage.uploadImmutable(upload);try check() }
                catch { throw AccountActivityPhotoEditError.uncertain }
            }
            state.uploaded.insert(upload.reference.id);try save(state)
        }
        // CAS expected IDs prevents overwriting another editor. No old-object cleanup/delete.
        state.metadataAttempted=true;try save(state)
        do {
            _ = try await transport.call("soom_activity_replace_photos_candidate_v1",params:.init(p_card_id:edit.cardID,
                p_expected_photo_ids:edit.expectedIDs,p_photos:edit.desired));try check()
            let verified=try await reader.loadPhotos(target);try check()
            guard verified.map({AccountActivityPhotoReference(id:$0.id,storage_path:$0.storage_path)})==edit.desired else { throw AccountActivityPhotoEditError.uncertain }
            try journal.write(journal.read().filter{$0.edit.id != edit.id})
        } catch { throw AccountActivityPhotoEditError.uncertain }
    }
}

/// Injection seam for the existing record-modify photo UI. Target resolution must
/// come from the validated activity bridge; workout UUID is never assumed to be card/post UUID.
@MainActor
struct AccountActivityWorkoutPhotoProvider: WorkoutPhotoManaging {
    let reader: AccountActivityInteractionAdapter
    let writer: AccountActivityPhotoMutationAdapter
    let legacy: any WorkoutPhotoManaging
    let resolveTarget: (UUID, UUID) async throws -> AccountActivityInteractionTarget
    func load(workoutID: UUID, ownerID: UUID) async throws -> [WorkoutPhotoReference] {
        let target = try await resolveTarget(workoutID,ownerID)
        switch target {
        case .legacy: return try await legacy.load(workoutID:workoutID,ownerID:ownerID)
        case .native(let cardID,let resolvedOwner):
            guard resolvedOwner==ownerID else { throw AccountActivityPhotoEditError.invalid }
            return try await reader.loadPhotos(target).map { .init(id:$0.id,storagePath:$0.storage_path,nativeCardID:cardID) }
        }
    }
    func replace(workout:UnifiedWorkout,ownerID:UUID,photos:[WorkoutPhotoDraft],expectedPhotoIDs:[UUID]?) async throws {
        let target=try await resolveTarget(workout.id,ownerID)
        switch target {
        case .legacy:
            try await legacy.replace(workout:workout,ownerID:ownerID,photos:photos,expectedPhotoIDs:expectedPhotoIDs)
        case .native(let cardID,let resolvedOwner):
            guard ownerID==resolvedOwner,let expectedPhotoIDs else { throw AccountActivityPhotoEditError.invalid }
            var references:[AccountActivityPhotoReference]=[];var uploads:[AccountActivityPhotoUpload]=[]
            for photo in photos {
                let path="\(ownerID.uuidString.lowercased())/\(cardID.uuidString.lowercased())/\(photo.id.uuidString.lowercased()).jpg"
                let reference=AccountActivityPhotoReference(id:photo.id,storage_path:path)
                if let existing=photo.reference {
                    guard existing.id==photo.id,existing.storagePath==path,existing.nativeCardID==cardID,photo.jpegData==nil else { throw AccountActivityPhotoEditError.invalid }
                } else if let data=photo.jpegData {
                    uploads.append(.init(reference:reference,jpeg:try WorkoutPhotoPolicy.sanitizedJPEG(from:data)))
                } else { throw AccountActivityPhotoEditError.invalid }
                references.append(reference)
            }
            let pending=try writer.pending(cardID:cardID)
            let edit=AccountActivityPhotoEdit(id:pending.first?.id ?? UUID(),ownerID:ownerID,cardID:cardID,
                expectedIDs:expectedPhotoIDs,desired:references,uploads:uploads)
            guard pending.isEmpty || pending==[edit] else { throw AccountActivityPhotoEditError.blocked }
            try await writer.apply(edit)
        }
    }
    func uploadRoute(workout:UnifiedWorkout,ownerID:UUID,data:Data) async throws {
        switch try await resolveTarget(workout.id,ownerID) {
        case .legacy: try await legacy.uploadRoute(workout:workout,ownerID:ownerID,data:data)
        case .native: throw AccountActivityInteractionError.disabled // Dedicated native route contract not part of photo metadata.
        }
    }
}
