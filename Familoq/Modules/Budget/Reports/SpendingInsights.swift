import SwiftUI
import FamiloqCore
import FamiloqBudget
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence (on-device language model, iOS 26+) explains the
/// report in plain words. Runs entirely on the iPhone - the numbers never
/// leave it. Without Apple Intelligence the built-in insights still show.
enum AppleIntelligence {
    enum State: Equatable {
        case available
        case unavailable(String)
    }

    static var state: State {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            if case .available = availability { return .available }
            if case .unavailable(let reason) = availability {
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("This iPhone does not support Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Turn on Apple Intelligence in the iPhone Settings to get a written explanation.")
                case .modelNotReady:
                    return .unavailable("Apple Intelligence is still getting ready (downloading). Try again later.")
                @unknown default:
                    return .unavailable("Apple Intelligence is not available right now.")
                }
            }
            return .unavailable("Apple Intelligence is not available right now.")
        }
        #endif
        return .unavailable("Needs iOS 26 or later with Apple Intelligence.")
    }

    /// The language the answer should be written in (the app's language).
    static var answerLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    static func explainSpending(_ facts: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You help a family understand their household spending. Use only the numbers given, never invent any. \
                Write in \(answerLanguage). Give 3 to 5 short bullet points starting with "• ": where most money goes, \
                which subcategories grew compared with the previous period and by how much, anything unusual, \
                and one or two practical, friendly ideas to spend less. No greeting, no closing sentence.
                """)
            let response = try await session.respond(to: facts)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw NSError(domain: "Familoq", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence is not available right now.")])
    }
}

extension AppleIntelligence {
    /// Files receipt lines the built-in keywords did not recognise.
    /// Returns item index -> one of `choices` (exactly as given).
    static func classifyItems(_ items: [String], choices: [String]) async throws -> [Int: String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You sort lines from a supermarket receipt (often abbreviated German, e.g. "Hähn." = chicken, \
                "Pudd." = pudding, "Pfand" = bottle deposit) into a family's budget categories. \
                For every numbered item answer with exactly one line "number: category", copying the category \
                exactly from the list. Use the closest match; nothing else in the answer.
                """)
            let list = choices.joined(separator: "\n")
            let numbered = items.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
            let response = try await session.respond(to: "Categories:\n\(list)\n\nItems:\n\(numbered)")
            return parseClassification(response.content, itemCount: items.count, choices: choices)
        }
        #endif
        return [:]
    }

    /// "3: Groceries > Milk & Dairy" -> [2: "Groceries > Milk & Dairy"].
    /// Also accepts only the subcategory name if it is unique.
    static func parseClassification(_ text: String, itemCount: Int, choices: [String]) -> [Int: String] {
        var result: [Int: String] = [:]
        let lowered = Dictionary(choices.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " -*•\t"))
            guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "." || $0 == ")" }),
                  let number = Int(line[..<colon].trimmingCharacters(in: .whitespaces)),
                  (1...itemCount).contains(number) else { continue }
            let answer = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'."))
            let key = answer.lowercased()
            if let exact = lowered[key] {
                result[number - 1] = exact
            } else {
                let matches = choices.filter { $0.lowercased().hasSuffix("> " + key) }
                if matches.count == 1 { result[number - 1] = matches[0] }
            }
        }
        return result
    }
}

/// "Insights" at the top of Reports: built-in facts, plus an optional
/// Apple Intelligence explanation on request.
struct SpendingInsightsSection: View {
    /// Short, already localized lines ("Meat & Poultry +45 € (+60 %)").
    let facts: [String]
    /// Numbers for the language model (English labels, user's names).
    let modelInput: String
    @State private var answer: String?
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        Section {
            if facts.isEmpty {
                Text("Not enough spending in this period for insights yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(facts, id: \.self) { fact in
                Text(verbatim: fact).font(.subheadline)
            }
            switch AppleIntelligence.state {
            case .available:
                if let answer {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Apple Intelligence", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                        Text(verbatim: answer).font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        Task { await explain() }
                    } label: {
                        HStack {
                            Label("Explain with Apple Intelligence", systemImage: "sparkles")
                            if isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isWorking || facts.isEmpty)
                }
                if let errorText {
                    Text(verbatim: errorText).font(.caption).foregroundStyle(.orange)
                }
            case .unavailable(let reason):
                Label(LocalizedStringKey(reason), systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Insights")
        } footer: {
            if answer != nil {
                Text("Written on this iPhone by Apple Intelligence from the numbers above - nothing is sent anywhere. It can make mistakes.")
            }
        }
    }

    private func explain() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            answer = try await AppleIntelligence.explainSpending(modelInput)
        } catch {
            errorText = String(localized: "Apple Intelligence could not answer: \(error.localizedDescription)")
        }
    }
}
