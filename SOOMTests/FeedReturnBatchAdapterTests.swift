import XCTest
import SwiftUI
import UIKit
import Combine
import Supabase
@testable import SOOM

@MainActor final class FeedReturnBatchAdapterTests: XCTestCase {
    private let context = FeedReturnBatchContext(viewerID: UUID(uuidString: "21f8f559-2692-63fe-ceab-c78b7e72f369")!, accountGeneration: 7, safetyRevision: 8, returnEpoch: 9)
    private var fixture: Data { Data(#"{"rows": [{"author": {"id": "a95dc583-796f-9823-9ecc-147995af54ad", "handle": "socialfixture1", "avatar_path": "a95dc583-796f-9823-9ecc-147995af54ad/6e852ca7-3e06-3cf5-40ae-d1597b686e46.jpg", "display_name": "SOOM 사용자"}, "avatar": {"etag": "avatar-one", "size": 1000, "bucket": "profile-avatars", "version": "a1", "object_id": "6e852ca7-3e06-3cf5-40ae-d1597b686e46", "authorized": true, "updated_at": "2026-11-14T17:28:47.963042+09:00", "storage_path": "a95dc583-796f-9823-9ecc-147995af54ad/6e852ca7-3e06-3cf5-40ae-d1597b686e46.jpg", "version_hash": "f39ce0e0c5a0524b428781045030d907679df612450b59d89b1a9f7e41a0c86a"}, "photos": {"rows": [{"id": "674b02cd-cb55-cd5c-ca79-958ee26d3eb9", "object": {"etag": "photo-one", "size": 1000, "version": "v1", "object_id": "674b02cd-cb55-cd5c-ca79-958ee26d3eb9", "updated_at": "2026-11-14T17:28:47.963042+09:00", "version_hash": "77fd628fb10eb15ee720b1abb540ab20effef839ffe027e8d654609ea0f8668e"}, "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "sort_order": 0, "storage_path": "a95dc583-796f-9823-9ecc-147995af54ad/b72bfb07-64a6-8fde-0811-66f167172788/674b02cd-cb55-cd5c-ca79-958ee26d3eb9.jpg"}], "bucket": "workout-photos", "backing": "legacy", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "release_ready": true, "profile_revision": 1, "projection_revision": 1}, "social": {"state": "ready", "receipt": {"backing": "legacy", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "legacy", "read_sources": [{"source_kind": "legacy", "source_id": "b72bfb07-64a6-8fde-0811-66f167172788"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "cheer_count": 0, "comment_count": 2, "latest_comment_at": "2026-11-14T17:28:47.335196+09:00", "viewer_has_cheered": false}, "allowed": true, "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "summary": {"sport": "running", "card_id": "23778b35-6d92-0131-3bf8-bdb05bf30f49", "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "revision": 1, "activity_at": "2020-01-01T00:00:00+09:00", "canonical_id": "b8a848e0-2ec4-a29a-338c-7a19b93e7d29", "distance_meters": 1000, "duration_seconds": 600}, "author_revision": "73affe3640dfa77d9f95ab81d2851b4c7adba5002329ec010f7ddd3c433aac2c", "social_revision": "c4b68ef0d9824711eb9f36d65c6d37acf04e5d95fcb6c3b99abc8f4eed331a26"}, {"author": {"id": "a95dc583-796f-9823-9ecc-147995af54ad", "handle": "socialfixture1", "avatar_path": "a95dc583-796f-9823-9ecc-147995af54ad/6e852ca7-3e06-3cf5-40ae-d1597b686e46.jpg", "display_name": "SOOM 사용자"}, "avatar": {"etag": "avatar-one", "size": 1000, "bucket": "profile-avatars", "version": "a1", "object_id": "6e852ca7-3e06-3cf5-40ae-d1597b686e46", "authorized": true, "updated_at": "2026-11-14T17:28:47.963042+09:00", "storage_path": "a95dc583-796f-9823-9ecc-147995af54ad/6e852ca7-3e06-3cf5-40ae-d1597b686e46.jpg", "version_hash": "f39ce0e0c5a0524b428781045030d907679df612450b59d89b1a9f7e41a0c86a"}, "photos": {"rows": [{"id": "7cc6d0b4-22ea-75c8-a9a2-5dfd900ca47c", "object": {"etag": null, "size": 1000, "version": "v1", "object_id": "7cc6d0b4-22ea-75c8-a9a2-5dfd900ca47c", "updated_at": "2026-11-14T17:28:47.963042+09:00", "version_hash": "30ff12b60f21baa5b47ea4a27a0ebde70c1ecd7036b7b4051fc18e532351f962"}, "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "sort_order": 0, "storage_path": "a95dc583-796f-9823-9ecc-147995af54ad/eba4f61f-48bf-0c18-811f-496efa16051c/7cc6d0b4-22ea-75c8-a9a2-5dfd900ca47c.jpg"}], "bucket": "activity-photos-candidate", "backing": "native", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "374dab0a-fdae-17b7-8e57-0fb2371ec110", "release_ready": true, "profile_revision": 1, "projection_revision": 1}, "social": {"state": "ready", "receipt": {"backing": "native", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "version": 2, "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "canonical_id": "374dab0a-fdae-17b7-8e57-0fb2371ec110", "release_ready": true, "profile_revision": 1, "projection_revision": 1, "write_backing": "native", "read_sources": [{"source_kind": "native", "source_id": "eba4f61f-48bf-0c18-811f-496efa16051c"}], "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, "cheer_count": 1, "comment_count": 1, "latest_comment_at": "2026-11-14T17:28:47.335196+09:00", "viewer_has_cheered": true}, "allowed": true, "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "summary": {"sport": "running", "card_id": "eba4f61f-48bf-0c18-811f-496efa16051c", "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad", "revision": 1, "activity_at": "2020-01-01T00:00:00+09:00", "canonical_id": "374dab0a-fdae-17b7-8e57-0fb2371ec110", "distance_meters": 1000, "duration_seconds": 600}, "author_revision": "73affe3640dfa77d9f95ab81d2851b4c7adba5002329ec010f7ddd3c433aac2c", "social_revision": "4ecd9c537dbb6326b25e424a2a1ace6d0a2a5198d8341fe38482fce97f61a2b6"}], "scope": "home", "version": 2, "has_more": false, "viewer_id": "21f8f559-2692-63fe-ceab-c78b7e72f369", "return_epoch": 9, "release_ready": true, "safety_revision": 8, "needs_page_reload": false, "account_generation": 7, "membership_revision": "c86de0df0087853bcc0c5338c4e36ef171ab46b8ab70527d1cd5ef841418db1e"}"#.utf8) }
    private func object() throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any]) }
    private func sourceRows() throws -> [AccountActivityFeedRow] {
        let rows = try XCTUnwrap(try object()["rows"] as? [[String: Any]])
        return try rows.map { value in
            var row = try JSONDecoder().decode(AccountActivityFeedRow.self, from: JSONSerialization.data(withJSONObject: value["summary"]!))
            row.readPolicy = .profileOnlyV2
            return row
        }
    }
    private func validate(_ value: [String: Any]? = nil) throws -> FeedReturnBatchPresentation {
        let rows = try sourceRows()
        return try FeedReturnBatchAdapter.validate(value.map { try JSONSerialization.data(withJSONObject: $0) } ?? fixture,
            cardIDs: rows.map(\.cardID), loadedRows: rows, context: context, id: UUID())
    }
    private func changingFirst(_ mutate: (inout [String: Any]) -> Void) throws -> [String: Any] {
        var value = try object(); var rows = try XCTUnwrap(value["rows"] as? [[String: Any]])
        mutate(&rows[0]); value["rows"] = rows; return value
    }
    func testActualV3SQLSyntheticWireDecodesIntoGrantedCardPresentation() throws {
        // Generated by actual local SQL definitions using synthetic users only.
        let data = try XCTUnwrap(Data(base64Encoded: "ewogICJyb3dzIjogWwogICAgewogICAgICAiYXV0aG9yIjogewogICAgICAgICJpZCI6ICJhOTVkYzU4My03OTZmLTk4MjMtOWVjYy0xNDc5OTVhZjU0YWQiLAogICAgICAgICJoYW5kbGUiOiAic29jaWFsZml4dHVyZTEiLAogICAgICAgICJhdmF0YXJfcGF0aCI6ICJhOTVkYzU4My03OTZmLTk4MjMtOWVjYy0xNDc5OTVhZjU0YWQvNmU4NTJjYTctM2UwNi0zY2Y1LTQwYWUtZDE1OTdiNjg2ZTQ2LmpwZyIsCiAgICAgICAgImRpc3BsYXlfbmFtZSI6ICJTT09NIFx1YzBhY1x1YzZhOVx1Yzc5MCIKICAgICAgfSwKICAgICAgImF2YXRhciI6IHsKICAgICAgICAiZXRhZyI6ICJhdmF0YXItb25lIiwKICAgICAgICAic2l6ZSI6IDEwMDAsCiAgICAgICAgImJ1Y2tldCI6ICJwcm9maWxlLWF2YXRhcnMiLAogICAgICAgICJ2ZXJzaW9uIjogImExIiwKICAgICAgICAib2JqZWN0X2lkIjogIjZlODUyY2E3LTNlMDYtM2NmNS00MGFlLWQxNTk3YjY4NmU0NiIsCiAgICAgICAgImF1dGhvcml6ZWQiOiB0cnVlLAogICAgICAgICJ1cGRhdGVkX2F0IjogIjIwMjYtMTEtMTdUMjA6Mzg6MjcuMDA4NTI2KzA5OjAwIiwKICAgICAgICAic3RvcmFnZV9wYXRoIjogImE5NWRjNTgzLTc5NmYtOTgyMy05ZWNjLTE0Nzk5NWFmNTRhZC82ZTg1MmNhNy0zZTA2LTNjZjUtNDBhZS1kMTU5N2I2ODZlNDYuanBnIiwKICAgICAgICAidmVyc2lvbl9oYXNoIjogIjg0OTgzYjdiZDUwNzhiYjUxNmI1YWZjZmFjN2NlNGQ1MDQ3NjY0MTRlZGNlMzBmZDJmNzYwZjAxY2Y4YWMxZTUiCiAgICAgIH0sCiAgICAgICJwaG90b3MiOiB7CiAgICAgICAgInJvd3MiOiBbCiAgICAgICAgICB7CiAgICAgICAgICAgICJpZCI6ICI2NzRiMDJjZC1jYjU1LWNkNWMtY2E3OS05NThlZTI2ZDNlYjkiLAogICAgICAgICAgICAib2JqZWN0IjogewogICAgICAgICAgICAgICJldGFnIjogInBob3RvLW9uZSIsCiAgICAgICAgICAgICAgInNpemUiOiAxMDAwLAogICAgICAgICAgICAgICJ2ZXJzaW9uIjogInYxIiwKICAgICAgICAgICAgICAib2JqZWN0X2lkIjogIjY3NGIwMmNkLWNiNTUtY2Q1Yy1jYTc5LTk1OGVlMjZkM2ViOSIsCiAgICAgICAgICAgICAgInVwZGF0ZWRfYXQiOiAiMjAyNi0xMS0xN1QyMDozODoyNy4wMDg1MjYrMDk6MDAiLAogICAgICAgICAgICAgICJ2ZXJzaW9uX2hhc2giOiAiMjc5ZmMxMGQzMzJiMzJhZGRkYjk0MDg2ZGQ3YzZmOGQzMTg0MjBkZTI4YzNmODU3ZjgxNjlmOTU1MjFhOThhOSIKICAgICAgICAgICAgfSwKICAgICAgICAgICAgImNhcmRfaWQiOiAiMjM3NzhiMzUtNmQ5Mi0wMTMxLTNiZjgtYmRiMDViZjMwZjQ5IiwKICAgICAgICAgICAgInNvcnRfb3JkZXIiOiAwLAogICAgICAgICAgICAic3RvcmFnZV9wYXRoIjogImE5NWRjNTgzLTc5NmYtOTgyMy05ZWNjLTE0Nzk5NWFmNTRhZC9iNzJiZmIwNy02NGE2LThmZGUtMDgxMS02NmYxNjcxNzI3ODgvNjc0YjAyY2QtY2I1NS1jZDVjLWNhNzktOTU4ZWUyNmQzZWI5LmpwZyIKICAgICAgICAgIH0KICAgICAgICBdLAogICAgICAgICJidWNrZXQiOiAid29ya291dC1waG90b3MiLAogICAgICAgICJiYWNraW5nIjogImxlZ2FjeSIsCiAgICAgICAgImNhcmRfaWQiOiAiMjM3NzhiMzUtNmQ5Mi0wMTMxLTNiZjgtYmRiMDViZjMwZjQ5IiwKICAgICAgICAidmVyc2lvbiI6IDIsCiAgICAgICAgIm93bmVyX2lkIjogImE5NWRjNTgzLTc5NmYtOTgyMy05ZWNjLTE0Nzk5NWFmNTRhZCIsCiAgICAgICAgInNvdXJjZV9pZCI6ICJiNzJiZmIwNy02NGE2LThmZGUtMDgxMS02NmYxNjcxNzI3ODgiLAogICAgICAgICJ2aWV3ZXJfaWQiOiAiMjFmOGY1NTktMjY5Mi02M2ZlLWNlYWItYzc4YjdlNzJmMzY5IiwKICAgICAgICAiY2Fub25pY2FsX2lkIjogImI4YTg0OGUwLTJlYzQtYTI5YS0zMzhjLTdhMTliOTNlN2QyOSIsCiAgICAgICAgInJlbGVhc2VfcmVhZHkiOiB0cnVlLAogICAgICAgICJwcm9maWxlX3JldmlzaW9uIjogMSwKICAgICAgICAicHJvamVjdGlvbl9yZXZpc2lvbiI6IDEKICAgICAgfSwKICAgICAgInNvY2lhbCI6IHsKICAgICAgICAic3RhdGUiOiAicmVhZHkiLAogICAgICAgICJyZWNlaXB0IjogewogICAgICAgICAgImJhY2tpbmciOiAibGVnYWN5IiwKICAgICAgICAgICJjYXJkX2lkIjogIjIzNzc4YjM1LTZkOTItMDEzMS0zYmY4LWJkYjA1YmYzMGY0OSIsCiAgICAgICAgICAidmVyc2lvbiI6IDIsCiAgICAgICAgICAib3duZXJfaWQiOiAiYTk1ZGM1ODMtNzk2Zi05ODIzLTllY2MtMTQ3OTk1YWY1NGFkIiwKICAgICAgICAgICJzb3VyY2VfaWQiOiAiYjcyYmZiMDctNjRhNi04ZmRlLTA4MTEtNjZmMTY3MTcyNzg4IiwKICAgICAgICAgICJ2aWV3ZXJfaWQiOiAiMjFmOGY1NTktMjY5Mi02M2ZlLWNlYWItYzc4YjdlNzJmMzY5IiwKICAgICAgICAgICJjYW5vbmljYWxfaWQiOiAiYjhhODQ4ZTAtMmVjNC1hMjlhLTMzOGMtN2ExOWI5M2U3ZDI5IiwKICAgICAgICAgICJyZWFkX3NvdXJjZXMiOiBbCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAic291cmNlX2lkIjogImI3MmJmYjA3LTY0YTYtOGZkZS0wODExLTY2ZjE2NzE3Mjc4OCIsCiAgICAgICAgICAgICAgInNvdXJjZV9raW5kIjogImxlZ2FjeSIKICAgICAgICAgICAgfQogICAgICAgICAgXSwKICAgICAgICAgICJyZWxlYXNlX3JlYWR5IjogdHJ1ZSwKICAgICAgICAgICJ3cml0ZV9iYWNraW5nIjogImxlZ2FjeSIsCiAgICAgICAgICAic291cmNlX3JldmlzaW9uIjogIjY1NzUzOGM0NDQ4NWU4MjVhOGE1Y2Y4MWUyMzhmZDFmIiwKICAgICAgICAgICJwcm9maWxlX3JldmlzaW9uIjogMSwKICAgICAgICAgICJwcm9qZWN0aW9uX3JldmlzaW9uIjogMQogICAgICAgIH0sCiAgICAgICAgImNoZWVyX2NvdW50IjogMCwKICAgICAgICAiY29tbWVudF9jb3VudCI6IDIsCiAgICAgICAgImxhdGVzdF9jb21tZW50X2F0IjogIjIwMjYtMTEtMTdUMjA6Mzg6MjYuMDQ5NzY1KzA5OjAwIiwKICAgICAgICAidmlld2VyX2hhc19jaGVlcmVkIjogZmFsc2UKICAgICAgfSwKICAgICAgImFsbG93ZWQiOiB0cnVlLAogICAgICAiY2FyZF9pZCI6ICIyMzc3OGIzNS02ZDkyLTAxMzEtM2JmOC1iZGIwNWJmMzBmNDkiLAogICAgICAic3VtbWFyeSI6IHsKICAgICAgICAic3BvcnQiOiAicnVubmluZyIsCiAgICAgICAgImNhcmRfaWQiOiAiMjM3NzhiMzUtNmQ5Mi0wMTMxLTNiZjgtYmRiMDViZjMwZjQ5IiwKICAgICAgICAib3duZXJfaWQiOiAiYTk1ZGM1ODMtNzk2Zi05ODIzLTllY2MtMTQ3OTk1YWY1NGFkIiwKICAgICAgICAicmV2aXNpb24iOiAxLAogICAgICAgICJhY3Rpdml0eV9hdCI6ICIyMDIwLTAxLTAxVDAwOjAwOjAwKzA5OjAwIiwKICAgICAgICAiY2Fub25pY2FsX2lkIjogImI4YTg0OGUwLTJlYzQtYTI5YS0zMzhjLTdhMTliOTNlN2QyOSIsCiAgICAgICAgImRpc3RhbmNlX21ldGVycyI6IDEwMDAsCiAgICAgICAgImR1cmF0aW9uX3NlY29uZHMiOiA2MDAKICAgICAgfSwKICAgICAgImNhcmRfcHJldmlldyI6IHsKICAgICAgICAic3RhdGUiOiAicmVhZHkiLAogICAgICAgICJ0aXRsZSI6ICJzeW50aGV0aWMgc29jaWFsIGxlZ2FjeSIsCiAgICAgICAgImNhcHRpb24iOiBudWxsLAogICAgICAgICJwb3N0X2lkIjogImI3MmJmYjA3LTY0YTYtOGZkZS0wODExLTY2ZjE2NzE3Mjc4OCIsCiAgICAgICAgInZlcnNpb24iOiAxLAogICAgICAgICJvd25lcl9pZCI6ICJhOTVkYzU4My03OTZmLTk4MjMtOWVjYy0xNDc5OTVhZjU0YWQiLAogICAgICAgICJkZXZpY2VfbmFtZSI6IG51bGwsCiAgICAgICAgInJvdXRlX3N0YXRlIjogInJlYWR5IiwKICAgICAgICAibG9jYXRpb25fbmFtZSI6IG51bGwsCiAgICAgICAgInBvc3RfcmV2aXNpb24iOiAiMjAyNi0xMS0xN1QyMDozOTo0NS45MTU3OTcrMDk6MDAiLAogICAgICAgICJjb25zZW50X3JldmlzaW9uIjogMSwKICAgICAgICAic25hcHNob3RfcmV2aXNpb24iOiAxLAogICAgICAgICJzZXJpYWxpemVyX3ZlcnNpb24iOiAxLAogICAgICAgICJhdXRob3JpemVkX3JvdXRlX2dlb21ldHJ5IjogWwogICAgICAgICAgewogICAgICAgICAgICAic2VnbWVudCI6IDAsCiAgICAgICAgICAgICJsYXRpdHVkZSI6IDAsCiAgICAgICAgICAgICJsb25naXR1ZGUiOiAwLjAwMwogICAgICAgICAgfSwKICAgICAgICAgIHsKICAgICAgICAgICAgInNlZ21lbnQiOiAwLAogICAgICAgICAgICAibGF0aXR1ZGUiOiAwLAogICAgICAgICAgICAibG9uZ2l0dWRlIjogMC4wMDQKICAgICAgICAgIH0sCiAgICAgICAgICB7CiAgICAgICAgICAgICJzZWdtZW50IjogMCwKICAgICAgICAgICAgImxhdGl0dWRlIjogMCwKICAgICAgICAgICAgImxvbmdpdHVkZSI6IDAuMDA2CiAgICAgICAgICB9LAogICAgICAgICAgewogICAgICAgICAgICAic2VnbWVudCI6IDAsCiAgICAgICAgICAgICJsYXRpdHVkZSI6IDAsCiAgICAgICAgICAgICJsb25naXR1ZGUiOiAwLjAwNwogICAgICAgICAgfQogICAgICAgIF0KICAgICAgfSwKICAgICAgImF1dGhvcl9yZXZpc2lvbiI6ICI3M2FmZmUzNjQwZGZhNzdkOWY5NWFiODFkMjg1MWI0YzdhZGJhNTAwMjMyOWVjMDEwZjdkZGQzYzQzM2FhYzJjIiwKICAgICAgInNvY2lhbF9yZXZpc2lvbiI6ICI1NjIyM2U2ZGQxMTU5MTRhMzgzNWE3MTdlNmE5OTExYTJlNjEyNWE3YmZjNmZjNTlhYTViYTkxNjFmNGEyNDkzIgogICAgfSwKICAgIHsKICAgICAgImF1dGhvciI6IHsKICAgICAgICAiaWQiOiAiYTk1ZGM1ODMtNzk2Zi05ODIzLTllY2MtMTQ3OTk1YWY1NGFkIiwKICAgICAgICAiaGFuZGxlIjogInNvY2lhbGZpeHR1cmUxIiwKICAgICAgICAiYXZhdGFyX3BhdGgiOiAiYTk1ZGM1ODMtNzk2Zi05ODIzLTllY2MtMTQ3OTk1YWY1NGFkLzZlODUyY2E3LTNlMDYtM2NmNS00MGFlLWQxNTk3YjY4NmU0Ni5qcGciLAogICAgICAgICJkaXNwbGF5X25hbWUiOiAiU09PTSBcdWMwYWNcdWM2YTlcdWM3OTAiCiAgICAgIH0sCiAgICAgICJhdmF0YXIiOiB7CiAgICAgICAgImV0YWciOiAiYXZhdGFyLW9uZSIsCiAgICAgICAgInNpemUiOiAxMDAwLAogICAgICAgICJidWNrZXQiOiAicHJvZmlsZS1hdmF0YXJzIiwKICAgICAgICAidmVyc2lvbiI6ICJhMSIsCiAgICAgICAgIm9iamVjdF9pZCI6ICI2ZTg1MmNhNy0zZTA2LTNjZjUtNDBhZS1kMTU5N2I2ODZlNDYiLAogICAgICAgICJhdXRob3JpemVkIjogdHJ1ZSwKICAgICAgICAidXBkYXRlZF9hdCI6ICIyMDI2LTExLTE3VDIwOjM4OjI3LjAwODUyNiswOTowMCIsCiAgICAgICAgInN0b3JhZ2VfcGF0aCI6ICJhOTVkYzU4My03OTZmLTk4MjMtOWVjYy0xNDc5OTVhZjU0YWQvNmU4NTJjYTctM2UwNi0zY2Y1LTQwYWUtZDE1OTdiNjg2ZTQ2LmpwZyIsCiAgICAgICAgInZlcnNpb25faGFzaCI6ICI4NDk4M2I3YmQ1MDc4YmI1MTZiNWFmY2ZhYzdjZTRkNTA0NzY2NDE0ZWRjZTMwZmQyZjc2MGYwMWNmOGFjMWU1IgogICAgICB9LAogICAgICAicGhvdG9zIjogewogICAgICAgICJyb3dzIjogWwogICAgICAgICAgewogICAgICAgICAgICAiaWQiOiAiN2NjNmQwYjQtMjJlYS03NWM4LWE5YTItNWRmZDkwMGNhNDdjIiwKICAgICAgICAgICAgIm9iamVjdCI6IHsKICAgICAgICAgICAgICAiZXRhZyI6IG51bGwsCiAgICAgICAgICAgICAgInNpemUiOiAxMDAwLAogICAgICAgICAgICAgICJ2ZXJzaW9uIjogInYxIiwKICAgICAgICAgICAgICAib2JqZWN0X2lkIjogIjdjYzZkMGI0LTIyZWEtNzVjOC1hOWEyLTVkZmQ5MDBjYTQ3YyIsCiAgICAgICAgICAgICAgInVwZGF0ZWRfYXQiOiAiMjAyNi0xMS0xN1QyMDozODoyNy4wMDg1MjYrMDk6MDAiLAogICAgICAgICAgICAgICJ2ZXJzaW9uX2hhc2giOiAiNmY0NjZmZmY4N2ExMWEzYzQzZjU0MTk2MmJlYjRkYWYzZjllMzBiYTY3ZDY4YmMwZDljZTljM2FmNWQwODY1YiIKICAgICAgICAgICAgfSwKICAgICAgICAgICAgImNhcmRfaWQiOiAiZWJhNGY2MWYtNDhiZi0wYzE4LTgxMWYtNDk2ZWZhMTYwNTFjIiwKICAgICAgICAgICAgInNvcnRfb3JkZXIiOiAwLAogICAgICAgICAgICAic3RvcmFnZV9wYXRoIjogImE5NWRjNTgzLTc5NmYtOTgyMy05ZWNjLTE0Nzk5NWFmNTRhZC9lYmE0ZjYxZi00OGJmLTBjMTgtODExZi00OTZlZmExNjA1MWMvN2NjNmQwYjQtMjJlYS03NWM4LWE5YTItNWRmZDkwMGNhNDdjLmpwZyIKICAgICAgICAgIH0KICAgICAgICBdLAogICAgICAgICJidWNrZXQiOiAiYWN0aXZpdHktcGhvdG9zLWNhbmRpZGF0ZSIsCiAgICAgICAgImJhY2tpbmciOiAibmF0aXZlIiwKICAgICAgICAiY2FyZF9pZCI6ICJlYmE0ZjYxZi00OGJmLTBjMTgtODExZi00OTZlZmExNjA1MWMiLAogICAgICAgICJ2ZXJzaW9uIjogMiwKICAgICAgICAib3duZXJfaWQiOiAiYTk1ZGM1ODMtNzk2Zi05ODIzLTllY2MtMTQ3OTk1YWY1NGFkIiwKICAgICAgICAic291cmNlX2lkIjogImViYTRmNjFmLTQ4YmYtMGMxOC04MTFmLTQ5NmVmYTE2MDUxYyIsCiAgICAgICAgInZpZXdlcl9pZCI6ICIyMWY4ZjU1OS0yNjkyLTYzZmUtY2VhYi1jNzhiN2U3MmYzNjkiLAogICAgICAgICJjYW5vbmljYWxfaWQiOiAiMzc0ZGFiMGEtZmRhZS0xN2I3LThlNTctMGZiMjM3MWVjMTEwIiwKICAgICAgICAicmVsZWFzZV9yZWFkeSI6IHRydWUsCiAgICAgICAgInByb2ZpbGVfcmV2aXNpb24iOiAxLAogICAgICAgICJwcm9qZWN0aW9uX3JldmlzaW9uIjogMQogICAgICB9LAogICAgICAic29jaWFsIjogewogICAgICAgICJzdGF0ZSI6ICJyZWFkeSIsCiAgICAgICAgInJlY2VpcHQiOiB7CiAgICAgICAgICAiYmFja2luZyI6ICJuYXRpdmUiLAogICAgICAgICAgImNhcmRfaWQiOiAiZWJhNGY2MWYtNDhiZi0wYzE4LTgxMWYtNDk2ZWZhMTYwNTFjIiwKICAgICAgICAgICJ2ZXJzaW9uIjogMiwKICAgICAgICAgICJvd25lcl9pZCI6ICJhOTVkYzU4My03OTZmLTk4MjMtOWVjYy0xNDc5OTVhZjU0YWQiLAogICAgICAgICAgInNvdXJjZV9pZCI6ICJlYmE0ZjYxZi00OGJmLTBjMTgtODExZi00OTZlZmExNjA1MWMiLAogICAgICAgICAgInZpZXdlcl9pZCI6ICIyMWY4ZjU1OS0yNjkyLTYzZmUtY2VhYi1jNzhiN2U3MmYzNjkiLAogICAgICAgICAgImNhbm9uaWNhbF9pZCI6ICIzNzRkYWIwYS1mZGFlLTE3YjctOGU1Ny0wZmIyMzcxZWMxMTAiLAogICAgICAgICAgInJlYWRfc291cmNlcyI6IFsKICAgICAgICAgICAgewogICAgICAgICAgICAgICJzb3VyY2VfaWQiOiAiZWJhNGY2MWYtNDhiZi0wYzE4LTgxMWYtNDk2ZWZhMTYwNTFjIiwKICAgICAgICAgICAgICAic291cmNlX2tpbmQiOiAibmF0aXZlIgogICAgICAgICAgICB9CiAgICAgICAgICBdLAogICAgICAgICAgInJlbGVhc2VfcmVhZHkiOiB0cnVlLAogICAgICAgICAgIndyaXRlX2JhY2tpbmciOiAibmF0aXZlIiwKICAgICAgICAgICJzb3VyY2VfcmV2aXNpb24iOiAiYWFjZTM4NDQ5ZjVjYTc1NWU5MTE0M2IyYzNkMWQ4MGMiLAogICAgICAgICAgInByb2ZpbGVfcmV2aXNpb24iOiAxLAogICAgICAgICAgInByb2plY3Rpb25fcmV2aXNpb24iOiAxCiAgICAgICAgfSwKICAgICAgICAiY2hlZXJfY291bnQiOiAxLAogICAgICAgICJjb21tZW50X2NvdW50IjogMSwKICAgICAgICAibGF0ZXN0X2NvbW1lbnRfYXQiOiAiMjAyNi0xMS0xN1QyMDozODoyNi4wNDk3NjUrMDk6MDAiLAogICAgICAgICJ2aWV3ZXJfaGFzX2NoZWVyZWQiOiB0cnVlCiAgICAgIH0sCiAgICAgICJhbGxvd2VkIjogdHJ1ZSwKICAgICAgImNhcmRfaWQiOiAiZWJhNGY2MWYtNDhiZi0wYzE4LTgxMWYtNDk2ZWZhMTYwNTFjIiwKICAgICAgInN1bW1hcnkiOiB7CiAgICAgICAgInNwb3J0IjogInJ1bm5pbmciLAogICAgICAgICJjYXJkX2lkIjogImViYTRmNjFmLTQ4YmYtMGMxOC04MTFmLTQ5NmVmYTE2MDUxYyIsCiAgICAgICAgIm93bmVyX2lkIjogImE5NWRjNTgzLTc5NmYtOTgyMy05ZWNjLTE0Nzk5NWFmNTRhZCIsCiAgICAgICAgInJldmlzaW9uIjogMSwKICAgICAgICAiYWN0aXZpdHlfYXQiOiAiMjAyMC0wMS0wMVQwMDowMDowMCswOTowMCIsCiAgICAgICAgImNhbm9uaWNhbF9pZCI6ICIzNzRkYWIwYS1mZGFlLTE3YjctOGU1Ny0wZmIyMzcxZWMxMTAiLAogICAgICAgICJkaXN0YW5jZV9tZXRlcnMiOiAxMDAwLAogICAgICAgICJkdXJhdGlvbl9zZWNvbmRzIjogNjAwCiAgICAgIH0sCiAgICAgICJjYXJkX3ByZXZpZXciOiB7CiAgICAgICAgInN0YXRlIjogInVuYXZhaWxhYmxlIiwKICAgICAgICAidmVyc2lvbiI6IDEKICAgICAgfSwKICAgICAgImF1dGhvcl9yZXZpc2lvbiI6ICI3M2FmZmUzNjQwZGZhNzdkOWY5NWFiODFkMjg1MWI0YzdhZGJhNTAwMjMyOWVjMDEwZjdkZGQzYzQzM2FhYzJjIiwKICAgICAgInNvY2lhbF9yZXZpc2lvbiI6ICJjZTgxOTBmMmJhZWVkODQ5ZTg5ZGFhZTFhODJjMTQxNjNjZTIyYjQ3MDgwZDExM2UwNWExZTFhM2NkOTRjZjU1IgogICAgfQogIF0sCiAgInNjb3BlIjogImhvbWUiLAogICJ2ZXJzaW9uIjogMywKICAiaGFzX21vcmUiOiBmYWxzZSwKICAidmlld2VyX2lkIjogIjIxZjhmNTU5LTI2OTItNjNmZS1jZWFiLWM3OGI3ZTcyZjM2OSIsCiAgInJldHVybl9lcG9jaCI6IDksCiAgInJlbGVhc2VfcmVhZHkiOiB0cnVlLAogICJzYWZldHlfcmV2aXNpb24iOiA4LAogICJuZWVkc19wYWdlX3JlbG9hZCI6IHRydWUsCiAgImFjY291bnRfZ2VuZXJhdGlvbiI6IDcsCiAgIm1lbWJlcnNoaXBfcmV2aXNpb24iOiAiYzg2ZGUwZGYwMDg3ODUzYmNjMGM1MzM4YzRlMzZlZjE3MWFiNDZiOGFiNzA1MjdkMWNkNWVmODQxNDE4ZGIxZSIKfQ=="))
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(wire["rows"] as? [[String: Any]])
        let rows = try entries.map { entry -> AccountActivityFeedRow in
            let summary = try XCTUnwrap(entry["summary"] as? [String: Any])
            var row = try JSONDecoder().decode(AccountActivityFeedRow.self, from: JSONSerialization.data(withJSONObject: summary))
            row.readPolicy = .profileOnlyV2; return row
        }
        let viewer = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(wire["viewer_id"] as? String)))
        let context = FeedReturnBatchContext(viewerID: viewer, accountGeneration: try XCTUnwrap(wire["account_generation"] as? Int),
            safetyRevision: try XCTUnwrap(wire["safety_revision"] as? Int), returnEpoch: try XCTUnwrap(wire["return_epoch"] as? Int))
        let result = try FeedReturnBatchAdapter.validate(data, cardIDs: rows.map(\.cardID), loadedRows: rows,
            context: context, id: UUID(), expectedVersion: 3)
        XCTAssertEqual(result.grants.count, rows.count)
        XCTAssertTrue(result.grants.values.allSatisfy { $0.hasBatchCardPreview })
        XCTAssertTrue(result.grants.values.contains { $0.batchCardPreview != nil })
    }

    func testInitialReadyObserverTriggersOneFreshV3Grant() async throws {
        try await initialReadyObserverScenario(invalidateDuringRead: false)
    }
    func testInitialReadyObserverCannotPublishAfterAccountContextWithdrawn() async throws {
        try await initialReadyObserverScenario(invalidateDuringRead: true)
    }
    private func initialReadyObserverScenario(invalidateDuringRead: Bool) async throws {
        let rows = try sourceRows(), response = try JSONSerialization.data(withJSONObject: v3Object())
        var current: FeedReturnBatchContext? = nil
        let expected = context
        var gate = FeedInitialAuthorizationRetry(), calls = 0
        let store = FeedReturnBatchStore()
        let storeID = store.begin(context: expected)
        XCTAssertFalse(gate.authorizeNowOrDefer(ready: current != nil))
        let finished = expectation(description: "fresh batch finishes")
        let adapter = FeedReturnBatchAdapter(read: { _ in
            calls += 1
            if invalidateDuringRead { current = nil }
            return response
        }, current: { current }, expectedVersion: 3)
        let state = Feed66V3ObserverState()
        state.recheck = {
            guard gate.consumeIfReady(current != nil) else { return }
            Task { @MainActor in
                defer { finished.fulfill() }
                do {
                    let value = try await adapter.load(cardIDs: rows.map(\.cardID), loadedRows: rows,
                        context: expected, id: storeID)
                    XCTAssertTrue(store.publish(value, expectedID: storeID, merging: false))
                } catch { XCTAssertTrue(invalidateDuringRead) }
            }
        }
        let host = UIHostingController(rootView: Feed66V3ObserverView(state: state))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(calls, 0)
        current = expected; state.ready = true
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(calls, 0, "Build65-shaped missing observer: readiness alone leaves authorization unrequested")
        XCTAssertNotEqual(store.presentation?.phase, .ready)
        print("FEED66_OBSERVER_BASELINE: no-observer ready transition -> RPC 0, no grants")
        state.ready = false
        state.observerEnabled = true
        try await Task.sleep(for: .milliseconds(100))
        current = expected; state.ready = true
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(calls, 1)
        for _ in 0..<5 { NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 1)
        if invalidateDuringRead { XCTAssertNotEqual(store.presentation?.phase, .ready) }
        else { XCTAssertEqual(store.presentation?.phase, .ready); XCTAssertEqual(store.presentation?.grants.count, rows.count) }
        print("FEED66_OBSERVER_FIXED: production observer -> RPC 1, withdrawn=\(invalidateDuringRead), ready=\(store.presentation?.phase == .ready)")
    }

    private func v3Object() throws -> [String: Any] {
        var value = try object()
        value["version"] = 3
        var rows = try XCTUnwrap(value["rows"] as? [[String: Any]])
        for i in rows.indices { rows[i]["card_preview"] = ["version": 1, "state": "unavailable"] }
        rows[0]["card_preview"] = [
            "version": 1, "state": "ready", "serializer_version": 1,
            "post_id": "b72bfb07-64a6-8fde-0811-66f167172788",
            "owner_id": "a95dc583-796f-9823-9ecc-147995af54ad",
            "post_revision": "2026-01-01T00:00:00Z",
            "snapshot_revision": 1, "consent_revision": 1,
            "title": "합성 요약", "caption": NSNull(), "device_name": "합성 기기", "location_name": "합성 장소",
            "route_state": "ready", "authorized_route_geometry": [
                ["latitude": 37.5, "longitude": 127.0, "segment": 0],
                ["latitude": 37.501, "longitude": 127.001, "segment": 0]
            ]
        ]
        value["rows"] = rows; return value
    }
    private func validateV3(_ value: [String: Any]) throws -> FeedReturnBatchPresentation {
        let rows = try sourceRows()
        return try FeedReturnBatchAdapter.validate(JSONSerialization.data(withJSONObject: value),
            cardIDs: rows.map(\.cardID), loadedRows: rows, context: context, id: UUID(), expectedVersion: 3)
    }
    func testV3BatchCarriesCardPresentationWithoutSeparateRead() async throws {
        let value = try v3Object(), rows = try sourceRows()
        var calls = 0
        let adapter = FeedReturnBatchAdapter(read: { _ in
            calls += 1; return try JSONSerialization.data(withJSONObject: value)
        }, current: { self.context }, expectedVersion: 3)
        let result = try await adapter.load(cardIDs: rows.map(\.cardID), loadedRows: rows, context: context, id: UUID())
        XCTAssertEqual(calls, 1)
        let first = try XCTUnwrap(result.grants[rows[0].cardID])
        XCTAssertTrue(first.hasBatchCardPreview)
        XCTAssertNotNil(first.batchCardPreview)
        XCTAssertTrue(try XCTUnwrap(result.grants[rows[1].cardID]).hasBatchCardPreview)
        XCTAssertNil(result.grants[rows[1].cardID]?.batchCardPreview)
    }
    func testV3CannotDowngradeOrMixAnotherPostsPreview() throws {
        XCTAssertThrowsError(try validateV3(object()))
        XCTAssertThrowsError(try validate(v3Object()))
        var value = try v3Object()
        var rows = try XCTUnwrap(value["rows"] as? [[String: Any]])
        var preview = try XCTUnwrap(rows[0]["card_preview"] as? [String: Any])
        preview["post_id"] = UUID().uuidString; rows[0]["card_preview"] = preview; value["rows"] = rows
        XCTAssertThrowsError(try validateV3(value))
    }
    func testV3DeniedCardCannotRetainProjectionAndAccountChangeDiscardsResponse() async throws {
        var value = try v3Object()
        var rows = try XCTUnwrap(value["rows"] as? [[String: Any]])
        rows[0]["allowed"] = false; value["rows"] = rows
        XCTAssertThrowsError(try validateV3(value))
        let valid = try v3Object(), source = try sourceRows()
        var current: FeedReturnBatchContext? = context
        let adapter = FeedReturnBatchAdapter(read: { _ in
            current = nil; return try JSONSerialization.data(withJSONObject: valid)
        }, current: { current }, expectedVersion: 3)
        do {
            _ = try await adapter.load(cardIDs: source.map(\.cardID), loadedRows: source, context: context, id: UUID())
            XCTFail("A prior account response must not publish")
        } catch { }
    }

    func testMissingViewportGrantCoalescesFourWithoutRenewingExistingAuthority() throws {
        let store = FeedReturnBatchStore(), template = try sourceRows()[0]
        let rows = (0..<16).map { _ in AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: template.ownerID, sport: "running", activityAt: "2020-01-01T00:00:00Z", durationSeconds: 600, distanceMeters: 1000, revision: 1) }
        let id = store.begin(context: context)
        store.setViewport([rows[0].cardID, rows[1].cardID])
        XCTAssertEqual(store.targets(loadedRows: Array(rows.prefix(8))), Array(rows.prefix(4)).map(\.cardID), "Initial viewport must align with the same small group instead of immediately requesting its fourth row separately")
        XCTAssertTrue(store.publish(.init(id: id, context: context, phase: .ready, requested: Set(rows.prefix(8).map(\.cardID))), expectedID: id))
        store.setViewport([rows[7].cardID])
        XCTAssertEqual(store.targets(loadedRows: rows, missingOnly: true), Array(rows[8..<12]).map(\.cardID))
        XCTAssertTrue(store.publish(.init(id: id, context: context, phase: .ready, requested: Set(rows[8..<12].map(\.cardID))), expectedID: id, merging: true))
        store.setViewport([rows[9].cardID])
        XCTAssertTrue(store.targets(loadedRows: rows, missingOnly: true).isEmpty)
        store.invalidate()
        _ = store.begin(context: context)
        XCTAssertEqual(store.targets(loadedRows: rows, missingOnly: true), Array(rows[8...10]).map(\.cardID), "A new authority epoch must freshly verify its viewport, not reuse old requested IDs")
        store.setViewport([rows[15].cardID])
        XCTAssertTrue(store.targets(loadedRows: rows).allSatisfy { rows.map(\.cardID).contains($0) })
    }

    func testViewportTargetsIgnoreEagerRegistrationAndRetainReturnPosition() throws {
        let store = FeedReturnBatchStore()
        let template = try sourceRows()[0]
        let rows = (0..<80).map { _ in AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: template.ownerID, sport: "running", activityAt: "2020-01-01T00:00:00Z", durationSeconds: 600, distanceMeters: 1000, revision: 1) }
        for row in rows { store.register(cardID: row.cardID, visible: true) }
        store.setViewport([rows[35].cardID, rows[36].cardID])
        XCTAssertEqual(store.targets(loadedRows: rows), Array(rows[34...37]).map(\.cardID))
        store.setViewport([])
        store.invalidate()
        _ = store.begin(context: context)
        XCTAssertEqual(store.targets(loadedRows: rows), Array(rows[34...37]).map(\.cardID), "Returning to the app must reauthorize the real viewport, not every eager card")
        store.setViewport([UUID()])
        XCTAssertEqual(store.targets(loadedRows: rows), Array(rows.prefix(8)).map(\.cardID))
        store.setViewport(Set(rows.map(\.cardID)))
        XCTAssertEqual(store.targets(loadedRows: rows).count, 50)
    }

    func testPhotoVersionChangeRevokesOnlyAffectedCardAuthority() throws {
        let store = FeedReturnBatchStore(), rows = try sourceRows()
        let id = store.begin(context: context), fixture = try validate()
        let value = FeedReturnBatchPresentation(id: id, context: context, phase: .ready, grants: fixture.grants)
        XCTAssertTrue(store.publish(value, expectedID: id))
        let affected = try XCTUnwrap(value.grants[rows[0].cardID])
        let unaffected = try XCTUnwrap(value.grants[rows[1].cardID])
        let old = FeedLinkedCardAuthority(context: context, batchID: id, grantID: affected.id, row: affected.row)
        let kept = FeedLinkedCardAuthority(context: context, batchID: id, grantID: unaffected.id, row: unaffected.row)
        XCTAssertFalse(store.invalidateResource("unrelated-resource"))
        XCTAssertTrue(store.isCurrent(authority: old, context: context))
        XCTAssertTrue(store.invalidateResource(try XCTUnwrap(affected.photoObjects.keys.first)))
        XCTAssertFalse(store.isCurrent(authority: old, context: context), "Revoked resource must fail the live reference fence immediately")
        XCTAssertTrue(store.isCurrent(authority: kept, context: context), "One changed photo must not blank unrelated cards")
        XCTAssertEqual(store.presentation?.phase, .ready)
        XCTAssertNil(store.presentation?.grants[rows[0].cardID])
        store.invalidate()
        XCTAssertFalse(store.isCurrent(authority: kept, context: context), "Account/scene invalidation still closes every grant")
    }

    func testActualIsolatedDatabaseWireValidatesIndependentPermissions() throws {
        let snapshot = try validate()
        XCTAssertEqual(snapshot.grants.count, 2)
        XCTAssertFalse(snapshot.needsPageReload)
        for grant in snapshot.grants.values {
            XCTAssertEqual(grant.photos.count, 1)
            XCTAssertEqual(grant.photoObjects.count, 1)
            XCTAssertNotNil(grant.avatarObject?.cacheVersionToken)
            XCTAssertNotNil(grant.socialStatus)
        }
    }
    func testDeniedRowContainsNoOldPayload() throws {
        let rows = try sourceRows()
        let data = try changingFirst { $0 = ["card_id": rows[0].cardID.uuidString, "allowed": false] }
        let snapshot = try validate(data)
        XCTAssertTrue(snapshot.denied.contains(rows[0].cardID))
        XCTAssertNil(snapshot.grants[rows[0].cardID])
        guard case .denied = snapshot.cardAccess(rowID: rows[0].cardID) else { return XCTFail("Denied must not choose another thread") }
    }
    func testDeniedRowExtraPayloadRejected() throws {
        XCTAssertThrowsError(try validate(changingFirst { $0["allowed"] = false }))
    }
    func testViewerAndEpochEchoMismatchRejected() throws {
        for key in ["viewer_id", "account_generation", "safety_revision", "return_epoch", "scope", "release_ready"] {
            var value = try object()
            switch key {
            case "viewer_id": value[key] = UUID().uuidString
            case "scope": value[key] = "profile"
            case "release_ready": value[key] = false
            default: value[key] = 77
            }
            XCTAssertThrowsError(try validate(value), key)
        }
    }
    func testMissingOrDuplicateRowsRejected() throws {
        var value = try object(); let rows = try XCTUnwrap(value["rows"] as? [[String: Any]])
        value["rows"] = [rows[0]]; XCTAssertThrowsError(try validate(value))
        value["rows"] = [rows[0], rows[0]]; XCTAssertThrowsError(try validate(value))
    }
    func testUnexpectedHealthFieldsRejected() throws {
        let value = try changingFirst { row in
            var summary = row["summary"] as! [String: Any]; summary["heart_rate"] = 150; row["summary"] = summary
        }
        XCTAssertThrowsError(try validate(value))
    }
    func testNullMediaAndSocialAreUnavailableNotFallbackAuthority() throws {
        let old = try validate(); let rows = try sourceRows()
        let snapshot = try validate(changingFirst { row in
            row["photos"] = NSNull(); row["social"] = NSNull(); row["social_revision"] = NSNull(); row["avatar"] = NSNull()
        })
        let photo = try XCTUnwrap(old.grants[rows[0].cardID]?.photos.first)
        guard case .denied = snapshot.photoAccess(photo) else { return XCTFail("Null is not permission to query the old path") }
        XCTAssertNil(snapshot.grants[rows[0].cardID]?.socialStatus)
    }
    func testUnknownVersionAndUnknownSizeRequireFreshBytes() throws {
        for mode in ["version", "size"] {
            let value = try changingFirst { row in
                var photos = row["photos"] as! [String: Any]; var items = photos["rows"] as! [[String: Any]]
                var object = items[0]["object"] as! [String: Any]
                if mode == "size" { object["size"] = NSNull() }
                else { object["version"] = ""; object["etag"] = NSNull(); object["updated_at"] = NSNull(); object["version_hash"] = NSNull() }
                items[0]["object"] = object; photos["rows"] = items; row["photos"] = photos
            }
            let snapshot = try validate(value); let id = try sourceRows()[0].cardID
            XCTAssertNil(snapshot.grants[id]?.photoObjects.values.first?.cacheVersionToken)
        }
    }
    func testOversizedObjectAndWrongPhotoPathRejected() throws {
        for mode in ["size", "path"] {
            let value = try changingFirst { row in
                var photos = row["photos"] as! [String: Any]; var items = photos["rows"] as! [[String: Any]]
                if mode == "size" {
                    var object = items[0]["object"] as! [String: Any]; object["size"] = 99_000_000; items[0]["object"] = object
                } else { items[0]["storage_path"] = "elsewhere.jpg" }
                photos["rows"] = items; row["photos"] = photos
            }
            XCTAssertThrowsError(try validate(value), mode)
        }
    }
    func testPendingAndFailedSnapshotsNeverExposeResidentGrant() throws {
        var value = try validate(); let id = try sourceRows()[0].cardID
        value.phase = .pending
        guard case .pending = value.cardAccess(rowID: id) else { return XCTFail("Pending leaked cached content") }
        value.phase = .failed
        guard case .denied = value.cardAccess(rowID: id) else { return XCTFail("Failure leaked cached content") }
    }
    func testLateAccountChangedReadCannotPublish() async throws {
        let rows = try sourceRows(), data = fixture, initial = context
        var current: FeedReturnBatchContext? = initial
        let adapter = FeedReturnBatchAdapter(read: { _ in current = nil; return data }, current: { current })
        do { _ = try await adapter.load(cardIDs: rows.map(\.cardID), loadedRows: rows, context: initial, id: UUID()); XCTFail("Old response published") }
        catch { }
    }
    func testStoreRejectsLateEpochAndRetainsBoundedRequestedIDs() throws {
        let store = FeedReturnBatchStore(), rows = try sourceRows()
        let old = store.begin(context: context)
        var late = try validate(); late = .init(id: old, context: context, phase: .ready, grants: late.grants)
        store.invalidate()
        XCTAssertFalse(store.publish(late, expectedID: old))
        XCTAssertEqual(store.targets(loadedRows: rows).count, 2)
    }
    func testManualRetrySynchronouslyLatchesAndRejectsStaleContext() {
        let store = FeedReturnBatchStore()
        let id = store.begin(context: context)
        XCTAssertFalse(store.beginRetry(context: context), "Pending cannot queue retries")
        store.fail(expectedID: id)
        let wrong = FeedReturnBatchContext(viewerID: UUID(), accountGeneration: 7, safetyRevision: 8, returnEpoch: 9)
        XCTAssertFalse(store.beginRetry(context: wrong))
        XCTAssertTrue(store.beginRetry(context: context))
        XCTAssertFalse(store.beginRetry(context: context), "Repeated taps cannot enqueue duplicate retries")
        XCTAssertEqual(store.requestCount, 0, "State changes cannot auto-start requests")
    }

    func testCurrentAuthorizationRequiresBothAccountsAndActiveApplication() {
        XCTAssertEqual(FeedReturnBatchContext.authorizedCurrent(context, authViewerID: context.viewerID,
            transportViewerID: context.viewerID, applicationActive: true), context)
        for id in [nil, UUID()] as [UUID?] {
            XCTAssertNil(FeedReturnBatchContext.authorizedCurrent(context, authViewerID: id,
                transportViewerID: context.viewerID, applicationActive: true))
            XCTAssertNil(FeedReturnBatchContext.authorizedCurrent(context, authViewerID: context.viewerID,
                transportViewerID: id, applicationActive: true))
        }
        XCTAssertNil(FeedReturnBatchContext.authorizedCurrent(context, authViewerID: context.viewerID,
            transportViewerID: context.viewerID, applicationActive: false))
    }
    func testTransportLogoutDuringReadCannotPublish() async throws {
        let initial = context, data = fixture, rows = try sourceRows()
        var transportViewer: UUID? = context.viewerID
        let adapter = FeedReturnBatchAdapter(read: { _ in transportViewer = nil; return data }, current: {
            FeedReturnBatchContext.authorizedCurrent(initial, authViewerID: initial.viewerID,
                transportViewerID: transportViewer, applicationActive: true)
        })
        do { _ = try await adapter.load(cardIDs: rows.map(\.cardID), loadedRows: rows, context: initial, id: UUID()); XCTFail("Logged-out transport published") }
        catch { }
    }

    func testRepeatedPhotoCaptureEncodesAndCommitsOnlyOnce() async throws {
        let batch = try validate(), scope = FeedStaleSummaryCache.scope(batch.context)
        let grant = try XCTUnwrap(batch.grants.values.first { !$0.photos.isEmpty })
        let photo = try XCTUnwrap(grant.photos.first), object = try XCTUnwrap(grant.photoObjects[photo.cacheKey])
        let cache = FeedStaleSummaryCache(maximumAge: 60, observeSafety: false)
        cache.accept(batch)
        let initialRevision = cache.revision
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        for _ in 0..<100 { cache.capture(photo: photo, object: object, image: image, scope: scope) }
        XCTAssertEqual(cache.photoEncodingStarts, 1)
        XCTAssertEqual(cache.photoCaptureCoalesced, 99)
        for _ in 0..<100 where cache.photoCaptureCommits == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(cache.photoCaptureCommits, 1)
        XCTAssertEqual(cache.revision, initialRevision + 1)
        for _ in 0..<100 { cache.capture(photo: photo, object: object, image: image, scope: scope) }
        XCTAssertEqual(cache.photoCaptureReuseHits, 100)
        XCTAssertEqual(cache.photoEncodingStarts, 1)
        XCTAssertEqual(cache.photoCaptureCommits, 1)
        XCTAssertEqual(cache.revision, initialRevision + 1)
        print("FEED71_CAPTURE_WORK: 200 requests -> 1 encode, 1 commit, 99 coalesced, 100 reuse; previous path schedules 200 encodes")
    }
    func testRevokedPhotoCaptureCannotCommitAndCanRetryFreshVersion() async throws {
        let batch = try validate(), scope = FeedStaleSummaryCache.scope(batch.context)
        let grant = try XCTUnwrap(batch.grants.values.first { !$0.photos.isEmpty })
        let photo = try XCTUnwrap(grant.photos.first), object = try XCTUnwrap(grant.photoObjects[photo.cacheKey])
        let cache = FeedStaleSummaryCache(maximumAge: 60, observeSafety: false)
        cache.accept(batch)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        cache.capture(photo: photo, object: object, image: image, scope: scope)
        cache.revokePhoto(photo.cacheKey)
        let revokedRevision = cache.revision
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(cache.photoCaptureCommits, 0)
        XCTAssertEqual(cache.revision, revokedRevision)
        // A fresh grant is required after revocation before recapturing pixels.
        cache.accept(batch)
        cache.capture(photo: photo, object: object, image: image, scope: scope)
        for _ in 0..<100 where cache.photoCaptureCommits == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(cache.photoEncodingStarts, 2)
        XCTAssertEqual(cache.photoCaptureCommits, 1)
    }

    func testCachedLayoutOnlyReusesMatchingVerifiedGeometry() throws {
        let layout = try XCTUnwrap(FeedStaleSummaryLayout(width: 402, height: 712.5,
            dynamicType: "large", environment: "ko|ltr|regular|v1", contentRevision: "5|photoA"))
        XCTAssertEqual(layout.height(width: 402, dynamicType: "large", environment: "ko|ltr|regular|v1", contentRevision: "5|photoA"), 712.5)
        XCTAssertNil(layout.height(width: 800, dynamicType: "large", environment: "ko|ltr|regular|v1", contentRevision: "5|photoA"))
        XCTAssertNil(layout.height(width: 402, dynamicType: "accessibility3", environment: "ko|ltr|regular|v1", contentRevision: "5|photoA"))
        XCTAssertNil(layout.height(width: 402, dynamicType: "large", environment: "ar|rtl|regular|v1", contentRevision: "5|photoA"))
        XCTAssertNil(layout.height(width: 402, dynamicType: "large", environment: "ko|ltr|regular|v1", contentRevision: "6|photoA,photoB"))
        XCTAssertNil(FeedStaleSummaryLayout(width: .nan, height: 500, dynamicType: "large", environment: "test", contentRevision: "1"))
        XCTAssertNil(FeedStaleSummaryLayout(width: 402, height: .infinity, dynamicType: "large", environment: "test", contentRevision: "1"))
        XCTAssertEqual(try JSONDecoder().decode(FeedStaleSummaryLayout.self, from: JSONEncoder().encode(layout)), layout)
    }

    func testStoredHoursOldSummaryIsShownOnlyDuringIndependentGrace() throws {
        let cache = FeedStaleSummaryCache(maximumAge: 86_400, displayGrace: 5, observeSafety: false)
        let batch = try validate(), scope = FeedStaleSummaryCache.scope(batch.context)
        let id = try XCTUnwrap(batch.grants.keys.first)
        let verified = Date(timeIntervalSince1970: 100_000)
        cache.accept(batch, now: verified, uptime: 10_000)
        let opening = verified.addingTimeInterval(3_600)
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: opening, uptime: 13_600), "Stored bytes alone never open a display window")
        cache.beginDisplayWindow(scope: scope, returnEpoch: 2, now: opening, uptime: 13_600)
        XCTAssertNotNil(cache.snapshot(cardID: id, scope: scope, now: opening.addingTimeInterval(4.99), uptime: 13_604.99))
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: opening.addingTimeInterval(5), uptime: 13_605))
        cache.beginDisplayWindow(scope: scope, returnEpoch: 2, now: opening.addingTimeInterval(5), uptime: 13_605)
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: opening.addingTimeInterval(5.1), uptime: 13_605.1), "Duplicate refresh must not restart grace")
        cache.beginDisplayWindow(scope: scope, returnEpoch: 3, now: opening.addingTimeInterval(20), uptime: 13_620)
        XCTAssertNotNil(cache.snapshot(cardID: id, scope: scope, now: opening.addingTimeInterval(20.1), uptime: 13_620.1))
        cache.revoke([id])
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: opening.addingTimeInterval(20.2), uptime: 13_620.2))
    }

    func testDisplayGraceDoesNotExtendStorageLifetimeOrSurviveAccountChange() throws {
        let cache = FeedStaleSummaryCache(maximumAge: 3_600, displayGrace: 5, observeSafety: false)
        let batch = try validate(), scope = FeedStaleSummaryCache.scope(batch.context)
        let id = try XCTUnwrap(batch.grants.keys.first), verified = Date(timeIntervalSince1970: 100_000)
        cache.accept(batch, now: verified, uptime: 10_000)
        cache.beginDisplayWindow(scope: scope, returnEpoch: 1, now: verified.addingTimeInterval(3_599), uptime: 13_599)
        XCTAssertNotNil(cache.snapshot(cardID: id, scope: scope, now: verified.addingTimeInterval(3_599.5), uptime: 13_599.5))
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: verified.addingTimeInterval(3_600), uptime: 13_600), "Stored-age cap wins even if display grace remains")
        cache.beginDisplayWindow(scope: scope, returnEpoch: 2, now: verified.addingTimeInterval(4_000), uptime: 14_000)
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: verified.addingTimeInterval(4_000), uptime: 14_000))
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        let other = FeedStaleSummaryScope(viewerID: UUID(), generation: scope.generation,
            safetyRevision: scope.safetyRevision, policyVersion: scope.policyVersion)
        cache.beginDisplayWindow(scope: other, returnEpoch: 1, now: verified, uptime: 10_000)
        XCTAssertTrue(cache.allSnapshots(scope: other, now: verified, uptime: 10_000).isEmpty)
    }

    func testStaleSummaryHardCapAndScopeNeverGrantAuthority() throws {
        let cache = FeedStaleSummaryCache(maximumAge: 5, observeSafety: false)
        let batch = try validate(), id = try XCTUnwrap(batch.grants.keys.first)
        let scope = FeedStaleSummaryCache.scope(batch.context)
        let now = Date(timeIntervalSince1970: 1000)
        cache.accept(batch, now: now, uptime: 10)
        XCTAssertNotNil(cache.snapshot(cardID: id, scope: scope, now: now.addingTimeInterval(4.9), uptime: 14.9))
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: now.addingTimeInterval(5), uptime: 15))
        XCTAssertNil(cache.snapshot(cardID: id, scope: .init(viewerID: UUID(), generation: scope.generation,
            safetyRevision: scope.safetyRevision, policyVersion: 1), now: now, uptime: 10))
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: now.addingTimeInterval(-1), uptime: 11))
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: now.addingTimeInterval(1), uptime: 1))
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: now.addingTimeInterval(1), uptime: 14))
        cache.revoke([id])
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: now.addingTimeInterval(1), uptime: 11))
    }

    func testStaleSummaryRequiresOptInAndDoesNotCopyPrivateDetail() throws {
        let batch = try validate(), id = try XCTUnwrap(batch.grants.keys.first)
        let scope = FeedStaleSummaryCache.scope(batch.context), now = Date(timeIntervalSince1970: 100)
        let disabled = FeedStaleSummaryCache(maximumAge: nil, observeSafety: false)
        disabled.accept(batch, now: now, uptime: 10)
        XCTAssertEqual(disabled.count, 0)
        let cache = FeedStaleSummaryCache(maximumAge: 5, observeSafety: false)
        cache.accept(batch, now: now, uptime: 10)
        let entry = try XCTUnwrap(cache.snapshot(cardID: id, scope: scope, now: now, uptime: 10))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        for key in ["caption", "body", "location", "route", "heartRate", "recovery", "insight", "comparison"] {
            XCTAssertNil(json[key])
        }
        var failed = batch; failed.phase = .failed
        cache.accept(failed, now: now.addingTimeInterval(4), uptime: 14)
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope, now: now.addingTimeInterval(5), uptime: 15),
            "A failed response must never extend last successful authorization")
        cache.clear(); XCTAssertEqual(cache.count, 0)
    }

    func testStorageInfoWireShapeAndBatchShareVersionWithoutInvalidationLoop() async throws {
        let object = try XCTUnwrap(try validate().grants.values.first?.photoObjects.values.first)
        // Actual Storage info shape has last_modified, not SQL updated_at.
        let bytes = try JSONSerialization.data(withJSONObject: [
            "id": object.objectID.uuidString.lowercased(), "name": object.path,
            "version": object.version, "size": try XCTUnwrap(object.size),
            "etag": object.etag ?? "", "last_modified": "2026-11-14T08:28:47Z"
        ])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let info = try decoder.decode(FileObjectV2.self, from: bytes)
        XCTAssertNil(info.updatedAt); XCTAssertNotNil(info.lastModified)
        let infoVersion = FeedReturnStorageObject.cacheVersionToken(objectID: info.id,
            version: info.version, etag: info.etag, updatedAt: info.updatedAt, size: info.size)
        XCTAssertEqual(object.cacheVersionToken, infoVersion)
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 100, maximumCount: 4)
        let scope = SOOMMediaCacheScope(viewerID: context.viewerID, accountGeneration: 7, safetyRevision: 8)
        var downloads = 0, changes = 0, authorizations = 0
        cache.onResourceVersionChanged = { _, _ in changes += 1 }
        for (index, token) in [object.cacheVersionToken, infoVersion, object.cacheVersionToken, infoVersion].enumerated() {
            let value = try await cache.value(for: object.path, scope: scope,
                presentationEpoch: "visit-\(index)", reusePresentation: false, requestOwner: index.isMultiple(of: 2) ? "feed" : "gallery",
                authorize: { authorizations += 1; return token }, load: { downloads += 1; return (42, 1) })
            XCTAssertEqual(value, 42)
        }
        XCTAssertEqual(authorizations, 4, "Each independent host must still authorize")
        XCTAssertEqual(downloads, 1); XCTAssertEqual(changes, 0)
    }

    func testStorageVersionDoesNotChangeWithTransportTimestampPrecision() throws {
        let id = UUID().uuidString, version = UUID().uuidString.lowercased()
        let sqlDate = Date(timeIntervalSince1970: 1794357244.612573)
        let storageDate = Date(timeIntervalSince1970: 1794357244.612)
        let batch = FeedReturnStorageObject.cacheVersionToken(objectID: id, version: version,
            etag: "\"same-content\"", updatedAt: sqlDate, size: 1611809)
        let storage = FeedReturnStorageObject.cacheVersionToken(objectID: id.lowercased(), version: version,
            etag: "\"same-content\"", updatedAt: storageDate, size: 1611809)
        XCTAssertEqual(batch, storage, "Transport timestamp precision must not revoke an unchanged Storage version")
        XCTAssertEqual(batch, FeedReturnStorageObject.cacheVersionToken(objectID: id, version: version,
            etag: nil, updatedAt: nil, size: 1611809), "Optional metadata absence must not supersede the authoritative version")
    }

    func testStorageVersionStillRejectsReplacementAndSizeMismatch() throws {
        let id = UUID().uuidString, version = UUID().uuidString
        func token(_ object: String, _ v: String, _ size: Int) -> String? {
            FeedReturnStorageObject.cacheVersionToken(objectID: object, version: v,
                etag: "same", updatedAt: Date(timeIntervalSince1970: 100), size: size)
        }
        let original = token(id, version, 100)
        XCTAssertNotEqual(original, token(id, UUID().uuidString, 100))
        XCTAssertNotEqual(original, token(UUID().uuidString, version, 100))
        XCTAssertNotEqual(original, token(id, version, 101))
        XCTAssertNil(token(id, version, 0))
    }

    func testStorageInfoAndBatchUseIdenticalObjectVersionTokens() throws {
        let object = try XCTUnwrap(try validate().grants.values.first?.photoObjects.values.first)
        XCTAssertEqual(object.cacheVersionToken, FeedReturnStorageObject.cacheVersionToken(
            objectID: object.objectID.uuidString.uppercased(), version: object.version,
            etag: object.etag, updatedAt: object.updatedAt, size: object.size))
        for invalidID in [nil, "", "not-an-object-id"] as [String?] {
            XCTAssertNil(FeedReturnStorageObject.cacheVersionToken(objectID: invalidID, version: "v1",
                etag: "tag", updatedAt: Date(), size: 100))
        }
    }

    func testCapturedBatchFenceRejectsOldGrantBeforeEnvironmentPropagation() throws {
        let store = FeedReturnBatchStore(), capturedContext = context
        let oldID = store.begin(context: context)
        var value = try validate()
        value = .init(id: oldID, context: context, phase: .ready, grants: value.grants)
        XCTAssertTrue(store.publish(value, expectedID: oldID))
        let oldEnvironmentReceipt = value
        let fence: (UUID) -> Bool = { store.isCurrent(id: $0, context: capturedContext) }
        XCTAssertTrue(fence(oldEnvironmentReceipt.id))
        let newID = store.begin(context: context)
        XCTAssertFalse(fence(oldEnvironmentReceipt.id), "Reference-store fence must close old closures synchronously")
        XCTAssertFalse(fence(newID), "Pending is not authorization")
        let fresh = FeedReturnBatchPresentation(id: newID, context: context, phase: .ready, grants: value.grants)
        XCTAssertTrue(store.publish(fresh, expectedID: newID))
        XCTAssertTrue(fence(newID)); XCTAssertFalse(fence(oldEnvironmentReceipt.id))
        XCTAssertFalse(store.isCurrent(id: newID, context: nil))
        store.invalidate(); XCTAssertFalse(fence(newID))
    }

    func testReadyMergeMembershipDriftClosesOldGrantsBeforeReload() throws {
        let store = FeedReturnBatchStore()
        let id = store.begin(context: context)
        var ready = try validate()
        ready = .init(id: id, context: context, phase: .ready, grants: ready.grants)
        XCTAssertTrue(store.publish(ready, expectedID: id))
        let cardID = try XCTUnwrap(ready.grants.keys.first)
        guard case .authorized = store.presentation?.cardAccess(rowID: cardID) else { return XCTFail("Fixture not ready") }
        var drift = ready; drift.needsPageReload = true
        store.invalidateForMembershipChange(drift)
        guard case .pending = store.presentation?.cardAccess(rowID: cardID) else { return XCTFail("Old grant visible during page reload") }
        XCTAssertFalse(store.publish(ready, expectedID: id), "Late old request cannot restore pre-drift authority")
    }

    func testSamePathRecreatedObjectNeverReusesPriorIdentity() async throws {
        let original = FeedReturnStorageObject(bucket: "workout-photos", path: "same.jpg", objectID: UUID(),
            version: "v1", etag: "same", updatedAt: Date(timeIntervalSince1970: 1), size: 1000, versionHash: nil)
        let recreated = FeedReturnStorageObject(bucket: original.bucket, path: original.path, objectID: UUID(),
            version: original.version, etag: original.etag, updatedAt: original.updatedAt, size: original.size, versionHash: nil)
        XCTAssertNotEqual(original.cacheVersionToken, recreated.cacheVersionToken)
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 20, maximumCount: 2)
        let scope = SOOMMediaCacheScope(viewerID: context.viewerID, accountGeneration: 7, safetyRevision: 8)
        var downloads = 0
        for (index, object) in [original, recreated, recreated].enumerated() {
            _ = try await cache.value(for: original.path, scope: scope, presentationEpoch: String(index),
                authorize: { object.cacheVersionToken }, load: { downloads += 1; return (downloads, 1) })
        }
        XCTAssertEqual(downloads, 2, "Recreated object downloads once; same fresh-authorized identity then reuses")
        let unknown = FeedReturnStorageObject(bucket: original.bucket, path: original.path, objectID: original.objectID,
            version: "", etag: nil, updatedAt: nil, size: 1000, versionHash: nil)
        XCTAssertNil(unknown.cacheVersionToken, "Object identity alone is not a content version")
    }

    func testFreshBatchReauthorizesPixelsWithoutSecondDownload() async throws {
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 20, maximumCount: 2)
        let scope = SOOMMediaCacheScope(viewerID: context.viewerID, accountGeneration: 7, safetyRevision: 8)
        var authorizations = 0, downloads = 0
        for epoch in ["first-batch", "second-batch"] {
            let value = try await cache.value(for: "photo", scope: scope, presentationEpoch: epoch,
                authorize: { authorizations += 1; return "v1" }, load: { downloads += 1; return (5, 1) })
            XCTAssertEqual(value, 5)
        }
        XCTAssertEqual(authorizations, 2)
        XCTAssertEqual(downloads, 1)
        cache.invalidateResource("photo")
        XCTAssertEqual(cache.entryCount, 0)
    }
}

