import Foundation

/// Whose invoices to read. The NIF must be the one the credentials belong to.
public enum InvoiceParty: Sendable, Hashable {
    /// Documents issued to this NIF (`CustomerTaxID`): the company's purchases.
    case buyer(NIF)
    /// Documents issued by this NIF (`TaxRegistrationNumber`): the company's sales.
    case issuer(NIF)
}

public struct InvoiceQuery: Sendable, Hashable {
    /// AT's upper limit for `nDocsPage`.
    public static let maximumPageSize = 5000

    public var party: InvoiceParty
    /// First day, inclusive. Not in the future.
    public var start: CalendarDay
    /// Last day, inclusive. AT accepts at most one month per request.
    public var end: CalendarDay
    /// 1-based.
    public var page: Int
    public var pageSize: Int

    public init(
        party: InvoiceParty, start: CalendarDay, end: CalendarDay,
        page: Int = 1, pageSize: Int = InvoiceQuery.maximumPageSize
    ) {
        self.party = party
        self.start = start
        self.end = end
        self.page = page
        self.pageSize = pageSize
    }

    /// Catches what can be known without asking AT. The one-month rule is left to AT.
    func validate() throws {
        guard start <= end else {
            throw EFaturaError.invalidRequest("end date \(end) is before start date \(start)")
        }
        guard page >= 1 else {
            throw EFaturaError.invalidRequest("page must be 1 or more")
        }
        guard (1...InvoiceQuery.maximumPageSize).contains(pageSize) else {
            throw EFaturaError.invalidRequest("page size must be between 1 and \(InvoiceQuery.maximumPageSize)")
        }
    }
}

/// Client for AT's "consultar faturas" webservice: the invoices e-Fatura holds for a taxpayer.
///
/// ```swift
/// let client = EFaturaClient(
///     environment: .production,
///     credentials: EFaturaCredentials(nif: nif, subuser: "1", password: password),
///     authenticationKey: try ATAuthenticationKey(contentsOf: keyURL),
///     transport: transport
/// )
/// let purchases = try await client.allInvoices(for: .buyer(nif), from: start, to: end)
/// ```
public struct EFaturaClient: Sendable {
    public let environment: EFaturaEnvironment
    let credentials: EFaturaCredentials
    let authenticationKey: ATAuthenticationKey
    let transport: any EFaturaTransport
    let now: @Sendable () -> Date

    /// - Parameter now: the clock used for the request timestamp. AT refuses requests
    ///   whose timestamp is off, so the host's clock must be synchronised.
    public init(
        environment: EFaturaEnvironment,
        credentials: EFaturaCredentials,
        authenticationKey: ATAuthenticationKey,
        transport: any EFaturaTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.environment = environment
        self.credentials = credentials
        self.authenticationKey = authenticationKey
        self.transport = transport
        self.now = now
    }

    /// Fetches one page.
    public func invoices(_ query: InvoiceQuery) async throws -> InvoicePage {
        try query.validate()
        // A new session key per request: AT rejects a repeated one.
        let header = try SecurityHeader.make(
            credentials: credentials, authenticationKey: authenticationKey, now: now()
        )
        let request = EFaturaHTTPRequest(
            url: environment.invoicesURL,
            headers: SOAP.headers,
            body: SOAP.envelope(header: header, body: SOAP.invoicesRequest(query))
        )
        return try InvoicesResponseParser.parse(try await transport.send(request))
    }

    /// Low level: sends `body`, the content of the SOAP body, to `url` with a fresh security header
    /// for these credentials, and returns AT's raw answer. The caller interprets the response.
    ///
    /// Not part of the public API: the library only reads. It exists for the live-check tool, which
    /// registers fake invoices in AT's test environment; opt in with `@_spi(Testing) import EFatura`.
    @_spi(Testing)
    public func sendSigned(body: String, to url: URL) async throws -> EFaturaHTTPResponse {
        let header = try SecurityHeader.make(
            credentials: credentials, authenticationKey: authenticationKey, now: now()
        )
        return try await transport.send(EFaturaHTTPRequest(
            url: url,
            headers: SOAP.headers,
            body: SOAP.envelope(header: header, body: body)
        ))
    }

    /// Fetches every document in `start...end`, one request per calendar month and per page.
    /// Any length of period is accepted; requests run one after another, oldest month first.
    public func allInvoices(
        for party: InvoiceParty,
        from start: CalendarDay,
        to end: CalendarDay,
        pageSize: Int = InvoiceQuery.maximumPageSize
    ) async throws -> [Invoice] {
        guard start <= end else {
            throw EFaturaError.invalidRequest("end date \(end) is before start date \(start)")
        }
        var all: [Invoice] = []
        for range in CalendarDay.monthlyRanges(from: start, to: end) {
            var page = 1
            while true {
                try Task.checkCancellation()
                let result = try await invoices(InvoiceQuery(
                    party: party, start: range.lowerBound, end: range.upperBound,
                    page: page, pageSize: pageSize
                ))
                all.append(contentsOf: result.invoices)
                // Stop on an empty page too, so a wrong total can never loop forever.
                guard result.hasMorePages, !result.invoices.isEmpty else { break }
                page += 1
            }
        }
        return all
    }
}
