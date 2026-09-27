import Foundation
import CloudKit
import SwiftData
import FamiloqCore

/// Family invitations = iCloud sharing of the family's zone.
///
/// The owner invites a person by the e-mail address or phone number of their
/// Apple Account. Only that person can open the link (the share is never
/// public), and the owner can withdraw the invitation or remove the person.
extension SyncCoordinator {
    enum SharingError: LocalizedError {
        case notRunning
        case notOwner
        case personNotFound
        case familyFull
        case ownFamily

        var errorDescription: String? {
            switch self {
            case .notRunning: return "iCloud sync is not active. Check that you are signed in to iCloud and online."
            case .notOwner: return "Only the family owner can do this."
            case .personNotFound: return "No Apple Account was found for this address. Use the e-mail address or phone number of their Apple Account."
            case .familyFull: return "This family has reached its member limit."
            case .ownFamily: return "This is an invitation to your own family."
            }
        }
    }

    /// The family's share, or nil when nobody was invited yet.
    func existingShare(familyID: UUID) async throws -> CKShare? {
        guard isRunning, let zone = zoneRecord(for: familyID) else { throw SharingError.notRunning }
        let database = zone.isShared ? container.sharedCloudDatabase : container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: recordZoneID(of: zone))
        do {
            return try await database.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Adds a person to the family's share (creating the share on first use).
    /// Returns the updated share; send `share.url` to the person.
    func invite(emailOrPhone: String, familyID: UUID, familyName: String, maxMembers: Int, activeMembers: Int) async throws -> CKShare {
        guard isRunning, let zone = zoneRecord(for: familyID) else { throw SharingError.notRunning }
        guard !zone.isShared else { throw SharingError.notOwner }
        let database = container.privateCloudDatabase
        let zoneID = recordZoneID(of: zone)

        // The zone must exist in iCloud before it can be shared.
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

        let share: CKShare
        if let existing = try await existingShare(familyID: familyID) {
            share = existing
        } else {
            share = CKShare(recordZoneID: zoneID)
            share.publicPermission = .none
        }
        share[CKShare.SystemFieldKey.title] = familyName as CKRecordValue

        let invited = share.participants.filter { $0.role != .owner && $0.acceptanceStatus != .removed }
        guard FamilyLimits.canAddMember(activeMemberCount: max(activeMembers, 1 + invited.count), maxMembers: maxMembers) else {
            throw SharingError.familyFull
        }

        let address = emailOrPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let participant: CKShare.Participant
        do {
            if address.contains("@") {
                participant = try await container.shareParticipant(forEmailAddress: address)
            } else {
                participant = try await container.shareParticipant(forPhoneNumber: address)
            }
        } catch {
            throw SharingError.personNotFound
        }
        participant.permission = .readWrite
        participant.role = .privateUser
        share.addParticipant(participant)

        return try await save(share)
    }

    /// Withdraws an invitation or removes a member from the family.
    func remove(_ participant: CKShare.Participant, from share: CKShare, familyID: UUID) async throws -> CKShare {
        share.removeParticipant(participant)
        let saved = try await save(share)
        // Mark the person's member entry as inactive (synced to everyone).
        if let recordName = participant.userIdentity.userRecordID?.recordName, let context = modelContainerContext {
            let fid = familyID
            let members = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.familyID == fid }))) ?? []
            for member in members where member.cloudUserRecordName == recordName {
                member.isActive = false
            }
            try? context.save()
            scanNow()
        }
        return saved
    }

    private func save(_ share: CKShare) async throws -> CKShare {
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard let saveResult = result.saveResults[share.recordID] else { return share }
        switch saveResult {
        case .success(let record):
            return (record as? CKShare) ?? share
        case .failure(let error):
            throw error
        }
    }

    // MARK: Joining

    /// The person tapped the invitation link (see FamiloqSceneDelegate).
    func accept(_ metadata: CKShare.Metadata) async {
        guard isRunning else {
            joinState = .failed(SharingError.notRunning.localizedDescription)
            return
        }
        if metadata.participantRole == .owner {
            joinState = .failed(SharingError.ownFamily.localizedDescription)
            return
        }
        joinState = .joining
        do {
            if metadata.participantStatus != .accepted {
                _ = try await container.accept(metadata)
            }
            let zoneID = metadata.share.recordID.zoneID
            guard let familyID = SyncZone.familyID(fromZoneName: zoneID.zoneName) else {
                joinState = .failed("This is not a Familoq family invitation.")
                return
            }
            registerSharedZone(zoneID)
            await fetchNow()
            joinState = .joined(familyID)
        } catch {
            joinState = .failed("Could not join the family: \(error.localizedDescription)")
        }
    }

    /// After joining: the person's own member entry in that family.
    func addMe(to familyID: UUID, name: String) {
        guard let context = modelContainerContext else { return }
        let member = FamilyMember(familyID: familyID, displayName: name, role: .member, isCurrentUser: true, cloudUserRecordName: userRecordName)
        context.insert(member)
        try? context.save()
        scanNow()
    }
}
