import AsyncHTTPClient
import EFatura
import Foundation
import NIOCore
import NIOPosix
import NIOSSL

/// The client certificate that identifies the software producer to AT, with its private key.
public struct EFaturaClientIdentity: Sendable {
    let certificateChain: [NIOSSLCertificate]
    let privateKey: NIOSSLPrivateKey

    /// The certificate AT signed (PEM, optionally followed by its chain) and the private key
    /// whose CSR was submitted (PEM).
    public static func pem(certificateFile: String, privateKeyFile: String) throws -> EFaturaClientIdentity {
        EFaturaClientIdentity(
            certificateChain: try NIOSSLCertificate.fromPEMFile(certificateFile),
            privateKey: try NIOSSLPrivateKey(file: privateKeyFile, format: .pem)
        )
    }

    /// The same, from memory, for secrets that arrive through the environment.
    public static func pem(certificate: String, privateKey: String) throws -> EFaturaClientIdentity {
        EFaturaClientIdentity(
            certificateChain: try NIOSSLCertificate.fromPEMBytes(Array(certificate.utf8)),
            privateKey: try NIOSSLPrivateKey(bytes: Array(privateKey.utf8), format: .pem)
        )
    }

    /// A PKCS#12 bundle (`.pfx`), the form in which AT distributes its test certificate.
    public static func pkcs12(file: String, passphrase: String) throws -> EFaturaClientIdentity {
        let bundle = try NIOSSLPKCS12Bundle(file: file, passphrase: Array(passphrase.utf8))
        return EFaturaClientIdentity(certificateChain: bundle.certificateChain, privateKey: bundle.privateKey)
    }
}

extension EFaturaClientIdentity {
    /// The TLS settings the transport uses: this identity as the client certificate, the system's
    /// trust store plus `additionalTrustRoots` for AT's server. Public so that diagnostics can open
    /// a connection with exactly the same settings.
    public func tlsConfiguration(additionalTrustRoots: [NIOSSLCertificate] = []) -> TLSConfiguration {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateChain = certificateChain.map { .certificate($0) }
        tls.privateKey = .privateKey(privateKey)
        if !additionalTrustRoots.isEmpty {
            tls.additionalTrustRoots = [.certificates(additionalTrustRoots)]
        }
        return tls
    }
}

/// Sends requests to AT over mutual TLS with AsyncHTTPClient, on SwiftNIO sockets with BoringSSL
/// on every platform (see `init`). Works on macOS and Linux.
///
/// Create one, reuse it for every request, and call ``shutdown()`` before the process exits.
public final class AsyncHTTPClientTransport: EFaturaTransport {
    private let client: HTTPClient
    private let timeout: TimeAmount
    private let maximumResponseBytes: Int

    /// - Parameters:
    ///   - additionalTrustRoots: extra CAs to accept for AT's server certificate, on top of the
    ///     system's. Needed only where the system trust store lacks AT's issuer.
    ///   - maximumResponseBytes: refuses larger responses. A full page of 5,000 documents is a few megabytes.
    public init(
        identity: EFaturaClientIdentity,
        timeout: TimeAmount = .seconds(60),
        additionalTrustRoots: [NIOSSLCertificate] = [],
        maximumResponseBytes: Int = 64 * 1024 * 1024
    ) {
        let tls = identity.tlsConfiguration(additionalTrustRoots: additionalTrustRoots)
        var configuration = HTTPClient.Configuration(tlsConfiguration: tls)
        configuration.timeout = .init(connect: .seconds(15), read: timeout)
        // Always NIO on sockets with BoringSSL. On Apple platforms AsyncHTTPClient's default group is
        // Network.framework, which cannot present a client certificate given as a NIOSSL key and
        // stops the process with a precondition failure on the first request.
        self.client = HTTPClient(
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            configuration: configuration
        )
        self.timeout = timeout
        self.maximumResponseBytes = maximumResponseBytes
    }

    public func send(_ request: EFaturaHTTPRequest) async throws -> EFaturaHTTPResponse {
        var outgoing = HTTPClientRequest(url: request.url.absoluteString)
        outgoing.method = .POST
        for (name, value) in request.headers {
            outgoing.headers.add(name: name, value: value)
        }
        outgoing.body = .bytes(ByteBuffer(bytes: request.body))

        let response = try await client.execute(outgoing, timeout: timeout)
        let body = try await response.body.collect(upTo: maximumResponseBytes)
        return EFaturaHTTPResponse(status: Int(response.status.code), body: Data(body.readableBytesView))
    }

    /// Closes the connections. Call it when the transport is no longer needed.
    public func shutdown() async throws {
        try await client.shutdown()
    }

    deinit {
        // AsyncHTTPClient traps if a client is released while running. Shut down here as a
        // safety net for callers that forgot; after an explicit shutdown this is a no-op.
        client.shutdown { _ in }
    }
}
