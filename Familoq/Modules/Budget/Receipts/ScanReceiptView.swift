import SwiftUI

/// Phase 2 builds receipt scanning here (VisionKit document camera + Vision
/// text recognition + item-level grocery categorisation). The grocery
/// classifier already exists and is tested in the FamiloqBudget package.
struct ScanReceiptView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text("Receipt scanning is coming")
                    .font(.title3.weight(.semibold))
                Text("Phase 2 adds on-device OCR: merchant, date & time, total, currency, VAT and individual items - e.g. chicken → Meat & Poultry, bananas → Fruits. You will confirm everything before it is saved, and the receipt's date is used for currency conversion.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    session.selectedTab = .add
                } label: {
                    Label("Add an expense manually", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .navigationTitle("Scan")
        }
    }
}
