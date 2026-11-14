import Foundation

enum SOAP {
    static let envelopeNamespace = "http://schemas.xmlsoap.org/soap/envelope/"
    static let securityNamespace = "http://schemas.xmlsoap.org/ws/2002/12/secext"
    static let invoicesNamespace = "http://factemi.at.min_financas.pt/fatshareInvoices"

    static let headers = [
        "Content-Type": "text/xml; charset=utf-8",
        "SOAPAction": "\"\"",
        "Accept": "text/xml",
    ]

    static func envelope(header: SecurityHeader, body: String) -> Data {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>\
            <S:Envelope xmlns:S="\(envelopeNamespace)">\
            <S:Header>\
            <wss:Security xmlns:wss="\(securityNamespace)">\
            <wss:UsernameToken>\
            <wss:Username>\(escape(header.username))</wss:Username>\
            <wss:Password>\(header.password)</wss:Password>\
            <wss:Nonce>\(header.nonce)</wss:Nonce>\
            <wss:Created>\(header.created)</wss:Created>\
            </wss:UsernameToken>\
            </wss:Security>\
            </S:Header>\
            <S:Body>\(body)</S:Body>\
            </S:Envelope>
            """
        return Data(xml.utf8)
    }

    static func invoicesRequest(_ query: InvoiceQuery) -> String {
        let party: String
        switch query.party {
        case .issuer(let nif): party = "<fat:TaxRegistrationNumber>\(nif.value)</fat:TaxRegistrationNumber>"
        case .buyer(let nif): party = "<fat:CustomerTaxID>\(nif.value)</fat:CustomerTaxID>"
        }
        return """
            <fat:InvoicesRequest xmlns:fat="\(invoicesNamespace)">\
            \(party)\
            <fat:StartDate>\(query.start)</fat:StartDate>\
            <fat:EndDate>\(query.end)</fat:EndDate>\
            <fat:Pagination>\
            <fat:nPage>\(query.page)</fat:nPage>\
            <fat:nDocsPage>\(query.pageSize)</fat:nDocsPage>\
            </fat:Pagination>\
            </fat:InvoicesRequest>
            """
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }
}
