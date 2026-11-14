import Crypto
import CryptoExtras
import Foundation

/// The WS-Security UsernameToken AT expects in every request
/// (manual "Aspetos genéricos", section 2.2.1):
///
/// - `Nonce`: a fresh 128-bit AES key, encrypted with AT's RSA public key (PKCS#1 v1.5), Base64.
/// - `Password`: the sub-user's password, AES/ECB/PKCS5 with that key, Base64.
/// - `Created`: the current UTC time in ISO 8601, AES/ECB/PKCS5 with that key, Base64.
///
/// The key must never be reused, so a header is good for one request only.
struct SecurityHeader: Sendable, Equatable {
    let username: String
    let password: String
    let nonce: String
    let created: String

    static func make(
        credentials: EFaturaCredentials,
        authenticationKey: ATAuthenticationKey,
        now: Date,
        sessionKey: SymmetricKey = SymmetricKey(size: .bits128)
    ) throws -> SecurityHeader {
        let rawKey = sessionKey.withUnsafeBytes { Data($0) }
        let nonce = try authenticationKey.publicKey.encrypt(rawKey, padding: ._WEAK_AND_INSECURE_PKCS_V1_5)
        return SecurityHeader(
            username: credentials.username,
            password: try encrypt(Data(credentials.password.utf8), with: sessionKey).base64EncodedString(),
            nonce: nonce.base64EncodedString(),
            created: try encrypt(Data(timestamp(now).utf8), with: sessionKey).base64EncodedString()
        )
    }

    /// AES in ECB mode with PKCS#5/7 padding. ECB is what AT specifies; each key encrypts
    /// two short values once, so the usual ECB weaknesses do not come into play.
    static func encrypt(_ plaintext: Data, with key: SymmetricKey) throws -> Data {
        let blockSize = 16
        let padding = blockSize - plaintext.count % blockSize
        var bytes = Array(plaintext) + Array(repeating: UInt8(padding), count: padding)
        for start in stride(from: 0, to: bytes.count, by: blockSize) {
            var block = Array(bytes[start..<start + blockSize])
            try AES.permute(&block, key: key)
            bytes.replaceSubrange(start..<start + blockSize, with: block)
        }
        return Data(bytes)
    }

    /// `2026-11-13T00:57:04.123Z`: UTC, milliseconds.
    static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Work in whole milliseconds so rounding can never produce ".1000".
        let totalMilliseconds = Int64((max(0, date.timeIntervalSince1970) * 1000).rounded(.down))
        let seconds = Double(totalMilliseconds / 1000)
        let milliseconds = Int(totalMilliseconds % 1000)
        let c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: seconds)
        )
        func pad(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(c.year, 4))-\(pad(c.month, 2))-\(pad(c.day, 2))"
            + "T\(pad(c.hour, 2)):\(pad(c.minute, 2)):\(pad(c.second, 2)).\(pad(milliseconds, 3))Z"
    }
}
