import Foundation
import CryptoKit
import Observation
@MainActor @Observable final class SyncCoordinator {
    var isSyncing = false
    var status = "Not connected"
    private func directory(scope: String) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = root.appendingPathComponent("Synchronization/\(digest)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    func synchronize(store: AppStore, transport: any WorkspaceTransport, scope: String, resolution: String = "merge") async {
        guard !store.isDemo, !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }
        do {
            let directory = try directory(scope: scope), baseURL = directory.appendingPathComponent("base.json")
            let localData = try BackupService.export(store.projects), local = try BackupCodec.decode(localData)
            let base = FileManager.default.fileExists(atPath: baseURL.path) ? try BackupCodec.decode(Data(contentsOf: baseURL)) : nil
            let remote = try await transport.fetch()
            guard try WorkspaceMerge.equivalent(local, BackupCodec.decode(BackupService.export(store.projects))) else { throw WorkspaceSyncError.localChanged }
            let merged: WorkspaceBackup
            switch resolution {
            case "device": merged = local
            case "remote": guard let backup = remote.backup else { throw WorkspaceSyncError.configuration("There is no remote workspace to download.") }; merged = backup
            default: merged = try WorkspaceMerge.merge(base: base, local: local, remote: remote.backup)
            }
            let saved: RemoteWorkspace
            if let current = remote.backup, try WorkspaceMerge.equivalent(current, merged) { saved = remote }
            else { saved = try await transport.save(merged, expectedRevision: remote.revision) }
            guard try WorkspaceMerge.equivalent(local, BackupCodec.decode(BackupService.export(store.projects))) else { throw WorkspaceSyncError.localChanged }
            // A protected, atomic safety copy precedes every local reconciliation, including explicit conflict resolution.
            try localData.write(to: directory.appendingPathComponent("before-last-sync.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            guard ArchiveReconciler.apply(merged, to: store) else { throw WorkspaceSyncError.configuration(store.errorMessage ?? "Local synchronization could not be saved.") }
            try BackupCodec.encode(merged).write(to: baseURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            status = "Synchronized revision \(saved.revision) · \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch { status = error.localizedDescription; store.errorMessage = error.localizedDescription }
    }
}
