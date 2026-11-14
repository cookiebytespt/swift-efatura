import CryptoExtras
import Foundation
import SwiftASN1
import X509

/// The RSA public key of AT's authentication system, which encrypts the per-request session key.
///
/// AT sends it by email on request (asi-cd@at.gov.pt) as an X.509 certificate.
/// It is public, and it differs between the test and production environments.
public struct ATAuthenticationKey: Sendable {
    let publicKey: _RSA.Encryption.PublicKey

    /// Accepts a PEM `CERTIFICATE` or a PEM `PUBLIC KEY`.
    public init(pemRepresentation pem: String) throws {
        if pem.contains("BEGIN CERTIFICATE") {
            let certificate: Certificate
            do {
                certificate = try Certificate(pemEncoded: pem)
            } catch {
                throw EFaturaError.invalidAuthenticationKey("unreadable certificate: \(error)")
            }
            try self.init(certificate: certificate)
        } else {
            let key: _RSA.Encryption.PublicKey
            do {
                key = try _RSA.Encryption.PublicKey(unsafePEMRepresentation: pem)
            } catch {
                throw EFaturaError.invalidAuthenticationKey("unreadable public key: \(error)")
            }
            self.init(publicKey: key)
        }
    }

    /// Accepts a DER certificate (`.cer`) or a DER SubjectPublicKeyInfo.
    public init(derRepresentation der: Data) throws {
        if let certificate = try? Certificate(derEncoded: Array(der)) {
            try self.init(certificate: certificate)
            return
        }
        let key: _RSA.Encryption.PublicKey
        do {
            key = try _RSA.Encryption.PublicKey(unsafeDERRepresentation: der)
        } catch {
            throw EFaturaError.invalidAuthenticationKey("neither a certificate nor a public key: \(error)")
        }
        self.init(publicKey: key)
    }

    /// Reads a certificate or public key file, PEM or DER.
    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN") {
            try self.init(pemRepresentation: text)
        } else {
            try self.init(derRepresentation: data)
        }
    }

    private init(certificate: Certificate) throws {
        let key: _RSA.Encryption.PublicKey
        do {
            let pem = try certificate.publicKey.serializeAsPEM().pemString
            key = try _RSA.Encryption.PublicKey(unsafePEMRepresentation: pem)
        } catch {
            throw EFaturaError.invalidAuthenticationKey("the certificate's key is not RSA: \(error)")
        }
        self.init(publicKey: key)
    }

    // The "unsafe" initialisers above only lift swift-crypto's 2048-bit minimum:
    // the key is AT's choice, and the library must accept whatever AT publishes.
    init(publicKey: _RSA.Encryption.PublicKey) {
        self.publicKey = publicKey
    }
}
