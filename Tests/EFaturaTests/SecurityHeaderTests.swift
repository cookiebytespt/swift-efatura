import Crypto
import CryptoExtras
import Foundation
import Testing

@testable import EFatura

@Suite struct SecurityHeaderTests {
    let privateKey = try! _RSA.Encryption.PrivateKey(unsafePEMRepresentation: Fixtures.privateKeyPEM)
    let credentials = EFaturaCredentials(username: "599999993/37", password: "s3nha çom acentos & <símbolos>")
    let now = Date(timeIntervalSince1970: 1_794_531_424.123)  // 2026-11-13T00:57:04.123Z

    /// Does what AT's side does: recover the session key, then the two fields.
    private func open(_ header: SecurityHeader) throws -> (password: String, created: String, key: Data) {
        let key = try privateKey.decrypt(Data(base64Encoded: header.nonce)!, padding: ._WEAK_AND_INSECURE_PKCS_V1_5)
        func decrypt(_ base64: String) throws -> String {
            var bytes = Array(Data(base64Encoded: base64)!)
            #expect(bytes.count % 16 == 0)
            for start in stride(from: 0, to: bytes.count, by: 16) {
                var block = Array(bytes[start..<start + 16])
                try AES.inversePermute(&block, key: SymmetricKey(data: key))
                bytes.replaceSubrange(start..<start + 16, with: block)
            }
            let padding = Int(bytes.last!)
            #expect((1...16).contains(padding))
            return String(decoding: bytes.dropLast(padding), as: UTF8.self)
        }
        return (try decrypt(header.password), try decrypt(header.created), key)
    }

    @Test func atCanRecoverPasswordAndTimestamp() throws {
        let key = try ATAuthenticationKey(pemRepresentation: Fixtures.certificatePEM)
        let header = try SecurityHeader.make(credentials: credentials, authenticationKey: key, now: now)
        let opened = try open(header)
        #expect(header.username == "599999993/37")
        #expect(opened.key.count == 16)
        #expect(opened.password == credentials.password)
        #expect(opened.created == "2026-11-13T00:57:04.123Z")
    }

    @Test func everyRequestGetsANewKey() throws {
        let key = try ATAuthenticationKey(pemRepresentation: Fixtures.certificatePEM)
        let first = try SecurityHeader.make(credentials: credentials, authenticationKey: key, now: now)
        let second = try SecurityHeader.make(credentials: credentials, authenticationKey: key, now: now)
        #expect(try open(first).key != open(second).key)
        #expect(first.password != second.password)
    }

    @Test func readsTheKeyFromEveryFormat() throws {
        let publicPEM = privateKey.publicKey.pemRepresentation
        let keys = [
            try ATAuthenticationKey(pemRepresentation: Fixtures.certificatePEM),
            try ATAuthenticationKey(derRepresentation: Fixtures.certificateDER),
            try ATAuthenticationKey(pemRepresentation: publicPEM),
            try ATAuthenticationKey(derRepresentation: privateKey.publicKey.derRepresentation),
        ]
        for key in keys {
            let header = try SecurityHeader.make(credentials: credentials, authenticationKey: key, now: now)
            #expect(try open(header).password == credentials.password)
        }
        #expect(throws: EFaturaError.self) { try ATAuthenticationKey(pemRepresentation: "not a key") }
        #expect(throws: EFaturaError.self) { try ATAuthenticationKey(derRepresentation: Data([1, 2, 3])) }
    }

    /// NIST SP 800-38A, F.1.1 (ECB-AES128.Encrypt), first block.
    @Test func aesMatchesTheNISTVector() throws {
        func hex(_ string: String) -> Data {
            var data = Data()
            var index = string.startIndex
            while index < string.endIndex {
                let next = string.index(index, offsetBy: 2)
                data.append(UInt8(string[index..<next], radix: 16)!)
                index = next
            }
            return data
        }
        let key = SymmetricKey(data: hex("2b7e151628aed2a6abf7158809cf4f3c"))
        let encrypted = try SecurityHeader.encrypt(hex("6bc1bee22e409f96e93d7e117393172a"), with: key)
        // A full block of input gains a full block of padding.
        #expect(encrypted.count == 32)
        #expect(encrypted.prefix(16) == hex("3ad77bb40d7a3660a89ecaf32466ef97"))
        #expect(try SecurityHeader.encrypt(Data("abc".utf8), with: key).count == 16)
    }

    @Test func timestampIsUTCWithMilliseconds() {
        #expect(SecurityHeader.timestamp(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z")
        #expect(SecurityHeader.timestamp(Date(timeIntervalSince1970: 1_704_067_199.9996)) == "2023-12-31T23:59:59.999Z")
        #expect(SecurityHeader.timestamp(Date(timeIntervalSince1970: 1_709_210_096.05)) == "2024-02-29T12:34:56.050Z")
    }
}
