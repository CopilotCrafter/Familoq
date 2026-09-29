import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

@Model
final class Expense {
    var id: UUID = UUID()
    var familyID: UUID = UUID()

    // Original amount as entered / printed on the receipt.
    var amountValue: Int64 = 0
    var currencyCode: String = "EUR"

    // Amount in the family's base currency (what budgets and reports use).
    var baseAmountValue: Int64? = nil
    var baseCurrencyCode: String = "EUR"

    // Conversion audit trail: 1 `currencyCode` = rate `baseCurrencyCode`.
    var exchangeRateText: String? = nil
    var exchangeRateDateKey: String? = nil
    var exchangeRateSource: String? = nil
    var conversionStatusRaw: String = "notNeeded"

    var merchant: String = ""
    /// Date AND time of the purchase (receipt time or user input).
    var date: Date = Date()
    var categoryID: UUID? = nil
    var subcategoryID: UUID? = nil
    /// Family member the expense is attributed to.
    var memberID: UUID? = nil
    /// Who created the record (for "members can edit their own expenses").
    var createdByMemberID: UUID? = nil
    var paymentMethodRaw: String = "debitCard"
    var note: String = ""
    var entryMethodRaw: String = "manual"
    @Attribute(.externalStorage) var receiptImageData: Data? = nil
    /// See ReceiptRecord: keep pin, change counter, measured size.
    var keepPhoto: Bool = false
    var photoRevision: Int = 0
    var photoBytes: Int = 0
    /// Travel: the trip, who paid (participant key) and who shares it
    /// (comma-separated keys, empty = everyone on the trip).
    var tripID: UUID? = nil
    var tripPaidBy: String = ""
    var tripSplit: String = ""
    /// Health costs: tax-relevant (außergewöhnliche Belastungen) and for whom.
    var isTaxRelevant: Bool = false
    var healthPersonID: UUID? = nil
    /// Set when the expense was created from a scanned receipt.
    var receiptID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(familyID: UUID, amount: Decimal, currencyCode: String, baseCurrencyCode: String, merchant: String, date: Date) {
        self.id = UUID()
        self.familyID = familyID
        self.amountValue = FixedPoint.storage(from: amount)
        self.currencyCode = CurrencyInfo.normalize(currencyCode)
        self.baseCurrencyCode = CurrencyInfo.normalize(baseCurrencyCode)
        self.merchant = merchant
        self.date = date
    }

    var amount: Decimal {
        get { FixedPoint.decimal(from: amountValue) }
        set { amountValue = FixedPoint.storage(from: newValue) }
    }

    var baseAmount: Decimal? {
        get { baseAmountValue.map { FixedPoint.decimal(from: $0) } }
        set { baseAmountValue = newValue.map { FixedPoint.storage(from: $0) } }
    }

    var conversionStatus: ConversionStatus {
        get { ConversionStatus(rawValue: conversionStatusRaw) ?? .pending }
        set { conversionStatusRaw = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .other }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var entryMethod: EntryMethod {
        get { EntryMethod(rawValue: entryMethodRaw) ?? .manual }
        set { entryMethodRaw = newValue.rawValue }
    }

    var exchangeRate: Decimal? {
        exchangeRateText.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    var isForeignCurrency: Bool { currencyCode != baseCurrencyCode }

    /// Clears conversion data before re-converting.
    func resetConversion() {
        exchangeRateText = nil
        exchangeRateDateKey = nil
        exchangeRateSource = nil
        if currencyCode == baseCurrencyCode {
            baseAmount = amount
            conversionStatus = .notNeeded
        } else {
            baseAmountValue = nil
            conversionStatus = .pending
        }
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var periodRaw: String = "monthly"
    var scopeRaw: String = "overall"
    var categoryID: UUID? = nil
    var subcategoryID: UUID? = nil
    /// Limit in the family base currency.
    var amountValue: Int64 = 0
    var currencyCode: String = "EUR"
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(familyID: UUID, period: BudgetPeriod, scope: BudgetScope, categoryID: UUID? = nil, subcategoryID: UUID? = nil, amount: Decimal, currencyCode: String) {
        self.familyID = familyID
        self.periodRaw = period.rawValue
        self.scopeRaw = scope.rawValue
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
        self.amountValue = FixedPoint.storage(from: amount)
        self.currencyCode = currencyCode
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    var scope: BudgetScope {
        get { BudgetScope(rawValue: scopeRaw) ?? .overall }
        set { scopeRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { FixedPoint.decimal(from: amountValue) }
        set { amountValue = FixedPoint.storage(from: newValue) }
    }
}

@Model
final class MerchantRuleRecord {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    /// Normalised pattern, e.g. "rewe".
    var pattern: String = ""
    /// Merchant as the user typed it, for display.
    var displayMerchant: String = ""
    var categoryID: UUID = UUID()
    var subcategoryID: UUID? = nil
    var isUserDefined: Bool = false
    var createdAt: Date = Date()

    init(familyID: UUID, pattern: String, displayMerchant: String, categoryID: UUID, subcategoryID: UUID?, isUserDefined: Bool) {
        self.familyID = familyID
        self.pattern = TextNormalizer.normalize(pattern)
        self.displayMerchant = displayMerchant
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
        self.isUserDefined = isUserDefined
    }
}

/// Cached public exchange rates (not family data - contains no personal info).
@Model
final class ExchangeRateCacheEntry {
    var id: UUID = UUID()
    var baseCode: String = ""
    var quoteCode: String = ""
    /// Day that was asked for.
    var requestedDateKey: String = ""
    /// Day the source actually published (previous business day on weekends).
    var rateDateKey: String = ""
    var rateText: String = ""
    var source: String = ""
    var fetchedAt: Date = Date()

    init(requestedDateKey: String, rate: ExchangeRate) {
        self.baseCode = rate.base
        self.quoteCode = rate.quote
        self.requestedDateKey = requestedDateKey
        self.rateDateKey = rate.rateDateKey
        self.rateText = "\(rate.rate)"
        self.source = rate.source
    }

    var exchangeRate: ExchangeRate? {
        guard let value = Decimal(string: rateText, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return ExchangeRate(base: baseCode, quote: quoteCode, rate: value, rateDateKey: rateDateKey, source: source)
    }
}

/// How the family files a receipt item, learned from their corrections on
/// the check screen ("Blätterteig" -> Bread & Bakery). Used before the
/// built-in keywords on the next receipt.
@Model
final class ItemCategoryRule {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    /// ItemRuleKey, e.g. "blatterteig".
    var key: String = ""
    /// The item as it was printed, for display.
    var displayName: String = ""
    var categoryID: UUID = UUID()
    var subcategoryID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID, familyID: UUID, key: String, displayName: String, categoryID: UUID, subcategoryID: UUID?) {
        self.id = id
        self.familyID = familyID
        self.key = key
        self.displayName = displayName
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
    }

    /// One rule per item and family - the same ID on every iPhone.
    static func ruleID(familyID: UUID, key: String) -> UUID {
        DeterministicID.uuid("itemrule|\(familyID.uuidString)|\(key)")
    }
}
