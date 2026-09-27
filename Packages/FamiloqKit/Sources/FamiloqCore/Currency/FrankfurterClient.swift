import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP abstraction so network clients can be unit-tested offline.
public protocol HTTPClient {
    /// Returns the body and the HTTP status code.
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public extension HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (data ?? Data(), status))
            }
            task.resume()
        }
    }
}

/// Free, key-less client for the Frankfurter API, which republishes the
/// European Central Bank's daily reference rates.
///
/// Privacy: the request contains ONLY two currency codes and a date. No
/// amounts, merchants or user identifiers ever leave the device.
///
/// The ECB publishes one reference rate per business day (~16:00 CET). There
/// is no free intraday/"time of day" rate; the rate of the expense's calendar
/// date is the best freely available approximation. Users who want the exact
/// rate their bank charged can enter it manually.
public struct FrankfurterClient: ExchangeRateProviding {
    public struct Endpoint: Sendable {
        public let baseURL: String
        /// Query parameter names differ between API versions.
        public let fromParam: String
        public let toParam: String

        public init(baseURL: String, fromParam: String, toParam: String) {
            self.baseURL = baseURL
            self.fromParam = fromParam
            self.toParam = toParam
        }
    }

    public static let defaultEndpoints: [Endpoint] = [
        Endpoint(baseURL: "https://api.frankfurter.dev/v1", fromParam: "base", toParam: "symbols"),
        Endpoint(baseURL: "https://api.frankfurter.app", fromParam: "from", toParam: "to")
    ]

    public static let sourceName = "ECB reference rate (Frankfurter)"

    private let http: HTTPClient
    private let endpoints: [Endpoint]

    public init(http: HTTPClient = URLSessionHTTPClient(), endpoints: [Endpoint] = FrankfurterClient.defaultEndpoints) {
        self.http = http
        self.endpoints = endpoints
    }

    public static func url(endpoint: Endpoint, from: String, to: String, dateKey: String?) -> URL? {
        let path = dateKey ?? "latest"
        let f = CurrencyInfo.normalize(from)
        let t = CurrencyInfo.normalize(to)
        return URL(string: "\(endpoint.baseURL)/\(path)?\(endpoint.fromParam)=\(f)&\(endpoint.toParam)=\(t)")
    }

    public func fetchRate(from: String, to: String, dateKey: String?) async throws -> ExchangeRate {
        let f = CurrencyInfo.normalize(from)
        let t = CurrencyInfo.normalize(to)
        guard CurrencyInfo.isValidCode(f), CurrencyInfo.isValidCode(t) else {
            throw ExchangeRateError.unsupportedCurrency
        }

        var lastError: Error = ExchangeRateError.unavailable
        var sawUnsupported = false
        for endpoint in endpoints {
            guard let url = Self.url(endpoint: endpoint, from: f, to: t, dateKey: dateKey) else { continue }
            do {
                let (data, status) = try await http.get(url)
                switch status {
                case 200:
                    return try Self.parse(data: data, from: f, to: t)
                case 404, 422:
                    // Unknown currency (or a date before 1999).
                    sawUnsupported = true
                    lastError = ExchangeRateError.unsupportedCurrency
                default:
                    lastError = ExchangeRateError.unavailable
                }
            } catch let error as ExchangeRateError {
                if error == .unsupportedCurrency { sawUnsupported = true }
                lastError = error
            } catch {
                lastError = ExchangeRateError.unavailable
            }
        }
        if sawUnsupported { throw ExchangeRateError.unsupportedCurrency }
        throw lastError
    }

    private struct Response: Decodable {
        let base: String
        let date: String
        let rates: [String: Decimal]
    }

    /// Parses `{"amount":1.0,"base":"USD","date":"2026-09-25","rates":{"EUR":0.8543}}`.
    public static func parse(data: Data, from: String, to: String) throws -> ExchangeRate {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ExchangeRateError.invalidResponse
        }
        let t = CurrencyInfo.normalize(to)
        guard let rate = response.rates[t] else {
            throw ExchangeRateError.unsupportedCurrency
        }
        guard rate > 0 else { throw ExchangeRateError.invalidResponse }
        return ExchangeRate(base: response.base, quote: t, rate: rate, rateDateKey: response.date, source: sourceName)
    }
}
