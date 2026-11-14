// --register-test-invoice: registers a fake invoice through AT's *test* sending service
// (fatcorews) and reads it back through the consult service, so the parser meets a real
// list from AT. Test environment only: the tool refuses it in production.

@_spi(Testing) import EFatura
import Foundation
import NIOSSL

/// AT's sending service in the test environment (from AT's reply to the test-access request).
let defaultTestSendingURL = URL(string: "https://servicos.portaldasfinancas.gov.pt:723/fatcorews/ws/")!

/// What gets registered: one line of 10,00 € at the normal VAT rate, to an anonymous final consumer.
struct TestInvoice {
    let issuer: NIF
    let number: String
    let date: CalendarDay
    let timestamp: String
    let atcud: String
    let customerTaxID = "999999990"   // AT's "final consumer, NIF not given"
    let customerCountry = "PT"
    let net = Decimal(string: "10.00")!
    let vat = Decimal(string: "2.30")!
    let gross = Decimal(string: "12.30")!
    let taxCode = "NOR"
    let taxPercentage = Decimal(23)

    /// A new number every run (AT refuses a number it already has with code -10).
    init(issuer: NIF, atcud: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        let now = Date()
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        func pad(_ value: Int?, _ width: Int = 2) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        self.issuer = issuer
        self.date = CalendarDay(year: c.year!, month: c.month!, day: c.day!)!
        self.timestamp = "\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day))T\(pad(c.hour)):\(pad(c.minute)):\(pad(c.second))"
        self.number = "FT PAPELADATESTE/\(Int(now.timeIntervalSince1970))"
        self.atcud = atcud
    }

    /// RegisterInvoiceRequest, field order and namespace as in AT's Fatcorews.wsdl.
    var soapBody: String {
        """
        <doc:RegisterInvoiceRequest xmlns:doc="http://factemi.at.min_financas.pt/documents">\
        <doc:eFaturaMDVersion>0.0.1</doc:eFaturaMDVersion>\
        <doc:AuditFileVersion>1.04_01</doc:AuditFileVersion>\
        <doc:TaxRegistrationNumber>\(issuer.value)</doc:TaxRegistrationNumber>\
        <doc:TaxEntity>Global</doc:TaxEntity>\
        <doc:SoftwareCertificateNumber>0</doc:SoftwareCertificateNumber>\
        <doc:InvoiceData>\
        <doc:InvoiceNo>\(number)</doc:InvoiceNo>\
        <doc:ATCUD>\(atcud)</doc:ATCUD>\
        <doc:InvoiceDate>\(date)</doc:InvoiceDate>\
        <doc:InvoiceType>FT</doc:InvoiceType>\
        <doc:SelfBillingIndicator>0</doc:SelfBillingIndicator>\
        <doc:CustomerTaxID>\(customerTaxID)</doc:CustomerTaxID>\
        <doc:CustomerTaxIDCountry>\(customerCountry)</doc:CustomerTaxIDCountry>\
        <doc:DocumentStatus>\
        <doc:InvoiceStatus>N</doc:InvoiceStatus>\
        <doc:InvoiceStatusDate>\(timestamp)</doc:InvoiceStatusDate>\
        </doc:DocumentStatus>\
        <doc:HashCharacters>0</doc:HashCharacters>\
        <doc:CashVATSchemeIndicator>0</doc:CashVATSchemeIndicator>\
        <doc:PaperLessIndicator>0</doc:PaperLessIndicator>\
        <doc:SystemEntryDate>\(timestamp)</doc:SystemEntryDate>\
        <doc:LineSummary>\
        <doc:TaxPointDate>\(date)</doc:TaxPointDate>\
        <doc:DebitCreditIndicator>C</doc:DebitCreditIndicator>\
        <doc:TotalTaxBase>10.00</doc:TotalTaxBase>\
        <doc:Tax>\
        <doc:TaxType>IVA</doc:TaxType>\
        <doc:TaxCountryRegion>PT</doc:TaxCountryRegion>\
        <doc:TaxCode>\(taxCode)</doc:TaxCode>\
        <doc:TaxPercentage>23.00</doc:TaxPercentage>\
        </doc:Tax>\
        </doc:LineSummary>\
        <doc:DocumentTotals>\
        <doc:TaxPayable>2.30</doc:TaxPayable>\
        <doc:NetTotal>10.00</doc:NetTotal>\
        <doc:GrossTotal>12.30</doc:GrossTotal>\
        </doc:DocumentTotals>\
        </doc:InvoiceData>\
        </doc:RegisterInvoiceRequest>
        """
    }
}