@MainActor private final class Feed66V3ObserverState: ObservableObject {
    @Published var ready = false
    @Published var observerEnabled = false
    var recheck: () -> Void = {}
}
private struct Feed66V3ObserverView: View {
    @ObservedObject var state: Feed66V3ObserverState
    var body: some View {
        if state.observerEnabled {
            Text("Synthetic v3 readiness")
                .modifier(FeedInitialAuthorizationReadinessObserver(ready: state.ready, recheck: state.recheck))
        } else {
            Text("Synthetic legacy readiness")
        }
    }
}

extension FeedReturnBatchAdapterTests {
    @MainActor func testEarlyCacheDeadlineCannotRenewWhenLiveFeedTakesOver() throws {
        let cache = FeedStaleSummaryCache(maximumAge: 86_400, displayGrace: 5, observeSafety: false)
        let batch = try validate(), scope = FeedStaleSummaryCache.scope(batch.context)
        let id = try XCTUnwrap(batch.grants.keys.first)
        let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
        cache.accept(batch, now: now, uptime: uptime)
        cache.beginEarlyDisplay(scope: scope)
        XCTAssertNotNil(cache.snapshot(cardID: id, scope: scope))
        // A newly-mounted verified feed uses a different returnEpoch, but must
        // continue the original early-display deadline, not receive another 5s.
        cache.beginDisplayWindow(scope: scope, returnEpoch: 999,
            now: now.addingTimeInterval(4), uptime: uptime + 4)
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope,
            now: now.addingTimeInterval(6), uptime: uptime + 6))
        cache.revoke([id])
        XCTAssertNil(cache.snapshot(cardID: id, scope: scope))
    }
}

