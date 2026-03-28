import BackendContracts
import Foundation
import Testing

struct BackendContractMirrorTests {
    @Test
    func `identity DTOs decode from generated backend fixtures`() throws {
        let appleAuth: AppleAuthRequestDTO = try decodeFixture(named: "AppleAuthRequestDTO")
        let session: SessionDTO = try decodeFixture(named: "SessionDTO")
        let credential: CredentialStatusDTO = try decodeFixture(named: "CredentialStatusDTO")

        #expect(appleAuth.deviceID == "device_01")
        #expect(appleAuth.authorizationCode == "auth-code")
        #expect(session.deviceID == "device_01")
        #expect(session.user.appleSubject == "apple-subject-01")
        #expect(credential.state == .valid)
    }

    @Test
    func `connection DTOs decode from generated backend fixtures`() throws {
        let connection: ConnectionCheckDTO = try decodeFixture(named: "ConnectionCheckDTO")

        #expect(connection.backend == .healthy)
        #expect(connection.auth == .missing)
        #expect(connection.openaiCredential == .missing)
        #expect(connection.latencyMilliseconds == 18)
    }

    @Test
    func `run DTOs decode nested projection snapshots from generated backend fixtures`() throws {
        let runSummary: RunSummaryDTO = try decodeFixture(named: "RunSummaryDTO")
        let runEvent: RunEventDTO = try decodeFixture(named: "RunEventDTO")
        let syncEnvelope: SyncEnvelopeDTO = try decodeFixture(named: "SyncEnvelopeDTO")

        #expect(runSummary.lastEventCursor == "cur_00000000000000000001")
        #expect(runEvent.kind == .messageCreated)
        #expect(runEvent.message?.role == .user)
        #expect(runEvent.run?.status == .queued)
        #expect(runEvent.conversation?.lastRunID == "run_01")
        #expect(syncEnvelope.nextCursor == "cur_00000000000000000002")
        #expect(syncEnvelope.events.first?.kind == .messageCreated)
    }

    @Test
    func `request DTOs encode with backend coding keys`() throws {
        let request = AppleAuthRequestDTO(
            identityToken: "identity-token",
            authorizationCode: "auth-code",
            deviceID: "device_01",
            email: nil,
            givenName: nil,
            familyName: nil
        )

        let encoded = try JSONEncoder.backendFixture.encode(request)
        let payload = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: String]
        )

        #expect(payload["deviceId"] == "device_01")
        #expect(payload["authorizationCode"] == "auth-code")
        #expect(payload["identityToken"] == "identity-token")
    }
}

private func decodeFixture<T: Decodable>(named key: String) throws -> T {
    let fixtures = try loadFixtures()
    let object = try #require(fixtures[key])
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder.backendFixture.decode(T.self, from: data)
}

private func loadFixtures(filePath: StaticString = #filePath) throws -> [String: Any] {
    var repositoryRoot = URL(fileURLWithPath: "\(filePath)")
    for _ in 0 ..< 5 {
        repositoryRoot.deleteLastPathComponent()
    }

    let fixturesURL = repositoryRoot.appending(path: "packages/backend-contracts/generated/fixtures.json")
    let data = try Data(contentsOf: fixturesURL)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private extension JSONDecoder {
    static let backendFixture: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let backendFixture: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
