// efatura-live-check: reads one or more months of invoices from AT's e-Fatura
// webservice and prints what came back, with enough detail to debug a first run.
//
// Configuration comes from environment variables, so no secret lands in shell history:
//
//   EFATURA_USERNAME      sub-user, NIF/UserId                      (asked if missing)
//   EFATURA_PASSWORD      sub-user password                         (asked if missing, hidden)
//   EFATURA_CERT          client certificate, PEM  ┐ or EFATURA_PFX and
//   EFATURA_KEY           client private key, PEM  ┘    EFATURA_PFX_PASSWORD
//   EFATURA_AUTH_KEY      AT's public encryption key (.cer, PEM or DER)
//   EFATURA_ENV           test (default) or production
//   EFATURA_URL           overrides the endpoint, for trying the tool against a local mock
//
// Options:
//   --month YYYY-MM       one month (default: last month)
//   --from YYYY-MM-DD --to YYYY-MM-DD
//                         any period; it is split into months
//   --as buyer|issuer     whose documents to read (default: buyer)
//   --nif NIF             NIF to query (default: the one in EFATURA_USERNAME)
//   --page-size N         documents per page, 1–5000 (default: 5000)
//   --dump DIR            write every request and response XML to DIR, plus run.log with
//                         everything printed, so the folder alone tells what happened
//   --ca FILE             extra CA certificate (PEM) to trust for AT's server
//   --register-test-invoice
//                         TEST ONLY: register a fake invoice through AT's test sending service,
//                         then read it back and compare (see TestInvoice.swift)
//   --atcud VALUE         ATCUD for the test invoice (default "0")
//
//   EFATURA_SEND_URL      overrides the test sending endpoint, for a local mock

import EFatura
import EFaturaAsyncHTTPClient
import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOTLS
import X509

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: Output

/// Everything printed also goes to run.log in the dump folder, when there is one.
nonisolated(unsafe) var logHandle: FileHandle?
/// What the tool is doing right now, for the Ctrl-C note.
nonisolated(unsafe) var currentStage = "starting"
nonisolated(unsafe) var stageStarted = Date()

func emit(_ line: String, toStandardError: Bool = false) {
    if toStandardError {
        fflush(nil)  // all streams, so stdout lands before the error
        FileHandle.standardError.write(Data((line + "\n").utf8))
    } else {
        print(line)
    }
    logHandle?.write(Data((line + "\n").utf8))
}

func say(_ text: String = "") { emit(text) }
func step(_ text: String) { emit("\n▸ \(text)") }
func ok(_ text: String) { emit("  ✓ \(text)") }
func info(_ text: String) { emit("    \(text)") }
func fail(_ text: String) -> Never {
    emit("\n✗ \(text)", toStandardError: true)
    try? logHandle?.synchronize()
    exit(1)
}

func setStage(_ text: String) {
    currentStage = text
    stageStarted = Date()
}

func seconds(since start: Date) -> String {
    String(format: "%.1f s", Date().timeIntervalSince(start))
}

/// Prints a line every 10 seconds while `body` runs, so a hang is visible as one.
func withHeartbeat<T: Sendable>(_ body: () async throws -> T) async throws -> T {
    let started = Date()
    let heartbeat = Task {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { break }
            info("… still waiting (\(Int(Date().timeIntervalSince(started))) s)")
        }
    }
    defer { heartbeat.cancel() }
    return try await body()
}

func euros(_ value: Decimal) -> String {
    let cents = value.cents
    let sign = cents < 0 ? "-" : ""
    let absolute = abs(cents)
    let fraction = String(absolute % 100)
    return "\(sign)\(absolute / 100),\(fraction.count == 1 ? "0" + fraction : fraction) €"
}

func padded(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

// MARK: Arguments

struct Options {
    var start: CalendarDay
    var end: CalendarDay
    var asIssuer = false
    var nif: NIF?
    var pageSize = InvoiceQuery.maximumPageSize
    var dumpDirectory: URL?
    var extraCA: String?
    var registerTestInvoice = false
    var atcud = "0"
}

func lastMonth() -> (CalendarDay, CalendarDay) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
    let now = calendar.dateComponents([.year, .month], from: Date())
    let year = now.month! == 1 ? now.year! - 1 : now.year!
    let month = now.month! == 1 ? 12 : now.month! - 1
    let first = CalendarDay(year: year, month: month, day: 1)!
    return (first, first.lastOfMonth)
}

