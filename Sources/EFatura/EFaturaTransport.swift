import Foundation

public struct EFaturaHTTPRequest: Sendable {
    public var url: URL
    public var headers: [String: String]
    public var body: Data

    public init(url: URL, headers: [String: String], body: Data) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct EFaturaHTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Sends one SOAP request to AT over HTTPS, presenting the producer's client certificate.
///
/// The core library does no networking of its own. `EFaturaAsyncHTTPClient` provides
/// an implementation; tests can supply a stub.
public protocol EFaturaTransport: Sendable {
    /// Returns the response whatever its HTTP status; throws only when no response arrived.
    func send(_ request: EFaturaHTTPRequest) async throws -> EFaturaHTTPResponse
}
