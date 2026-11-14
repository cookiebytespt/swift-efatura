# swift-efatura

A Swift client for the e-Fatura invoice-consultation webservice of the Portuguese Tax and Customs Authority (Autoridade Tributária e Aduaneira, AT). It returns the invoices AT has on record for a taxpayer, as buyer or as issuer.

It builds the SOAP request and AT's encrypted WS-Security header, sends it over mutual TLS, and returns typed invoices. It runs on macOS and Linux, and fits server-side Swift (Vapor, Hummingbird).

The library only reads. It cannot register, change or cancel invoices.

> **Status:** early, not yet tagged. Tested against AT's test environment: authentication, an empty month, and a list of invoices read back field for field. Not yet run against production. See [What has been confirmed against AT](#what-has-been-confirmed-against-at).

This project is not affiliated with or endorsed by AT.

## Requirements

- Swift 6.0 or newer
- macOS 13 or newer, or Linux
- Access to AT's webservice: a sub-user, AT's authentication public key and a client certificate (see [Getting access from AT](#getting-access-from-at))
- Outbound TCP to `servicos.portaldasfinancas.gov.pt` on port 725 (test) or 425 (production). Some networks only allow ports 80 and 443 out.

## Installation

Add the package to `Package.swift`. Until the first release, depend on the branch:

```swift
dependencies: [
    .package(url: "https://github.com/cookiebytespt/swift-efatura.git", branch: "main"),
],
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "EFatura", package: "swift-efatura"),
            .product(name: "EFaturaAsyncHTTPClient", package: "swift-efatura"),
        ]
    ),
]
```

| Product | What it is |
| --- | --- |
| `EFatura` | The client: request, security header, response parser and types. No networking: it talks to anything that conforms to `EFaturaTransport`, which makes it easy to test with a stub. |
| `EFaturaAsyncHTTPClient` | The mutual-TLS transport, on AsyncHTTPClient and SwiftNIO SSL. |

## Getting access from AT

| Item | Where it comes from | Used as |
| --- | --- | --- |
| Sub-user and password | Portal das Finanças > Autenticação de Contribuintes > Gestão de Utilizadores, on the taxpayer's account. Format `NIF/UserId`. | `EFaturaCredentials` |
| Authentication public key | Emailed by AT on request (asi-cd@at.gov.pt), as a `.cer`. It encrypts the password header. | `ATAuthenticationKey` |
| Client certificate and key | **Test:** the certificate AT emails with the public key. **Production:** your own key and CSR, signed by AT through e-Fatura > Produtores de Software > Aderir ao Serviço, valid 12 months. | `EFaturaClientIdentity` |

Use a sub-user, never the taxpayer's main password. The certificate, private key and password are secrets: the `.gitignore` excludes the usual file types, but keep them out of any repository anyway.

## Usage

```swift
import EFatura
import EFaturaAsyncHTTPClient
import Foundation

let nif = NIF("599999993")!

let transport = AsyncHTTPClientTransport(
    identity: try .pem(certificateFile: "/run/secrets/at-cert.pem", privateKeyFile: "/run/secrets/at-key.pem")
)

let client = EFaturaClient(
    environment: .test,  // or .production
    credentials: EFaturaCredentials(nif: nif, subuser: "1", password: password),
    authenticationKey: try ATAuthenticationKey(contentsOf: URL(fileURLWithPath: "/run/secrets/at-auth.cer")),
    transport: transport
)

// Everything issued to the company in the third quarter.
let invoices = try await client.allInvoices(
    for: .buyer(nif),
    from: CalendarDay("2026-07-01")!,
    to: CalendarDay("2026-09-30")!
)

for invoice in invoices {
    print(invoice.date, invoice.issuerNIF ?? "-", invoice.number, invoice.grossTotal.cents)
}

try await transport.shutdown()
```

- `allInvoices(for:from:to:)` takes any period, sends one request per calendar month and follows the pages.
- `invoices(_:)` fetches a single page, for when you want control.
- `.buyer(nif)` reads what was issued to the taxpayer (its purchases); `.issuer(nif)` reads what it issued.
- The client certificate can also come from PEM strings (`.pem(certificate:privateKey:)`) or a PKCS#12 file (`.pkcs12(file:passphrase:)`).
- In Vapor, create the transport once at startup and shut it down with the application.

## What comes back

Each `Invoice` carries the document number, ATCUD, date, type (`FT`, `FS`, `FR`, `NC`, …), the counterparty's tax number, the tax breakdown per rate (`lines`) and the net, tax and gross totals as `Decimal`. `.cents` turns an amount into integer cents.

- AT returns no PDF and no names. Asking as buyer gives the issuer's NIF only.
- For amounts, use the document totals and each line's `totalTaxBase` and `taxAmount`. A line's `netAmount` and `grossAmount` depend on how the issuer's software reported it: AT can return `netAmount` 0 and `grossAmount` equal to the tax alone.
- Some fields are returned only to the issuer (software certificate number, status, activity code) or only to the buyer (sector). They are optional in the model.

## Limits AT sets

- One request covers at most one month. `allInvoices` splits longer periods for you.
- Up to 5,000 documents per page.
- The NIF in the query must be the NIF of the credentials.
- The host's clock must be accurate: the header carries an encrypted timestamp.

## Errors

`EFaturaError.rejected(status)` carries AT's code and message, and `status.kind` groups them:

| Codes | Kind | Meaning |
| --- | --- | --- |
| 200 | `.success` | |
| 1–99 | `.authentication` | Sub-user, password, session key or timestamp refused (99: password validation failed) |
| 310–330 | `.structure` | NIF or a date is missing |
| 410–454 | `.content` | 414 NIF differs from the login, 422 year not available, 434 period over one month, 444 page beyond the last |
| 486 | — | "Lista de faturas vazia": nothing in the period. Not thrown; returned as an empty page |
| 598, 599 | `.server` | AT internal error; retry later |

The other cases are `.soapFault`, `.http` (an answer that is not SOAP), `.malformedResponse`, `.invalidRequest` (refused before sending) and `.invalidAuthenticationKey`.

## Live check

`Tools/live-check` is a command-line tool that runs this package against AT's real webservice and reports each step. Use it for a first connection or for debugging. It is a separate package, so the library ships no executable.

```
cd Tools/live-check
export EFATURA_CERT=~/at/test-cert.pem EFATURA_KEY=~/at/test-key.pem
export EFATURA_AUTH_KEY=~/at/auth-key.cer EFATURA_USERNAME=599999993/1
swift run efatura-live-check --month 2026-10 --dump /tmp/efatura
```

- It asks for the password when `EFATURA_PASSWORD` is not set.
- Before any SOAP it tests a plain TCP connection to AT's port, then a TLS handshake with the client certificate.
- It sends one request on its own, so a failure is reported clearly, then reads the whole period and prints the documents and totals.
- On failure it says which kind it was (port blocked, server not trusted, client certificate refused, AT silent, credentials) and what to check.
- `--dump DIR` writes every request and response, plus `run.log` with everything the tool printed.
- `--register-test-invoice` works in the test environment only. It registers a fake invoice through AT's test sending service, then reads it back and compares every field. It is the way to see a real list before production. This is the only place anything is written to AT, through an API hidden behind `@_spi(Testing)`; the tool refuses it outside the test environment.

Run `--help` for the other options.

## What has been confirmed against AT

Against AT's test environment, from macOS, in November 2026:

- The security header is accepted as built: RSA PKCS#1 v1.5 for the session key, AES/ECB/PKCS#5 for password and timestamp, timestamp with milliseconds.
- AT's test certificate works as the client certificate, and macOS trusts AT's server certificate.
- A period with no documents answers code 486, which the client returns as an empty page.
- A list of invoices parses field for field. AT drops trailing zeros (`2.3`, `10`) and sends empty elements (`<EACCode/>`). That answer is kept as a test.

Still open:

1. Real invoices from certified software, in production.
2. Whether authentication failures arrive as status codes or as SOAP faults. Both are handled.
3. Whether a Linux container's trust store accepts AT's server certificate. `additionalTrustRoots` is there if it does not.

## Notes on the implementation

- **macOS.** The transport always runs AsyncHTTPClient on SwiftNIO sockets with BoringSSL. AsyncHTTPClient's default on Apple platforms, Network.framework, cannot present a client certificate given this way and stops the process.
- **Encryption.** The security header uses AES in ECB mode because AT's specification requires it. Each request uses a fresh key, used for two short values only.
- **Dependencies.** swift-crypto, swift-certificates, swift-nio, swift-nio-ssl and async-http-client.

## Tests

```
swift test
```

The certificate and key in `Tests/EFaturaTests/Fixtures.swift` were generated for the tests and protect nothing. Two fixtures are real answers from AT's test environment, about fake test invoices.

## Contributing

Issues and pull requests are welcome. Please never include certificates, keys, passwords or real taxpayer data in an issue or a test.

## License

MIT. See [LICENSE](LICENSE).

## References

- [AT: e-Fatura webservice documentation and WSDLs](https://info.portaldasfinancas.gov.pt/pt/apoio_ao_contribuinte/Outras_entidades/Suporte_tecnologico/Webservice/e_Fatura)
