import Foundation

enum InvoicesResponseParser {
    /// Turns the HTTP response into a page, or throws the most specific error it can find.
    static func parse(_ response: EFaturaHTTPResponse) throws -> InvoicePage {
        let root: XMLNode
        do {
            root = try XMLNode.parse(response.body)
        } catch {
            // A proxy or TLS front end answered instead of the service.
            if !(200..<300).contains(response.status) {
                throw EFaturaError.http(status: response.status, body: preview(response.body))
            }
            throw error
        }

        if let fault = root.first(named: "Fault") {
            throw EFaturaError.soapFault(
                code: fault.value("faultcode") ?? "",
                message: fault.value("faultstring") ?? ""
            )
        }
        guard let payload = root.first(named: "InvoicesResponse") else {
            if !(200..<300).contains(response.status) {
                throw EFaturaError.http(status: response.status, body: preview(response.body))
            }
            throw EFaturaError.malformedResponse("no InvoicesResponse element")
        }
        guard let state = payload.child("estadoExecucao"),
              let code = state.value("EstadoOperacao").flatMap({ Int($0) })
        else {
            throw EFaturaError.malformedResponse("no estadoExecucao/EstadoOperacao")
        }
        let status = EFaturaStatus(code: code, message: state.value("Desc") ?? "")
        if status.code == EFaturaStatus.emptyList {
            return InvoicePage(
                invoices: [],
                pagination: .init(totalDocuments: 0, documentsInPage: 0, totalPages: 0, page: 1)
            )
        }
        guard status.isSuccess else { throw EFaturaError.rejected(status) }

        guard let list = payload.child("InvoicesList") else {
            // Success with no list: nothing registered in the period.
            return InvoicePage(
                invoices: [],
                pagination: .init(totalDocuments: 0, documentsInPage: 0, totalPages: 0, page: 1)
            )
        }
        let invoices = try list.children(named: "Invoice").map(invoice)
        let totals = list.child("PaginationTotal")
        func total(_ name: String, default fallback: Int) -> Int {
            totals?.value(name).flatMap { Int($0) } ?? fallback
        }
        return InvoicePage(
            invoices: invoices,
            pagination: .init(
                totalDocuments: total("totalDocs", default: invoices.count),
                documentsInPage: total("totalDocsSent", default: invoices.count),
                totalPages: total("totalPages", default: 1),
                page: total("nPage", default: 1)
            )
        )
    }

    private static func invoice(_ node: XMLNode) throws -> Invoice {
        let number = try required(node, "InvoiceNo", in: "Invoice")
        let context = "Invoice \(number)"

        let counterparty: Invoice.Counterparty
        if let issuer = node.value("TaxRegistrationNumber") {
            counterparty = .issuer(nif: issuer)
        } else if let customer = node.value("CustomerTaxID") {
            counterparty = .customer(taxID: customer, country: node.value("CustomerTaxIDCountry"))
        } else {
            throw EFaturaError.malformedResponse("\(context): neither TaxRegistrationNumber nor CustomerTaxID")
        }

        return Invoice(
            softwareCertificateNumber: node.value("SoftwareCertificateNumber").flatMap { Int($0) },
            number: number,
            atcud: node.value("ATCUD"),
            date: try day(node, "InvoiceDate", in: context),
            type: InvoiceType(rawValue: try required(node, "InvoiceType", in: context)),
            isSelfBilling: flag(node.value("SelfBillingIndicator")),
            counterparty: counterparty,
            status: node.value("DocumentStatus").map(DocumentStatus.init(rawValue:)),
            isCashVATScheme: flag(node.value("CashVATSchemeIndicator")),
            eacCode: node.value("EACCode"),
            sector: node.value("Sector"),
            lines: try node.children(named: "LineSummary").map { try line($0, in: context) },
            taxPayable: try decimal(node, "TaxPayable", in: context),
            netTotal: try decimal(node, "NetTotal", in: context),
            grossTotal: try decimal(node, "GrossTotal", in: context)
        )
    }

    private static func line(_ node: XMLNode, in context: String) throws -> Invoice.LineSummary {
        let context = "\(context), LineSummary"
        let tax = node.child("Tax")
        return Invoice.LineSummary(
            taxPointDate: try day(node, "TaxPointDate", in: context),
            debitCredit: node.value("DebitCreditIndicator").flatMap(Invoice.DebitCredit.init(rawValue:)),
            taxAmount: try decimal(node, "TaxAmount", in: context),
            netAmount: try decimal(node, "NetAmount", in: context),
            grossAmount: try decimal(node, "GrossAmount", in: context),
            totalTaxBase: try decimal(node, "TotalTaxBase", in: context),
            tax: Invoice.Tax(
                type: tax?.value("TaxType"),
                countryRegion: tax?.value("TaxCountryRegion"),
                code: tax?.value("TaxCode"),
                percentage: try tax.flatMap { try optionalDecimal($0, "TaxPercentage", in: context) },
                totalAmount: try tax.flatMap { try optionalDecimal($0, "TotalTaxAmount", in: context) }
            ),
            // The WSDL puts it beside Tax; the manual numbers it inside Tax. Accept both.
            taxExemptionCode: node.value("TaxExemptionCode") ?? tax?.value("TaxExemptionCode")
        )
    }

    // MARK: Field helpers

    private static func required(_ node: XMLNode, _ name: String, in context: String) throws -> String {
        guard let value = node.value(name) else {
            throw EFaturaError.malformedResponse("\(context): missing \(name)")
        }
        return value
    }

    private static func day(_ node: XMLNode, _ name: String, in context: String) throws -> CalendarDay {
        let text = try required(node, name, in: context)
        guard let day = CalendarDay(text) else {
            throw EFaturaError.malformedResponse("\(context): \(name) is not a date (\(text))")
        }
        return day
    }

    private static func decimal(_ node: XMLNode, _ name: String, in context: String) throws -> Decimal {
        guard let value = try optionalDecimal(node, name, in: context) else {
            throw EFaturaError.malformedResponse("\(context): missing \(name)")
        }
        return value
    }

    private static func optionalDecimal(_ node: XMLNode, _ name: String, in context: String) throws -> Decimal? {
        guard let text = node.value(name) else { return nil }
        // Decimal(string:) stops at the first character it cannot read, so check the shape first.
        let digits = text.drop { $0 == "-" || $0 == "+" }
        let wellFormed = !digits.isEmpty
            && digits.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
            && digits.filter { $0 == "." }.count <= 1
            && digits != "."
        guard wellFormed, let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw EFaturaError.malformedResponse("\(context): \(name) is not a number (\(text))")
        }
        return value
    }

    private static func flag(_ text: String?) -> Bool? {
        switch text {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    private static func preview(_ body: Data) -> String {
        String(decoding: body.prefix(500), as: UTF8.self)
    }
}
