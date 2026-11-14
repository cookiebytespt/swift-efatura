import EFatura
import Foundation

/// A self-signed certificate and its key, generated for these tests only.
/// They stand in for AT's authentication certificate; they protect nothing.
enum Fixtures {
    static let certificatePEM = """
        -----BEGIN CERTIFICATE-----
        MIIDezCCAmOgAwIBAgIUYe7A35PdPJyw7TTOv4AJk5YKMGswDQYJKoZIhvcNAQEL
        BQAwTTELMAkGA1UEBhMCUFQxHDAaBgNVBAoME3N3aWZ0LWVmYXR1cmEgdGVzdHMx
        IDAeBgNVBAMMF1Rlc3QgYXV0aGVudGljYXRpb24ga2V5MB4XDTI2MTExMzAxMDcx
        NFoXDTM2MTExMDAxMDcxNFowTTELMAkGA1UEBhMCUFQxHDAaBgNVBAoME3N3aWZ0
        LWVmYXR1cmEgdGVzdHMxIDAeBgNVBAMMF1Rlc3QgYXV0aGVudGljYXRpb24ga2V5
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr4wKjA9AU14NuFYW9K+I
        5bAWyOp55YyZCcwCG/W7HrvyuLh8s7DCo3qanY84HZ+3Jk7WWUVzTiEWXuct98Fj
        xXmhL0sTvUu2LG9fZSMLrJ45GW9Esb0SbCiNv1ce2+ipCJd4O69OiDqEv6qV6mCW
        nnJlhBeWqsACfdTzRpYKNbemotqRvFrsyinHNWFYY1eNQeFd0RvSLC13LlzAHr6P
        Qt31OlVTccDJ1EbUA2WJC4zQiGfoTugWrD+AHU68JOUqqsxDWbLWZCJ5UlX2xiwy
        WepohRpy7xjcSMwis8A/ZlHMIvBmYdCw+r/awKQX+WoRUG1/Ztocv6E5yU9sxHDS
        +QIDAQABo1MwUTAdBgNVHQ4EFgQUeeXQffjOuNnFECl34Jbf3emcUdAwHwYDVR0j
        BBgwFoAUeeXQffjOuNnFECl34Jbf3emcUdAwDwYDVR0TAQH/BAUwAwEB/zANBgkq
        hkiG9w0BAQsFAAOCAQEAcUQp/q3FHYWNEMj0cNkZz7JGF6rKhN1X5HCSIRTyBc7l
        GdMP2NFuaoeU46QhJK1FdZhopIKiRFtSOPRr4gdvJAGKP79bu8dCF+2THV5QCL1T
        l+5nukjNqqYy1/7n49XrmTz5K0gvjVVCm2u9TnQQeIN+VY5peH16OIX/jxrtIeTY
        aV41O/nYFOSRZ9UXCkVWu/6wLp4MF5xd/u7of4u+arXKFd6jkur6wevmdvvpwi7B
        MR+fHZFpGElXbf5NZRJfJBv9LxoKoYHu02Pipik61ptDn9xac7tzVi534CTRtS3b
        k1B37iThZ1cgxHD/DO87206O+Vooa/Z+1LP48fN6/w==
        -----END CERTIFICATE-----
        """

