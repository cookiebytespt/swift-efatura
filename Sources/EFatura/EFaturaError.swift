/// The `estadoExecucao` of a response: AT's numeric code and its description.
public struct EFaturaStatus: Sendable, Hashable, CustomStringConvertible {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public enum Kind: Sendable, Hashable {
        /// 200.
        case success
        /// 1–99: the WS-Security header was refused (bad sub-user, password, key or clock).
        case authentication
        /// 3xx: a required request element is missing.
        case structure
        /// 4xx: a value was refused (NIF, dates, paging).
        case content
        /// 5xx: AT's side failed; worth retrying later.
        case server
        case unknown
    }

    public var kind: Kind {
        switch code {
        case 200: return .success
        case 1...99: return .authentication
        case 300...399: return .structure
        case 400...499: return .content
        case 500...599: return .server
        default: return .unknown
        }
    }

    public var isSuccess: Bool { kind == .success }

    public var description: String { "\(code): \(message)" }

    // Codes from AT's manual, section 2.1.10 (Consultar faturas).
    public static let nifDoesNotMatchLogin = 414
    public static let yearNotAvailable = 422
    public static let periodLongerThanOneMonth = 434
    public static let pageBeyondLastPage = 444
    /// "Lista de faturas vazia": nothing registered for the query. Not in the manual's table;
    /// observed from AT's test environment on 13 Nov 2026. Treated as an empty result, not an error.
    public static let emptyList = 486
}

public enum EFaturaError: Error, Sendable, CustomStringConvertible {
    /// The request was refused locally, before anything was sent.
    case invalidRequest(String)
    /// AT answered with a status other than 200.
    case rejected(EFaturaStatus)
    /// AT answered with a SOAP fault.
    case soapFault(code: String, message: String)
    /// A non-SOAP HTTP failure. `body` is truncated.
    case http(status: Int, body: String)
    /// The response could not be understood.
    case malformedResponse(String)
    /// The authentication public key or certificate could not be read, or is not RSA.
    case invalidAuthenticationKey(String)

    public var description: String {
        switch self {
        case .invalidRequest(let reason): return "Invalid e-Fatura request: \(reason)"
        case .rejected(let status): return "e-Fatura refused the request (\(status))"
        case .soapFault(let code, let message): return "e-Fatura SOAP fault \(code): \(message)"
        case .http(let status, let body): return "e-Fatura HTTP \(status): \(body)"
        case .malformedResponse(let reason): return "Malformed e-Fatura response: \(reason)"
        case .invalidAuthenticationKey(let reason): return "Invalid AT authentication key: \(reason)"
        }
    }
}