func parseOptions() -> Options {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let (defaultStart, defaultEnd) = lastMonth()
    var options = Options(start: defaultStart, end: defaultEnd)
    var from: CalendarDay?
    var to: CalendarDay?

    func value(for flag: String) -> String {
        guard !arguments.isEmpty else { fail("\(flag) needs a value") }
        return arguments.removeFirst()
    }

    while !arguments.isEmpty {
        let flag = arguments.removeFirst()
        switch flag {
        case "--month":
            let text = value(for: flag)
            guard let first = CalendarDay(text + "-01") else { fail("--month must be YYYY-MM, got \(text)") }
            from = first
            to = first.lastOfMonth
        case "--from":
            let text = value(for: flag)
            guard let day = CalendarDay(text) else { fail("--from must be YYYY-MM-DD, got \(text)") }
            from = day
        case "--to":
            let text = value(for: flag)
            guard let day = CalendarDay(text) else { fail("--to must be YYYY-MM-DD, got \(text)") }
            to = day
        case "--as":
            switch value(for: flag) {
            case "buyer": options.asIssuer = false
            case "issuer": options.asIssuer = true
            case let other: fail("--as must be buyer or issuer, got \(other)")
            }
        case "--nif":
            let text = value(for: flag)
            guard let nif = NIF(text) else { fail("\(text) is not a valid NIF") }
            options.nif = nif
        case "--page-size":
            let text = value(for: flag)
            guard let size = Int(text), (1...InvoiceQuery.maximumPageSize).contains(size) else {
                fail("--page-size must be between 1 and \(InvoiceQuery.maximumPageSize)")
            }
            options.pageSize = size
        case "--dump":
            options.dumpDirectory = URL(fileURLWithPath: value(for: flag), isDirectory: true)
        case "--ca":
            options.extraCA = value(for: flag)
        case "--register-test-invoice":
            options.registerTestInvoice = true
        case "--atcud":
            options.atcud = value(for: flag)
        case "-h", "--help":
            say("Usage: efatura-live-check [--month YYYY-MM | --from YYYY-MM-DD --to YYYY-MM-DD] "
                + "[--as buyer|issuer] [--nif NIF] [--page-size N] [--dump DIR] [--ca FILE] "
                + "[--register-test-invoice [--atcud VALUE]]")
            say("Configuration is read from EFATURA_* environment variables; see the top of main.swift.")
            exit(0)
        default:
            fail("Unknown option \(flag). Try --help.")
        }
    }
    if let from { options.start = from }
    if let to { options.end = to }
    if from != nil && to == nil { options.end = options.start.lastOfMonth }
    guard options.start <= options.end else { fail("The period ends before it starts.") }
    return options
}

// MARK: Configuration

let environment = ProcessInfo.processInfo.environment

func setting(_ name: String) -> String? {
    guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

func requiredFile(_ name: String) -> String {
    guard let path = setting(name) else { fail("Set \(name) to the file's path.") }
    let expanded = (path as NSString).expandingTildeInPath
    guard FileManager.default.isReadableFile(atPath: expanded) else { fail("\(name): cannot read \(expanded)") }
    return expanded
}

func askLine(_ prompt: String) -> String {
    print(prompt, terminator: "")
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
        fail("Nothing entered.")
    }
    return line
}

func askSecret(_ prompt: String) -> String {
    guard let raw = getpass(prompt) else { fail("Could not read the password.") }
    let value = String(cString: raw)
    guard !value.isEmpty else { fail("No password entered.") }
    return value
}

/// Describes a certificate file in one line: subject, issuer and how long it is still valid.
func describeCertificate(atPath path: String) -> String? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let begin = text.range(of: "-----BEGIN CERTIFICATE-----"),
          let end = text.range(of: "-----END CERTIFICATE-----", range: begin.upperBound..<text.endIndex),
          let certificate = try? Certificate(pemEncoded: String(text[begin.lowerBound..<end.upperBound]))
    else { return nil }
    let days = Int(certificate.notValidAfter.timeIntervalSinceNow / 86_400)
    let validity = days >= 0 ? "valid for \(days) more days" : "EXPIRED \(-days) days ago"
    return "\(certificate.subject) — issued by \(certificate.issuer) — \(validity)"
}

// MARK: Dumping transport

/// Passes requests through and writes each request and response to a folder.
/// The request holds the username in clear; the password and timestamp are encrypted
/// with a key used once, but treat the folder as private anyway.
actor DumpCounter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

