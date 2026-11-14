/// A Portuguese tax identification number (NIF/NIPC): nine digits, the last a mod-11 check digit.
public struct NIF: Sendable, Hashable, Codable, LosslessStringConvertible {
    public let value: String

    /// Fails unless `string` is nine digits, does not start with 0 and has a valid check digit.
    public init?(_ string: String) {
        guard NIF.isValid(string) else { return nil }
        self.value = string
    }

    public var description: String { value }

    public static func isValid(_ string: String) -> Bool {
        let digits = string.utf8.map { Int($0) - 48 }
        guard digits.count == 9, digits.allSatisfy({ (0...9).contains($0) }), digits[0] != 0 else {
            return false
        }
        let sum = zip(digits.prefix(8), stride(from: 9, to: 1, by: -1)).reduce(0) { $0 + $1.0 * $1.1 }
        let remainder = sum % 11
        let check = remainder < 2 ? 0 : 11 - remainder
        return digits[8] == check
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let nif = NIF(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid NIF")
        }
        self = nif
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
