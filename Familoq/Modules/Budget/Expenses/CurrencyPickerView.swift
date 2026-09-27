import SwiftUI
import FamiloqCore
import FamiloqBudget

/// Searchable list of ISO currencies. EUR and common currencies first.
struct CurrencyPickerView: View {
    @Binding var selection: String
    var title: String = "Currency"
    var onSelect: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var codes: [String] {
        let all = CurrencyNames.allCodes
        guard !search.isEmpty else { return all }
        let q = search.lowercased()
        return all.filter { $0.lowercased().contains(q) || CurrencyNames.name(for: $0).lowercased().contains(q) }
    }

    var body: some View {
        List(codes, id: \.self) { code in
            Button {
                if let onSelect {
                    onSelect(code)
                } else {
                    selection = code
                    dismiss()
                }
            } label: {
                HStack {
                    Text(code)
                        .font(.body.monospaced().weight(.semibold))
                        .frame(width: 50, alignment: .leading)
                    VStack(alignment: .leading) {
                        Text(CurrencyNames.name(for: code))
                        if code != "EUR" && !CurrencyInfo.ecbReferenceCurrencies.contains(code) {
                            Text("No automatic rate - enter rate manually")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if code == selection {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $search, prompt: "Search currency")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
