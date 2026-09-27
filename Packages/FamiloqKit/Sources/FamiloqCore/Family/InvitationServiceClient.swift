import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the Familoq invitation service (server/invitation-service).
/// Handles Level 1 access only: may this Apple ID use Familoq at all?
/// Family data never goes through this service.
public struct InvitationServiceClient {
    public struct Session: Codable, Equatable, Sendable {
        public let status: String
        public let token: String
        /// Seconds since 1970.
        public let expiresAt: Double
        public let alreadyActivated: Bool?

        public init(status: String, token: String, expiresAt: Double, alreadyActivated: Bool? = nil) {
            self.status = status
            self.token = token
            self.expiresAt = expiresAt
            self.alreadyActivated = alreadyActivated
        }
    }

    public enum ServiceError: Error, Equatable {
        case invalidCode
        case expired
        case used
        case revoked
        case accountRevoked
        case notActivated
        case invalidAppleToken
        case invalidSession
        case rateLimited
        case missingFields
        case offline
        case server(String)

        /// Text for the user.
        public var message: String {
            switch self {
            case .invalidCode: return "This invitation code is not valid. Please check it and try again."
            case .expired: return "This invitation has expired. Please ask for a new one."
            case .used: return "This invitation has already been used."
            case .revoked: return "This invitation is no longer valid."
            case .accountRevoked: return "Access to Familoq has been turned off for this Apple ID."
            case .notActivated: return "This Apple ID has not been activated yet. Please enter your invitation code."
            case .invalidAppleToken: return "Sign in with Apple could not be confirmed. Please try again."
            case .invalidSession: return "Please sign in with Apple again."
            case .rateLimited: return "Too many attempts. Please wait a while and try again."
            case .missingFields: return "Please fill in all fields."
            case .offline: return "No connection to the Familoq service. Check your internet connection."
            case .server(let text): return text
            }
        }

        static func from(code: String?, message: String?, status: Int) -> ServiceError {
            switch code {
            case "invalid_code": return .invalidCode
            case "expired": return .expired
            case "used": return .used
            case "revoked": return .revoked
            case "account_revoked": return .accountRevoked
            case "not_activated": return .notActivated
            case "invalid_apple_token": return .invalidAppleToken
            case "invalid_session": return .invalidSession
            case "rate_limited": return .rateLimited
            case "missing_fields": return .missingFields
            default: return .server(message ?? "The Familoq service answered with status \(status).")
            }
        }
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let message: String?
    }

    public let baseURL: URL
    private let http: HTTPClient

    public init(baseURL: URL, http: HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.http = http
    }

    /// Level 1: redeem an App Invitation for this Apple ID.
    public func redeem(code: String, identityToken: String, nonce: String) async throws -> Session {
        try await post("v1/invitations/redeem", body: [
            "code": InvitationCode.normalize(code),
            "identityToken": identityToken,
            "nonce": nonce
        ])
    }

    /// Reinstall / new device: an already-activated Apple ID signs in again.
    public func restore(identityToken: String, nonce: String) async throws -> Session {
        try await post("v1/session/apple", body: ["identityToken": identityToken, "nonce": nonce])
    }

    /// Periodic check; fails with `.accountRevoked` if access was turned off.
    public func refresh(token: String) async throws -> Session {
        try await post("v1/session/refresh", body: [:], bearer: token)
    }

    public func requestInvitation(name: String, contact: String, message: String) async throws {
        let _: [String: String] = try await post("v1/invitation-requests", body: [
            "name": name, "contact": contact, "message": message
        ])
    }

    private func post<T: Decodable>(_ path: String, body: [String: String], bearer: String? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let status: Int
        do {
            (data, status) = try await http.send(request)
        } catch {
            throw ServiceError.offline
        }
        guard (200..<300).contains(status) else {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw ServiceError.from(code: parsed?.error, message: parsed?.message, status: status)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ServiceError.server("Unexpected answer from the Familoq service.")
        }
    }
}