struct DumpingTransport: EFaturaTransport {
    let inner: any EFaturaTransport
    let directory: URL
    let counter = DumpCounter()

    func send(_ request: EFaturaHTTPRequest) async throws -> EFaturaHTTPResponse {
        let number = await counter.next()
        let prefix = String(format: "%03d", number)
        try request.body.write(to: directory.appendingPathComponent("\(prefix)-request.xml"))
        do {
            let response = try await inner.send(request)
            try response.body.write(to: directory.appendingPathComponent("\(prefix)-response-http\(response.status).xml"))
            return response
        } catch {
            try? Data("\(error)".utf8).write(to: directory.appendingPathComponent("\(prefix)-transport-error.txt"))
            throw error
        }
    }
}

// MARK: Explaining failures

func explain(_ error: any Error) -> Never {
    var lines: [String] = []
    switch error {
    case EFaturaError.rejected(let status):
        lines.append("AT refused the request: \(status.code) — \(status.message)")
        switch status.kind {
        case .authentication:
            lines += [
                "This is an authentication code. In order of likelihood:",
                "• the sub-user or its password is wrong, or the sub-user lacks permission for this service;",
                "• this Mac's clock is off (the timestamp is checked);",
                "• the Nonce padding is not what AT expects (see the README, \"Not yet confirmed\").",
                "Run again with --dump DIR and keep the files for comparison.",
            ]
        case .content where status.code == EFaturaStatus.nifDoesNotMatchLogin:
            lines.append("The NIF queried must be the sub-user's NIF. Drop --nif or fix EFATURA_USERNAME.")
        case .content where status.code == EFaturaStatus.yearNotAvailable:
            lines.append("AT does not serve that year here. Try a more recent month.")
        case .server:
            lines.append("AT's side failed. Try again in a few minutes.")
        default:
            break
        }
    case EFaturaError.soapFault(let code, let message):
        lines.append("AT answered with a SOAP fault: \(code) — \(message)")
        lines.append("Run again with --dump DIR to see the full request and response.")
    case EFaturaError.http(let status, let body):
        lines.append("AT answered HTTP \(status) without a SOAP body:")
        lines.append(body)
        if status == 401 || status == 403 {
            lines.append("The client certificate was probably not accepted for this endpoint.")
        }
    case EFaturaError.malformedResponse(let reason):
        lines.append("The response could not be read: \(reason)")
        lines.append("Run again with --dump DIR and look at the response file; the parser may need adjusting.")
    default:
        let text = "\(error)"
        lines.append("Request failed: \(text)")
        if text.contains("deadlineExceeded") || text.contains("readTimeout") {
            lines.append("The connection and TLS handshake worked, but AT did not answer within 60 s.")
            lines.append("If AT refused the client certificate it would usually say so; silence more often means")
            lines.append("its test service is slow or down. Try again later; if it keeps happening, the request in")
            lines.append("the dump folder is what to show AT through e-balcão.")
        } else if text.contains("CERTIFICATE_VERIFY_FAILED") {
            lines.append("This machine does not trust AT's server certificate. Find the CA that issued it")
            lines.append("(openssl s_client -connect servicos.portaldasfinancas.gov.pt:725 -showcerts) and pass it with --ca.")
        } else if ["UNKNOWN_CA", "BAD_CERTIFICATE", "CERTIFICATE_REQUIRED", "CERTIFICATE_UNKNOWN", "HANDSHAKE_FAILURE",
                   "ACCESS_DENIED"].contains(where: text.contains) {
            lines.append("AT refused the client certificate. Check that EFATURA_CERT/EFATURA_KEY (or EFATURA_PFX)")
            lines.append("hold AT's test certificate for the test environment, or the signed one for production.")
        } else if error is NIOSSLError || text.localizedCaseInsensitiveContains("ssl")
            || text.localizedCaseInsensitiveContains("tls") || text.localizedCaseInsensitiveContains("handshake") {
            lines.append("TLS failed: either AT refused the client certificate, or this machine does not trust")
            lines.append("AT's server certificate (pass its CA with --ca).")
        } else if text.localizedCaseInsensitiveContains("connect") || text.localizedCaseInsensitiveContains("timeout")
            || text.localizedCaseInsensitiveContains("timed out") {
            lines.append("AT's port could not be reached. Ports 725 (test) and 425 (production) must be open outbound;")
            lines.append("some networks and VPNs block non-standard ports.")
        }
    }
    fail(lines.joined(separator: "\n  "))
}

// MARK: Run

let options = parseOptions()

