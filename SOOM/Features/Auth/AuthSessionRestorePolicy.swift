import Foundation

enum AuthSessionRestorePolicy: String, Codable, Equatable {
    case preferRemoteIfAvailable
    case localFirst
    case remoteOnlyFuture
}
