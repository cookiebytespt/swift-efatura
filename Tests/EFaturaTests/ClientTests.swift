import Foundation
import Testing

@_spi(Testing) @testable import EFatura

/// Answers from a script and records what was sent.
actor StubTransport: EFaturaTransport {
    private var responses: [EFaturaHTTPResponse]
    private(set) var requests: [EFaturaHTTPRequest] = []

    init(_ bodies: [String], status: Int = 200) {
        self.responses = bodies.map { EFaturaHTTPResponse(status: status, body: Data($0.utf8)) }
    }

    func send(_ request: EFaturaHTTPRequest) async throws -> EFaturaHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw EFaturaError.invalidRequest("stub has no more responses") }
        return responses.removeFirst()
    }

    var bodies: [String] { requests.map { String(decoding: $0.body, as: UTF8.self) } }
}

@Suite struct ClientTests {
    func client(_ transport: StubTransport) throws -> EFaturaClient {
        EFaturaClient(
            environment: .test,
            credentials: EFaturaCredentials(nif: Fixtures.nif, subuser: "1", password: "segredo"),
            authenticationKey: try ATAuthenticationKey(pemRepresentation: Fixtures.certificatePEM),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_794_531_424) }
        )
    }

    func october(page: Int = 1, pageSize: Int = 300) -> InvoiceQuery {
        InvoiceQuery(
            party: .buyer(Fixtures.nif), start: CalendarDay("2026-10-01")!, end: CalendarDay("2026-10-31")!,
            page: page, pageSize: pageSize
        )
    }

    @Test func sendsTheRequestATDocuments() async throws {
        let transport = StubTransport([Fixtures.successResponse])
        _ = try await client(transport).invoices(october())

        let request = try #require(await transport.requests.first)
        #expect(request.url.absoluteString == "https://servicos.portaldasfinancas.gov.pt:725/fatshare/ws/fatshareFaturas")
        #expect(request.headers["Content-Type"] == "text/xml; charset=utf-8")
        #expect(request.headers["SOAPAction"] == "\"\"")

        // Parse what was sent, so the test checks structure and not spacing.
        let root = try XMLNode.parse(request.body)
        #expect(root.name == "Envelope")
        let token = try #require(root.first(named: "UsernameToken"))
        #expect(token.value("Username") == "599999993/1")
        for field in ["Password", "Nonce", "Created"] {
            let value = try #require(token.value(field))
            #expect(Data(base64Encoded: value) != nil)
        }
        let body = try #require(root.child("Body")?.child("InvoicesRequest"))
        #expect(body.children.map(\.name) == ["CustomerTaxID", "StartDate", "EndDate", "Pagination"])
        #expect(body.value("CustomerTaxID") == "599999993")
        #expect(body.value("StartDate") == "2026-10-01")
        #expect(body.value("EndDate") == "2026-10-31")
        #expect(body.child("Pagination")?.value("nPage") == "1")
        #expect(body.child("Pagination")?.value("nDocsPage") == "300")

        let text = String(decoding: request.body, as: UTF8.self)
        #expect(text.contains(#"xmlns:fat="http://factemi.at.min_financas.pt/fatshareInvoices""#))
        #expect(text.contains(#"xmlns:wss="http://schemas.xmlsoap.org/ws/2002/12/secext""#))
        #expect(!text.contains("segredo"))
    }

    @Test func sendsARawBodyWithAFreshHeader() async throws {
        let transport = StubTransport(["<ok/>", "<ok/>"])
        let client = try client(transport)
        let url = URL(string: "https://example.test:723/fatcorews/ws/")!
        let first = try await client.sendSigned(body: "<doc:Ping xmlns:doc=\"urn:x\"/>", to: url)
        _ = try await client.sendSigned(body: "<doc:Ping xmlns:doc=\"urn:x\"/>", to: url)
        #expect(String(decoding: first.body, as: UTF8.self) == "<ok/>")

        let requests = await transport.requests
        #expect(requests.map(\.url) == [url, url])
        let roots = try requests.map { try XMLNode.parse($0.body) }
        #expect(roots[0].child("Body")?.child("Ping") != nil)
        #expect(roots[0].first(named: "Username")?.text == "599999993/1")
        #expect(roots[0].first(named: "Nonce")?.text != roots[1].first(named: "Nonce")?.text)
    }

    @Test func asksAsIssuerWithTheOtherElement() async throws {
        let transport = StubTransport([Fixtures.successResponse])
        var query = october()
        query.party = .issuer(Fixtures.nif)
        _ = try await client(transport).invoices(query)
        let body = try #require(await transport.bodies.first)
        #expect(body.contains("<fat:TaxRegistrationNumber>599999993</fat:TaxRegistrationNumber>"))
        #expect(!body.contains("CustomerTaxID"))
    }

    @Test func parsesInvoices() async throws {
        let page = try await client(StubTransport([Fixtures.successResponse])).invoices(october())
        #expect(page.pagination == .init(totalDocuments: 2, documentsInPage: 2, totalPages: 1, page: 1))
        #expect(!page.hasMorePages)
        #expect(page.invoices.count == 2)

        let invoice = page.invoices[0]
        #expect(invoice.number == "FT 2026A/123")
        #expect(invoice.atcud == "JFX7K2M9-123")
        #expect(invoice.date == CalendarDay("2026-10-14"))
        #expect(invoice.type == .invoice)
        #expect(invoice.isSelfBilling == false)
        #expect(invoice.isCashVATScheme == nil)
        #expect(invoice.counterparty == .issuer(nif: "501234560"))
        #expect(invoice.issuerNIF == "501234560")
        #expect(invoice.sector == "C99")
        #expect(invoice.status == nil)
        #expect(invoice.taxPayable.cents == 2300)
        #expect(invoice.netTotal.cents == 11010)
        #expect(invoice.grossTotal.cents == 13310)
        #expect(invoice.lines.count == 2)
        #expect(invoice.lines[0].debitCredit == .credit)
        #expect(invoice.lines[0].tax.code == "NOR")
        #expect(invoice.lines[0].tax.percentage == 23)
        #expect(invoice.lines[0].taxExemptionCode == nil)
        #expect(invoice.lines[1].taxExemptionCode == "M07")
        #expect(invoice.lines[1].netAmount.cents == 1010)

        let credit = page.invoices[1]
        #expect(credit.type == .creditNote)
        #expect(credit.type.isCredit)
        #expect(credit.atcud == nil)
        #expect(credit.isSelfBilling == nil)
        #expect(credit.isCashVATScheme == true)
        #expect(credit.date == CalendarDay("2026-10-31"))
        #expect(credit.counterparty == .customer(taxID: "FR12345678901", country: "FR"))
        #expect(credit.issuerNIF == nil)
        #expect(credit.status == .normal)
        #expect(credit.lines[0].debitCredit == .debit)
    }

    @Test func surfacesATsStatus() async throws {
        let body = Fixtures.statusResponse(code: 434, message: "O período não pode exceder um mês.")
        do {
            _ = try await client(StubTransport([body])).invoices(october())
            Issue.record("expected an error")
        } catch EFaturaError.rejected(let status) {
            #expect(status.code == EFaturaStatus.periodLongerThanOneMonth)
            #expect(status.kind == .content)
            #expect(status.message == "O período não pode exceder um mês.")
        }
        #expect(EFaturaStatus(code: 99, message: "").kind == .authentication)
        #expect(EFaturaStatus(code: 310, message: "").kind == .structure)
        #expect(EFaturaStatus(code: 599, message: "").kind == .server)
    }

    @Test func successWithoutAListIsAnEmptyPage() async throws {
        let body = Fixtures.statusResponse(code: 200, message: "OK")
        let page = try await client(StubTransport([body])).invoices(october())
        #expect(page.invoices.isEmpty)
        #expect(page.pagination.totalDocuments == 0)
        #expect(!page.hasMorePages)
    }

    /// A real list from AT's test environment: trailing zeros dropped, empty elements, and line
    /// amounts that are not what they seem (see `Invoice.LineSummary`).
    @Test func parsesARealListFromAT() async throws {
        var query = october()
        query.party = .issuer(NIF("599999993")!)
        let page = try await client(StubTransport([Fixtures.realATList])).invoices(query)
        #expect(page.pagination == .init(totalDocuments: 2, documentsInPage: 2, totalPages: 1, page: 1))
        #expect(page.invoices.map(\.number) == ["FT PAPELADATESTE/1794594338", "FT PAPELADATESTE/1794594440"])

        let invoice = try #require(page.invoices.last)
        #expect(invoice.softwareCertificateNumber == 0)
        #expect(invoice.atcud == "0")
        #expect(invoice.date == CalendarDay("2026-11-13"))
        #expect(invoice.type == .invoice)
        #expect(invoice.isSelfBilling == false)
        #expect(invoice.counterparty == .customer(taxID: "999999990", country: "PT"))
        #expect(invoice.status == .normal)
        #expect(invoice.isCashVATScheme == false)
        #expect(invoice.eacCode == nil)
        #expect(invoice.netTotal.cents == 1000)
        #expect(invoice.taxPayable.cents == 230)
        #expect(invoice.grossTotal.cents == 1230)

        let line = try #require(invoice.lines.first)
        #expect(invoice.lines.count == 1)
        #expect(line.totalTaxBase.cents == 1000)
        #expect(line.taxAmount.cents == 230)
        #expect(line.netAmount.cents == 0)      // as AT sends it
        #expect(line.grossAmount.cents == 230)  // as AT sends it
        #expect(line.tax.code == "NOR")
        #expect(line.tax.percentage == 23)
        #expect(line.taxExemptionCode == nil)
    }

    /// AT's answer for a month with nothing in it, exactly as the test environment sent it.
    @Test func emptyListIsAnEmptyPage() async throws {
        let body = """
            <?xml version="1.0" encoding="UTF-8"?>
            <env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"><env:Header/><env:Body>\
            <InvoicesResponse xmlns="http://factemi.at.min_financas.pt/fatshareInvoices"><estadoExecucao>\
            <EstadoOperacao>486</EstadoOperacao><Desc>Lista de faturas vazia.</Desc></estadoExecucao>\
            </InvoicesResponse></env:Body></env:Envelope>
            """
        let page = try await client(StubTransport([body])).invoices(october())
        #expect(page.invoices.isEmpty)
        #expect(!page.hasMorePages)

        // A period of empty months reads as nothing, not as an error.
        let quarter = try await client(StubTransport([body, body, body])).allInvoices(
            for: .buyer(Fixtures.nif), from: CalendarDay("2026-07-01")!, to: CalendarDay("2026-09-30")!
        )
        #expect(quarter.isEmpty)
    }

    @Test func reportsSOAPFaultsAndHTTPFailures() async throws {
        let fault = """
            <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><soap:Fault>
            <faultcode>soap:Client</faultcode><faultstring>Pedido SOAP inválido</faultstring>
            </soap:Fault></soap:Body></soap:Envelope>
            """
        do {
            _ = try await client(StubTransport([fault], status: 500)).invoices(october())
            Issue.record("expected an error")
        } catch EFaturaError.soapFault(let code, let message) {
            #expect(code == "soap:Client")
            #expect(message == "Pedido SOAP inválido")
        }

        do {
            _ = try await client(StubTransport(["Bad Gateway"], status: 502)).invoices(october())
            Issue.record("expected an error")
        } catch EFaturaError.http(let status, let body) {
            #expect(status == 502)
            #expect(body == "Bad Gateway")
        }

        do {
            _ = try await client(StubTransport(["<html><body>hello</body></html>"])).invoices(october())
            Issue.record("expected an error")
        } catch EFaturaError.malformedResponse {
        }
    }

    @Test func namesTheInvoiceWhenAFieldIsBroken() async throws {
        let body = Fixtures.successResponse.replacingOccurrences(
            of: "<ns2:GrossTotal>133.10</ns2:GrossTotal>", with: "<ns2:GrossTotal>133,10</ns2:GrossTotal>"
        )
        do {
            _ = try await client(StubTransport([body])).invoices(october())
            Issue.record("expected an error")
        } catch EFaturaError.malformedResponse(let reason) {
            #expect(reason.contains("FT 2026A/123"))
            #expect(reason.contains("GrossTotal"))
        }
    }

    @Test func refusesBadQueriesWithoutCallingAT() async throws {
        let transport = StubTransport([])
        let client = try client(transport)
        var backwards = october()
        backwards.end = CalendarDay("2026-09-30")!
        for query in [backwards, october(page: 0), october(pageSize: 0), october(pageSize: 5001)] {
            await #expect(throws: EFaturaError.self) { try await client.invoices(query) }
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func fetchesAQuarterMonthByMonthAndPageByPage() async throws {
        let transport = StubTransport([
            Fixtures.pageResponse(first: 1, count: 2, page: 1, totalPages: 2, totalDocs: 3, date: "2026-07-10"),
            Fixtures.pageResponse(first: 3, count: 1, page: 2, totalPages: 2, totalDocs: 3, date: "2026-07-20"),
            Fixtures.statusResponse(code: 200, message: "OK"),
            Fixtures.pageResponse(first: 4, count: 1, page: 1, totalPages: 1, totalDocs: 1, date: "2026-09-02"),
        ])
        let invoices = try await client(transport).allInvoices(
            for: .buyer(Fixtures.nif), from: CalendarDay("2026-07-01")!, to: CalendarDay("2026-09-30")!, pageSize: 2
        )
        #expect(invoices.map(\.number) == ["FT A/1", "FT A/2", "FT A/3", "FT A/4"])

        let sent = try await transport.requests.map { request -> String in
            let body = try #require(try XMLNode.parse(request.body).first(named: "InvoicesRequest"))
            return [
                body.value("StartDate"), body.value("EndDate"),
                body.child("Pagination")?.value("nPage"), body.child("Pagination")?.value("nDocsPage"),
            ].map { $0 ?? "?" }.joined(separator: " ")
        }
        #expect(sent == [
            "2026-07-01 2026-07-31 1 2",
            "2026-07-01 2026-07-31 2 2",
            "2026-08-01 2026-08-31 1 2",
            "2026-09-01 2026-09-30 1 2",
        ])

        // Each request carries its own session key.
        let nonces = try await transport.requests.map { try XMLNode.parse($0.body).first(named: "Nonce")?.text }
        #expect(Set(nonces).count == 4)
    }
}