extension FeedReturnBatchAdapterTests {
    @MainActor func testChromeMetadataLearnsAfterOldCacheAndMatchingEntryLeaseDoesNotResize() throws {
        let cache = FeedStaleSummaryCache(maximumAge: 86_400, displayGrace: 5, observeSafety: false)
        let batch = try validate(), scope = FeedStaleSummaryCache.scope(batch.context)
        cache.accept(batch)
        cache.beginEarlyDisplay(scope: scope)
        XCTAssertNil(cache.chromeReservation(viewerID: scope.viewerID, width: 390, dynamicType: "large", environment: "fixture"))
        let first = try XCTUnwrap(FeedChromeLayout(width: 390, dynamicType: "large", environment: "fixture", height: 286.5))
        cache.captureChrome(first, viewerID: scope.viewerID)
        XCTAssertEqual(cache.chromeReservation(viewerID: scope.viewerID, width: 390, dynamicType: "large", environment: "fixture")?.height, 286.5)
        let later = try XCTUnwrap(FeedChromeLayout(width: 390, dynamicType: "large", environment: "fixture", height: 600))
        cache.captureChrome(later, viewerID: scope.viewerID)
        XCTAssertEqual(cache.chromeReservation(viewerID: scope.viewerID, width: 390, dynamicType: "large", environment: "fixture")?.height, 286.5,
            "Fresh larger chrome must use the reachable overflow region, not move the first card")
        XCTAssertNil(cache.chromeReservation(viewerID: UUID(), width: 390, dynamicType: "large", environment: "fixture"))
        XCTAssertNil(cache.chromeReservation(viewerID: scope.viewerID, width: 430, dynamicType: "large", environment: "fixture"))
        XCTAssertNil(cache.chromeReservation(viewerID: scope.viewerID, width: 390, dynamicType: "accessibility3", environment: "fixture"))
        XCTAssertNil(FeedChromeLayout(width: 390, dynamicType: "large", environment: "fixture", height: .infinity))
        cache.clear()
        XCTAssertNil(cache.chromeReservation(viewerID: scope.viewerID, width: 390, dynamicType: "large", environment: "fixture"))
    }
}