if let dump = options.dumpDirectory {
    do {
        try FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
        let logURL = dump.appendingPathComponent("run.log")
        _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try FileHandle(forWritingTo: logURL)
    } catch {
        fail("--dump: \(error)")
    }
}

// Ctrl-C leaves a note saying where the run was, instead of nothing.
signal(SIGINT, SIG_IGN)
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
interruptSource.setEventHandler {
    emit("\n✗ Interrupted while \(currentStage), after \(seconds(since: stageStarted)).", toStandardError: true)
    try? logHandle?.synchronize()
    exit(130)
}
interruptSource.resume()

say("Started \(ISO8601DateFormatter().string(from: Date())) — \(CommandLine.arguments.dropFirst().joined(separator: " "))")

let environmentName = setting("EFATURA_ENV") ?? "test"
var atEnvironment: EFaturaEnvironment
switch environmentName {
case "test": atEnvironment = .test
case "production": atEnvironment = .production
default: fail("EFATURA_ENV must be test or production, got \(environmentName).")
}
if options.registerTestInvoice && environmentName != "test" {
    fail("--register-test-invoice creates a fake invoice, so it runs only with EFATURA_ENV=test.")
}
if let override = setting("EFATURA_URL") {
    guard let url = URL(string: override), url.scheme == "https" else { fail("EFATURA_URL must be an https URL.") }
    atEnvironment = EFaturaEnvironment(invoicesURL: url)
}

say("e-Fatura live check — \(environmentName) environment")
say("  \(atEnvironment.invoicesURL.absoluteString)")

step("Loading certificates and keys")

let authenticationKeyPath = requiredFile("EFATURA_AUTH_KEY")
let authenticationKey: ATAuthenticationKey
do {
    authenticationKey = try ATAuthenticationKey(contentsOf: URL(fileURLWithPath: authenticationKeyPath))
} catch {
    fail("AT public key: \(error)")
}
ok("AT public key: \((authenticationKeyPath as NSString).lastPathComponent)")
if let description = describeCertificate(atPath: authenticationKeyPath) { info(description) }

let identity: EFaturaClientIdentity
if let pfx = setting("EFATURA_PFX") {
    let path = requiredFile("EFATURA_PFX")
    let passphrase = setting("EFATURA_PFX_PASSWORD") ?? askSecret("Passphrase for \((pfx as NSString).lastPathComponent): ")
    do {
        identity = try .pkcs12(file: path, passphrase: passphrase)
    } catch {
        fail("Client certificate (.pfx): \(error)\n  If it is an older bundle, convert it: openssl pkcs12 -legacy -in file.pfx -nodes -out file.pem")
    }
    ok("Client certificate: \((path as NSString).lastPathComponent)")
} else {
    let certificatePath = requiredFile("EFATURA_CERT")
    let keyPath = requiredFile("EFATURA_KEY")
    do {
        identity = try .pem(certificateFile: certificatePath, privateKeyFile: keyPath)
    } catch {
        fail("Client certificate or key: \(error)")
    }
    ok("Client certificate: \((certificatePath as NSString).lastPathComponent)")
    if let description = describeCertificate(atPath: certificatePath) { info(description) }
}

var extraRoots: [NIOSSLCertificate] = []
if let ca = options.extraCA {
    do {
        extraRoots = try NIOSSLCertificate.fromPEMFile((ca as NSString).expandingTildeInPath)
    } catch {
        fail("--ca: \(error)")
    }
    ok("Extra trusted CA: \((ca as NSString).lastPathComponent)")
}

step("Credentials")

let username = setting("EFATURA_USERNAME") ?? askLine("Sub-user (NIF/UserId): ")
let password = setting("EFATURA_PASSWORD") ?? askSecret("Password for \(username): ")
let credentials = EFaturaCredentials(username: username, password: password)
guard let queryNIF = options.nif ?? credentials.nif else {
    fail("\(username) does not start with a valid NIF. Use the form NIF/UserId, or pass --nif.")
}
ok("Sub-user \(username)")
let party: InvoiceParty = options.asIssuer ? .issuer(queryNIF) : .buyer(queryNIF)
info("Querying documents where \(queryNIF) is the \(options.asIssuer ? "issuer" : "buyer")")

let utc = ISO8601DateFormatter()
info("This machine's clock (UTC): \(utc.string(from: Date())) — AT checks it, so it must be accurate")

if let dump = options.dumpDirectory {
    info("Writing the log, requests and responses to \(dump.path)")
}

// MARK: Connection check