/// The text of the first element with this local name, whatever its prefix.
func xmlValue(_ name: String, in xml: String) -> String? {
    let pattern = "<(?:[A-Za-z0-9_]+:)?\(name)(?:\\s[^>]*)?>([^<]*)</"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
          let range = Range(match.range(at: 1), in: xml)
    else { return nil }
    return decodeEntities(String(xml[range])).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// `Opera&#231;&#227;o` → `Operação`: numeric and the five named XML entities.
func decodeEntities(_ text: String) -> String {
    var out = ""
    var rest = Substring(text)
    while let amp = rest.firstIndex(of: "&") {
        out += rest[..<amp]
        guard let semi = rest[amp...].firstIndex(of: ";") else { break }
        let entity = rest[rest.index(after: amp)..<semi]
        var decoded: String?
        switch entity {
        case "amp": decoded = "&"
        case "lt": decoded = "<"
        case "gt": decoded = ">"
        case "quot": decoded = "\""
        case "apos": decoded = "'"
        default:
            let number = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16)
                : entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
            decoded = number.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        out += decoded ?? String(rest[amp...semi])
        rest = rest[rest.index(after: semi)...]
    }
    return out + rest
}

func explainRegistration(code: Int, message: String) -> [String] {
    var lines = ["AT did not register the test invoice: \(code) — \(message)"]
    switch code {
    case -16:
        lines.append("The sub-user may not register documents for this NIF. In Portal das Finanças, give it")
        lines.append("the e-Fatura sending permission (\"WFA – Comunicação de dados de faturas\") and try again.")
    case 1...99:
        lines.append("This is an authentication code, from the sending service this time. The same header")
        lines.append("worked for the consult service, so the likeliest cause is the sub-user's permissions.")
    case -39:
        lines.append("AT refused certificate number 0 for an uncertified program, at least in this environment.")
    case -10:
        lines.append("A document with this number is already registered. Run again; each run uses a new number.")
    case -1, -7, -28, -50:
        lines.append("AT found something in the document it does not accept. The request is in the dump folder;")
        lines.append("if ATCUD \"0\" is the problem, try --atcud with a value in AT's format (CODE-NUMBER).")
    case -97, -99:
        lines.append("AT's side failed. Try again in a few minutes.")
    default:
        break
    }
    return lines
}

func registerTestInvoice(client: EFaturaClient, issuer: NIF, atcud: String, sendingURL: URL, tls: TLSConfiguration) async {
    say("\nTest invoice: registers a fake invoice in AT's TEST environment and reads it back.")

    await checkConnection(to: sendingURL, tls: tls)

    let invoice = TestInvoice(issuer: issuer, atcud: atcud)
    step("Registering \(invoice.number)")
    info("Sending service: \(sendingURL.absoluteString)")
    info("Issuer \(issuer), customer \(invoice.customerTaxID) (final consumer), dated \(invoice.date), ATCUD \(invoice.atcud)")
    info("One line: \(euros(invoice.net)) at \(invoice.taxCode) 23% — VAT \(euros(invoice.vat)), total \(euros(invoice.gross))")

    setStage("waiting for AT to register the test invoice")
    let started = Date()
    let response: EFaturaHTTPResponse
    do {
        response = try await withHeartbeat { try await client.sendSigned(body: invoice.soapBody, to: sendingURL) }
    } catch {
        info("Failed while \(currentStage), after \(seconds(since: stageStarted))")
        explain(error)
    }
    let xml = String(decoding: response.body, as: UTF8.self)

    if xml.contains("Fault>"), let fault = xmlValue("faultstring", in: xml) {
        fail("AT answered the registration with a SOAP fault: \(xmlValue("faultcode", in: xml) ?? "") — \(fault)")
    }
    guard let codeText = xmlValue("CodigoResposta", in: xml), let code = Int(codeText) else {
        fail("AT's answer to the registration has no CodigoResposta (HTTP \(response.status)):\n  \(String(xml.prefix(500)))")
    }
    let message = xmlValue("Mensagem", in: xml) ?? ""
    guard code == 0 else { fail(explainRegistration(code: code, message: message).joined(separator: "\n  ")) }
    ok("AT registered it in \(seconds(since: started)): \(message.isEmpty ? "code 0" : message)")

    // Read it back as the issuer. The two services may not share data at once, so try a few times.
    step("Reading it back from the consult service, as issuer")
    var found: Invoice?
    var seen: [String] = []
    for attempt in 1...4 {
        setStage("reading the test invoice back (attempt \(attempt))")
        do {
            let page = try await withHeartbeat {
                try await client.invoices(InvoiceQuery(party: .issuer(issuer), start: invoice.date, end: invoice.date))
            }
            seen = page.invoices.map(\.number)
            found = page.invoices.first { $0.number == invoice.number }
        } catch {
            info("Failed while \(currentStage), after \(seconds(since: stageStarted))")
            explain(error)
        }
        if found != nil { break }
        if attempt < 4 {
            info("Not listed yet (\(seen.count) document\(seen.count == 1 ? "" : "s") that day); trying again in 15 s")
            try? await Task.sleep(for: .seconds(15))
        }
    }

    guard let back = found else {
        say("\nAT registered the invoice, but the consult service does not list it after a minute.")
        if !seen.isEmpty { say("It lists instead: \(seen.joined(separator: ", "))") }
        say("In the test environment the sending and consult services may not share data. The registration")
        say("still proves the sending side works; the parser has to wait for production data.")
        try? logHandle?.synchronize()
        exit(0)
    }
    ok("Found \(back.number)")

    step("Sent versus read back")
    var mismatches = 0
    func compare(_ label: String, _ sent: String, _ received: String) {
        if sent == received {
            info("✓ " + padded(label, 16) + received)
        } else {
            mismatches += 1
            info("✗ " + padded(label, 16) + "sent \(sent), read \(received)")
        }
    }
    let customer: String
    switch back.counterparty {
    case .customer(let taxID, let country): customer = country.map { "\(taxID) (\($0))" } ?? taxID
    case .issuer(let nif): customer = "issuer \(nif)"
    }
    compare("Number", invoice.number, back.number)
    compare("Date", invoice.date.description, back.date.description)
    compare("Type", "FT", back.type.rawValue)
    compare("Customer", "\(invoice.customerTaxID) (\(invoice.customerCountry))", customer)
    compare("ATCUD", invoice.atcud, back.atcud ?? "—")
    compare("Net", euros(invoice.net), euros(back.netTotal))
    compare("VAT", euros(invoice.vat), euros(back.taxPayable))
    compare("Gross", euros(invoice.gross), euros(back.grossTotal))
    compare("Lines", "1", String(back.lines.count))
    if let line = back.lines.first {
        compare("Line tax", "IVA PT NOR 23", [line.tax.type, line.tax.countryRegion, line.tax.code,
                                             line.tax.percentage.map { "\($0)" }].map { $0 ?? "—" }.joined(separator: " "))
        compare("Line base", euros(invoice.net), euros(line.totalTaxBase))
    }
    if let status = back.status { info("  " + padded("Status", 16) + status.rawValue) }

    if mismatches == 0 {
        say("\nAll good: AT registered the test invoice and the client read it back field for field.")
    } else {
        say("\n\(mismatches) field\(mismatches == 1 ? "" : "s") differ. The response is in the dump folder; send it over.")
    }
    try? logHandle?.synchronize()
    exit(mismatches == 0 ? 0 : 1)
}
