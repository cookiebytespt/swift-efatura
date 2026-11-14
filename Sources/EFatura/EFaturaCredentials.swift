/// Portal das Finanças credentials of the taxpayer whose invoices are read.
/// Use a sub-user (`NIF/UserId`), never the taxpayer's main password.
public struct EFaturaCredentials: Sendable, CustomStringConvertible {
    /// `NIF/UserId`, for example `555555555/1`.
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    public init(nif: NIF, subuser: String, password: String) {
        self.init(username: "\(nif.value)/\(subuser)", password: password)
    }

    /// The NIF part of the username, when it is a valid NIF.
    public var nif: NIF? {
        NIF(String(username.prefix { $0 != "/" }))
    }

    // Keeps the password out of logs and string interpolation.
    public var description: String { "EFaturaCredentials(username: \(username), password: <redacted>)" }
}