/// Fulfils a promise when the TLS handshake completes or fails.
final class HandshakeWatcher: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let promise: EventLoopPromise<Void>
    private var finished = false

    init(promise: EventLoopPromise<Void>) {
        self.promise = promise
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let tlsEvent = event as? TLSUserEvent, case .handshakeCompleted = tlsEvent {
            finish(nil)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        finish(error)
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish(ChannelError.eof)
        context.fireChannelInactive()
    }

    private func finish(_ error: (any Error)?) {
        guard !finished else { return }
        finished = true
        if let error { promise.fail(error) } else { promise.succeed(()) }
    }
}

struct HandshakeTimeout: Error, CustomStringConvertible {
    var description: String { "no TLS handshake within 20 s" }
}

/// Opens a plain TCP connection, then a TLS one with the client certificate, before any SOAP,
/// so a network block, a trust problem and a refused certificate each show up on their own.
func checkConnection(to url: URL, tls: TLSConfiguration) async {
    guard let host = url.host else { fail("The endpoint URL has no host.") }
    let port = url.port ?? 443
    let group = MultiThreadedEventLoopGroup.singleton

    step("Connection to \(host):\(port)")

    setStage("opening a TCP connection to \(host):\(port)")
    var started = Date()
    do {
        let channel = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .connect(host: host, port: port)
            .get()
        ok("TCP connection to \(channel.remoteAddress?.description ?? host) in \(seconds(since: started))")
        try? await channel.close().get()
    } catch {
        fail("""
            No TCP connection to \(host):\(port) after \(seconds(since: started)): \(error)
              The port is blocked between this machine and AT, or AT is down. Many routers, VPNs and
              firewalls allow only ports 80 and 443 out. Try another network (a phone hotspot is a quick test),
              or allow TCP \(port) to \(host) in the firewall.
            """)
    }

    setStage("doing the TLS handshake with \(host):\(port)")
    started = Date()
    do {
        let sslContext = try NIOSSLContext(configuration: tls)
        let eventLoop = group.next()
        let handshake = eventLoop.makePromise(of: Void.self)
        let channel = try await ClientBootstrap(group: eventLoop)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: sslContext, serverHostname: host)
                    )
                    try channel.pipeline.syncOperations.addHandler(HandshakeWatcher(promise: handshake))
                }
            }
            .connect(host: host, port: port)
            .get()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await handshake.futureResult.get() }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                channel.close(promise: nil)
                throw HandshakeTimeout()
            }
            try await group.next()
            group.cancelAll()
        }
        ok("TLS handshake in \(seconds(since: started)); this machine trusts AT's server certificate")
        info("Whether AT accepts the client certificate shows on the first request")
        try? await channel.close().get()
    } catch {
        let text = "\(error)"
        var advice = ["TLS handshake failed after \(seconds(since: started)): \(text)"]
        if text.contains("CERTIFICATE_VERIFY_FAILED") {
            advice.append("This machine does not trust AT's server certificate. See its chain with")
            advice.append("openssl s_client -connect \(host):\(port) -showcerts, and pass the issuing CA with --ca.")
        } else if error is HandshakeTimeout {
            advice.append("The connection opened but AT never completed the handshake. Something on the path")
            advice.append("(a firewall or proxy doing TLS inspection) may be interfering with port \(port).")
        } else {
            advice.append("AT refused the connection during the handshake, most likely the client certificate.")
            advice.append("Check that it is AT's test certificate for the test environment, or the signed one for production.")
        }
        fail(advice.joined(separator: "\n  "))
    }
}

let clientTLS: TLSConfiguration = identity.tlsConfiguration(additionalTrustRoots: extraRoots)
await checkConnection(to: atEnvironment.invoicesURL, tls: clientTLS)

let httpTransport = AsyncHTTPClientTransport(identity: identity, additionalTrustRoots: extraRoots)
let transport: any EFaturaTransport = options.dumpDirectory.map {
    DumpingTransport(inner: httpTransport, directory: $0)
} ?? httpTransport

let client = EFaturaClient(
    environment: atEnvironment,
    credentials: credentials,
    authenticationKey: authenticationKey,
    transport: transport
)

if options.registerTestInvoice {
    let sendingURL: URL
    if let override = setting("EFATURA_SEND_URL") {
        guard let url = URL(string: override), url.scheme == "https" else { fail("EFATURA_SEND_URL must be an https URL.") }
        sendingURL = url
    } else {
        sendingURL = defaultTestSendingURL
    }
    guard sendingURL.port != 423 else { fail("Port 423 is AT's production sending service; refusing.") }
    await registerTestInvoice(client: client, issuer: queryNIF, atcud: options.atcud, sendingURL: sendingURL, tls: clientTLS)
}

