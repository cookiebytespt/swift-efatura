import Foundation

/// One document registered in e-Fatura, as the "consultar faturas" service returns it.
/// The service returns data only: there is no PDF and no party names.
public struct Invoice: Sendable, Hashable, Codable {
    /// Certification number of the invoicing software. Returned to the issuer only.
    public var softwareCertificateNumber: Int?
    /// `InvoiceNo`, for example `FT 2026A/123`.
    public var number: String
    public var atcud: String?
    public var date: CalendarDay
    public var type: InvoiceType
    public var isSelfBilling: Bool?
    /// The other side of the document: the issuer when you asked as buyer, the customer when you asked as issuer.
    public var counterparty: Counterparty
    /// Returned to the issuer only.
    public var status: DocumentStatus?
    public var isCashVATScheme: Bool?
    /// The issuer's activity code (CAE). Returned to the issuer only.
    public var eacCode: String?
    /// Returned to the buyer only.
    public var sector: String?
    public var lines: [LineSummary]
    public var taxPayable: Decimal
    public var netTotal: Decimal
    public var grossTotal: Decimal

    public enum Counterparty: Sendable, Hashable, Codable {
        /// `TaxRegistrationNumber`: the Portuguese NIF of whoever issued the document.
        case issuer(nif: String)
        /// `CustomerTaxID`, which may be foreign, and its country when known.
        case customer(taxID: String, country: String?)
    }

    /// The issuer's NIF, when the query was made as buyer.
    public var issuerNIF: String? {
        if case .issuer(let nif) = counterparty { return nif }
        return nil
    }

    /// One line of the tax breakdown: the document's amounts for one tax rate.
    ///
    /// Use `totalTaxBase` and `taxAmount`, or the document's totals. `netAmount` and `grossAmount`
    /// mirror what the issuer's software sent as the line's `Amount`: when it sent `TotalTaxBase`
    /// instead, AT returns `netAmount` 0 and `grossAmount` equal to the tax alone (seen in AT's test
    /// environment, 13 Nov 2026).
    public struct LineSummary: Sendable, Hashable, Codable {
        public var taxPointDate: CalendarDay
        public var debitCredit: DebitCredit?
        public var taxAmount: Decimal
        /// May be 0 even on a taxed line; see the type's note.
        public var netAmount: Decimal
        /// May hold only the tax; see the type's note.
        public var grossAmount: Decimal
        public var totalTaxBase: Decimal
        public var tax: Tax
        /// `M01`…`M99`, when the line is exempt.
        public var taxExemptionCode: String?
    }

    public struct Tax: Sendable, Hashable, Codable {
        /// `IVA`, `IS` or `NS`.
        public var type: String?
        /// `PT`, `PT-AC`, `PT-MA` or another country code.
        public var countryRegion: String?
        /// `NOR`, `INT`, `RED`, `ISE`, `OUT`, or a stamp-duty code.
        public var code: String?
        public var percentage: Decimal?
        /// Present instead of `percentage` for fixed-amount taxes.
        public var totalAmount: Decimal?
    }

    public enum DebitCredit: String, Sendable, Hashable, Codable {
        case debit = "D"
        case credit = "C"
    }
}

/// SAF-T document type. A struct so that a type AT adds later still decodes.
public struct InvoiceType: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Fatura.
    public static let invoice = InvoiceType(rawValue: "FT")
    /// Fatura simplificada.
    public static let simplifiedInvoice = InvoiceType(rawValue: "FS")
    /// Fatura-recibo.
    public static let invoiceReceipt = InvoiceType(rawValue: "FR")
    /// Nota de crédito.
    public static let creditNote = InvoiceType(rawValue: "NC")
    /// Nota de débito.
    public static let debitNote = InvoiceType(rawValue: "ND")
    /// Prémio ou recibo de prémio (seguros).
    public static let insurancePremium = InvoiceType(rawValue: "RP")
    /// Estorno ou recibo de estorno (seguros).
    public static let insuranceReversal = InvoiceType(rawValue: "RE")
    /// Imputação a co-seguradoras.
    public static let coInsurerAllocation = InvoiceType(rawValue: "CS")
    /// Imputação a co-seguradora líder.
    public static let leadCoInsurerAllocation = InvoiceType(rawValue: "LD")
    /// Resseguro aceite.
    public static let acceptedReinsurance = InvoiceType(rawValue: "RA")

    /// Credit notes and insurance reversals reduce what was spent.
    public var isCredit: Bool { self == .creditNote || self == .insuranceReversal }
}

public struct DocumentStatus: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let normal = DocumentStatus(rawValue: "N")
    /// Anulado.
    public static let cancelled = DocumentStatus(rawValue: "A")
    /// Faturado.
    public static let billed = DocumentStatus(rawValue: "F")
    /// Autofaturação.
    public static let selfBilled = DocumentStatus(rawValue: "S")
}

/// One page of results.
public struct InvoicePage: Sendable, Hashable {
    public var invoices: [Invoice]
    public var pagination: Pagination

    public struct Pagination: Sendable, Hashable {
        /// Documents matching the query, across all pages.
        public var totalDocuments: Int
        /// Documents in this page.
        public var documentsInPage: Int
        public var totalPages: Int
        public var page: Int
    }

    public var hasMorePages: Bool { pagination.page < pagination.totalPages }
}

extension Decimal {
    /// The amount in integer cents, rounded half up: `12.34` is `1234`.
    public var cents: Int {
        var scaled = self * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
