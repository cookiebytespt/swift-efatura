import Foundation

/// Which AT system to talk to. The test endpoint accepts only AT's test certificate;
/// production accepts only a certificate AT signed for the software producer.
public struct EFaturaEnvironment: Sendable, Hashable {
    /// Endpoint of the "consultar faturas" (fatshare) service.
    public let invoicesURL: URL

    public init(invoicesURL: URL) {
        self.invoicesURL = invoicesURL
    }

    public static let test = EFaturaEnvironment(
        invoicesURL: URL(string: "https://servicos.portaldasfinancas.gov.pt:725/fatshare/ws/fatshareFaturas")!
    )

    public static let production = EFaturaEnvironment(
        invoicesURL: URL(string: "https://servicos.portaldasfinancas.gov.pt:425/fatshare/ws/fatshareFaturas")!
    )
}