let months = CalendarDay.monthlyRanges(from: options.start, to: options.end)
var invoices: [Invoice] = []

do {
    // The first request on its own, so a failure is reported before anything else runs.
    step("First request: \(months[0].lowerBound) to \(months[0].upperBound), page 1")
    info("Gives up after 60 s without an answer")
    setStage("waiting for AT's answer to the first request")
    let started = Date()
    let firstPage = try await withHeartbeat {
        try await client.invoices(InvoiceQuery(
            party: party, start: months[0].lowerBound, end: months[0].upperBound,
            page: 1, pageSize: options.pageSize
        ))
    }
    let elapsed = Date().timeIntervalSince(started)
    ok("AT answered 200 in \(String(format: "%.1f", elapsed)) s")
    let pagination = firstPage.pagination
    info("\(pagination.totalDocuments) documents in the month, \(pagination.documentsInPage) in this page, "
        + "page \(pagination.page) of \(pagination.totalPages)")

    step("Reading \(options.start) to \(options.end) (\(months.count) month\(months.count == 1 ? "" : "s"))")
    setStage("reading the whole period")
    invoices = try await withHeartbeat {
        try await client.allInvoices(for: party, from: options.start, to: options.end, pageSize: options.pageSize)
    }
    ok("\(invoices.count) documents")
} catch {
    info("Failed while \(currentStage), after \(seconds(since: stageStarted))")
    try? await httpTransport.shutdown()
    explain(error)
}
try? await httpTransport.shutdown()

// MARK: Report

guard !invoices.isEmpty else {
    say("\nNo documents in this period. The connection, authentication and parsing all worked.")
    say("In the test environment that may simply mean AT holds no test data for \(queryNIF).")
    try? logHandle?.synchronize()
    exit(0)
}

step("Documents")
say("  " + padded("Date", 11) + padded("Type", 5) + padded("Number", 26) + padded(options.asIssuer ? "Customer" : "Issuer NIF", 19)
    + padded("ATCUD", 22) + "Gross")
for invoice in invoices.sorted(by: { ($0.date, $0.number) < ($1.date, $1.number) }) {
    let counterparty: String
    switch invoice.counterparty {
    case .issuer(let nif): counterparty = nif
    case .customer(let taxID, let country): counterparty = country.map { "\($0) \(taxID)" } ?? taxID
    }
    let signedGross = invoice.type.isCredit ? -invoice.grossTotal : invoice.grossTotal
    say("  " + padded(invoice.date.description, 11) + padded(invoice.type.rawValue, 5) + padded(invoice.number, 26)
        + padded(counterparty, 19) + padded(invoice.atcud ?? "—", 22) + euros(signedGross))
}

step("Summary")
var byType: [String: (count: Int, gross: Decimal)] = [:]
for invoice in invoices {
    let signed = invoice.type.isCredit ? -invoice.grossTotal : invoice.grossTotal
    let current = byType[invoice.type.rawValue] ?? (0, 0)
    byType[invoice.type.rawValue] = (current.count + 1, current.gross + signed)
}
for (type, totals) in byType.sorted(by: { $0.key < $1.key }) {
    info(padded(type, 5) + padded("\(totals.count) document\(totals.count == 1 ? "" : "s")", 16) + euros(totals.gross))
}
let net = invoices.reduce(Decimal(0)) { $0 + ($1.type.isCredit ? -$1.netTotal : $1.netTotal) }
let tax = invoices.reduce(Decimal(0)) { $0 + ($1.type.isCredit ? -$1.taxPayable : $1.taxPayable) }
let gross = invoices.reduce(Decimal(0)) { $0 + ($1.type.isCredit ? -$1.grossTotal : $1.grossTotal) }
info("Net \(euros(net)) · VAT \(euros(tax)) · Gross \(euros(gross)) (credit notes subtracted)")

let issuers = Set(invoices.compactMap(\.issuerNIF))
if !issuers.isEmpty { info("\(issuers.count) different issuers") }
let withoutATCUD = invoices.filter { $0.atcud == nil }.count
if withoutATCUD > 0 { info("\(withoutATCUD) documents without ATCUD") }

say("\nAll good: connection, authentication, paging and parsing worked against AT.")
try? logHandle?.synchronize()
