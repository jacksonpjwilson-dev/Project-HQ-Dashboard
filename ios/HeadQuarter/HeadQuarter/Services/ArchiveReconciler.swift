import Foundation
import SwiftData
@MainActor enum ArchiveReconciler {
    static func apply(_ backup: WorkspaceBackup, to store: AppStore) -> Bool {
        do { try backup.validate() } catch { store.errorMessage = error.localizedDescription; return false }
        return store.commit {
            let existing = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0) })
            let ids = Set(backup.projects.map(\.id))
            for old in existing.values where !ids.contains(old.id) { store.context.delete(old) }
            for archive in backup.projects {
                let project = existing[archive.id] ?? Project(name: archive.name, summary: archive.summary)
                if existing[archive.id] == nil { store.context.insert(project) }
                project.id = archive.id; project.name = archive.name; project.summary = archive.summary
                project.icon = archive.icon; project.phase = archive.phase; project.priority = archive.priority
                project.order = archive.order; project.requireAllChecks = archive.requireAllChecks; project.createdAt = archive.createdAt
                let tasks = Dictionary(uniqueKeysWithValues: project.tasks.map { ($0.id, $0) })
                let taskIDs = Set(archive.tasks.map(\.id))
                project.tasks = archive.tasks.map { t in
                    let item = tasks[t.id] ?? WorkItem(title: t.title)
                    item.id = t.id; item.title = t.title; item.notes = t.notes; item.status = t.status
                    item.priority = t.priority; item.weight = t.weight; item.assignee = t.assignee; item.blocker = t.blocker
                    item.createdAt = t.createdAt; item.plannedAt = t.plannedAt; item.completedAt = t.completedAt
                    item.parentID = t.parentID; item.dependencyIDs = t.dependencyIDs; item.milestoneID = t.milestoneID; item.modifiedAt = t.modifiedAt; return item
                }
                for old in tasks.values where !taskIDs.contains(old.id) { store.context.delete(old) }
                let services = Dictionary(uniqueKeysWithValues: project.services.map { ($0.id, $0) })
                let serviceIDs = Set(archive.services.map(\.id))
                project.services = archive.services.map { s in
                    let item = services[s.id] ?? MonitoredService(name: s.name)
                    item.id = s.id; item.name = s.name; item.provider = s.provider; item.endpoint = s.endpoint
                    item.critical = s.critical; item.timeout = s.timeout; item.expiry = s.expiry; item.evidence = s.evidence
                    item.lastCheckedAt = s.lastCheckedAt; item.nextAllowedCheckAt = s.nextAllowedCheckAt
                    item.expectedHTTPStatus = s.expectedHTTPStatus; item.requiredBodyText = s.requiredBodyText
                    item.configurationRevision += 1; return item
                }
                for old in services.values where !serviceIDs.contains(old.id) { store.context.delete(old) }
                let milestones = Dictionary(uniqueKeysWithValues: project.milestones.map { ($0.id, $0) })
                let milestoneIDs = Set(archive.milestones.map(\.id))
                project.milestones = archive.milestones.map { m in let item = milestones[m.id] ?? Milestone(title: m.title); item.id = m.id; item.title = m.title; item.dueAt = m.dueAt; item.completedAt = m.completedAt; return item }
                for old in milestones.values where !milestoneIDs.contains(old.id) { store.context.delete(old) }
                let events = Dictionary(uniqueKeysWithValues: project.events.map { ($0.id, $0) })
                let eventIDs = Set(archive.events.map(\.id))
                project.events = archive.events.map { e in let item = events[e.id] ?? ActivityEvent(kind: e.kind, message: e.message, source: e.source); item.id = e.id; item.kindRaw = e.kind.rawValue; item.message = e.message; item.source = e.source; item.timestamp = e.timestamp; item.serviceID = e.serviceID; return item }
                for old in events.values where !eventIDs.contains(old.id) { store.context.delete(old) }
                let incidents = Dictionary(uniqueKeysWithValues: project.incidents.map { ($0.id, $0) })
                let incidentIDs = Set(archive.incidents.map(\.id))
                project.incidents = archive.incidents.map { i in let item = incidents[i.id] ?? Incident(serviceID: i.serviceID, title: i.title, health: i.health); item.id = i.id; item.serviceID = i.serviceID; item.title = i.title; item.healthRaw = i.health.rawValue; item.stateRaw = i.state.rawValue; item.openedAt = i.openedAt; item.updatedAt = i.updatedAt; item.resolvedAt = i.resolvedAt; item.lastNotifiedAt = i.lastNotifiedAt; return item }
                for old in incidents.values where !incidentIDs.contains(old.id) { store.context.delete(old) }
            }
        }
    }
}
