import Foundation
import FamiloqCore

/// Reads CSV exports of any bank. The user maps the columns once (date,
/// amount or debit/credit, payee, purpose); Familoq remembers the mapping
/// for files with the same header.
public enum CSVReader {
    /// Semicolon (German banks), comma or tab - whichever splits the lines best.
    public static func detectDelimiter(_ text: String) -> Character {
        let lines = text.split(whereSeparator: \.isNewline).prefix(30).map(String.init)
        var best: (Character, Int) = (";", -1)
        for candidate in [";", ",", "\t"] as [Character] {
            let counts = lines.map { line in split(line, delimiter: candidate).count }.filter { $0 > 1 }
            // Most lines with the same (largest) number of columns wins.
            let frequency = Dictionary(grouping: counts, by: { $0 }).mapValues(\.count)
            if let top = frequency.max(by: { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }),
               top.value * top.key > best.1 {
                best = (candidate, top.value * top.key)
            }
        }
        return best.0
    }

    /// One line into cells (quotes and doubled quotes handled).
    public static func split(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = Array(line).makeIterator()
        var pending: Character? = nil
        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    public static func rows(_ text: String) -> [[String]] {
        let delimiter = detectDelimiter(text)
        return text.split(whereSeparator: \.isNewline)
            .map { split(String($0), delimiter: delimiter) }
            .filter { row in row.contains { !$0.isEmpty } }
    }
}

public struct BankColumnMapping: Codable, Equatable, Sendable {
    public var headerRow: Int
    public var date: Int
    /// One signed amount column, or …
    public var amount: Int?
    /// … separate debit (Soll) and credit (Haben) columns.
    public var debit: Int?
    public var credit: Int?
    public var payee: Int
    public var purpose: Int?

    public init(headerRow: Int, date: Int, amount: Int?, debit: Int? = nil, credit: Int? = nil, payee: Int, purpose: Int?) {
        self.headerRow = headerRow
        self.date = date
        self.amount = amount
        self.debit = debit
        self.credit = credit
        self.payee = payee
        self.purpose = purpose
    }
}

public struct BankTransaction: Equatable, Sendable, Identifiable {
    public let row: Int
    public let date: Date
    /// Negative = money going out.
    public let amount: Decimal
    public let payee: String
    public let purpose: String
    public var id: Int { row }

    /// Same file imported twice (or by two family members) gives the same key.
    public var stableKey: String {
        "bank|\(Int(date.timeIntervalSince1970))|\(amount)|\(payee.lowercased())|\(purpose.lowercased().prefix(60))"
    }

    /// What the expense is called: payee, else the start of the purpose text.
    public var displayName: String {
        let name = payee.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return String(purpose.prefix(40)).trimmingCharacters(in: .whitespaces)
    }
}

public enum BankStatement {
    private static let dateWords = ["buchungstag", "buchungsdatum", "datum", "date", "booking date", "valuta", "wertstellung", "valutadatum", "transaction date"]
    private static let amountWords = ["betrag", "umsatz", "amount", "betrag (eur)", "betrag (€)", "value"]
    private static let debitWords = ["soll", "debit", "ausgang", "belastung"]
    private static let creditWords = ["haben", "credit", "eingang", "gutschrift"]
    private static let payeeWords = ["beguenstigter/zahlungspflichtiger", "begünstigter/zahlungspflichtiger", "auftraggeber/empfänger", "auftraggeber / begünstigter",
                                     "zahlungsempfänger*in", "zahlungspflichtige*r", "empfänger", "empfaenger", "name", "payee", "counterparty", "partner name", "zahlungsempfänger", "auftraggeber"]
    private static let purposeWords = ["verwendungszweck", "buchungstext", "purpose", "reference", "description", "beschreibung", "payment reference", "text"]

    /// The header: the first row with at least three text cells that is
    /// followed by a row containing a date (skips bank "preamble" lines).
    public static func headerRow(_ rows: [[String]]) -> Int {
        for (index, row) in rows.enumerated() where index + 1 < rows.count {
            let textCells = row.filter { cell in cell.contains(where: \.isLetter) && parseDate(cell) == nil }.count
            if textCells >= 3, rows[index + 1].contains(where: { parseDate($0) != nil }) { return index }
        }
        return 0
    }

    public static func signature(_ header: [String]) -> String {
        header.map { $0.lowercased() }.joined(separator: "|")
    }

    private static func column(_ header: [String], _ words: [String], excluding: Set<Int> = []) -> Int? {
        let lowered = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        for word in words {
            if let exact = lowered.indices.first(where: { !excluding.contains($0) && lowered[$0] == word }) { return exact }
        }
        for word in words {
            if let partial = lowered.indices.first(where: { !excluding.contains($0) && lowered[$0].contains(word) }) { return partial }
        }
        return nil
    }

