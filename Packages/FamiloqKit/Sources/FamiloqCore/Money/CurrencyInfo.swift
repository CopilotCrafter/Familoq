import Foundation

public enum CurrencyInfo {
    /// Default base currency for every new family. Users can change it.
    public static let defaultBaseCurrency = "EUR"

    /// Currencies for which the European Central Bank publishes daily
    /// reference rates (used by the Frankfurter API). Other currencies can
    /// still be used, but need a manually entered rate.
    ///
    /// Notes: BGN ended when Bulgaria adopted the euro (2026); HRK ended 2023;
    /// RUB publication is suspended.  The app also asks the API at runtime, so
    /// this list is only a hint for the UI.
    public static let ecbReferenceCurrencies: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "GBP", "HKD", "HUF",
        "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD",
        "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"
    ]

    /// Currencies shown at the top of pickers.
    public static let commonCurrencies: [String] = [
        "EUR", "USD", "GBP", "CHF", "INR", "PLN", "CZK", "HUF", "SEK", "NOK",
        "DKK", "JPY", "CNY", "TRY", "AUD", "CAD"
    ]

    private static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF",
        "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]
    private static let threeDecimalCurrencies: Set<String> = [
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"
    ]

    public static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func isValidCode(_ code: String) -> Bool {
        let c = normalize(code)
        return c.count == 3 && c.allSatisfy { $0.isLetter && $0.isASCII }
    }

    /// Number of minor units (decimal places) per ISO 4217.
    public static func minorUnits(for code: String) -> Int {
        let c = normalize(code)
        if zeroDecimalCurrencies.contains(c) { return 0 }
        if threeDecimalCurrencies.contains(c) { return 3 }
        return 2
    }

    /// True if an automatic ECB-based rate can be fetched for the pair.
    public static func canAutoConvert(from: String, to: String) -> Bool {
        let f = normalize(from), t = normalize(to)
        let supported = ecbReferenceCurrencies.union(["EUR"])
        return supported.contains(f) && supported.contains(t)
    }
}
