import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FamiloqCore

final class InvitationServiceClientTests: XCTestCase {
    final class StubHTTP: HTTPClient {
        var status: Int
        var body: String
        var fail = false
        private(set) var lastRequest: URLRequest?

        init(status: Int, body: String) {
            self.status = status
            self.body = body
        }

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            lastRequest = request
            if fail { throw URLError(.notConnectedToInternet) }
            return (Data(body.utf8), status)
        }
    }

    private let base = URL(string: "https://api.example.com")!

    func testRedeemSendsNormalisedCodeAndParsesSession() async throws {
        let http = StubHTTP(status: 200, body: #"{"status":"active","token":"t1","expiresAt":1790000000,"alreadyActivated":false}"#)
        let client = InvitationServiceClient(baseURL: base, http: http)
        let session = try await client.redeem(code: "mbf7 k92x-4qp7", identityToken: "apple", nonce: "n")
        XCTAssertEqual(session.token, "t1")
        XCTAssertEqual(http.lastRequest?.url?.absoluteString, "https://api.example.com/v1/invitations/redeem")
        XCTAssertEqual(http.lastRequest?.httpMethod, "POST")
        let sent = try JSONSerialization.jsonObject(with: http.lastRequest!.httpBody!) as! [String: String]
        XCTAssertEqual(sent["code"], "MBF7K92X4QP7")
        XCTAssertEqual(sent["identityToken"], "apple")
    }

    func testServerErrorsAreMapped() async {
        let cases: [(Int, String, InvitationServiceClient.ServiceError)] = [
            (404, "invalid_code", .invalidCode),
            (410, "expired", .expired),
            (409, "used", .used),
            (410, "revoked", .revoked),
            (403, "account_revoked", .accountRevoked),
            (404, "not_activated", .notActivated),
            (429, "rate_limited", .rateLimited)
        ]
        for (status, code, expected) in cases {
            let http = StubHTTP(status: status, body: #"{"error":"\#(code)","message":"x"}"#)
            do {
                _ = try await InvitationServiceClient(baseURL: base, http: http).redeem(code: "x", identityToken: "t", nonce: "n")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? InvitationServiceClient.ServiceError, expected)
            }
        }
    }

    func testOffline() async {
        let http = StubHTTP(status: 200, body: "{}")
        http.fail = true
        do {
            _ = try await InvitationServiceClient(baseURL: base, http: http).refresh(token: "t")
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? InvitationServiceClient.ServiceError, .offline)
        }
    }

    func testRefreshSendsBearer() async throws {
        let http = StubHTTP(status: 200, body: #"{"status":"active","token":"t2","expiresAt":1}"#)
        _ = try await InvitationServiceClient(baseURL: base, http: http).refresh(token: "abc")
        XCTAssertEqual(http.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
    }
}

final class FamilyInvitationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testValidInvitation() {
        let terms = FamilyInvitationTerms(expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(FamilyInvitationRules.status(of: terms, now: now, activeMembers: 2, maxMembers: 6), .valid)
    }

    func testExpiredFamilyInvitation() {
        let terms = FamilyInvitationTerms(expiresAt: now.addingTimeInterval(-1))
        XCTAssertEqual(FamilyInvitationRules.status(of: terms, now: now, activeMembers: 2, maxMembers: 6), .expired)
    }

    func testUsedRevokedAndFull() {
        let future = now.addingTimeInterval(3600)
        XCTAssertEqual(FamilyInvitationRules.status(of: .init(expiresAt: future, maxUses: 1, uses: 1), now: now, activeMembers: 1, maxMembers: 6), .usedUp)
        XCTAssertEqual(FamilyInvitationRules.status(of: .init(expiresAt: future, isRevoked: true), now: now, activeMembers: 1, maxMembers: 6), .revoked)
        XCTAssertEqual(FamilyInvitationRules.status(of: .init(expiresAt: future), now: now, activeMembers: 6, maxMembers: 6), .familyFull)
    }
}