    /// A first guess the user can correct.
    public static func guessMapping(_ rows: [[String]]) -> BankColumnMapping? {
        let headerIndex = headerRow(rows)
        guard headerIndex < rows.count else { return nil }
        let header = rows[headerIndex]
        guard let date = column(header, dateWords) else { return nil }
        let amount = column(header, amountWords, excluding: [date])
        let debit = amount == nil ? column(header, debitWords, excluding: [date]) : nil
        let credit = amount == nil ? column(header, creditWords, excluding: [date]) : nil
        guard amount != nil || debit != nil else { return nil }
        var used: Set<Int> = [date]
        [amount, debit, credit].compactMap { $0 }.forEach { used.insert($0) }
        let payee = column(header, payeeWords, excluding: used) ?? header.indices.first { !used.contains($0) } ?? 0
        used.insert(payee)
        let purpose = column(header, purposeWords, excluding: used)
        return BankColumnMapping(headerRow: headerIndex, date: date, amount: amount, debit: debit, credit: credit, payee: payee, purpose: purpose)
    }

    /// "28.09.2026", "28.09.26", "2026-09-28", "28/09/2026".
    public static func parseDate(_ text: String) -> DateComponents? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let patterns: [(String, (Int, Int, Int))] = [
            (#"^(\d{1,2})\.(\d{1,2})\.(\d{4})$"#, (3, 2, 1)),
            (#"^(\d{1,2})\.(\d{1,2})\.(\d{2})$"#, (3, 2, 1)),
            (#"^(\d{4})-(\d{2})-(\d{2})"#, (1, 2, 3)),
            (#"^(\d{1,2})/(\d{1,2})/(\d{4})$"#, (3, 2, 1))
        ]
        for (pattern, order) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { continue }
            func group(_ i: Int) -> Int? { Range(m.range(at: i), in: t).flatMap { Int(t[$0]) } }
            guard var year = group(order.0), let month = group(order.1), let day = group(order.2),
                  (1...12).contains(month), (1...31).contains(day) else { continue }
            if year < 100 { year += 2000 }
            return DateComponents(year: year, month: month, day: day)
        }
        return nil
    }

    /// "-1.234,56", "1,234.56", "−12,50 €", "12,50 S" (S = Soll = out).
    public static func parseAmount(_ text: String) -> Decimal? {
        var t = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "EUR", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
        var sign: Decimal = 1
        if t.hasSuffix("S") { sign = -1; t.removeLast() } else if t.hasSuffix("H") { t.removeLast() }
        if t.hasPrefix("+") { t.removeFirst() }
        guard !t.isEmpty, let value = DecimalParser.parse(t) else { return nil }
        return value * sign
    }

    public static func transactions(_ rows: [[String]], mapping: BankColumnMapping, calendar: Calendar) -> [BankTransaction] {
        var result: [BankTransaction] = []
        for (index, row) in rows.enumerated() where index > mapping.headerRow {
            func cell(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let parts = parseDate(cell(mapping.date)), let date = calendar.date(from: parts) else { continue }
            let amount: Decimal
            if let single = parseAmount(cell(mapping.amount)), mapping.amount != nil {
                amount = single
            } else {
                let debit = parseAmount(cell(mapping.debit)).map { $0 > 0 ? -$0 : $0 } ?? 0
                let credit = parseAmount(cell(mapping.credit)).map { abs($0) } ?? 0
                guard debit != 0 || credit != 0 else { continue }
                amount = debit != 0 ? debit : credit
            }
            result.append(BankTransaction(row: index, date: date, amount: amount,
                                          payee: cell(mapping.payee), purpose: cell(mapping.purpose)))
        }
        return result
    }

    /// Already in Familoq: same amount within `days` days, and the shop name
    /// matches (or there is only one such amount that day range).
    public static func isAlreadyRecorded(_ transaction: BankTransaction, existing: [(date: Date, amount: Decimal, merchant: String)],
                                         days: Int = 3, calendar: Calendar) -> Bool {
        let value = abs(transaction.amount)
        let candidates = existing.filter { entry in
            entry.amount == value &&
            abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date), to: calendar.startOfDay(for: transaction.date)).day ?? 99) <= days
        }
        guard !candidates.isEmpty else { return false }
        let payee = TextNormalizer.normalize(transaction.payee + " " + transaction.purpose)
        if candidates.contains(where: { entry in
            let merchant = TextNormalizer.normalize(entry.merchant)
            return !merchant.isEmpty && merchant.split(separator: " ").contains { $0.count >= 3 && payee.contains($0) }
        }) { return true }
        return candidates.count == 1
    }
}