    static let certificateDER = Data(base64Encoded: "MIIDezCCAmOgAwIBAgIUYe7A35PdPJyw7TTOv4AJk5YKMGswDQYJKoZIhvcNAQELBQAwTTELMAkGA1UEBhMCUFQxHDAaBgNVBAoME3N3aWZ0LWVmYXR1cmEgdGVzdHMxIDAeBgNVBAMMF1Rlc3QgYXV0aGVudGljYXRpb24ga2V5MB4XDTI2MTExMzAxMDcxNFoXDTM2MTExMDAxMDcxNFowTTELMAkGA1UEBhMCUFQxHDAaBgNVBAoME3N3aWZ0LWVmYXR1cmEgdGVzdHMxIDAeBgNVBAMMF1Rlc3QgYXV0aGVudGljYXRpb24ga2V5MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr4wKjA9AU14NuFYW9K+I5bAWyOp55YyZCcwCG/W7HrvyuLh8s7DCo3qanY84HZ+3Jk7WWUVzTiEWXuct98FjxXmhL0sTvUu2LG9fZSMLrJ45GW9Esb0SbCiNv1ce2+ipCJd4O69OiDqEv6qV6mCWnnJlhBeWqsACfdTzRpYKNbemotqRvFrsyinHNWFYY1eNQeFd0RvSLC13LlzAHr6PQt31OlVTccDJ1EbUA2WJC4zQiGfoTugWrD+AHU68JOUqqsxDWbLWZCJ5UlX2xiwyWepohRpy7xjcSMwis8A/ZlHMIvBmYdCw+r/awKQX+WoRUG1/Ztocv6E5yU9sxHDS+QIDAQABo1MwUTAdBgNVHQ4EFgQUeeXQffjOuNnFECl34Jbf3emcUdAwHwYDVR0jBBgwFoAUeeXQffjOuNnFECl34Jbf3emcUdAwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAcUQp/q3FHYWNEMj0cNkZz7JGF6rKhN1X5HCSIRTyBc7lGdMP2NFuaoeU46QhJK1FdZhopIKiRFtSOPRr4gdvJAGKP79bu8dCF+2THV5QCL1Tl+5nukjNqqYy1/7n49XrmTz5K0gvjVVCm2u9TnQQeIN+VY5peH16OIX/jxrtIeTYaV41O/nYFOSRZ9UXCkVWu/6wLp4MF5xd/u7of4u+arXKFd6jkur6wevmdvvpwi7BMR+fHZFpGElXbf5NZRJfJBv9LxoKoYHu02Pipik61ptDn9xac7tzVi534CTRtS3bk1B37iThZ1cgxHD/DO87206O+Vooa/Z+1LP48fN6/w==")!

    static let privateKeyPEM = """
        -----BEGIN PRIVATE KEY-----
        MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCvjAqMD0BTXg24
        Vhb0r4jlsBbI6nnljJkJzAIb9bseu/K4uHyzsMKjepqdjzgdn7cmTtZZRXNOIRZe
        5y33wWPFeaEvSxO9S7Ysb19lIwusnjkZb0SxvRJsKI2/Vx7b6KkIl3g7r06IOoS/
        qpXqYJaecmWEF5aqwAJ91PNGlgo1t6ai2pG8WuzKKcc1YVhjV41B4V3RG9IsLXcu
        XMAevo9C3fU6VVNxwMnURtQDZYkLjNCIZ+hO6BasP4AdTrwk5SqqzENZstZkInlS
        VfbGLDJZ6miFGnLvGNxIzCKzwD9mUcwi8GZh0LD6v9rApBf5ahFQbX9m2hy/oTnJ
        T2zEcNL5AgMBAAECggEAEhKrCVAOptFBkgSm+LT+X+tORTbCqvaGe6LkZV2EphLi
        gnsCjPtkkTEaVvX7ky0yIsBYwrhq478gpE+iWhCvxWZoHkwunD1TDuW+c//01TuK
        6bVHZLxwTPCrOz5Bv+aG9IqnnGQdg9qbzSHHrRQZnaFtwHjZ5aVpUZbJdFnBHlYo
        db+XMzAPFFLB4aMzIyZDi2nBvLbcaJgOhZ8wrasK4dnMKqb7pR1uJgFHg8LoKJjz
        TJRBkLkQxDP29cLn54tCoNxvtS7RE9S6t5XGbElAq7+1Pfb9IjFNFFkOzAoRf8UW
        tHn4M8nXHxPwtN6Y1u3wqaO1hUz9rmh4lYq2RNv2uwKBgQDx0bA7gYzbI7rWb4c1
        2XE092u1xNkAhGTqtK7agPEu7JRdtga1+4JomhH0Se7nUU6uofAx0mwLSv7u2oog
        fwJlEutcI6s8yieYE5OzGwD6yPQJThN+m7yUdrk94ScZBgWVru3Lu+FnwDY/kgLN
        Z0yYua1/GCRkOA4P1aUQKDt9BwKBgQC513FdrljYAh6l1dqpeNEqfQMSmjQ+oEjt
        SjF+QWsJEylY0d+ftzj5yaYAzUjgfU9udz7NB+WcmtOXnSNPltEQwGEGHDP4Lbhi
        i53fGFiduYICzQ841D6+wZ7s5oxRWfiB8tsWUo/sMSg/znE3pKH9+6rkpCKvJi29
        QRZVHS0v/wKBgEr6GQpaQLIxgdy699Faeh9SF7NkNWRTqHadTxmwoRdLgzULG0mR
        kf2cx7RWuBxAuYSr8S2BcL6PojusxucMelGcbB1FcfKHO3+LkmAWH1eitwerjZ/T
        6cSeixEEnnrDwzeF5XUl692fWzKaswO846L27zRY5++q8bE3LNa1orxBAoGAKZxV
        o9Yvyl3fIt6ZUSzeGJdZIscoP4WADrF4F37qSmPh9CM54PcTaMp/wto0IR+ts1w7
        0YidHs2D5wSmLWHlecy5bLbP5BfImzgLpzI6VUZ+F8Z2TBEp42hS/1Q3wtdUTzRj
        XcIqu4XeLzs4Gm9gXhAFmaAuq+zufNuf9nrL7V0CgYABZgsiImD2jxQHJoe4RuzS
        wBFEbuRtE4GaLEc2nmZ421mRDvEA02c7kYWn6TfdNIxkaVuC7ixl8ENiO6jQgcP5
        WKg0C4/JQU67/8w1qf0Aa99T866pMvnR01AVqmlNjOx/bUMw3ejJyYd8z9qhN3gn
        0GW6q6iLwsLcGLW/X+Sn0g==
        -----END PRIVATE KEY-----
        """

