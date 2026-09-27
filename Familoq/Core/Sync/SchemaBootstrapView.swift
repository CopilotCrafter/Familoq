import SwiftUI
import CloudKit
import FamiloqCore

/// One-time helper, only in the special "CloudKit schema" build
/// (.github/workflows/cloudkit-schema-build.yml, docs/11).
///
/// CloudKit creates the system record type `cloudkit.share` only when a
/// share is saved in the DEVELOPMENT environment. TestFlight always uses
/// PRODUCTION, so without this one run family invitations fail with
/// "Cannot create new type cloudkit.share in production schema".
///
/// This screen saves one test record and one zone-wide share in the
/// Development environment, then deletes them again. Afterwards: CloudKit
/// Console -> Deploy Schema Changes.
struct SchemaBootstrapView: View {
    @State private var log: [String] = []
    @State private var isRunning = false
    @State private var succeeded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This special Familoq build prepares iCloud for family invitations. Tap the button once, then deploy the schema in the CloudKit Console and reinstall Familoq from TestFlight.")
                        .font(.subheadline)
                }
                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            Label("Prepare iCloud schema", systemImage: "icloud.and.arrow.up")
                            if isRunning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isRunning)
                }
                if !log.isEmpty {
                    Section("Progress") {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote.monospaced())
                        }
                    }
                }
                if succeeded {
                    Section {
                        Label("Done. Now: CloudKit Console → Development → Deploy Schema Changes (cloudkit.share is listed). Then install Familoq from TestFlight again.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("CloudKit schema")
        }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        log = []
        let identifier = Bundle.main.object(forInfoDictionaryKey: "FQCloudKitContainer") as? String ?? "iCloud.com.carolandmartin.familoq"
        let container = CKContainer(identifier: identifier)
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "schema-bootstrap", ownerName: CKCurrentUserDefaultName)
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                log.append("✗ iCloud account not available (\(status.rawValue)). Sign in to iCloud in Settings.")
                return
            }
            log.append("✓ iCloud account available (container \(identifier))")

            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            log.append("✓ Test zone created")

            let item = CKRecord(recordType: SyncCoordinator.recordType, recordID: CKRecord.ID(recordName: "family-\(UUID().uuidString)", zoneID: zoneID))
            item["kind"] = "family"
            item["payload"] = "{}"
            item["modifiedAt"] = Date()
            _ = try await database.modifyRecords(saving: [item], deleting: [])
            log.append("✓ Test record saved (\(SyncCoordinator.recordType))")

            let share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = "Schema test" as CKRecordValue
            share.publicPermission = .none
            let result = try await database.modifyRecords(saving: [share], deleting: [])
            if case .failure(let error) = result.saveResults[share.recordID] { throw error }
            log.append("✓ Test share saved → cloudkit.share now exists in Development")

            _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
            log.append("✓ Test zone deleted again")
            succeeded = true
        } catch {
            log.append("✗ \(error.localizedDescription)")
            _ = try? await database.modifyRecordZones(saving: [], deleting: [zoneID])
        }
    }
}
