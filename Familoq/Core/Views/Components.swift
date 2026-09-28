import SwiftUI
import FamiloqCore

// MARK: - Formatting

extension Decimal {
    func currency(_ code: String) -> String {
        formatted(.currency(code: code))
    }

    /// Whole units, e.g. "€3,000".
    func currencyShort(_ code: String) -> String {
        formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}

enum CurrencyNames {
    static func name(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    /// Common currencies first, then every ISO code the system knows.
    static var allCodes: [String] {
        let common = CurrencyInfo.commonCurrencies
        let rest = Locale.commonISOCurrencyCodes.filter { !common.contains($0) }.sorted()
        return common + rest
    }
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Reusable views

struct CategoryIcon: View {
    let icon: String
    let colorHex: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(title)).font(.headline)
            Text(LocalizedStringKey(message))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

/// Builds its content only when it is actually shown. NavigationLink creates
/// its destination for every row as soon as the list appears; destinations
/// with their own @Query then set up database queries for every row, which
/// made iOS 27 rebuild the list endlessly (freeze/crash).
struct LazyView<Content: View>: View {
    private let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: Content { build() }
}