    static let nif = NIF("599999993")!

    static let successResponse = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
          <SOAP-ENV:Header/>
          <SOAP-ENV:Body>
            <ns2:InvoicesResponse xmlns:ns2="http://factemi.at.min_financas.pt/fatshareInvoices">
              <ns2:InvoicesList>
                <ns2:Invoice>
                  <ns2:InvoiceNo>FT 2026A/123</ns2:InvoiceNo>
                  <ns2:ATCUD>JFX7K2M9-123</ns2:ATCUD>
                  <ns2:InvoiceDate>2026-10-14</ns2:InvoiceDate>
                  <ns2:InvoiceType>FT</ns2:InvoiceType>
                  <ns2:SelfBillingIndicator>0</ns2:SelfBillingIndicator>
                  <ns2:TaxRegistrationNumber>501234560</ns2:TaxRegistrationNumber>
                  <ns2:CashVATSchemeIndicator></ns2:CashVATSchemeIndicator>
                  <ns2:Sector>C99</ns2:Sector>
                  <ns2:LineSummary>
                    <ns2:TaxPointDate>2026-10-14</ns2:TaxPointDate>
                    <ns2:DebitCreditIndicator>C</ns2:DebitCreditIndicator>
                    <ns2:TaxAmount>23.00</ns2:TaxAmount>
                    <ns2:NetAmount>100.00</ns2:NetAmount>
                    <ns2:GrossAmount>123.00</ns2:GrossAmount>
                    <ns2:TotalTaxBase>100.00</ns2:TotalTaxBase>
                    <ns2:Tax>
                      <ns2:TaxType>IVA</ns2:TaxType>
                      <ns2:TaxCountryRegion>PT</ns2:TaxCountryRegion>
                      <ns2:TaxCode>NOR</ns2:TaxCode>
                      <ns2:TaxPercentage>23.00</ns2:TaxPercentage>
                    </ns2:Tax>
                    <ns2:TaxExemptionCode></ns2:TaxExemptionCode>
                  </ns2:LineSummary>
                  <ns2:LineSummary>
                    <ns2:TaxPointDate>2026-10-14</ns2:TaxPointDate>
                    <ns2:DebitCreditIndicator>C</ns2:DebitCreditIndicator>
                    <ns2:TaxAmount>0.00</ns2:TaxAmount>
                    <ns2:NetAmount>10.10</ns2:NetAmount>
                    <ns2:GrossAmount>10.10</ns2:GrossAmount>
                    <ns2:TotalTaxBase>10.10</ns2:TotalTaxBase>
                    <ns2:Tax>
                      <ns2:TaxType>IVA</ns2:TaxType>
                      <ns2:TaxCountryRegion>PT</ns2:TaxCountryRegion>
                      <ns2:TaxCode>ISE</ns2:TaxCode>
                      <ns2:TaxPercentage>0.00</ns2:TaxPercentage>
                    </ns2:Tax>
                    <ns2:TaxExemptionCode>M07</ns2:TaxExemptionCode>
                  </ns2:LineSummary>
                  <ns2:TaxPayable>23.00</ns2:TaxPayable>
                  <ns2:NetTotal>110.10</ns2:NetTotal>
                  <ns2:GrossTotal>133.10</ns2:GrossTotal>
                </ns2:Invoice>
                <ns2:Invoice>
                  <ns2:InvoiceNo>NC B/7</ns2:InvoiceNo>
                  <ns2:ATCUD/>
                  <ns2:InvoiceDate>2026-10-31+01:00</ns2:InvoiceDate>
                  <ns2:InvoiceType>NC</ns2:InvoiceType>
                  <ns2:SelfBillingIndicator/>
                  <ns2:CustomerTaxID>FR12345678901</ns2:CustomerTaxID>
                  <ns2:CustomerTaxIDCountry>FR</ns2:CustomerTaxIDCountry>
                  <ns2:DocumentStatus>N</ns2:DocumentStatus>
                  <ns2:CashVATSchemeIndicator>1</ns2:CashVATSchemeIndicator>
                  <ns2:LineSummary>
                    <ns2:TaxPointDate>2026-10-31</ns2:TaxPointDate>
                    <ns2:DebitCreditIndicator>D</ns2:DebitCreditIndicator>
                    <ns2:TaxAmount>0.60</ns2:TaxAmount>
                    <ns2:NetAmount>10.00</ns2:NetAmount>
                    <ns2:GrossAmount>10.60</ns2:GrossAmount>
                    <ns2:TotalTaxBase>10.00</ns2:TotalTaxBase>
                    <ns2:Tax>
                      <ns2:TaxType>IVA</ns2:TaxType>
                      <ns2:TaxCountryRegion>PT</ns2:TaxCountryRegion>
                      <ns2:TaxCode>RED</ns2:TaxCode>
                      <ns2:TaxPercentage>6.00</ns2:TaxPercentage>
                      <ns2:TaxExemptionCode/>
                    </ns2:Tax>
                  </ns2:LineSummary>
                  <ns2:TaxPayable>0.60</ns2:TaxPayable>
                  <ns2:NetTotal>10.00</ns2:NetTotal>
                  <ns2:GrossTotal>10.60</ns2:GrossTotal>
                </ns2:Invoice>
                <ns2:PaginationTotal>
                  <ns2:totalDocs>2</ns2:totalDocs>
                  <ns2:totalDocsSent>2</ns2:totalDocsSent>
                  <ns2:totalPages>1</ns2:totalPages>
                  <ns2:nPage>1</ns2:nPage>
                </ns2:PaginationTotal>
              </ns2:InvoicesList>
              <ns2:estadoExecucao>
                <ns2:EstadoOperacao>200</ns2:EstadoOperacao>
                <ns2:Desc>Operação efetuada com sucesso.</ns2:Desc>
              </ns2:estadoExecucao>
            </ns2:InvoicesResponse>
          </SOAP-ENV:Body>
        </SOAP-ENV:Envelope>
        """

    static func statusResponse(code: Int, message: String) -> String {
        """
        <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/"><S:Body>
        <InvoicesResponse xmlns="http://factemi.at.min_financas.pt/fatshareInvoices">
        <estadoExecucao><EstadoOperacao>\(code)</EstadoOperacao><Desc>\(message)</Desc></estadoExecucao>
        </InvoicesResponse></S:Body></S:Envelope>
        """
    }

    /// A page holding `count` minimal invoices, numbered from `first`.
    static func pageResponse(first: Int, count: Int, page: Int, totalPages: Int, totalDocs: Int, date: String) -> String {
        let invoices = (first..<first + count).map { n in
            """
            <Invoice><InvoiceNo>FT A/\(n)</InvoiceNo><ATCUD>AAAA-\(n)</ATCUD><InvoiceDate>\(date)</InvoiceDate>\
            <InvoiceType>FT</InvoiceType><SelfBillingIndicator>0</SelfBillingIndicator>\
            <TaxRegistrationNumber>501234560</TaxRegistrationNumber><CashVATSchemeIndicator>0</CashVATSchemeIndicator>\
            <TaxPayable>0.23</TaxPayable><NetTotal>1.00</NetTotal><GrossTotal>1.23</GrossTotal></Invoice>
            """
        }.joined()
        return """
            <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/"><S:Body>
            <InvoicesResponse xmlns="http://factemi.at.min_financas.pt/fatshareInvoices"><InvoicesList>\(invoices)
            <PaginationTotal><totalDocs>\(totalDocs)</totalDocs><totalDocsSent>\(count)</totalDocsSent>\
            <totalPages>\(totalPages)</totalPages><nPage>\(page)</nPage></PaginationTotal></InvoicesList>
            <estadoExecucao><EstadoOperacao>200</EstadoOperacao><Desc>OK</Desc></estadoExecucao>
            </InvoicesResponse></S:Body></S:Envelope>
            """
    }

    /// AT's test environment, 13 Nov 2026: the consult answer listing two test invoices that
    /// efatura-live-check registered (fake data, sold to the final consumer 999999990). Kept as AT
    /// sent it apart from line breaks; the query was made as issuer, whose NIF does not appear here.
    static let realATList = """
        <?xml version="1.0" encoding="UTF-8"?><env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"><env:Header/><env:Body>\
        <InvoicesResponse xmlns="http://factemi.at.min_financas.pt/fatshareInvoices"><InvoicesList>\
        <Invoice><SoftwareCertificateNumber>0</SoftwareCertificateNumber><InvoiceNo>FT PAPELADATESTE/1794594338</InvoiceNo>\
        <ATCUD>0</ATCUD><InvoiceDate>2026-11-13</InvoiceDate><InvoiceType>FT</InvoiceType><SelfBillingIndicator>0</SelfBillingIndicator>\
        <CustomerTaxID>999999990</CustomerTaxID><CustomerTaxIDCountry>PT</CustomerTaxIDCountry><DocumentStatus>N</DocumentStatus>\
        <CashVATSchemeIndicator>0</CashVATSchemeIndicator><EACCode/><LineSummary><TaxPointDate>2026-11-13</TaxPointDate>\
        <DebitCreditIndicator>C</DebitCreditIndicator><TaxAmount>2.3</TaxAmount><NetAmount>0</NetAmount><GrossAmount>2.3</GrossAmount>\
        <TotalTaxBase>10</TotalTaxBase><Tax><TaxType>IVA</TaxType><TaxCountryRegion>PT</TaxCountryRegion><TaxCode>NOR</TaxCode>\
        <TaxPercentage>23</TaxPercentage></Tax><TaxExemptionCode/></LineSummary><TaxPayable>2.3</TaxPayable><NetTotal>10</NetTotal>\
        <GrossTotal>12.3</GrossTotal></Invoice>\
        <Invoice><SoftwareCertificateNumber>0</SoftwareCertificateNumber><InvoiceNo>FT PAPELADATESTE/1794594440</InvoiceNo>\
        <ATCUD>0</ATCUD><InvoiceDate>2026-11-13</InvoiceDate><InvoiceType>FT</InvoiceType><SelfBillingIndicator>0</SelfBillingIndicator>\
        <CustomerTaxID>999999990</CustomerTaxID><CustomerTaxIDCountry>PT</CustomerTaxIDCountry><DocumentStatus>N</DocumentStatus>\
        <CashVATSchemeIndicator>0</CashVATSchemeIndicator><EACCode/><LineSummary><TaxPointDate>2026-11-13</TaxPointDate>\
        <DebitCreditIndicator>C</DebitCreditIndicator><TaxAmount>2.3</TaxAmount><NetAmount>0</NetAmount><GrossAmount>2.3</GrossAmount>\
        <TotalTaxBase>10</TotalTaxBase><Tax><TaxType>IVA</TaxType><TaxCountryRegion>PT</TaxCountryRegion><TaxCode>NOR</TaxCode>\
        <TaxPercentage>23</TaxPercentage></Tax><TaxExemptionCode/></LineSummary><TaxPayable>2.3</TaxPayable><NetTotal>10</NetTotal>\
        <GrossTotal>12.3</GrossTotal></Invoice>\
        <PaginationTotal><totalDocs>2</totalDocs><totalDocsSent>2</totalDocsSent><totalPages>1</totalPages><nPage>1</nPage></PaginationTotal>\
        </InvoicesList><estadoExecucao><EstadoOperacao>200</EstadoOperacao><Desc>Consulta efetuada com sucesso.</Desc></estadoExecucao>\
        </InvoicesResponse></env:Body></env:Envelope>
        """
}
