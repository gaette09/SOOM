import Contacts
import CryptoKit
import Foundation

/// Invoked only by an explicit Connect action after validated server readiness/consent.
/// Does not transmit data. Names, notes, phone numbers and photos are never requested.
@MainActor
final class ContactDiscoveryDeviceReader {
    enum Failure: Error { case notReady, accountChanged, permissionDenied, tooManyContacts }
    private let store: CNContactStore
    init(store: CNContactStore = CNContactStore()) { self.store = store }

    func permission() -> ContactDiscoveryPermission {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        #if os(iOS)
        if #available(iOS 18.0, *), status == .limited { return .limited }
        #endif
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        default: return .restricted
        }
    }

    func requestPermissionAfterExplicitConnect(receipt: ContactDiscoveryReceipt,
        accountID: UUID, requestGeneration: Int,
        currentContext: () -> (UUID?, Int)) async throws -> ContactDiscoveryPermission {
        let before = currentContext()
        try receipt.validate(expectedAccount: accountID, currentAccount: before.0,
            requestedGeneration: requestGeneration, currentGeneration: before.1)
        guard receipt.consentReady, receipt.matchingReady, receipt.decision == "accepted" else { throw Failure.notReady }
        if permission() == .notDetermined { _ = try await store.requestAccess(for: .contacts) }
        let after = currentContext()
        guard after.0 == accountID, after.1 == requestGeneration else { throw Failure.accountChanged }
        return permission()
    }

    func tokensAfterExplicitConnect(receipt: ContactDiscoveryReceipt, accountID: UUID,
        requestGeneration: Int, currentContext: () -> (UUID?, Int)) throws -> [String] {
        let context = currentContext()
        try receipt.validate(expectedAccount: accountID, currentAccount: context.0,
            requestedGeneration: requestGeneration, currentGeneration: context.1)
        guard receipt.consentReady, receipt.matchingReady, receipt.decision == "accepted" else { throw Failure.notReady }
        guard permission().permitsSelectedContacts else { throw Failure.permissionDenied }
        let request = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])
        var tokens = Set<String>()
        var exceeded = false
        try store.enumerateContacts(with: request) { contact, stop in
            for email in contact.emailAddresses {
                if let token = ContactDiscoveryEmailToken.make(String(email.value)) { tokens.insert(token) }
            }
            if tokens.count > 100 { exceeded = true; stop.pointee = true }
        }
        guard !exceeded else { throw Failure.tooManyContacts }
        let after = currentContext()
        guard after.0 == accountID, after.1 == requestGeneration else { throw Failure.accountChanged }
        return tokens.sorted()
    }
}

enum ContactDiscoveryEmailToken {
    /// A reversible-by-guessing pseudonym, NOT anonymization or encryption.
    static func make(_ value: String) -> String? {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.utf8.count <= 254, email.unicodeScalars.allSatisfy({ $0.isASCII }),
              email.range(of: #"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$"#, options: .regularExpression) != nil else { return nil }
        return SHA256.hash(data: Data(("soom-contact-v1:email:" + email).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
