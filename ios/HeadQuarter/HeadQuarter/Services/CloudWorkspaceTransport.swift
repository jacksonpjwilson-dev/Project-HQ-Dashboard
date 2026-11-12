import Foundation
import CloudKit
actor CloudWorkspaceTransport: WorkspaceTransport {
    let containerIdentifier: String
    init(containerIdentifier: String) { self.containerIdentifier = containerIdentifier }
    private func database() throws -> CKDatabase {
        guard Bundle.main.object(forInfoDictionaryKey: "HQCloudKitEnabled") as? Bool == true else {
            throw WorkspaceSyncError.configuration("CloudKit requires your signed iCloud container and HQCloudKitEnabled in Info.plist. See the Apple setup guide; no iCloud connection has been made.")
        }
        return CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }
    private func loadRecord() async throws -> CKRecord? {
        do { return try await database().record(for: CKRecord.ID(recordName: "head-quarter-workspace-v1")) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }
    func fetch() async throws -> RemoteWorkspace {
        guard let record = try await loadRecord() else { return .init(revision: 0, backup: nil) }
        guard let revision = record["revision"] as? Int, let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { throw WorkspaceSyncError.invalidResponse }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= BackupCodec.maximumBytes else { throw WorkspaceSyncError.invalidResponse }
        return .init(revision: revision, backup: try BackupCodec.decode(Data(contentsOf: url)))
    }
    func save(_ backup: WorkspaceBackup, expectedRevision: Int) async throws -> RemoteWorkspace {
        try backup.validate()
        let record = try await loadRecord() ?? CKRecord(recordType: "HQWorkspace", recordID: CKRecord.ID(recordName: "head-quarter-workspace-v1"))
        guard (record["revision"] as? Int ?? 0) == expectedRevision else { throw WorkspaceSyncError.remoteChanged }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try BackupCodec.encode(backup).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); defer { try? FileManager.default.removeItem(at: file) }
        record["revision"] = (expectedRevision + 1) as CKRecordValue; record["payload"] = CKAsset(fileURL: file)
        let database = try database()
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged; operation.isAtomic = true
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { continuation.resume(with: $0) }; database.add(operation)
            }
        } catch let error as CKError where error.code == .serverRecordChanged { throw WorkspaceSyncError.remoteChanged }
        return .init(revision: expectedRevision + 1, backup: backup)
    }
}
